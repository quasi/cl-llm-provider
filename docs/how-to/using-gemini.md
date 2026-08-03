# Using the Gemini Provider

<!-- Generated from: canon/features/providers/scenarios/gemini-provider-usage.md -->

This guide shows you how to use Google Gemini with cl-llm-provider for text completions, vision analysis, and embeddings.

## Prerequisites

- **API Key**: Get yours at https://aistudio.google.com/apikey
- **cl-llm-provider** installed ([see Quickstart](../quickstart.md))

## Quick Setup

Set your API key as an environment variable:

```bash
export GEMINI_API_KEY="your-api-key-here"
```

Or provide it directly when creating the provider:

```lisp
(make-provider :gemini :api-key "your-api-key-here")
```

## Basic Text Completion

The simplest way to use Gemini:

```lisp
(use-package :cl-llm-provider)

(let ((provider (make-provider :gemini :model "gemini-3-flash-preview")))
  (let ((response (complete '((:role "user" :content "What is Common Lisp?"))
                            :provider provider)))
    (format t "~A~%" (response-content response))))
```

**Expected output:**
```
Common Lisp is a multi-paradigm programming language that supports functional, procedural, and object-oriented programming...
```

## Switching from Another Provider

Gemini is a drop-in replacement. Change one line:

```lisp
;; Before: OpenAI
(let ((provider (make-provider :openai :model "gpt-4")))
  (complete messages :provider provider))

;; After: Gemini
(let ((provider (make-provider :gemini :model "gemini-3-pro-preview")))
  (complete messages :provider provider))
```

Everything else stays the same - same `complete` function, same message format, same response structure.

## Available Models

Gemini provides three models:

### Text Generation

| Model | Best For | Context | Cost |
|-------|----------|---------|------|
| **gemini-3-flash-preview** | Fast responses, high volume | 1M tokens | $0.075/$0.30 per 1M |
| **gemini-3-pro-preview** | Complex reasoning, long context | 2M tokens | $1.25/$5.00 per 1M |

### Embeddings

| Model | Dimensions | Cost |
|-------|------------|------|
| **gemini-embedding-001** | 768 | Free |

**Choosing a model:**
- **Flash**: Use for most tasks - fast and cost-effective
- **Pro**: Use when you need the massive 2M token context or advanced reasoning
- **Embedding**: Use for semantic search, clustering, similarity

## Multi-Turn Conversations

Build up conversation history by maintaining a message list:

```lisp
(let ((messages (list (list :role "user" :content "What is 2+2?")))
      (provider (make-provider :gemini)))

  ;; First turn
  (let ((response (complete messages :provider provider)))
    (format t "First: ~A~%" (response-content response))

    ;; Add assistant response to history
    (push (response-message response) messages)

    ;; Add next user message
    (push (list :role "user" :content "Now multiply that by 3") messages)

    ;; Second turn with context
    (let ((response2 (complete (reverse messages) :provider provider)))
      (format t "Second: ~A~%" (response-content response2)))))
```

**Output:**
```
First: 2 + 2 = 4
Second: 4 × 3 = 12
```

**Key points:**
- Push messages onto the list (newest first)
- Reverse before sending (oldest first for API)
- Include both user and assistant messages

## Vision: Analyzing Images

Gemini can analyze images. Supported formats: JPEG, PNG, WebP, GIF.

```lisp
;; This library ships no base64 encoder — use cl-base64 (or your own).
(let* ((bytes (with-open-file (s "path/to/image.jpg" :element-type '(unsigned-byte 8))
                (let ((buf (make-array (file-length s) :element-type '(unsigned-byte 8))))
                  (read-sequence buf s)
                  buf)))
       (data-url (format nil "data:image/jpeg;base64,~A"
                         (cl-base64:usb8-array-to-base64-string bytes)))
       (provider (make-provider :gemini :model "gemini-3-flash-preview")))

  (let ((response
          (complete (list (list :role "user"
                               :content (list
                                          (list :type "text"
                                                :text "What's in this image?")
                                          (list :type "image_url"
                                                :image_url (list :url data-url)))))
                    :provider provider)))
    (format t "~A~%" (response-content response))))
```

**Image format:**
- Use base64-encoded data URLs
- Prefix with `data:image/{type};base64,`
- Combine text and image in the same message

**Cost note:** Vision requests consume more tokens (~258 tokens per image for token counting purposes).

## Function Calling (Tools)

Let Gemini call your functions:

