# Reference: Complete API

Complete API reference for cl-llm-provider.

---

## Core Functions

### `complete`

Send a completion request to an LLM.

```lisp
(complete messages &key provider model max-tokens temperature
                        system tools tool-choice stop
                        hooks on-request on-response on-error)
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
- `:hooks` (hooks) - Hook set from `make-hooks`
- `:on-request` (function) - Called with the outgoing request
- `:on-response` (function) - Called with `(response timing)`
- `:on-error` (function) - Called with the signalled condition

Profiling is enabled by binding `*performance-profiling*`, not by a keyword.

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
(embedding input &key provider model dimensions)
→ embedding-response
```

**Parameters**:
- `input` (string or list) - Text(s) to embed
- `:provider` (provider) - Provider instance
- `:model` (string) - Model override
- `:dimensions` (integer) - Requested output dimensions, when supported by the provider

**Returns**: `embedding-response`; use `(response-embeddings response)` for vectors

**Example**:
```lisp
(let ((response (embedding "The quick brown fox"
                           :provider (make-provider :openai))))
  (length (first (response-embeddings response))))  ; Vector length
```

### `count-tokens`

Count tokens in messages.

```lisp
(count-tokens messages &key model provider)
→ integer
```

**Parameters**:
- `messages` (list) - Messages to count
- `:model` (string) - Model whose tokenizer to assume
- `:provider` (provider) - Provider instance

See also `count-tokens-with-system`, which includes a system prompt.

**Returns**: Number of tokens

**Example**:
```lisp
(let ((tokens (count-tokens '((:role "user" :content "Hello")))))
  (format t "Tokens: ~A~%" tokens))
```

---

## Provider Functions

### `make-provider`

Create a provider instance.

```lisp
(make-provider provider-type &key api-key base-url model options)
→ provider
```

**Types**:
- `:anthropic` - Anthropic (Claude)
- `:openai` - OpenAI (GPT)
- `:gemini` - Google Gemini
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

;; Google Gemini
(make-provider :gemini :model "gemini-3-flash-preview")

;; Ollama local
(make-provider :ollama :base-url "http://localhost:11434")

;; Custom OpenAI-compatible
(make-provider :openai-compatible
              :base-url "https://api.example.com/v1"
              :api-key "sk-...")
```

**Gemini-specific parameters:**
- `:base-url` - Custom API endpoint (default: `https://generativelanguage.googleapis.com/v1beta/openai/`)
- `:api-key` - Gemini API key (falls back to `GEMINI_API_KEY` env var)
- `:model` - Default model (e.g., "gemini-3-flash-preview", "gemini-3-pro-preview")

**Available Gemini models:**
- `gemini-3-flash-preview` - Fast, cost-effective model (1M token context)
- `gemini-3-pro-preview` - Advanced model (2M token context)
- `gemini-embedding-001` - Text embeddings (768 dimensions)

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

### `find-tool-by-name`

Get a registered tool. Tool functions live in the `cl-llm-provider.tools`
package, not `cl-llm-provider`.

```lisp
(find-tool-by-name name &key registry) → tool or nil
```

### `list-tools`

List all registered tools.

```lisp
(list-tools registry &key categories safety-level) → list of tools
```

### `execute-tool`

Execute a resolved tool definition for a model-requested tool call.

```lisp
(execute-tool tool tool-call &key registry skip-approval skip-validation
                            approval-callback max-safety-level)
→ result
```

For completion responses containing multiple tool calls, use:

```lisp
(execute-tool-calls response &key registry skip-approval skip-validation
                              approval-callback max-safety-level on-missing-tool)
→ list of (tool-call . result)
```

---

## Response Objects

### `completion-response`

Result from `complete`.

**Accessors**:
- `(response-id response)` - Response ID
- `(response-model response)` - Model used
- `(response-content response)` - Text content
- `(response-message response)` - Full assistant message for continuation; Anthropic tool-use responses carry content-block plists
- `(response-tool-calls response)` - List of tool calls (if any)
- `(response-finish-reason response)` - Why it stopped (`:stop`, `:length`, etc.)
- `(response-usage response)` - Token usage plist `(:prompt-tokens N :completion-tokens M :total-tokens T)`
- `(response-metadata response)` - Provider-specific metadata plist
- `(response-performance response)` - Timing plist `(:encode-time :api-time :decode-time)`, in seconds, when `*performance-profiling*` is bound to T

**Example**:
```lisp
(let ((response (complete messages)))
  (format t "Content: ~A~%" (response-content response))
  (format t "Tokens: ~A~%" (getf (response-usage response) :total-tokens))
  (when (response-tool-calls response)
    (dolist (call (response-tool-calls response))
      (format t "Tool: ~A~%" (tool-call-name call)))))
```

### Tool Response Objects

