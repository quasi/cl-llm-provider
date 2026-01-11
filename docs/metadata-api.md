# Metadata and Introspection API

**Query provider capabilities, model metadata, and response context without trial-and-error.**

---

## What Is This?

The metadata API lets you ask questions about providers and models before making API calls:
- "Does this provider support tools?"
- "What's the context window for GPT-4o?"
- "Which provider sent this response?"

Without this API, you'd need to use `typecase` on provider classes (fragile) or try operations and catch errors (wasteful).

---

## Quick Start

### Get Provider Information

```lisp
(use-package :cl-llm-provider)

;; Create a provider
(let ((provider (make-provider :openai :model "gpt-4o")))

  ;; What type is it? → :openai
  (provider-type provider)

  ;; Human-readable name → "OpenAI"
  (provider-name provider)

  ;; Does it support tools? → T
  (provider-supports-p provider :tools)

  ;; Does it support embeddings? → T
  (provider-supports-p provider :embeddings))
```

**Expected output**:
```
:OPENAI
"OpenAI"
T
T
```

**You now have provider introspection working.** See below for model metadata and advanced usage.

---

## Common Use Cases

### 1. Check If Feature Is Supported

**Problem**: You want to use tools, but not all providers support them.

**Solution**: Check before calling.

```lisp
(defun complete-with-tools-if-supported (messages tools)
  "Use tools only if the configured provider supports them."
  (let ((provider (get-default-provider)))
    (if (provider-supports-p provider :tools)
        (progn
          (format t "~A supports tools, enabling~%" (provider-name provider))
          (complete messages :tools tools))
        (progn
          (warn "~A doesn't support tools, using plain completion"
                (provider-name provider))
          (complete messages)))))
```

---

### 2. Display Provider Info in Logs

**Problem**: You need to log which provider handled a request.

**Solution**: Use `provider-name` for human-readable output.

```lisp
(defun log-completion (provider messages)
  "Log which provider is handling the request."
  (format t "[~A] Sending ~D messages to ~A~%"
          (provider-name provider)        ; "OpenAI", "Anthropic", etc.
          (length messages)
          (provider-default-model provider)))

;; Output: [OpenAI] Sending 3 messages to gpt-4o
```

---

### 3. Check Model Context Window

**Problem**: You need to verify messages fit within the model's context limit.

**Solution**: Query model metadata for context window.

```lisp
(defun check-fits-in-context (provider model messages)
  "Verify messages fit within model's context window."
  (let ((meta (model-metadata provider model)))
    (if meta
        (let ((ctx-window (getf meta :context-window))
              (estimated-tokens (estimate-message-tokens messages)))
          (if (> estimated-tokens ctx-window)
              (error "Messages (~D tokens) exceed ~A context (~D tokens)"
                     estimated-tokens model ctx-window)
              (format t "✓ Messages fit: ~D / ~D tokens~%"
                      estimated-tokens ctx-window)))
        ;; No metadata available for this model
        (warn "No metadata for ~A, cannot verify context limit" model))))

;; Usage
(check-fits-in-context
  (make-provider :openai)
  "gpt-4o-mini"
  my-messages)
;; Output: ✓ Messages fit: 1024 / 128000 tokens
```

---

### 4. Estimate API Costs

**Problem**: You want to estimate costs before making expensive calls.

**Solution**: Use model metadata pricing information.

```lisp
(defun estimate-completion-cost (provider model input-tokens output-tokens)
  "Calculate estimated cost in USD."
  (let ((meta (model-metadata provider model)))
    (if meta
        (let ((input-cost (getf meta :input-cost-per-1m-tokens))
              (output-cost (getf meta :output-cost-per-1m-tokens)))
          ;; Costs are per 1M tokens
          (+ (* input-tokens (/ input-cost 1000000.0))
             (* output-tokens (/ output-cost 1000000.0))))
        ;; Unknown model - can't estimate
        nil)))

;; Compare costs across providers
(let ((openai-cost (estimate-completion-cost
                     (make-provider :openai) "gpt-4o" 1000 500))
      (anthropic-cost (estimate-completion-cost
                        (make-provider :anthropic)
                        "claude-3-5-sonnet-20241022" 1000 500)))
  (format t "OpenAI:   $~,6F~%" openai-cost)
  (format t "Anthropic: $~,6F~%" anthropic-cost))

;; Output:
;; OpenAI:   $0.007500
;; Anthropic: $0.010500
```

