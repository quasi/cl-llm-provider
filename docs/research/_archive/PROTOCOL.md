# Protocol Architecture

The cl-llm-provider library uses a **generic function protocol** to support multiple LLM providers with different APIs while maintaining a unified interface. This document describes the protocol design and how providers implement it.

## Design Overview

The protocol is based on Common Lisp's **CLOS (Common Lisp Object System)** generic functions, which provide runtime dispatch based on the argument types. Each provider type subclasses `llm-provider` and implements provider-specific methods.

```
User Code
    ↓
API Functions (complete, embedding, ...)
    ↓
Generic Protocol Methods
    ↓
Provider-Specific Implementations
    ↓
HTTP API Calls
```

## Core Protocol Definitions

### Provider Hierarchy

```lisp
llm-provider (base class)
├── anthropic-provider
├── openai-provider
├── ollama-provider
├── openrouter-provider
└── openai-compatible-provider (inherits from openai-provider)
```

### Key Classes

**`llm-provider` (Base Class)**
```lisp
(defclass llm-provider ()
  ((api-key :reader provider-api-key)
   (base-url :reader provider-base-url)
   (default-model :accessor provider-default-model)
   (options :reader provider-options)))
```

**`completion-response`**
```lisp
(defclass completion-response ()
  ((id :reader response-id)
   (model :reader response-model)
   (content :reader response-content)
   (message :reader response-message)
   (tool-calls :reader response-tool-calls)
   (finish-reason :reader response-finish-reason)
   (usage :reader response-usage)
   (raw :reader response-raw)
   (performance :reader response-performance)
   (metadata :reader response-metadata)))
```

**`embedding-response`**
```lisp
(defclass embedding-response ()
  ((embeddings :reader response-embeddings)
   (model :reader response-model)
   (usage :reader response-usage)
   (raw :reader response-raw)
   (performance :reader response-performance)
   (metadata :reader response-metadata)))
```

## Generic Functions (The Protocol Contract)

### Completion Protocol

#### `send-completion-request` (REQUIRED)
**Signature**: `(send-completion-request provider messages &key model max-tokens temperature system tools tool-choice stop) → raw-response`

Sends a completion request to the provider's API.

- **Provider Argument**: Specialized by provider type
- **Messages**: Plist list of messages `((:role "user" :content "...") ...)`
- **Returns**: Raw parsed JSON response (hash-table)
- **Signals**: `provider-api-error`, `provider-authentication-error`, `provider-rate-limit-error`

**Implementation Details Per Provider**:
- **OpenAI/OpenRouter**: POST to `/chat/completions`
- **Anthropic**: POST to `/messages` with separate system parameter
- **Ollama**: POST to `/api/chat`
- **OpenAI-Compatible**: Same as OpenAI (inherits)

#### `parse-completion-response` (REQUIRED)
**Signature**: `(parse-completion-response provider raw-response &key performance) → completion-response`

Parses provider-specific response format into normalized `completion-response`.

- **Raw Response**: Hash-table from `send-completion-request`
- **Returns**: `completion-response` object
- **Performance**: Optional plist with timing data `(:encode-time N :api-time M :decode-time K)`

**Normalization Happens Here**:
- Extract content, tool calls, finish reason
- Parse tool calls from provider format
- Extract token usage (normalized to `:prompt-tokens`, `:completion-tokens`, `:total-tokens`)
- Extract provider-specific metadata

### Embedding Protocol

#### `send-embedding-request` (REQUIRED for embedding providers)
**Signature**: `(send-embedding-request provider input &key model dimensions) → raw-response`

Sends embedding request to provider.

- **Input**: String or list of strings
- **Returns**: Raw parsed JSON response

#### `parse-embedding-response` (REQUIRED for embedding providers)
**Signature**: `(parse-embedding-response provider raw-response &key performance) → embedding-response`

Parses embedding response into normalized format.

- **Returns**: `embedding-response` with embeddings list

### Tool Protocol

#### `translate-tool-to-provider` (OPTIONAL, has default)
**Signature**: `(translate-tool-to-provider provider tool-definition) → provider-format`

