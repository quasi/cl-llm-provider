---
type: contract
name: gemini-api
version: 1.0.0
status: draft
feature: providers
source: Web research and API documentation
triangulation:
  docs: https://ai.google.dev/gemini-api/docs/openai
  api: Google Generative Language API v1beta
  status: documented
---

# Gemini API Contract

This contract defines the specifics of Google's Gemini API integration, including authentication, request/response formats, and provider-specific features.

## Overview

The Gemini provider implements the `llm-provider` protocol for Google's Gemini models. It uses Google's OpenAI-compatible endpoint for consistency with existing OpenAI-style integrations.

**Key Characteristics**:
- OpenAI-compatible API format
- Multimodal support (text, images, audio)
- Native function calling
- Streaming responses via SSE
- Multiple model tiers (Flash, Pro, Embedding)

## Provider Configuration

### Class Definition

```lisp
(defclass gemini-provider (llm-provider)
  ()
  (:documentation "Provider for Google Gemini API using OpenAI-compatible endpoint"))
```

### Base URL

**Default**: `https://generativelanguage.googleapis.com/v1beta/openai/`

**Format**: Uses OpenAI-compatible endpoint structure:
- Chat completions: `{base-url}/chat/completions`
- Embeddings: `{base-url}/embeddings`

**Note**: This is distinct from the native Gemini API endpoint (`https://generativelanguage.googleapis.com/v1beta/`), which uses a different request format.

### Authentication

**Method**: Bearer token authentication

**Header Format**:
```
Authorization: Bearer {GEMINI_API_KEY}
```

**Environment Variable**: `GEMINI_API_KEY`