---

### 5. Choose Provider Based on Requirements

**Problem**: You need to dynamically select a provider that meets specific requirements.

**Solution**: Filter providers by capabilities.

```lisp
(defun select-provider-with-vision (providers)
  "Select first provider that supports vision."
  (find-if (lambda (provider)
             (provider-supports-p provider :vision))
           providers))

;; Usage
(let* ((providers (list (make-provider :openai :model "gpt-4o")
                        (make-provider :anthropic :model "claude-3-5-sonnet-20241022")
                        (make-provider :ollama :model "llama3")))
       (vision-provider (select-provider-with-vision providers)))

  (if vision-provider
      (format t "Selected ~A for vision task~%"
              (provider-name vision-provider))
      (error "No provider supports vision")))

;; Output: Selected OpenAI for vision task
```

---

### 6. Get Provider Context from Response

**Problem**: You received a response and need to know which provider sent it.

**Solution**: Check response metadata.

```lisp
(defun log-response-details (response)
  "Log response with provider information."
  (let ((meta (response-metadata response)))
    (format t "Response from: ~A (~A)~%"
            (getf meta :provider-name)   ; "OpenAI"
            (getf meta :provider-type))  ; :openai

    (format t "Response ID: ~A~%" (response-id response))

    ;; Provider-specific metadata (varies by provider)
    (when-let ((fingerprint (getf meta :system-fingerprint)))
      (format t "System fingerprint: ~A~%" fingerprint))

    (when-let ((created (getf meta :created)))
      (format t "Created: ~A~%" created))))

;; Usage
(let ((response (complete '((:role "user" :content "Hello")))))
  (log-response-details response))

;; Output:
;; Response from: OpenAI (:openai)
;; Response ID: chatcmpl-abc123
;; System fingerprint: fp_xyz
;; Created: 1234567890
```

---

## Complete API Reference

### Provider Introspection

#### `provider-type`

```lisp
(provider-type provider) → keyword
```

Returns a keyword uniquely identifying the provider type.

**Returns**: One of `:openai`, `:anthropic`, `:ollama`, `:openrouter`, `:openai-compatible`

**Example**:
```lisp
(provider-type (make-provider :openai))  → :OPENAI
(provider-type (make-provider :anthropic))  → :ANTHROPIC
```

**Use case**: Dispatch based on provider type using `case` or `eql` specializers.

---

#### `provider-name`

```lisp
(provider-name provider) → string
```

Returns a human-readable name for the provider.

**Returns**: String like `"OpenAI"`, `"Anthropic"`, `"Ollama"`, etc.

**Example**:
```lisp
(provider-name (make-provider :openai))  → "OpenAI"
(provider-name (make-provider :anthropic))  → "Anthropic"
```

**Use case**: Display provider name in UI, logs, or error messages.

---

#### `provider-capabilities`

```lisp
(provider-capabilities provider) → plist
```

Returns a property list of provider capabilities.

**Returns**: Plist with keys:
- `:tools` - Boolean, supports tool/function calling
- `:embeddings` - Boolean, supports text embeddings
- `:streaming` - Boolean, supports streaming responses
- `:vision` - Boolean, supports image understanding
- `:function-calling` - Boolean, supports function calling (synonym for `:tools`)

**Example**:
```lisp
(provider-capabilities (make-provider :openai))
→ (:TOOLS T :EMBEDDINGS T :STREAMING T :VISION T :FUNCTION-CALLING T)

(provider-capabilities (make-provider :anthropic))
→ (:TOOLS T :EMBEDDINGS NIL :STREAMING T :VISION T :FUNCTION-CALLING T)
```

**Use case**: Check multiple capabilities at once, display all features to user.

---

#### `provider-supports-p`

