# How-To: Observability and Logging

Add logging, tracing, and monitoring to your LLM applications using hooks.

## When to Use Observability

**Use observability hooks when**:
- Debugging LLM application behavior
- Monitoring production API usage and costs
- Tracking request/response timing
- Auditing LLM interactions
- Building dashboards and metrics

**Available mechanisms**:
- **Hooks** - Structured callbacks for extensibility
- **Logging hooks** - Pre-configured logging
- **Custom monitoring** - Integration with your metrics system

---

## Quick Start: Logging

### Simple Request Logging

```lisp
(use-package :cl-llm-provider)

;; Create logging hooks
(let ((hooks (make-logging-hooks)))
  (complete '((:role "user" :content "Hello!"))
            :provider (make-provider :openai :model "gpt-4o-mini")
            :hooks hooks))

;; Output:
;; [14:23:45] LLM Request: OPENAI gpt-4o-mini (1 messages)
;; [14:23:46] LLM Response: 0.42s, 12 tokens
```

### Debug Level Logging

See full messages and responses:

```lisp
(let ((hooks (make-logging-hooks :level :debug)))
  (complete messages :provider provider :hooks hooks))

;; Output:
;; [14:23:45] LLM Request: OPENAI gpt-4o-mini (1 messages)
;;   Messages: ((:ROLE "user" :CONTENT "Hello!"))
;; [14:23:46] LLM Response: 0.42s, 12 tokens
;;   Content: "Hello! How can I help you today?"
```

### Log to File

```lisp
(with-open-file (log-stream "/var/log/llm-requests.log"
                            :direction :output
                            :if-exists :append
                            :if-does-not-exist :create)
  (let ((hooks (make-logging-hooks :stream log-stream :level :info)))
    (complete messages :provider provider :hooks hooks)))
```

---

## Hook System

### Hook Types

Four hook types cover the complete lifecycle:

| Hook Type | When | Signature |
|-----------|------|-----------|
| `:before-request` | Before API call | `(provider model messages)` |
| `:after-response` | After success | `(provider model response timing)` |
| `:on-error` | On error | `(provider model error)` |
| `:on-stream-chunk` | Each streaming chunk | `(provider model chunk)` |

### Creating and Using Hooks

```lisp
;; Create hooks container
(let ((hooks (make-hooks)))

  ;; Add before-request hook
  (add-hook hooks :before-request
            (lambda (provider model messages)
              (format t "→ Calling ~A ~A with ~D messages~%"
                      (provider-type provider)
                      model
                      (length messages))))

  ;; Add after-response hook
  (add-hook hooks :after-response
            (lambda (provider model response timing)
              (format t "← Response in ~,2Fs: ~A~%"
                      timing
                      (response-content response))))

  ;; Use hooks
  (complete messages :provider provider :hooks hooks))
```

---

## Observability Patterns

### Pattern 1: Request/Response Logging

Track all API interactions:

```lisp
(defun create-audit-hooks (audit-stream)
  "Create hooks that audit all LLM interactions to a stream."
  (let ((hooks (make-hooks)))

    (add-hook hooks :before-request
              (lambda (provider model messages)
                (format audit-stream "~&[~A] REQUEST~%" (get-timestamp))
                (format audit-stream "  Provider: ~A~%" (provider-type provider))
                (format audit-stream "  Model: ~A~%" model)
                (format audit-stream "  Messages: ~D~%" (length messages))))

    (add-hook hooks :after-response
              (lambda (provider model response timing)
                (format audit-stream "~&[~A] RESPONSE~%" (get-timestamp))
                (format audit-stream "  Timing: ~,3Fs~%" timing)
                (let ((usage (response-usage response)))
                  (format audit-stream "  Tokens: ~A~%"
                          (getf usage :total-tokens)))))

    (add-hook hooks :on-error
              (lambda (provider model error)
                (format audit-stream "~&[~A] ERROR~%" (get-timestamp))
                (format audit-stream "  Error: ~A~%" error)))

    hooks))

;; Usage
(with-open-file (audit "/var/log/llm-audit.log"
                       :direction :output
                       :if-exists :append)
  (let ((hooks (create-audit-hooks audit)))
    (complete messages :provider provider :hooks hooks)))
```

