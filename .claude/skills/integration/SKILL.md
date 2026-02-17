---
name: cl-llm-provider-integration
description: How to use cl-llm-provider LLM abstraction in your Common Lisp project
version: 1.0.0
author: quasiLabs
type: integration
---

# cl-llm-provider Integration Skill

## What is cl-llm-provider

A unified Common Lisp interface for multiple LLM providers. Write LLM code once, switch providers freely. Protocol-based design with provider-agnostic messages, tool calling, streaming, and error recovery via conditions/restarts.

## Quick Start

```lisp
(ql:quickload :cl-llm-provider)

;; Create a provider
(defvar *provider* (make-provider :anthropic :api-key "..."))

;; Basic completion
(complete *provider*
  :messages '((:role "user" :content "Hello"))
  :model "claude-sonnet-4-5-20250929")

;; With tool calling
(complete *provider*
  :messages '((:role "user" :content "What's the weather?"))
  :tools (list (define-tool "get_weather" ...)))

;; Streaming
(complete-stream *provider*
  :messages '((:role "user" :content "Tell me a story"))
  :callback (lambda (chunk) (format t "~a" chunk)))
```

## Core Concepts

**Providers**: Each LLM backend (`:anthropic`, `:openai`, `:ollama`, `:openrouter`, `:gemini`) is a provider instance created with `make-provider`. Providers are immutable after creation.

**Messages**: Provider-agnostic plist format with `:role` and `:content`. Roles: `"user"`, `"assistant"`, `"system"`, `"tool"`. Always oldest-first ordering.

**Tool Calling**: Define tools with `define-tool`, pass via `:tools` parameter. Tool names must match `^[a-zA-Z0-9_-]+$`. Every tool-call needs a matching tool-result.

**Error Handling**: Errors signal conditions (not return values). Use `handler-bind`/`handler-case` with restarts like `retry-request`, `use-fallback-provider`, `skip-tool-call`.

## Key API

| Function | Purpose |
|----------|---------|
| `make-provider` | Create provider instance |
| `complete` | Send completion request |
| `complete-stream` | Streaming completion with callback |
| `embedding` | Generate embeddings |
| `define-tool` | Define a tool for tool-calling |
| `tool-calls` | Extract tool calls from response |
| `make-tool-result` | Create tool result for next turn |
| `model-metadata` | Get model info (context window, pricing) |
| `provider-supports-p` | Check if provider supports a feature |

## Common Patterns

**Multi-turn conversation**:
```lisp
(let ((messages '((:role "user" :content "What is CL?"))))
  (let ((response (complete *provider* :messages messages)))
    ;; Append assistant response, then user follow-up
    (push (list :role "assistant" :content (response-content response)) messages)
    (push (list :role "user" :content "Tell me more") messages)
    (complete *provider* :messages (reverse messages))))
```

**Error recovery with restarts**:
```lisp
(handler-bind
    ((llm-api-error
       (lambda (c)
         (invoke-restart 'retry-request :max-retries 3))))
  (complete *provider* :messages messages))
```

**Provider switching** — just change the provider, code stays the same:
```lisp
(defvar *openai* (make-provider :openai :api-key "..."))
(complete *openai* :messages messages :model "gpt-4o")
```

## Pitfalls

- **Messages must be oldest-first** — reverse chronological order causes silent failures
- **Don't mutate providers** — create new instances instead
- **Match every tool-call** — missing tool-results break conversation flow
- **Don't catch conditions generically** — use specific condition types
- **Never log API keys** — they appear in provider instances; be careful with debug output

## Detailed Specifications

| Reference | Content |
|-----------|---------|
| `references/core-spec.md` | 15 normative rules, 7 invariants, verification checklist |
| `references/core-api-spec.md` | Full protocol contracts, method signatures, type specs |
| `references/core-patterns.md` | 14 complete runnable patterns |
| `references/metadata-api-spec.md` | Provider introspection, model registry |
| `references/streaming-api-spec.md` | Streaming API specification |
| `references/streaming-patterns.md` | Streaming and observability patterns |
