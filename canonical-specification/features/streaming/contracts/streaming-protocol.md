---
type: contract
name: streaming-protocol
version: 0.1.0
status: draft
feature: streaming
---

# Streaming Protocol Contract

This contract defines how providers implement streaming completions using Server-Sent Events (SSE).

## Overview

The streaming protocol specifies how providers translate their SSE formats into normalized `stream-chunk` objects. Each provider implements streaming-specific methods to handle their event format.

## Provider Methods

### Required: `send-streaming-request`

Send an HTTP request for streaming completion.

```lisp
(send-streaming-request provider messages options) → http-stream
```

**Parameters**:
- `provider`: Provider instance
- `messages`: Conversation messages
- `options`: Plist with `:model`, `:tools`, `:max-tokens`, etc.

**Returns**: HTTP stream object for reading SSE events

**Implementation Requirements**:
1. Set `stream: true` in request body
2. Set `Accept: text/event-stream` header
3. Use chunked transfer encoding
4. Return stream without reading (lazy evaluation)

### Required: `parse-stream-chunk`

Parse a single SSE event into a stream-chunk object.

```lisp
(parse-stream-chunk provider event-data index) → stream-chunk-or-done
```

**Parameters**:
- `provider`: Provider instance
- `event-data`: Raw SSE data string (after "data: " prefix)
- `index`: Current chunk index

**Returns**:
- `stream-chunk` object
- `:done` if stream is complete
- `nil` to skip this event

### Optional: `parse-stream-event-type`

Parse event type for typed SSE streams (e.g., Anthropic).

```lisp
(parse-stream-event-type provider event-type event-data index)
→ stream-chunk-or-done-or-nil
```

Used for providers with `event: type` lines before `data:` lines.

## SSE Event Formats

### OpenAI Format

Simple data-only events:

```
data: {"choices":[{"delta":{"content":"Hello"},"index":0}]}

data: {"choices":[{"delta":{"content":" there"},"index":0}]}

data: [DONE]
```

**Parsing**:
- Each `data:` line contains full JSON
- `[DONE]` signals completion
- No event type field

#### JSON Schema: OpenAI Stream Chunk

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "choices": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "delta": {
            "type": "object",
            "properties": {
              "content": {"type": "string"},
              "tool_calls": {"type": "array"}
            }
          },
          "index": {"type": "integer"},
          "finish_reason": {
            "type": ["string", "null"],
            "enum": ["stop", "length", "tool_calls", null]
          }
        }
      }
    }
  }
}
```

### Anthropic Format

Typed events with state machine:

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_123"}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","usage":{"output_tokens":5}}

event: message_stop
data: {"type":"message_stop"}
```

**Parsing**:
- Event type determines how to parse data
- Only `content_block_delta` produces stream chunks
- Other events update metadata

#### JSON Schema: Anthropic Content Block Delta

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["type", "index", "delta"],
  "properties": {
    "type": {
      "type": "string",
      "const": "content_block_delta"
    },
    "index": {"type": "integer"},
    "delta": {
      "type": "object",
      "properties": {
        "type": {"type": "string", "enum": ["text_delta", "input_json_delta"]},
        "text": {"type": "string"},
        "partial_json": {"type": "string"}
      }
    }
  }
}
```

## Implementation Template

### OpenAI-style Provider

```lisp
(defmethod send-streaming-request ((provider openai-provider) messages options)
  (let ((request-body (build-completion-request provider messages options)))
    (setf (gethash "stream" request-body) t)
    (http-stream-request (provider-base-url provider)
                         "/chat/completions"
                         :method :post
                         :headers (auth-headers provider)
                         :json request-body)))

(defmethod parse-stream-chunk ((provider openai-provider) data index)
  (cond
    ((string= data "[DONE]") :done)
    ((string= data "") nil)
    (t (let* ((json (yason:parse data))
              (choices (gethash "choices" json))
              (first-choice (elt choices 0))
              (delta (gethash "delta" first-choice))
              (content (gethash "content" delta))
              (finish-reason (gethash "finish_reason" first-choice)))
         (make-instance 'stream-chunk
                        :delta (or content "")
                        :content (or content "")
                        :finish-reason (when finish-reason
                                        (intern (string-upcase finish-reason) :keyword))
                        :index index
                        :usage nil)))))
