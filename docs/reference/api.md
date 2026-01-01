# Reference: Complete API

Complete API reference for cl-llm-provider.

---

## Core Functions

### `complete`

Send a completion request to an LLM.

```lisp
(complete messages &key provider model max-tokens temperature
                        system tools tool-choice stop
                        enable-profiling)
→ completion-response
```

**Parameters**:
- `messages` (list) - Conversation messages
- `:provider` (provider) - Provider instance (default: auto-detect)
- `:model` (string) - Model name override
- `:max-tokens` (integer) - Max response length
- `:temperature` (float 0-1) - Response randomness
- `:system` (string) - System message/instructions
- `:tools` (list) - Available tools
- `:tool-choice` (keyword) - `:auto`, `:required`, tool name
- `:stop` (list) - Stop generation at strings
- `:enable-profiling` (boolean) - Enable timing breakdown

**Returns**: `completion-response` object

**Example**:
```lisp
(let ((response (complete '((:role "user" :content "Hello"))
                         :provider (make-provider :anthropic)
                         :max-tokens 100
                         :temperature 0.7)))
  (response-content response))
```

### `embedding`

Get vector embeddings for text.

```lisp
(embedding texts &key provider model)
→ vector or list of vectors
```

**Parameters**:
- `texts` (string or list) - Text(s) to embed
- `:provider` (provider) - Provider instance
- `:model` (string) - Model override

**Returns**: Single vector (list of floats) or list of vectors

**Example**:
```lisp
(let ((embedding (embedding "The quick brown fox"
                           :provider (make-provider :openai))))
  (length embedding))  ; Vector length
```

### `token-count`

Count tokens in messages or text.

```lisp
(token-count input &key provider)
→ integer
```

**Parameters**:
- `input` (string or list) - Text or messages to count
- `:provider` (provider) - Provider instance

**Returns**: Number of tokens

**Example**:
```lisp
(let ((tokens (token-count '((:role "user" :content "Hello")))))
  (format t "Tokens: ~A~%" tokens))
```

---

## Provider Functions

### `make-provider`

Create a provider instance.

```lisp
(make-provider type &rest options)
→ provider
```

**Types**:
- `:anthropic` - Anthropic (Claude)
- `:openai` - OpenAI (GPT)
- `:ollama` - Ollama (local)
- `:openrouter` - OpenRouter
- `:openai-compatible` - Generic OpenAI-compatible

**Options**:
- `:api-key` (string) - API key (auto from env if not provided)
- `:model` (string) - Default model
- `:base-url` (string) - API base URL (for custom endpoints)

**Example**:
```lisp
;; Anthropic (auto API key)
(make-provider :anthropic)

;; OpenAI with model override
(make-provider :openai :model "gpt-4")

;; Ollama local
(make-provider :ollama :base-url "http://localhost:11434")

;; Custom OpenAI-compatible
(make-provider :openai-compatible
              :base-url "https://api.example.com/v1"
              :api-key "sk-...")
```

### `provider-api-key`

Get provider's API key.

```lisp
(provider-api-key provider) → string
```

### `provider-default-model`

Get provider's default model.

```lisp
(provider-default-model provider) → string
```

### `provider-base-url`

Get provider's base URL.

```lisp
(provider-base-url provider) → string
```

---

## Tool Functions

### `define-tool`

Define a tool that LLMs can call.

```lisp
(define-tool name description parameters
             &key required handler safety-level
                  categories requires-approval
                  parameter-validators
                  on-start on-complete on-error
                  metadata)
```

**Parameters**:
- `name` (string) - Tool name (how LLM calls it)
- `description` (string) - What the tool does
- `parameters` (list) - Input parameter definitions
- `:required` (list) - Required parameter names
- `:handler` (function) - Function that executes tool
- `:safety-level` (keyword) - `:safe`, `:moderate`, `:dangerous`
- `:categories` (list) - Category keywords
- `:requires-approval` (boolean or function) - Require user approval
- `:parameter-validators` (list) - Validation rules
- `:on-start` (function) - Called before execution
- `:on-complete` (function) - Called after execution
- `:on-error` (function) - Called on error
- `:metadata` (plist) - Arbitrary metadata

**Example**:
```lisp
(define-tool "search"
  "Search the web"
  '((:name "query" :type :string)
    (:name "limit" :type :integer))
  :required '("query")
  :safety-level :safe
  :categories '(:search :external-api)
  :handler (lambda (args) ...))
```

### `get-tool`

Get a registered tool.

```lisp
(get-tool name) → tool or nil
```

### `list-tools`

List all registered tools.

```lisp
(list-tools) → list of tools
```

### `execute-tool`

Execute a tool by name.

```lisp
(execute-tool name arguments) → result
```

---

## Response Objects

### `completion-response`

Result from `complete`.