```lisp
(let* ((tools (list
                (define-tool "get_weather"
                             "Get current weather for a location"
                             '((:name "location" :type :string
                                :description "City name, e.g., 'Paris' or 'Tokyo'")))))
       (provider (make-provider :gemini))
       (messages (list (list :role "user"
                            :content "What's the weather in Paris?"))))

  ;; First request - Gemini decides to call tool
  (let ((response (complete messages :provider provider :tools tools)))
    (if (response-tool-calls response)
        (progn
          (format t "Gemini wants to call: ~A~%"
                  (tool-call-name (first (response-tool-calls response))))

          ;; Add assistant message with tool call
          (push (response-message response) messages)

          ;; Execute tool and add result
          (let* ((tc (first (response-tool-calls response)))
                 (result "{\"temperature\": 18, \"condition\": \"sunny\"}"))
            (push (list :role "tool"
                       :tool_call_id (tool-call-id tc)
                       :content result)
                  messages))

          ;; Send back to Gemini with results
          (let ((final (complete (reverse messages)
                                :provider provider
                                :tools tools)))
            (format t "Final: ~A~%" (response-content final))))
        (format t "No tool call: ~A~%" (response-content response)))))
```

**Expected flow:**
```
Gemini wants to call: get_weather
Final: The weather in Paris is currently 18°C and sunny.
```

**Tool format notes:**
- Gemini uses OpenAI-compatible tool format (no translation needed)
- Tool results should be JSON strings
- Include `tool_call_id` to match calls with results

## Streaming Responses

Get tokens as they're generated:

```lisp
(let ((provider (make-provider :gemini))
      (full-content ""))

  (complete-stream '((:role "user" :content "Write a haiku about Lisp"))
                   :provider provider
                   :on-chunk (lambda (chunk)
                               (let ((delta (chunk-content chunk)))
                                 (when delta
                                   (setf full-content
                                         (concatenate 'string full-content delta))
                                   (format t "~A" delta)
                                   (force-output)))))

  (format t "~%~%Complete text: ~A~%" full-content))
```

**Output (as it streams):**
```
Parentheses dance
Code as data, elegance
Lisp's ancient grace

Complete text: Parentheses dance...
```

## Embeddings

Generate 768-dimensional embeddings for text:

```lisp
;; Single text
(let ((provider (make-provider :gemini :model "gemini-embedding-001")))
  (let ((response (embedding "Common Lisp is a functional language"
                            :provider provider)))
    ;; RESPONSE-EMBEDDINGS is a LIST of vectors, one per input.
    (let ((vec (first (response-embeddings response))))
      (format t "Vector length: ~D~%" (length vec))
      (format t "First 5 values: ~{~,3F ~}~%" (subseq vec 0 5)))))
```

**Output:**
```
Vector length: 768
First 5 values: 0.023 -0.041 0.102 -0.015 0.067
```

**Batch embeddings:**

```lisp
;; Multiple texts in one request
(let ((provider (make-provider :gemini :model "gemini-embedding-001")))
  (let ((responses (embedding (list "First text"
                                    "Second text"
                                    "Third text")
                              :provider provider)))
    (format t "Got ~D embedding vectors~%" (length responses))))
```

**Use cases:**
- Semantic search (find similar documents)
- Clustering (group related texts)
- Classification (train classifier on embeddings)

## Checking Capabilities

Before using a feature, check if it's supported:

```lisp
(let ((provider (make-provider :gemini)))
  (format t "Vision: ~A~%" (provider-supports-p provider :vision))
  (format t "Tools: ~A~%" (provider-supports-p provider :tools))
  (format t "Streaming: ~A~%" (provider-supports-p provider :streaming))
  (format t "Embeddings: ~A~%" (provider-supports-p provider :embeddings)))
```

**Output:**
```
Vision: T
Tools: T
Streaming: T
Embeddings: T
```

All capabilities are supported by Gemini.

## Getting Model Metadata

Query model limits and pricing before making requests:

```lisp
(let* ((provider (make-provider :gemini))
       (meta (model-metadata provider "gemini-3-flash-preview")))
  (format t "Context window: ~:D tokens~%" (getf meta :context-window))
  (format t "Max output: ~:D tokens~%" (getf meta :max-output-tokens))
  (format t "Input: $~,3F per 1M tokens~%" (getf meta :input-cost-per-1m-tokens))
  (format t "Output: $~,3F per 1M tokens~%" (getf meta :output-cost-per-1m-tokens))
  (format t "Supports vision: ~A~%" (getf meta :supports-vision)))
```

**Output:**
```
Context window: 1,048,576 tokens
Max output: 8,192 tokens
Input: $0.075 per 1M tokens
Output: $0.300 per 1M tokens
Supports vision: T
```

## Error Handling

Handle authentication and rate limits gracefully:

**Invalid API key:**

