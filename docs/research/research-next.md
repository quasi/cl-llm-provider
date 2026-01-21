# Feature Research: Multi-Provider LLM Support - Tools, Tokens, and Context Management

## Executive Summary

**Domain**: Multi-provider LLM libraries with comprehensive tool calling, token management, and context handling
**Date**: 2026-01-12
**Primary Reference**: LiteLLM (Python) - most comprehensive feature set, 100+ providers, mature production deployment
**Secondary References**:
- Vercel AI SDK (JavaScript/TypeScript) - best-in-class developer experience, streaming, structured outputs
- aisuite (Python) - simplest API, good for understanding minimal viable interface

### Key Findings

1. **Streaming is table stakes** - All modern multi-provider libraries support streaming responses (text, objects, tool calls). This is critical for user experience and is expected by 2026.

2. **Context management has evolved beyond simple token counting** - Advanced libraries provide prompt caching, context window overflow detection, automatic truncation, and "bash-tool" style retrieval to keep large context local.

3. **Tool calling has become sophisticated** - Beyond basic function calling, libraries now support:
   - Parallel tool execution
   - Tool result streaming
   - Automatic tool execution loops
   - Tool-level provider options (e.g., caching tool definitions)
   - Programmatic tool calling (code execution environments)
   - Multi-modal tool results (images/audio from tools)

4. **Observability is a first-class concern** - Production libraries integrate with tracing platforms (Langfuse, Helicone, Datadog), provide detailed usage metadata, and support debugging workflows.

5. **Cost optimization requires intelligent routing** - Libraries provide routing logic to select models based on cost, capability, or performance thresholds.

### Recommendation

**Phase 1 - Critical Gaps (Implement Now)**:
Focus on streaming support and enhanced context management. These are fundamental expectations in 2026 and directly impact user experience and production viability.

**Phase 2 - Production Readiness**:
Add observability hooks, retry/fallback mechanisms, and batch processing support. These are essential for production deployments.

**Phase 3 - Advanced Features**:
Implement parallel tool calling, tool result streaming, prompt caching, and intelligent routing. These differentiate best-in-class libraries.

---

## 1. Problem Domain

### Core Functionality
Multi-provider LLM libraries abstract differences between LLM providers (OpenAI, Anthropic, Google, etc.) and provide a unified interface for:
- Text completion and chat
- Tool/function calling
- Token counting and cost estimation
- Message format normalization
- Error handling and retry logic

### Adjacent Functionality
Mature implementations extend beyond basic API calls to include:
- **Streaming**: Real-time token generation for text, objects, and tool calls
- **Context Management**: Token counting, context window detection, prompt caching, truncation strategies
- **Tool Execution**: Tool definition, validation, execution, result handling, parallel calling
- **Observability**: Logging, tracing, debugging, cost tracking
- **Reliability**: Retry logic, fallbacks, rate limit handling
- **Optimization**: Batch processing, intelligent routing, cost optimization

### Out of Scope
The following are typically separate concerns or explicitly non-goals:
- Built-in conversation memory/persistence (left to application layer)
- Fine-tuning APIs (separate from inference)
- Vector databases and embeddings management (separate tools)
- Built-in UI components (though some libraries provide React hooks)

---

## 2. Landscape Survey

### Implementations Reviewed

| Name | Ecosystem | Stars/Popularity | Last Active | Notes |
|------|-----------|-----------------|-------------|-------|
| **LiteLLM** | Python | 15k+ stars | Jan 2026 | 100+ providers, proxy server, comprehensive |
| **Vercel AI SDK** | TypeScript/JS | Very high (Vercel) | Jan 2026 | Best DX, streaming, React integration |
| **aisuite** | Python | 12k+ stars | Dec 2025 | Andrew Ng project, simplest API |
| **LangChain** | Python/JS | 100k+ stars | Jan 2026 | Agent framework, comprehensive but complex |
| **multi-llm-ts** | TypeScript | ~500 stars | 2025 | Simple unified interface |
| **llm-sdk** | TypeScript/Rust/Go | Active | 2025 | Multi-language, multi-modal tools |
| **Instructor** | Python/JS | 10k+ stars | 2026 | Structured outputs focus |
| **cl-llm-provider** | Common Lisp | N/A | Jan 2026 | Our implementation - solid foundation |

### Ecosystem Observations

**Python**: Most mature ecosystem for LLM tooling. LiteLLM is the gold standard for production use with proxy server, cost tracking, and 100+ provider support. aisuite provides the simplest possible API, good reference for minimal interface design.

**TypeScript/JavaScript**: Vercel AI SDK leads in developer experience with excellent streaming support, React hooks, and structured output handling. Strong focus on UI integration.

**Common Lisp**: cl-llm-provider is well-positioned with solid fundamentals (provider abstraction, tool calling, token counting, error handling). Main gaps are streaming and advanced context management.

---

## 3. Deep Dive: Reference Implementations

### LiteLLM (Python) - Primary Reference

**Repository**: https://github.com/BerriAI/litellm
**Documentation**: https://docs.litellm.ai/

#### API Overview

```python
from litellm import completion, acompletion, token_counter, completion_cost

# Basic completion
response = completion(
    model="gpt-3.5-turbo",
    messages=[{"role": "user", "content": "Hello"}]
)

# Streaming
response = completion(model="gpt-3.5-turbo", messages=messages, stream=True)
for chunk in response:
    print(chunk)

# Async streaming
response = await acompletion(model="gpt-3.5-turbo", messages=messages, stream=True)
async for chunk in response:
    print(chunk)

# Token counting before API call
token_count = token_counter(model="gpt-3.5-turbo", messages=messages)
cost_estimate = completion_cost(model="gpt-3.5-turbo", prompt="...", completion="...")

# Router with retries and fallbacks
from litellm import Router
router = Router(
    model_list=[
        {"model_name": "gpt-3.5-turbo", "litellm_params": {"model": "gpt-3.5-turbo"}},
        {"model_name": "gpt-3.5-turbo", "litellm_params": {"model": "claude-3-sonnet"}}
    ],
    num_retries=2,
    retry_strategy="exponential_backoff_retry"
)
response = await router.acompletion(model="gpt-3.5-turbo", messages=messages)

# Batch processing
response = await litellm.acreate_batch(
    completion_window="24h",
    endpoint="/v1/chat/completions",
    input_file_id=file_id
)
```

