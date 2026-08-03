# How-To: Error Handling

Handle API errors, network failures, and edge cases gracefully.

**Prerequisites**: [Tutorial: Basic Completions](../tutorials/01-basics.md) complete.

---

## Common Error Types

Every error is a condition under `llm-provider-error`. The names are prefixed —
there is no bare `network-error` or `rate-limit-error`:

```lisp
(in-package :cl-llm-provider)

(handler-case
    (complete messages)

  ;; Transient — worth retrying
  (provider-rate-limit-error (e)
    (format t "Rate limited, retry after ~As~%" (error-retry-after e)))

  (provider-timeout-error (e)
    (format t "Request timed out: ~A~%" e))

  (provider-network-error (e)
    (format t "Could not reach ~A: ~A~%" (error-url e) e))

  (provider-overloaded-error (e)
    (format t "Provider overloaded: ~A~%" e))

  ;; Permanent — retrying repeats the same failure
  (provider-authentication-error (e)
    (format t "Auth failed (~A). Check your API key.~%" (error-status-code e)))

  (provider-model-not-found-error (e)
    (format t "No such model: ~A~%" (error-requested-model e)))

  (provider-context-length-error (e)
    (format t "Prompt too long: ~A~%" e))

  ;; Everything else
  (llm-provider-error (e)
    (format t "Provider error: ~A~%" e)))
```

The hierarchy, so you can catch at the altitude you mean:

```
llm-provider-error
├── provider-configuration-error
├── provider-api-error              ; the server answered, with an error
│   ├── provider-rate-limit-error
│   ├── provider-authentication-error
│   ├── provider-model-not-found-error
│   ├── provider-context-length-error
│   ├── provider-content-filter-error
│   ├── provider-overloaded-error
│   └── provider-invalid-response-error
├── provider-network-error          ; the server did not answer
│   └── provider-timeout-error
├── provider-json-parse-error
└── llm-stream-error
    ├── stream-interrupted-error
    └── stream-parse-error
```

Don't classify by string matching or status code — `handle-http-error` already
did that, which is what the typed conditions are for. If you need the predicate
rather than the type, `(transient-error-p condition)` is the same judgement the
library uses internally.

## Restarts

Every error point offers restarts. **Use `handler-bind`, never `handler-case`**:
`handler-case` unwinds the stack before its body runs, which disestablishes every
restart, so `invoke-restart` there signals `control-error` instead of recovering.

| Restart | Established by | Argument(s) | Effect |
|---|---|---|---|
| `use-value` | HTTP 401 | new API key | Set the key on the provider and re-issue |
| `wait-and-retry` | HTTP 429 | — | Sleep `retry-after`, then re-issue |
| `retry` | HTTP 429, and every other status **except 401** | — | Re-issue the identical request |
| `use-model` | `complete`, `embedding`, `complete-stream` | model name | Re-issue against the **same** provider with a different model |
| `use-fallback-provider` | `complete`, `embedding`, `complete-stream` | provider, *optional* model | Re-issue against a **different** provider |
| `skip-tool` | `execute-tool-calls`, when a tool name is not in the registry | — | Skip that call and carry on |
| `use-error-result` | `execute-tool`, on handler failure | — | Record the error as that tool's result |
| `retry-execution` | `execute-tool`, on handler failure | — | Run the handler again |

Three things that surprise people. A 401 offers only `use-value`, not `retry` —
the same key would fail the same way. `provider-overloaded-error` (503/529) falls
through the generic branch, so it offers plain `retry` and **not**
`wait-and-retry`; for backoff there use `with-auto-recovery`, whose own loop
honours `retry-after` for overloaded conditions. And the three tool-execution
restart names above live in `cl-llm-provider.tools` and are not exported — from
another package, write `(find-restart 'cl-llm-provider.tools::skip-tool c)`.

```lisp
(handler-bind
    ((provider-model-not-found-error
       (lambda (c)
         (let ((r (find-restart 'use-model c)))
           (when r (invoke-restart r "gpt-4o-mini"))))))
  (complete messages :model "gtp-4o-mini"))   ; typo, corrected in flight
```

To discover what is available at runtime rather than from this table:

