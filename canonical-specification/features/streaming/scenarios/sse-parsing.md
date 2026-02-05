---
type: scenario
name: sse-parsing
version: 0.1.0
feature: streaming
covers:
  - streaming-protocol
tags:
  - happy-path
  - sse
  - provider-implementation
---

# Streaming Protocol - SSE Event Parsing

## Context

Provider implementations must parse Server-Sent Events (SSE) from streaming endpoints and convert them to normalized stream-chunk objects. Different providers use different SSE formats.

## Scenario 1: Parse OpenAI-style SSE events

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *raw-events* '("data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"index\":0}]}"
                     "data: {\"choices\":[{\"delta\":{\"content\":\" world\"},\"index\":0}]}"
                     "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\",\"index\":0}]}"
                     "data: [DONE]"))
```

### Steps

#### 1. Parse first chunk

**Action**: Parse delta with content
```lisp
(setf *chunk1* (parse-stream-chunk *provider*
                                   (subseq (first *raw-events*) 6) ; Remove "data: "
                                   0))
```

**Expected**:
- Returns stream-chunk object
- `stream-chunk-delta` = "Hello"
- `stream-chunk-index` = 0
- `stream-chunk-finish-reason` = nil

#### 2. Parse second chunk

**Action**: Parse next delta
```lisp
(setf *chunk2* (parse-stream-chunk *provider*
                                   (subseq (second *raw-events*) 6)
                                   1))
```

**Expected**:
- Delta = " world"
- Index = 1
- No finish reason

#### 3. Parse final chunk

**Action**: Parse completion chunk
```lisp
(setf *chunk3* (parse-stream-chunk *provider*
                                   (subseq (third *raw-events*) 6)
                                   2))
```

**Expected**:
- Delta = ""
- Finish reason = `:stop`
- Index = 2

#### 4. Parse done signal

**Action**: Parse termination
```lisp
(setf *result* (parse-stream-chunk *provider*
                                   (subseq (fourth *raw-events*) 6)
                                   3))
```

**Expected**:
- Returns `:done` symbol
- Signals end of stream

### Verification

```
ASSERT (stream-chunk-delta *chunk1*) == "Hello"
ASSERT (stream-chunk-delta *chunk2*) == " world"
ASSERT (stream-chunk-finish-reason *chunk3*) == :stop
ASSERT *result* == :done
```

## Scenario 2: Parse Anthropic-style typed events

### Setup

```lisp
(setf *provider* (make-provider :anthropic))
(setf *events* '(("message_start" "{\"type\":\"message_start\",\"message\":{\"id\":\"msg_123\"}}")
                 ("content_block_start" "{\"type\":\"content_block_start\",\"index\":0}")
                 ("content_block_delta" "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}")
                 ("content_block_delta" "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" world\"}}")
                 ("content_block_stop" "{\"type\":\"content_block_stop\",\"index\":0}")
                 ("message_stop" "{\"type\":\"message_stop\"}")))
```

### Steps

#### 1. Parse message_start

**Action**: Parse initialization event
```lisp
(setf *result1* (parse-stream-event-type *provider*
                                         "message_start"
                                         (second (first *events*))
                                         0))
```

**Expected**:
- Returns `nil` (metadata event, no chunk)
- Provider stores message ID internally

#### 2. Parse content_block_start

**Action**: Parse block start
```lisp
(setf *result2* (parse-stream-event-type *provider*
                                         "content_block_start"
                                         (second (second *events*))
                                         0))
```

**Expected**:
- Returns `nil` (no content delta yet)
- Provider initializes block tracking

#### 3. Parse first content_block_delta

**Action**: Parse content delta
```lisp
(setf *chunk1* (parse-stream-event-type *provider*
                                        "content_block_delta"
                                        (second (third *events*))
                                        0))
```

**Expected**:
- Returns stream-chunk object
- Delta = "Hello"
- Index = 0

#### 4. Parse second content_block_delta

**Action**: Parse next delta
```lisp
(setf *chunk2* (parse-stream-event-type *provider*
                                        "content_block_delta"
                                        (second (fourth *events*))
                                        1))
```

**Expected**:
- Delta = " world"
- Index = 1

#### 5. Parse message_stop

**Action**: Parse termination
```lisp
(setf *done* (parse-stream-event-type *provider*
                                      "message_stop"
                                      (second (sixth *events*))
                                      2))
```

**Expected**:
- Returns `:done`
- Signals stream complete

### Verification

```
ASSERT (stream-chunk-delta *chunk1*) == "Hello"
ASSERT (stream-chunk-delta *chunk2*) == " world"
ASSERT *done* == :done
```

## Scenario 3: Handle malformed events

### Setup

```lisp
(setf *provider* (make-provider :openai))
```

### Steps

#### 1. Parse invalid JSON

**Action**: Parse broken JSON
```lisp
(handler-case
    (parse-stream-chunk *provider*
                       "{invalid json}"
                       0)
  (json-parse-error (e)
    :json-error))
```

**Expected**:
- Error caught
- Returns `nil` (skip event)
- Logs warning
- Stream continues

#### 2. Parse empty event

**Action**: Parse empty data
```lisp
(parse-stream-chunk *provider* "" 0)
```

**Expected**:
- Returns `nil`
- No error raised
- Event skipped

#### 3. Parse unknown event type (Anthropic)

**Action**: Parse unrecognized type
```lisp
(parse-stream-event-type *provider*
                        "unknown_event_type"
                        "{\"type\":\"unknown_event_type\"}"
                        0)