### Pattern 2: Metrics Collection

Track costs and performance:

```lisp
(defvar *llm-metrics* (make-hash-table :test 'equal))

(defun create-metrics-hooks ()
  "Create hooks that collect metrics for monitoring."
  (let ((hooks (make-hooks)))

    (add-hook hooks :before-request
              (lambda (provider model messages)
                (let ((key (format nil "~A:~A" (provider-type provider) model)))
                  (incf (gethash key *llm-metrics* 0)))))

    (add-hook hooks :after-response
              (lambda (provider model response timing)
                (let* ((key (format nil "~A:~A:timing"
                                   (provider-type provider) model))
                       (timings (gethash key *llm-metrics* nil)))
                  (push timing timings)
                  (setf (gethash key *llm-metrics*) timings))

                (let* ((usage (response-usage response))
                       (tokens (getf usage :total-tokens))
                       (key (format nil "~A:~A:tokens"
                                   (provider-type provider) model))
                       (total (gethash key *llm-metrics* 0)))
                  (setf (gethash key *llm-metrics*) (+ total tokens)))))

    hooks))

;; Usage
(setf *global-hooks* (create-metrics-hooks))

;; Query metrics
(defun print-metrics ()
  (maphash (lambda (k v)
             (format t "~A: ~A~%" k v))
           *llm-metrics*))
```

### Pattern 3: Error Tracking

Track and categorize errors:

```lisp
(defvar *error-log* nil)

(defun create-error-tracking-hooks ()
  "Create hooks that track and categorize errors."
  (let ((hooks (make-hooks)))

    (add-hook hooks :on-error
              (lambda (provider model error)
                (let ((error-entry (list
                                   :timestamp (get-universal-time)
                                   :provider (provider-type provider)
                                   :model model
                                   :error-type (type-of error)
                                   :error-message (format nil "~A" error))))
                  (push error-entry *error-log*))))

    hooks))

;; Usage
(setf *global-hooks* (create-error-tracking-hooks))

;; Analyze errors
(defun analyze-errors ()
  "Summarize errors by type."
  (let ((error-counts (make-hash-table :test 'equal)))
    (dolist (entry *error-log*)
      (let ((error-type (getf entry :error-type)))
        (incf (gethash error-type error-counts 0))))

    (maphash (lambda (type count)
               (format t "~A: ~D occurrences~%" type count))
             error-counts)))
```

### Pattern 4: Cost Tracking

Monitor API costs in real-time:

```lisp
(defvar *total-cost* 0.0)
(defvar *cost-by-provider* (make-hash-table :test 'equal))

(defun create-cost-tracking-hooks ()
  "Create hooks that track API costs."
  (let ((hooks (make-hooks)))

    (add-hook hooks :after-response
              (lambda (provider model response timing)
                (let* ((usage (response-usage response))
                       (prompt-tokens (getf usage :prompt-tokens))
                       (completion-tokens (getf usage :completion-tokens))
                       (metadata (model-metadata provider model))
                       (input-cost-per-1m (getf metadata :input-cost-per-1m-tokens))
                       (output-cost-per-1m (getf metadata :output-cost-per-1m-tokens)))

                  (when (and input-cost-per-1m output-cost-per-1m
                            prompt-tokens completion-tokens)
                    (let* ((input-cost (* prompt-tokens
                                         (/ input-cost-per-1m 1000000.0)))
                           (output-cost (* completion-tokens
                                          (/ output-cost-per-1m 1000000.0)))
                           (request-cost (+ input-cost output-cost))
                           (provider-key (format nil "~A:~A"
                                                (provider-type provider)
                                                model)))

                      ;; Update totals
                      (incf *total-cost* request-cost)
                      (incf (gethash provider-key *cost-by-provider* 0.0)
                            request-cost)

                      ;; Log
                      (format t "Cost: ~A (~A)~%"
                              (format-cost request-cost)
                              provider-key))))))

    hooks))

;; Usage
(setf *global-hooks* (create-cost-tracking-hooks))

;; Check costs
(defun print-costs ()
  (format t "Total cost: ~A~%" (format-cost *total-cost*))
  (format t "~%By provider:~%")
  (maphash (lambda (provider cost)
             (format t "  ~A: ~A~%" provider (format-cost cost)))
           *cost-by-provider*))
```

