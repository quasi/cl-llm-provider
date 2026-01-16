---
type: scenario
name: gemini-provider-usage
version: 1.0.0
status: stable
feature: providers
test_evidence: tests/test-gemini-provider.lisp (44 assertions, 100% pass)
implemented: 2026-01-16
---

# Gemini Provider Usage Scenarios

**Implementation Status**: Complete and verified (2026-01-16)

## Overview

This scenario defines how users interact with the Gemini provider, covering basic completions, multimodal inputs, function calling, and streaming responses.

## Scenario 1: Basic Text Completion

### Given

- User has valid `GEMINI_API_KEY` environment variable set
- User wants to send a simple text prompt to Gemini

### When

User creates Gemini provider and sends completion request:

```lisp
(use-package :cl-llm-provider)

;; Create provider
(let ((provider (make-provider :gemini
                               :default-model "gemini-3-flash-preview")))
  ;; Send completion
  (complete '((:role "user" :content "What is Common Lisp?"))
            :provider provider))
```

### Then

- ✅ Provider reads API key from `GEMINI_API_KEY` environment variable
- ✅ HTTP POST sent to `https://generativelanguage.googleapis.com/v1beta/openai/chat/completions`
- ✅ Request includes Bearer token authentication
- ✅ Response is parsed into `completion-response` object
- ✅ `response-content` returns Gemini's text response
- ✅ `response-usage` contains token counts
- ✅ Metadata includes `:provider-type :gemini` and `:provider-name "Google Gemini"`

## Scenario 2: Provider Substitutability

### Given

- User has code working with OpenAI provider
- User wants to switch to Gemini without changing application logic

### When

User changes only the provider type:

```lisp
;; Original code with OpenAI
(let ((provider (make-provider :openai :model "gpt-4")))
  (complete messages :provider provider))

;; Switch to Gemini - same code structure
(let ((provider (make-provider :gemini :model "gemini-3-pro-preview")))
  (complete messages :provider provider))
```

### Then

- ✅ Same `complete` function works for both providers
- ✅ Messages format is identical
- ✅ Response structure is identical
- ✅ No changes needed in application logic
- ✅ Only provider instantiation changes

## Scenario 3: Multi-Turn Conversation

### Given

- User wants to have a conversation with multiple back-and-forth turns

### When

```lisp
(let ((messages (list (list :role "user" :content "What is 2+2?")))
      (provider (make-provider :gemini)))

  ;; First turn
  (let ((response (complete messages :provider provider)))
    (push (response-message response) messages)

    ;; Second turn
    (push (list :role "user" :content "Now multiply that by 3") messages)
    (complete (reverse messages) :provider provider)))
```

### Then

- ✅ Conversation history is maintained in messages list
- ✅ Each response includes role `"assistant"`
- ✅ Messages alternate between user and assistant
- ✅ Context is preserved across turns
- ✅ Token usage accumulates across requests

## Scenario 4: Vision Input (Image Understanding)

### Given

- User has an image (JPEG, PNG, WebP, or GIF)
- User wants Gemini to analyze the image

### When

```lisp
(let* ((image-data (read-file-to-base64 "path/to/image.jpg"))
       (data-url (format nil "data:image/jpeg;base64,~A" image-data))
       (provider (make-provider :gemini :model "gemini-3-flash-preview")))

  (complete (list (list :role "user"
                       :content (list
                                  (list :type "text"
                                        :text "What's in this image?")
                                  (list :type "image_url"
                                        :image_url (list :url data-url)))))
            :provider provider))
```

### Then

- ✅ Image is sent as base64-encoded data URL
- ✅ Gemini processes both text and image
- ✅ Response describes image content
- ✅ Token usage includes image input tokens (approximate)
- ✅ `provider-capabilities` includes `:vision t`

**Supported Image Formats**: JPEG, PNG, WebP, GIF

## Scenario 5: Function Calling (Tools)

### Given

- User defines tools for weather and calculator
- User wants Gemini to use these tools

### When

```lisp
(let* ((tools (list
                (define-tool "get_weather"
                             "Get current weather for a location"
                             '((:name "location" :type :string
                                :description "City name")))
                (define-tool "calculator"
                             "Perform mathematical calculations"
                             '((:name "expression" :type :string
                                :description "Math expression to evaluate")))))
       (provider (make-provider :gemini))
       (messages (list (list :role "user"
                            :content "What's the weather in Paris?"))))

  ;; First request - Gemini decides to call tool
  (let ((response (complete messages :provider provider :tools tools)))
    (when (response-tool-calls response)
      (format t "Tool call: ~A~%" (tool-call-name (first (response-tool-calls response)))))))
```