#### Architecture

```
litellm/
├── completion()          # Sync/async completion with unified interface
├── token_counter()       # Pre-request token counting
├── completion_cost()     # Cost estimation
├── Router               # Load balancing, retries, fallbacks
│   ├── retry_strategy   # Exponential backoff for rate limits
│   ├── num_retries      # Per-model retry count
│   └── allowed_fails    # Cooldown threshold
├── Batch API            # Async batch processing
└── Observability        # Langfuse, Helicone, etc. integration
```

#### Complexity Analysis

- **Total LoC**: ~50k+ (estimated from repo size)
- **Core LoC**: ~10k for main completion logic
- **Dependencies**: Moderate (requests, pydantic, tokenizers)
- **Files/Modules**: 100+ files

**What makes it complex**:
- Supporting 100+ providers with different API formats
- Proxy server implementation (separate deployment mode)
- Complex routing logic with fallbacks and load balancing
- Comprehensive error handling for every provider's quirks
- Cost database maintenance (model pricing updates)
- Token counting for multiple tokenizer formats

**What keeps it manageable**:
- Clear separation: SDK vs. Proxy Server
- Provider-specific modules (providers/openai.py, providers/anthropic.py)
- Unified response format based on OpenAI schema
- Extensive test coverage

#### Strengths
- **Production-ready**: Proxy server mode, rate limiting, budgets
- **Comprehensive provider support**: 100+ providers
- **Cost tracking**: Built-in pricing database and tracking
- **Observability**: First-class integration with monitoring platforms
- **Performance**: 6.5x faster with fastuuid optimization (2026)
- **Batch processing**: Support for async batch jobs

#### Weaknesses
- **Complexity**: Large codebase can be overwhelming
- **Python-specific**: No multi-language story
- **Breaking changes**: Rapid development means occasional API changes
- **Documentation sprawl**: Lots of features, hard to discover everything

---

### Vercel AI SDK (TypeScript) - Best Developer Experience

**Repository**: https://github.com/vercel/ai
**Documentation**: https://ai-sdk.dev/

#### API Overview

```typescript
import { generateText, streamText, streamObject } from 'ai';
import { openai } from '@ai-sdk/openai';

// Basic text generation
const { text } = await generateText({
  model: openai('gpt-4-turbo'),
  prompt: 'What is love?',
});

// Streaming text
const result = await streamText({
  model: openai('gpt-4-turbo'),
  prompt: 'Tell me a story',
});

for await (const textPart of result.textStream) {
  process.stdout.write(textPart);
}

// Structured output with schema validation
const result = await generateText({
  model: openai('gpt-4-turbo'),
  prompt: 'Generate a person',
  output: {
    schema: z.object({
      name: z.string(),
      age: z.number(),
    }),
  },
});

// Tool calling with streaming inputs
const result = await streamText({
  model: anthropic('claude-3-5-sonnet-20241022'),
  tools: {
    getWeather: {
      description: 'Get weather for location',
      parameters: z.object({
        city: z.string(),
      }),
      execute: async ({ city }) => {
        return { temperature: 72 };
      },
    },
  },
  prompt: 'What is the weather in Paris?',
});

// Tool lifecycle hooks
const result = await streamText({
  model: anthropic('claude-3-5-sonnet-20241022'),
  tools: { /* ... */ },
  onInputStart: ({ toolName }) => console.log(`Starting ${toolName}`),
  onInputDelta: ({ toolName, argsTextDelta }) => console.log(argsTextDelta),
  onInputAvailable: ({ toolName, args }) => console.log(`Got args: ${args}`),
});

// Prompt caching (Anthropic)
const result = await generateText({
  model: anthropic('claude-3-5-sonnet-20241022'),
  messages: [...],
  providerOptions: {
    anthropic: { cacheControl: { type: 'ephemeral' } }
  }
});

// Memory tool (AI SDK 6)
const result = await streamText({
  model: anthropic('claude-3-5-sonnet-20241022'),
  tools: memory({ directory: './memory' }),
  prompt: 'Remember that I like pizza',
});
```

#### Architecture

```
AI SDK Architecture:
├── Core
│   ├── generateText()        # Sync text generation
│   ├── streamText()          # Streaming text with tool support
│   ├── generateObject()      # Structured output
│   └── streamObject()        # Streaming structured output
├── Tools
│   ├── Tool definition       # Zod schemas
│   ├── Tool execution        # Automatic or manual
│   ├── Tool streaming        # Input/output streaming
│   └── Lifecycle hooks       # onInputStart, onInputDelta, etc.
├── Messages
│   ├── UIMessage            # Application state (for persistence)
│   └── ModelMessage         # Optimized for LLM API
├── Provider Options
│   ├── Caching              # Provider-specific (Anthropic)
│   ├── Strict mode          # OpenAI structured outputs
│   └── Custom headers       # Provider extensions
└── Integrations
    ├── React hooks          # useChat, useCompletion
    ├── Stream protocol      # Server-to-client streaming
    └── Observability        # Built-in DevTools
```

#### Complexity Analysis

- **Total LoC**: ~30k+ (estimated)
- **Core LoC**: ~8k for core SDK
- **Dependencies**: Minimal (zod, provider SDKs)
- **Files/Modules**: ~100+ files organized by concern

**What makes it complex**:
- Dual message types (UIMessage vs ModelMessage) for different use cases
- Stream protocol implementation for server-client communication
- React integration and hooks management
- Provider-specific options and feature flags
- Schema validation integration (Zod, JSON Schema, Valibot)

**What keeps it simple**:
- Clear separation of concerns (Core, UI, RSC, Providers)
- Excellent TypeScript types guide usage
- Consistent API patterns (generate*/stream*)
- Comprehensive examples and documentation

#### Strengths
- **Best-in-class DX**: Excellent TypeScript types, clear APIs
- **Streaming everywhere**: Text, objects, tool inputs all stream
- **Structured outputs**: First-class schema validation support
- **React integration**: Hooks make UI integration trivial
- **Tool lifecycle**: Granular hooks for tool execution stages
- **Data parts**: Send arbitrary typed data alongside LLM responses
- **Memory tools**: Provider-specific optimizations (bash-tool, etc.)
- **Prompt caching**: Full support with clear API

