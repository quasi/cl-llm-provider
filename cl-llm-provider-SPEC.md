# CL-LLM-PROVIDER Specification

## Overview

**Name**: cl-llm-provider
**Purpose**: Unified Common Lisp interface for multiple LLM provider APIs (text completion and embeddings)
**Author**: quasi / quasiLabs
**License**: MIT
**Style**: fukamachi (modern structure with `src/` directory, sensible dependencies)

## Problem Statement

Common Lisp lacks a unified, production-ready library for interacting with multiple LLM providers. Developers currently must:

1. Write provider-specific HTTP code for each API (Anthropic, OpenAI, Ollama, OpenRouter)
2. Handle different request/response formats manually
3. Manage API keys and configuration inconsistently
4. Duplicate tool-calling schema translation logic across projects

`cl-llm-provider` solves this by providing a single, Lispy interface that normalizes interactions across providers while preserving provider-specific capabilities when needed.

## Requirements

### Functional Requirements

1. **Text Completion**: Send messages and receive text responses from any supported provider
2. **Embeddings**: Generate vector embeddings for text using provider embedding models
3. **Provider Abstraction**: Uniform interface that works identically across:
   - Anthropic API (Claude models)
   - OpenAI API (GPT models)
   - OpenAI-compatible APIs (Groq, Together, local vLLM, etc.)
   - Ollama (local models)
   - OpenRouter (multi-provider gateway)
4. **Tool Calling**: Define tool schemas, translate between provider formats, parse tool-call responses
5. **Configuration**: Load API keys from environment variables or `.env` files
6. **Global Defaults**: Set default provider, model, and parameters globally; override per-request

### Non-Functional Requirements

- **Performance**: Minimal overhead; direct HTTP calls without unnecessary abstraction layers
- **Portability**: Works on SBCL, CCL, ECL, ABCL (with optional SBCL optimizations)
- **Dependencies**: Modern stable stack (alexandria, serapeum, dexador, yason, etc.)
- **Thread Safety**: Safe for use with bordeaux-threads (no shared mutable state without locks)
- **Extensibility**: Easy to add new providers via generic function specialization

### Explicit Non-Goals (v1)

- Streaming responses (deferred to v2)
- Audio/video/image processing
- Automatic tool execution loops (agent-layer responsibility)
- Cost tracking or rate limiting
- Conversation memory/history management

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Application                          │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                      cl-llm-provider API                         │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐    │
│  │ complete  │  │ embedding │  │  tools    │  │  config   │    │
│  └───────────┘  └───────────┘  └───────────┘  └───────────┘    │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Provider Protocol Layer                      │
│         (generic functions specialized per provider)             │
└─────────────────────────────────────────────────────────────────┘
                                 │
          ┌──────────┬──────────┼──────────┬──────────┐
          ▼          ▼          ▼          ▼          ▼
     ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
     │Anthropic│ │ OpenAI  │ │ Ollama  │ │OpenRouter│ │OpenAI-  │
     │ Provider│ │ Provider│ │ Provider│ │ Provider│ │Compatible│
     └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘
          │          │          │          │          │
          └──────────┴──────────┴──────────┴──────────┘
                                 │
                                 ▼
                    ┌───────────────────────┐
                    │   HTTP Layer (dexador) │
                    └───────────────────────┘
```

## API Design

### Provider Creation

#### `make-provider`
```lisp
(make-provider provider-type &key api-key base-url model options)
  => provider instance
```
**Purpose**: Create a provider instance for API interactions.

**Arguments**:
- `provider-type`: keyword - One of `:anthropic`, `:openai`, `:ollama`, `:openrouter`, `:openai-compatible`
- `api-key`: string or nil - API key (falls back to environment/config if nil)
- `base-url`: string or nil - Override default API endpoint
- `model`: string or nil - Default model for this provider
- `options`: plist - Provider-specific options

**Returns**: A provider instance (subclass of `llm-provider`)

**Signals**: `provider-configuration-error` if required config missing

**Example**:
```lisp
;; Explicit configuration
(make-provider :anthropic 
               :api-key "sk-ant-..."
               :model "claude-3-sonnet-20240229")

