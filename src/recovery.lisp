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
    (min 60 (* base (+ 0.5 (random 1.0))))))

(defun/i provider-retry-after (condition)
  "Extract retry-after hint from CONDITION, or nil if none.

Works on any condition that has an error-retry-after reader
(provider-rate-limit-error, provider-overloaded-error)."
  (:feature error-recovery)
  (:purpose "Extract provider-supplied retry delay from condition")
  (typecase condition
    (provider-rate-limit-error (error-retry-after condition))
    (provider-overloaded-error (error-retry-after condition))
    (t nil)))

(defun/i retry-wait-time (condition attempt backoff-base)
  "Compute wait time for retry ATTEMPT, respecting provider hints.

CONDITION - the error condition
ATTEMPT - retry attempt number (1-based)
BACKOFF-BASE - base multiplier for exponential backoff

Returns seconds to wait. Respects retry-after hints from rate-limit
and overloaded conditions. Falls back to exponential backoff with jitter."
  (:feature error-recovery)
  (:purpose "Determine retry delay from provider hints or exponential backoff")
  (or (provider-retry-after condition)
      (* backoff-base (default-backoff attempt))))

;;; Retry Handler

(defun/i make-retry-handler (&key (max-retries 3)
                                   (backoff-fn #'default-backoff)
                                   on-retry)
  "Create a fresh handler function that retries transient errors via restarts.

MAX-RETRIES - maximum number of retry attempts (default 3)
BACKOFF-FN - function (attempt) -> seconds to wait (default: exponential with jitter)
ON-RETRY - optional callback (lambda (condition attempt) ...) called before each retry

Returns a function suitable for handler-bind. The handler:
1. Checks if the error is transient (via transient-error-p)
2. If retries remaining, waits per backoff-fn or provider hint
3. Invokes the best available retry restart (retry or wait-and-retry)
4. If no retry restart found, declines to handle (error propagates)
5. If retries exhausted, declines to handle

Create a fresh handler per request: the attempt counter is closed over and
never resets. This handler invokes restarts established by the signaling code.
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
        ;; Determine wait time (respect provider hints, fall back to backoff-fn)
        (let ((wait-time (or (provider-retry-after condition)
                             (funcall backoff-fn attempts))))
          (when (and wait-time (> wait-time 0))
            (sleep wait-time)))
        ;; Prefer RETRY: this handler already slept above, and WAIT-AND-RETRY
        ;; may sleep the provider hint a second time.
        (let ((restart (or (find-restart 'retry condition)
                           (find-restart 'wait-and-retry condition))))
          (when restart
            (invoke-restart restart)))))))

;;; Auto-Recovery Macro

(defun %fallback-entry (entry)
  "Split a :FALLBACK-PROVIDERS entry into (values provider model model-supplied-p).

ENTRY is a provider, or (PROVIDER . MODEL), or (PROVIDER MODEL). A provider is
never a cons, so the two forms cannot be confused.

MODEL-SUPPLIED-P is the whole point: it decides between the one-argument
USE-FALLBACK-PROVIDER, which keeps the caller's model — correct for two endpoints
serving the same one — and the two-argument form, which replaces it. A bare
provider entry must stay on the one-argument path or every same-model failover
changes behaviour with nothing to notice."
  (if (consp entry)
      (let ((tail (cdr entry)))
        (if (null tail)
            (values (car entry) nil nil)          ; (provider) — no model named
            (values (car entry)
                    (if (consp tail) (car tail) tail)
                    t)))
      (values entry nil nil)))

(defmacro with-auto-recovery ((&key (max-retries 3)
                                     (backoff-base 1.0)
                                     fallback-providers
                                     on-retry)
                               &body body)
  "Execute BODY with automatic recovery from transient errors.

MAX-RETRIES - maximum retry attempts before trying fallback (default 3)
BACKOFF-BASE - base multiplier for exponential backoff in seconds (default 1.0)
FALLBACK-PROVIDERS - list of entries to try if the primary exhausts retries.
  Each entry is a provider, or (PROVIDER . MODEL) / (PROVIDER MODEL) to reach
  that provider with a model of its own. NAME THE MODEL WHENEVER THE FALLBACK IS
  A DIFFERENT SERVICE: a bare entry keeps the caller's model, which is right for
  two endpoints serving the same one and wrong for every local->cloud switch,
  since a local model name means nothing to a hosted provider.
ON-RETRY - optional callback (lambda (condition attempt) ...) for each retry

Recovery behavior:
  1. Rate limit -> wait retry-after or backoff, re-execute body
  2. Overloaded -> wait retry-after or backoff, re-execute body
  3. Network/timeout -> wait backoff, re-execute body
  4. Retries exhausted + fallback entries -> invoke the USE-FALLBACK-PROVIDER
     restart with that provider and, when named, its model
  5. All options exhausted -> error propagates normally

RETRIES re-execute BODY. THE FALLBACK PATH DOES NOT: it invokes the restart
COMPLETE established, so only the failing request is re-issued and the body's
side effects are not repeated. This also means the fallback reaches a body that
passes :PROVIDER explicitly, which a *DEFAULT-PROVIDER* swap never could.

For a body with no LLM call in scope — one that signals an llm-provider-error
itself — there is no restart to invoke, and the fallback path falls back to
rebinding *default-provider* and re-executing BODY.

CAVEAT: This macro installs an outermost handler-bind on llm-provider-error.
Do NOT nest with-auto-recovery inside other handler-bind forms that handle
llm-provider-error — the outer handler fires first and may re-execute the
body before inner handlers get a chance. Use with-auto-recovery as the
outermost recovery layer only.

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
  (with-gensyms (retry-count max-r bb fallbacks on-retry-fn condition wait
                 recovery-block retry-point fb-prov fb-model fb-model-p restart)
    `(let ((,retry-count 0)
           (,max-r ,max-retries)
           (,bb ,backoff-base)
           (,fallbacks (copy-list ,fallback-providers))
           (,on-retry-fn ,on-retry)
           (*default-provider* *default-provider*))  ; shadow for safe fallback rebinding
       (block ,recovery-block
         (tagbody
           ,retry-point
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
                        (go ,retry-point))
                       ;; Retries exhausted, try fallback provider
                       (,fallbacks
                        (multiple-value-bind (,fb-prov ,fb-model ,fb-model-p)
                            (%fallback-entry (pop ,fallbacks))
                          (setf ,retry-count 0)  ; reset retries for new provider
                          (when ,on-retry-fn
                            (funcall ,on-retry-fn ,condition 0))
                          ;; PREFER THE RESTART. It is live here — a handler-bind
                          ;; handler runs before any unwinding, so COMPLETE's
                          ;; restart-case is still established — and it is where
                          ;; the model handling already lives correctly.
                          ;;
                          ;; The *DEFAULT-PROVIDER* swap could never do this. It
                          ;; cannot change the model, so a body naming one sent it
                          ;; to the fallback; and it does nothing at all for a body
                          ;; that passes :PROVIDER explicitly, which is exactly what
                          ;; a local-first caller writes.
                          ;;
                          ;; ONE ARGUMENT FOR A BARE ENTRY, two for (provider .
                          ;; model). The restart's own contract, unchanged: keep the
                          ;; caller's model unless a replacement is named.
                          (let ((,restart (find-restart 'use-fallback-provider ,condition)))
                            (if ,restart
                                (if ,fb-model-p
                                    (invoke-restart ,restart ,fb-prov ,fb-model)
                                    (invoke-restart ,restart ,fb-prov))
                                ;; No LLM call in scope — a body that signalled the
                                ;; condition itself. Swap the default and re-execute,
                                ;; exactly as before.
                                (progn
                                  (setf *default-provider* ,fb-prov)
                                  (go ,retry-point)))))))))))
             (return-from ,recovery-block (progn ,@body))))))))

;;; Telos Intent Annotations

(defintent available-recovery-options
  :feature error-recovery
  :purpose "List available restarts as agent-inspectable plists"
  :role "Primary introspection tool for agents to discover recovery options at runtime")

(defintent make-retry-handler
  :feature error-recovery
  :purpose "Create reusable handler function for restart-based transient error retry"
  :role "Lower-level restart-invoking handler; use with-auto-recovery for body re-execution")

(defintent with-auto-recovery
  :feature error-recovery
  :purpose "Automatic retry/fallback macro for transient LLM errors"
  :role "High-level recovery wrapper using tagbody/go for true re-execution")
