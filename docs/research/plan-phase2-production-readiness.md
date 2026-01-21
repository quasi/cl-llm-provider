# Phase 2: Production Readiness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add context window overflow detection, retry logic with exponential backoff, and batch API support - the three features essential for reliable production deployments.

**Architecture:**
- Context Management: Use token counting from Phase 1 + model metadata to detect overflow before API calls. Add `context-window-exceeded` condition with truncation restart. Implement truncation strategies.
- Retry Logic: Add retry policy system with exponential backoff + jitter. Classify errors as retriable/non-retriable. Add `:num-retries` and `:retry-policy` parameters to `complete`.
- Batch API: Add async batch job creation, status polling, and result retrieval for OpenAI and Anthropic. Use futures pattern for async operations.

**Tech Stack:** bordeaux-threads (delays, async), alexandria (utilities), existing conditions system

**Dependencies:** Requires Phase 1 (token counting) for context management. Retry and Batch can proceed independently.

---

## Task 1: Context Window Overflow Detection

### Task 1.1: Add Context Window Exceeded Condition

**Files:**
- Modify: `src/conditions.lisp`
- Test: `tests/test-context-management.lisp` (create)

**Step 1: Write the failing test**

Create `tests/test-context-management.lisp`:

```lisp
(defpackage :cl-llm-provider/test-context-management
  (:use :cl :cl-llm-provider :fiveam))

(in-package :cl-llm-provider/test-context-management)

(def-suite context-management-suite :description "Context window management tests")
(in-suite context-management-suite)

(test context-window-exceeded-condition
  "Test context-window-exceeded condition"
  (let ((condition (make-condition 'cl-llm-provider::context-window-exceeded
                                   :tokens 150000
                                   :max-tokens 128000
                                   :model "gpt-4")))
    (is (= 150000 (cl-llm-provider::context-window-exceeded-tokens condition)))
    (is (= 128000 (cl-llm-provider::context-window-exceeded-max-tokens condition)))
    (is (string= "gpt-4" (cl-llm-provider::context-window-exceeded-model condition)))))

(test context-window-exceeded-report
  "Test context-window-exceeded has readable report"
  (let* ((condition (make-condition 'cl-llm-provider::context-window-exceeded
                                    :tokens 150000
                                    :max-tokens 128000
                                    :model "gpt-4"))
         (report (format nil "~A" condition)))
    (is (search "150000" report))
    (is (search "128000" report))))
```

**Step 2: Run test to verify it fails**

Run: `sbcl --noinform --non-interactive --eval '(ql:quickload :fiveam)' --eval '(ql:quickload :cl-llm-provider)' --load tests/test-context-management.lisp --eval "(fiveam:run! 'cl-llm-provider/test-context-management::context-management-suite)"`

Expected: FAIL with "no class named CONTEXT-WINDOW-EXCEEDED"

**Step 3: Write minimal implementation**

Add to `src/conditions.lisp` after `provider-authentication-error`:

```lisp
(define-condition context-window-exceeded (llm-provider-error)
  ((tokens :initarg :tokens
           :reader context-window-exceeded-tokens
           :documentation "Number of tokens in the request.")
   (max-tokens :initarg :max-tokens
               :reader context-window-exceeded-max-tokens
               :documentation "Maximum tokens allowed by the model.")
   (model :initarg :model
          :initform nil
          :reader context-window-exceeded-model
          :documentation "Model that was exceeded."))
  (:documentation "Signaled when input exceeds model's context window.")
  (:report (lambda (c s)
             (format s "~&━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%")
             (format s "Context Window Exceeded~%")
             (format s "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%")
             (format s "Input tokens: ~:D~%" (context-window-exceeded-tokens c))
             (format s "Maximum allowed: ~:D~%" (context-window-exceeded-max-tokens c))
             (format s "Overflow: ~:D tokens~%"
                     (- (context-window-exceeded-tokens c)
                        (context-window-exceeded-max-tokens c)))
             (when (context-window-exceeded-model c)
               (format s "Model: ~A~%" (context-window-exceeded-model c)))
             (format s "~%Available restarts:~%")
             (format s "  • TRUNCATE-AND-RETRY - Truncate messages and retry~%")
             (format s "  • USE-DIFFERENT-MODEL - Switch to model with larger context~%")
             (format s "  • CONTINUE - Proceed anyway (may fail at API)~%")
             (format s "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%"))))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/conditions.lisp tests/test-context-management.lisp
git commit -m "feat(context): add context-window-exceeded condition"
```

---

### Task 1.2: Add Context Window Check Function

**Files:**
- Create: `src/context.lisp`
- Modify: `cl-llm-provider.asd`
- Test: `tests/test-context-management.lisp`

**Step 1: Write the failing test**

Add to `tests/test-context-management.lisp`:

```lisp
(test check-context-window-basic
  "Test context window checking"
  (let ((provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "test")))
    ;; Small message should pass
    (is (cl-llm-provider:check-context-window
         '((:role "user" :content "Hello"))
         :provider provider
         :model "gpt-4o"))

    ;; Very long message should fail (signal condition)
    (let ((long-content (make-string 1000000 :initial-element #\x)))
      (signals cl-llm-provider::context-window-exceeded
        (cl-llm-provider:check-context-window
         (list (list :role "user" :content long-content))
         :provider provider
         :model "gpt-4o")))))

(test get-model-context-window
  "Test getting model context window size"
  (let ((provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "test")))
    (let ((window (cl-llm-provider:get-context-window provider "gpt-4o")))
      (is (numberp window))
      (is (= 128000 window)))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "CHECK-CONTEXT-WINDOW is undefined"

**Step 3: Write minimal implementation**

Create `src/context.lisp`:

```lisp
(in-package :cl-llm-provider)

;;;; Context Window Management
;;;;
;;;; Provides context window overflow detection and truncation strategies.