;; Using environment variables (reads ANTHROPIC_API_KEY)
(make-provider :anthropic :model "claude-3-sonnet-20240229")

;; Local Ollama
(make-provider :ollama 
               :base-url "http://localhost:11434"
               :model "llama3")

;; OpenAI-compatible (e.g., Groq)
(make-provider :openai-compatible
               :api-key "gsk_..."
               :base-url "https://api.groq.com/openai/v1"
               :model "mixtral-8x7b-32768")
```

### Core Functions

#### `complete`
```lisp
(complete messages &key provider model max-tokens temperature 
                        system tools tool-choice stop)
  => response
```
**Purpose**: Send a completion request to an LLM provider.

**Arguments**:
- `messages`: list - List of message plists `((:role "user" :content "Hello"))`
- `provider`: provider or nil - Provider instance (uses `*default-provider*` if nil)
- `model`: string or nil - Model identifier (uses provider/global default if nil)
- `max-tokens`: integer or nil - Maximum tokens in response
- `temperature`: float or nil - Sampling temperature (0.0-2.0)
- `system`: string or nil - System prompt
- `tools`: list or nil - List of tool definitions
- `tool-choice`: keyword or string or nil - Tool selection strategy
- `stop`: string or list or nil - Stop sequences

**Returns**: A `completion-response` object

**Signals**: 
- `provider-api-error` on API errors
- `provider-rate-limit-error` on rate limiting
- `provider-authentication-error` on auth failures

**Example**:
```lisp
;; Simple completion using defaults
(complete '((:role "user" :content "What is Common Lisp?")))

;; With explicit provider and parameters
(complete '((:role "user" :content "Explain monads"))
          :provider *anthropic*
          :model "claude-3-opus-20240229"
          :max-tokens 1000
          :temperature 0.7
          :system "You are a functional programming expert.")

;; Multi-turn conversation
(complete '((:role "user" :content "What is 2+2?")
            (:role "assistant" :content "2+2 equals 4.")
            (:role "user" :content "And if you add 3?")))
```

#### `embedding`
```lisp
(embedding input &key provider model dimensions)
  => embedding-response
```
**Purpose**: Generate vector embeddings for text.

**Arguments**:
- `input`: string or list of strings - Text to embed
- `provider`: provider or nil - Provider instance
- `model`: string or nil - Embedding model identifier
- `dimensions`: integer or nil - Output dimensions (if model supports)

**Returns**: An `embedding-response` object

**Signals**: `provider-api-error`, `provider-authentication-error`

**Example**:
```lisp
;; Single text
(embedding "Common Lisp is a powerful language")

;; Batch embeddings
(embedding '("First document" "Second document" "Third document")
           :model "text-embedding-3-small")
```

### Tool Calling

#### `define-tool`
```lisp
(define-tool name description parameters &key required)
  => tool-definition
```
**Purpose**: Create a tool definition that can be passed to `complete`.

**Arguments**:
- `name`: string - Tool/function name
- `description`: string - What the tool does (used by LLM)
- `parameters`: list - Parameter specifications as plists
- `required`: list - List of required parameter names

**Returns**: A `tool-definition` object

**Example**:
```lisp
(define-tool "get_weather"
  "Get the current weather in a given location"
  '((:name "location" 
     :type :string 
     :description "City and state, e.g. San Francisco, CA")
    (:name "unit"
     :type :string
     :enum ("celsius" "fahrenheit")
     :description "Temperature unit"))
  :required '("location"))
```

#### `tool-calls`
```lisp
(tool-calls response)
  => list of tool-call objects or nil
```
**Purpose**: Extract tool calls from a completion response.

**Arguments**:
- `response`: completion-response - Response from `complete`

**Returns**: List of `tool-call` objects, or nil if no tool calls

**Example**:
```lisp
(let* ((tools (list (define-tool "get_weather" ...)))
       (response (complete '((:role "user" :content "What's the weather in Paris?"))
                           :tools tools)))
  (when-let ((calls (tool-calls response)))
    (dolist (call calls)
      (format t "Call ~A with ~A~%" 
              (tool-call-name call)
              (tool-call-arguments call)))))