```lisp
(provider-supports-p provider capability) → boolean
```

Check if provider supports a specific capability.

**Arguments**:
- `provider` - Provider instance
- `capability` - Keyword (`:tools`, `:embeddings`, `:streaming`, `:vision`, `:function-calling`)

**Returns**: `T` if supported, `NIL` if not supported

**Example**:
```lisp
(provider-supports-p (make-provider :openai) :tools)  → T
(provider-supports-p (make-provider :anthropic) :embeddings)  → NIL
(provider-supports-p (make-provider :ollama) :vision)  → NIL
```

**Use case**: Conditional feature enabling based on provider capabilities.

---

#### `provider-config-summary`

```lisp
(provider-config-summary provider) → plist
```

Returns configuration summary for the provider (without sensitive data).

**Returns**: Plist with keys:
- `:type` - Provider type keyword
- `:name` - Provider name string
- `:model` - Default model string
- `:base-url` - API base URL string
- `:capabilities` - Capabilities plist

**Note**: API key is explicitly excluded for security.

**Example**:
```lisp
(provider-config-summary (make-provider :openai :model "gpt-4o"))
→ (:TYPE :OPENAI
   :NAME "OpenAI"
   :MODEL "gpt-4o"
   :BASE-URL "https://api.openai.com/v1"
   :CAPABILITIES (:TOOLS T :EMBEDDINGS T ...))
```

**Use case**: Serialize provider configuration for logging, debugging, or API responses.

---

### Model Metadata

#### `model-metadata`

```lisp
(model-metadata provider model-name) → plist or nil
```

Get metadata for a specific model.

**Arguments**:
- `provider` - Provider instance
- `model-name` - String, name of model (e.g., `"gpt-4o"`, `"claude-3-5-sonnet-20241022"`)

**Returns**: Plist with keys (if model is known), or `NIL` (if model is unknown):
- `:context-window` - Integer, maximum context size in tokens
- `:max-output-tokens` - Integer, maximum output length
- `:supports-tools` - Boolean, model supports tool calling
- `:supports-vision` - Boolean, model supports vision
- `:input-cost-per-1m-tokens` - Float, input cost in USD per 1M tokens
- `:output-cost-per-1m-tokens` - Float, output cost in USD per 1M tokens

**Example**:
```lisp
(model-metadata (make-provider :openai) "gpt-4o")
→ (:CONTEXT-WINDOW 128000
   :MAX-OUTPUT-TOKENS 16384
   :SUPPORTS-TOOLS T
   :SUPPORTS-VISION T
   :INPUT-COST-PER-1M-TOKENS 2.5
   :OUTPUT-COST-PER-1M-TOKENS 10.0)

(model-metadata (make-provider :openai) "unknown-model")
→ NIL
```

**Supported models**:
- **OpenAI**: gpt-4o, gpt-4o-mini, gpt-4-turbo, gpt-4, gpt-3.5-turbo (see `src/model-registry.lisp` for complete list)
- **Anthropic**: claude-opus-4-20250514, claude-sonnet-4-20250514, claude-3-5-sonnet-20241022, claude-3-5-haiku-20241022, claude-3-opus-20240229 (see registry for complete list)
- **Ollama, OpenRouter**: Returns `NIL` (no built-in registry)

**Use case**: Get model specifications before making requests, estimate costs, validate context limits.

---

#### `register-model-metadata`

```lisp
(register-model-metadata registry model-name metadata) → metadata
```

Register metadata for a custom model.

**Arguments**:
- `registry` - Hash table (use `*openai-model-registry*`, `*anthropic-model-registry*`, or create custom)
- `model-name` - String, model identifier
- `metadata` - Plist with same structure as `model-metadata` return value

**Returns**: The registered metadata plist

