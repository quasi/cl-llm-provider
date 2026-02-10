;;; ABOUTME: Agent recovery helpers for automatic retry, fallback, and error inspection
(in-package :cl-llm-provider)

;;;; Agent Recovery Helpers
;;;;
;;;; Programmatic recovery utilities for autonomous agents.
;;;; These helpers make it easy for agents to handle transient errors
;;;; without custom handler-bind boilerplate.

;;; Introspection

(defun/i available-recovery-options (condition)
  "List available restarts for CONDITION as agent-inspectable plists.

CONDITION - an active condition object

Returns list of plists, each with:
  :name - restart name (symbol or nil)
  :report - human-readable description (string)

Example (from within a handler-bind):
  (handler-bind
      ((provider-rate-limit-error
        (lambda (e)
          (let ((options (available-recovery-options e)))
            (dolist (opt options)
              (format t \"~A: ~A~%\" (getf opt :name) (getf opt :report)))))))
    (complete messages))"
  (:feature error-recovery)
  (:purpose "Expose available restarts as structured data for agent consumption")
  (mapcar (lambda (restart)
            (list :name (restart-name restart)
                  :report (handler-case
                              (with-output-to-string (s)
                                (let ((*print-escape* nil))
                                  (princ restart s)))
                            (error () "(report unavailable)"))))
          (compute-restarts condition)))

;;; Classification

(defun/i transient-error-p (condition)
  "Return T if CONDITION represents a transient error that may succeed on retry.

Transient errors:
  - provider-rate-limit-error (rate limiting)
  - provider-overloaded-error (temporary capacity)
  - provider-network-error (connection issues, includes timeout)

Non-transient errors (don't retry):
  - provider-authentication-error (bad credentials)
  - provider-model-not-found-error (wrong model name)
  - provider-context-length-error (input too large)
  - provider-content-filter-error (content rejected)
  - tool-* errors (programming errors)"
  (:feature error-recovery)
  (:purpose "Classify whether an error is transient and worth retrying")
  (typep condition '(or provider-rate-limit-error
                        provider-overloaded-error
                        provider-network-error)))

;;; Backoff

(defun/i default-backoff (attempt)
  "Default exponential backoff: 1s, 2s, 4s, 8s, ...

ATTEMPT - retry attempt number (1-based)

Returns seconds to wait. Adds jitter (0.5x-1.5x) to avoid thundering herd."
  (:feature error-recovery)
  (:purpose "Exponential backoff with jitter for retry timing")
  (let ((base (expt 2 (1- attempt))))
    (* base (+ 0.5 (random 1.0)))))

(defun/i retry-wait-time (condition attempt backoff-base)
  "Compute wait time for retry ATTEMPT, respecting provider hints.

CONDITION - the error condition
ATTEMPT - retry attempt number (1-based)
BACKOFF-BASE - base multiplier for exponential backoff

Returns seconds to wait. Respects retry-after hints from rate-limit
and overloaded conditions. Falls back to exponential backoff with jitter."
  (:feature error-recovery)
  (:purpose "Determine retry delay from provider hints or exponential backoff")
  (cond
    ;; Rate limit with retry-after hint
    ((and (typep condition 'provider-rate-limit-error)
          (error-retry-after condition))
     (error-retry-after condition))
    ;; Overloaded with retry-after
    ((and (typep condition 'provider-overloaded-error)
          (error-overload-retry-after condition))
     (error-overload-retry-after condition))
    ;; Exponential backoff with jitter
    (t (* backoff-base (default-backoff attempt)))))

;;; Retry Handler

(defun/i make-retry-handler (&key (max-retries 3)
                                   (backoff-fn #'default-backoff)
                                   on-retry)
  "Create a handler function that retries transient errors via available restarts.

MAX-RETRIES - maximum number of retry attempts (default 3)
BACKOFF-FN - function (attempt) -> seconds to wait (default: exponential with jitter)
ON-RETRY - optional callback (lambda (condition attempt) ...) called before each retry

Returns a function suitable for handler-bind. The handler:
1. Checks if the error is transient (via transient-error-p)
2. If retries remaining, waits per backoff-fn or provider hint
3. Invokes the best available retry restart (wait-and-retry or retry)
4. If no retry restart found, declines to handle (error propagates)
5. If retries exhausted, declines to handle

Note: This handler invokes restarts established by the signaling code.
For full retry (re-executing the body), use with-auto-recovery instead.

Example:
  (handler-bind
      ((provider-rate-limit-error
        (make-retry-handler :max-retries 5
                            :on-retry (lambda (e n) (format t \"Retry ~D~%\" n)))))
    (complete messages))"
  (:feature error-recovery)
  (:purpose "Create reusable handler function for restart-based transient error retry")
  (let ((attempts 0))
    (lambda (condition)
      (when (and (transient-error-p condition)
                 (< attempts max-retries))
        (incf attempts)
        (when on-retry
          (funcall on-retry condition attempts))
        ;; Determine wait time
        (let ((wait-time
                (cond
                  ((and (typep condition 'provider-rate-limit-error)
                        (error-retry-after condition))
                   (error-retry-after condition))
                  ((and (typep condition 'provider-overloaded-error)
                        (error-overload-retry-after condition))
                   (error-overload-retry-after condition))
                  (t (funcall backoff-fn attempts)))))
          (when (and wait-time (> wait-time 0))
            (sleep wait-time)))
        ;; Try to invoke a retry restart
        (let ((restart (or (find-restart 'wait-and-retry condition)
                           (find-restart 'retry condition))))
          (when restart
            (invoke-restart restart)))))))

;;; Auto-Recovery Macro

(defmacro with-auto-recovery ((&key (max-retries 3)
                                     (backoff-base 1.0)
                                     fallback-providers
                                     on-retry)
                               &body body)
  "Execute BODY with automatic recovery from transient errors.

MAX-RETRIES - maximum retry attempts before trying fallback (default 3)
BACKOFF-BASE - base multiplier for exponential backoff in seconds (default 1.0)
FALLBACK-PROVIDERS - list of providers to try if primary exhausts retries
ON-RETRY - optional callback (lambda (condition attempt) ...) for each retry

Recovery behavior:
  1. Rate limit -> wait retry-after or backoff, re-execute body
  2. Overloaded -> wait retry-after or backoff, re-execute body
  3. Network/timeout -> wait backoff, re-execute body
  4. Retries exhausted + fallback providers -> switch *default-provider*, retry
  5. All options exhausted -> error propagates normally

The macro re-executes BODY on each retry (not just the failing sub-call).
Fallback providers are tried by rebinding *default-provider*, so they work
with code that uses the default provider. Code that explicitly passes
:provider will not be affected by fallback.

Example:
  ;; Simple retry
  (with-auto-recovery (:max-retries 5)
    (complete messages))

  ;; With fallback providers and logging
  (with-auto-recovery (:max-retries 3
                       :fallback-providers (list *openai* *anthropic*)
                       :on-retry (lambda (e attempt)
                                   (format t \"Retry ~D: ~A~%\" attempt e)))
    (complete messages))"
  (with-gensyms (retry-count max-r bb fallbacks on-retry-fn condition wait)
    `(let ((,retry-count 0)
           (,max-r ,max-retries)
           (,bb ,backoff-base)
           (,fallbacks ,(when fallback-providers `(copy-list ,fallback-providers)))
           (,on-retry-fn ,on-retry)
           (*default-provider* *default-provider*))  ; shadow for safe fallback rebinding
       (block auto-recovery
         (tagbody
           retry-point
           (handler-bind
               ((llm-provider-error
                 (lambda (,condition)
                   (when (transient-error-p ,condition)
                     (cond
                       ;; Still have retries
                       ((< ,retry-count ,max-r)
                        (incf ,retry-count)
                        (when ,on-retry-fn
                          (funcall ,on-retry-fn ,condition ,retry-count))
                        (let ((,wait (retry-wait-time ,condition ,retry-count ,bb)))
                          (when (> ,wait 0)
                            (sleep ,wait)))
                        (go retry-point))
                       ;; Retries exhausted, try fallback provider
                       (,fallbacks
                        (setf *default-provider* (pop ,fallbacks))
                        (setf ,retry-count 0)  ; reset retries for new provider
                        (when ,on-retry-fn
                          (funcall ,on-retry-fn ,condition 0))
                        (go retry-point)))))))
             (return-from auto-recovery (progn ,@body))))))))

;;; Telos Intent Annotations

(defintent available-recovery-options
  :feature error-recovery
  :purpose "List available restarts as agent-inspectable plists"
  :role "Primary introspection tool for agents to discover recovery options at runtime")

(defintent with-auto-recovery
  :feature error-recovery
  :purpose "Automatic retry/fallback macro for transient LLM errors"
  :role "High-level recovery wrapper using tagbody/go for true re-execution")
