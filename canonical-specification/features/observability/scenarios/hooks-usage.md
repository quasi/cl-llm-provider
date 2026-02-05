---
type: scenario
name: hooks-usage
version: 0.1.0
feature: observability
covers:
  - hooks-api
tags:
  - happy-path
  - observability
---

# Hooks API - Observability and Monitoring

## Context

Application needs to monitor LLM API calls for logging, metrics, debugging, and auditing without modifying core completion logic.

## Scenario 1: Basic request/response logging

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *messages* '((:role "user" :content "What is Common Lisp?")))
(setf *hooks* (make-hooks))
```

### Steps

#### 1. Add before-request hook

**Action**: Register hook to log before request
```lisp
(add-hook *hooks* :before-request
          (lambda (provider model messages)
            (format t "[~A] Request to ~A ~A (~D messages)~%"
                    (format-timestamp (get-universal-time))
                    (provider-name provider)
                    model
                    (length messages))))
```

**Expected**:
- Hook added to hooks structure
- No immediate execution (hooks are lazy)

#### 2. Add after-response hook

**Action**: Register hook to log after success
```lisp
(add-hook *hooks* :after-response
          (lambda (provider model response timing)
            (format t "[~A] Response from ~A in ~,2Fs (~D tokens)~%"
                    (format-timestamp (get-universal-time))
                    (provider-name provider)
                    timing
                    (getf (response-usage response) :total-tokens))))
```

**Expected**:
- Hook registered
- Will be called after successful completion

#### 3. Make completion with hooks

**Action**: Call complete with hooks
```lisp
(complete *messages*
          :provider *provider*
          :hooks *hooks*)
```

**Expected**:
- Before-request hook invoked before API call
- After-response hook invoked after parsing
- Logs appear in order
- Completion works normally

### Verification

```
ASSERT before-request logged before API call
ASSERT after-response logged after completion
ASSERT logs contain timestamp, provider, timing, tokens
```

## Scenario 2: Error handling hooks

### Setup

```lisp
(setf *hooks* (make-hooks))
(setf *error-count* 0)
```

### Steps

#### 1. Add error hook

**Action**: Register error handler
```lisp
(add-hook *hooks* :on-error
          (lambda (provider model error)
            (incf *error-count*)
            (format t "[ERROR] ~A on ~A: ~A~%"
                    (provider-name provider)
                    model
                    (princ-to-string error))))
```

#### 2. Trigger error condition

**Action**: Cause API error (invalid key)
```lisp
(handler-case
    (complete *messages*
             :provider (make-provider :openai :api-key "invalid")
             :hooks *hooks*)
  (provider-authentication-error (e)
    :caught))
```

**Expected**:
- Error hook invoked
- Error logged
- `*error-count*` incremented
- Error still propagates to handler-case

### Verification

```
ASSERT *error-count* == 1
ASSERT error hook logged error details
ASSERT error propagates to caller
```

## Scenario 3: Streaming with chunk hooks

### Setup

```lisp
(setf *hooks* (make-hooks))
(setf *chunk-count* 0)
```

### Steps

#### 1. Add stream chunk hook

**Action**: Register chunk callback
```lisp
(add-hook *hooks* :on-stream-chunk
          (lambda (provider model chunk)
            (incf *chunk-count*)
            (format t "Chunk ~D: ~S~%"
                    (stream-chunk-index chunk)
                    (stream-chunk-delta chunk))))
```

#### 2. Stream with hooks

**Action**: Use complete-stream with hooks
```lisp
(let ((stream (complete-stream *messages*
                               :provider *provider*
                               :hooks *hooks*)))
  (loop for chunk = (read-stream-chunk stream)
        until (eq chunk :done)
        collect chunk))
```

**Expected**:
- Chunk hook invoked for each chunk
- `*chunk-count*` increments per chunk
- Chunks logged in real-time
- Streaming works normally

### Verification

```
ASSERT *chunk-count* > 1
ASSERT all chunks logged
ASSERT streaming completes successfully
```

## Scenario 4: Multiple hooks of same type

### Setup

```lisp
(setf *hooks* (make-hooks))
(setf *log1* nil)
(setf *log2* nil)
```

### Steps

#### 1. Add first hook

**Action**: Register first logger
```lisp
(add-hook *hooks* :before-request
          (lambda (provider model messages)
            (push :log1 *log1*)))
```

#### 2. Add second hook

**Action**: Register second logger
```lisp
(add-hook *hooks* :before-request
          (lambda (provider model messages)
            (push :log2 *log2*)))
