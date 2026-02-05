---
type: contract
name: hooks-api
version: 1.0.0
status: stable
feature: observability
source: src/observability.lisp
---

# Hooks API Contract

This contract defines the observability hook system for monitoring LLM API calls.

## Overview

The hooks system provides a non-intrusive way to observe request/response lifecycle events. Hooks are callbacks registered for specific event types and invoked automatically during API calls.

## Data Structure

### hooks

**Constructor**:
```lisp
(make-hooks) → hooks
```

**Slots**:

| Slot | Type | Default | Description |
|------|------|---------|-------------|
| `before-request` | `list` | `nil` | Callbacks before API call |
| `after-response` | `list` | `nil` | Callbacks after success |
| `on-error` | `list` | `nil` | Callbacks on error |
| `on-stream-chunk` | `list` | `nil` | Callbacks per stream chunk |

**Accessors**:
- `hooks-before-request`
- `hooks-after-response`
- `hooks-on-error`
- `hooks-on-stream-chunk`

### JSON Schema: Hooks Structure

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "before_request": {
      "type": "array",
      "items": {"type": "string", "description": "Function reference"}
    },
    "after_response": {
      "type": "array",
      "items": {"type": "string", "description": "Function reference"}
    },
    "on_error": {
      "type": "array",
      "items": {"type": "string", "description": "Function reference"}
    },
    "on_stream_chunk": {
      "type": "array",
      "items": {"type": "string", "description": "Function reference"}
    }
  }
}
```

---

## Functions

### add-hook

**Signature**:
```lisp
(add-hook hooks hook-type function) → hooks
```

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `hooks` | `hooks` | Yes | Hooks structure |
| `hook-type` | `keyword` | Yes | One of `:before-request`, `:after-response`, `:on-error`, `:on-stream-chunk` |
| `function` | `function` | Yes | Callback function |

**Returns**: The hooks structure (for chaining)

**Behavior**: Pushes function onto the front of the hook list (LIFO order).

**Example**:
```lisp
(let ((hooks (make-hooks)))
  (add-hook hooks :before-request
            (lambda (provider model messages)
              (format t "Calling ~A~%" model)))
  (add-hook hooks :after-response
            (lambda (provider model response timing)
              (format t "Response in ~,2Fs~%" timing)))
  hooks)
```

---

### remove-hook

**Signature**:
```lisp
(remove-hook hooks hook-type function) → hooks
```

**Parameters**: Same as `add-hook`

**Returns**: The hooks structure

**Behavior**: Removes function from the hook list using `remove` (identity comparison).

---

### invoke-hooks

**Signature**:
```lisp
(invoke-hooks hooks hook-type &rest args)
```

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `hooks` | `hooks` | Yes | Hooks structure |
| `hook-type` | `keyword` | Yes | Hook type to invoke |
| `args` | `&rest` | No | Arguments passed to callbacks |

**Behavior**:
1. Gets the list of callbacks for `hook-type`
2. Iterates through list, calling each with `args`
3. Catches and logs errors; does NOT propagate

**Error Handling**:
```lisp
(handler-case
    (apply hook args)
  (error (e)
    (warn "Observability hook error: ~A" e)))
```

**Invariant**: Hook errors never break the main request flow.

---

## Callback Signatures

### :before-request

```lisp
(lambda (provider model messages) ...)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `provider` | `llm-provider` | Provider instance |
| `model` | `string` | Model identifier |
| `messages` | `list` | Message list |

**Invocation Point**: Before `send-completion-request` or `send-streaming-request`

---

### :after-response

```lisp
(lambda (provider model response timing) ...)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `provider` | `llm-provider` | Provider instance |
| `model` | `string` | Model identifier |
| `response` | `completion-response` | Parsed response |
| `timing` | `number` | Request duration in seconds |

**Invocation Point**: After successful response parsing

---

### :on-error

```lisp
(lambda (provider model error) ...)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `provider` | `llm-provider` | Provider instance |
| `model` | `string` | Model identifier |
| `error` | `condition` | Error condition |

**Invocation Point**: When an error condition is signaled

---

### :on-stream-chunk

```lisp
(lambda (provider model chunk) ...)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `provider` | `llm-provider` | Provider instance |
| `model` | `string` | Model identifier |
| `chunk` | `stream-chunk` | Parsed chunk |

**Invocation Point**: After each stream chunk is parsed

---

## Global Hooks

### *global-hooks*

**Type**: `hooks` or `nil`

**Default**: `nil`

**Description**: When non-nil, these hooks are applied to all requests that don't specify explicit `:hooks`.

**Usage**:
```lisp
;; Set global hooks
(setf *global-hooks* (make-logging-hooks :level :info))

;; All requests now logged
(complete messages :provider provider)

;; Disable
(setf *global-hooks* nil)
```

---

## Built-in Hook Factories

### make-logging-hooks

**Signature**:
```lisp
(make-logging-hooks &key stream level) → hooks
```

**Parameters**:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `stream` | `stream` | `*standard-output*` | Output stream |
| `level` | `keyword` | `:info` | Log level |

**Returns**: Configured hooks structure

**Log Levels**:

| Level | Before Request | After Response |
|-------|----------------|----------------|
| `:debug` | Provider, model, message count, full messages | Timing, tokens, truncated content |
| `:info` | Provider, model, message count | Timing, tokens |
| `:warn` | Nothing | Nothing |

All levels log errors via `:on-error`.

**Example Output** (`:info`):
```
[14:23:45] LLM Request: OpenAI gpt-4o-mini (1 messages)
[14:23:46] LLM Response: 0.42s, 12 tokens
```

---

## Invariants

### INV-HOOKS-001: Hook Isolation

Hook errors are isolated and do not propagate to the main request flow.

**Check**:
```lisp
;; Even with failing hook, request completes
(let ((hooks (make-hooks)))
  (add-hook hooks :before-request
            (lambda (&rest args) (error "Hook error!")))
  (complete messages :hooks hooks))  ; Should succeed with warning
```

---

### INV-HOOKS-002: Callback Order

Hooks are invoked in LIFO order (most recently added first).

**Check**:
```lisp
(let ((calls nil)
      (hooks (make-hooks)))
  (add-hook hooks :before-request (lambda (&rest args) (push 1 calls)))
  (add-hook hooks :before-request (lambda (&rest args) (push 2 calls)))
  ;; After invoke: calls = (1 2) meaning 2 was called first
  )
```

---

## Integration Points

### complete

The `complete` function accepts `:hooks` parameter:

```lisp
(complete messages &key hooks ...) → response
```

When `hooks` is provided, `invoke-hooks` is called at appropriate lifecycle points.

### complete-stream

The `complete-stream` function accepts `:hooks` parameter:

```lisp
(complete-stream messages &key hooks on-chunk ...) → stream
```

The `:on-stream-chunk` hooks are invoked for each chunk.

---

## See Also

- [vocabulary.md](../vocabulary.md) - Observability terms
- [core-api/contracts/complete.md](../../core-api/contracts/complete.md) - complete function
- [streaming contracts](../../streaming/) - Streaming integration