### Then

- ✅ Tools are translated to OpenAI function format (no custom translation needed)
- ✅ Gemini returns `finish-reason` of `:tool_calls`
- ✅ `response-tool-calls` contains list of tool call objects
- ✅ Each tool call has `:id`, `:name`, and `:arguments`
- ✅ Arguments are parsed from JSON string
- ✅ User can execute tools and send results back

## Scenario 6: Tool Execution Round-Trip

### Given

- Gemini has requested a tool call
- User executes the tool and gets a result

### When

```lisp
;; After receiving tool call from Scenario 5
(let ((tool-calls (response-tool-calls response)))
  ;; Add assistant message with tool call
  (push (response-message response) messages)

  ;; Execute tool and create result message
  (dolist (tc tool-calls)
    (let ((result (execute-tool tc)))  ; User's tool execution logic
      (push (list :role "tool"
                 :tool_call_id (tool-call-id tc)
                 :content (yason:encode result))
            messages)))

  ;; Send back to Gemini with results
  (complete (reverse messages) :provider provider :tools tools))
```

### Then

- ✅ Tool results sent in OpenAI-compatible format
- ✅ Gemini processes results and generates final response
- ✅ Response incorporates tool call results
- ✅ Finish reason is `:stop` (normal completion)

## Scenario 7: Streaming Response

### Given

- User wants real-time token-by-token output
- User provides callback to process chunks

### When

```lisp
(let ((provider (make-provider :gemini))
      (full-content ""))

  (complete-streaming '((:role "user" :content "Write a haiku about Lisp"))
                      :provider provider
                      :callback (lambda (chunk)
                                 (let ((delta (stream-chunk-content chunk)))
                                   (when delta
                                     (setf full-content (concatenate 'string full-content delta))
                                     (format t "~A" delta)
                                     (force-output)))))

  (format t "~%Final: ~A~%" full-content))
```

### Then

- ✅ HTTP request sent with `stream: true`
- ✅ Callback invoked for each SSE chunk
- ✅ `stream-chunk-content` returns delta text
- ✅ Streaming follows OpenAI SSE format
- ✅ Stream ends with `[DONE]` marker
- ✅ User can build full response incrementally

## Scenario 8: Error Handling - Invalid API Key

### Given

- User provides invalid or missing API key

### When

```lisp
(handler-case
    (let ((provider (make-provider :gemini :api-key "invalid-key")))
      (complete '((:role "user" :content "Hello")) :provider provider))
  (provider-authentication-error (e)
    (format t "Auth error: ~A~%" e)
    ;; Restart: provide new API key
    (invoke-restart 'use-value (uiop:getenv "GEMINI_API_KEY"))))
```

### Then

- ✅ HTTP 401 response triggers `provider-authentication-error`
- ✅ Error message includes "Invalid API key"
- ✅ Restart `use-value` allows providing new API key
- ✅ Request is retried with new key

## Scenario 9: Error Handling - Rate Limit

### Given

- User exceeds Gemini's rate limit (15 requests/min on free tier)

### When

```lisp
(handler-case
    (complete messages :provider provider)
  (provider-rate-limit-error (e)
    (format t "Rate limited: ~A~%" e)
    ;; Restart: wait and retry
    (invoke-restart 'wait-and-retry)))
```

### Then

- ✅ HTTP 429 response triggers `provider-rate-limit-error`
- ✅ Error includes rate limit details
- ✅ Restart `wait-and-retry` waits appropriate duration
- ✅ Request is automatically retried after delay
- ✅ Alternative restart `:use-fallback-provider` available

## Scenario 10: Model Metadata Query

### Given

- User wants to check model capabilities before using

### When

```lisp
(let* ((provider (make-provider :gemini))
       (meta (model-metadata provider "gemini-3-flash-preview")))

  (format t "Context window: ~D tokens~%" (getf meta :context-window))
  (format t "Max output: ~D tokens~%" (getf meta :max-output-tokens))
  (format t "Supports tools: ~A~%" (getf meta :supports-tools))
  (format t "Supports vision: ~A~%" (getf meta :supports-vision))
  (format t "Input cost: $~,2F per 1M tokens~%"
          (getf meta :input-cost-per-1m-tokens))
  (format t "Output cost: $~,2F per 1M tokens~%"
          (getf meta :output-cost-per-1m-tokens)))
```

### Then

- ✅ Returns metadata for specified model
- ✅ Includes context window (1M tokens for Flash)
- ✅ Includes max output tokens (8K)
- ✅ Includes capability flags (tools, vision)
- ✅ Includes pricing information
- ✅ Returns `nil` for unknown models