#### Weaknesses
- **JavaScript/TypeScript only**: No multi-language support
- **Vercel ecosystem**: Some features tied to Vercel platform
- **Breaking changes**: Frequent major version updates
- **Complexity for simple use cases**: Many concepts to learn

---

### aisuite (Python) - Simplicity Reference

**Repository**: https://github.com/andrewyng/aisuite
**Documentation**: https://github.com/andrewyng/aisuite

#### API Overview

```python
import aisuite as ai

client = ai.Client()

# Simple completion - provider:model format
response = client.chat.completions.create(
    model="openai:gpt-4o",
    messages=[{"role": "user", "content": "What is AI?"}]
)

# Switch providers easily
response = client.chat.completions.create(
    model="anthropic:claude-3-5-sonnet-20241022",
    messages=[{"role": "user", "content": "What is AI?"}]
)

# Tool calling with automatic schema generation
def get_weather(city: str) -> dict:
    """Get weather for a city."""
    return {"temperature": 72}

response = client.chat.completions.create(
    model="openai:gpt-4o",
    messages=[{"role": "user", "content": "Weather in Paris?"}],
    tools=[get_weather]  # Pass real functions!
)

# Agent with automatic tool execution
response = client.chat.completions.create(
    model="openai:gpt-4o",
    messages=[{"role": "user", "content": "Book me a flight"}],
    tools=[search_flights, book_flight],
    max_turns=5  # Automatic tool execution loop
)
```

#### Architecture

Simple three-layer design:
```
aisuite/
├── Client                  # Main entry point
├── Provider plugins        # Modular provider support
│   ├── openai.py
│   ├── anthropic.py
│   └── ...
└── Tool handling
    ├── Schema generation   # From Python functions
    ├── Tool execution      # Automatic or manual
    └── MCP integration     # Model Context Protocol
```

#### Complexity Analysis

- **Total LoC**: ~5k (small codebase)
- **Core LoC**: ~1k for main client
- **Dependencies**: Provider SDKs only
- **Files/Modules**: ~20 files

**What makes it simple**:
- Minimal abstractions - just Client and provider plugins
- "provider:model" string format eliminates configuration
- Pass Python functions directly as tools
- Automatic tool execution with max_turns
- No custom types - uses OpenAI format directly

**What's missing** (intentionally):
- No streaming support (yet)
- No batch processing
- No cost tracking
- No observability integrations
- Limited error handling

#### Strengths
- **Simplest possible API**: "provider:model" string, done
- **Tool calling made easy**: Pass real Python functions
- **Automatic tool execution**: max_turns parameter
- **MCP integration**: Connect to Model Context Protocol tools
- **Great for learning**: Easy to understand codebase

#### Weaknesses
- **No streaming**: Not production-ready without it
- **Limited features**: Basic functionality only
- **Young project**: Less battle-tested than alternatives
- **No cost tracking**: Can't estimate or track costs

---

## 4. Feature Analysis

### Core Features (Must Have) - We Have These

| Feature | Complexity | cl-llm-provider Status | Notes |
|---------|------------|------------------------|-------|
| Provider abstraction | Medium | ✅ Complete | Multiple providers supported |
| Message normalization | Medium | ✅ Complete | Convert between formats |
| Tool definition | Low | ✅ Complete | `define-tool` with validation |
| Tool calling | Medium | ✅ Complete | Request and parse tool calls |
| Token counting | Medium | ✅ Complete | Usage tracking in responses |
| Error handling | Medium | ✅ Complete | Restarts for rate limits, auth |
| Model metadata | Low | ✅ Complete | Context windows, pricing, capabilities |
| Provider introspection | Low | ✅ Complete | `provider-supports-p`, `model-metadata` |

### Critical Gaps (Should Have - Missing)

| Feature | Complexity | Benefit | Rationale |
|---------|------------|---------|-----------|
| **Streaming responses** | High | Essential | Table stakes in 2026, required for UX |
| **Context window management** | Medium | Important | Detect overflow, handle gracefully |
| **Token counting before call** | Low | Important | Cost estimation, prevent errors |
| **Retry/exponential backoff** | Medium | Important | Production reliability |
| **Batch API support** | Medium | Useful | Cost savings (50% discount) |
| **Observability hooks** | Low | Important | Debugging, monitoring, tracing |

### Advanced Features (Could Have)

| Feature | Complexity | Benefit | Rationale |
|---------|------------|---------|-----------|
| **Parallel tool calling** | Medium | Useful | Performance for multi-tool scenarios |
| **Tool result streaming** | High | Useful | Real-time feedback for long operations |
| **Prompt caching** | Low | Important | Reduce costs and latency (Anthropic) |
| **Streaming structured output** | High | Useful | Progressive UI updates |
| **Intelligent routing** | Medium | Useful | Cost optimization |
| **Multi-modal support** | Medium | Nice-to-have | Vision, audio (future) |
| **Memory management** | Low | Nice-to-have | Application-level concern |

### Explicitly Out of Scope (v1)

- **Built-in conversation memory** - Application responsibility
- **Vector database integration** - Separate concern
- **Fine-tuning APIs** - Different from inference
- **Built-in UI components** - Language doesn't support it
- **Automatic tool execution loops** - Application logic

---

## 5. Complexity vs. Benefit Matrix

```
                    │ Low Complexity │ Medium         │ High           │
────────────────────┼────────────────┼────────────────┼────────────────┤
Essential           │ • Token count  │                │ • Streaming    │
                    │   before call  │                │   responses    │
                    │ • Observability│                │                │
────────────────────┼────────────────┼────────────────┼────────────────┤
Important           │ • Prompt       │ • Context      │                │
                    │   caching      │   overflow     │                │
                    │                │ • Retry logic  │                │
                    │                │ • Batch API    │                │
────────────────────┼────────────────┼────────────────┼────────────────┤
Useful              │ • Memory       │ • Parallel     │ • Tool result  │
                    │   management   │   tools        │   streaming    │
                    │                │ • Multi-modal  │ • Streaming    │
                    │                │ • Routing      │   objects      │
────────────────────┼────────────────┼────────────────┼────────────────┤
Nice-to-have        │ (defer all)    │ (defer all)    │ (defer all)    │
```