```

### Anthropic-style Provider

```lisp
(defmethod send-streaming-request ((provider anthropic-provider) messages options)
  ;; Similar to OpenAI but with "stream": true in body
  ...)

(defmethod parse-stream-event-type ((provider anthropic-provider)
                                    event-type data index)
  (cond
    ((string= event-type "message_stop") :done)
    ((string= event-type "content_block_delta")
     (let* ((json (yason:parse data))
            (delta (gethash "delta" json))
            (text (gethash "text" delta)))
       (make-instance 'stream-chunk
                      :delta text
                      :content text
                      :finish-reason nil
                      :index index
                      :usage nil)))
    ;; Ignore other event types
    (t nil)))
```

## SSE Parsing Rules

### General SSE Format

```
field: value\n
field: value\n
\n
```

- Fields are `data:`, `event:`, `id:`, `retry:`
- Each field ends with `\n`
- Empty line (`\n\n`) signals event boundary
- Lines starting with `:` are comments (ignored)

### Parsing Algorithm

```
1. Read line from HTTP stream
2. If starts with "data:", extract data payload
3. If starts with "event:", extract event type
4. If empty line, dispatch event:
   - Call parse-stream-chunk or parse-stream-event-type
   - Pass accumulated data and event type
5. Reset buffers for next event
6. Repeat until [DONE] or stream closes
```

## State Management

### Stream State Machine

```
CONNECTING → READING_HEADERS → STREAMING → COMPLETE
                                    ↓
                                  ERROR
```

### Provider State

Providers maintain:
- **Connection**: HTTP stream handle
- **Buffer**: Accumulated event data
- **Index**: Current chunk index (increments per chunk)
- **Event type**: For typed SSE streams
- **Usage**: Accumulated token usage

## Error Handling

### HTTP Errors During Streaming

| Status | Timing | Handling |
|--------|--------|----------|
| 401/403 | Before stream | Signal auth error immediately |
| 429 | Before stream | Signal rate limit error |
| 500/503 | Before stream | Signal server error |
| Connection drop | During stream | Signal `stream-connection-closed` |
| Timeout | During stream | Signal `stream-timeout` |

### Malformed Events

- **Invalid JSON**: Skip event, log warning, continue
- **Missing fields**: Use defaults, continue
- **Unknown event type**: Ignore event, continue

## Tool Calls in Streaming

### OpenAI Tool Call Format

Tool calls arrive incrementally:

```
data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"get"}}]}}]}
data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"loc"}}]}}]}
data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"ation\""}}]}}]}
data: {"choices":[{"finish_reason":"tool_calls"}]}
```

**Handling**:
1. Accumulate tool call fragments
2. Parse complete JSON when finish_reason is "tool_calls"
3. Return tool calls in final chunk

### Anthropic Tool Use Format

Tool use is a single event:

```
event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_123","name":"get_weather"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"location\""}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}
```

**Handling**: Similar accumulation strategy.

## Performance Considerations

- **Chunk buffering**: Providers may buffer tokens before sending chunks
- **Connection overhead**: ~100-200ms to establish SSE stream
- **Throughput**: ~10-50 chunks/second typical
- **Memory**: Keep stream state minimal (< 10KB per stream)

## Invariants

1. **Index monotonicity**: Chunk indices MUST increment by 1
2. **Done finality**: After returning `:done`, no more chunks
3. **Event ordering**: Events must be processed in received order
4. **Connection state**: Stream must be open for reading chunks
5. **Error propagation**: Network errors MUST surface as conditions, not ignored

## Best Practices

1. **Timeout management**: Set read timeout per chunk (10-30s)
2. **Buffering**: Use small read buffers (4KB-8KB)
3. **Error logging**: Log malformed events for debugging
4. **Cleanup**: Close HTTP connection in finalizer
5. **Testing**: Mock SSE streams for unit tests

## Related Contracts

- [completion-stream.md](./completion-stream.md) - Public streaming API
- [stream-chunk.md](./stream-chunk.md) - Chunk data structure
- [provider-protocol.md](../providers/contracts/provider-protocol.md) - Base provider protocol

## Implementation Notes

- SSE parsing is provider-agnostic at HTTP level
- Provider-specific logic is in chunk parsing methods
- OpenAI-compatible providers (Gemini, etc.) reuse OpenAI parsing
- Anthropic's typed events require additional state tracking
- Tool calls require fragment accumulation across chunks
