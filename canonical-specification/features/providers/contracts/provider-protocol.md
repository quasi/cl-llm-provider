---
type: contract
name: provider-protocol
version: 1.0.0
status: stable
feature: providers
source: src/protocol.lisp
triangulation:
  docs: docs/agent/core-SPEC.agent.md (RULE-001)
  code: src/protocol.lisp
  status: convergent
---

# Provider Protocol Contract

This contract defines the generic function protocol that all LLM provider implementations must follow. New providers are added by subclassing `llm-provider` and implementing these generic functions.

## Overview

The protocol separates concerns into three categories:

1. **Required Methods** - Every provider MUST implement
2. **Streaming Methods** - Required for streaming support
3. **Introspection Methods** - Required for capability discovery
4. **Optional Methods** - Have default implementations

## Required Protocol Methods

### send-completion-request

**Signature**:
```lisp
(defgeneric send-completion-request (provider messages &key model max-tokens
                                                        temperature system tools
                                                        tool-choice stop)
  → raw-response)
```

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `provider` | `llm-provider` | Yes | Provider instance |
| `messages` | `list` | Yes | List of message plists |
| `model` | `string` | No | Model identifier |
| `max-tokens` | `integer` | No | Maximum tokens in response |
| `temperature` | `float` | No | Sampling temperature (0.0-2.0) |
| `system` | `string` | No | System prompt |
| `tools` | `list` | No | List of tool-definition objects |
| `tool-choice` | `keyword/string/nil` | No | Tool selection strategy |
| `stop` | `string/list` | No | Stop sequences |

**Returns**: Raw HTTP response body (hash-table or alist)

**Signals**: `provider-api-error` on HTTP errors

**Invariants**:
- RULE-012: No side effects beyond HTTP requests, profiling, and condition signaling

#### JSON Schema: Raw Response Structure

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "description": "Provider-specific raw response (structure varies by provider)"
}
```

---

### parse-completion-response

**Signature**:
```lisp
(defgeneric parse-completion-response (provider raw-response &key performance)
  → completion-response)
```

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `provider` | `llm-provider` | Yes | Provider instance |
| `raw-response` | `hash-table` | Yes | Raw response from send-completion-request |
| `performance` | `plist` | No | Performance timing data |

**Returns**: `completion-response` object

**Invariants**:
- INV-001: Raw response preserved in `response-raw` slot
- RULE-015: Finish reason normalized to standard keywords

---

### send-embedding-request

**Signature**:
```lisp
(defgeneric send-embedding-request (provider input &key model dimensions)
  → raw-response)
```

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `provider` | `llm-provider` | Yes | Provider instance |
| `input` | `string/list` | Yes | Text to embed (single or batch) |
| `model` | `string` | No | Embedding model identifier |
| `dimensions` | `integer` | No | Output dimensions (if model supports) |

**Returns**: Raw HTTP response body (hash-table or alist)

**Signals**: `provider-api-error` on HTTP errors

---

### parse-embedding-response

**Signature**:
```lisp
(defgeneric parse-embedding-response (provider raw-response &key performance)
  → embedding-response)
```

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `provider` | `llm-provider` | Yes | Provider instance |
| `raw-response` | `hash-table` | Yes | Raw response from send-embedding-request |
| `performance` | `plist` | No | Performance timing data |

**Returns**: `embedding-response` object

---

## Streaming Protocol Methods

### send-streaming-request

**Signature**:
```lisp
(defgeneric send-streaming-request (provider messages &key model max-tokens
                                                          temperature system tools
                                                          tool-choice stop)
  → completion-stream)
```

**Parameters**: Same as `send-completion-request`

**Returns**: `completion-stream` object (can be read chunk-by-chunk)

**Signals**: `provider-api-error` on HTTP connection errors

---

### parse-stream-chunk

**Signature**:
```lisp
(defgeneric parse-stream-chunk (provider raw-chunk stream)
  → stream-chunk | nil)
```

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `provider` | `llm-provider` | Yes | Provider instance |
| `raw-chunk` | `string` | Yes | Raw SSE data from stream |
| `stream` | `completion-stream` | Yes | Stream for state tracking |

**Returns**: `stream-chunk` object, or nil for keep-alive/empty chunks

**Side Effects**: Sets stream state to `:closed` when done signal received

---

### read-stream-chunk

**Signature**:
```lisp
(defgeneric read-stream-chunk (stream &key timeout)
  → stream-chunk | nil)
