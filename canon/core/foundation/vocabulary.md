# Core Vocabulary

**Status**: Extracted from docs/agent/core-SPEC.agent.md and docs/agent/metadata-API-SPEC.agent.md
**Confidence**: High (formal specifications, verified against code)
**Last Updated**: 2026-01-16

This file defines the fundamental terms used throughout the cl-llm-provider system. All terms are sourced from formal agent specifications and verified against implementation.

---

## Provider Domain

### Provider

An instance of an `llm-provider` subclass representing an API connection to an LLM service.

**Invariants**:
- Every provider has a `provider-type` (keyword) and `provider-name` (string)
- Provider instances are thread-safe for concurrent requests
- Provider configuration is immutable after creation

**Relationships**:
- Providers implement the **Protocol Methods**
- Providers have associated **Capabilities**
- Providers may have a default **Model**

**Code Location**: `src/protocol.lisp`, `src/providers/`

---

### Provider Type

A keyword uniquely identifying a provider class: `:openai`, `:anthropic`, `:ollama`, `:openrouter`, `:openai-compatible`.

**Invariants**:
- Provider type is stable across provider instances (same class → same keyword)
- Provider type is `eql`-comparable

**Semantic Boundaries**: This is a keyword, not a string. Use `provider-name` for display strings.

---

### Capability

A boolean feature flag indicating provider support: `:tools`, `:embeddings`, `:streaming`, `:vision`, `:function-calling`.

**Invariants**:
- Capabilities are queryable via `provider-supports-p`
- `provider-capabilities` returns a plist with keyword keys and boolean values

---

## Request/Response Domain

### Completion

A text generation request/response cycle via the `complete` function.

**Relationships**:
- A completion takes **Messages** as input
- A completion produces a **Response Object** (`completion-response`)
- A completion may use **Tools**

**Code Location**: `src/api.lisp:complete`

---

### Embedding

A vector representation request/response cycle via the `embedding` function.

**Relationships**:
- An embedding takes text input
- An embedding produces a **Response Object** (`embedding-response`)

**Code Location**: `src/api.lisp:embedding`

---

### Response Object

An instance of `completion-response` or `embedding-response` containing the result of an API call.

**Invariants**:
- Response objects are **immutable** after creation (RULE-004)
- Response objects preserve the **Raw Response** from the provider
- Response objects contain **Usage** information

**Code Location**: `src/types.lisp`

---

### Raw Response

The provider's original HTTP response body, preserved as a hash-table.

**Invariants**:
- INV-001: `(response-raw response)` always returns a hash-table
- Raw response is never modified after parsing

**Purpose**: Enables access to provider-specific fields not normalized into standard slots.

---

### Usage

A token count plist with keys `:prompt-tokens`, `:completion-tokens`, `:total-tokens`.

**Invariants**:
- INV-002: All token counts are non-negative integers
- Total tokens equals prompt + completion tokens

---

### Finish Reason

A keyword indicating why generation stopped: `:stop`, `:length`, `:tool-calls`, `:content-filter`.

**Invariants**:
- RULE-015: `parse-completion-response` normalizes finish reasons to these keywords
- If finish-reason is `:tool-calls`, then `response-tool-calls` is non-nil

---

## Message Domain

### Message

A plist representing a single conversation turn with keys:
- `:role` - Required: `"user"`, `"assistant"`, `"system"`, or `"tool"`
- `:content` - Required for user/system, optional for assistant with tool-calls
- `:tool-calls` - Optional: list of tool-call objects (assistant only)
- `:tool-call-id` - Required for tool role messages

**Invariants**:
- INV-004: Role is one of the four valid values
- RULE-002: Invalid roles cause API errors
- RULE-013: User/assistant messages must have non-empty content OR tool-calls

**Code Location**: Message handling in `src/api.lisp`

---

### Message History

An ordered list of messages forming conversation context.

**Invariants**:
- RULE-006: Messages must be ordered chronologically (oldest first)
- Providers reject misordered messages

---

## Tool Domain

### Tool Definition

