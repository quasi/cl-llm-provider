# How-To: Error Handling

Handle API errors, network failures, and edge cases gracefully.

**Prerequisites**: [Tutorial: Basic Completions](../tutorials/01-basics.md) complete.

---

## Common Error Types

cl-llm-provider provides specific error types for different failure modes:

```lisp
(use-package :cl-llm-provider)

(handler-case
  (let ((response (complete messages)))
    ...)

  ;; Retry-able errors (temporary failures)
  (rate-limit-error (e)
    (format t "Rate limited. Wait and retry.~%"))

  (timeout-error (e)
    (format t "Request timed out.~%"))

  (network-error (e)
    (format t "Network error: ~A~%" e))

  ;; Non-retry-able errors (permanent failures)
  (authentication-error (e)
    (format t "Auth failed. Check your API key.~%"))

  (provider-error (e)
    (format t "Provider API error: ~A~%" e))

  ;; Catch-all
  (error (e)
    (format t "Unknown error: ~A~%" e)))
```

**Retry-able Errors** (use backoff and retry):
- `rate-limit-error` - Too many requests
- `timeout-error` - Request timed out
- `network-error` - Connection failed

**Non-retry-able Errors** (log and fail):
- `authentication-error` - Invalid API key or credentials
- `provider-error` - API returned an error
- `provider-configuration-error` - Missing required configuration

## Retry with Exponential Backoff

Automatically retry transient failures with increasing delays:

```lisp
(use-package :cl-llm-provider)

(defun complete-with-retry (messages
                           &key
                           (max-retries 3)
                           (initial-delay 1)
                           (max-delay 60))
  "Send completion, retrying transient errors with exponential backoff."

  (let ((retry-count 0)
        (delay initial-delay))

    (loop
      (handler-case
        ;; Try the request
        (return (complete messages))

        ;; Transient errors: retry with backoff
        ((or rate-limit-error timeout-error network-error) (e)
          (if (< retry-count max-retries)
            (progn
              (incf retry-count)
              ;; Wait with exponential backoff
              (format t "Error: ~A. Retrying in ~A seconds (~A/~A)~%"
                     e delay retry-count max-retries)
              (sleep delay)
              ;; Exponential backoff: 1s, 2s, 4s, 8s...
              (setf delay (min max-delay (* delay 2))))
            ;; Give up after max retries
            (error "Max retries exceeded: ~A" e)))

        ;; Permanent errors: fail immediately
        ((or authentication-error provider-error) (e)
          (error "Unrecoverable error: ~A" e))))))

;; Use it
(complete-with-retry messages)
```

## Rate Limit Handling

Handle rate limits intelligently:

```lisp
(use-package :cl-llm-provider)

(defun complete-rate-limit-aware (messages
                                 &key
                                 (request-delay 0))
  "Complete with automatic rate limit awareness."

  (loop
    (handler-case
      (progn
        (when (> request-delay 0)
          (sleep request-delay))
        (return (complete messages)))

      ;; Respect rate limits
      (rate-limit-error (e)
        ;; Extract wait time from error if available
        (let ((wait-seconds (get-rate-limit-reset-time e)))
          (format t "Rate limited. Waiting ~A seconds...~%" wait-seconds)
          (sleep wait-seconds))))))

(defun get-rate-limit-reset-time (error-condition)
  "Extract 'Retry-After' header from rate limit error."
  (let ((retry-after (error-retry-after error-condition)))
    (or retry-after 60)))  ; Default to 60s if not specified
```

## Batch Processing with Error Recovery

Process multiple requests with per-request error handling:

```lisp
(use-package :cl-llm-provider)

(defun process-batch (messages-list
                     &key
                     (continue-on-error t))
  "Process multiple completion requests.
  If continue-on-error is T, collect both successes and failures.
  If NIL, stop on first error."

  (let ((results '())
        (errors '()))

    (dolist (msg messages-list)
      (handler-case
        (push (complete msg) results)

        ;; Handle transient errors
        ((or rate-limit-error timeout-error network-error) (e)
          (if continue-on-error
            (push (list :error msg :condition e) errors)
            (error e)))

        ;; Handle permanent errors
        ((or authentication-error provider-error) (e)
          (if continue-on-error
            (push (list :error msg :condition e) errors)
            (error e)))))

    (values (reverse results) (reverse errors))))

;; Use it
(multiple-value-bind (successes failures)
    (process-batch messages)
  (format t "Processed: ~A successful, ~A failed~%"
         (length successes) (length failures))
  (dolist (failure failures)
    (format t "Failed: ~A~%" (getf failure :condition))))
```

## Handling Specific API Errors

Some providers return specific error messages. Handle them appropriately:

