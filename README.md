# cl-llm-provider

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Unified Common Lisp interface for multiple LLM providers.** Write once, switch providers with a single parameter. Works with Claude, GPT, Gemini, Ollama, and any OpenAI-compatible API.

## Why Use This?

You want to use LLMs in your Common Lisp code, but you're tired of rewriting the same request/response handling for each provider's different API format.

**cl-llm-provider solves this by:**

- **Single interface** - One `complete` and `embedding` call works across all providers (Anthropic, OpenAI, Gemini, Ollama, OpenRouter, Groq, etc.)
- **Provider-agnostic messages** - Define conversations once, run them on any LLM
- **Tool calling** - Define tools once, they work across Anthropic, OpenAI, Ollama formats automatically
- **Smart error recovery** - Rate limits, auth failures, and API errors handled gracefully with Lisp restarts
- **Accurate token counting** - Track usage across all providers with consistent metrics
- **Performance profiling** - Optional timing breakdown (encode/API/decode) for optimization
- **Configuration as Lisp** - Not YAML. Set up providers in actual Lisp code with full power.
- **Thread-safe** - Safe for concurrent requests

## Quick Start

**1. Install & set API key:**

```bash
# Via Quicklisp (when available)
sbcl --eval '(ql:quickload :cl-llm-provider)'

# Or clone and load locally
sbcl --eval '(asdf:load-system :cl-llm-provider)'

# Set your API key
export ANTHROPIC_API_KEY="sk-ant-..."
```

**2. Your first completion (3 lines):**

```lisp
(use-package :cl-llm-provider)

(let ((response (complete '((:role "user" :content "What is Lisp?")))))
  (format t "~A~%" (response-content response)))
```

Expected output:
```
Lisp is a functional programming language known for...
```

**That's it.** You now have LLM completions working. Ready to switch to OpenAI? Change `:anthropic` to `:openai`. Same code.

---

## Common Use Cases

**Chat with multiple turns:**
```lisp
(let ((messages (list (list :role "user" :content "What is 2+2?"))))
  (let ((response (complete messages)))
    (push (response-message response) messages)
    (push (list :role "user" :content "Add 3 to that?") messages)
    (complete (reverse messages))))
```

**Use tool calling:**
```lisp
(let* ((tools (list (define-tool "get_weather" "Get weather for a location"
                                  '((:name "city" :type :string)))))
       (response (complete '((:role "user" :content "What's the weather in Paris?"))
                           :tools tools)))
  (when (response-tool-calls response)
    ;; Handle tool calls...
    ))
```

**Switch providers dynamically:**
```lisp
(complete messages :provider (make-provider :openai :model "gpt-4"))
;; Same code, different provider
```

**Check provider capabilities:**
```lisp
;; Check if provider supports tools before using them
(let ((provider (make-provider :anthropic :model "claude-3-5-sonnet-20241022")))
  (if (provider-supports-p provider :tools)
      (complete messages :tools my-tools)
      (complete messages)))

;; Get model context window and pricing
(let* ((provider (make-provider :openai))
       (meta (model-metadata provider "gpt-4o")))
  (format t "Context: ~D tokens~%" (getf meta :context-window))
  (format t "Cost: $~,2F per 1M input tokens~%"
          (getf meta :input-cost-per-1m-tokens)))
```

---

## Human-Oriented Documentation

### 📚 Getting Started (Choose Your Path)

**I want to...**

| Goal | Start Here |
|------|-----------|
| **Get working in 5 minutes** | [Quick Start](docs/quickstart.md) |
| **Learn how to use this library** | [Tutorials](docs/tutorials/01-basics.md) - Progressive learning |
| **Query provider capabilities** | [Metadata API Guide](docs/metadata-api.md) - Introspection and model metadata |
| **Solve a specific problem** | [How-To Guides](docs/how-to/) - Task-oriented |
| **Understand the design** | [Explanation](docs/explanation/architecture.md) - Conceptual |
| **Look up an API** | [Reference](docs/reference/api.md) - Complete API |
| **Upgrade from old code** | [Migration Guide](docs/reference/migration.md) |

### 📖 Learning Paths

**Beginner** (0 to first working code):
1. [Quick Start](docs/quickstart.md) (5 min)
2. [Tutorial: Basics](docs/tutorials/01-basics.md) (15 min)

**Building Features** (using tools, error handling):
1. [Tutorial: Tool Calling](docs/tutorials/02-tool-calling.md)
2. [How-To: Advanced Tools](docs/how-to/tools.md)
3. [How-To: Error Handling](docs/how-to/error-handling.md)

**Mastering** (performance, custom providers):
1. [Tutorial: Advanced Features](docs/tutorials/03-advanced.md)
2. [Explanation: Protocol Architecture](docs/explanation/architecture.md)
3. [How-To: Add a Provider](docs/how-to/add-provider.md)

**Testing & Quality**:
- [How-To: Testing Tools](docs/how-to/testing.md)

### 📚 Complete Documentation Structure