**Example**:
```lisp
;; Register custom fine-tuned model
(register-model-metadata *openai-model-registry*
                         "gpt-4-company-finetune"
                         '(:context-window 128000
                           :max-output-tokens 16384
                           :supports-tools t
                           :supports-vision t
                           :input-cost-per-1m-tokens 30.00
                           :output-cost-per-1m-tokens 60.00))

;; Register local Ollama model
(defvar *my-registry* (make-hash-table :test 'equal))
(register-model-metadata *my-registry*
                         "llama3:70b-instruct"
                         '(:context-window 8192
                           :max-output-tokens 4096
                           :supports-tools t
                           :supports-vision nil
                           :input-cost-per-1m-tokens 0.0  ; Local - free
                           :output-cost-per-1m-tokens 0.0))
```

**Important**: Registry must be created with `(make-hash-table :test 'equal)` for string key lookups to work.

---

### Response Metadata

#### `response-metadata`

```lisp
(response-metadata response) → plist
```

Get metadata from completion or embedding response.

**Returns**: Plist with guaranteed keys:
- `:provider-type` - Keyword, which provider sent this response
- `:provider-name` - String, human-readable provider name

Plus optional provider-specific keys:
- `:system-fingerprint` - String (OpenAI, OpenRouter)
- `:created` - Integer timestamp (OpenAI, Anthropic, OpenRouter)
- `:stop-sequence` - String (Anthropic)
- `:total-duration-ns` - Integer nanoseconds (Ollama)
- `:completion-tokens-details` - Plist (OpenAI - for o1/o3 reasoning tokens)
- `:prompt-tokens-details` - Plist (OpenAI - for cached tokens)

**Example**:
```lisp
(let* ((response (complete '((:role "user" :content "Hi"))))
       (meta (response-metadata response)))

  ;; Always present
  (getf meta :provider-type)  → :OPENAI
  (getf meta :provider-name)  → "OpenAI"

  ;; Provider-specific (may be NIL)
  (getf meta :system-fingerprint)  → "fp_abc123"
  (getf meta :created)  → 1234567890)
```

**Use case**: Track which provider handled request, extract provider-specific metadata, debugging.

---

## Capability Reference

### Standard Capabilities

| Capability | Description | OpenAI | Anthropic | Ollama | OpenRouter |
|------------|-------------|--------|-----------|--------|------------|
| `:tools` | Tool/function calling | ✅ | ✅ | ✅ | ✅ |
| `:embeddings` | Text embeddings API | ✅ | ❌ | ✅ | ❌ |
| `:streaming` | Streaming responses | ✅ | ✅ | ✅ | ✅ |
| `:vision` | Image understanding | ✅ | ✅ | ❌* | ✅* |
| `:function-calling` | Same as `:tools` | ✅ | ✅ | ✅ | ✅ |

*Model-dependent - conservative default

---

## Model Metadata Reference

### Metadata Schema

All registered models have this metadata structure:

```lisp
(:context-window <integer>           ; Max total tokens (input + output)
 :max-output-tokens <integer>        ; Max output length
 :supports-tools <boolean>           ; Model supports tool calling
 :supports-vision <boolean>          ; Model supports images
 :input-cost-per-1m-tokens <float>   ; USD per 1M input tokens
 :output-cost-per-1m-tokens <float>) ; USD per 1M output tokens
```

### Registered Models

#### OpenAI Models

| Model | Context | Max Output | Tools | Vision | Input Cost | Output Cost |
|-------|---------|------------|-------|--------|------------|-------------|
| gpt-4o | 128K | 16K | ✅ | ✅ | $2.50 | $10.00 |
| gpt-4o-mini | 128K | 16K | ✅ | ✅ | $0.15 | $0.60 |
| gpt-4-turbo | 128K | 4K | ✅ | ✅ | $10.00 | $30.00 |
| gpt-4 | 8K | 8K | ✅ | ❌ | $30.00 | $60.00 |
| gpt-3.5-turbo | 16K | 4K | ✅ | ❌ | $0.50 | $1.50 |

#### Anthropic Models

| Model | Context | Max Output | Tools | Vision | Input Cost | Output Cost |
|-------|---------|------------|-------|--------|------------|-------------|
| claude-opus-4-20250514 | 200K | 32K | ✅ | ✅ | $15.00 | $75.00 |
| claude-sonnet-4-20250514 | 200K | 16K | ✅ | ✅ | $3.00 | $15.00 |
| claude-3-5-sonnet-20241022 | 200K | 8K | ✅ | ✅ | $3.00 | $15.00 |
| claude-3-5-haiku-20241022 | 200K | 8K | ✅ | ✅ | $0.80 | $4.00 |
| claude-3-opus-20240229 | 200K | 4K | ✅ | ✅ | $15.00 | $75.00 |

