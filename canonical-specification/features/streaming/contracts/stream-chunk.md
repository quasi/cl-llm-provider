---
type: contract
name: stream-chunk
version: 0.1.0
status: draft
feature: streaming
depends_on:
  - core/foundation/vocabulary#chunk
---

# Stream Chunk Contract

This contract defines the structure and semantics of streaming response chunks.

## Overview

A stream chunk represents an incremental piece of content from a streaming completion. Each chunk contains a delta (new content), cumulative metadata, and optionally a finish reason and usage statistics.

## Class: `stream-chunk`

### Slots

| Slot | Type | Description |
|------|------|-------------|
| `delta` | string | Incremental content since last chunk |
| `content` | string | Alias for `delta` (for consistency) |
| `finish-reason` | keyword or `nil` | Completion reason (only in final chunk) |
| `index` | integer | Chunk sequence number (0-indexed) |
| `usage` | plist or `nil` | Token usage stats (only in final chunk) |

## Accessors

### `stream-chunk-delta`

```lisp
(stream-chunk-delta chunk) → string
```

Returns the incremental content in this chunk.

### `stream-chunk-content`

```lisp
(stream-chunk-content chunk) → string
```

Alias for `stream-chunk-delta`. Provided for API consistency with non-streaming responses.

### `stream-chunk-finish-reason`

```lisp
(stream-chunk-finish-reason chunk) → keyword-or-nil
```

Returns the finish reason if this is the final chunk, otherwise `nil`.

**Possible values**:
- `nil` - Not the final chunk
- `:stop` - Completed normally
- `:length` - Stopped due to max_tokens limit
- `:tool-calls` - Stopped to make tool calls
- `:content-filter` - Stopped due to content filtering

### `stream-chunk-index`

```lisp
(stream-chunk-index chunk) → integer
```

Returns the 0-indexed sequence number of this chunk.

### `stream-chunk-usage`

```lisp
(stream-chunk-usage chunk) → plist-or-nil
```

Returns token usage statistics if available (typically only in final chunk).

**Format**: `(:prompt-tokens N :completion-tokens N :total-tokens N)`

## Chunk Schema

```json-schema
{
  "type": "object",
  "properties": {
    "delta": {
      "type": "string",
      "description": "New content in this chunk",
      "examples": ["Hello", " world", "!"]
    },
    "content": {
      "type": "string",
      "description": "Alias for delta"
    },
    "finish_reason": {
      "type": ["string", "null"],
      "enum": ["stop", "length", "tool_calls", "content_filter", null],
      "description": "Completion reason (null until final chunk)"
    },
    "index": {
      "type": "integer",
      "minimum": 0,
      "description": "Chunk sequence number"
    },
    "usage": {
      "type": ["object", "null"],
      "properties": {
        "prompt_tokens": {
          "type": "integer",
          "minimum": 0
        },
        "completion_tokens": {
          "type": "integer",
          "minimum": 0
        },
        "total_tokens": {
          "type": "integer",
          "minimum": 0
        }
      }
    }
  },
  "required": ["delta", "index"]
}
```

## Chunk Types

### Content Chunk

Normal incremental content:

```lisp
(make-instance 'stream-chunk
  :delta "Hello"
  :content "Hello"
  :finish-reason nil
  :index 0
  :usage nil)
```

### Final Chunk

Last chunk with finish reason and usage:

```lisp
(make-instance 'stream-chunk
  :delta ""
  :content ""
  :finish-reason :stop
  :index 42
  :usage '(:prompt-tokens 10
           :completion-tokens 42
           :total-tokens 52))
```

### Empty Chunk

Some providers send empty deltas:

```lisp
(make-instance 'stream-chunk
  :delta ""
  :content ""
  :finish-reason nil
  :index 5
  :usage nil)
```

**Handling**: Empty chunks should be processed normally (they maintain index sequence).

## Usage Examples

### Accumulating Content

```lisp
(let ((accumulated ""))
  (loop for chunk = (read-stream-chunk stream)
        until (eq chunk :done)
        do (setf accumulated
                 (concatenate 'string
                              accumulated
                              (stream-chunk-delta chunk))))
  accumulated)
```

### Detecting Completion

```lisp
(loop for chunk = (read-stream-chunk stream)
      until (eq chunk :done)
      do (when (stream-chunk-finish-reason chunk)
           (format t "~%Stream finished: ~A~%"
                   (stream-chunk-finish-reason chunk))
           (when-let ((usage (stream-chunk-usage chunk)))
             (format t "Tokens: ~D~%"
                     (getf usage :total-tokens)))))
```

### Filtering Empty Chunks

```lisp
(loop for chunk = (read-stream-chunk stream)
      until (eq chunk :done)
      when (> (length (stream-chunk-delta chunk)) 0)
        do (process-chunk chunk))
```

## Provider Wire Formats

### OpenAI Format

```json
{
  "choices": [{
    "index": 0,
    "delta": {
      "content": "Hello"
    },
    "finish_reason": null
  }]
}
```

Mapped to:
```lisp
(make-instance 'stream-chunk
  :delta "Hello"
  :content "Hello"
  :finish-reason nil
  :index 0
  :usage nil)
```

### Anthropic Format

```json
{
  "type": "content_block_delta",
  "index": 0,
  "delta": {
    "type": "text_delta",
    "text": "Hello"
  }
}
```

Mapped to the same `stream-chunk` structure.

## Invariants

1. **Non-null delta**: `delta` is always a string (may be empty, never `nil`)
2. **Non-negative index**: `index` >= 0 for all chunks
3. **Sequential indices**: For chunks C1, C2 in sequence, C2.index = C1.index + 1
4. **Finish reason uniqueness**: At most one chunk has non-nil `finish-reason`
5. **Usage finality**: If `usage` is non-nil, `finish-reason` is also non-nil
6. **Content/delta equality**: `(equal (stream-chunk-content chunk) (stream-chunk-delta chunk))` is always `t`

## Chunk Processing Order

```
1. Receive SSE event
2. Parse JSON payload
3. Extract delta/content
4. Create stream-chunk object
5. Invoke callback (if provided)
6. Return chunk to caller
```

## Error Conditions

| Condition | When | Recovery |
|-----------|------|----------|
| `malformed-chunk` | Invalid JSON in chunk data | Skip chunk, continue stream |
| `missing-delta` | No content field in chunk | Treat as empty delta |
| `invalid-index` | Non-sequential index | Log warning, use sequential index |

## Performance Notes

- **Chunk size**: Typically 1-50 characters per chunk
- **Chunk frequency**: 10-50 chunks/second
- **Memory**: ~100 bytes per chunk object
- **GC pressure**: Consider object pooling for high-throughput streams

## Related Contracts

- [completion-stream.md](./completion-stream.md) - Streaming completion API
- [streaming-protocol.md](./streaming-protocol.md) - Provider-level protocol
- [complete.md](../core-api/contracts/complete.md) - Non-streaming response

## Implementation Notes

- `content` slot is an alias for `delta` to maintain API consistency
- Chunks are immutable once created
- Empty deltas are valid and maintain index sequence
- Final chunk may or may not have content
- Usage statistics format matches non-streaming responses