**Obtaining Keys**: API keys are generated in [Google AI Studio](https://aistudio.google.com/)

**Security Notes**:
- API keys are project-specific
- Keys should never be committed to version control
- Keys have usage quotas and rate limits

## Supported Models

### Text Generation Models

| Model ID | Description | Context Window | Capabilities |
|----------|-------------|----------------|--------------|
| `gemini-3-flash-preview` | Fast, efficient model | 1M tokens | Text, vision, tools |
| `gemini-3-pro-preview` | Most capable model | 2M tokens | Text, vision, tools, audio |
| `gemini-2.0-flash-exp` | Experimental 2.0 model | 1M tokens | Text, vision, tools |

### Embedding Models

| Model ID | Description | Output Dimensions |
|----------|-------------|-------------------|
| `gemini-embedding-001` | Text embeddings | 768 |

### Image Generation Models

| Model ID | Description | Capabilities |
|----------|-------------|--------------|
| `imagen-3.0-generate-002` | Image generation | Text-to-image |

**Note**: Image generation uses a different endpoint (`images.generate`) and is not covered by the standard completion protocol.

## API Endpoints

### Chat Completions

**Endpoint**: `POST /chat/completions`

**Request Format** (OpenAI-compatible):
```json
{
  "model": "gemini-3-flash-preview",
  "messages": [
    {"role": "user", "content": "Hello"}
  ],
  "max_tokens": 1024,
  "temperature": 0.7,
  "stream": false,
  "tools": [...],
  "tool_choice": "auto"
}
```

**Response Format** (OpenAI-compatible):
```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "gemini-3-flash-preview",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "Hello! How can I help you?",
      "tool_calls": null
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 20,
    "total_tokens": 30
  }
}
```

### Embeddings

**Endpoint**: `POST /embeddings`

**Request Format**:
```json
{
  "model": "gemini-embedding-001",
  "input": "Text to embed"
}
```

**Response Format**:
```json
{
  "object": "list",
  "data": [{
    "object": "embedding",
    "embedding": [0.1, 0.2, ...],
    "index": 0
  }],
  "model": "gemini-embedding-001",
  "usage": {
    "prompt_tokens": 5,
    "total_tokens": 5
  }
}
```

## Protocol Implementation Requirements

### Required Methods

Per the `provider-protocol` contract, Gemini provider MUST implement:

1. **`provider-type`** → `:gemini`
2. **`provider-name`** → `"Google Gemini"`
3. **`provider-capabilities`** → `(:tools t :embeddings t :streaming t :vision t)`
4. **`send-completion-request`** - HTTP POST to `/chat/completions`
5. **`parse-completion-response`** - Parse OpenAI-compatible response
6. **`send-embedding-request`** - HTTP POST to `/embeddings`
7. **`parse-embedding-response`** - Parse embedding response

### Optional Methods

8. **`provider-default-base-url`** → `"https://generativelanguage.googleapis.com/v1beta/openai/"`
9. **`provider-api-key-env-var`** → `"GEMINI_API_KEY"`
10. **`translate-tool-to-provider`** - Use default OpenAI format (no override needed)
11. **`parse-tool-calls`** - Use default OpenAI parser (no override needed)

### Streaming Support

12. **`send-streaming-request`** - HTTP POST with `stream: true`
13. **`parse-stream-chunk`** - Parse SSE chunks in OpenAI format

**Streaming Format**:
```
data: {"id":"...","choices":[{"delta":{"content":"Hello"},"index":0}]}

data: {"id":"...","choices":[{"delta":{"content":" there"},"index":0}]}

data: [DONE]
```

## Multimodal Support

### Vision (Image Input)

**Mechanism**: Images are sent as base64-encoded data URLs in message content

**Format**:
```lisp
(list :role "user"
      :content (list
                 (list :type "text" :text "What's in this image?")
                 (list :type "image_url"
                       :image_url (list :url "data:image/jpeg;base64,..."))))
```

**Supported Formats**: JPEG, PNG, WebP, GIF

**Models**: `gemini-3-flash-preview`, `gemini-3-pro-preview`

### Audio Input

**Mechanism**: Audio is sent as base64-encoded data in message content

**Format**:
```lisp
(list :role "user"
      :content (list
                 (list :type "input_audio"
                       :input_audio (list :data "base64-audio-data"
                                         :format "wav"))))
```

**Supported Formats**: WAV, MP3, FLAC

**Models**: `gemini-3-pro-preview`

## Function Calling (Tools)

### Format

Gemini uses **OpenAI-compatible function calling** format:

**Request**:
```json
{
  "tools": [{
    "type": "function",
    "function": {
      "name": "get_weather",
      "description": "Get weather for a location",
      "parameters": {
        "type": "object",
        "properties": {
          "location": {"type": "string"}
        },
        "required": ["location"]
      }
    }
  }],
  "tool_choice": "auto"
}
```

**Response**:
```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "tool_calls": [{
        "id": "call_...",
        "type": "function",
        "function": {
          "name": "get_weather",
          "arguments": "{\"location\":\"Paris\"}"
        }
      }]
    },
    "finish_reason": "tool_calls"
  }]
}
```

### Tool Choice Options

| Value | Behavior |
|-------|----------|
| `"auto"` | Model decides whether to call functions |
| `"none"` | Model will not call functions |
| `{"type": "function", "function": {"name": "..."}}` | Force specific function |

**Note**: No translation needed—use the default `translate-tool-to-provider` implementation.

## Error Handling

### HTTP Status Codes

| Code | Meaning | Restart Strategy |
|------|---------|------------------|
| 400 | Bad Request | Fix request format |
| 401 | Unauthorized | `:use-value` (new API key) |
| 403 | Forbidden | Check API key permissions |
| 429 | Rate Limited | `:wait-and-retry` |
| 500 | Server Error | `:retry` |
| 503 | Service Unavailable | `:retry` with backoff |

### Error Response Format

```json
{
  "error": {
    "message": "Invalid API key",
    "type": "invalid_request_error",
    "code": "invalid_api_key"
  }
}
```

### Gemini-Specific Errors

- **Quota Exceeded**: HTTP 429 with quota limit message
- **Content Filtering**: Finish reason `"content_filter"` when content violates policies
- **Max Tokens**: Finish reason `"max_tokens"` when output is truncated

## Rate Limits

**Free Tier** (as of 2026-01):
- 15 requests per minute
- 1 million tokens per minute
- 1500 requests per day

**Paid Tier**:
- Higher limits based on billing tier
- Contact Google Cloud for enterprise limits

**Rate Limit Headers** (if provided):
- `x-ratelimit-limit`
- `x-ratelimit-remaining`
- `x-ratelimit-reset`

## Token Counting

### Request Tokens

- Counted from input messages, system prompt, and tool definitions
- Multimodal inputs (images, audio) count as approximate token equivalents

### Response Tokens

- Counted from assistant's generated text
- Tool call JSON counts toward completion tokens

### Token Usage Tracking

Usage is returned in OpenAI format:

```json
{
  "usage": {
    "prompt_tokens": 100,
    "completion_tokens": 50,
    "total_tokens": 150
  }
}
```

**Invariants**:
- `total_tokens = prompt_tokens + completion_tokens`
- Token counts are estimates and may vary slightly

## Model Metadata

The `model-metadata` method should return:

```lisp
(model-metadata provider "gemini-3-flash-preview")
; → (:context-window 1048576
;     :max-output-tokens 8192
;     :supports-tools t
;     :supports-vision t
;     :input-cost-per-1m-tokens 0.075
;     :output-cost-per-1m-tokens 0.30)
```

**Pricing** (as of 2026-01, subject to change):

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|------------------------|
| gemini-3-flash-preview | $0.075 | $0.30 |
| gemini-3-pro-preview | $1.25 | $5.00 |
| gemini-embedding-001 | $0.00 | $0.00 (free) |

**Note**: Prices are for prompts ≤128K tokens. Longer contexts may have different pricing.

## Implementation Notes

### Reusing OpenAI Implementation

Since Gemini uses an OpenAI-compatible endpoint, the implementation can:

1. **Inherit from `openai-provider`** (if using class inheritance)
2. **Reuse OpenAI request/response handling** (same JSON structure)
3. **Override only**:
   - `provider-type` → `:gemini`
   - `provider-name` → `"Google Gemini"`
   - `provider-default-base-url`
   - `provider-api-key-env-var`
   - `model-metadata` (Gemini-specific pricing/limits)

### Example Implementation Outline

```lisp
(defclass gemini-provider (llm-provider)
  ()
  (:documentation "Google Gemini API provider"))

(defmethod provider-type ((provider gemini-provider))
  :gemini)

(defmethod provider-name ((provider gemini-provider))
  "Google Gemini")

(defmethod provider-default-base-url ((provider gemini-provider))
  "https://generativelanguage.googleapis.com/v1beta/openai/")

(defmethod provider-api-key-env-var ((provider gemini-provider))
  "GEMINI_API_KEY")

(defmethod provider-capabilities ((provider gemini-provider))
  '(:tools t
    :embeddings t
    :streaming t
    :vision t
    :function-calling t))

;; Reuse OpenAI's send-completion-request and parse-completion-response
;; by using the same implementation (or calling shared helper functions)
```

## Configuration Example

### Basic Usage

```lisp
(let ((provider (make-provider :gemini
                               :api-key (uiop:getenv "GEMINI_API_KEY")
                               :default-model "gemini-3-flash-preview")))
  (complete '((:role "user" :content "Hello, Gemini!"))
            :provider provider))
```

### With Custom Base URL

```lisp
;; For Vertex AI deployment (different base URL)
(let ((provider (make-provider :gemini
                               :api-key "..."
                               :base-url "https://us-central1-aiplatform.googleapis.com/v1/..."
                               :default-model "google/gemini-2.0-flash-001")))
  ...)
```

## Testing Requirements

### Unit Tests

- ✅ Provider introspection (`provider-type`, `provider-name`, `provider-capabilities`)
- ✅ Base URL and API key configuration
- ✅ Request body construction (messages, tools, parameters)
- ✅ Response parsing (content, tool calls, usage)
- ✅ Error handling (401, 429, 500)

### Integration Tests

- ✅ Basic completion with text input
- ✅ Multi-turn conversation
- ✅ Function calling round-trip
- ✅ Streaming response
- ✅ Vision input (image understanding)
- ✅ Embedding generation

### Mock Testing

Use mock HTTP responses in OpenAI format to avoid hitting real API during test suite execution.

## Acceptance Criteria

- ✅ Gemini provider conforms to `provider-protocol` contract
- ✅ All protocol methods implemented
- ✅ OpenAI-compatible format used for requests/responses
- ✅ Multimodal inputs (vision, audio) supported
- ✅ Function calling works with existing tool definitions
- ✅ Streaming responses parsed correctly
- ✅ Error handling includes Gemini-specific conditions
- ✅ Model metadata includes Gemini pricing and limits
- ✅ Provider substitutable with other providers in user code

## Related Artifacts

- [provider-protocol.md](./provider-protocol.md) - Generic provider contract
- [vocabulary.md](../vocabulary.md) - Provider vocabulary definitions
- [openai-api.md](./openai-api.md) - OpenAI provider (similar implementation)

## External References

- **API Documentation**: https://ai.google.dev/gemini-api/docs/openai
- **Model Garden**: https://ai.google.dev/gemini-api/docs/models/gemini
- **Pricing**: https://ai.google.dev/pricing
- **API Keys**: https://aistudio.google.com/apikey