**Priority 1 (Implement Now)**:
- Streaming responses (High complexity, Essential benefit)
- Token counting before call (Low complexity, Essential benefit)
- Observability hooks (Low complexity, Essential benefit)

**Priority 2 (Production Readiness)**:
- Context window overflow detection (Medium complexity, Important benefit)
- Retry/exponential backoff (Medium complexity, Important benefit)
- Batch API support (Medium complexity, Important benefit)

**Priority 3 (Differentiation)**:
- Prompt caching (Low complexity, Important benefit)
- Parallel tool calling (Medium complexity, Useful benefit)
- Intelligent routing (Medium complexity, Useful benefit)

---

## 6. Design Patterns Observed

### Universal Patterns (Every implementation uses)

1. **Provider Plugin Architecture**
   - Abstract provider interface/protocol
   - Provider-specific implementations
   - Factory pattern for provider creation
   - Example: `make-provider :anthropic` → anthropic-provider instance

2. **OpenAI Format as Lingua Franca**
   - Most libraries normalize to OpenAI's message/response format
   - Providers translate to/from their native format
   - Makes switching providers transparent

3. **Unified Tool Definition Format**
   - JSON Schema for parameters
   - Name, description, parameters structure
   - Required field lists

### Common Patterns (Most implementations use)

4. **Token Counting Abstraction**
   - Pre-request: Estimate tokens before API call
   - Post-request: Extract usage from response
   - Model-specific tokenizers (tiktoken, sentencepiece)

5. **Error Hierarchy**
   - Base error class
   - Specialized errors (RateLimitError, AuthError, ContextWindowError)
   - Condition system / error handling with restarts

6. **Configuration Management**
   - Environment variables for API keys
   - Explicit configuration overrides
   - Defaults from registry/config files

7. **Async/Streaming Support**
   - Separate sync and async APIs
   - Iterator/generator pattern for streaming
   - Chunk-by-chunk processing

### Divergent Approaches (Trade-offs)

8. **Message State Management**
   - **Vercel AI SDK**: Dual message types (UIMessage vs ModelMessage)
     - Pro: Optimize for different use cases
     - Con: More complexity
   - **Others**: Single message format
     - Pro: Simpler
     - Con: Not optimized for persistence vs. API calls

9. **Tool Execution**
   - **Automatic** (aisuite): `max_turns` parameter, auto-execute tools
     - Pro: Simplest for common case
     - Con: Less control
   - **Manual** (most): Return tool calls, app executes, send results
     - Pro: Full control, inspection
     - Con: More code

10. **Retry Strategy**
    - **Router-level** (LiteLLM): Routing layer handles retries/fallbacks
      - Pro: Centralized, powerful
      - Con: Must use Router
    - **Call-level** (most): Per-call retry configuration
      - Pro: Simple, flexible
      - Con: Repetitive configuration

---

## 7. Implementation Insights

### What Works Well

1. **Streaming is non-negotiable for production**
   - Users expect real-time feedback
   - Enables better UX (progressive display)
   - Required for long responses
   - Implementation: Generator/iterator pattern works well

2. **Token counting saves money and prevents errors**
   - Count before call → estimate cost, prevent context overflow
   - Count after call → track actual usage
   - Implementation: Use model-specific tokenizers where available, fall back to tiktoken

3. **Provider-specific options are necessary**
   - Not all features map across providers (e.g., Anthropic caching)
   - Implementation: `providerOptions` or `options` parameter

4. **Tool calling should be declarative**
   - Define tools once, work across providers
   - Library handles format translation
   - Validation happens early (before API call)

5. **Observability hooks enable debugging**
   - Callback functions for logging/tracing
   - Integration with monitoring platforms
   - Implementation: Simple callback functions or protocol

6. **Retry with exponential backoff is essential**
   - Rate limits are common
   - Network failures happen
   - Implementation: Configurable retry count + backoff strategy

### Common Pitfalls

1. **Context window overflow is silent failure**
   - APIs reject with error, but damage is done (tokens charged, time wasted)
   - Solution: Pre-flight token counting + overflow detection

2. **Provider differences leak through abstractions**
   - Tool calling formats differ subtly
   - Some features are provider-specific (parallel tools, caching)
   - Solution: Capability detection + provider-specific options

3. **Streaming adds complexity everywhere**
   - Error handling in streams
   - Partial results
   - Connection issues mid-stream
   - Solution: Robust chunk handling, connection recovery

4. **Token counting is imprecise**
   - Different tokenizers give different counts
   - Provider may count differently than client
   - Solution: Accept 5-10% variance, use provider's count as ground truth

5. **Cost tracking requires maintenance**
   - Model pricing changes
   - New models added
   - Solution: Separate pricing database, regular updates

### Opportunities

