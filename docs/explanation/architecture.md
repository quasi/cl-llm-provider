# Explanation: How cl-llm-provider Works

Understanding the architecture and design.

---

## The Problem

Different LLM providers have different APIs:
- **Anthropic** uses one message format, token counting method, and tool calling convention
- **OpenAI** uses a different format, different token counting, different tool format
- **Ollama** is compatible with OpenAI but with slight differences
- Each requires separate code to use

**Result**: To use multiple providers, you write the same logic 3+ times, each adapted for one API.

## The Solution: A Unified Protocol

cl-llm-provider defines a **single protocol** that all providers implement. You write code once, use any provider.

```
Your Code
    ↓
cl-llm-provider API (complete, embedding, etc.)
    ↓
Generic Protocol Methods
    ↓
Provider-Specific Implementations
    ↓
Anthropic API, OpenAI API, Ollama API, ...
```

## How It Works: The Protocol

### 1. Provider Objects

Each provider is an object that knows how to:
- Format requests in the provider's format
- Parse responses from the provider
- Handle provider-specific errors
- Track provider-specific metadata

```lisp
;; Provider object (internal)
(defclass llm-provider ()
  ((api-key :reader provider-api-key)
   (base-url :reader provider-base-url)
   (default-model :accessor provider-default-model)))

;; Subclasses for each provider
(defclass anthropic-provider (llm-provider) ...)
(defclass openai-provider (llm-provider) ...)
(defclass ollama-provider (llm-provider) ...)
```

### 2. Generic Functions

The protocol uses **generic functions** (CLOS) to dispatch based on provider type:

```lisp
;; Generic function
(defgeneric send-completion-request (provider messages &key model ...))

;; Provider-specific implementations
(defmethod send-completion-request ((provider anthropic-provider) ...)
  ;; Anthropic-specific implementation
  )

(defmethod send-completion-request ((provider openai-provider) ...)
  ;; OpenAI-specific implementation
  )
```

When you call `send-completion-request`, Common Lisp automatically calls the right implementation based on the provider type.

### 3. Message Normalization

Messages get converted to provider format at the boundary:

```
Your format:
(:role "user" :content "Hello")

↓

Anthropic format:
{role: "user", content: "Hello"}

↓

OpenAI format:
{role: "user", content: "Hello"}

↓

Ollama format:
{role: "user", content: "Hello"}
```

Inside cl-llm-provider, everything uses the **standard format**. At the API boundary, we convert to/from provider format.

### 4. Request/Response Flow

When you call `complete`:

```
1. User calls (complete messages)

2. cl-llm-provider:
   - Creates/finds a provider instance
   - Validates messages and parameters
   - Calls generic send-completion-request

3. Provider-specific method:
   - Normalizes messages to provider format
   - Converts tools to provider format
   - Formats HTTP request
   - Sends to provider API
   - Parses provider response

4. Response parsing:
   - Convert provider response to standard format
   - Create completion-response object
   - Return to user

5. User code:
   - (response-content response) → "Hello"
   - (response-tool-calls response) → '((:name "search" ...))
```

## Provider Types and Hierarchy

```
llm-provider (base class)
├── anthropic-provider        # Claude API
├── openai-provider           # GPT-4, GPT-3.5
│   └── openai-compatible     # Groq, vLLM, etc. (inherits from openai)
├── ollama-provider           # Local models
├── openrouter-provider       # Multi-provider routing
```

**Inheritance**: OpenAI-compatible providers inherit from `openai-provider` because they use the same API format.

## Message Handling

### Standard Format

Inside cl-llm-provider:

```lisp
'(:role "user" :content "Hello")
'(:role "assistant" :content "Hi there")
```

### Provider Formats

**Anthropic**:
```json
{"role": "user", "content": "Hello"}
```

**OpenAI**:
```json
{"role": "user", "content": "Hello"}
```

**Ollama**:
```json
{"role": "user", "content": "Hello"}
```

(Most providers actually use the same JSON format internally, but cl-llm-provider normalizes to Lisp property lists.)

### System Messages

System messages work across all providers but are handled differently:

- **Anthropic**: Separate `system` parameter
- **OpenAI**: Separate role: "system" message
- **Ollama**: Handled as first message or separate parameter

cl-llm-provider normalizes this—you always use `:system "..."` parameter:

```lisp
;; You write
(complete messages :system "You are helpful")

;; Internally becomes:

;; For Anthropic
(send-completion-request provider messages :system "You are helpful")

;; For OpenAI
(let ((messages (list (list :role "system" :content "You are helpful")
                            ...messages)))
  (send-completion-request provider messages))
```