```lisp
(use-package :cl-llm-provider)

(defun handle-api-error (condition)
  "Convert API error to appropriate action."
  (let ((message (error-message condition))
        (status-code (error-status-code condition)))

    (cond
      ;; Rate limiting
      ((or (string-contains "rate" message)
           (= status-code 429))
       :retry-with-backoff)

      ;; Invalid API key
      ((or (string-contains "unauthorized" message)
           (= status-code 401))
       :check-credentials)

      ;; Invalid model name
      ((string-contains "not found" message)
       :check-model-name)

      ;; Quota exceeded
      ((= status-code 403)
       :check-billing)

      ;; Server error
      ((>= status-code 500)
       :retry-transient)

      ;; Default: unrecoverable
      (t :fail))))
```

## Graceful Degradation

Fall back to alternative approaches on error:

```lisp
(use-package :cl-llm-provider)

(defun complete-with-fallback (messages)
  "Try primary provider, fall back to secondary on error."

  ;; Try primary provider
  (handler-case
    (return (complete messages
                     :provider (make-provider :anthropic
                                            :model "claude-3-sonnet-20240229")))
    (error (e)
      (format t "Primary provider failed: ~A~%" e)))

  ;; Fall back to secondary provider
  (handler-case
    (return (complete messages
                     :provider (make-provider :openai
                                            :model "gpt-4")))
    (error (e)
      (format t "Secondary provider failed: ~A~%" e)))

  ;; Fall back to tertiary provider
  (handler-case
    (return (complete messages
                     :provider (make-provider :ollama
                                            :model "mistral")))
    (error (e)
      (format t "Tertiary provider failed: ~A~%" e)
      ;; If all fail, return cached response or error
      (error "All providers failed"))))
```

## Circuit Breaker Pattern

Stop attempting requests to a failing provider temporarily:

```lisp
(use-package :cl-llm-provider)

(defclass circuit-breaker ()
  ((failures :initform 0 :accessor breaker-failures)
   (threshold :initarg :threshold :initform 5)
   (reset-time :initarg :reset-time :initform 300)  ; 5 minutes
   (last-failure :initform nil :accessor breaker-last-failure)
   (state :initform :closed :accessor breaker-state)))

(defmethod breaker-open-p ((breaker circuit-breaker))
  "Check if circuit breaker is open."
  (eq (breaker-state breaker) :open))

(defmethod record-failure ((breaker circuit-breaker))
  "Record a failure."
  (incf (breaker-failures breaker))
  (setf (breaker-last-failure breaker) (get-universal-time))
  (when (>= (breaker-failures breaker) (slot-value breaker 'threshold))
    (setf (breaker-state breaker) :open)))

(defmethod reset-breaker ((breaker circuit-breaker))
  "Reset circuit breaker after cooldown."
  (when (breaker-open-p breaker)
    (let ((now (get-universal-time))
          (last (breaker-last-failure breaker)))
      (when (> (- now last) (slot-value breaker 'reset-time))
        (setf (breaker-failures breaker) 0)
        (setf (breaker-state breaker) :closed)))))

(defun complete-with-breaker (messages breaker)
  "Complete with circuit breaker protection."
  (reset-breaker breaker)
  (if (breaker-open-p breaker)
    (error "Provider is down. Circuit open.")
    (handler-case
      (return (complete messages))
      ((or rate-limit-error timeout-error network-error) (e)
        (record-failure breaker)
        (error e)))))
```

## Logging and Monitoring

Log errors for debugging and monitoring:

```lisp
(use-package :cl-llm-provider)

(defvar *error-log* (make-array 100 :initial-element nil))
(defvar *error-count* 0)

(defun log-error (condition messages)
  "Log an error for monitoring."
  (let ((entry (list
         :timestamp (get-universal-time)
         :error (type-of condition)
         :message (error-message condition)
         :messages-count (length messages)
         :condition condition)))
    ;; Store in log
    (setf (aref *error-log* (mod *error-count* 100)) entry)
    (incf *error-count*)
    ;; Print to stderr
    (format *error-output* "[ERROR] ~A: ~A~%"
           (error-message condition)
           (type-of condition))))

(defun complete-with-logging (messages)
  "Complete with error logging."
  (handler-case
    (complete messages)
    (error (e)
      (log-error e messages)
      (error e))))

;; View error logs
(defun show-recent-errors (&optional (n 10))
  "Show last N errors."
  (loop
    for i from (max 0 (- *error-count* n)) below *error-count*
    for entry = (aref *error-log* (mod i 100))
    when entry
    do (format t "~A: ~A~%"
              (getf entry :timestamp)
              (getf entry :message))))
```

## Production Best Practices

**In production, always**:

1. **Catch all errors**, not just expected ones
2. **Log errors** with context (request, user, timestamp)
3. **Use exponential backoff** for transient failures
4. **Implement circuit breakers** to prevent cascading failures
5. **Monitor error rates** to detect issues early
6. **Alert on critical errors** (auth failures, provider down)

```lisp
(defun complete-production (messages &key context)
  "Production-ready completion with all protections."
  (with-error-logging context
    (with-circuit-breaker (get-provider-breaker)
      (complete-with-retry
        messages
        :max-retries 3))))
```

---

**See Also**:
- [Tutorial: Basic Completions](../tutorials/01-basics.md)
- [Tutorial: Advanced Features](../tutorials/03-advanced.md)