1. **Lisp advantages for tool definitions**
   - Could use Lisp functions directly (like aisuite's Python functions)
   - Macro for tool definition → automatic parameter extraction
   - Condition system for rich error handling

2. **Streaming + CLOS**
   - Generic functions for different stream types
   - Protocol for streamable responses
   - Method combination for stream processing

3. **Thread-safe by design**
   - Lisp's threading primitives are excellent
   - Can build robust concurrent request handling

4. **DSL for routing logic**
   - Lisp excels at DSLs
   - Could build expressive routing rules
   - Example: `(route-by :cost < 0.001 :capability :tools)`

---

## 8. Detailed Feature Specifications

### 8.1 Streaming Responses

**What**: Real-time token-by-token delivery of LLM responses.

**Why Essential**:
- Users expect real-time feedback (industry standard by 2026)
- Better UX for long responses
- Enables progressive UI updates
- Required for production applications

**Implementation Complexity**: High
- Must handle connection management
- Partial JSON parsing for tool calls
- Error handling mid-stream
- Different streaming formats per provider

**API Design** (proposed for cl-llm-provider):

```lisp
;; Basic streaming
(let ((stream (complete-stream messages :provider *anthropic*)))
  (loop for chunk = (stream-read-chunk stream)
        while chunk
        do (format t "~A" (chunk-content chunk))))

;; Or with callback
(complete-stream messages
  :provider *anthropic*
  :on-chunk (lambda (chunk)
              (format t "~A" (chunk-content chunk))))

;; Async streaming
(with-async-stream (stream (complete-stream messages))
  (loop for chunk = (await (stream-read-chunk stream))
        while chunk
        do (format t "~A" (chunk-content chunk))))
```

**Provider Differences**:
- OpenAI: Server-Sent Events (SSE) with `data: ` prefix
- Anthropic: Multiple event types (content_block_start, content_block_delta, etc.)
- Ollama: Newline-delimited JSON

**Reference Implementation**:
- LiteLLM: `litellm.completion(stream=True)` returns iterator
- Vercel AI SDK: `streamText()` returns async iterator + text stream

### 8.2 Context Window Management

**What**: Detect and handle context window overflow before/during API calls.

**Why Important**:
- Prevent API errors (costs time + money)
- Enable automatic truncation strategies
- Provide clear error messages

**Implementation Complexity**: Medium
- Token counting before call
- Compare against model's context window
- Different truncation strategies
- Handle system prompt separately

**API Design** (proposed):

```lisp
;; Check context before call
(let ((token-count (count-tokens messages :model "gpt-4")))
  (when (> token-count (model-max-tokens "gpt-4"))
    (error 'context-window-exceeded
           :tokens token-count
           :max-tokens (model-max-tokens "gpt-4"))))

;; Automatic truncation
(complete messages
  :provider *openai*
  :max-context-tokens 4000
  :truncation-strategy :keep-recent)  ; or :keep-first, :smart

;; Overflow detection with helpful error
(handler-bind ((context-window-exceeded
                (lambda (c)
                  (format t "Context too large: ~D tokens (max ~D)~%"
                          (context-window-exceeded-tokens c)
                          (context-window-exceeded-max-tokens c))
                  (invoke-restart 'truncate-and-retry))))
  (complete messages :provider *openai*))
```

**Truncation Strategies**:
1. **Keep Recent**: Drop oldest messages (preserves recent context)
2. **Keep First**: Keep initial messages (preserves instructions)
3. **Smart**: Keep system + recent user/assistant pairs
4. **Summarize**: LLM-based summarization (expensive but best)

**Reference Implementation**:
- LiteLLM: `get_max_tokens()`, `ContextWindowExceededError`
- Vercel AI SDK: Messages middleware for compression

### 8.3 Token Counting Before API Calls

**What**: Estimate token count before making API request.

**Why Important**:
- Cost estimation
- Context window overflow prevention
- Helps users understand token usage

**Implementation Complexity**: Low-Medium
- Need tokenizer for each model family
- tiktoken for OpenAI models
- Sentencepiece for some others
- Approximate for unknown models

**API Design** (proposed):

```lisp
;; Count tokens for messages
(defun count-tokens (messages &key model provider)
  "Count tokens in MESSAGES for MODEL/PROVIDER.
Returns estimated token count."
  (let ((tokenizer (get-tokenizer model provider)))
    (count-message-tokens messages tokenizer)))

;; Estimate cost before call
(defun estimate-cost (messages &key model provider max-tokens)
  "Estimate cost for completion.
Returns (values input-cost output-cost-estimate total-estimate)."
  (let* ((input-tokens (count-tokens messages :model model :provider provider))
         (output-tokens (or max-tokens 1000))
         (meta (model-metadata provider model))
         (input-cost-per-1m (getf meta :input-cost-per-1m-tokens))
         (output-cost-per-1m (getf meta :output-cost-per-1m-tokens)))
    (values (* input-tokens (/ input-cost-per-1m 1000000.0))
            (* output-tokens (/ output-cost-per-1m 1000000.0))
            (+ (* input-tokens (/ input-cost-per-1m 1000000.0))
               (* output-tokens (/ output-cost-per-1m 1000000.0))))))

;; Usage
(let ((cost (estimate-cost messages :model "gpt-4" :max-tokens 500)))
  (when (> cost 0.10)
    (unless (yes-or-no-p "Cost will be ~$~,3F. Continue?" cost)
      (return-from expensive-query nil)))
  (complete messages :model "gpt-4" :max-tokens 500))
```

**Tokenizers by Provider**:
- OpenAI: tiktoken (cl-tiktoken package or FFI)
- Anthropic: Claude tokenizer (approximate with tiktoken)
- Others: Fall back to character-based estimation

**Reference Implementation**:
- LiteLLM: `token_counter()`, `completion_cost()`
- Vercel AI SDK: Not built-in, use provider SDKs

### 8.4 Retry Logic with Exponential Backoff

**What**: Automatically retry failed requests with increasing delays.

**Why Important**:
- Rate limits are common
- Network failures happen
- Improves reliability

**Implementation Complexity**: Medium
- Detect retriable errors (rate limit, network, 5xx)
- Exponential backoff calculation
- Max retries limit
- Jitter to prevent thundering herd

**API Design** (proposed):

```lisp
;; Simple retry
(complete messages
  :provider *openai*
  :num-retries 3
  :retry-strategy :exponential-backoff)

;; Advanced retry configuration
(complete messages
  :provider *openai*
  :retry-policy (make-retry-policy
                 :max-retries 5
                 :initial-delay 1.0
                 :max-delay 60.0
                 :exponential-base 2
                 :jitter t
                 :retriable-errors '(rate-limit-error network-error api-error-5xx)))

;; With fallback providers
(complete messages
  :providers (list *openai* *anthropic* *groq*)
  :retry-policy *default-retry-policy*
  :fallback-on-failure t)
```

**Exponential Backoff Formula**:
```
delay = min(max-delay, initial-delay * (base ^ attempt) + random-jitter)
```

**Retriable vs. Non-Retriable Errors**:
- **Retriable**: Rate limit (429), Network errors, 5xx server errors
- **Non-Retriable**: Auth errors (401), Invalid request (400), Context overflow

**Reference Implementation**:
- LiteLLM: `num_retries` + `retry_strategy="exponential_backoff_retry"`
- Custom: bordeaux-threads for delays, random for jitter

### 8.5 Observability Hooks

**What**: Callbacks for logging, tracing, and monitoring LLM calls.

**Why Important**:
- Debugging complex interactions
- Cost tracking
- Performance monitoring
- Integration with observability platforms

**Implementation Complexity**: Low
- Simple callback functions
- Capture timing, tokens, costs
- Optional integration with tracing platforms

**API Design** (proposed):

```lisp
;; Simple callbacks
(complete messages
  :provider *anthropic*
  :on-request (lambda (request)
                (log:info "Sending request: ~A" request))
  :on-response (lambda (response timing)
                 (log:info "Got response: ~A tokens, ~Ams"
                          (response-usage response)
                          timing)))

;; Lifecycle hooks
(defvar *observability-hooks* (make-hooks))

(add-hook *observability-hooks* :before-request
          (lambda (provider model messages)
            (log:debug "Request to ~A/~A with ~D messages"
                      provider model (length messages))))

(add-hook *observability-hooks* :after-response
          (lambda (provider model response)
            (track-cost provider model response)))

(complete messages :hooks *observability-hooks*)

;; Integration with tracing platforms
(defclass langfuse-observer ()
  ((api-key :initarg :api-key)))

(defmethod observe-request ((obs langfuse-observer) request)
  (langfuse-log-request (slot-value obs 'api-key) request))

(defmethod observe-response ((obs langfuse-observer) response)
  (langfuse-log-response (slot-value obs 'api-key) response))

(complete messages :observer (make-instance 'langfuse-observer :api-key "..."))
```

**Data to Capture**:
- Request: provider, model, messages, parameters
- Response: content, usage (tokens), finish reason
- Timing: total time, encode time, API time, decode time
- Errors: type, message, stack trace

**Integration Targets**:
- Langfuse (open source LLM observability)
- Helicone (LLM proxy + observability)
- Datadog LLM Observability
- Custom logging/metrics systems

**Reference Implementation**:
- LiteLLM: Callbacks + success_callback/failure_callback
- Vercel AI SDK: Built-in DevTools + custom telemetry

### 8.6 Batch API Support

**What**: Submit batch jobs for async processing (50% cost reduction).

**Why Important**:
- Significant cost savings (OpenAI: 50% discount)
- Process large volumes efficiently
- Non-time-sensitive workloads

**Implementation Complexity**: Medium
- File upload API
- Batch creation API
- Status polling
- Result retrieval
- Different batch APIs per provider

**API Design** (proposed):

```lisp
;; Create batch job
(let* ((requests (loop for msg in message-list
                      collect (list :model "gpt-4"
                                   :messages msg)))
       (batch (create-batch-job requests
                               :provider *openai*
                               :completion-window "24h"
                               :metadata '(:job-id "analysis-2026-01"))))
  (format t "Batch created: ~A~%" (batch-id batch)))

;; Check status
(let ((batch (get-batch-status batch-id :provider *openai*)))
  (format t "Status: ~A, Completed: ~D/~D~%"
          (batch-status batch)
          (batch-completed-count batch)
          (batch-total-count batch)))

;; Retrieve results when complete
(when (eq (batch-status batch) :completed)
  (let ((results (get-batch-results batch-id :provider *openai*)))
    (loop for result in results
          do (process-result result))))

;; Async/await style
(let ((batch (await (create-batch-job-async requests :provider *openai*))))
  (await (batch-completion batch))
  (let ((results (await (get-batch-results-async (batch-id batch)))))
    (process-results results)))
```

**Provider Support**:
- OpenAI: Full batch API support (50% discount)
- Anthropic: Message Batches API
- Azure OpenAI: Batch API
- Others: May not support batching

**Reference Implementation**:
- LiteLLM: `acreate_batch()`, `aretrieve_batch()`, `afile_content()`
- Direct provider SDKs

### 8.7 Prompt Caching (Anthropic)

**What**: Cache frequently-used prompt prefixes to reduce cost/latency.

**Why Important**:
- Reduce costs (90% savings on cached portions)
- Reduce latency (faster responses)
- Especially useful for system prompts, tool definitions

**Implementation Complexity**: Low
- Provider-specific (Anthropic only for now)
- Just add cache control markers
- Requires 1024+ tokens minimum

**API Design** (proposed):

```lisp
;; Enable caching for system prompt
(complete messages
  :provider *anthropic*
  :system "Long system prompt..."
  :cache-system-prompt t)  ; Anthropic-specific

;; Cache tool definitions
(complete messages
  :provider *anthropic*
  :tools tool-definitions
  :cache-tools t)  ; Cache the tool definitions

;; Manual cache control via provider options
(complete messages
  :provider *anthropic*
  :provider-options '(:anthropic (:cache-control (:type "ephemeral"))))
```

**Caching Rules** (Anthropic):
- Minimum 1024 tokens for cache to engage
- Cache TTL: 5 minutes (ephemeral)
- Pricing: Cache writes = 25% more, cache reads = 90% less
- Only specific breakpoints can be cached

**Reference Implementation**:
- Vercel AI SDK: `providerOptions: { anthropic: { cacheControl: { type: 'ephemeral' }}}`
- LiteLLM: Native support via provider options

### 8.8 Parallel Tool Calling

**What**: Execute multiple tool calls simultaneously.

**Why Useful**:
- Faster for independent tool calls
- Better resource utilization
- Common pattern: LLM requests multiple tools at once

**Implementation Complexity**: Medium
- Detect parallel tool calls in response
- Execute tools concurrently
- Collect results
- Handle partial failures

**API Design** (proposed):

```lisp
;; Automatic parallel execution
(complete messages
  :provider *openai*
  :tools tool-definitions
  :parallel-tool-execution t)  ; Execute in parallel automatically

;; Manual parallel execution
(let ((response (complete messages :provider *openai* :tools tool-definitions)))
  (when-let ((tool-calls (response-tool-calls response)))
    (let ((results (execute-tools-parallel tool-calls tool-definitions)))
      (complete (append messages
                       (list (response-message response))
                       (mapcar #'make-tool-result-message results))
                :provider *openai*))))

;; With thread pool
(defparameter *tool-thread-pool* (make-thread-pool :size 5))

(execute-tools-parallel tool-calls tool-definitions
                       :thread-pool *tool-thread-pool*)
```

**Considerations**:
- Not all providers support parallel tool calls
- Some tools shouldn't run in parallel (side effects)
- Error handling: partial success/failure
- Thread safety

**Provider Support**:
- OpenAI: `parallel_tool_calls` parameter
- Anthropic: Multiple tool calls supported
- Others: Varies

**Reference Implementation**:
- LiteLLM: `supports_parallel_function_calling(model)`
- Custom: bordeaux-threads, lparallel for parallelism

---

## 9. Recommendations

### Immediate Next Steps (Priority 1)

**1. Implement Streaming Support**
- **Complexity**: High
- **Impact**: Essential for production use
- **Approach**:
  - Start with text streaming (simplest)
  - Use generator/closure pattern for stream chunks
  - Handle per-provider streaming formats (SSE, NDJSON)
  - Add error handling mid-stream
  - Later: Extend to tool call streaming

**2. Add Token Counting Before Calls**
- **Complexity**: Low-Medium
- **Impact**: Essential for cost estimation
- **Approach**:
  - Integrate tiktoken (FFI or pure Lisp port)
  - Add `count-tokens` function
  - Add `estimate-cost` function using model metadata
  - Document accuracy limitations

**3. Add Observability Hooks**
- **Complexity**: Low
- **Impact**: Essential for debugging/monitoring
- **Approach**:
  - Add `:on-request`, `:on-response`, `:on-error` callbacks
  - Capture timing information
  - Document integration patterns for logging frameworks
  - Later: Add integration helpers for Langfuse, etc.

### Production Readiness (Priority 2)

**4. Context Window Overflow Detection**
- **Complexity**: Medium
- **Impact**: Important for reliability
- **Approach**:
  - Use token counting + model metadata
  - Add `context-window-exceeded` condition
  - Implement truncation strategies
  - Provide clear error messages

**5. Retry Logic with Exponential Backoff**
- **Complexity**: Medium
- **Impact**: Important for reliability
- **Approach**:
  - Add `:num-retries` and `:retry-strategy` parameters
  - Implement exponential backoff with jitter
  - Distinguish retriable vs. non-retriable errors
  - Document retry policies

**6. Batch API Support**
- **Complexity**: Medium
- **Impact**: Important for cost optimization
- **Approach**:
  - Start with OpenAI batch API
  - Add async operations (promises or futures)
  - Polling for status updates
  - Result retrieval

### Advanced Features (Priority 3)

**7. Prompt Caching Support**
- **Complexity**: Low
- **Impact**: Important for cost optimization
- **Approach**:
  - Add Anthropic-specific options
  - Add `:cache-system-prompt` and `:cache-tools` parameters
  - Document caching rules and pricing

**8. Parallel Tool Calling**
- **Complexity**: Medium
- **Impact**: Useful for performance
- **Approach**:
  - Add `:parallel-tool-execution` parameter
  - Use bordeaux-threads or lparallel
  - Handle partial failures gracefully
  - Document thread safety requirements

**9. Intelligent Routing**
- **Complexity**: Medium
- **Impact**: Useful for cost optimization
- **Approach**:
  - Add routing DSL for model selection
  - Support cost-based, capability-based routing
  - Fallback chains
  - A/B testing support

### Design Principles

1. **Opt-in Complexity**: Make simple things simple, complex things possible
   - Basic usage: `(complete messages)` just works
   - Advanced features: Optional parameters

2. **Lisp-idiomatic**: Use Lisp's strengths
   - Condition system for error handling
   - Generic functions for extensibility
   - Macros for DSLs (routing, tool definition)
   - CLOS for provider protocols

3. **Provider-Agnostic First**: Abstractions should work everywhere
   - Provider-specific features via `:provider-options`
   - Clear documentation of what's universal vs. provider-specific

4. **Production-Ready**: Not just feature-complete
   - Comprehensive error handling
   - Observability hooks
   - Performance considerations
   - Thread safety

---

## 10. Open Questions

1. **Streaming API Design**: What's the most Lisp-idiomatic way to handle streams?
   - Generator/closure pattern?
   - Gray streams?
   - Async/await style (promises)?
   - Callback-based?

2. **Async Strategy**: How should we handle async operations?
   - Blocking by default, async variants?
   - Futures/promises (lparallel, cl-async)?
   - Callback-based?
   - Event loop (usocket, iolib)?

3. **Tool Execution**: Should we support automatic tool execution?
   - aisuite has `max_turns` for automatic loops
   - Most libraries leave this to application
   - Would a macro help? `(with-tool-execution-loop ...)`

4. **Cost Tracking**: Should we build cost tracking into the library?
   - Track costs per session
   - Budget limits
   - Or leave to application/observability layer?

5. **Configuration Management**: How should users configure providers?
   - Current approach (environment vars + explicit config) is good
   - Should we add config file support? (NOT YAML - Lisp files!)
   - Provider profiles/presets?

6. **Package Structure**: Should advanced features be separate systems?
   - Core: cl-llm-provider (basic completion, tools, tokens)
   - Streaming: cl-llm-provider/streaming
   - Observability: cl-llm-provider/observability
   - Batch: cl-llm-provider/batch

---

## 11. References

### Python Libraries

**LiteLLM**:
- Repository: https://github.com/BerriAI/litellm
- Documentation: https://docs.litellm.ai/
- PyPI: https://pypi.org/project/litellm/

**aisuite**:
- Repository: https://github.com/andrewyng/aisuite
- Announcement: https://www.infoq.com/news/2024/12/aisuite-cross-llm-api/

**Instructor**:
- Website: https://python.useinstructor.com/
- Repository: https://github.com/567-labs/instructor-js (JS version)

### JavaScript/TypeScript Libraries

**Vercel AI SDK**:
- Website: https://ai-sdk.dev/
- Documentation: https://vercel.com/docs/ai-sdk
- AI SDK 6 announcement: https://vercel.com/blog/ai-sdk-6

**multi-llm-ts**:
- Repository: https://github.com/nbonamy/multi-llm-ts
- npm: https://www.npmjs.com/package/multi-llm-ts

**llm-sdk**:
- Repository: https://github.com/hoangvvo/llm-sdk

**LlamaIndex.TS**:
- Documentation: https://developers.llamaindex.ai/typescript/framework/

### Observability Platforms

**Langfuse**:
- Website: https://langfuse.com/
- Documentation: https://langfuse.com/docs/observability/overview
- Open source LLM observability

**Portkey**:
- Blog: https://portkey.ai/blog/the-complete-guide-to-llm-observability/
- Multi-provider routing

**Datadog LLM Observability**:
- Documentation: https://docs.datadoghq.com/llm_observability/
- Product page: https://www.datadoghq.com/product/llm-observability/

### Articles & Guides

- Multi-provider LLM orchestration in production: https://dev.to/ash_dubai/multi-provider-llm-orchestration-in-production-a-2026-guide-1g10
- LLM Pricing Comparison 2026: https://www.cloudidr.com/blog/llm-pricing-comparison-2026
- LLM Observability Tools Comparison: https://lakefs.io/blog/llm-observability-tools/
- Top LLM Observability Platforms: https://www.getmaxim.ai/articles/top-5-llm-observability-platforms-in-2026-2/

---

## 12. Appendix: Feature Comparison Table

| Feature | cl-llm-provider | LiteLLM | Vercel AI SDK | aisuite | Priority |
|---------|----------------|---------|---------------|---------|----------|
| **Core Features** | | | | | |
| Multiple providers | ✅ | ✅ | ✅ | ✅ | Must have |
| Message normalization | ✅ | ✅ | ✅ | ✅ | Must have |
| Tool definition | ✅ | ✅ | ✅ | ✅ | Must have |
| Tool calling | ✅ | ✅ | ✅ | ✅ | Must have |
| Token counting (post) | ✅ | ✅ | ✅ | ✅ | Must have |
| Error handling | ✅ | ✅ | ✅ | ⚠️ | Must have |
| Model metadata | ✅ | ✅ | ⚠️ | ❌ | Must have |
| **Streaming** | | | | | |
| Text streaming | ❌ | ✅ | ✅ | ❌ | **P1** |
| Tool call streaming | ❌ | ✅ | ✅ | ❌ | P3 |
| Object streaming | ❌ | ⚠️ | ✅ | ❌ | P3 |
| Async streaming | ❌ | ✅ | ✅ | ❌ | **P1** |
| **Token & Context** | | | | | |
| Token counting (pre) | ❌ | ✅ | ⚠️ | ❌ | **P1** |
| Cost estimation | ⚠️ | ✅ | ❌ | ❌ | **P1** |
| Context overflow detect | ❌ | ✅ | ⚠️ | ❌ | **P2** |
| Auto truncation | ❌ | ⚠️ | ✅ | ❌ | P2 |
| Prompt caching | ❌ | ✅ | ✅ | ❌ | P3 |
| **Tool Features** | | | | | |
| Tool validation | ✅ | ⚠️ | ✅ | ⚠️ | Must have |
| Safety levels | ✅ | ❌ | ❌ | ❌ | Nice |
| Approval workflow | ✅ | ❌ | ❌ | ❌ | Nice |
| Parallel tools | ❌ | ✅ | ✅ | ❌ | P3 |
| Auto execution | ❌ | ❌ | ✅ | ✅ | P3 |
| Tool hooks | ✅ | ❌ | ✅ | ❌ | Nice |
| **Reliability** | | | | | |
| Retry logic | ⚠️ | ✅ | ❌ | ❌ | **P2** |
| Exponential backoff | ❌ | ✅ | ❌ | ❌ | **P2** |
| Fallback providers | ❌ | ✅ | ❌ | ❌ | P2 |
| Rate limit handling | ✅ | ✅ | ❌ | ❌ | Must have |
| **Observability** | | | | | |
| Callbacks/hooks | ❌ | ✅ | ✅ | ❌ | **P1** |
| Timing info | ✅ | ✅ | ✅ | ❌ | **P1** |
| Tracing integration | ❌ | ✅ | ✅ | ❌ | P2 |
| Cost tracking | ⚠️ | ✅ | ❌ | ❌ | P2 |
| **Advanced** | | | | | |
| Batch API | ❌ | ✅ | ❌ | ❌ | **P2** |
| Structured output | ❌ | ⚠️ | ✅ | ❌ | P3 |
| Multi-modal | ❌ | ✅ | ⚠️ | ❌ | P3 |
| Intelligent routing | ❌ | ✅ | ❌ | ❌ | P3 |

**Legend**:
- ✅ Full support
- ⚠️ Partial support or limited
- ❌ Not supported
- **Bold** = High priority for cl-llm-provider

---

## Summary: Top 10 Missing Features

Based on this comprehensive research, here are the top 10 features we should add to cl-llm-provider, ordered by priority:

1. **Streaming Responses** (P1, High Complexity, Essential) - Table stakes for 2026
2. **Token Counting Before API Calls** (P1, Low Complexity, Essential) - Cost estimation and overflow prevention
3. **Observability Hooks** (P1, Low Complexity, Essential) - Debugging and monitoring
4. **Context Window Overflow Detection** (P2, Medium Complexity, Important) - Prevent errors, better UX
5. **Retry Logic with Exponential Backoff** (P2, Medium Complexity, Important) - Production reliability
6. **Batch API Support** (P2, Medium Complexity, Important) - 50% cost savings
7. **Prompt Caching** (P3, Low Complexity, Important) - 90% cost savings on cached portions
8. **Parallel Tool Calling** (P3, Medium Complexity, Useful) - Performance optimization
9. **Tool Result Streaming** (P3, High Complexity, Useful) - Real-time feedback for long operations
10. **Intelligent Routing** (P3, Medium Complexity, Useful) - Cost and performance optimization

**Implementation Strategy**:
- **Phase 1** (1-3 weeks): Items 1-3 (streaming, token counting, observability)
- **Phase 2** (2-4 weeks): Items 4-6 (context management, retry, batch)
- **Phase 3** (3-6 weeks): Items 7-10 (advanced features)

The research shows that cl-llm-provider has an excellent foundation. Adding these features will make it competitive with the best Python and JavaScript libraries while leveraging Lisp's unique strengths (condition system, macros, CLOS).