---

## Global vs Per-Request Hooks

### Global Hooks

Apply to all requests automatically:

```lisp
;; Set once at application startup
(setf *global-hooks* (make-logging-hooks :level :info))

;; All requests use global hooks
(complete messages1 :provider provider)  ; Logged
(complete messages2 :provider provider)  ; Logged
(complete messages3 :provider provider)  ; Logged

;; Disable global hooks
(setf *global-hooks* nil)
```

**Use global hooks for**:
- Application-wide monitoring
- Production logging
- Cost tracking across all requests
- Audit trails

### Per-Request Hooks

Apply to specific requests:

```lisp
;; Different hooks for different requests
(complete important-messages
          :provider provider
          :hooks (make-logging-hooks :level :debug))  ; Verbose logging

(complete routine-messages
          :provider provider
          :hooks (make-logging-hooks :level :warn))   ; Only errors

(complete background-messages
          :provider provider)  ; No hooks (or global only)
```

**Use per-request hooks for**:
- Request-specific logging
- Debug sessions
- Temporary monitoring
- Testing

### Combining Global and Per-Request

```lisp
;; Global hooks for metrics
(setf *global-hooks* (create-metrics-hooks))

;; Add per-request hooks for specific debugging
(complete messages
          :provider provider
          :hooks (make-logging-hooks :level :debug))  ; Both metrics + debug logs
```

**Note**: Currently, explicit `:hooks` parameter overrides `*global-hooks*`. To use both, merge them manually:

```lisp
(defun merge-hooks (global-hooks request-hooks)
  "Combine global and request hooks."
  (let ((merged (make-hooks)))
    ;; Copy global hooks
    (dolist (hook (hooks-before-request global-hooks))
      (push hook (hooks-before-request merged)))
    ;; Add request hooks
    (dolist (hook (hooks-before-request request-hooks))
      (push hook (hooks-before-request merged)))
    ;; Repeat for other hook types...
    merged))
```

---

## Individual Callbacks

Alternative to hooks structures for simple cases:

### Simple Callbacks

```lisp
(complete messages
          :provider provider
          :on-request (lambda (request-info)
                        (format t "Sending request: ~A~%" request-info))
          :on-response (lambda (response timing)
                         (format t "Got response in ~,2Fs~%" timing))
          :on-error (lambda (error)
                      (format t "Error: ~A~%" error)))
```

**Request info plist**:
```lisp
(:provider-type :openai
 :model "gpt-4o-mini"
 :message-count 3
 :has-tools t)
```

### When to Use Callbacks vs Hooks

**Use individual callbacks when**:
- Quick debugging/testing
- One-off logging
- Simple use cases

**Use hooks structures when**:
- Reusable logging configuration
- Multiple concerns (metrics + logging + audit)
- Production applications
- Global observability

---

## Streaming Observability

### Log Streaming Requests

Hooks work with streaming too:

```lisp
(let ((hooks (make-logging-hooks :level :info)))
  (complete-stream messages
                   :provider provider
                   :hooks hooks  ; Logs start/end
                   :on-chunk (lambda (chunk)
                               (format t "~A" (chunk-delta chunk)))))

;; Output:
;; [14:30:15] LLM Request: OPENAI gpt-4o-mini (1 messages)
;; [streaming chunks...]
;; [14:30:16] LLM Response: 0.52s, 15 tokens
```

### Track Streaming Progress