**Tool Definition** (from `find-tool-by-name`):
- `(tool-name tool)` - Tool name
- `(tool-description tool)` - Description
- `(tool-parameters tool)` - Parameter definitions
- `(tool-required-params tool)` - Required params
- `(tool-handler tool)` - Handler function
- `(tool-safety-level tool)` - Safety level keyword
- `(tool-categories tool)` - Category list
- `(tool-metadata tool)` - Metadata plist

---

## Error Types

All inherit from `llm-provider-error`, which inherits from `error`. The names are
prefixed — there is no bare `network-error` or `rate-limit-error`.

```lisp
(handler-case
    (complete messages)

  ;; Transient (safe to retry)
  (provider-rate-limit-error (e)
    (sleep (or (error-retry-after e) 60)))

  (provider-timeout-error (e)
    (format t "Timed out: ~A~%" e))

  (provider-network-error (e)
    (format t "Could not reach ~A~%" (error-url e)))

  ;; Permanent (don't retry)
  (provider-authentication-error (e)
    (format t "Auth failed: ~A~%" (error-message e)))

  (provider-api-error (e)
    (format t "Provider error: ~A~%" (error-message e))))
```

**Hierarchy**:

| Condition | Meaning |
|---|---|
| `llm-provider-error` | Root of everything below |
| `provider-configuration-error` | Missing or invalid configuration |
| `provider-api-error` | The server answered, with an error |
| `provider-rate-limit-error` | Too many requests |
| `provider-authentication-error` | Invalid credentials |
| `provider-model-not-found-error` | No such model on that provider |
| `provider-context-length-error` | Prompt exceeds the context window |
| `provider-content-filter-error` | Refused by a content filter |
| `provider-overloaded-error` | Server temporarily overloaded |
| `provider-invalid-response-error` | Response was not the expected shape |
| `provider-network-error` | The server did not answer |
| `provider-timeout-error` | Request or response exceeded the time limit |
| `provider-json-parse-error` | Response body was not valid JSON |
| `llm-stream-error` | Streaming failures (`stream-interrupted-error`, `stream-parse-error`) |

**Accessors**:
- `(error-message e)` — message string
- `(error-status-code e)` — HTTP status, on `provider-api-error` and subtypes
- `(error-provider e)` — the provider instance
- `(error-retry-after e)` — seconds from the server's `Retry-After`, or `NIL`
- `(error-requested-model e)` — on `provider-model-not-found-error`
- `(error-url e)`, `(error-operation e)` — on `provider-network-error`
- `(transient-error-p e)` — whether retrying could plausibly succeed

---

## Recovery

### Restarts

Use `handler-bind`, **not** `handler-case`: `handler-case` unwinds before its body
runs, which disestablishes every restart, so `invoke-restart` there signals
`control-error`.

| Restart | Established by | Arguments | Effect |
|---|---|---|---|
| `use-value` | HTTP 401 | new API key | Set the key on the provider and re-issue |
| `wait-and-retry` | HTTP 429 | — | Sleep `retry-after`, then re-issue |
| `retry` | HTTP 429, and every other status except 401 | — | Re-issue the identical request |
| `use-model` | `complete`, `embedding`, `complete-stream` | model name | Re-issue against the same provider with a different model |
| `use-fallback-provider` | `complete`, `embedding`, `complete-stream` | provider, *optional* model | Re-issue against a different provider |
| `skip-tool` | `execute-tool-calls`, tool name not in registry | — | Skip that call and carry on |
| `use-error-result` | `execute-tool`, handler failure | — | Record the error as the result |
| `retry-execution` | `execute-tool`, handler failure | — | Run the handler again |
| `use-value` | HTTP 401, and `execute-tool` handler failure | new key / any value | Substitute a value and re-issue |

A 401 offers only `use-value` — retrying with the same key fails identically.
`provider-overloaded-error` falls through the generic branch and offers plain
`retry`, not `wait-and-retry`.

The three tool-execution restart names live in `cl-llm-provider.tools` and are
**not exported**, so from another package name them explicitly:
`(find-restart 'cl-llm-provider.tools::skip-tool c)`. `use-value` needs no
qualification — it is the standard `cl:use-value`.

```lisp
(handler-bind
    ((provider-network-error
       (lambda (c)
         (let ((r (find-restart 'use-fallback-provider c)))
           ;; Both arguments whenever the fallback is a different service —
           ;; the dead endpoint's model name means nothing to it.
           (when r (invoke-restart r *cloud* "openai/gpt-oss-120b"))))))
  (complete messages :provider *local* :model "local-model-name"))
```

Omitting the model keeps the caller's and re-resolves it against the new
provider, which is correct only when both endpoints serve the same model.

`(available-recovery-options condition)` returns the live restarts as plists of
`:name` and `:report`, for discovering them at runtime.

