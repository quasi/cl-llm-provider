---
type: property
name: hook-safety
version: 1.0.0
status: stable
feature: observability
source: src/observability.lisp:59-73
---

# Hook Safety Properties

Properties ensuring the observability hook system doesn't compromise main functionality.

## PROP-HOOKS-001: Error Isolation

**Statement**: Errors in hook callbacks do not propagate to the calling code.

**Formal**:
```
∀ hook ∈ hooks, ∀ error:
  (error-in hook) ⇒ (warn logged) ∧ ¬(error propagated)
```

**Implementation**:
```lisp
(dolist (hook hook-list)
  (handler-case
      (apply hook args)
    (error (e)
      ;; Log but don't propagate
      (warn "Observability hook error: ~A" e))))
```

**Rationale**: Observability is secondary to core functionality. A failing logging hook should never break a production API call.

**Verification**:
```lisp
(let ((hooks (make-hooks)))
  (add-hook hooks :before-request
            (lambda (&rest args)
              (error "Intentional hook failure")))
  ;; This should complete successfully (with a warning)
  (complete '((:role "user" :content "test"))
            :provider provider
            :hooks hooks))
```

---

## PROP-HOOKS-002: Non-Blocking Semantics

**Statement**: Hook invocation is synchronous but non-blocking to the extent that hooks themselves are non-blocking.

**Implication**: The library guarantees it won't add latency beyond what hook code itself takes. Users are responsible for keeping hooks fast.

**Best Practice**:
```lisp
;; BAD: Blocking operation in hook
(add-hook hooks :after-response
          (lambda (&rest args)
            (http-post "https://slow-server.com/log" args)))

;; GOOD: Async operation
(add-hook hooks :after-response
          (lambda (&rest args)
            (bt:make-thread
              (lambda () (http-post "..." args)))))
```

---

## PROP-HOOKS-003: Callback Argument Immutability

**Statement**: Hooks receive read-only views of arguments; mutations do not affect subsequent hooks or main flow.

**Rationale**: Hooks observe but do not control. This prevents hooks from interfering with each other or with the main request processing.

**Note**: This is a convention, not enforced by the type system. Arguments are passed by reference but should be treated as immutable.

---

## PROP-HOOKS-004: Global/Local Precedence

**Statement**: Explicit `:hooks` parameter takes precedence over `*global-hooks*`.

**Formal**:
```
(complete messages :hooks local-hooks)
  ⇒ invokes local-hooks
  ⇒ does NOT invoke *global-hooks*
```

**Rationale**: Allows per-request customization without interference from global configuration.

**Workaround for combining**:
```lisp
(defun merge-hooks (global local)
  "Combine global and local hooks."
  (let ((merged (make-hooks)))
    (dolist (h (hooks-before-request global))
      (push h (hooks-before-request merged)))
    (dolist (h (hooks-before-request local))
      (push h (hooks-before-request merged)))
    ;; ... repeat for other hook types
    merged))
```

---

## PROP-HOOKS-005: Thread Safety

**Statement**: The hooks structure is not inherently thread-safe, but `invoke-hooks` is safe for concurrent reads.

**Guideline**:
- Do not modify hooks structure after sharing across threads
- Create hooks structure before spawning threads
- Each thread can safely invoke the same hooks structure

**Pattern**:
```lisp
;; Safe: Create once, use from multiple threads
(let ((hooks (make-logging-hooks)))
  (bt:make-thread (lambda () (complete msgs1 :hooks hooks)))
  (bt:make-thread (lambda () (complete msgs2 :hooks hooks))))

;; Unsafe: Modifying while using
(let ((hooks (make-logging-hooks)))
  (bt:make-thread (lambda () (complete msgs :hooks hooks)))
  (add-hook hooks :on-error ...))  ; Race condition!
```

---

## Verification Checklist

```
[ ] Hook errors logged as warnings, not propagated
[ ] Request completes successfully even with failing hooks
[ ] Hooks invoked in LIFO order (most recent first)
[ ] Explicit :hooks overrides *global-hooks*
[ ] Hook callbacks receive correct arguments for each type
[ ] make-logging-hooks produces working hooks at all levels
```

---

## See Also

- [hooks-api.md](../contracts/hooks-api.md) - Hooks API contract
- [core invariants](../../../core/foundation/invariants.md) - System-wide invariants