See `src/model-registry.lisp` for the complete and up-to-date model list.

---

## Troubleshooting

### Error: `model-metadata` always returns NIL

**Cause**: Model name doesn't match registry key exactly (case-sensitive, must be exact string).

**Fix**: Check spelling and case:
```lisp
;; WRONG
(model-metadata provider "GPT-4O")  ; Wrong case

;; RIGHT
(model-metadata provider "gpt-4o")  ; Exact match
```

---

### Error: Custom registry lookups fail

**Cause**: Hash table was created with wrong test (`:test 'eq` instead of `:test 'equal`).

**Fix**: Create registry with `'equal` test:
```lisp
;; WRONG
(defvar *my-registry* (make-hash-table :test 'eq))

;; RIGHT
(defvar *my-registry* (make-hash-table :test 'equal))
```

---

### Warning: No metadata for newly released model

**Cause**: Model was released after the library version was published.

**Fix**: Register the model yourself:
```lisp
(register-model-metadata *openai-model-registry* "gpt-5"
  '(:context-window 256000
    :max-output-tokens 32768
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 5.00
    :output-cost-per-1m-tokens 15.00))
```

---

## Advanced Patterns

### Creating a Provider Selection Function

```lisp
(defun select-best-provider-for-task (task-requirements)
  "Select optimal provider based on requirements and cost."
  (let ((candidates '()))

    ;; Collect providers that meet requirements
    (dolist (provider-type '(:openai :anthropic :ollama))
      (let ((provider (make-provider provider-type)))
        (when (every (lambda (req)
                       (provider-supports-p provider req))
                     (getf task-requirements :capabilities))
          (push provider candidates))))

    ;; Sort by cost (prefer cheapest)
    (when candidates
      (first (sort candidates #'<
                   :key (lambda (p)
                          (or (getf (model-metadata p (provider-default-model p))
                                    :input-cost-per-1m-tokens)
                              most-positive-fixnum)))))))

;; Usage
(select-best-provider-for-task
  '(:capabilities (:tools :embeddings)))
→ Returns cheapest provider supporting tools and embeddings
```

---

### Cost-Aware Request Routing

```lisp
(defun complete-with-cost-limit (messages max-cost-usd)
  "Complete using cheapest provider under cost limit."
  (let ((providers (list (make-provider :openai :model "gpt-4o-mini")
                         (make-provider :anthropic :model "claude-3-5-haiku-20241022"))))

    (dolist (provider providers)
      (let* ((model (provider-default-model provider))
             (meta (model-metadata provider model))
             (estimated-cost (when meta
                              (* 1000  ; Estimate 1000 tokens
                                 (/ (getf meta :input-cost-per-1m-tokens)
                                    1000000.0)))))

        (when (and estimated-cost (< estimated-cost max-cost-usd))
          (format t "Using ~A (~A) - estimated cost: $~,6F~%"
                  (provider-name provider) model estimated-cost)
          (return (complete messages :provider provider)))))

    (error "No provider found under cost limit $~,2F" max-cost-usd)))
```

---

## What's Next?

- **See**: [API Reference](reference/api.md) for complete function documentation
- **See**: [How-To: Add a Provider](how-to/add-provider.md) to implement your own provider
- **See**: [Agent Documentation](agent/METADATA-API.agent.md) for formal specification

---

## Summary

You now know how to:
- ✅ Check provider capabilities with `provider-supports-p`
- ✅ Get human-readable provider names with `provider-name`
- ✅ Query model metadata with `model-metadata`
- ✅ Estimate API costs using metadata pricing
- ✅ Extract provider context from responses
- ✅ Register custom models with `register-model-metadata`

The metadata API eliminates guesswork and trial-and-error when working with multiple providers.