```

#### `make-tool-result`
```lisp
(make-tool-result tool-call-id result &key is-error)
  => message plist
```
**Purpose**: Create a tool result message to send back to the LLM.

**Arguments**:
- `tool-call-id`: string - ID from the original tool call
- `result`: string - Result of executing the tool (typically JSON)
- `is-error`: boolean - Whether this represents an error

**Returns**: A message plist suitable for inclusion in the messages list

**Example**:
```lisp
(let* ((call (first (tool-calls response)))
       (result (make-tool-result 
                (tool-call-id call)
                "{\"temperature\": 22, \"unit\": \"celsius\"}")))
  (complete (append original-messages 
                    (list (response-message response))
                    (list result))))
```

### Configuration

#### `*default-provider*`
**Type**: provider or nil
**Default**: nil
**Purpose**: Default provider used when `:provider` argument is omitted.

#### `*default-model*`
**Type**: string or nil  
**Default**: nil
**Purpose**: Default model used when `:model` argument is omitted and provider has no default.

#### `*default-max-tokens*`
**Type**: integer
**Default**: 4096
**Purpose**: Default max-tokens when not specified.

#### `*default-temperature*`
**Type**: float
**Default**: 1.0
**Purpose**: Default temperature when not specified.

#### `load-configuration`
```lisp
(load-configuration &key env-file)
  => configuration plist
```
**Purpose**: Load configuration from environment variables and optional .env file.

**Arguments**:
- `env-file`: pathname or string or nil - Path to .env file (defaults to ".env" in current directory)

**Returns**: Plist of loaded configuration values

**Side Effects**: Sets environment variables from .env file if found

**Example**:
```lisp
;; Load from default .env
(load-configuration)