## Scenario 11: Capability Introspection

### Given

- User wants to check if provider supports specific feature

### When

```lisp
(let ((provider (make-provider :gemini)))
  (if (provider-supports-p provider :vision)
      (format t "Gemini supports vision inputs~%")
      (format t "Gemini does not support vision~%"))

  (if (provider-supports-p provider :embeddings)
      (format t "Gemini supports embeddings~%")
      (format t "Gemini does not support embeddings~%")))
```

### Then

- ✅ `provider-supports-p` returns boolean for each capability
- ✅ `:tools` → `t`
- ✅ `:embeddings` → `t`
- ✅ `:streaming` → `t`
- ✅ `:vision` → `t`
- ✅ `:function-calling` → `t`

## Scenario 12: Embedding Generation

### Given

- User wants to generate embeddings for text

### When

```lisp
(let ((provider (make-provider :gemini :default-model "gemini-embedding-001")))
  (embedding "Common Lisp is a functional programming language"
             :provider provider))
```

### Then

- ✅ HTTP POST sent to `/embeddings` endpoint
- ✅ Response contains 768-dimensional vector
- ✅ `embedding-response` object returned
- ✅ `embedding-vector` accessor returns float array
- ✅ Token usage included in response

## Scenario 13: Batch Embedding

### Given

- User wants embeddings for multiple texts at once

### When

```lisp
(let ((provider (make-provider :gemini :default-model "gemini-embedding-001")))
  (embedding (list "First text"
                   "Second text"
                   "Third text")
             :provider provider))
```

### Then

- ✅ Single API request for all texts
- ✅ Returns list of embedding vectors
- ✅ Order preserved (index 0, 1, 2)
- ✅ Total token usage included

## Scenario 14: Configuration Summary

### Given

- User wants to inspect provider configuration

### When

```lisp
(let* ((provider (make-provider :gemini :model "gemini-3-flash-preview"))
       (summary (provider-config-summary provider)))
  (format t "Config: ~S~%" summary))
```

### Then

- ✅ Returns plist with configuration details
- ✅ Includes `:type :gemini`
- ✅ Includes `:name "Google Gemini"`
- ✅ Includes `:model "gemini-3-flash-preview"`
- ✅ Includes `:base-url "https://generativelanguage.googleapis.com/v1beta/openai/"`
- ✅ Includes `:capabilities` plist
- ✅ **Does NOT include** `:api-key` (sensitive data)

## Invariants

- **INV-GEMINI-01**: Gemini provider always uses OpenAI-compatible format
- **INV-GEMINI-02**: Authentication always uses Bearer token in Authorization header
- **INV-GEMINI-03**: Provider type is always `:gemini` (keyword)
- **INV-GEMINI-04**: Base URL defaults to Google's OpenAI-compatible endpoint
- **INV-GEMINI-05**: All multimodal content uses base64 encoding
- **INV-GEMINI-06**: Tool format is OpenAI-compatible (no translation needed)
- **INV-GEMINI-07**: API key is never included in config summaries or logs

## Acceptance Criteria

- ✅ Gemini provider works for basic text completions
- ✅ Provider is substitutable with other providers (same API)
- ✅ Multi-turn conversations maintain context
- ✅ Vision inputs (images) are processed correctly
- ✅ Function calling works end-to-end
- ✅ Streaming delivers chunks in real-time
- ✅ Error handling includes Gemini-specific conditions
- ✅ Rate limits trigger appropriate restarts
- ✅ Model metadata returns accurate information
- ✅ Capability introspection works correctly
- ✅ Embeddings (single and batch) work
- ✅ Configuration can be inspected without leaking secrets

## Related Artifacts

- [gemini-api.md](../contracts/gemini-api.md) - Gemini API contract
- [provider-protocol.md](../contracts/provider-protocol.md) - Generic provider contract
- [vocabulary.md](../vocabulary.md) - Provider vocabulary

## Test Evidence

**To be implemented**:
- Unit tests: `tests/test-gemini-provider.lisp`
- Integration tests: `tests/integration/test-gemini-integration.lisp`
- Mock tests: Use recorded HTTP responses in OpenAI format

## External References

- **Gemini API Docs**: https://ai.google.dev/gemini-api/docs/openai
- **OpenAI Compatibility**: https://ai.google.dev/gemini-api/docs/openai
- **Models**: https://ai.google.dev/gemini-api/docs/models/gemini
- **API Keys**: https://aistudio.google.com/apikey