```lisp
(handler-bind
    ((llm-provider-error
       (lambda (c)
         (dolist (opt (available-recovery-options c))
           (format t "~A — ~A~%" (getf opt :name) (getf opt :report))))))
  (complete messages))
```

`use-fallback-provider` takes an optional second argument, the model to use on
the fallback. Supply it whenever the fallback is a different service; see
[Local models and failover](local-models-and-failover.md), which is the case it
exists for.

## Retry with Exponential Backoff

`with-auto-recovery` does this. It retries transient errors only, waits
`retry-after` when the server sent one and backs off exponentially when it did
not:

```lisp
(with-auto-recovery (:max-retries 3 :backoff-base 1.0
                     :on-retry (lambda (e n) (format t "retry ~D: ~A~%" n e)))
  (complete messages))
```

Write it by hand only if you need behaviour the macro does not have. The pieces
are exported, so you are not starting from nothing:

```lisp
(defun complete-with-retry (messages &key (max-retries 3) (backoff-base 1.0))
  "Send a completion, retrying transient errors with exponential backoff."
  (let ((attempt 0))
    (loop                              ; LOOP establishes the block RETURN needs
      (handler-case
          (return (complete messages))
        (llm-provider-error (e)
          (unless (and (transient-error-p e) (< attempt max-retries))
            (error e))
          (incf attempt)
          (let ((wait (retry-wait-time e attempt backoff-base)))
            (format t "~A — retrying in ~,1Fs (~D/~D)~%" e wait attempt max-retries)
            (when (> wait 0) (sleep wait))))))))
```

## Rate Limit Handling

`provider-rate-limit-error` carries the server's own `Retry-After` when it sent
one. `wait-and-retry` uses it for you:

```lisp
(handler-bind
    ((provider-rate-limit-error
       (lambda (c)
         (format t "Rate limited; waiting ~As~%" (or (error-retry-after c) 60))
         (let ((r (find-restart 'wait-and-retry c)))
           (when r (invoke-restart r))))))
  (complete messages))
```

`(error-retry-after c)` returns `NIL` when the provider sent no header, which is
why the fallback above is explicit. `retry-wait-time` applies the same default.

## Batch Processing with Error Recovery

Collect successes and failures instead of stopping at the first problem:

```lisp
(defun process-batch (messages-list &key (continue-on-error t))
  "Complete each request. Returns (values successes failures)."
  (let ((results '())
        (failures '()))
    (dolist (msg messages-list)
      (handler-case
          (push (complete msg) results)
        (llm-provider-error (e)
          (if continue-on-error
              (push (list :messages msg :condition e) failures)
              (error e)))))
    (values (nreverse results) (nreverse failures))))

(multiple-value-bind (successes failures)
    (process-batch (list (list (list :role "user" :content "Q1"))
                         (list (list :role "user" :content "Q2"))))
  (format t "~D succeeded, ~D failed~%" (length successes) (length failures))
  (dolist (f failures)
    (format t "  ~A~%" (getf f :condition))))
```

## Deciding What to Do With an Error

Dispatch on the condition type. The status code and message were already
classified for you:

```lisp
(defun error-action (condition)
  "What to do about CONDITION."
  (typecase condition
    (provider-rate-limit-error       :wait-and-retry)
    (provider-overloaded-error       :wait-and-retry)
    (provider-timeout-error          :retry-with-backoff)
    (provider-network-error          :use-fallback-provider)
    (provider-authentication-error   :check-credentials)
    (provider-model-not-found-error  :use-model)
    (provider-context-length-error   :shorten-the-prompt)
    (provider-content-filter-error   :do-not-retry)
    (t (if (transient-error-p condition) :retry-with-backoff :fail))))
```

## Graceful Degradation

Try one provider, fall back to another. Use the restart — it re-issues the
failing request in place, so nothing before it in your code runs twice:

```lisp
(defparameter *fallbacks*
  (list (cons (make-provider :openai :model "gpt-4o") "gpt-4o")
        (cons (make-provider :ollama :model "mistral") "mistral")))

(defun complete-with-fallback (messages)
  "Try the default provider, then each fallback, on network failure."
  (let ((remaining *fallbacks*))
    (handler-bind
        ((provider-network-error
           (lambda (c)
             (let ((next (pop remaining))
                   (r (find-restart 'use-fallback-provider c)))
               (when (and next r)
                 (format *error-output* "~&falling back to ~A~%"
                         (provider-name (car next)))
                 (invoke-restart r (car next) (cdr next)))))))
      (complete messages))))
```

