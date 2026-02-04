---
type: scenario
name: basic-streaming
version: 0.1.0
feature: streaming
tags:
  - happy-path
  - core-functionality
---

# Basic Streaming Completion

## Context

User wants to receive LLM responses incrementally as they're generated, enabling real-time display and lower perceived latency.

## Scenario 1: Stream simple completion

### Setup

```lisp
(setf *provider* (make-provider :openai :api-key "test-key"))
(setf *messages* '((:role "user" :content "Count to 5")))
```

### Steps

#### 1. Create streaming completion

**Action**: Call `complete-stream`
```lisp
(setf *stream* (complete-stream *messages* :provider *provider* :model "gpt-4o"))
```

**Expected**:
- Returns stream object
- No HTTP error
- Stream is in CREATED state

#### 2. Read first chunk

**Action**: Read chunk from stream
```lisp
(setf *chunk1* (read-stream-chunk *stream*))
```

**Expected**:
- Returns stream-chunk object
- `(stream-chunk-delta *chunk1*)` is non-empty string
- `(stream-chunk-index *chunk1*)` = 0
- `(stream-chunk-finish-reason *chunk1*)` = NIL

#### 3. Read subsequent chunks

**Action**: Read chunks in loop
```lisp
(loop for chunk = (read-stream-chunk *stream*)
      until (eq chunk :done)
      collect chunk into chunks
      finally (return chunks))
```

**Expected**:
- Multiple chunks returned
- Each chunk has sequential index (0, 1, 2, ...)
- Final chunk has finish-reason (typically `:stop`)
- Concatenated deltas form complete response

#### 4. Verify completion

**Action**: Check final chunk
```lisp
(let ((last-chunk (car (last *chunks*))))
  (stream-chunk-finish-reason last-chunk))
```

**Expected**:
- Finish reason is `:stop`
- Usage statistics present in final chunk
- Total prompt tokens > 0
- Total completion tokens > 0

### Verification

```
ASSERT stream != NIL
ASSERT (length chunks) > 1
ASSERT (every (lambda (c) (>= (stream-chunk-index c) 0)) chunks)
ASSERT (stream-chunk-finish-reason (car (last chunks))) == :stop
ASSERT (concatenate 'string (mapcar #'stream-chunk-delta chunks)) != ""
```

## Scenario 2: Stream with max-tokens limit

### Setup

Same as Scenario 1

### Steps

#### 1. Create stream with token limit

**Action**: Call with max-tokens
```lisp
(setf *stream* (complete-stream *messages*
                                :provider *provider*
                                :max-tokens 10))
```

#### 2. Read all chunks

**Action**: Read until done
```lisp
(loop for chunk = (read-stream-chunk *stream*)
      until (eq chunk :done)
      collect chunk)
```

**Expected**:
- Stream completes
- Final chunk has finish-reason `:length` (stopped due to token limit)
- Completion tokens ≈ 10

### Verification

```
ASSERT (stream-chunk-finish-reason (car (last chunks))) == :length
ASSERT (getf (stream-chunk-usage (car (last chunks))) :completion-tokens) <= 10
```

## Scenario 3: Empty stream response

### Setup

Messages that might produce empty response

### Steps

#### 1. Create stream

**Action**: Stream with potential empty response
```lisp
(setf *stream* (complete-stream '((:role "user" :content ""))
                                :provider *provider*))
```

#### 2. Read chunks

**Action**: Read all chunks
```lisp
(loop for chunk = (read-stream-chunk *stream*)
      until (eq chunk :done)
      collect chunk)
```

**Expected**:
- At least one chunk returned (even if empty delta)
- Final chunk has finish-reason
- No errors raised

### Verification

```
ASSERT chunks != NIL
ASSERT (stream-chunk-finish-reason (car (last chunks))) != NIL
```

## Error Scenarios

### Scenario 4: Invalid model

**Action**: Create stream with unknown model
```lisp
(handler-case
    (complete-stream *messages* :provider *provider* :model "invalid-model-xxx")
  (error (e) e))
```

**Expected**:
- Error signaled before stream created
- Error type: `api-error` or `model-not-found`
- No partial stream returned

### Scenario 5: Network interruption

**Action**: Simulate connection drop mid-stream
```lisp
(handler-case
    (loop for chunk = (read-stream-chunk *interrupted-stream*)
          until (eq chunk :done)
          collect chunk)
  (stream-error (e) e))
```

**Expected**:
- `stream-error` condition signaled
- Error message indicates connection issue
- Partial chunks collected before error

## Performance Criteria

- First chunk arrives within 500ms
- Chunk frequency: 10-50 chunks/second
- Total streaming overhead < 10% vs non-streaming
- Memory usage: O(current_chunk), not O(total_response)