### `with-auto-recovery`

```lisp
(with-auto-recovery (&key max-retries backoff-base fallback-providers on-retry)
  &body body)
```

| Parameter | Default | Meaning |
|---|---|---|
| `max-retries` | 3 | Retries on transient errors only |
| `backoff-base` | 1.0 | Exponential backoff multiplier, seconds |
| `fallback-providers` | `nil` | Entries tried after retries are exhausted |
| `on-retry` | `nil` | `(lambda (condition attempt) ...)`; `attempt` is 0 on a fallback switch |

Each fallback entry is a provider, or `(provider . model)` / `(provider model)`.
**Name the model whenever the fallback is a different service**; a bare entry
keeps the caller's model.

```lisp
(with-auto-recovery (:max-retries 3
                     :fallback-providers (list (cons *cloud* "openai/gpt-oss-120b")))
  (complete messages :provider *local* :model "local-model-name"))
```

Retries re-execute `body`. The fallback switch does not — it invokes
`use-fallback-provider`, so only the failing request is re-issued and side effects
earlier in `body` are not repeated. Because it uses the restart, it also reaches a
`body` that passes `:provider` explicitly.

For a `body` with no LLM call in scope, there is no restart to invoke and the
macro rebinds `*default-provider*` and re-executes `body` instead.

Do not nest inside another `handler-bind` that handles `llm-provider-error` — the
outer handler fires first.

See [How-To: Error Handling](../how-to/error-handling.md) and
[Local models and failover](../how-to/local-models-and-failover.md).

---

## Configuration

### Environment Variables

- `ANTHROPIC_API_KEY` - Anthropic API key
- `OPENAI_API_KEY` - OpenAI API key
- `GEMINI_API_KEY` - Google Gemini API key
- `OPENROUTER_API_KEY` - OpenRouter API key
- `OLLAMA_BASE_URL` - Ollama base URL (default: http://localhost:11434)

### Runtime Configuration

```lisp
;; Set default provider
(setf cl-llm-provider:*default-provider* :anthropic)

;; Set default model
(setf cl-llm-provider:*default-model* "claude-3-sonnet-20240229")

;; Defaults applied when a call does not specify them
(setf cl-llm-provider:*default-max-tokens* 4096)
(setf cl-llm-provider:*default-temperature* 1.0)

;; Enable timing collection (see Profiling, below)
(setf cl-llm-provider:*performance-profiling* t)

;; Per-request HTTP read timeout, in seconds
(make-provider :openai :options '(:timeout 120))
```

---

## Profiling

### Performance Timing

Enable by binding `*performance-profiling*` around the call — there is no
`:enable-profiling` keyword:

```lisp
(let* ((*performance-profiling* t)
       (response (complete messages)))
  (let ((prof (response-performance response)))
    (when prof
      (format t "Encode: ~,4Fs~%" (getf prof :encode-time))
      (format t "API:    ~,4Fs~%" (getf prof :api-time))
      (format t "Decode: ~,4Fs~%" (getf prof :decode-time)))))
```

**Profiling Fields** (seconds, as floats):
- `:encode-time` - Time to build and encode the request
- `:api-time` - Time waiting for the API response
- `:decode-time` - Time to parse the response

There is no `:total-time`; sum the three, or time the call yourself if you want
wall-clock including retries.

---

## Utilities

### Message Building

```lisp
;; Create a user message
(list :role "user" :content "Hello")

;; Create an assistant message
(list :role "assistant" :content "Hi there")

;; Build conversation
(let* ((messages (list (list :role "user" :content "Q1")))
       (answer (complete messages)))
  (push (response-message answer) messages)
  (push (list :role "user" :content "Q2") messages)
  (reverse messages))
```

### Tool Parameter Types

Parameter specs are plists, written inside a quoted list in `define-tool`:

```
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
(let ((first-answer (complete (list (list :role "user" :content "Q1")))))
  (complete (list
    (list :role "user" :content "Q1")
    (response-message first-answer)
    (list :role "user" :content "Q2"))))

;; 3. With tools
(complete messages :tools (list (find-tool-by-name "search")))

;; 4. Token counting
(count-tokens messages)

;; 5. Switch providers
(complete messages :provider (make-provider :openai))

;; 6. Error handling
(handler-case
  (complete messages)
  (provider-rate-limit-error (e) (sleep (or (error-retry-after e) 60))))

;; 7. Retries and failover
(with-auto-recovery (:max-retries 3
                     :fallback-providers (list (cons (make-provider :openai) "gpt-4o")))
  (complete messages))
```

---

**See Also**:
- [Quick Start](../quickstart.md)
- [Tutorials](../tutorials/01-basics.md)
- [How-To Guides](../how-to/tools.md)