```lisp
;; handler-BIND, not handler-CASE. handler-case unwinds the stack before its
;; body runs, which disestablishes every restart the signalling code set up —
;; `invoke-restart` there signals control-error instead of recovering.
(handler-bind
    ((provider-authentication-error
       (lambda (e)
         (format t "Auth failed: ~A~%" e)
         ;; Provide correct key via restart
         (let ((r (find-restart 'use-value e)))
           (when r (invoke-restart r (uiop:getenv "GEMINI_API_KEY")))))))
  (let ((provider (make-provider :gemini :api-key "invalid")))
    (complete '((:role "user" :content "Hello")) :provider provider)))
```

**Rate limits:**

```lisp
(handler-bind
    ((provider-rate-limit-error
       (lambda (e)
         (format t "Rate limited. Waiting and retrying...~%")
         (let ((r (find-restart 'wait-and-retry e)))
           (when r (invoke-restart r))))))
  (complete messages :provider provider))
```

**Available restarts:**
- `use-value` - Provide a new value (e.g., different API key)
- `wait-and-retry` - Wait and automatically retry
- `use-fallback-provider` - Switch to a different provider. Takes an optional
  second argument, the model to use there — pass it whenever the fallback is a
  different service, since Gemini's model names mean nothing to anyone else
- `use-model` - Retry against the *same* provider with a different model name

See [Local models and failover](local-models-and-failover.md) for the
local-first pattern these two are built for.

## Configuration Inspection

View provider configuration without exposing secrets:

```lisp
(let* ((provider (make-provider :gemini :model "gemini-3-flash-preview"))
       (summary (provider-config-summary provider)))
  (format t "Config: ~S~%" summary))
```

**Output:**
```
(:TYPE :GEMINI
 :NAME "Google Gemini"
 :MODEL "gemini-3-flash-preview"
 :BASE-URL "https://generativelanguage.googleapis.com/v1beta/openai/"
 :CAPABILITIES (:TOOLS T :EMBEDDINGS T :STREAMING T :VISION T))
```

**Note:** API key is never included in config summaries for security.

## Common Patterns

### Pattern 1: Try Gemini, Fall Back to OpenAI

```lisp
(let ((gemini (make-provider :gemini))
      (openai (make-provider :openai)))
  (handler-case
      (complete messages :provider gemini)
    (provider-error (e)
      (warn "Gemini failed: ~A. Trying OpenAI..." e)
      (complete messages :provider openai))))
```

### Pattern 2: Cost-Optimize with Flash → Pro

Start with fast/cheap Flash, escalate to Pro if needed:

```lisp
(let ((flash (make-provider :gemini :model "gemini-3-flash-preview"))
      (pro (make-provider :gemini :model "gemini-3-pro-preview")))
  (let ((response (complete messages :provider flash)))
    (if (eq (response-finish-reason response) :length)
        ;; Hit token limit, retry with Pro's larger context
        (complete messages :provider pro)
        response)))
```

### Pattern 3: Check Before Using Features

```lisp
(defun safe-complete-with-vision (messages provider)
  (if (provider-supports-p provider :vision)
      (complete messages :provider provider)
      (error "Provider ~A doesn't support vision" (provider-name provider))))
```

## Troubleshooting

**"Invalid API key"**
- Verify key at https://aistudio.google.com/apikey
- Check `GEMINI_API_KEY` environment variable is set
- Ensure no extra whitespace in key

**"Rate limit exceeded"**
- Free tier: 15 requests/minute
- Wait 60 seconds or use `wait-and-retry` restart
- Consider upgrading to paid tier for higher limits

**"Model not found"**
- Use exact model names: `gemini-3-flash-preview`, `gemini-3-pro-preview`
- Check model availability in your region
- Some models require API access approval

**Vision requests fail**
- Verify image is base64-encoded
- Check image format (JPEG, PNG, WebP, GIF only)
- Ensure data URL has correct prefix: `data:image/jpeg;base64,`
- Image size limits: 10MB max

## API Reference

See the main [API Reference](../reference/api.md) for complete function signatures and parameters.

## Related Documentation

- [Quickstart](../quickstart.md) - Get started in 5 minutes
- [Error Handling](error-handling.md) - Comprehensive error handling patterns
- [Tools](tools.md) - Advanced tool/function calling
- [Streaming](streaming.md) - Streaming response details
- [Provider Comparison](../explanation/providers.md) - Compare Gemini with other providers

## External Resources

- **Gemini API Documentation**: https://ai.google.dev/gemini-api/docs/openai
- **Model Information**: https://ai.google.dev/gemini-api/docs/models/gemini
- **Pricing**: https://ai.google.dev/pricing
- **Get API Key**: https://aistudio.google.com/apikey