```

#### 3. Make completion

**Action**: Trigger hooks
```lisp
(complete *messages* :provider *provider* :hooks *hooks*)
```

**Expected**:
- Both hooks invoked
- LIFO order: log2 called before log1
- Both logs populated

### Verification

```
ASSERT *log1* contains :log1
ASSERT *log2* contains :log2
ASSERT both hooks executed
```

## Scenario 5: Remove hook

### Setup

```lisp
(setf *hooks* (make-hooks))
(setf *counter* 0)

(defun my-hook (provider model messages)
  (incf *counter*))

(add-hook *hooks* :before-request #'my-hook)
```

### Steps

#### 1. Verify hook is registered

**Action**: Call complete
```lisp
(complete *messages* :provider *provider* :hooks *hooks*)
```

**Expected**:
- `*counter*` = 1
- Hook executed

#### 2. Remove hook

**Action**: Unregister hook
```lisp
(remove-hook *hooks* :before-request #'my-hook)
```

**Expected**:
- Hook removed from list
- Future completions don't call it

#### 3. Verify removal

**Action**: Call complete again
```lisp
(complete *messages* :provider *provider* :hooks *hooks*)
```

**Expected**:
- `*counter*` still = 1 (not incremented)
- Hook not called

### Verification

```
ASSERT *counter* == 1 after removal
ASSERT hook not in hooks list
```

## Scenario 6: Global hooks

### Setup

```lisp
(setf *request-log* nil)
(setf *global-hooks* (make-hooks))
(add-hook *global-hooks* :before-request
          (lambda (provider model messages)
            (push (list :provider (provider-name provider)
                       :model model
                       :timestamp (get-universal-time))
                  *request-log*)))
```

### Steps

#### 1. Make completion without explicit hooks

**Action**: Call complete without :hooks parameter
```lisp
(complete *messages* :provider *provider*)
```

**Expected**:
- Global hooks used automatically
- Request logged to `*request-log*`

#### 2. Override with local hooks

**Action**: Provide explicit hooks
```lisp
(let ((local-hooks (make-hooks)))
  (complete *messages* :provider *provider* :hooks local-hooks))
```

**Expected**:
- Global hooks ignored
- Local hooks used instead
- No entry added to `*request-log*`

#### 3. Disable global hooks

**Action**: Set to nil
```lisp
(setf *global-hooks* nil)
(complete *messages* :provider *provider*)
```

**Expected**:
- No hooks invoked
- Completion works without hooks

### Verification

```
ASSERT *request-log* populated with global hooks
ASSERT local hooks override global
ASSERT nil global hooks = no hooks
```

## Scenario 7: Hook error isolation

### Setup

```lisp
(setf *hooks* (make-hooks))
(setf *good-hook-called* nil)
```

### Steps

#### 1. Add failing hook

**Action**: Register hook that errors
```lisp
(add-hook *hooks* :before-request
          (lambda (provider model messages)
            (error "Hook error!")))
```

#### 2. Add good hook

**Action**: Register working hook
```lisp
(add-hook *hooks* :before-request
          (lambda (provider model messages)
            (setf *good-hook-called* t)))
```

#### 3. Make completion

**Action**: Trigger hooks
```lisp
(complete *messages* :provider *provider* :hooks *hooks*)
```

**Expected**:
- Failing hook errors caught and logged as warning
- Error does NOT propagate to caller
- Good hook still executes
- Completion succeeds

### Verification

```
ASSERT *good-hook-called* == t
ASSERT completion succeeds despite hook error
ASSERT warning logged for hook error
```

## Scenario 8: Built-in logging hooks

### Setup

```lisp
(setf *log-output* (make-string-output-stream))
```

### Steps

#### 1. Create logging hooks

**Action**: Use factory function
```lisp
(setf *hooks* (make-logging-hooks :stream *log-output*
                                   :level :info))
```

**Expected**:
- Hooks structure created
- Configured for info level logging

#### 2. Make completion

**Action**: Complete with logging
```lisp
(complete *messages* :provider *provider* :hooks *hooks*)
```

**Expected**:
- Request logged
- Response logged
- Output written to stream

#### 3. Check log output

**Action**: Get logged content
```lisp
(get-output-stream-string *log-output*)
```

**Expected**:
- Contains "LLM Request"
- Contains "LLM Response"
- Contains timing information

### Verification

```
ASSERT log contains request info
ASSERT log contains response timing
ASSERT log contains token counts
```

## Performance Criteria

- Hook invocation overhead: < 1ms per hook
- Hook errors caught and logged without breaking flow
- Multiple hooks: O(n) where n = number of hooks
- No memory leaks on repeated add/remove

## Safety Invariants

- **Error isolation**: Hook errors NEVER break main request flow
- **Order guarantees**: Hooks invoked in LIFO order
- **No side effects**: Hooks cannot modify request/response data
- **Audit trail**: All invocations logged when requested
