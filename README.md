# cl-llm-provider

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Unified Common Lisp interface for multiple LLM provider APIs (text completion and embeddings).

## Overview

`cl-llm-provider` provides a single, Lispy interface that normalizes interactions across major LLM providers while preserving provider-specific capabilities when needed. Write your code once and switch providers with a single parameter change.

**Supported Providers:**
- **Anthropic** (Claude models)
- **OpenAI** (GPT models)
- **Ollama** (local models)
- **OpenRouter** (multi-provider gateway)
- **OpenAI-compatible APIs** (Groq, Together AI, local vLLM, etc.)

**Features:**
- Unified API for text completion and embeddings
- Tool/function calling with automatic schema translation
- Configuration via Lisp config file (`~/.config/cl-llm-provider/config.lisp`)
- Global defaults with per-request overrides
- Comprehensive condition system with restarts
- Thread-safe design

## Installation

```lisp
;; Via Quicklisp (once available)
(ql:quickload :cl-llm-provider)

;; Or clone and load locally
(asdf:load-system :cl-llm-provider)
```

## Quick Start

```lisp
(use-package :cl-llm-provider)

;; Load API keys from config file
(load-configuration)

;; Configure defaults
(configure-defaults :provider :anthropic
                    :model "claude-3-sonnet-20240229")

;; Simple completion
(let ((response (complete '((:role "user" :content "What is Common Lisp?")))))
  (format t "~A~%" (response-content response)))
```

## Configuration

Create `~/.config/cl-llm-provider/config.lisp` with your API keys:

```lisp
;;; Set API keys via environment variables
(setf (uiop:getenv "ANTHROPIC_API_KEY") "sk-ant-...")
(setf (uiop:getenv "OPENAI_API_KEY") "sk-...")

;;; Or set defaults directly
(setf cl-llm-provider:*default-provider*
      (cl-llm-provider:make-provider :anthropic
                                      :model "claude-3-sonnet-20240229"))
```

See `config.lisp.example` in the repository for a complete example.

## Usage

### Creating Providers

```lisp
;; Anthropic (reads ANTHROPIC_API_KEY from environment)
(defparameter *anthropic*
  (make-provider :anthropic :model "claude-3-sonnet-20240229"))

;; OpenAI with explicit API key
(defparameter *openai*
  (make-provider :openai
                 :api-key "sk-..."
                 :model "gpt-4-turbo"))

;; Local Ollama
(defparameter *ollama*
  (make-provider :ollama
                 :base-url "http://localhost:11434"
                 :model "llama3"))

;; OpenRouter
(defparameter *openrouter*
  (make-provider :openrouter
                 :model "anthropic/claude-3-opus"))

;; OpenAI-compatible (e.g., Groq)
(defparameter *groq*
  (make-provider :openai-compatible
                 :api-key (uiop:getenv "GROQ_API_KEY")
                 :base-url "https://api.groq.com/openai/v1"
                 :model "mixtral-8x7b-32768"))
```

### Text Completion

```lisp
;; Using default provider
(complete '((:role "user" :content "Explain recursion in one sentence.")))

;; With explicit provider and parameters
(complete '((:role "user" :content "Write a haiku about Lisp."))
          :provider *anthropic*
          :model "claude-3-opus-20240229"
          :max-tokens 200
          :temperature 0.7
          :system "You are a poetic programmer.")

;; Multi-turn conversation
(complete '((:role "user" :content "What is 2+2?")
            (:role "assistant" :content "2+2 equals 4.")
            (:role "user" :content "And if you add 3?"))
          :provider *openai*)
```

### Tool Calling

```lisp
;; Define a tool
(defparameter *weather-tool*
  (define-tool "get_weather"
    "Get the current weather in a given location"
    '((:name "location"
       :type :string
       :description "City and state, e.g. San Francisco, CA")
      (:name "unit"
       :type :string
       :enum ("celsius" "fahrenheit")
       :description "Temperature unit"))
    :required '("location")))

;; Use the tool
(let ((response (complete
                 '((:role "user" :content "What's the weather in Tokyo?"))
                 :tools (list *weather-tool*))))

  ;; Check if the model wants to call a tool
  (when-let ((calls (tool-calls response)))
    (dolist (call calls)
      (format t "Tool: ~A~%" (tool-call-name call))
      (format t "Args: ~A~%" (tool-call-arguments call))

      ;; Execute the tool (your implementation)
      (let* ((result (execute-weather-tool (tool-call-arguments call)))
             ;; Send result back to the model
             (final (complete
                     (list* (response-message response)
                            (make-tool-result (tool-call-id call) result)
                            nil))))
        (format t "Final response: ~A~%" (response-content final))))))
```