(defun get-context-window (provider model)
  "Get context window size for MODEL on PROVIDER.

Returns the maximum input tokens, or nil if unknown.

Example:
  (get-context-window *openai* \"gpt-4o\") => 128000"
  (let ((metadata (model-metadata provider model)))
    (getf metadata :context-window)))

(defun get-max-output-tokens (provider model)
  "Get maximum output tokens for MODEL on PROVIDER.

Returns the maximum output tokens, or nil if unknown."
  (let ((metadata (model-metadata provider model)))
    (getf metadata :max-output-tokens)))

(defun check-context-window (messages &key provider model system max-tokens
                                           (signal-error t))
  "Check if MESSAGES fit within MODEL's context window.

MESSAGES - List of message plists
PROVIDER - Provider instance
MODEL - Model identifier
SYSTEM - System prompt (counted separately)
MAX-TOKENS - Reserved tokens for output (default: model's max or 4096)
SIGNAL-ERROR - If T (default), signal context-window-exceeded on overflow

Returns T if messages fit, NIL if they don't (when signal-error is NIL).
Signals context-window-exceeded if messages exceed context window.

Example:
  (check-context-window messages :provider *openai* :model \"gpt-4\")
  => T  ; or signals condition"
  (let* ((context-window (get-context-window provider model))
         (model-max-output (get-max-output-tokens provider model))
         (reserved-output (or max-tokens model-max-output 4096))
         (available-input (when context-window
                           (- context-window reserved-output)))
         (input-tokens (count-tokens-with-system messages system
                                                  :model model
                                                  :provider provider)))

    ;; If we don't know the context window, assume it's ok
    (unless available-input
      (return-from check-context-window t))

    (if (<= input-tokens available-input)
        t
        (if signal-error
            (restart-case
                (error 'context-window-exceeded
                       :tokens input-tokens
                       :max-tokens available-input
                       :model model
                       :provider provider)
              (truncate-and-retry (strategy)
                :report "Truncate messages and retry"
                :interactive (lambda ()
                              (format t "Truncation strategy (:keep-recent, :keep-first, :smart): ")
                              (list (read)))
                (truncate-messages messages strategy
                                  :target-tokens available-input
                                  :system system))
              (use-different-model (new-model)
                :report "Use a different model with larger context"
                :interactive (lambda ()
                              (format t "Enter model name: ")
                              (list (read-line)))
                (values messages new-model))
              (continue ()
                :report "Proceed anyway (may fail at API)"
                (values messages nil)))
            nil))))

(defun context-fits-p (messages &key provider model system max-tokens)
  "Non-signaling version of check-context-window.

Returns T if messages fit, NIL otherwise.

Example:
  (if (context-fits-p messages :provider *openai* :model \"gpt-4\")
      (complete messages)
      (handle-overflow))"
  (check-context-window messages
                        :provider provider
                        :model model
                        :system system
                        :max-tokens max-tokens
                        :signal-error nil))
```

Add to `cl-llm-provider.asd`:

```lisp
(:file "context" :depends-on ("types" "tokenizer" "conditions"))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/context.lisp cl-llm-provider.asd tests/test-context-management.lisp
git commit -m "feat(context): add context window check and detection functions"
```

---

### Task 1.3: Implement Truncation Strategies

**Files:**
- Modify: `src/context.lisp`
- Test: `tests/test-context-management.lisp`

**Step 1: Write the failing test**

Add to `tests/test-context-management.lisp`:

```lisp
(test truncate-messages-keep-recent
  "Test truncation with :keep-recent strategy"
  (let ((messages (list (list :role "user" :content "First message")
                       (list :role "assistant" :content "First response")
                       (list :role "user" :content "Second message")
                       (list :role "assistant" :content "Second response")
                       (list :role "user" :content "Third message"))))
    (let ((truncated (cl-llm-provider:truncate-messages messages :keep-recent
                                                        :target-tokens 50)))
      ;; Should keep the most recent messages
      (is (< (length truncated) (length messages)))
      ;; Last message should be preserved
      (is (string= "Third message"
                   (getf (car (last truncated)) :content))))))

(test truncate-messages-keep-first
  "Test truncation with :keep-first strategy"
  (let ((messages (list (list :role "user" :content "First message")
                       (list :role "assistant" :content "First response")
                       (list :role "user" :content "Second message")
                       (list :role "assistant" :content "Second response")
                       (list :role "user" :content "Third message"))))
    (let ((truncated (cl-llm-provider:truncate-messages messages :keep-first
                                                        :target-tokens 50)))
      ;; Should keep the first messages
      (is (< (length truncated) (length messages)))
      ;; First message should be preserved
      (is (string= "First message"
                   (getf (car truncated) :content))))))

(test truncate-messages-smart
  "Test truncation with :smart strategy"
  (let ((messages (list (list :role "system" :content "You are helpful")
                       (list :role "user" :content "First question")
                       (list :role "assistant" :content "First answer")
                       (list :role "user" :content "Second question")
                       (list :role "assistant" :content "Second answer")
                       (list :role "user" :content "Current question"))))
    (let ((truncated (cl-llm-provider:truncate-messages messages :smart
                                                        :target-tokens 50)))
      ;; Smart should keep system and most recent
      (is (< (length truncated) (length messages)))
      ;; Current question should be preserved
      (is (string= "Current question"
                   (getf (car (last truncated)) :content))))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "TRUNCATE-MESSAGES is undefined"

**Step 3: Write minimal implementation**

Add to `src/context.lisp`:

```lisp
;;;; Truncation Strategies

(defun truncate-messages (messages strategy &key target-tokens system)
  "Truncate MESSAGES to fit within TARGET-TOKENS using STRATEGY.

MESSAGES - List of message plists
STRATEGY - One of:
  :keep-recent - Drop oldest messages, keep most recent
  :keep-first - Drop newest messages, keep first
  :smart - Keep system message and most recent user/assistant pairs
TARGET-TOKENS - Maximum tokens for result
SYSTEM - System prompt (not included in messages, but counted)

Returns truncated list of messages.

Example:
  (truncate-messages messages :keep-recent :target-tokens 4000)"
  (ecase strategy
    (:keep-recent (truncate-keep-recent messages target-tokens system))
    (:keep-first (truncate-keep-first messages target-tokens system))
    (:smart (truncate-smart messages target-tokens system))))

(defun truncate-keep-recent (messages target-tokens system)
  "Truncate by dropping oldest messages first."
  (let ((result nil)
        (current-tokens (if system (estimate-tokens-from-text system) 0)))
    ;; Process from most recent to oldest
    (loop for message in (reverse messages)
          for msg-tokens = (count-message-tokens message)
          while (<= (+ current-tokens msg-tokens) target-tokens)
          do (push message result)
             (incf current-tokens msg-tokens))
    result))

(defun truncate-keep-first (messages target-tokens system)
  "Truncate by dropping newest messages first."
  (let ((result nil)
        (current-tokens (if system (estimate-tokens-from-text system) 0)))
    ;; Process from oldest to newest
    (loop for message in messages
          for msg-tokens = (count-message-tokens message)
          while (<= (+ current-tokens msg-tokens) target-tokens)
          do (push message result)
             (incf current-tokens msg-tokens))
    (nreverse result)))

(defun truncate-smart (messages target-tokens system)
  "Smart truncation: keep system, first exchange, and most recent exchanges."
  (let* ((system-tokens (if system (estimate-tokens-from-text system) 0))
         (available (- target-tokens system-tokens))
         (first-user nil)
         (first-assistant nil)
         (rest-messages nil))

    ;; Separate first exchange from rest
    (loop for (msg . remaining) on messages
          for role = (getf msg :role)
          do (cond
               ((and (null first-user) (string= role "user"))
                (setf first-user msg))
               ((and first-user (null first-assistant) (string= role "assistant"))
                (setf first-assistant msg))
               (t
                (push msg rest-messages))))
    (setf rest-messages (nreverse rest-messages))

    ;; Calculate tokens for first exchange
    (let* ((first-tokens (+ (if first-user (count-message-tokens first-user) 0)
                           (if first-assistant (count-message-tokens first-assistant) 0)))
           (remaining-budget (- available first-tokens)))

      ;; Fill remaining budget with most recent messages
      (let ((recent (truncate-keep-recent rest-messages remaining-budget nil)))
        ;; Combine: first exchange + recent messages
        (append (remove nil (list first-user first-assistant))
                recent)))))

;;; Auto-truncation wrapper

(defun with-auto-truncation (messages &key provider model system max-tokens
                                           (strategy :keep-recent))
  "Automatically truncate MESSAGES if they exceed context window.

Returns (values truncated-messages was-truncated).

Example:
  (multiple-value-bind (msgs truncated-p)
      (with-auto-truncation messages :provider *openai* :model \"gpt-4\")
    (when truncated-p
      (warn \"Messages were truncated\"))
    (complete msgs))"
  (if (context-fits-p messages :provider provider :model model
                               :system system :max-tokens max-tokens)
      (values messages nil)
      (let* ((context-window (get-context-window provider model))
             (model-max-output (get-max-output-tokens provider model))
             (reserved-output (or max-tokens model-max-output 4096))
             (available-input (- context-window reserved-output)))
        (values (truncate-messages messages strategy
                                  :target-tokens available-input
                                  :system system)
                t))))
```

Add exports to `src/package.lisp`:

```lisp
;; Context management
#:get-context-window
#:get-max-output-tokens
#:check-context-window
#:context-fits-p
#:truncate-messages
#:with-auto-truncation
#:context-window-exceeded
#:context-window-exceeded-tokens
#:context-window-exceeded-max-tokens
#:context-window-exceeded-model
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/context.lisp src/package.lisp tests/test-context-management.lisp
git commit -m "feat(context): implement truncation strategies (keep-recent, keep-first, smart)"
```

---

### Task 1.4: Integrate Context Check into complete Function

**Files:**
- Modify: `src/api.lisp`
- Test: `tests/test-context-management.lisp`

**Step 1: Write the failing test**

Add to `tests/test-context-management.lisp`:

```lisp
(test complete-with-context-check
  "Test that complete checks context window"
  ;; This is a design test - verify the parameter exists
  (is (member :check-context
              (alexandria:function-arglist #'cl-llm-provider:complete)
              :test #'string-equal
              :key (lambda (x) (if (symbolp x) (symbol-name x) "")))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL (parameter doesn't exist yet)

**Step 3: Write minimal implementation**

Modify `complete` in `src/api.lisp` to add context checking:

```lisp
(defun complete (messages &key provider model max-tokens temperature
                              system tools tool-choice stop
                              hooks on-request on-response on-error
                              ;; NEW: Context management
                              check-context auto-truncate truncation-strategy)
  "Send a completion request to an LLM provider.

MESSAGES - List of message plists ((:role \"user\" :content \"Hello\"))
PROVIDER - Provider instance (uses *default-provider* if nil)
MODEL - Model identifier (uses provider/global default if nil)
MAX-TOKENS - Maximum tokens in response (integer)
TEMPERATURE - Sampling temperature (0.0-2.0)
SYSTEM - System prompt (string)
TOOLS - List of tool definitions
TOOL-CHOICE - Tool selection strategy (keyword, string, or nil)
STOP - Stop sequences (string or list)

OBSERVABILITY:
HOOKS - hooks structure from make-hooks
ON-REQUEST - Callback (lambda (request-plist) ...) before request
ON-RESPONSE - Callback (lambda (response timing) ...) after response
ON-ERROR - Callback (lambda (error) ...) on error

CONTEXT MANAGEMENT:
CHECK-CONTEXT - If T, check context window before request (signals on overflow)
AUTO-TRUNCATE - If T, automatically truncate if context exceeded
TRUNCATION-STRATEGY - :keep-recent (default), :keep-first, or :smart

Returns a completion-response object."
  (let* ((provider (or provider *default-provider*))
         (effective-model (or model
                             (provider-default-model provider)
                             *default-model*))
         (all-hooks (or hooks *global-hooks*))
         (start-time (get-internal-real-time))
         (actual-messages messages))

    ;; Context window management
    (when (or check-context auto-truncate)
      (if auto-truncate
          ;; Auto-truncate mode
          (multiple-value-bind (truncated was-truncated)
              (with-auto-truncation messages
                                    :provider provider
                                    :model effective-model
                                    :system system
                                    :max-tokens max-tokens
                                    :strategy (or truncation-strategy :keep-recent))
            (when was-truncated
              (warn "Messages truncated to fit context window"))
            (setf actual-messages truncated))
          ;; Just check mode (signal on overflow)
          (check-context-window messages
                               :provider provider
                               :model effective-model
                               :system system
                               :max-tokens max-tokens)))

    ;; Build request info for hooks
    (let ((request-info (list :provider (provider-type provider)
                             :model effective-model
                             :message-count (length actual-messages)
                             :has-tools (not (null tools)))))

      ;; Invoke before-request hooks
      (when all-hooks
        (invoke-hooks all-hooks :before-request provider effective-model actual-messages))
      (when on-request
        (funcall on-request request-info))

      (handler-case
          (let* ((*performance-stats* (when *performance-profiling*
                                       (make-performance-stats)))
                 (raw-response (send-completion-request provider actual-messages
                                                        :model effective-model
                                                        :max-tokens max-tokens
                                                        :temperature temperature
                                                        :system system
                                                        :tools tools
                                                        :tool-choice tool-choice
                                                        :stop stop))
                 (response (with-performance-timing (:decode-time)
                            (parse-completion-response provider raw-response
                                                       :performance (get-performance-stats))))
                 (timing (/ (- (get-internal-real-time) start-time)
                           internal-time-units-per-second)))

            ;; Invoke after-response hooks
            (when all-hooks
              (invoke-hooks all-hooks :after-response provider effective-model response timing))
            (when on-response
              (funcall on-response response timing))

            response)

        (error (e)
          ;; Invoke error hooks
          (when all-hooks
            (invoke-hooks all-hooks :on-error provider effective-model e))
          (when on-error
            (funcall on-error e))
          (error e))))))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/api.lisp tests/test-context-management.lisp
git commit -m "feat(context): integrate context window check into complete function"
```

---

## Task 2: Retry Logic with Exponential Backoff

### Task 2.1: Define Retry Policy Structure

**Files:**
- Create: `src/retry.lisp`
- Modify: `cl-llm-provider.asd`
- Test: `tests/test-retry.lisp` (create)

**Step 1: Write the failing test**

Create `tests/test-retry.lisp`:

```lisp
(defpackage :cl-llm-provider/test-retry
  (:use :cl :cl-llm-provider :fiveam))

(in-package :cl-llm-provider/test-retry)

(def-suite retry-suite :description "Retry logic tests")
(in-suite retry-suite)

(test retry-policy-creation
  "Test retry policy creation"
  (let ((policy (cl-llm-provider:make-retry-policy
                 :max-retries 3
                 :initial-delay 1.0
                 :max-delay 60.0
                 :exponential-base 2.0
                 :jitter t)))
    (is (= 3 (cl-llm-provider::retry-policy-max-retries policy)))
    (is (= 1.0 (cl-llm-provider::retry-policy-initial-delay policy)))
    (is (= 60.0 (cl-llm-provider::retry-policy-max-delay policy)))))

(test default-retry-policy
  "Test default retry policy"
  (let ((policy (cl-llm-provider:default-retry-policy)))
    (is (not (null policy)))
    (is (cl-llm-provider::retry-policy-p policy))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "MAKE-RETRY-POLICY is undefined"

**Step 3: Write minimal implementation**

Create `src/retry.lisp`:

```lisp
(in-package :cl-llm-provider)

;;;; Retry Logic
;;;;
;;;; Provides retry with exponential backoff for transient failures.

(defstruct retry-policy
  "Configuration for retry behavior.

MAX-RETRIES - Maximum number of retry attempts
INITIAL-DELAY - Initial delay in seconds before first retry
MAX-DELAY - Maximum delay between retries
EXPONENTIAL-BASE - Base for exponential backoff (default 2.0)
JITTER - If T, add random jitter to prevent thundering herd
RETRIABLE-ERRORS - List of error types to retry on"
  (max-retries 3 :type integer)
  (initial-delay 1.0 :type float)
  (max-delay 60.0 :type float)
  (exponential-base 2.0 :type float)
  (jitter t :type boolean)
  (retriable-errors '(provider-rate-limit-error
                     provider-api-error)
                   :type list))

(defvar *default-retry-policy* nil
  "Default retry policy used when :retry is T but no policy specified.
Set with (setf *default-retry-policy* (make-retry-policy ...)).")

(defun default-retry-policy ()
  "Return the default retry policy.
Creates one if *default-retry-policy* is not set."
  (or *default-retry-policy*
      (make-retry-policy
       :max-retries 3
       :initial-delay 1.0
       :max-delay 60.0
       :exponential-base 2.0
       :jitter t
       :retriable-errors '(provider-rate-limit-error))))

(defun calculate-backoff-delay (policy attempt)
  "Calculate delay for ATTEMPT using POLICY.

POLICY - retry-policy structure
ATTEMPT - Current attempt number (0-based)

Returns delay in seconds (float)."
  (let* ((base-delay (* (retry-policy-initial-delay policy)
                       (expt (retry-policy-exponential-base policy) attempt)))
         (capped-delay (min base-delay (retry-policy-max-delay policy)))
         (jitter (if (retry-policy-jitter policy)
                    (* capped-delay (random 0.5))
                    0.0)))
    (+ capped-delay jitter)))

(defun retriable-error-p (error policy)
  "Check if ERROR should be retried according to POLICY.

ERROR - The condition that was signaled
POLICY - retry-policy structure

Returns T if error is retriable."
  (let ((retriable-types (retry-policy-retriable-errors policy)))
    (some (lambda (error-type)
            (typep error error-type))
          retriable-types)))

(defun non-retriable-error-p (error)
  "Check if ERROR should never be retried.

Returns T for authentication errors, invalid requests, etc."
  (or (typep error 'provider-authentication-error)
      (typep error 'context-window-exceeded)
      (typep error 'tool-validation-error)
      (typep error 'tool-schema-error)))
```

Add to `cl-llm-provider.asd`:

```lisp
(:file "retry" :depends-on ("types" "conditions"))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/retry.lisp cl-llm-provider.asd tests/test-retry.lisp
git commit -m "feat(retry): add retry policy structure and backoff calculation"
```

---

### Task 2.2: Implement with-retry Macro

**Files:**
- Modify: `src/retry.lisp`
- Test: `tests/test-retry.lisp`

**Step 1: Write the failing test**

Add to `tests/test-retry.lisp`:

```lisp
(test with-retry-success
  "Test with-retry on successful operation"
  (let ((call-count 0))
    (let ((result (cl-llm-provider::with-retry ((cl-llm-provider:default-retry-policy))
                    (incf call-count)
                    42)))
      (is (= 1 call-count))
      (is (= 42 result)))))

(test with-retry-eventual-success
  "Test with-retry retries on transient error"
  (let ((call-count 0))
    (let ((result (cl-llm-provider::with-retry ((cl-llm-provider:default-retry-policy))
                    (incf call-count)
                    (when (< call-count 3)
                      (error 'cl-llm-provider::provider-rate-limit-error
                             :message "Rate limited"))
                    "success")))
      (is (= 3 call-count))
      (is (string= "success" result)))))

(test with-retry-max-retries-exceeded
  "Test with-retry gives up after max retries"
  (let ((call-count 0)
        (policy (cl-llm-provider:make-retry-policy :max-retries 2)))
    (signals cl-llm-provider::provider-rate-limit-error
      (cl-llm-provider::with-retry (policy)
        (incf call-count)
        (error 'cl-llm-provider::provider-rate-limit-error
               :message "Always rate limited")))
    ;; Should have tried 3 times (initial + 2 retries)
    (is (= 3 call-count))))

(test with-retry-non-retriable-error
  "Test with-retry doesn't retry non-retriable errors"
  (let ((call-count 0))
    (signals cl-llm-provider::provider-authentication-error
      (cl-llm-provider::with-retry ((cl-llm-provider:default-retry-policy))
        (incf call-count)
        (error 'cl-llm-provider::provider-authentication-error
               :message "Bad key")))
    ;; Should have only tried once
    (is (= 1 call-count))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "WITH-RETRY is undefined"

**Step 3: Write minimal implementation**

Add to `src/retry.lisp`:

```lisp
;;;; Retry Execution

(defmacro with-retry ((policy &key on-retry) &body body)
  "Execute BODY with retry logic according to POLICY.

POLICY - retry-policy structure (evaluated once)
ON-RETRY - Optional callback (lambda (attempt delay error) ...) called before each retry

Returns the result of BODY on success.
Signals the last error after max retries exhausted.

Example:
  (with-retry ((make-retry-policy :max-retries 3))
    (call-flaky-api))"
  (let ((policy-var (gensym "POLICY-"))
        (attempt (gensym "ATTEMPT-"))
        (last-error (gensym "LAST-ERROR-"))
        (result (gensym "RESULT-"))
        (success (gensym "SUCCESS-")))
    `(let* ((,policy-var ,policy)
            (,attempt 0)
            (,last-error nil)
            (,result nil)
            (,success nil))
       (loop
         (handler-case
             (progn
               (setf ,result (progn ,@body))
               (setf ,success t)
               (return ,result))
           (error (e)
             (setf ,last-error e)
             (cond
               ;; Non-retriable error - rethrow immediately
               ((non-retriable-error-p e)
                (error e))
               ;; Not a retriable error type for this policy
               ((not (retriable-error-p e ,policy-var))
                (error e))
               ;; Max retries exceeded
               ((>= ,attempt (retry-policy-max-retries ,policy-var))
                (error e))
               ;; Retry
               (t
                (let ((delay (calculate-backoff-delay ,policy-var ,attempt)))
                  ,@(when on-retry
                      `((funcall ,on-retry ,attempt delay e)))
                  (sleep delay)
                  (incf ,attempt))))))))))

(defun call-with-retry (thunk &key policy on-retry)
  "Functional version of with-retry.

THUNK - Zero-argument function to call
POLICY - retry-policy (default: default-retry-policy)
ON-RETRY - Optional callback

Returns result of THUNK on success.

Example:
  (call-with-retry
    (lambda () (complete messages :provider *openai*))
    :policy (make-retry-policy :max-retries 5))"
  (let ((effective-policy (or policy (default-retry-policy))))
    (with-retry (effective-policy :on-retry on-retry)
      (funcall thunk))))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/retry.lisp tests/test-retry.lisp
git commit -m "feat(retry): implement with-retry macro with exponential backoff"
```

---

### Task 2.3: Integrate Retry into complete Function

**Files:**
- Modify: `src/api.lisp`
- Modify: `src/package.lisp`
- Test: `tests/test-retry.lisp`

**Step 1: Write the failing test**

Add to `tests/test-retry.lisp`:

```lisp
(test complete-with-retry-parameters
  "Test that complete accepts retry parameters"
  ;; Verify parameters exist in function signature
  (let ((arglist (alexandria:function-arglist #'cl-llm-provider:complete)))
    (is (member :num-retries arglist
                :test #'string-equal
                :key (lambda (x) (if (symbolp x) (symbol-name x) ""))))
    (is (member :retry-policy arglist
                :test #'string-equal
                :key (lambda (x) (if (symbolp x) (symbol-name x) ""))))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL

**Step 3: Write minimal implementation**

Update `complete` in `src/api.lisp` to add retry support:

```lisp
(defun complete (messages &key provider model max-tokens temperature
                              system tools tool-choice stop
                              hooks on-request on-response on-error
                              check-context auto-truncate truncation-strategy
                              ;; NEW: Retry parameters
                              num-retries retry-policy on-retry)
  "Send a completion request to an LLM provider.

...existing docstring...

RETRY:
NUM-RETRIES - Number of retries on transient failure (creates simple policy)
RETRY-POLICY - Full retry-policy structure (overrides num-retries)
ON-RETRY - Callback (lambda (attempt delay error) ...) before each retry

Returns a completion-response object."
  (let* ((provider (or provider *default-provider*))
         (effective-model (or model
                             (provider-default-model provider)
                             *default-model*))
         (effective-retry-policy (cond
                                  (retry-policy retry-policy)
                                  (num-retries (make-retry-policy :max-retries num-retries))
                                  (t nil))))

    ;; The actual completion logic
    (flet ((do-complete ()
             (let ((all-hooks (or hooks *global-hooks*))
                   (start-time (get-internal-real-time))
                   (actual-messages messages))

               ;; Context window management
               (when (or check-context auto-truncate)
                 (if auto-truncate
                     (multiple-value-bind (truncated was-truncated)
                         (with-auto-truncation messages
                                               :provider provider
                                               :model effective-model
                                               :system system
                                               :max-tokens max-tokens
                                               :strategy (or truncation-strategy :keep-recent))
                       (when was-truncated
                         (warn "Messages truncated to fit context window"))
                       (setf actual-messages truncated))
                     (check-context-window messages
                                          :provider provider
                                          :model effective-model
                                          :system system
                                          :max-tokens max-tokens)))

               (let ((request-info (list :provider (provider-type provider)
                                        :model effective-model
                                        :message-count (length actual-messages)
                                        :has-tools (not (null tools)))))

                 ;; Invoke before-request hooks
                 (when all-hooks
                   (invoke-hooks all-hooks :before-request provider effective-model actual-messages))
                 (when on-request
                   (funcall on-request request-info))

                 (handler-case
                     (let* ((*performance-stats* (when *performance-profiling*
                                                  (make-performance-stats)))
                            (raw-response (send-completion-request provider actual-messages
                                                                   :model effective-model
                                                                   :max-tokens max-tokens
                                                                   :temperature temperature
                                                                   :system system
                                                                   :tools tools
                                                                   :tool-choice tool-choice
                                                                   :stop stop))
                            (response (with-performance-timing (:decode-time)
                                       (parse-completion-response provider raw-response
                                                                  :performance (get-performance-stats))))
                            (timing (/ (- (get-internal-real-time) start-time)
                                      internal-time-units-per-second)))

                       ;; Invoke after-response hooks
                       (when all-hooks
                         (invoke-hooks all-hooks :after-response provider effective-model response timing))
                       (when on-response
                         (funcall on-response response timing))

                       response)

                   (error (e)
                     ;; Invoke error hooks
                     (when all-hooks
                       (invoke-hooks all-hooks :on-error provider effective-model e))
                     (when on-error
                       (funcall on-error e))
                     (error e)))))))

      ;; Execute with or without retry
      (if effective-retry-policy
          (call-with-retry #'do-complete
                          :policy effective-retry-policy
                          :on-retry on-retry)
          (do-complete)))))
```

Add exports to `src/package.lisp`:

```lisp
;; Retry
#:make-retry-policy
#:retry-policy-max-retries
#:retry-policy-initial-delay
#:retry-policy-max-delay
#:default-retry-policy
#:*default-retry-policy*
#:call-with-retry
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/api.lisp src/retry.lisp src/package.lisp tests/test-retry.lisp
git commit -m "feat(retry): integrate retry logic into complete function"
```

---

## Task 3: Batch API Support

### Task 3.1: Define Batch Types

**Files:**
- Create: `src/batch.lisp`
- Modify: `cl-llm-provider.asd`
- Test: `tests/test-batch.lisp` (create)

**Step 1: Write the failing test**

Create `tests/test-batch.lisp`:

```lisp
(defpackage :cl-llm-provider/test-batch
  (:use :cl :cl-llm-provider :fiveam))

(in-package :cl-llm-provider/test-batch)

(def-suite batch-suite :description "Batch API tests")
(in-suite batch-suite)

(test batch-request-creation
  "Test batch request creation"
  (let ((request (cl-llm-provider:make-batch-request
                  :model "gpt-4"
                  :messages '((:role "user" :content "Hello"))
                  :custom-id "req-001")))
    (is (string= "gpt-4" (cl-llm-provider::batch-request-model request)))
    (is (string= "req-001" (cl-llm-provider::batch-request-custom-id request)))))

(test batch-job-creation
  "Test batch job creation"
  (let ((job (make-instance 'cl-llm-provider::batch-job
                            :id "batch-123"
                            :status :validating
                            :created-at (get-universal-time))))
    (is (string= "batch-123" (cl-llm-provider::batch-job-id job)))
    (is (eq :validating (cl-llm-provider::batch-job-status job)))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "MAKE-BATCH-REQUEST is undefined"

**Step 3: Write minimal implementation**

Create `src/batch.lisp`:

```lisp
(in-package :cl-llm-provider)

;;;; Batch API Support
;;;;
;;;; Provides async batch processing for high-volume, non-time-sensitive workloads.
;;;; OpenAI offers 50% discount for batch API usage.

;;;; Batch Request Structure

(defstruct batch-request
  "A single request within a batch job.

MODEL - Model to use for this request
MESSAGES - List of message plists
CUSTOM-ID - Unique identifier for correlating results
MAX-TOKENS - Maximum output tokens
TEMPERATURE - Sampling temperature
SYSTEM - System prompt
TOOLS - Tool definitions"
  (model nil :type (or null string))
  (messages nil :type list)
  (custom-id nil :type (or null string))
  (max-tokens nil :type (or null integer))
  (temperature nil :type (or null number))
  (system nil :type (or null string))
  (tools nil :type list))

;;;; Batch Job Class

(defclass batch-job ()
  ((id :initarg :id
       :reader batch-job-id
       :documentation "Batch job identifier from provider.")
   (provider :initarg :provider
             :reader batch-job-provider
             :documentation "Provider instance.")
   (status :initarg :status
           :accessor batch-job-status
           :documentation "Job status: :validating, :in-progress, :completed, :failed, :expired, :cancelled")
   (created-at :initarg :created-at
               :reader batch-job-created-at
               :documentation "Creation timestamp (universal time).")
   (completed-at :initarg :completed-at
                 :initform nil
                 :accessor batch-job-completed-at
                 :documentation "Completion timestamp (universal time).")
   (request-counts :initarg :request-counts
                   :initform nil
                   :accessor batch-job-request-counts
                   :documentation "Plist with :total, :completed, :failed counts.")
   (input-file-id :initarg :input-file-id
                  :initform nil
                  :reader batch-job-input-file-id
                  :documentation "Uploaded input file ID.")
   (output-file-id :initarg :output-file-id
                   :initform nil
                   :accessor batch-job-output-file-id
                   :documentation "Output file ID when complete.")
   (error-file-id :initarg :error-file-id
                  :initform nil
                  :accessor batch-job-error-file-id
                  :documentation "Error file ID if any failures.")
   (metadata :initarg :metadata
             :initform nil
             :accessor batch-job-metadata
             :documentation "Custom metadata plist."))
  (:documentation "Represents an async batch processing job."))

(defmethod print-object ((job batch-job) stream)
  (print-unreadable-object (job stream :type t)
    (format stream "~A ~A"
            (batch-job-id job)
            (batch-job-status job))))

;;;; Batch Result Structure

(defstruct batch-result
  "Result for a single request in a batch.

CUSTOM-ID - Correlates to batch-request custom-id
STATUS - :success or :error
RESPONSE - completion-response object on success
ERROR - Error message/details on failure"
  (custom-id nil :type (or null string))
  (status nil :type keyword)
  (response nil)
  (error nil))

;;;; Batch Job Predicates

(defun batch-job-complete-p (job)
  "Return T if JOB has completed (successfully or with errors)."
  (member (batch-job-status job) '(:completed :failed :expired :cancelled)))

(defun batch-job-in-progress-p (job)
  "Return T if JOB is still processing."
  (member (batch-job-status job) '(:validating :in-progress)))

(defun batch-job-success-p (job)
  "Return T if JOB completed successfully."
  (eq (batch-job-status job) :completed))
```

Add to `cl-llm-provider.asd`:

```lisp
(:file "batch" :depends-on ("types" "protocol"))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/batch.lisp cl-llm-provider.asd tests/test-batch.lisp
git commit -m "feat(batch): add batch request, job, and result types"
```

---

### Task 3.2: Add Batch Protocol Generic Functions

**Files:**
- Modify: `src/batch.lisp`
- Test: `tests/test-batch.lisp`

**Step 1: Write the failing test**

Add to `tests/test-batch.lisp`:

```lisp
(test batch-protocol-functions-exist
  "Test batch protocol generic functions exist"
  (is (fboundp 'cl-llm-provider::create-batch-job))
  (is (fboundp 'cl-llm-provider::get-batch-status))
  (is (fboundp 'cl-llm-provider::get-batch-results))
  (is (fboundp 'cl-llm-provider::cancel-batch-job)))
```

**Step 2: Run test to verify it fails**

Expected: FAIL

**Step 3: Write minimal implementation**

Add to `src/batch.lisp`:

```lisp
;;;; Batch Protocol

(defgeneric create-batch-job (provider requests &key completion-window metadata)
  (:documentation "Create a batch job on PROVIDER.

PROVIDER - Provider instance
REQUESTS - List of batch-request structures
COMPLETION-WINDOW - Time window for completion (e.g., \"24h\")
METADATA - Custom metadata plist

Returns a batch-job object.
Signals provider-api-error on failure."))

(defgeneric get-batch-status (provider batch-id)
  (:documentation "Get current status of a batch job.

PROVIDER - Provider instance
BATCH-ID - Batch job ID (string)

Returns updated batch-job object."))

(defgeneric get-batch-results (provider batch-id)
  (:documentation "Retrieve results of a completed batch job.

PROVIDER - Provider instance
BATCH-ID - Batch job ID (string)

Returns list of batch-result structures.
Signals error if job not complete."))

(defgeneric cancel-batch-job (provider batch-id)
  (:documentation "Cancel a batch job.

PROVIDER - Provider instance
BATCH-ID - Batch job ID (string)

Returns T on success."))

(defgeneric provider-supports-batch-p (provider)
  (:documentation "Return T if PROVIDER supports batch API.")
  (:method ((provider llm-provider))
    "Default: batch not supported."
    nil))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/batch.lisp tests/test-batch.lisp
git commit -m "feat(batch): add batch protocol generic functions"
```

---

### Task 3.3: Implement OpenAI Batch API

**Files:**
- Modify: `src/providers/openai.lisp`
- Test: `tests/test-batch.lisp`

**Step 1: Write the failing test**

Add to `tests/test-batch.lisp`:

```lisp
(test openai-supports-batch
  "Test OpenAI provider supports batch API"
  (let ((provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "test")))
    (is (cl-llm-provider::provider-supports-batch-p provider))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL

**Step 3: Write minimal implementation**

Add to `src/providers/openai.lisp`:

```lisp
;;; Batch API Support

(defmethod provider-supports-batch-p ((provider openai-provider))
  t)

(defun format-batch-request-jsonl (request)
  "Format a batch-request as JSONL line for OpenAI batch API."
  (let ((body (make-hash-table :test 'equal)))
    (setf (gethash "custom_id" body) (or (batch-request-custom-id request)
                                         (format nil "req-~A" (random 1000000))))
    (setf (gethash "method" body) "POST")
    (setf (gethash "url" body) "/v1/chat/completions")

    (let ((req-body (make-hash-table :test 'equal)))
      (setf (gethash "model" req-body) (or (batch-request-model request) "gpt-4"))
      (setf (gethash "messages" req-body)
            (map 'vector #'plist-to-hash (batch-request-messages request)))
      (when (batch-request-max-tokens request)
        (setf (gethash "max_tokens" req-body) (batch-request-max-tokens request)))
      (when (batch-request-temperature request)
        (setf (gethash "temperature" req-body) (batch-request-temperature request)))
      (setf (gethash "body" body) req-body))

    (with-output-to-string (s)
      (yason:encode body s))))

(defmethod create-batch-job ((provider openai-provider) requests
                             &key (completion-window "24h") metadata)
  "Create batch job on OpenAI."
  (let* ((base-url (provider-base-url provider))
         (headers (make-http-headers provider)))

    ;; Step 1: Create JSONL content
    (let ((jsonl-content (with-output-to-string (s)
                          (dolist (req requests)
                            (write-line (format-batch-request-jsonl req) s)))))

      ;; Step 2: Upload file
      (let* ((file-url (format nil "~A/files" base-url))
             (boundary (format nil "----WebKitFormBoundary~A" (random 1000000)))
             (file-body (format nil "~
--~A~%~
Content-Disposition: form-data; name=\"purpose\"~%~%~
batch~%~
--~A~%~
Content-Disposition: form-data; name=\"file\"; filename=\"batch.jsonl\"~%~
Content-Type: application/json~%~%~
~A~%~
--~A--~%"
                               boundary boundary jsonl-content boundary)))

        (multiple-value-bind (response status-code)
            (dex:post file-url
                      :headers (append headers
                                      (list (cons "Content-Type"
                                                 (format nil "multipart/form-data; boundary=~A" boundary))))
                      :content file-body
                      :force-string t)
          (unless (and (>= status-code 200) (< status-code 300))
            (handle-http-error status-code (yason:parse response) provider))

          (let* ((file-response (yason:parse response))
                 (file-id (gethash "id" file-response)))

            ;; Step 3: Create batch
            (let* ((batch-url (format nil "~A/batches" base-url))
                   (batch-body (make-hash-table :test 'equal)))
              (setf (gethash "input_file_id" batch-body) file-id)
              (setf (gethash "endpoint" batch-body) "/v1/chat/completions")
              (setf (gethash "completion_window" batch-body) completion-window)
              (when metadata
                (setf (gethash "metadata" batch-body) (plist-to-hash metadata)))

              (multiple-value-bind (batch-response batch-status)
                  (dex:post batch-url
                            :headers headers
                            :content (with-output-to-string (s)
                                      (yason:encode batch-body s))
                            :force-string t)
                (unless (and (>= batch-status 200) (< batch-status 300))
                  (handle-http-error batch-status (yason:parse batch-response) provider))

                (let ((batch-data (yason:parse batch-response)))
                  (make-instance 'batch-job
                                 :id (gethash "id" batch-data)
                                 :provider provider
                                 :status (intern (string-upcase (gethash "status" batch-data)) :keyword)
                                 :created-at (get-universal-time)
                                 :input-file-id file-id
                                 :metadata metadata))))))))))

(defmethod get-batch-status ((provider openai-provider) batch-id)
  "Get batch job status from OpenAI."
  (let* ((url (format nil "~A/batches/~A" (provider-base-url provider) batch-id))
         (headers (make-http-headers provider)))
    (multiple-value-bind (response status-code)
        (dex:get url :headers headers :force-string t)
      (unless (and (>= status-code 200) (< status-code 300))
        (handle-http-error status-code (yason:parse response) provider))

      (let ((data (yason:parse response)))
        (make-instance 'batch-job
                       :id (gethash "id" data)
                       :provider provider
                       :status (intern (string-upcase (gethash "status" data)) :keyword)
                       :created-at (get-universal-time)
                       :completed-at (when (gethash "completed_at" data)
                                      (get-universal-time))
                       :request-counts (let ((counts (gethash "request_counts" data)))
                                        (when counts
                                          (list :total (gethash "total" counts)
                                                :completed (gethash "completed" counts)
                                                :failed (gethash "failed" counts))))
                       :output-file-id (gethash "output_file_id" data)
                       :error-file-id (gethash "error_file_id" data))))))

(defmethod get-batch-results ((provider openai-provider) batch-id)
  "Get results of completed batch job from OpenAI."
  (let ((job (get-batch-status provider batch-id)))
    (unless (batch-job-success-p job)
      (error 'provider-api-error
             :provider provider
             :message (format nil "Batch job ~A not complete (status: ~A)"
                             batch-id (batch-job-status job))))

    (let* ((output-file-id (batch-job-output-file-id job))
           (url (format nil "~A/files/~A/content" (provider-base-url provider) output-file-id))
           (headers (make-http-headers provider)))

      (multiple-value-bind (response status-code)
          (dex:get url :headers headers :force-string t)
        (unless (and (>= status-code 200) (< status-code 300))
          (handle-http-error status-code response provider))

        ;; Parse JSONL response
        (with-input-from-string (s response)
          (loop for line = (read-line s nil nil)
                while line
                when (> (length line) 0)
                collect (let* ((data (yason:parse line))
                              (custom-id (gethash "custom_id" data))
                              (response-data (gethash "response" data))
                              (error-data (gethash "error" data)))
                         (if error-data
                             (make-batch-result
                              :custom-id custom-id
                              :status :error
                              :error (gethash "message" error-data))
                             (make-batch-result
                              :custom-id custom-id
                              :status :success
                              :response (parse-completion-response
                                        provider
                                        (gethash "body" response-data)))))))))))

(defmethod cancel-batch-job ((provider openai-provider) batch-id)
  "Cancel batch job on OpenAI."
  (let* ((url (format nil "~A/batches/~A/cancel" (provider-base-url provider) batch-id))
         (headers (make-http-headers provider)))
    (multiple-value-bind (response status-code)
        (dex:post url :headers headers :force-string t)
      (declare (ignore response))
      (and (>= status-code 200) (< status-code 300)))))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/providers/openai.lisp tests/test-batch.lisp
git commit -m "feat(batch): implement OpenAI batch API support"
```

---

### Task 3.4: Add High-Level Batch API Functions

**Files:**
- Modify: `src/batch.lisp`
- Modify: `src/package.lisp`
- Test: `tests/test-batch.lisp`

**Step 1: Write the failing test**

Add to `tests/test-batch.lisp`:

```lisp
(test wait-for-batch-function-exists
  "Test wait-for-batch function exists"
  (is (fboundp 'cl-llm-provider:wait-for-batch)))

(test batch-complete-function-exists
  "Test batch-complete convenience function exists"
  (is (fboundp 'cl-llm-provider:batch-complete)))
```

**Step 2: Run test to verify it fails**

Expected: FAIL

**Step 3: Write minimal implementation**

Add to `src/batch.lisp`:

```lisp
;;;; High-Level Batch API

(defun wait-for-batch (job &key (poll-interval 10) (timeout 86400) on-progress)
  "Wait for BATCH-JOB to complete, polling status periodically.

JOB - batch-job object
POLL-INTERVAL - Seconds between status checks (default: 10)
TIMEOUT - Maximum seconds to wait (default: 86400 = 24 hours)
ON-PROGRESS - Optional callback (lambda (job) ...) on each poll

Returns updated batch-job when complete.
Signals error on timeout.

Example:
  (let ((job (create-batch-job provider requests)))
    (wait-for-batch job :on-progress (lambda (j)
                                       (format t \"Status: ~A~%\" (batch-job-status j)))))"
  (let ((provider (batch-job-provider job))
        (batch-id (batch-job-id job))
        (start-time (get-internal-real-time)))
    (loop
      (let ((current-job (get-batch-status provider batch-id)))
        (when on-progress
          (funcall on-progress current-job))

        (when (batch-job-complete-p current-job)
          (return current-job))

        (let ((elapsed (/ (- (get-internal-real-time) start-time)
                         internal-time-units-per-second)))
          (when (> elapsed timeout)
            (error 'provider-api-error
                   :provider provider
                   :message (format nil "Batch job ~A timed out after ~D seconds"
                                   batch-id timeout))))

        (sleep poll-interval)))))

(defun batch-complete (requests &key provider model completion-window metadata
                                     wait poll-interval timeout on-progress)
  "Convenience function to create and optionally wait for a batch job.

REQUESTS - List of (messages &key max-tokens temperature system) specs
PROVIDER - Provider instance
MODEL - Default model for all requests
COMPLETION-WINDOW - Time window (default: \"24h\")
METADATA - Custom metadata
WAIT - If T, wait for completion and return results
POLL-INTERVAL - Seconds between polls when waiting
TIMEOUT - Max wait time in seconds
ON-PROGRESS - Progress callback when waiting

Returns:
  If WAIT is NIL: batch-job object
  If WAIT is T: list of batch-result structures

Example:
  ;; Fire and forget
  (let ((job (batch-complete requests :provider *openai*)))
    (format t \"Batch ~A submitted~%\" (batch-job-id job)))

  ;; Wait for results
  (let ((results (batch-complete requests :provider *openai* :wait t)))
    (dolist (r results)
      (format t \"~A: ~A~%\" (batch-result-custom-id r)
              (if (eq (batch-result-status r) :success)
                  (response-content (batch-result-response r))
                  (batch-result-error r)))))"
  (let* ((provider (or provider *default-provider*))
         (effective-model (or model (provider-default-model provider)))
         ;; Convert simple request specs to batch-request structures
         (batch-requests
          (loop for req in requests
                for idx from 0
                collect (etypecase req
                          (batch-request req)
                          (list
                           ;; Assume (messages &key max-tokens temperature system)
                           (let ((messages (if (keywordp (first req))
                                              (list req)  ; Single message
                                              (first req))))
                             (make-batch-request
                              :model effective-model
                              :messages messages
                              :custom-id (format nil "req-~D" idx)
                              :max-tokens (getf (rest req) :max-tokens)
                              :temperature (getf (rest req) :temperature)
                              :system (getf (rest req) :system))))))))

    (let ((job (create-batch-job provider batch-requests
                                 :completion-window (or completion-window "24h")
                                 :metadata metadata)))
      (if wait
          (let ((completed-job (wait-for-batch job
                                              :poll-interval (or poll-interval 10)
                                              :timeout (or timeout 86400)
                                              :on-progress on-progress)))
            (get-batch-results provider (batch-job-id completed-job)))
          job))))
```

Add exports to `src/package.lisp`:

```lisp
;; Batch API
#:make-batch-request
#:batch-request-model
#:batch-request-messages
#:batch-request-custom-id
#:batch-job
#:batch-job-id
#:batch-job-status
#:batch-job-complete-p
#:batch-job-in-progress-p
#:batch-job-success-p
#:batch-result
#:batch-result-custom-id
#:batch-result-status
#:batch-result-response
#:batch-result-error
#:create-batch-job
#:get-batch-status
#:get-batch-results
#:cancel-batch-job
#:wait-for-batch
#:batch-complete
#:provider-supports-batch-p
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/batch.lisp src/package.lisp tests/test-batch.lisp
git commit -m "feat(batch): add high-level batch-complete and wait-for-batch functions"
```

---

## Final Task: Run Full Test Suite

**Step 1: Run all Phase 2 tests**

```bash
sbcl --noinform --non-interactive \
  --eval '(ql:quickload :fiveam)' \
  --eval '(ql:quickload :cl-llm-provider)' \
  --load tests/test-context-management.lisp \
  --load tests/test-retry.lisp \
  --load tests/test-batch.lisp \
  --eval '(fiveam:run-all-tests)'
```

**Step 2: Run existing test suite for regressions**

```bash
sbcl --noinform --non-interactive --load tests/test-tools-support.lisp
sbcl --noinform --non-interactive --load tests/test-provider-protocols.lisp
```

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete Phase 2 - context management, retry logic, batch API"
```

---

## Summary

**Phase 2 delivers:**
1. **Context Window Overflow Detection** - `check-context-window`, `context-fits-p`, truncation strategies
2. **Retry Logic** - `make-retry-policy`, exponential backoff with jitter, `:num-retries` parameter
3. **Batch API** - `create-batch-job`, `wait-for-batch`, `batch-complete` for 50% cost savings

**Files created/modified:**
- `src/context.lisp` - context window checking, truncation strategies
- `src/retry.lisp` - retry policy, exponential backoff
- `src/batch.lisp` - batch types, protocol, high-level functions
- `src/conditions.lisp` - context-window-exceeded condition
- `src/api.lisp` - integrated context checking and retry
- `src/providers/openai.lisp` - OpenAI batch implementation
- `src/package.lisp` - new exports

**Next:** Phase 3 - Prompt caching, parallel tools, intelligent routing