;; Load from specific file
(load-configuration :env-file #p"~/.config/llm/secrets.env")
```

#### `configure-defaults`
```lisp
(configure-defaults &key provider model max-tokens temperature)
  => nil
```
**Purpose**: Set global defaults for LLM operations.

**Arguments**:
- `provider`: provider or keyword - Default provider (keyword creates one automatically)
- `model`: string - Default model
- `max-tokens`: integer - Default max tokens
- `temperature`: float - Default temperature

**Example**:
```lisp
;; Configure with provider instance
(configure-defaults :provider (make-provider :anthropic)
                    :model "claude-3-sonnet-20240229"
                    :max-tokens 2048)

;; Configure with provider keyword (uses env vars for API key)
(configure-defaults :provider :anthropic
                    :model "claude-3-sonnet-20240229")
```

### Convenience Macros

#### `with-provider`
```lisp
(with-provider (provider-form) &body body)
```
**Purpose**: Execute body with a specific provider as the default.

**Example**:
```lisp
(with-provider ((make-provider :ollama :model "llama3"))
  (complete '((:role "user" :content "Hello")))
  (complete '((:role "user" :content "Goodbye"))))
```

#### `with-model`
```lisp
(with-model (model-name) &body body)
```
**Purpose**: Execute body with a specific model as the default.

**Example**:
```lisp
(with-model ("claude-3-opus-20240229")
  (complete '((:role "user" :content "Complex reasoning task..."))))
```

## Data Types

### `llm-provider` (class)
```lisp
(defclass llm-provider ()
  ((api-key :initarg :api-key :reader provider-api-key)
   (base-url :initarg :base-url :reader provider-base-url)
   (default-model :initarg :model :accessor provider-default-model)
   (options :initarg :options :reader provider-options :initform nil)))
```
**Purpose**: Base class for all LLM providers.

### Provider Subclasses
```lisp
(defclass anthropic-provider (llm-provider) ())
(defclass openai-provider (llm-provider) ())
(defclass ollama-provider (llm-provider) ())
(defclass openrouter-provider (llm-provider) ())
(defclass openai-compatible-provider (openai-provider) ())
```

### `completion-response` (class)
```lisp
(defclass completion-response ()
  ((id :initarg :id :reader response-id)
   (model :initarg :model :reader response-model)
   (content :initarg :content :reader response-content)
   (message :initarg :message :reader response-message)
   (tool-calls :initarg :tool-calls :reader response-tool-calls :initform nil)
   (finish-reason :initarg :finish-reason :reader response-finish-reason)
   (usage :initarg :usage :reader response-usage)
   (raw :initarg :raw :reader response-raw)))
```
**Purpose**: Normalized response from any provider's completion endpoint.

**Slots**:
- `id`: Unique response identifier
- `model`: Model that generated the response  
- `content`: Text content of the response (string or nil if tool call)
- `message`: Full message plist (for conversation continuation)
- `tool-calls`: List of tool-call objects if the model requested tool use
- `finish-reason`: Why generation stopped (`:stop`, `:length`, `:tool-calls`)
- `usage`: Token usage plist `(:prompt-tokens N :completion-tokens M :total-tokens T)`
- `raw`: Original provider response (for debugging/advanced use)

### `embedding-response` (class)
```lisp
(defclass embedding-response ()
  ((embeddings :initarg :embeddings :reader response-embeddings)
   (model :initarg :model :reader response-model)
   (usage :initarg :usage :reader response-usage)
   (raw :initarg :raw :reader response-raw)))
```
**Purpose**: Normalized response from embedding endpoints.

**Slots**:
- `embeddings`: List of vectors (each vector is a list of floats)
- `model`: Model used for embeddings
- `usage`: Token usage plist
- `raw`: Original provider response

### `tool-definition` (class)
```lisp
(defclass tool-definition ()
  ((name :initarg :name :reader tool-name)
   (description :initarg :description :reader tool-description)
   (parameters :initarg :parameters :reader tool-parameters)
   (required :initarg :required :reader tool-required-params :initform nil)))
```
**Purpose**: Represents a tool that can be called by the LLM.

### `tool-call` (class)
```lisp
(defclass tool-call ()
  ((id :initarg :id :reader tool-call-id)
   (name :initarg :name :reader tool-call-name)
   (arguments :initarg :arguments :reader tool-call-arguments)))
```
**Purpose**: Represents a tool invocation requested by the LLM.

**Slots**:
- `id`: Unique identifier for this call (needed for result correlation)
- `name`: Name of the tool to call
- `arguments`: Plist of arguments (already parsed from JSON)

## Conditions

### `llm-provider-error` (condition)
```lisp
(define-condition llm-provider-error (error)
  ((provider :initarg :provider :reader error-provider)
   (message :initarg :message :reader error-message)))
```
**Purpose**: Base condition for all provider errors.

### `provider-configuration-error` (condition)
```lisp
(define-condition provider-configuration-error (llm-provider-error)
  ((missing-key :initarg :missing-key :reader error-missing-key)))
```
**When signaled**: Missing required configuration (API key, base URL, etc.)

**Restarts provided**:
- `use-value` - Provide the missing value interactively
- `use-environment` - Try reading from a specific environment variable

### `provider-api-error` (condition)
```lisp
(define-condition provider-api-error (llm-provider-error)
  ((status-code :initarg :status-code :reader error-status-code)
   (body :initarg :body :reader error-body)))
```
**When signaled**: API request failed.

**Restarts provided**:
- `retry` - Retry the request
- `use-fallback-provider` - Try a different provider

### `provider-rate-limit-error` (condition)
```lisp
(define-condition provider-rate-limit-error (provider-api-error)
  ((retry-after :initarg :retry-after :reader error-retry-after)))
```
**When signaled**: Rate limit exceeded.

**Restarts provided**:
- `wait-and-retry` - Sleep for retry-after seconds and retry
- `retry` - Retry immediately
- `use-fallback-provider` - Try a different provider

### `provider-authentication-error` (condition)
```lisp
(define-condition provider-authentication-error (provider-api-error) ())
```
**When signaled**: Invalid or expired API key.

**Restarts provided**:
- `use-value` - Provide a new API key

### `tool-schema-error` (condition)
```lisp
(define-condition tool-schema-error (llm-provider-error)
  ((tool :initarg :tool :reader error-tool)
   (reason :initarg :reason :reader error-reason)))
```
**When signaled**: Invalid tool definition or schema translation failure.

## Provider Protocol

New providers are added by subclassing `llm-provider` and implementing these generic functions:

```lisp
;; Required
(defgeneric send-completion-request (provider messages &key model max-tokens 
                                              temperature system tools tool-choice stop)
  (:documentation "Send a completion request and return raw response."))

(defgeneric parse-completion-response (provider raw-response)
  (:documentation "Parse provider-specific response into completion-response."))

(defgeneric send-embedding-request (provider input &key model dimensions)
  (:documentation "Send an embedding request and return raw response."))

(defgeneric parse-embedding-response (provider raw-response)
  (:documentation "Parse provider-specific response into embedding-response."))

;; Optional (have default implementations)
(defgeneric provider-default-base-url (provider)
  (:documentation "Return default API base URL for this provider type."))

(defgeneric provider-api-key-env-var (provider)
  (:documentation "Return environment variable name for API key."))

(defgeneric translate-tool-to-provider (provider tool-definition)
  (:documentation "Translate generic tool definition to provider format."))

(defgeneric parse-tool-calls (provider raw-response)
  (:documentation "Extract tool calls from provider response format."))
```

## File Structure

```
cl-llm-provider/
├── cl-llm-provider.asd
├── README.md
├── LICENSE
├── .env.example
├── src/
│   ├── package.lisp
│   ├── conditions.lisp
│   ├── config.lisp
│   ├── protocol.lisp
│   ├── types.lisp
│   ├── tools.lisp
│   ├── api.lisp
│   └── providers/
│       ├── anthropic.lisp
│       ├── openai.lisp
│       ├── ollama.lisp
│       ├── openrouter.lisp
│       └── openai-compatible.lisp
└── tests/
    ├── package.lisp
    ├── test-tools.lisp
    ├── test-providers.lisp
    └── test-integration.lisp
```

## Dependencies

| Dependency | Purpose | Required? |
|------------|---------|-----------|
| alexandria | General utilities, hash-table operations | Yes |
| serapeum | Additional utilities, string operations | Yes |
| dexador | HTTP client | Yes |
| yason | JSON parsing/generation | Yes |
| cl-dotenv or envy | .env file parsing | Yes |
| bordeaux-threads | Thread-safe operations | Yes |
| cl-ppcre | String matching (model name parsing) | Yes |
| fiveam | Testing framework | Dev only |
| cl-mock | Mocking for tests | Dev only |

## Environment Variables

| Variable | Provider | Purpose |
|----------|----------|---------|
| `ANTHROPIC_API_KEY` | Anthropic | API authentication |
| `OPENAI_API_KEY` | OpenAI | API authentication |
| `OPENROUTER_API_KEY` | OpenRouter | API authentication |
| `OLLAMA_BASE_URL` | Ollama | Custom Ollama endpoint (default: http://localhost:11434) |
| `LLM_DEFAULT_PROVIDER` | All | Default provider type (keyword name) |
| `LLM_DEFAULT_MODEL` | All | Default model identifier |
| `LLM_DEFAULT_MAX_TOKENS` | All | Default max tokens |
| `LLM_DEFAULT_TEMPERATURE` | All | Default temperature |

## Testing Strategy

- **Framework**: fiveam
- **Unit Tests**: 
  - Tool schema generation and translation
  - Response parsing for each provider format
  - Configuration loading
  - Condition signaling and restarts
- **Integration Tests** (with mocking):
  - Full request/response cycle per provider
  - Tool calling round-trip
  - Error handling scenarios
- **Live Tests** (optional, requires API keys):
  - Real API calls to each provider
  - Skipped by default, enabled via environment variable

## Implementation Notes

### Request/Response Normalization

The library uses OpenAI's message format as the internal canonical representation:
```lisp
;; Internal message format
(:role "user" :content "Hello")
(:role "assistant" :content "Hi there!")
(:role "assistant" :content nil :tool-calls (...))
(:role "tool" :tool-call-id "call_123" :content "{...}")
```

Provider implementations translate to/from this format. This mirrors how LiteLLM and aisuite approach normalization.

### Tool Schema Translation

Tools are defined in a provider-agnostic format and translated per-provider:

```lisp
;; Generic format (internal)
(:name "get_weather"
 :description "Get weather for a location"
 :parameters ((:name "location" :type :string :description "City name"))
 :required ("location"))

;; Translates to OpenAI format
{"type": "function",
 "function": {"name": "get_weather", ...}}

;; Translates to Anthropic format  
{"name": "get_weather",
 "description": "Get weather for a location",
 "input_schema": {"type": "object", ...}}
```

### Thread Safety

- Provider instances are immutable after creation
- Global defaults use thread-local dynamic variables
- No shared mutable state in request handling

### SBCL Optimizations (Optional)

When running on SBCL, the library can optionally use:
- `sb-ext:compare-and-swap` for lock-free operations
- Type declarations for hot paths
- Compile-time provider dispatch when type is known

These are enabled via `(pushnew :cl-llm-provider-sbcl-optimizations *features*)` before loading.

## Usage Examples

### Basic Usage
```lisp
(ql:quickload :cl-llm-provider)
(use-package :cl-llm-provider)

;; Load API keys from .env file
(load-configuration)

;; Configure defaults
(configure-defaults :provider :anthropic
                    :model "claude-3-sonnet-20240229")

;; Simple completion
(let ((response (complete '((:role "user" :content "What is Lisp?")))))
  (format t "~A~%" (response-content response)))
```

### Multiple Providers
```lisp
(let ((anthropic (make-provider :anthropic :model "claude-3-sonnet-20240229"))
      (openai (make-provider :openai :model "gpt-4-turbo"))
      (local (make-provider :ollama :model "llama3")))
  
  ;; Compare responses
  (dolist (provider (list anthropic openai local))
    (let ((response (complete '((:role "user" :content "Explain recursion"))
                              :provider provider
                              :max-tokens 200)))
      (format t "~A: ~A~%~%" 
              (type-of provider)
              (response-content response)))))
```

### Tool Calling
```lisp
(let* ((weather-tool 
        (define-tool "get_weather"
          "Get current weather for a location"
          '((:name "location" :type :string :description "City, State")
            (:name "unit" :type :string :enum ("celsius" "fahrenheit")))
          :required '("location")))
       
       (response (complete 
                  '((:role "user" :content "What's the weather in Tokyo?"))
                  :tools (list weather-tool))))
  
  (when (tool-calls response)
    (let* ((call (first (tool-calls response)))
           (result (actually-get-weather (tool-call-arguments call)))
           (final (complete 
                   (list* (response-message response)
                          (make-tool-result (tool-call-id call) result)
                          nil))))
      (format t "~A~%" (response-content final)))))
```

### Error Handling
```lisp
(handler-bind
    ((provider-rate-limit-error
      (lambda (e)
        (format t "Rate limited, waiting ~A seconds...~%" 
                (error-retry-after e))
        (invoke-restart 'wait-and-retry)))
     (provider-authentication-error
      (lambda (e)
        (declare (ignore e))
        (format t "Auth failed, trying backup key~%")
        (invoke-restart 'use-value (get-backup-api-key)))))
  (complete '((:role "user" :content "Hello"))))
```

### Embeddings
```lisp
(let* ((documents '("Common Lisp is a dialect of Lisp"
                    "Python is popular for data science"
                    "Rust provides memory safety"))
       (response (embedding documents :model "text-embedding-3-small"))
       (vectors (response-embeddings response)))
  (format t "Got ~A embeddings of dimension ~A~%"
          (length vectors)
          (length (first vectors))))
```

## Handoff to Claude Code

To implement this specification:

1. Open Claude Code in the project directory
2. Share this spec file
3. Say: "Implement this CL library spec using the cl-library-craft skill"

Claude Code will use `cl-library-craft/write/SKILL.md` to generate idiomatic code following the fukamachi conventions.

## Future Considerations (v2+)

- **Streaming**: Callback-based streaming with `complete-stream`
- **Async Operations**: `complete-async` returning futures/promises
- **Retry Policies**: Configurable retry with exponential backoff
- **Response Caching**: Optional memoization layer
- **Cost Tracking**: Token counting and cost estimation
- **Model Discovery**: Query available models from providers
- **Vision/Multimodal**: Image input support for capable models