```

**Expected**:
- Returns `nil`
- Event ignored
- No error

### Verification

```
ASSERT malformed JSON returns nil
ASSERT empty events return nil
ASSERT unknown events return nil
ASSERT stream continues after errors
```

## Scenario 4: Accumulate tool calls across chunks

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *events* '("data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"name\":\"get\"}}]}}]}"
                 "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"loc\"}}]}}]}"
                 "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"ation\\\"\"}}]}}]}"
                 "data: {\"choices\":[{\"finish_reason\":\"tool_calls\"}]}"))
```

### Steps

#### 1. Parse first tool call fragment

**Action**: Parse tool name
```lisp
(setf *chunk1* (parse-stream-chunk *provider*
                                   (subseq (first *events*) 6)
                                   0))
```

**Expected**:
- Chunk contains partial tool call
- Provider accumulates fragment

#### 2. Parse argument fragments

**Action**: Parse incremental arguments
```lisp
(setf *chunk2* (parse-stream-chunk *provider*
                                   (subseq (second *events*) 6)
                                   1))
(setf *chunk3* (parse-stream-chunk *provider*
                                   (subseq (third *events*) 6)
                                   2))
```

**Expected**:
- Provider accumulates JSON fragments
- Chunks may contain partial tool data

#### 3. Parse completion

**Action**: Parse final chunk with finish reason
```lisp
(setf *chunk4* (parse-stream-chunk *provider*
                                   (subseq (fourth *events*) 6)
                                   3))
```

**Expected**:
- Finish reason = `:tool-calls`
- Provider assembles complete tool call from fragments
- Tool call available in final chunk

### Verification

```
ASSERT final chunk has finish-reason :tool-calls
ASSERT tool call arguments properly assembled
ASSERT complete JSON parsed successfully
```

## Scenario 5: SSE event boundary detection

### Setup

```lisp
(setf *raw-stream* "data: chunk1\n\ndata: chunk2\n\nevent: custom\ndata: chunk3\n\n")
```

### Steps

#### 1. Parse first event

**Action**: Read until empty line
```lisp
(setf *event1* (read-sse-event *raw-stream*))
```

**Expected**:
- Returns `(:data "chunk1")`
- Stream position advanced

#### 2. Parse second event

**Action**: Read next event
```lisp
(setf *event2* (read-sse-event *raw-stream*))
```

**Expected**:
- Returns `(:data "chunk2")`
- Boundary detected correctly

#### 3. Parse typed event

**Action**: Read event with type
```lisp
(setf *event3* (read-sse-event *raw-stream*))
```

**Expected**:
- Returns `(:event "custom" :data "chunk3")`
- Event type preserved

### Verification

```
ASSERT events separated correctly
ASSERT empty lines trigger parsing
ASSERT event types preserved
```

## Scenario 6: Connection handling

### Setup

```lisp
(setf *provider* (make-provider :openai))
```

### Steps

#### 1. Handle connection drop mid-stream

**Action**: Simulate dropped connection
```lisp
(handler-case
    (loop for chunk = (read-stream-chunk *interrupted-stream*)
          until (eq chunk :done)
          collect chunk)
  (stream-connection-closed (e)
    (format t "Connection dropped after ~D chunks~%"
            (stream-error-chunks-received e))
    :connection-lost))
```

**Expected**:
- Signals `stream-connection-closed`
- Error includes chunks received
- Partial results available

#### 2. Handle read timeout

**Action**: Set timeout on chunk read
```lisp
(handler-case
    (read-stream-chunk *slow-stream* :timeout 5)
  (stream-timeout (e)
    :timeout))
```

**Expected**:
- Times out after 5 seconds
- Signals `stream-timeout`
- Stream can be closed gracefully

### Verification

```
ASSERT connection errors signaled
ASSERT partial data accessible
ASSERT timeouts handled cleanly
```

## Scenario 7: State machine tracking

### Setup

```lisp
(defclass stateful-stream ()
  ((state :initform :connecting :accessor stream-state)
   (buffer :initform "" :accessor stream-buffer)
   (index :initform 0 :accessor stream-index)))
```

### Steps

#### 1. Initialize stream

**Action**: Create stream
```lisp
(setf *stream* (make-instance 'stateful-stream))
```

**Expected**:
- State = `:connecting`
- Buffer empty
- Index = 0

#### 2. Transition to streaming

**Action**: Receive first chunk
```lisp
(process-chunk *stream* "data: chunk1\n\n")
(stream-state *stream*)
```

**Expected**:
- State = `:streaming`
- Index incremented

#### 3. Handle completion

**Action**: Receive done signal
```lisp
(process-chunk *stream* "data: [DONE]\n\n")
(stream-state *stream*)
```

**Expected**:
- State = `:complete`
- No further chunks accepted

#### 4. Attempt read after done

**Action**: Try to read completed stream
```lisp
(read-stream-chunk *stream*)
```

**Expected**:
- Returns `nil`
- No error
- State remains `:complete`

### Verification

```
ASSERT state transitions: connecting → streaming → complete
ASSERT completed streams return nil on read
ASSERT state machine enforced
```

## Performance Criteria

- Event parsing: < 1ms per chunk
- JSON parsing: < 5ms for typical chunk
- State updates: < 0.1ms
- Buffer management: O(1) for chunks < 1KB
- Connection overhead: ~100-200ms initial setup

## Error Handling Invariants

- Malformed JSON → skip event, log warning, continue
- Unknown event types → ignore, continue
- Connection errors → signal condition with partial data
- Timeout → signal timeout condition, allow cleanup
- Invalid finish reasons → normalize to `:stop`