**Accessors**:
- `(response-id response)` - Response ID
- `(response-model response)` - Model used
- `(response-content response)` - Text content
- `(response-message response)` - Full message (role + content)
- `(response-tool-calls response)` - List of tool calls (if any)
- `(response-finish-reason response)` - Why it stopped (`:stop`, `:length`, etc.)
- `(response-token-count response)` - Tokens used
- `(response-provider response)` - Provider keyword
- `(response-metadata response)` - Provider-specific metadata
- `(response-profiling response)` - Timing breakdown (if enabled)

**Example**:
```lisp
(let ((response (complete messages)))
  (format t "Content: ~A~%" (response-content response))
  (format t "Tokens: ~A~%" (response-token-count response))
  (when (response-tool-calls response)
    (dolist (call (response-tool-calls response))
      (format t "Tool: ~A~%" (getf call :name)))))
```

### Tool Response Objects

**Tool Definition** (from `get-tool`):
- `(tool-name tool)` - Tool name
- `(tool-description tool)` - Description
- `(tool-parameters tool)` - Parameter definitions
- `(tool-required-parameters tool)` - Required params
- `(tool-handler tool)` - Handler function
- `(tool-safety-level tool)` - Safety level keyword
- `(tool-categories tool)` - Category list
- `(tool-metadata tool)` - Metadata plist

---

## Error Types

All inherit from `error`. Catch with `handler-case`:

```lisp
(handler-case
  (complete messages)

  ;; Transient errors (safe to retry)
  (rate-limit-error (e)
    (sleep 60)
    (complete messages))

  (timeout-error (e)
    (complete messages))

  (network-error (e)
    (complete messages))

  ;; Permanent errors (don't retry)
  (authentication-error (e)
    (format t "Auth failed: ~A~%" (error-message e)))

  (provider-error (e)
    (format t "Provider error: ~A~%" (error-message e)))

  ;; Catch all
  (error (e)
    (format t "Unknown error: ~A~%" e)))
```

**Error Types**:
- `rate-limit-error` - Too many requests
- `timeout-error` - Request timed out
- `network-error` - Connection failed
- `authentication-error` - Invalid credentials
- `provider-error` - API returned error
- `provider-configuration-error` - Missing config
- `validation-error` - Parameter validation failed

**Error Accessors**:
- `(error-message error)` - Error message string
- `(error-status-code error)` - HTTP status (if applicable)

---

## Configuration

### Environment Variables

- `ANTHROPIC_API_KEY` - Anthropic API key
- `OPENAI_API_KEY` - OpenAI API key
- `OPENROUTER_API_KEY` - OpenRouter API key
- `OLLAMA_BASE_URL` - Ollama base URL (default: http://localhost:11434)

### Runtime Configuration

```lisp
;; Set default provider
(setf cl-llm-provider:*default-provider* :anthropic)

;; Set default model
(setf cl-llm-provider:*default-model* "claude-3-sonnet-20240229")

;; Disable token counting
(setf cl-llm-provider:*enable-token-counting* nil)

;; Set HTTP timeout
(setf dexador:*default-connect-timeout* 30)
```

---

## Profiling

### Performance Timing

Enable with `:enable-profiling t`:

```lisp
(let ((response (complete messages :enable-profiling t)))
  (when (response-profiling response)
    (let ((prof (response-profiling response)))
      (format t "Encode: ~Ams~%" (getf prof :encode-time))
      (format t "API: ~Ams~%" (getf prof :api-time))
      (format t "Decode: ~Ams~%" (getf prof :decode-time))
      (format t "Total: ~Ams~%" (getf prof :total-time)))))
```

**Profiling Fields**:
- `:encode-time` - Time to format request
- `:api-time` - Time waiting for API response
- `:decode-time` - Time to parse response
- `:total-time` - Total elapsed time

---

## Utilities

### Message Building

```lisp
;; Create a user message
(list :role "user" :content "Hello")

;; Create an assistant message
(list :role "assistant" :content "Hi there")

;; Build conversation
(let ((messages '()))
  (push (list :role "user" :content "Q1") messages)
  (push (response-message response1) messages)
  (push (list :role "user" :content "Q2") messages)
  (reverse messages))
```

### Tool Parameter Types

```lisp
;; String
(:name "query" :type :string)

;; Integer
(:name "count" :type :integer)

;; Number (float)
(:name "temperature" :type :number)

;; Boolean
(:name "enabled" :type :boolean)
```

---

## Quick Reference

**Most Common Operations**:

```lisp
;; 1. Simple completion
(complete '((:role "user" :content "Hello")))

;; 2. Multi-turn conversation
(complete (list
  (list :role "user" :content "Q1")
  (response-message response1)
  (list :role "user" :content "Q2")))

;; 3. With tools
(complete messages :tools (list (get-tool "search")))

;; 4. Token counting
(token-count messages)

;; 5. Switch providers
(complete messages :provider (make-provider :openai))

;; 6. Error handling
(handler-case
  (complete messages)
  (rate-limit-error (e) (sleep 60) (complete messages)))
```

---

**See Also**:
- [Quick Start](../quickstart.md)
- [Tutorials](../tutorials/01-basics.md)
- [How-To Guides](../how-to/tools.md)