```lisp
(let ((hooks (make-hooks))
      (start-time nil))

  (add-hook hooks :before-request
            (lambda (provider model messages)
              (setf start-time (get-internal-real-time))
              (format t "Starting stream...~%")))

  (complete-stream messages
                   :provider provider
                   :hooks hooks
                   :on-chunk (lambda (chunk)
                               (let ((elapsed (/ (- (get-internal-real-time) start-time)
                                                internal-time-units-per-second)))
                                 (format t "[~,1Fs] ~A"
                                         elapsed (chunk-delta chunk))))))
```

---

## Integration with External Systems

### Prometheus Metrics

```lisp
(defun create-prometheus-hooks (prometheus-client)
  "Create hooks that export metrics to Prometheus."
  (let ((hooks (make-hooks)))

    (add-hook hooks :before-request
              (lambda (provider model messages)
                (prometheus:increment prometheus-client
                                     "llm_requests_total"
                                     :labels `(("provider" . ,(provider-type provider))
                                             ("model" . ,model)))))

    (add-hook hooks :after-response
              (lambda (provider model response timing)
                (prometheus:observe prometheus-client
                                   "llm_request_duration_seconds"
                                   timing
                                   :labels `(("provider" . ,(provider-type provider))
                                           ("model" . ,model)))

                (let* ((usage (response-usage response))
                       (tokens (getf usage :total-tokens)))
                  (prometheus:increment prometheus-client
                                       "llm_tokens_total"
                                       tokens
                                       :labels `(("provider" . ,(provider-type provider))
                                               ("model" . ,model))))))

    (add-hook hooks :on-error
              (lambda (provider model error)
                (prometheus:increment prometheus-client
                                     "llm_errors_total"
                                     :labels `(("provider" . ,(provider-type provider))
                                             ("model" . ,model)
                                             ("error_type" . ,(type-of error))))))

    hooks))
```

### Structured JSON Logging

```lisp
(defun create-json-logging-hooks (json-stream)
  "Create hooks that log structured JSON for log aggregation."
  (let ((hooks (make-hooks)))

    (add-hook hooks :before-request
              (lambda (provider model messages)
                (let ((log-entry (yason:encode-plist
                                 (list :timestamp (get-universal-time)
                                       :event "llm_request"
                                       :provider (provider-type provider)
                                       :model model
                                       :message-count (length messages)))))
                  (format json-stream "~A~%" log-entry))))

    (add-hook hooks :after-response
              (lambda (provider model response timing)
                (let* ((usage (response-usage response))
                       (log-entry (yason:encode-plist
                                  (list :timestamp (get-universal-time)
                                        :event "llm_response"
                                        :provider (provider-type provider)
                                        :model model
                                        :timing timing
                                        :tokens (getf usage :total-tokens)))))
                  (format json-stream "~A~%" log-entry))))

    hooks))
```

### OpenTelemetry Tracing

```lisp
(defun create-otel-hooks (tracer)
  "Create hooks that emit OpenTelemetry spans."
  (let ((hooks (make-hooks))
        (current-span nil))

    (add-hook hooks :before-request
              (lambda (provider model messages)
                (setf current-span
                      (otel:start-span tracer "llm.completion"
                                      :attributes `(("llm.provider" . ,(provider-type provider))
                                                  ("llm.model" . ,model)
                                                  ("llm.message_count" . ,(length messages)))))))

    (add-hook hooks :after-response
              (lambda (provider model response timing)
                (let ((usage (response-usage response)))
                  (otel:set-span-attributes current-span
                                           `(("llm.usage.prompt_tokens" . ,(getf usage :prompt-tokens))
                                             ("llm.usage.completion_tokens" . ,(getf usage :completion-tokens))
                                             ("llm.response_time" . ,timing)))
                  (otel:end-span current-span))))

    (add-hook hooks :on-error
              (lambda (provider model error)
                (otel:record-exception current-span error)
                (otel:end-span current-span)))

    hooks))
```

---

## Best Practices

### 1. Don't Let Hooks Fail Requests

Hooks should be defensive - errors in hooks shouldn't break your application:

```lisp
;; BAD: Hook error breaks request
(add-hook hooks :after-response
          (lambda (provider model response timing)
            (write-to-database response)))  ; Might fail!

;; GOOD: Hook errors are caught
(add-hook hooks :after-response
          (lambda (provider model response timing)
            (handler-case
                (write-to-database response)
              (error (e)
                (warn "Failed to log response: ~A" e)))))
```

**Note**: The hook system automatically catches hook errors and logs warnings, but being defensive in hook code is still recommended.

### 2. Keep Hooks Fast

Hooks run synchronously - slow hooks delay requests:

```lisp
;; BAD: Slow synchronous operation
(add-hook hooks :after-response
          (lambda (provider model response timing)
            (http-post "https://slow-server.com/log" response)))  ; Blocks!

;; GOOD: Async logging
(add-hook hooks :after-response
          (lambda (provider model response timing)
            (bt:make-thread
              (lambda ()
                (http-post "https://slow-server.com/log" response)))))
```

### 3. Use Log Levels Appropriately

- `:debug` - Development, troubleshooting (shows full messages)
- `:info` - Production, normal operations (shows summary)
- `:warn` - Errors only (minimal logging)

```lisp
;; Development
(setf *global-hooks* (make-logging-hooks :level :debug))

;; Production
(setf *global-hooks* (make-logging-hooks :level :info))
```

### 4. Sanitize Sensitive Data

Don't log API keys, PII, or sensitive content:

```lisp
(defun sanitize-message (message)
  "Remove sensitive data from message."
  (let ((content (getf message :content)))
    ;; Redact patterns that look like emails, SSNs, etc.
    (ppcre:regex-replace-all "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b"
                            content
                            "[EMAIL_REDACTED]")))

(add-hook hooks :before-request
          (lambda (provider model messages)
            (let ((sanitized (mapcar #'sanitize-message messages)))
              (format t "Request: ~A~%" sanitized))))
```

### 5. Rotate Log Files

For file logging, implement rotation:

```lisp
(defun get-rotating-log-stream ()
  "Open log file with date in filename for daily rotation."
  (let ((log-filename (format nil "/var/log/llm-~A.log"
                             (format-timestring nil (now) :format '(:year :month :day)))))
    (open log-filename
          :direction :output
          :if-exists :append
          :if-does-not-exist :create)))
```

---

## Troubleshooting

### Hooks Not Firing

**Symptom**: Hook callbacks never called

**Checklist**:
- ✅ Did you pass `:hooks` parameter to `complete`/`complete-stream`?
- ✅ Did you add hooks with `add-hook` before calling?
- ✅ Is `*global-hooks*` set if not using explicit `:hooks`?

**Debug**:
```lisp
;; Verify hook was added
(let ((hooks (make-hooks)))
  (add-hook hooks :before-request (lambda (&rest args) (format t "CALLED~%")))
  (format t "Hooks: ~A~%" (hooks-before-request hooks)))
```

### Hook Errors

**Symptom**: Warnings about hook errors

**Cause**: Hook code throwing errors

**Solution**: Wrap hook body in `handler-case`:
```lisp
(add-hook hooks :after-response
          (lambda (provider model response timing)
            (handler-case
                (process-response response)
              (error (e)
                (warn "Hook error: ~A" e)))))
```

### Performance Impact

**Symptom**: Requests slower with hooks

**Cause**: Synchronous operations in hooks (database writes, HTTP calls)

**Solution**: Make hooks async or use queues:
```lisp
(defvar *log-queue* (make-queue))

(add-hook hooks :after-response
          (lambda (provider model response timing)
            ;; Fast: just enqueue
            (enqueue *log-queue* (list response timing))))

;; Separate thread processes queue
(bt:make-thread
  (lambda ()
    (loop
      (let ((entry (dequeue *log-queue*)))
        (when entry
          (process-log-entry entry))))))
```

---

## See Also

- [Tutorial: Advanced Features](../tutorials/03-advanced.md) - Using observability with other features
- [How-To: Streaming](streaming.md) - Observability for streaming responses
- [How-To: Error Handling](error-handling.md) - Error hooks and recovery
- [Reference: API](../reference/api.md) - Complete hooks API reference
- [Phase 1 Manual Testing](../phase-1-manual-testing.md) - Testing observability features