## Tool Definition Handling

### Standard Format

You define tools using cl-llm-provider's format:

```lisp
(define-tool "search"
  "Search the web"
  '((:name "query" :type :string)
    (:name "limit" :type :integer))
  :required '("query")
  :handler (lambda (args) ...))
```

### Provider Formats

When sending to providers, tools get converted:

**Anthropic tool format**:
```json
{
  "name": "search",
  "description": "Search the web",
  "input_schema": {
    "type": "object",
    "properties": {
      "query": {"type": "string"},
      "limit": {"type": "integer"}
    },
    "required": ["query"]
  }
}
```

**OpenAI function format**:
```json
{
  "type": "function",
  "function": {
    "name": "search",
    "description": "Search the web",
    "parameters": {
      "type": "object",
      "properties": {
        "query": {"type": "string"},
        "limit": {"type": "integer"}
      },
      "required": ["query"]
    }
  }
}
```

cl-llm-provider handles all conversions internally.

## Error Handling

Errors are abstracted:

**Provider returns 429 (rate limited)**
↓
**Provider-specific code detects it**
↓
**Converts to standard error**: `rate-limit-error`
↓
**User catches** `rate-limit-error`

This way, your error handling code works across providers without checking which provider returned the error.

## Token Counting

Each provider counts tokens differently:

- **Anthropic**: Uses its own algorithm
- **OpenAI**: Uses its own algorithm
- **Ollama**: Often approximates based on input

cl-llm-provider provides a unified token-count function that:
1. Calls the right provider's token counter
2. Falls back to approximation if provider doesn't support it
3. Returns consistent counts

```lisp
;; Same API, different implementations per provider
(token-count messages)  ; Returns consistent count across all providers
```

## Dynamic Provider Selection

You can switch providers at runtime without changing code:

```lisp
;; Use default (from env vars)
(complete messages)

;; Override for this call
(complete messages :provider (make-provider :openai :model "gpt-4"))

;; Switch to local model
(complete messages :provider (make-provider :ollama :model "mistral"))
```

## Performance Profiling

Optional profiling tracks where time is spent:

```
Request → Provider
  ├── encode (format to JSON): 5ms
  ├── network/api (HTTP call): 800ms
  └── decode (parse response): 10ms
Total: 815ms
```

Each provider tracks its own timing, but the interface is uniform.

## Why This Design?

**Benefits**:
1. **Write once, use any provider** - Your code is provider-agnostic
2. **Easy to add providers** - Implement generic functions, done
3. **Safe provider switching** - Same interface everywhere
4. **Consistent error handling** - Catch standard error types
5. **Provider interoperability** - Fall back to alternative providers

**Trade-offs**:
- Small overhead for abstraction (negligible vs. API latency)
- Need to implement all protocols for each provider
- Some provider-specific features might not be exposed

## Under the Hood: An Example

Here's what happens internally when you call:

```lisp
(complete '((:role "user" :content "What is Lisp?"))
         :provider (make-provider :anthropic)
         :max-tokens 100
         :temperature 0.7)
```

**Step 1**: Find/create provider
```lisp
provider = (make-provider :anthropic)
;;  → #<ANTHROPIC-PROVIDER>
```

**Step 2**: Call generic function
```lisp
(send-completion-request
  provider
  '((:role "user" :content "What is Lisp?"))
  :max-tokens 100
  :temperature 0.7)
```

**Step 3**: Dispatch to provider method (Common Lisp chooses this)
```lisp
;; Calls the anthropic-provider version
(defmethod send-completion-request ((provider anthropic-provider) ...)
  ;; Normalize messages to Anthropic format
  (let ((formatted '(...)))
    ;; Make HTTP request to Anthropic API
    (let ((response (dexador:post "https://api.anthropic.com/...")))
      ;; Parse response
      (let ((parsed (yason:parse response)))
        ;; Create response object
        (make-instance 'completion-response
                      :content (getf parsed :content)
                      ...)))))
```

**Step 4**: User code receives standard response object
```lisp
response-object
  :id "msg_123"
  :content "Lisp is a programming language..."
  :model "claude-3-sonnet-20240229"
  :provider :anthropic
```

The abstraction is transparent to you.

---

**See Also**:
- [How-To: Add a Provider](../how-to/add-provider.md)
- [Explanation: Understanding Providers](providers.md)
