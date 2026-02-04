---
type: contract
name: completion-stream
version: 0.1.0
status: draft
feature: streaming
---

# Completion Stream Contract

This contract defines the streaming completion API for receiving LLM responses incrementally via Server-Sent Events (SSE).

## Overview

Streaming completions allow receiving model output token-by-token as it's generated, enabling real-time display and lower perceived latency. The stream returns `stream-chunk` objects until completion.

## Function: `complete-stream`

Create a streaming completion request.

### Signature

```lisp
(complete-stream messages &key model provider tools max-tokens
                              temperature system callback)
→ stream-object
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `messages` | list | required | Conversation messages |
| `model` | string | provider default | Model to use |
| `provider` | provider | `*default-provider*` | LLM provider instance |
| `tools` | list | `nil` | Tool definitions |
| `max-tokens` | integer | provider default | Maximum completion tokens |
| `temperature` | float | `1.0` | Sampling temperature (0.0-2.0) |
| `system` | string | `nil` | System message |
| `callback` | function | `nil` | Optional callback for each chunk |

### Return Value

Returns a stream object that can be read with `read-stream-chunk`.

## Stream Reading

### Function: `read-stream-chunk`

Read the next chunk from a stream.

```lisp
(read-stream-chunk stream) → stream-chunk-or-done
```

**Returns**:
- `stream-chunk` object with delta content
- `:done` when stream is complete
- Signals `stream-error` on failure

### Stream Chunk Object

```json-schema
{
  "type": "object",
  "properties": {
    "delta": {
      "type": "string",
      "description": "Incremental content since last chunk"
    },
    "content": {
      "type": "string",
      "description": "Accumulated content (alias for delta)"
    },
    "finish_reason": {
      "type": "string",
      "enum": ["stop", "length", "tool_calls", "content_filter", null],
      "description": "Reason for completion (null until final chunk)"
    },
    "index": {
      "type": "integer",
      "description": "Chunk sequence number (0-indexed)"
    },
    "usage": {
      "type": "object",
      "description": "Token usage (only in final chunk)",
      "properties": {
        "prompt_tokens": {"type": "integer"},
        "completion_tokens": {"type": "integer"},
        "total_tokens": {"type": "integer"}
      }
    }
  },
  "required": ["delta", "index"]
}
```

### Accessors

```lisp
(stream-chunk-delta chunk)         → string
(stream-chunk-content chunk)       → string  ; alias for delta
(stream-chunk-finish-reason chunk) → keyword-or-nil
(stream-chunk-index chunk)         → integer
(stream-chunk-usage chunk)         → plist-or-nil
```

## Usage Patterns

### Basic Streaming

```lisp
(let ((stream (complete-stream '((:role "user" :content "Tell me a story")))))
  (loop for chunk = (read-stream-chunk stream)
        until (eq chunk :done)
        do (format t "~A" (stream-chunk-delta chunk))
           (force-output))
  (terpri))
```

### With Callback

```lisp
(complete-stream '((:role "user" :content "Count to 10"))
  :callback (lambda (chunk)
              (format t "~A" (stream-chunk-delta chunk))
              (force-output)))
;; Callback is invoked for each chunk automatically
```

### Accumulating Content

```lisp
(let ((stream (complete-stream messages))
      (full-text ""))
  (loop for chunk = (read-stream-chunk stream)
        until (eq chunk :done)
        do (setf full-text
                 (concatenate 'string full-text (stream-chunk-delta chunk))))
  full-text)
```

### Tracking Progress

```lisp
(let ((stream (complete-stream messages))
      (tokens 0))
  (loop for chunk = (read-stream-chunk stream)
        until (eq chunk :done)
        do (incf tokens)
           (when (stream-chunk-finish-reason chunk)
             (format t "~%Finished: ~A (~D tokens)~%"
                     (stream-chunk-finish-reason chunk)
                     tokens))))
```

## Stream States

```
CREATED → READING → COMPLETED
           ↓
         ERROR
```

| State | Description | Valid Operations |
|-------|-------------|------------------|
| CREATED | Stream initialized | `read-stream-chunk` |
| READING | Actively receiving chunks | `read-stream-chunk` |
| COMPLETED | Stream finished normally | None (returns `:done`) |
| ERROR | Stream encountered error | None (signals error) |

## SSE Protocol

### Event Format

Streams use Server-Sent Events (SSE) protocol:

```
data: {"choices":[{"delta":{"content":"Hello"},"index":0}]}

data: {"choices":[{"delta":{"content":" there"},"index":0}]}

data: [DONE]
```

### Parsing Rules

1. Lines starting with `data:` contain JSON payloads
2. Empty lines separate events
3. `data: [DONE]` signals stream completion
4. Comments (lines starting with `:`) are ignored
5. Other fields (`event:`, `id:`, `retry:`) may be present

## Provider-Specific Formats

### OpenAI Streaming

```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion.chunk",
  "created": 1234567890,
  "model": "gpt-4",
  "choices": [{
    "index": 0,
    "delta": {
      "content": "Hello"
    },
    "finish_reason": null
  }]
}
```

### Anthropic Streaming

Uses typed SSE events:

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_...","role":"assistant"}}

event: content_block_delta
data: {"type":"content_block_delta","delta":{"text":"Hello"},"index":0}

event: message_stop
data: {"type":"message_stop"}
```

Both formats are normalized to `stream-chunk` objects internally.

## Error Handling

### Condition: `stream-error`

Signaled on stream reading errors.

**Slots**:
- `stream` - the stream object
- `message` - error description
- `http-status` - HTTP status code (if applicable)

**Restarts**:
- `:retry` - Retry reading the chunk
- `:abort-stream` - Stop reading and cleanup

### Common Errors

| Condition | Cause | Recovery |
|-----------|-------|----------|
| `stream-timeout` | No data received in timeout window | `:retry` or `:abort-stream` |
| `stream-malformed-data` | Invalid JSON in SSE data | `:abort-stream` |
| `stream-connection-closed` | Connection dropped mid-stream | `:retry` with new stream |
| `stream-rate-limited` | HTTP 429 received | Wait and retry |

## Invariants

1. **Monotonic indices**: Chunk indices MUST be sequential starting from 0
2. **Single finish reason**: `finish-reason` is `nil` until the final chunk
3. **Delta ordering**: Concatenating deltas in order MUST produce valid text
4. **Usage in final**: Token usage appears only in the final chunk (if provided)
5. **Done signal**: After returning `:done`, `read-stream-chunk` continues to return `:done`

## Best Practices

1. **Flush output**: Call `force-output` after printing each delta for real-time display
2. **Handle interruptions**: Wrap stream reading in `handler-case` for network errors
3. **Timeout limits**: Set reasonable timeouts (30-60s) for chunk reading
4. **Accumulate cautiously**: For large outputs, consider saving to file instead of string accumulation
5. **Cleanup**: Ensure streams are closed even on error (use `unwind-protect`)

## Performance Considerations

- **Latency**: First chunk typically arrives within 100-500ms
- **Throughput**: ~10-50 tokens/second depending on model and provider
- **Memory**: Each chunk is ~50-200 bytes; accumulation grows linearly
- **Connection**: Streams hold HTTP connection open for duration (typically 30-120s max)

## Related Contracts

- [stream-chunk.md](./stream-chunk.md) - Chunk data structure
- [streaming-protocol.md](./streaming-protocol.md) - Provider streaming protocol
- [complete.md](../core-api/contracts/complete.md) - Non-streaming completion

## Implementation Notes

- Streaming uses chunked transfer encoding over HTTP
- Providers may buffer several tokens before sending a chunk
- Tool calls in streaming mode require special handling (see streaming-protocol.md)
- Some providers don't support streaming for all models