```

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `stream` | `completion-stream` | Yes | Stream to read from |
| `timeout` | `number/nil` | No | Max seconds to wait (nil = block) |

**Returns**: `stream-chunk` object, or nil if stream closed

**Signals**: `stream-error` on read failures

---

## Introspection Protocol Methods

### provider-type

**Signature**:
```lisp
(defgeneric provider-type (provider)
  → keyword)
```

**Returns**: Provider type keyword (`:openai`, `:anthropic`, `:ollama`, `:openrouter`, `:openai-compatible`, `:gemini`)

**Invariants**:
- INV-005: Same provider class always returns same keyword
- Result is `eql`-comparable

---

### provider-name

**Signature**:
```lisp
(defgeneric provider-name (provider)
  → string)
```

**Returns**: Human-readable name for display (e.g., `"OpenAI"`, `"Anthropic"`)

---

### provider-capabilities

**Signature**:
```lisp
(defgeneric provider-capabilities (provider)
  → plist)
```

**Returns**: Plist of capabilities with keyword keys and boolean values

**Keys**: `:tools`, `:embeddings`, `:streaming`, `:vision`, `:function-calling`

**Invariants**:
- Missing keys equivalent to NIL (not supported)
- Values are T or NIL

#### JSON Schema: Provider Capabilities

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "tools": {"type": "boolean"},
    "embeddings": {"type": "boolean"},
    "streaming": {"type": "boolean"},
    "vision": {"type": "boolean"},
    "function_calling": {"type": "boolean"}
  }
}
```

---

### provider-config-summary

**Signature**:
```lisp
(defgeneric provider-config-summary (provider)
  → plist)
```

**Returns**: Configuration summary (no sensitive data)

**Keys**: `:type`, `:name`, `:model`, `:base-url`, `:capabilities`

**Invariants**:
- RULE-004 (metadata): MUST NOT include `:api-key` or credentials

---

### model-metadata

**Signature**:
```lisp
(defgeneric model-metadata (provider model-name)
  → plist | nil)
```

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `provider` | `llm-provider` | Yes | Provider instance |
| `model-name` | `string` | Yes | Model identifier |

**Returns**: Metadata plist or NIL for unknown models

**Keys**: `:context-window`, `:max-output-tokens`, `:supports-tools`, `:supports-vision`, `:input-cost-per-1m-tokens`, `:output-cost-per-1m-tokens`

**Invariants**:
- RULE-005 (metadata): Returns NIL for unknown models

---

## Optional Protocol Methods

These have default implementations but can be overridden.

### provider-default-base-url

**Signature**:
```lisp
(defgeneric provider-default-base-url (provider)
  → string | nil)
```

**Default**: Returns NIL (must be specified in constructor)

---

### provider-api-key-env-var

**Signature**:
```lisp
(defgeneric provider-api-key-env-var (provider)
  → string | nil)
```

**Returns**: Environment variable name for API key (e.g., `"OPENAI_API_KEY"`)

**Default**: Returns NIL (no standard env var)

---

### translate-tool-to-provider

**Signature**:
```lisp
(defgeneric translate-tool-to-provider (provider tool-definition)
  → hash-table)
```

**Returns**: Provider-specific tool schema

**Default**: Returns OpenAI function format

---

### parse-tool-calls

**Signature**:
```lisp
(defgeneric parse-tool-calls (provider raw-response)
  → list | nil)
```

**Returns**: List of `tool-call` objects, or nil

**Default**: Parses OpenAI-style tool calls

---

## Helper Function

### provider-supports-p

**Signature**:
```lisp
(defun provider-supports-p (provider capability)
  → boolean)
```

**Example**:
```lisp
(provider-supports-p provider :tools)  ; → T or NIL
```

---

## Implementation Requirements

Per RULE-001, every `llm-provider` subclass MUST implement:

1. `send-completion-request`
2. `parse-completion-response`
3. `send-embedding-request`
4. `parse-embedding-response`
5. `provider-type`
6. `provider-name`
7. `provider-capabilities`

Streaming-capable providers must also implement:
- `send-streaming-request`
- `parse-stream-chunk`

---

## Error Handling

The protocol provides structured error handling:

| Condition | When | Restarts |
|-----------|------|----------|
| `provider-api-error` | HTTP 4xx/5xx | `:retry`, `:use-fallback-provider` |
| `provider-rate-limit-error` | HTTP 429 | `:wait-and-retry`, `:retry`, `:use-fallback-provider` |
| `provider-authentication-error` | HTTP 401 | `:use-value` (new API key) |
| `stream-error` | Stream read failures | - |

---

## See Also

- [vocabulary.md](../../core/foundation/vocabulary.md) - Protocol Method definition
- [core-api/contracts/complete.md](../../core-api/contracts/complete.md) - User-facing API