A specification of a callable function containing:
- `name` - String matching `^[a-zA-Z0-9_-]+$` (RULE-003)
- `description` - Human-readable purpose
- `parameters` - List of parameter specs with `:name`, `:type`, `:description`
- `handler` - Optional function for execution

**Invariants**:
- INV-007: Tool definitions are immutable after registration
- RULE-011: Parameter types must be `:string`, `:integer`, `:number`, `:boolean`, `:array`, `:object`

**Code Location**: `src/tools.lisp`, `src/tools/`

---

### Tool Call

An LLM's request to invoke a specific tool with arguments.

**Components**:
- `id` - Unique identifier for correlation
- `name` - Tool to invoke
- `arguments` - Plist or hash-table of argument values

**Invariants**:
- INV-003: Tool call IDs are unique within a response
- RULE-007: `make-tool-result` must use exact ID from tool-call

---

### Tool Result

A message with role `"tool"` containing tool execution output.

**Required Fields**:
- `:role "tool"`
- `:tool-call-id` - Must match the originating tool-call ID
- `:content` - Serialized result (string)

---

### Safety Level

Tool classification for approval workflows: `:safe`, `:moderate`, `:dangerous`.

**Purpose**: Enables approval gates before tool execution.

**Code Location**: `src/tools/`

---

## Protocol Domain

### Protocol Method

A generic function specialized per provider type.

**Required Methods** (RULE-001):
- `send-completion-request`
- `parse-completion-response`
- `send-embedding-request`
- `parse-embedding-response`

**Streaming Methods**:
- `send-streaming-request`
- `parse-stream-chunk`
- `read-stream-chunk`

**Invariant**: RULE-012 - Protocol methods should have no side effects beyond HTTP requests, profiling, and condition signaling.

**Code Location**: `src/protocol.lisp`

---

### Normalization

The process of converting provider-specific response formats into the unified representation.

**Examples**:
- OpenAI's `finish_reason: "stop"` → `:stop`
- Anthropic's `stop_reason: "end_turn"` → `:stop`
- Different tool-call JSON formats → unified `tool-call` objects

---

## Metadata Domain

### Model Metadata

A plist containing context window size, pricing, and capability data for a specific model.

**Keys**:
- `:context-window` - Integer, maximum tokens
- `:input-cost-per-1m-tokens` - Float, cost in dollars
- `:output-cost-per-1m-tokens` - Float, cost in dollars
- `:capabilities` - Plist of model-specific capabilities

**Invariants**:
- RULE-005 (metadata): Returns NIL for unknown models

**Code Location**: `src/model-registry.lisp`

---

### Registry

A hash table mapping model names (strings) to metadata plists.

**Purpose**: Enables model lookup without API calls.

**Code Location**: `src/model-registry.lisp`

---

### Introspection

Querying provider properties without invoking API calls.

**Functions**:
- `provider-type` - Get provider keyword
- `provider-name` - Get display name
- `provider-capabilities` - Get capability plist
- `provider-supports-p` - Check specific capability
- `model-metadata` - Get model information

---

## Observability Domain

### Performance Profiling

Timing collection for encode/API/decode phases, enabled via `*performance-profiling*`.

**Invariants**:
- INV-006: When enabled, stats contain exactly `:encode-time`, `:api-time`, `:decode-time`
- RULE-009: Stats must only be modified via `with-performance-timing` macro

**Code Location**: `src/observability.lisp`

---

### Response Metadata

A plist in response objects containing provider context and request tracking data.

**Contents vary by provider but may include**:
- Timing information
- Request fingerprints
- Stop sequences used
- System fingerprints

---

## Cross-Reference

| Term | Primary Location | Related Terms |
|------|------------------|---------------|
| Provider | src/protocol.lisp | Protocol Method, Capability |
| Completion | src/api.lisp | Message, Response Object, Tools |
| Message | src/api.lisp | Message History, Role |
| Tool Definition | src/tools.lisp | Tool Call, Tool Result, Safety Level |
| Response Object | src/types.lisp | Raw Response, Usage, Finish Reason |