Converts generic tool definition to provider-specific JSON schema format.

**Default (OpenAI Format)**:
```json
{
  "type": "function",
  "function": {
    "name": "tool_name",
    "description": "...",
    "parameters": {
      "type": "object",
      "properties": {...},
      "required": [...]
    }
  }
}
```

**Provider Overrides**:
- **Anthropic**: Uses flat format with `input_schema` instead of nested `parameters`
- Others: Use default OpenAI format

#### `parse-tool-calls` (OPTIONAL, has default)
**Signature**: `(parse-tool-calls provider raw-response) → list of tool-call objects`

Extracts tool calls from provider response.

**Default (OpenAI Format)**:
- Looks in `response.choices[0].message.tool_calls[]`
- Parses JSON string arguments to plists

**Provider Overrides**:
- **Anthropic**: Looks in content blocks with `type: "tool_use"`
- **Ollama**: Generates missing IDs if not provided

### Configuration Protocol

#### `provider-default-base-url` (OPTIONAL)
**Signature**: `(provider-default-base-url provider) → url-string or nil`

Returns the default API endpoint for a provider.

- **OpenAI**: `https://api.openai.com/v1`
- **Anthropic**: `https://api.anthropic.com`
- **OpenRouter**: `https://openrouter.ai/api/v1`
- **Ollama**: `nil` (must be specified)

#### `provider-api-key-env-var` (OPTIONAL)
**Signature**: `(provider-api-key-env-var provider) → env-var-name or nil`

Returns the environment variable name for API key lookup.

- **OpenAI**: `OPENAI_API_KEY`
- **Anthropic**: `ANTHROPIC_API_KEY`
- **OpenRouter**: `OPENROUTER_API_KEY`
- **Ollama**: `nil` (typically no key needed)

## Request/Response Normalization

### Message Format Normalization

**Input** (User-provided plist):
```lisp
'(:role "user" :content "Hello")
```

**Conversion** (Internal hash-table):
```lisp
#("role" "user" "content" "Hello")
```

**Per-Provider Handling**:
- Keywords automatically converted to lowercase string keys
- String keys preserved as-is
- System messages handled per provider (separate param in Anthropic, in messages array in OpenAI/Ollama)

### Response Normalization

All providers return different formats. The `parse-completion-response` method normalizes to:

```lisp
completion-response(
  :id "response-id"
  :model "model-name"
  :content "Text response"
  :message (:role "assistant" :content "...")
  :tool-calls (list of tool-call objects)
  :finish-reason :stop  ; or :length, :tool-calls, :content-filter
  :usage (:prompt-tokens 100 :completion-tokens 50 :total-tokens 150)
  :raw (original hash-table)
  :metadata (:provider-specific-fields ...)
)
```

### Tool Call Normalization

**Provider Formats** (examples):

**OpenAI**:
```json
{
  "tool_calls": [{
    "id": "call_123",
    "type": "function",
    "function": {"name": "tool", "arguments": "{\"a\": 5}"}
  }]
}
```

**Anthropic**:
```json
{
  "content": [{
    "type": "tool_use",
    "id": "call_123",
    "name": "tool",
    "input": {"a": 5}
  }]
}
```

**Normalized Form** (all providers):
```lisp
tool-call(
  :id "call_123"
  :name "tool"
  :arguments (:a 5)
)
```

## Error Handling

### Exception Hierarchy

```
llm-provider-error (base)
├── provider-configuration-error
├── provider-api-error
│   ├── provider-rate-limit-error
│   └── provider-authentication-error
└── tool-schema-error
```

### Error Extraction

The library includes an `extract-error-message` function that handles multiple provider error formats:

**OpenAI Format**:
```json
{"error": {"message": "...", "type": "..."}}
```

**Anthropic Format**:
```json
{"error": {"type": "...", "message": "..."}}
```

**Direct Message**:
```json
{"message": "error description"}
```

**Detail Field**:
```json
{"detail": "error description"}
```

## Performance Profiling

Optional timing instrumentation wraps protocol methods:

```
encode-time: JSON encoding of request
  ↓
api-time: HTTP request + response
  ↓
decode-time: Response parsing
```

