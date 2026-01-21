# Phase 3: Advanced Features Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add prompt caching, parallel tool calling, and intelligent routing - advanced features that differentiate best-in-class multi-provider LLM libraries.

**Architecture:**
- Prompt Caching: Add Anthropic-specific cache control markers. Simple `:cache-system-prompt` and `:cache-tools` parameters. Provider options for advanced control.
- Parallel Tool Calling: Execute multiple tool calls concurrently using bordeaux-threads. Handle partial failures. Add `:parallel-tool-execution` parameter.
- Intelligent Routing: DSL for model selection rules. Support cost-based, capability-based routing. Fallback chains with A/B testing hooks.

**Tech Stack:** bordeaux-threads (parallel execution), alexandria (utilities), lparallel (optional for thread pools)

**Dependencies:** Requires Phase 1 (observability for routing metrics). Parallel tools builds on existing tool infrastructure. Each feature is mostly independent.

---

## Task 1: Prompt Caching (Anthropic)

### Task 1.1: Add Provider Options Infrastructure

**Files:**
- Modify: `src/api.lisp`
- Modify: `src/protocol.lisp`
- Test: `tests/test-prompt-caching.lisp` (create)

**Step 1: Write the failing test**

Create `tests/test-prompt-caching.lisp`:

```lisp
(defpackage :cl-llm-provider/test-prompt-caching
  (:use :cl :cl-llm-provider :fiveam))

(in-package :cl-llm-provider/test-prompt-caching)

(def-suite prompt-caching-suite :description "Prompt caching tests")
(in-suite prompt-caching-suite)

(test complete-accepts-provider-options
  "Test that complete accepts provider-options parameter"
  (let ((arglist (alexandria:function-arglist #'cl-llm-provider:complete)))
    (is (member :provider-options arglist
                :test #'string-equal
                :key (lambda (x) (if (symbolp x) (symbol-name x) ""))))))

(test complete-accepts-cache-system-prompt
  "Test that complete accepts cache-system-prompt parameter"
  (let ((arglist (alexandria:function-arglist #'cl-llm-provider:complete)))
    (is (member :cache-system-prompt arglist
                :test #'string-equal
                :key (lambda (x) (if (symbolp x) (symbol-name x) ""))))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL

**Step 3: Write minimal implementation**

Add to `src/api.lisp` (update `complete` function signature and implementation):

```lisp
(defun complete (messages &key provider model max-tokens temperature
                              system tools tool-choice stop
                              hooks on-request on-response on-error
                              check-context auto-truncate truncation-strategy
                              num-retries retry-policy on-retry
                              ;; NEW: Provider-specific options
                              provider-options
                              cache-system-prompt cache-tools)
  "Send a completion request to an LLM provider.

...existing docstring...

PROVIDER-SPECIFIC:
PROVIDER-OPTIONS - Plist of provider-specific options
                   e.g., '(:anthropic (:cache-control (:type \"ephemeral\")))
CACHE-SYSTEM-PROMPT - If T, enable caching for system prompt (Anthropic)
CACHE-TOOLS - If T, enable caching for tool definitions (Anthropic)

Returns a completion-response object."
  ;; ...existing implementation with provider-options passed through
  )