```
docs/
├── quickstart.md              # Get started in 5 minutes
├── metadata-api.md            # Provider introspection and model metadata
├── tutorials/                 # Progressive learning
│   ├── 01-basics.md          # Messages and conversations
│   ├── 02-tool-calling.md    # Using tools with LLMs
│   └── 03-advanced.md        # Profiling, embeddings, error recovery
├── how-to/                    # Task-oriented guides
│   ├── tools.md              # Advanced tool features
│   ├── add-provider.md       # Implement a new provider
│   ├── error-handling.md     # Error patterns and retry logic
│   └── testing.md            # Testing tools and providers
├── explanation/               # Conceptual understanding
│   ├── architecture.md       # How the system works
│   └── providers.md          # Understanding each provider
├── reference/                # API documentation
│   ├── api.md               # Complete API reference
│   └── migration.md         # Upgrading existing code
├── examples/                 # Complete working examples
│   └── CHAT_WITH_TOOLS.md   # Interactive chat with tools
└── agent/                    # For LLM agents and code assistants
    ├── SPEC.agent.md        # Formal specification
    ├── PATTERNS.agent.md    # Runnable patterns
    ├── API-SPEC.agent.md    # Formal API specification
    └── METADATA-API.agent.md # Metadata/introspection specification
```

### 🤖 Agent-Oriented Documentation

**For LLM agents and automated code assistants** - Machine-optimized specifications:

| Document | Purpose |
|----------|---------|
| **[docs/agent/SPEC.agent.md](docs/agent/SPEC.agent.md)** | 15 normative rules, 7 invariants, verification checklist |
| **[docs/agent/PATTERNS.agent.md](docs/agent/PATTERNS.agent.md)** | 14 complete, runnable patterns |
| **[docs/agent/API-SPEC.agent.md](docs/agent/API-SPEC.agent.md)** | Formal signatures and state machines |
| **[docs/agent/METADATA-API.agent.md](docs/agent/METADATA-API.agent.md)** | 10 normative rules, 5 invariants, 10 complete patterns for metadata/introspection API |

See [docs/agent/README.md](docs/agent/README.md) for agent documentation index.

---

## Supported Providers

| Provider | Text Completion | Embeddings | Tools | Streaming | Vision |
|----------|---|---|---|---|---|
| **Anthropic** (Claude) | ✅ | ❌ | ✅ (native) | ✅ | ✅ |
| **OpenAI** (GPT-4, etc.) | ✅ | ✅ | ✅ (function calling) | ✅ | ✅ |
| **Google Gemini** | ✅ | ✅ | ✅ (function calling) | ✅ | ✅ |
| **Ollama** (local models) | ✅ | ✅ | ✅ (OpenAI-compatible) | ✅ | ❌ |
| **OpenRouter** | ✅ | ✅ | ✅ (multi-provider) | ✅ | ✅ |
| **OpenAI-compatible** (Groq, Together, vLLM) | ✅ | ✅ | ✅ | ✅ | Varies |

---

## Key Features at a Glance

- **Message Normalization** - Convert between provider formats automatically
- **Streaming Responses** - Real-time token-by-token output with callbacks
- **Provider Introspection** - Query capabilities, model metadata, and configuration without trial-and-error
- **Token Counting** - Accurate usage tracking for cost estimation
- **Performance Profiling** - Optional timing breakdown for optimization
- **Observability Hooks** - Before/after request callbacks for logging, metrics, debugging
- **Comprehensive Error Handling** - Restarts for rate limits, auth failures, API errors
- **Configuration via Lisp** - Full power of Lisp for provider setup
- **Thread-Safe** - Safe for concurrent requests across threads
- **Opt-in Design** - Load config only when you want it; defaults are sensible

---

## Testing

Comprehensive test suite included: **423 tests, 100% passing**.

**Test categories:**
- Provider protocols and request/response handling
- Token counting and metadata extraction
- Tool definition and tool calling workflows
- Error handling and recovery
- Configuration and defaults

**Run tests:**
```bash
sbcl --noinform --non-interactive --load tests/test-tools-support.lisp
sbcl --noinform --non-interactive --load tests/test-provider-protocols.lisp
sbcl --noinform --non-interactive --load tests/test-token-metadata-comprehensive.lisp
```

See `tests/README.md` for complete test documentation.

---

## Non-Goals (v1)

These features are intentionally deferred to future versions:

- Audio/video/image processing
- Automatic tool execution loops
- Cost tracking and billing
- Built-in conversation memory management

---

## Dependencies

- **alexandria** - General utilities
- **serapeum** - Additional utilities
- **dexador** - HTTP client
- **yason** - JSON parsing
- **uiop** - OS interface
- **bordeaux-threads** - Thread safety
- **cl-ppcre** - Regular expressions

All are standard, well-maintained libraries available via Quicklisp.

---

## Contributing

Contributions welcome! Please ensure:
- Code follows existing style conventions
- All 423 tests pass
- New features include tests
- Documentation is updated

---

## License

MIT License - see LICENSE file for details.

---

## Author

quasi / quasiLabs

Design inspired by Python's LiteLLM and aisuite libraries, adapted for idiomatic Common Lisp.