Controlled by `*performance-profiling*` global variable.

## Provider-Specific Features

### Anthropic-Specific

- **System Messages**: Separate `system` parameter (not in messages)
- **Max Tokens**: Required parameter (default 4096)
- **Tool Format**: Flat with `input_schema`
- **Tool Calls**: In content blocks as `type: "tool_use"`

### OpenAI-Specific

- **System Messages**: First message in array with role "system"
- **Tool Choice**: Supports `:auto`, `:required`, or specific tool name
- **Token Details**: Breakdown for reasoning/cache tokens
- **Embeddings**: Full support with configurable dimensions

### Ollama-Specific

- **System Messages**: In messages array
- **Timeout**: Long default (120s) for reasoning models
- **Thinking**: Supports reasoning models with think field
- **Tool IDs**: Auto-generated if missing
- **No Token Info**: Defaults to 0 tokens

### OpenRouter-Specific

- **Multi-Provider**: Routes through multiple backends
- **Tool Support**: Limited to specific models
- **Format**: Uses OpenAI format

## Implementing a New Provider

To add a new provider, follow these steps:

1. **Create Provider Class**
```lisp
(defclass my-provider (llm-provider)
  ()
  (:documentation "My custom provider"))
```

2. **Implement Required Methods**
```lisp
(defmethod send-completion-request ((provider my-provider) messages &key ...)
  ;; Build request, make HTTP call, return raw response
  )

(defmethod parse-completion-response ((provider my-provider) raw-response &key performance)
  ;; Parse raw response, extract fields, return completion-response
  )
```

3. **Implement Tool Methods** (if supporting tools)
```lisp
(defmethod translate-tool-to-provider ((provider my-provider) tool)
  ;; Convert tool-definition to provider-specific format
  )

(defmethod parse-tool-calls ((provider my-provider) raw-response)
  ;; Extract tool calls from response format
  )
```

4. **Implement Optional Methods**
```lisp
(defmethod provider-default-base-url ((provider my-provider))
  "https://api.myservice.com/v1")

(defmethod provider-api-key-env-var ((provider my-provider))
  "MY_SERVICE_API_KEY")
```

5. **Test Implementation**
- Implement provider tests following existing patterns
- Test message normalization
- Test response parsing
- Test tool translation
- Test error handling

See `docs/PROVIDERS.md` for detailed implementation guide.

## Message Flow Diagram

```
User Request
    ↓
complete(messages, :tools [...], :provider provider, ...)
    ↓
validate-tools() - Check tool definitions
    ↓
Build request body - Normalize messages, translate tools
    ↓
send-completion-request() - HTTP POST
    ↓
Handle HTTP errors - Throw provider-api-error conditions
    ↓
parse-completion-response() - Parse raw response
    ↓
Extract tool calls if present - parse-tool-calls()
    ↓
Return completion-response
    ↓
Application: check response-tool-calls()
    ↓
If tools called:
  - Execute tools (application responsibility)
  - Create tool result messages: make-tool-result()
  - Call complete() again with tool results
    ↓
Final response
```

## Design Rationale

### Why Generic Functions?

1. **Open for Extension** - New providers added without modifying existing code
2. **Idiomatic CL** - Uses CLOS standard patterns
3. **Type-Safe** - Method dispatch based on actual provider types
4. **Performance** - Dispatch happens at runtime with caching

### Why Protocol Methods?

1. **Clear Contracts** - Each provider knows exactly what methods to implement
2. **Separation of Concerns** - Message normalization separate from API details
3. **Testability** - Each method can be tested independently
4. **Flexibility** - Providers can override only what they need

### Why Normalization?

1. **Provider Agnostic** - Application code doesn't depend on provider specifics
2. **Provider Switching** - Change providers by changing one parameter
3. **Consistency** - Same response structure regardless of provider
4. **Feature Access** - Optional metadata still accessible for advanced use

## See Also

- `docs/PROVIDERS.md` - How to implement a new provider
- `docs/FEATURES.md` - Detailed feature documentation
- `src/protocol.lisp` - Protocol definitions
- `src/api.lisp` - API entry points using the protocol