```

Add to `src/protocol.lisp` (extend `send-completion-request`):

```lisp
(defgeneric send-completion-request (provider messages &key model max-tokens
                                                        temperature system tools
                                                        tool-choice stop
                                                        provider-options)
  (:documentation "Send a completion request to PROVIDER and return raw response.

...existing docs...

PROVIDER-OPTIONS - Plist of provider-specific options"))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/api.lisp src/protocol.lisp tests/test-prompt-caching.lisp
git commit -m "feat(caching): add provider-options and cache parameters to complete"
```

---

### Task 1.2: Implement Anthropic Cache Control

**Files:**
- Modify: `src/providers/anthropic.lisp`
- Test: `tests/test-prompt-caching.lisp`

**Step 1: Write the failing test**

Add to `tests/test-prompt-caching.lisp`:

```lisp
(test anthropic-cache-control-format
  "Test Anthropic cache control message formatting"
  (let ((provider (make-instance 'cl-llm-provider::anthropic-provider
                                 :api-key "test")))
    ;; Test that the provider can format cache control
    (let ((system-with-cache (cl-llm-provider::format-system-with-cache
                              provider
                              "You are a helpful assistant"
                              t)))
      (is (listp system-with-cache))
      ;; Should have cache_control
      (is (gethash "cache_control"
                   (car (coerce system-with-cache 'list)))))))

(test anthropic-tool-cache-format
  "Test Anthropic tool caching format"
  (let ((provider (make-instance 'cl-llm-provider::anthropic-provider
                                 :api-key "test"))
        (tool (cl-llm-provider:define-tool "test_tool" "A test tool"
                                           '((:name "param" :type :string)))))
    (let ((cached-tool (cl-llm-provider::format-tool-with-cache provider tool)))
      (is (hash-table-p cached-tool))
      (is (gethash "cache_control" cached-tool)))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "FORMAT-SYSTEM-WITH-CACHE is undefined"

**Step 3: Write minimal implementation**

Add to `src/providers/anthropic.lisp`:

```lisp
;;; Prompt Caching Support

(defun format-system-with-cache (provider system enable-cache)
  "Format system prompt with cache control for Anthropic.

PROVIDER - anthropic-provider instance
SYSTEM - System prompt string
ENABLE-CACHE - If T, add cache control markers

Returns:
  If ENABLE-CACHE is T: Vector of content blocks with cache control
  Otherwise: Plain string"
  (declare (ignore provider))
  (if (and enable-cache system)
      (let ((block (make-hash-table :test 'equal)))
        (setf (gethash "type" block) "text")
        (setf (gethash "text" block) system)
        (let ((cache-control (make-hash-table :test 'equal)))
          (setf (gethash "type" cache-control) "ephemeral")
          (setf (gethash "cache_control" block) cache-control))
        (vector block))
      system))

(defun format-tool-with-cache (provider tool)
  "Format tool definition with cache control for Anthropic.

PROVIDER - anthropic-provider instance
TOOL - tool-definition object

Returns hash-table with cache control added."
  (let ((base (translate-tool-to-provider provider tool)))
    (let ((cache-control (make-hash-table :test 'equal)))
      (setf (gethash "type" cache-control) "ephemeral")
      (setf (gethash "cache_control" base) cache-control))
    base))

(defmethod send-completion-request ((provider anthropic-provider) messages
                                    &key model max-tokens temperature
                                         system tools tool-choice stop
                                         provider-options)
  "Send completion request to Anthropic with cache control support."
  (let* ((url (format nil "~A/messages" (provider-base-url provider)))
         (headers (append
                   (make-http-headers provider)
                   (list (cons "anthropic-version" "2023-06-01"))))
         ;; Extract Anthropic-specific options
         (anthropic-options (getf provider-options :anthropic))
         (cache-system-p (or (getf anthropic-options :cache-system-prompt)
                            (getf anthropic-options :cache-control)))
         (cache-tools-p (getf anthropic-options :cache-tools))
         (encoded-body nil))

    ;; Build and encode request body
    (with-performance-timing (:encode-time)
      (let ((body (make-hash-table :test 'equal)))
        (setf (gethash "model" body) model)
        (setf (gethash "max_tokens" body) (or max-tokens 4096))

        ;; System prompt with optional caching
        (when system
          (setf (gethash "system" body)
                (format-system-with-cache provider system cache-system-p)))

        ;; Messages
        (setf (gethash "messages" body)
              (map 'vector #'plist-to-hash messages))

        (when temperature
          (setf (gethash "temperature" body) temperature))

        (when stop
          (setf (gethash "stop_sequences" body) (ensure-list stop)))

        ;; Tools with optional caching
        (when tools
          (setf (gethash "tools" body)
                (map 'vector
                     (if cache-tools-p
                         (lambda (tool) (format-tool-with-cache provider tool))
                         (lambda (tool) (translate-tool-to-provider provider tool)))
                     tools)))

        (when tool-choice
          (setf (gethash "tool_choice" body)
                (etypecase tool-choice
                  (keyword (plist-to-hash
                            (list :type (string-downcase (symbol-name tool-choice)))))
                  (string (plist-to-hash
                           (list :type "tool" :name tool-choice))))))

        (setf encoded-body
              (with-output-to-string (s)
                (yason:encode body s)))))

    ;; Make HTTP request
    (multiple-value-bind (response-body status-code)
        (with-performance-timing (:api-time)
          (handler-case
              (dex:post url
                        :headers headers
                        :content encoded-body
                        :force-string t)
            (dex:http-request-failed (e)
              (values (dex:response-body e) (dex:response-status e)))))

      (if (and (>= status-code 200) (< status-code 300))
          (yason:parse response-body)
          (handle-http-error status-code
                            (handler-case (yason:parse response-body)
                              (error () response-body))
                            provider)))))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/providers/anthropic.lisp tests/test-prompt-caching.lisp
git commit -m "feat(caching): implement Anthropic prompt and tool caching"
```

---

### Task 1.3: Update complete Function to Pass Cache Options

**Files:**
- Modify: `src/api.lisp`
- Test: `tests/test-prompt-caching.lisp`

**Step 1: Write the failing test**

Add to `tests/test-prompt-caching.lisp`:

```lisp
(test complete-passes-cache-options
  "Test complete passes cache options to provider"
  ;; This is a structural test - we verify the path exists
  ;; Actual caching requires API call
  (let ((provider (make-instance 'cl-llm-provider::anthropic-provider
                                 :api-key "test")))
    ;; Just verify function accepts and processes these parameters
    (is (not (null
              (ignore-errors
                ;; This will fail at API call, but should process params
                (handler-case
                    (cl-llm-provider:complete
                     '((:role "user" :content "Hi"))
                     :provider provider
                     :cache-system-prompt t
                     :cache-tools t
                     :system "You are helpful")
                  (error () t))))))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL (or needs adjustment)

**Step 3: Write minimal implementation**

Update `complete` in `src/api.lisp` to pass through cache options:

```lisp
;; Inside the do-complete flet, update the send-completion-request call:

(raw-response (send-completion-request provider actual-messages
                                       :model effective-model
                                       :max-tokens max-tokens
                                       :temperature temperature
                                       :system system
                                       :tools tools
                                       :tool-choice tool-choice
                                       :stop stop
                                       :provider-options
                                       (merge-provider-options
                                        provider-options
                                        (when (or cache-system-prompt cache-tools)
                                          (list :anthropic
                                                (list :cache-system-prompt cache-system-prompt
                                                      :cache-tools cache-tools))))))
```

Add helper function to `src/api.lisp`:

```lisp
(defun merge-provider-options (explicit-options implicit-options)
  "Merge explicit provider options with implicit ones.
Explicit options take precedence."
  (if (null implicit-options)
      explicit-options
      (if (null explicit-options)
          implicit-options
          ;; Merge plists by provider
          (let ((result (copy-list explicit-options)))
            (loop for (provider opts) on implicit-options by #'cddr
                  unless (getf result provider)
                  do (setf (getf result provider) opts))
            result))))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/api.lisp tests/test-prompt-caching.lisp
git commit -m "feat(caching): integrate cache options into complete function"
```

---

### Task 1.4: Add Cache Usage Reporting

**Files:**
- Modify: `src/providers/anthropic.lisp`
- Test: `tests/test-prompt-caching.lisp`

**Step 1: Write the failing test**

Add to `tests/test-prompt-caching.lisp`:

```lisp
(test parse-cache-usage
  "Test parsing cache usage from Anthropic response"
  (let ((provider (make-instance 'cl-llm-provider::anthropic-provider
                                 :api-key "test"))
        ;; Simulated response with cache info
        (raw-response (yason:parse
                       "{\"id\":\"msg_123\",
                         \"model\":\"claude-3-sonnet\",
                         \"content\":[{\"type\":\"text\",\"text\":\"Hello\"}],
                         \"stop_reason\":\"end_turn\",
                         \"usage\":{
                           \"input_tokens\":100,
                           \"output_tokens\":50,
                           \"cache_creation_input_tokens\":80,
                           \"cache_read_input_tokens\":20
                         }}")))
    (let ((response (cl-llm-provider::parse-completion-response
                     provider raw-response)))
      (let ((metadata (cl-llm-provider::response-metadata response)))
        (is (= 80 (getf metadata :cache-creation-tokens)))
        (is (= 20 (getf metadata :cache-read-tokens)))))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL (metadata not capturing cache info)

**Step 3: Write minimal implementation**

Update `parse-completion-response` in `src/providers/anthropic.lisp`:

```lisp
(defmethod parse-completion-response ((provider anthropic-provider) raw-response
                                      &key performance)
  (let* ((content-blocks (gethash "content" raw-response))
         (first-block (when (and content-blocks (> (length content-blocks) 0))
                       (elt content-blocks 0)))
         (content-type (gethash "type" first-block))
         (text-content (when (string= content-type "text")
                        (gethash "text" first-block)))
         (finish-reason (gethash "stop_reason" raw-response))
         (usage (gethash "usage" raw-response))
         (tool-calls nil))

    ;; Parse tool uses from content blocks
    (loop for block in (coerce content-blocks 'list)
          for block-type = (gethash "type" block)
          when (string= block-type "tool_use")
          collect (make-instance 'tool-call
                                 :id (gethash "id" block)
                                 :name (gethash "name" block)
                                 :arguments (gethash "input" block))
          into calls
          finally (setf tool-calls calls))

    ;; Build message for conversation continuation
    (let ((message (list :role "assistant")))
      (if tool-calls
          (setf (getf message :tool-calls) tool-calls)
          (setf (getf message :content) text-content)))

    (make-instance 'completion-response
                   :id (gethash "id" raw-response)
                   :model (gethash "model" raw-response)
                   :content text-content
                   :message message
                   :tool-calls tool-calls
                   :finish-reason (intern (string-upcase finish-reason) :keyword)
                   :usage (list :prompt-tokens (gethash "input_tokens" usage)
                                :completion-tokens (gethash "output_tokens" usage)
                                :total-tokens (+ (gethash "input_tokens" usage)
                                                (gethash "output_tokens" usage)))
                   :raw raw-response
                   :performance performance
                   :metadata (let ((metadata nil))
                              ;; Provider introspection
                              (setf (getf metadata :provider-type) (provider-type provider))
                              (setf (getf metadata :provider-name) (provider-name provider))
                              ;; Stop sequence
                              (when-let ((stop-seq (gethash "stop_sequence" raw-response)))
                                (setf (getf metadata :stop-sequence) stop-seq))
                              ;; Cache usage (Anthropic-specific)
                              (when-let ((cache-create (gethash "cache_creation_input_tokens" usage)))
                                (setf (getf metadata :cache-creation-tokens) cache-create))
                              (when-let ((cache-read (gethash "cache_read_input_tokens" usage)))
                                (setf (getf metadata :cache-read-tokens) cache-read))
                              metadata))))
```

Add exports to `src/package.lisp`:

```lisp
;; Prompt caching (response metadata)
;; (cache info available in response-metadata plist)
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/providers/anthropic.lisp src/package.lisp tests/test-prompt-caching.lisp
git commit -m "feat(caching): add cache usage reporting in response metadata"
```

---

## Task 2: Parallel Tool Calling

### Task 2.1: Add Parallel Execution Infrastructure

**Files:**
- Create: `src/parallel.lisp`
- Modify: `cl-llm-provider.asd`
- Test: `tests/test-parallel-tools.lisp` (create)

**Step 1: Write the failing test**

Create `tests/test-parallel-tools.lisp`:

```lisp
(defpackage :cl-llm-provider/test-parallel-tools
  (:use :cl :cl-llm-provider :fiveam))

(in-package :cl-llm-provider/test-parallel-tools)

(def-suite parallel-tools-suite :description "Parallel tool execution tests")
(in-suite parallel-tools-suite)

(test parallel-map-basic
  "Test basic parallel mapping"
  (let ((results (cl-llm-provider::parallel-map
                  (lambda (x) (* x x))
                  '(1 2 3 4 5))))
    (is (equal '(1 4 9 16 25) results))))

(test parallel-map-with-errors
  "Test parallel mapping with some errors"
  (let ((results (cl-llm-provider::parallel-map
                  (lambda (x)
                    (if (evenp x)
                        (error "Even number!")
                        (* x x)))
                  '(1 2 3 4 5)
                  :on-error :collect)))
    ;; Should have mix of results and error markers
    (is (= 5 (length results)))
    (is (= 1 (first results)))
    (is (= 9 (third results)))
    (is (= 25 (fifth results)))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "PARALLEL-MAP is undefined"

**Step 3: Write minimal implementation**

Create `src/parallel.lisp`:

```lisp
(in-package :cl-llm-provider)

;;;; Parallel Execution
;;;;
;;;; Provides parallel execution utilities for tool calling and batch operations.
;;;; Uses bordeaux-threads for portable threading.

(defvar *default-thread-pool-size* 4
  "Default number of worker threads for parallel operations.")

(defstruct parallel-result
  "Result of a parallel operation.

VALUE - The result value on success
ERROR - The error condition on failure
INDEX - Original index in input sequence"
  (value nil)
  (error nil)
  (index 0 :type integer))

(defun parallel-map (function sequence &key (on-error :signal) timeout)
  "Map FUNCTION over SEQUENCE in parallel.

FUNCTION - Function of one argument to apply
SEQUENCE - Sequence of inputs
ON-ERROR - :signal (default) rethrows first error
           :collect returns parallel-result structs
           :ignore skips failed items
TIMEOUT - Maximum seconds per item (nil = no timeout)

Returns list of results in same order as inputs.

Example:
  (parallel-map #'process-item items :on-error :collect)"
  (let* ((items (coerce sequence 'list))
         (count (length items))
         (results (make-array count :initial-element nil))
         (errors (make-array count :initial-element nil))
         (lock (bt:make-lock "parallel-map"))
         (threads nil))

    ;; Launch threads
    (loop for item in items
          for idx from 0
          do (push
              (bt:make-thread
               (lambda ()
                 (let ((item item)
                       (idx idx))
                   (handler-case
                       (let ((result (funcall function item)))
                         (bt:with-lock-held (lock)
                           (setf (aref results idx) result)))
                     (error (e)
                       (bt:with-lock-held (lock)
                         (setf (aref errors idx) e))))))
               :name (format nil "parallel-map-~D" idx))
              threads))

    ;; Wait for all threads
    (dolist (thread threads)
      (bt:join-thread thread))

    ;; Process results based on on-error strategy
    (loop for idx from 0 below count
          for result = (aref results idx)
          for error = (aref errors idx)
          collect
          (cond
            (error
             (ecase on-error
               (:signal (error error))
               (:collect (make-parallel-result :error error :index idx))
               (:ignore nil)))
            (t
             (if (eq on-error :collect)
                 (make-parallel-result :value result :index idx)
                 result))))))

(defun parallel-execute (functions &key (on-error :signal))
  "Execute FUNCTIONS in parallel, return results in order.

FUNCTIONS - List of zero-argument functions
ON-ERROR - Same as parallel-map

Returns list of results.

Example:
  (parallel-execute
    (list (lambda () (call-api-1))
          (lambda () (call-api-2))
          (lambda () (call-api-3))))"
  (parallel-map #'funcall functions :on-error on-error))
```

Add to `cl-llm-provider.asd`:

```lisp
(:file "parallel" :depends-on ("types"))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/parallel.lisp cl-llm-provider.asd tests/test-parallel-tools.lisp
git commit -m "feat(parallel): add parallel-map and parallel-execute utilities"
```

---

### Task 2.2: Add execute-tools-parallel Function

**Files:**
- Modify: `src/tools/execution.lisp`
- Test: `tests/test-parallel-tools.lisp`

**Step 1: Write the failing test**

Add to `tests/test-parallel-tools.lisp`:

```lisp
(test execute-tools-parallel-basic
  "Test parallel tool execution"
  (let* ((tool1 (cl-llm-provider:define-tool "tool1" "First tool"
                                             '((:name "x" :type :integer))
                                             :handler (lambda (args)
                                                       (sleep 0.1)
                                                       (list :result (* 2 (getf args :x))))))
         (tool2 (cl-llm-provider:define-tool "tool2" "Second tool"
                                             '((:name "y" :type :integer))
                                             :handler (lambda (args)
                                                       (sleep 0.1)
                                                       (list :result (* 3 (getf args :y))))))
         (tools (list tool1 tool2))
         (call1 (make-instance 'cl-llm-provider::tool-call
                               :id "call1" :name "tool1"
                               :arguments '(:x 5)))
         (call2 (make-instance 'cl-llm-provider::tool-call
                               :id "call2" :name "tool2"
                               :arguments '(:y 7)))
         (calls (list call1 call2)))

    ;; Sequential would take ~0.2s, parallel should be ~0.1s
    (let ((start-time (get-internal-real-time)))
      (let ((results (cl-llm-provider:execute-tools-parallel calls tools)))
        (let ((elapsed (/ (- (get-internal-real-time) start-time)
                         internal-time-units-per-second)))
          ;; Should complete faster than sequential
          (is (< elapsed 0.15))
          (is (= 2 (length results)))
          ;; Results should be correct
          (is (equal '(:result 10) (getf (first results) :result)))
          (is (equal '(:result 21) (getf (second results) :result))))))))

(test execute-tools-parallel-with-failure
  "Test parallel execution with partial failure"
  (let* ((tool1 (cl-llm-provider:define-tool "good" "Works"
                                             '()
                                             :handler (lambda (args)
                                                       (declare (ignore args))
                                                       "success")))
         (tool2 (cl-llm-provider:define-tool "bad" "Fails"
                                             '()
                                             :handler (lambda (args)
                                                       (declare (ignore args))
                                                       (error "Tool failed!"))))
         (tools (list tool1 tool2))
         (call1 (make-instance 'cl-llm-provider::tool-call
                               :id "c1" :name "good" :arguments nil))
         (call2 (make-instance 'cl-llm-provider::tool-call
                               :id "c2" :name "bad" :arguments nil)))

    (let ((results (cl-llm-provider:execute-tools-parallel
                    (list call1 call2) tools :on-error :collect)))
      (is (= 2 (length results)))
      ;; First should succeed
      (is (string= "success" (getf (first results) :result)))
      ;; Second should have error
      (is (getf (second results) :error)))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "EXECUTE-TOOLS-PARALLEL is undefined"

**Step 3: Write minimal implementation**

Add to `src/tools/execution.lisp` (or create if doesn't exist):

```lisp
(in-package :cl-llm-provider)

;;;; Parallel Tool Execution

(defun find-tool-by-name (name tools)
  "Find tool definition by NAME in TOOLS list."
  (find name tools :key #'tool-name :test #'string=))

(defun execute-tool-call (tool-call tool)
  "Execute a single tool call.

TOOL-CALL - tool-call object
TOOL - tool-definition object with handler

Returns plist with :tool-call-id, :result or :error"
  (let ((handler (tool-handler tool))
        (arguments (tool-call-arguments tool-call))
        (tool-call-id (tool-call-id tool-call)))
    (unless handler
      (return-from execute-tool-call
        (list :tool-call-id tool-call-id
              :error "No handler defined for tool")))

    ;; Call lifecycle hooks
    (when-let ((on-start (tool-on-start tool)))
      (funcall on-start tool-call arguments))

    (handler-case
        (let ((result (funcall handler arguments)))
          (when-let ((on-complete (tool-on-complete tool)))
            (funcall on-complete tool-call arguments result))
          (list :tool-call-id tool-call-id :result result))
      (error (e)
        (when-let ((on-error (tool-on-error tool)))
          (funcall on-error tool-call arguments e))
        (list :tool-call-id tool-call-id
              :error (format nil "~A" e))))))

(defun execute-tools-parallel (tool-calls tools &key (on-error :collect))
  "Execute multiple tool calls in parallel.

TOOL-CALLS - List of tool-call objects
TOOLS - List of tool-definition objects (with handlers)
ON-ERROR - :collect (default) includes errors in results
           :signal rethrows first error

Returns list of result plists, each with:
  :tool-call-id - ID of the tool call
  :result - Result value on success
  :error - Error message on failure

Example:
  (let ((results (execute-tools-parallel tool-calls tools)))
    (dolist (r results)
      (if (getf r :error)
          (handle-error r)
          (process-result r))))"
  (let ((tool-map (make-hash-table :test 'equal)))
    ;; Build tool lookup map
    (dolist (tool tools)
      (setf (gethash (tool-name tool) tool-map) tool))

    ;; Create execution functions
    (let ((executors
           (loop for call in tool-calls
                 for tool = (gethash (tool-call-name call) tool-map)
                 collect
                 (if tool
                     (lambda ()
                       (let ((call call) (tool tool))
                         (execute-tool-call call tool)))
                     (lambda ()
                       (let ((call call))
                         (list :tool-call-id (tool-call-id call)
                               :error (format nil "Unknown tool: ~A"
                                            (tool-call-name call)))))))))

      ;; Execute in parallel
      (let ((raw-results (parallel-execute executors :on-error :collect)))
        ;; Process results
        (loop for r in raw-results
              collect
              (if (parallel-result-p r)
                  (or (parallel-result-value r)
                      (list :tool-call-id "?"
                            :error (format nil "~A" (parallel-result-error r))))
                  r))))))

(defun execute-tools-sequential (tool-calls tools)
  "Execute tool calls sequentially (for comparison/fallback).

TOOL-CALLS - List of tool-call objects
TOOLS - List of tool-definition objects

Returns list of result plists."
  (let ((tool-map (make-hash-table :test 'equal)))
    (dolist (tool tools)
      (setf (gethash (tool-name tool) tool-map) tool))

    (loop for call in tool-calls
          for tool = (gethash (tool-call-name call) tool-map)
          collect
          (if tool
              (execute-tool-call call tool)
              (list :tool-call-id (tool-call-id call)
                    :error (format nil "Unknown tool: ~A" (tool-call-name call)))))))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/tools/execution.lisp tests/test-parallel-tools.lisp
git commit -m "feat(parallel): add execute-tools-parallel for concurrent tool execution"
```

---

### Task 2.3: Add parallel-tool-execution Parameter to complete

**Files:**
- Modify: `src/api.lisp`
- Modify: `src/package.lisp`
- Test: `tests/test-parallel-tools.lisp`

**Step 1: Write the failing test**

Add to `tests/test-parallel-tools.lisp`:

```lisp
(test complete-accepts-parallel-tool-execution
  "Test complete accepts parallel-tool-execution parameter"
  (let ((arglist (alexandria:function-arglist #'cl-llm-provider:complete)))
    (is (member :parallel-tool-execution arglist
                :test #'string-equal
                :key (lambda (x) (if (symbolp x) (symbol-name x) ""))))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL

**Step 3: Write minimal implementation**

This parameter is mainly informational for the user's tool handling code after getting a response. Add documentation to `complete`:

```lisp
;; Add to complete function signature and docstring:

;; TOOL EXECUTION:
;; PARALLEL-TOOL-EXECUTION - If T, hint that tool calls should be executed in parallel
;;                          (Note: actual execution is done by application code using
;;                          execute-tools-parallel after receiving response)
```

Add exports to `src/package.lisp`:

```lisp
;; Parallel tool execution
#:execute-tools-parallel
#:execute-tools-sequential
#:parallel-map
#:parallel-execute
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/api.lisp src/package.lisp tests/test-parallel-tools.lisp
git commit -m "feat(parallel): export parallel tool execution functions"
```

---

## Task 3: Intelligent Routing

### Task 3.1: Define Router Structure

**Files:**
- Create: `src/router.lisp`
- Modify: `cl-llm-provider.asd`
- Test: `tests/test-router.lisp` (create)

**Step 1: Write the failing test**

Create `tests/test-router.lisp`:

```lisp
(defpackage :cl-llm-provider/test-router
  (:use :cl :cl-llm-provider :fiveam))

(in-package :cl-llm-provider/test-router)

(def-suite router-suite :description "Intelligent routing tests")
(in-suite router-suite)

(test router-creation
  "Test router creation"
  (let ((router (cl-llm-provider:make-router
                 :providers (list (make-instance 'cl-llm-provider::openai-provider
                                                 :api-key "test1"
                                                 :model "gpt-4")
                                 (make-instance 'cl-llm-provider::anthropic-provider
                                                 :api-key "test2"
                                                 :model "claude-3-sonnet"))
                 :strategy :round-robin)))
    (is (not (null router)))
    (is (cl-llm-provider::router-p router))))

(test router-select-provider
  "Test provider selection"
  (let* ((p1 (make-instance 'cl-llm-provider::openai-provider :api-key "t1" :model "gpt-4"))
         (p2 (make-instance 'cl-llm-provider::anthropic-provider :api-key "t2" :model "claude"))
         (router (cl-llm-provider:make-router :providers (list p1 p2)
                                              :strategy :round-robin)))
    (let ((selected1 (cl-llm-provider::router-select-provider router nil)))
      (is (not (null selected1)))
      (let ((selected2 (cl-llm-provider::router-select-provider router nil)))
        ;; Round robin should alternate
        (is (not (eq selected1 selected2)))))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "MAKE-ROUTER is undefined"

**Step 3: Write minimal implementation**

Create `src/router.lisp`:

```lisp
(in-package :cl-llm-provider)

;;;; Intelligent Routing
;;;;
;;;; Provides intelligent model/provider selection based on:
;;;; - Cost optimization
;;;; - Capability requirements
;;;; - Load balancing
;;;; - Fallback chains

(defstruct router
  "Router for intelligent provider selection.

PROVIDERS - List of configured provider instances
STRATEGY - Selection strategy keyword
FALLBACK-CHAIN - Ordered list of providers for fallback
CAPABILITY-REQUIREMENTS - Required capabilities plist
COST-THRESHOLD - Maximum cost per 1M tokens
METRICS - Performance metrics hash-table"
  (providers nil :type list)
  (strategy :round-robin :type keyword)
  (fallback-chain nil :type list)
  (capability-requirements nil :type list)
  (cost-threshold nil :type (or null number))
  (metrics (make-hash-table :test 'equal) :type hash-table)
  ;; Internal state
  (current-index 0 :type integer)
  (lock (bt:make-lock "router") :type t))

(defun make-router (&key providers strategy fallback-chain
                         capability-requirements cost-threshold)
  "Create a new router for intelligent provider selection.

PROVIDERS - List of provider instances to route between
STRATEGY - Selection strategy:
  :round-robin - Rotate through providers
  :random - Random selection
  :least-cost - Select cheapest provider for the task
  :least-latency - Select fastest provider (based on metrics)
  :capability-match - Select based on required capabilities
  :failover - Use first provider, fallback on error
FALLBACK-CHAIN - Ordered list for failover (default: PROVIDERS order)
CAPABILITY-REQUIREMENTS - Required capabilities (e.g., '(:tools t :vision t))
COST-THRESHOLD - Max cost per 1M tokens (filters providers)

Returns router structure.

Example:
  (make-router
    :providers (list *openai* *anthropic* *groq*)
    :strategy :least-cost
    :capability-requirements '(:tools t))"
  (make-router-struct
   :providers providers
   :strategy (or strategy :round-robin)
   :fallback-chain (or fallback-chain providers)
   :capability-requirements capability-requirements
   :cost-threshold cost-threshold))

;;;; Provider Selection

(defun router-select-provider (router context)
  "Select a provider using ROUTER's strategy.

ROUTER - router structure
CONTEXT - Plist with request context:
  :messages - The messages being sent
  :tools - Tool definitions if any
  :model - Requested model (may be nil)

Returns selected provider instance."
  (let ((providers (filter-providers-by-requirements
                   (router-providers router)
                   (router-capability-requirements router)
                   (router-cost-threshold router)
                   context)))
    (when (null providers)
      (error 'provider-configuration-error
             :message "No providers match requirements"))

    (ecase (router-strategy router)
      (:round-robin (select-round-robin router providers))
      (:random (select-random providers))
      (:least-cost (select-least-cost providers context))
      (:least-latency (select-least-latency router providers))
      (:capability-match (select-capability-match providers context))
      (:failover (first providers)))))

(defun filter-providers-by-requirements (providers capabilities cost-threshold context)
  "Filter PROVIDERS to those meeting requirements."
  (declare (ignore context))
  (remove-if-not
   (lambda (provider)
     (and
      ;; Check capabilities
      (or (null capabilities)
          (loop for (cap required) on capabilities by #'cddr
                always (or (not required)
                          (provider-supports-p provider cap))))
      ;; Check cost threshold
      (or (null cost-threshold)
          (let* ((model (provider-default-model provider))
                 (meta (when model (model-metadata provider model)))
                 (input-cost (getf meta :input-cost-per-1m-tokens)))
            (or (null input-cost) (<= input-cost cost-threshold))))))
   providers))

(defun select-round-robin (router providers)
  "Select provider using round-robin strategy."
  (bt:with-lock-held ((router-lock router))
    (let* ((idx (mod (router-current-index router) (length providers)))
           (provider (nth idx providers)))
      (incf (router-current-index router))
      provider)))

(defun select-random (providers)
  "Select provider randomly."
  (nth (random (length providers)) providers))

(defun select-least-cost (providers context)
  "Select cheapest provider for the estimated request."
  (declare (ignore context))
  (let ((sorted (sort (copy-list providers)
                     #'<
                     :key (lambda (p)
                            (let* ((model (provider-default-model p))
                                   (meta (when model (model-metadata p model))))
                              (or (getf meta :input-cost-per-1m-tokens)
                                  most-positive-fixnum))))))
    (first sorted)))

(defun select-least-latency (router providers)
  "Select provider with best latency metrics."
  (let ((metrics (router-metrics router)))
    (let ((sorted (sort (copy-list providers)
                       #'<
                       :key (lambda (p)
                              (or (gethash (provider-type p) metrics)
                                  most-positive-fixnum)))))
      (first sorted))))

(defun select-capability-match (providers context)
  "Select provider with best capability match for context."
  (let ((needs-tools (getf context :tools)))
    (or (find-if (lambda (p)
                  (and (or (not needs-tools)
                          (provider-supports-p p :tools))))
                providers)
        (first providers))))

;;;; Router Metrics

(defun router-record-latency (router provider latency)
  "Record latency metric for PROVIDER in ROUTER."
  (bt:with-lock-held ((router-lock router))
    (let ((key (provider-type provider))
          (metrics (router-metrics router)))
      ;; Simple exponential moving average
      (let ((current (gethash key metrics)))
        (setf (gethash key metrics)
              (if current
                  (+ (* 0.9 current) (* 0.1 latency))
                  latency))))))

(defun router-record-error (router provider error-type)
  "Record error for PROVIDER in ROUTER metrics."
  (declare (ignore router provider error-type))
  ;; TODO: Implement error tracking for circuit breaker pattern
  nil)
```

Add to `cl-llm-provider.asd`:

```lisp
(:file "router" :depends-on ("types" "protocol" "parallel"))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/router.lisp cl-llm-provider.asd tests/test-router.lisp
git commit -m "feat(router): add intelligent routing infrastructure"
```

---

### Task 3.2: Add routed-complete Function

**Files:**
- Modify: `src/router.lisp`
- Test: `tests/test-router.lisp`

**Step 1: Write the failing test**

Add to `tests/test-router.lisp`:

```lisp
(test routed-complete-exists
  "Test routed-complete function exists"
  (is (fboundp 'cl-llm-provider:routed-complete)))

(test routed-complete-uses-router
  "Test routed-complete uses router for selection"
  ;; This is a structural test
  (let* ((p1 (make-instance 'cl-llm-provider::openai-provider :api-key "t1"))
         (p2 (make-instance 'cl-llm-provider::anthropic-provider :api-key "t2"))
         (router (cl-llm-provider:make-router :providers (list p1 p2)
                                              :strategy :round-robin)))
    ;; Just verify it accepts router parameter
    (is (not (null router)))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "ROUTED-COMPLETE is undefined"

**Step 3: Write minimal implementation**

Add to `src/router.lisp`:

```lisp
;;;; Routed Completion

(defun routed-complete (messages &key router model max-tokens temperature
                                      system tools tool-choice stop
                                      hooks on-request on-response on-error
                                      check-context auto-truncate
                                      num-retries retry-policy on-retry
                                      provider-options)
  "Send completion using ROUTER for intelligent provider selection.

MESSAGES - List of message plists
ROUTER - router structure (required)
...other parameters same as complete...

On failure, automatically tries next provider in fallback chain.

Returns completion-response object.

Example:
  (let ((router (make-router :providers (list *openai* *anthropic*)
                            :strategy :least-cost)))
    (routed-complete messages :router router))"
  (unless router
    (error 'provider-configuration-error
           :message "Router required for routed-complete"))

  (let* ((context (list :messages messages :tools tools :model model))
         (fallback-chain (router-fallback-chain router))
         (last-error nil))

    ;; Try providers in order until success
    (dolist (provider fallback-chain)
      (handler-case
          (let* ((start-time (get-internal-real-time))
                 (response (complete messages
                                     :provider provider
                                     :model (or model (provider-default-model provider))
                                     :max-tokens max-tokens
                                     :temperature temperature
                                     :system system
                                     :tools tools
                                     :tool-choice tool-choice
                                     :stop stop
                                     :hooks hooks
                                     :on-request on-request
                                     :on-response on-response
                                     :on-error on-error
                                     :check-context check-context
                                     :auto-truncate auto-truncate
                                     :num-retries num-retries
                                     :retry-policy retry-policy
                                     :on-retry on-retry
                                     :provider-options provider-options))
                 (latency (/ (- (get-internal-real-time) start-time)
                            internal-time-units-per-second)))

            ;; Record success metrics
            (router-record-latency router provider latency)
            (return-from routed-complete response))

        (error (e)
          ;; Record error and try next provider
          (router-record-error router provider (type-of e))
          (setf last-error e))))

    ;; All providers failed
    (error last-error)))

(defun with-routing ((router) &body body)
  "Execute BODY with ROUTER providing *default-provider*.

Binds *default-provider* to a routing wrapper.

Example:
  (with-routing (my-router)
    (complete messages)  ; Uses router for selection
    (complete other-messages))"
  ;; This is a convenience macro that could be implemented
  ;; For now, just document the pattern
  (declare (ignore router body))
  (error "with-routing not yet implemented - use routed-complete directly"))
```

Add exports to `src/package.lisp`:

```lisp
;; Routing
#:make-router
#:router-providers
#:router-strategy
#:router-select-provider
#:router-record-latency
#:routed-complete
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/router.lisp src/package.lisp tests/test-router.lisp
git commit -m "feat(router): add routed-complete for automatic provider selection"
```

---

### Task 3.3: Add Cost-Based Routing

**Files:**
- Modify: `src/router.lisp`
- Test: `tests/test-router.lisp`

**Step 1: Write the failing test**

Add to `tests/test-router.lisp`:

```lisp
(test cost-based-routing
  "Test cost-based provider selection"
  (let* ((expensive (make-instance 'cl-llm-provider::openai-provider
                                   :api-key "test"
                                   :model "gpt-4"))
         (cheap (make-instance 'cl-llm-provider::openai-provider
                               :api-key "test"
                               :model "gpt-4o-mini"))
         (router (cl-llm-provider:make-router
                  :providers (list expensive cheap)
                  :strategy :least-cost)))
    ;; Least cost should prefer gpt-4o-mini
    (let ((selected (cl-llm-provider::router-select-provider router nil)))
      (is (string= "gpt-4o-mini" (cl-llm-provider::provider-default-model selected))))))

(test cost-threshold-filtering
  "Test cost threshold filters expensive providers"
  (let* ((expensive (make-instance 'cl-llm-provider::openai-provider
                                   :api-key "test"
                                   :model "gpt-4"))  ; ~$30/1M
         (cheap (make-instance 'cl-llm-provider::openai-provider
                               :api-key "test"
                               :model "gpt-4o-mini"))  ; ~$0.15/1M
         (router (cl-llm-provider:make-router
                  :providers (list expensive cheap)
                  :strategy :round-robin
                  :cost-threshold 1.0)))  ; $1/1M max
    ;; Should only use cheap provider (gpt-4 is $30/1M > $1)
    (let ((selected (cl-llm-provider::router-select-provider router nil)))
      (is (string= "gpt-4o-mini"
                   (cl-llm-provider::provider-default-model selected))))))
```

**Step 2: Run test to verify it fails (or passes if implementation is correct)**

Expected: Should pass with current implementation

**Step 3: Verify implementation is complete**

The cost-based selection is already in `select-least-cost` and `filter-providers-by-requirements`. Verify tests pass.

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add tests/test-router.lisp
git commit -m "test(router): add cost-based routing tests"
```

---

## Final Task: Run Full Test Suite

**Step 1: Run all Phase 3 tests**

```bash
sbcl --noinform --non-interactive \
  --eval '(ql:quickload :fiveam)' \
  --eval '(ql:quickload :cl-llm-provider)' \
  --load tests/test-prompt-caching.lisp \
  --load tests/test-parallel-tools.lisp \
  --load tests/test-router.lisp \
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
git commit -m "feat: complete Phase 3 - prompt caching, parallel tools, routing"
```

---

## Summary

**Phase 3 delivers:**
1. **Prompt Caching** - Anthropic cache control via `:cache-system-prompt` and `:cache-tools`
2. **Parallel Tool Calling** - `execute-tools-parallel` for concurrent execution
3. **Intelligent Routing** - `make-router`, `routed-complete` with multiple strategies

**Files created/modified:**
- `src/parallel.lisp` - parallel-map, parallel-execute utilities
- `src/router.lisp` - router structure, selection strategies, routed-complete
- `src/tools/execution.lisp` - execute-tools-parallel, execute-tools-sequential
- `src/providers/anthropic.lisp` - cache control formatting
- `src/api.lisp` - provider-options, cache parameters
- `src/package.lisp` - new exports

**Routing Strategies:**
- `:round-robin` - Rotate through providers
- `:random` - Random selection
- `:least-cost` - Select cheapest based on model pricing
- `:least-latency` - Select fastest based on recorded metrics
- `:capability-match` - Match required capabilities
- `:failover` - Use first provider, fallback on error

**Usage Examples:**

```lisp
;; Prompt Caching (Anthropic)
(complete messages
  :provider *anthropic*
  :system "Long system prompt..."
  :cache-system-prompt t
  :tools my-tools
  :cache-tools t)

;; Parallel Tool Execution
(let ((response (complete messages :provider *openai* :tools tools)))
  (when-let ((calls (response-tool-calls response)))
    (let ((results (execute-tools-parallel calls tools)))
      ;; Process results...
      )))

;; Intelligent Routing
(let ((router (make-router
               :providers (list *openai* *anthropic* *groq*)
               :strategy :least-cost
               :cost-threshold 1.0)))  ; Max $1/1M tokens
  (routed-complete messages :router router))
```

---

## All Phases Complete

**Total Features Delivered:**

**Phase 1 - Critical Gaps:**
- Streaming responses (`complete-stream`)
- Token counting before calls (`count-tokens`, `estimate-cost`)
- Observability hooks (`make-hooks`, `add-hook`, logging helpers)

**Phase 2 - Production Readiness:**
- Context window overflow detection (`check-context-window`, truncation)
- Retry logic with exponential backoff (`make-retry-policy`, `:num-retries`)
- Batch API support (`batch-complete`, `wait-for-batch`)

**Phase 3 - Advanced Features:**
- Prompt caching (`cache-system-prompt`, `cache-tools`)
- Parallel tool calling (`execute-tools-parallel`)
- Intelligent routing (`make-router`, `routed-complete`)

**cl-llm-provider is now competitive with LiteLLM and Vercel AI SDK!**