`with-auto-recovery` expresses the same thing declaratively, with retries first:

```lisp
(with-auto-recovery (:max-retries 2 :fallback-providers *fallbacks*)
  (complete messages))
```

**Name the model in each entry** whenever the fallback is a different service. A
bare provider entry keeps the caller's model, which is right only when both
endpoints serve the same one.

## Circuit Breaker Pattern

Stop attempting requests to a provider that keeps failing:

```lisp
(defclass circuit-breaker ()
  ((failures    :initform 0   :accessor breaker-failures)
   (threshold   :initarg :threshold  :initform 5   :reader breaker-threshold)
   (reset-time  :initarg :reset-time :initform 300 :reader breaker-reset-time)
   (last-failure :initform nil :accessor breaker-last-failure)
   (state       :initform :closed :accessor breaker-state)))

(defun breaker-open-p (breaker)
  "Open means blocking — the circuit has tripped."
  (eq (breaker-state breaker) :open))

(defun record-failure (breaker)
  (incf (breaker-failures breaker))
  (setf (breaker-last-failure breaker) (get-universal-time))
  (when (>= (breaker-failures breaker) (breaker-threshold breaker))
    (setf (breaker-state breaker) :open)))

(defun maybe-reset (breaker)
  "Re-close the circuit once the cooldown has passed."
  (when (and (breaker-open-p breaker)
             (> (- (get-universal-time) (breaker-last-failure breaker))
                (breaker-reset-time breaker)))
    (setf (breaker-failures breaker) 0
          (breaker-state breaker) :closed)))

(defun complete-with-breaker (messages breaker)
  "Complete unless the circuit is open; count transient failures against it."
  (maybe-reset breaker)
  (when (breaker-open-p breaker)
    (error "Circuit open — provider has failed ~D times"
           (breaker-failures breaker)))
  (handler-bind
      ((llm-provider-error
         (lambda (e) (when (transient-error-p e) (record-failure breaker)))))
    (complete messages)))
```

The handler is `handler-bind` and does not transfer control, so the condition
carries on to whatever established a restart or an outer handler. A
`handler-case` here would swallow it.

## Logging and Monitoring

`handler-bind` is right for logging specifically because it does *not* unwind —
you observe the error and let it continue to whoever can act on it:

```lisp
(defvar *recent-errors* '())

(defun log-provider-error (condition)
  (push (list :timestamp (get-universal-time)
              :type      (type-of condition)
              :message   (error-message condition))
        *recent-errors*)
  (format *error-output* "[ERROR] ~A: ~A~%"
          (type-of condition) (error-message condition)))

(defun complete-with-logging (messages)
  (handler-bind ((llm-provider-error #'log-provider-error))
    (complete messages)))
```

For request/response logging rather than error logging, use the hooks in
[Observability](observability.md) instead — they see successful calls too.

## Production Best Practices

1. **Handle at the right altitude.** `llm-provider-error` for logging;
   the specific types where the action differs.
2. **`handler-bind`, not `handler-case`**, wherever a restart might be invoked.
3. **Let `with-auto-recovery` do backoff** rather than hand-rolling it.
4. **Fail over on `provider-network-error`, not on every API error.** The
   fallback will not answer your 400 any better, and it will charge you to say so
   twice.
5. **Name the model when failing over across services.**
6. **Monitor error rates**, and alert on authentication failures — they do not
   resolve themselves.

```lisp
(defparameter *breaker* (make-instance 'circuit-breaker :threshold 5))

(defun complete-production (messages &key (breaker *breaker*))
  "Retries, failover, circuit breaking and logging, composed."
  (handler-bind ((llm-provider-error #'log-provider-error))
    (with-auto-recovery (:max-retries 3 :fallback-providers *fallbacks*)
      (complete-with-breaker messages breaker))))
```

---

**See Also**:
- [Local models and failover](local-models-and-failover.md) — the failover pattern end to end
- [Observability](observability.md) — hooks, metrics, request logging
- [Tutorial: Basic Completions](../tutorials/01-basics.md)
- [Tutorial: Advanced Features](../tutorials/03-advanced.md)
