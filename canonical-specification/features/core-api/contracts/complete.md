---
type: contract
name: complete
version: 0.1.0
status: draft
feature: core-api
---

# complete - LLM Completion Request

[DRAFT] - Extracted from src/api.lisp:65

## Overview

The `complete` function is the primary interface for sending completion requests to LLM providers. It provides a unified API across all providers (Anthropic, OpenAI, Ollama, OpenRouter), abstracting provider-specific differences.

## Signature

```lisp
(defun complete (messages &key provider model max-tokens temperature
                              system tools tool-choice stop
                              hooks on-request on-response on-error)
  → completion-response
```

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `messages` | `list` of `plist` | Yes | - | Conversation history. Each message: `(:role "user|assistant" :content "text")` |
| `provider` | `llm-provider` | No | `*default-provider*` | Provider instance for API interactions |
| `model` | `string` | No | Provider/global default | Model identifier (e.g., "claude-3-sonnet-20240229") |
| `max-tokens` | `integer` | No | `*default-max-tokens*` | Maximum tokens in response |
| `temperature` | `float` | No | `*default-temperature*` | Sampling temperature (0.0-2.0) |
| `system` | `string` | No | `nil` | System prompt for the conversation |
| `tools` | `list` of `tool-definition` | No | `nil` | Available tools for the model |
| `tool-choice` | `keyword`, `string`, or `nil` | No | `nil` | Tool selection strategy |
| `stop` | `string` or `list` | No | `nil` | Stop sequences |
| `hooks` | `hooks` | No | `*global-hooks*` | Observability hooks |
| `on-request` | `function` | No | `nil` | Callback before request: `(lambda (request-plist) ...)` |
| `on-response` | `function` | No | `nil` | Callback after response: `(lambda (response timing) ...)` |
| `on-error` | `function` | No | `nil` | Callback on error: `(lambda (error) ...)` |

## Return Value

Returns: `completion-response` object

### completion-response Slots

| Slot | Type | Accessor | Description |
|------|------|----------|-------------|
| `id` | `string` | `response-id` | Unique response identifier |
| `model` | `string` | `response-model` | Model that generated response |
| `content` | `string` or `nil` | `response-content` | Text content (`nil` if tool call) |
| `message` | `plist` | `response-message` | Full message for continuation |
| `tool-calls` | `list` or `nil` | `response-tool-calls` | Tool call requests |
| `finish-reason` | `keyword` | `response-finish-reason` | `:stop`, `:length`, or `:tool-calls` |
| `usage` | `plist` | `response-usage` | `(:prompt-tokens N :completion-tokens M :total-tokens T)` |
| `raw` | `hash-table` | `response-raw` | Original provider response |
| `performance` | `plist` or `nil` | `response-performance` | Timing data when profiling enabled |
| `metadata` | `plist` or `nil` | `response-metadata` | Provider-specific metadata |

## Behavior

### Request Flow

1. **Validation**: Validates provider and model are set (uses defaults if available)
2. **Tool Validation**: If tools provided, validates each tool definition
3. **Hook Invocation**: Calls `before-request` hook if configured
4. **Encoding**: Converts messages and tools to provider format (timed if profiling enabled)
5. **API Call**: Invokes `send-completion-request` on provider (timed)
6. **Parsing**: Parses raw response into `completion-response` (timed)
7. **Hook Invocation**: Calls `after-response` hook on success, or `on-error` on failure
8. **Return**: Returns normalized `completion-response` object

### Provider Abstraction

The same code works across all providers:

```lisp
;; Anthropic
(complete messages :provider (make-provider :anthropic :model "claude-3-sonnet-20240229"))

;; OpenAI
(complete messages :provider (make-provider :openai :model "gpt-4"))

;; Ollama (local)
(complete messages :provider (make-provider :ollama :model "llama3"))
```

Provider-specific differences are handled internally.

### Multi-turn Conversations

For conversations, append each response message to the message list:

```lisp
(let ((messages (list (list :role "user" :content "What is 2+2?"))))
  (let ((response (complete messages)))
    (push (response-message response) messages)  ; Add assistant response
    (push (list :role "user" :content "Add 3 to that") messages)
    (complete (reverse messages))))  ; Continue conversation
```

## Error Conditions

| Condition | When | Restarts |
|-----------|------|----------|
| `provider-configuration-error` | Provider or model not set and no defaults | - |
| `provider-api-error` | HTTP error (4xx, 5xx) | `:retry`, `:use-fallback-provider` |
| `provider-rate-limit-error` | HTTP 429 (rate limited) | `:wait-and-retry`, `:retry`, `:use-fallback-provider` |
| `provider-authentication-error` | HTTP 401 (auth failed) | `:use-value` (new API key) |
| `tool-schema-error` | Tool definition invalid | - |

## Examples

### Basic Completion

```lisp
(complete '((:role "user" :content "What is Common Lisp?")))
```

### With Parameters

```lisp
(complete '((:role "user" :content "Explain recursion"))
          :model "claude-3-opus-20240229"
          :max-tokens 1000
          :temperature 0.7
          :system "You are a helpful programming tutor.")
```

### With Tools

```lisp
(let* ((tools (list (define-tool "get_weather"
                                  "Get weather for a location"
                                  '((:name "city" :type :string)))))
       (response (complete '((:role "user" :content "What's the weather in Paris?"))
                           :tools tools)))
  (when (response-tool-calls response)
    (format t "Model requested tool: ~A~%"
            (tool-call-name (first (response-tool-calls response))))))
```

### With Observability

```lisp
(complete messages
          :on-request (lambda (info)
                        (format t "Sending to ~A...~%" (getf info :provider)))
          :on-response (lambda (resp timing)
                         (format t "Got response in ~,2Fs~%" timing)))
```

### With Performance Profiling

```lisp
(let ((*performance-profiling* t))
  (let ((response (complete messages)))
    (format-performance-stats (response-performance response))))
```

Output:
```
Performance Stats:
  Encode time: 0.0023 seconds
  API time:    1.2456 seconds
  Decode time: 0.0034 seconds
```

## Invariants

- **INV-001**: If `tools` is non-nil, all tool definitions must pass validation
- **INV-002**: If `finish-reason` is `:tool-calls`, then `tool-calls` is non-nil and `content` is nil
- **INV-003**: If `finish-reason` is `:stop` or `:length`, then `content` is non-nil (unless model returned empty)
- **INV-004**: `usage` always contains `:prompt-tokens`, `:completion-tokens`, and `:total-tokens`
- **INV-005**: `message` plist is always suitable for appending to conversation history

## Performance Characteristics

**Typical Latency** (measured on API call phase):
- Local Ollama: 0.5-2s
- OpenAI/Anthropic: 1-5s (depends on model, region, load)

**Encoding/Decoding Overhead**: < 10ms typically

**Token Limits**:
- Varies by model (see `model-metadata` for per-model limits)
- Anthropic Claude: 200K tokens (context)
- OpenAI GPT-4: 8K-128K tokens (varies by version)

## See Also

- [make-provider](./make-provider.md) - Creating provider instances
- [completion-response](../../core/contracts/shared-types.md#completion-response) - Response structure
- [tool-definition](../tools/contracts/tool-definition.md) - Tool specification
- [Provider Protocol](../providers/contracts/provider-protocol.md) - Provider implementation contract