### Embeddings

```lisp
;; Single text
(let ((response (embedding "Common Lisp is a powerful language"
                           :provider *openai*
                           :model "text-embedding-3-small")))
  (format t "Embedding dimension: ~A~%"
          (length (first (response-embeddings response)))))

;; Batch embeddings
(let* ((docs '("First document" "Second document" "Third document"))
       (response (embedding docs :model "text-embedding-3-small"))
       (vectors (response-embeddings response)))
  (format t "Got ~A embeddings~%" (length vectors)))
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

### Advanced Configuration

You can do anything in the Lisp config file since it's just Lisp code:

```lisp
;;; ~/.config/cl-llm-provider/config.lisp

;; Load different keys based on environment
(let ((env (or (uiop:getenv "APP_ENV") "development")))
  (cond
    ((string= env "production")
     (setf (uiop:getenv "ANTHROPIC_API_KEY") "sk-production-key"))
    ((string= env "development")
     (setf (uiop:getenv "ANTHROPIC_API_KEY") "sk-dev-key"))))

;; Use local model during the day, cloud at night
(setf cl-llm-provider:*default-provider*
      (if (< (sixth (multiple-value-list (get-decoded-time))) 18)
          (cl-llm-provider:make-provider :ollama :model "llama3")
          (cl-llm-provider:make-provider :anthropic)))
```

### Switching Providers

```lisp
;; Compare responses from different providers
(defun compare-providers (prompt)
  (dolist (provider (list *anthropic* *openai* *ollama*))
    (let ((response (complete `((:role "user" :content ,prompt))
                              :provider provider
                              :max-tokens 100)))
      (format t "~%~A:~%~A~%~%"
              (type-of provider)
              (response-content response)))))

(compare-providers "Explain Common Lisp in one sentence.")
```

### Using Context Macros

```lisp
;; Temporarily use a different provider
(with-provider ((make-provider :ollama :model "llama3"))
  (complete '((:role "user" :content "Hello")))
  (complete '((:role "user" :content "Goodbye"))))

;; Temporarily use a different model
(with-model ("claude-3-opus-20240229")
  (complete '((:role "user" :content "Complex reasoning task..."))))
```

## API Reference

### Core Functions

- `make-provider` - Create a provider instance
- `complete` - Send a completion request
- `embedding` - Generate vector embeddings
- `define-tool` - Create a tool definition
- `tool-calls` - Extract tool calls from response
- `make-tool-result` - Create tool result message

### Configuration

- `load-configuration` - Load from config.lisp file
- `configure-defaults` - Set global defaults
- `*default-provider*` - Default provider
- `*default-model*` - Default model
- `*default-max-tokens*` - Default max tokens
- `*default-temperature*` - Default temperature

### Macros

- `with-provider` - Execute with specific provider
- `with-model` - Execute with specific model

### Conditions

- `llm-provider-error` - Base error
- `provider-configuration-error` - Missing config
- `provider-api-error` - API request failed
- `provider-rate-limit-error` - Rate limited
- `provider-authentication-error` - Auth failed
- `tool-schema-error` - Invalid tool definition

## Architecture

The library uses a protocol-based design with generic functions specialized per provider:

- `send-completion-request` - Send HTTP request
- `parse-completion-response` - Parse response
- `send-embedding-request` - Send embedding request
- `parse-embedding-response` - Parse embedding response
- `translate-tool-to-provider` - Convert tool schema
- `parse-tool-calls` - Extract tool calls

New providers can be added by subclassing `llm-provider` and implementing these methods.

## Dependencies

- **alexandria** - General utilities
- **serapeum** - Additional utilities
- **dexador** - HTTP client
- **yason** - JSON parsing/generation
- **uiop** - OS interface (built-in with ASDF)
- **bordeaux-threads** - Thread safety
- **cl-ppcre** - Regular expressions

## Non-Goals (v1)

The following features are explicitly deferred to future versions:

- Streaming responses
- Audio/video/image processing
- Automatic tool execution loops
- Cost tracking or rate limiting
- Conversation memory management

## Testing

```lisp
(asdf:test-system :cl-llm-provider)
```

## License

MIT License - see LICENSE file for details.

## Author

quasi / quasiLabs

## Contributing

Contributions welcome! Please ensure:
- Code follows existing style conventions
- All tests pass
- New features include tests
- Documentation is updated

## Acknowledgments

Design inspired by Python's LiteLLM and aisuite libraries, adapted for idiomatic Common Lisp.
