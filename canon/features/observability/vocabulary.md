# Observability Vocabulary

**Status**: Extracted from src/observability.lisp and docs/how-to/observability.md
**Confidence**: High
**Last Updated**: 2026-01-16

Feature-specific terms for the observability subsystem.

---

## Core Concepts

### Hooks

A container structure (`hooks`) holding callback functions for lifecycle events.

**Structure**:
```lisp
(defstruct hooks
  (before-request nil :type list)   ; List of callbacks
  (after-response nil :type list)
  (on-error nil :type list)
  (on-stream-chunk nil :type list))
```

**Code Location**: `src/observability.lisp:8-19`

---

### Hook Type

One of four lifecycle event types that can be observed:

| Hook Type | When Fired | Signature |
|-----------|------------|-----------|
| `:before-request` | Before API call | `(provider model messages)` |
| `:after-response` | After successful response | `(provider model response timing)` |
| `:on-error` | On error condition | `(provider model error)` |
| `:on-stream-chunk` | Each streaming chunk | `(provider model chunk)` |

---

### Global Hooks

The `*global-hooks*` special variable, when non-nil, provides hooks applied to all requests automatically.

**Usage**:
```lisp
(setf *global-hooks* (make-logging-hooks))
```

**Scope**: Session-wide, affects all `complete` and `complete-stream` calls.

---

### Per-Request Hooks

Hooks passed via the `:hooks` parameter to individual API calls.

**Precedence**: Per-request hooks override global hooks (not additive by default).

---

## Hook Operations

### add-hook

Function to register a callback for a specific hook type.

**Signature**:
```lisp
(add-hook hooks hook-type function) → hooks
```

**Behavior**: Pushes function onto the hook list (LIFO order).

---

### remove-hook

Function to unregister a callback.

**Signature**:
```lisp
(remove-hook hooks hook-type function) → hooks
```

---

### invoke-hooks

Internal function that fires all callbacks for a hook type.

**Signature**:
```lisp
(invoke-hooks hooks hook-type &rest args)
```

**Error Handling**: Catches and logs errors in hooks; does not propagate.

---

## Built-in Hooks

### Logging Hooks

Pre-configured hooks created by `make-logging-hooks`.

**Parameters**:
- `:stream` - Output stream (default: `*standard-output*`)
- `:level` - Log level (`:debug`, `:info`, `:warn`)

**Behavior by level**:
| Level | Shows |
|-------|-------|
| `:debug` | Full messages and content |
| `:info` | Request summary and timing |
| `:warn` | Errors only |

---

## Cross-Reference

| Term | Defined In | Relates To |
|------|-----------|------------|
| Hooks | observability | complete, complete-stream |
| Hook Type | observability | Request lifecycle |
| Global Hooks | observability | *global-hooks* variable |
