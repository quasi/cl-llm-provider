---
type: scenario
name: streaming-with-callback
version: 0.1.0
feature: streaming
tags:
  - callback
  - convenience
---

# Streaming with Callback Function

## Context

User wants automatic chunk processing via callback instead of manual loop reading, enabling cleaner code for real-time display or logging.

## Scenario 1: Basic callback usage

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *messages* '((:role "user" :content "Tell me a short story")))
(setf *accumulated* "")
```

### Steps

#### 1. Define callback function

**Action**: Create callback to accumulate and display chunks
```lisp
(defun my-callback (chunk)
  (let ((delta (stream-chunk-delta chunk)))
    (setf *accumulated* (concatenate 'string *accumulated* delta))
    (format t "~A" delta)
    (force-output)))
```

#### 2. Create stream with callback

**Action**: Pass callback to complete-stream
```lisp
(complete-stream *messages*
                 :provider *provider*
                 :callback #'my-callback)
```

**Expected**:
- Callback invoked for each chunk
- Chunks display in real-time
- No manual loop needed
- Function returns after stream completes

#### 3. Verify accumulation

**Action**: Check accumulated content
```lisp
(length *accumulated*)
```

**Expected**:
- *accumulated* contains full response
- Length > 0
- Content is coherent text

### Verification

```
ASSERT (length *accumulated*) > 0
ASSERT callback was invoked multiple times
ASSERT final chunk had finish-reason
```

## Scenario 2: Callback with logging

### Setup

Same as Scenario 1

### Steps

#### 1. Define logging callback

**Action**: Create callback that logs chunk metadata
```lisp
(defun logging-callback (chunk)
  (log:info "Chunk ~D: ~S (~A chars, finish: ~A)"
            (stream-chunk-index chunk)
            (subseq (stream-chunk-delta chunk) 0 (min 20 (length (stream-chunk-delta chunk))))
            (length (stream-chunk-delta chunk))
            (stream-chunk-finish-reason chunk)))
```

#### 2. Stream with logging

**Action**: Use logging callback
```lisp
(complete-stream *messages*
                 :provider *provider*
                 :callback #'logging-callback)
```

**Expected**:
- Each chunk logged with metadata
- Logs show sequential indices
- Final log shows finish-reason
- No impact on stream functionality

### Verification

```
ASSERT logs contain entries for each chunk
ASSERT final log entry has finish-reason != NIL
```

## Scenario 3: Callback with error handling

### Setup

Callback that might raise errors

### Steps

#### 1. Define error-prone callback

**Action**: Create callback that validates chunks
```lisp
(defun validating-callback (chunk)
  (unless (>= (stream-chunk-index chunk) 0)
    (error "Invalid chunk index: ~D" (stream-chunk-index chunk)))
  (when (and (stream-chunk-finish-reason chunk)
             (not (member (stream-chunk-finish-reason chunk)
                         '(:stop :length :tool-calls))))
    (warn "Unexpected finish reason: ~A" (stream-chunk-finish-reason chunk))))
```

#### 2. Stream with validation

**Action**: Use validating callback
```lisp
(handler-case
    (complete-stream *messages*
                     :provider *provider*
                     :callback #'validating-callback)
  (error (e)
    (format t "Callback error: ~A~%" e)))
```

**Expected**:
- If validation passes, stream completes normally
- If validation fails, error propagates
- Stream processing stops on callback error

### Verification

```
ASSERT stream completes without error OR error is caught and reported
```

## Scenario 4: Callback for UI updates

### Setup

Simulated UI context

### Steps

#### 1. Define UI update callback

**Action**: Create callback that updates UI
```lisp
(defun ui-callback (chunk)
  (let ((delta (stream-chunk-delta chunk)))
    (when (> (length delta) 0)
      (append-to-text-widget delta))
    (when (stream-chunk-finish-reason chunk)
      (show-completion-indicator (stream-chunk-finish-reason chunk)))))
```

#### 2. Stream with UI updates

**Action**: Use UI callback
```lisp
(complete-stream *messages*
                 :provider *provider*
                 :callback #'ui-callback)
```

**Expected**:
- Text widget updates incrementally
- User sees real-time typing effect
- Completion indicator shows when done
- Smooth user experience

### Verification

```
ASSERT text-widget contains full response
ASSERT completion indicator visible
ASSERT UI updates occurred > 1 time
```

## Scenario 5: Multiple callbacks (composition)

### Setup

Need multiple actions per chunk

### Steps

#### 1. Compose callbacks

**Action**: Create composite callback
```lisp
(defun compose-callbacks (&rest callbacks)
  (lambda (chunk)
    (dolist (cb callbacks)
      (funcall cb chunk))))

(setf *composite* (compose-callbacks #'display-callback
                                    #'log-callback
                                    #'metrics-callback))
```

#### 2. Use composite callback

**Action**: Stream with multiple actions
```lisp
(complete-stream *messages*
                 :provider *provider*
                 :callback *composite*)
```

**Expected**:
- All callbacks invoked for each chunk
- No interference between callbacks
- Stream completes normally

### Verification

```
ASSERT display was updated
ASSERT logs were written
ASSERT metrics were recorded
```

## Performance Criteria

- Callback overhead < 1ms per chunk
- No blocking in callback (use async for heavy work)
- Callback errors propagate cleanly
- Memory usage proportional to chunk size, not total response
