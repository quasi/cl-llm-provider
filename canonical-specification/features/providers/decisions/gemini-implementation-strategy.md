---
type: decision
name: gemini-implementation-strategy
version: 1.0.0
status: accepted
feature: providers
date: 2026-01-16
implemented: 2026-01-16
outcome: successful
---

# Decision: Gemini Implementation Strategy

## Context

Google's Gemini API needs to be added to cl-llm-provider to expand the set of supported LLM providers. Gemini offers competitive models with strong multimodal capabilities and competitive pricing.

**Key Facts**:
1. Gemini provides an **OpenAI-compatible API endpoint** (`/v1beta/openai/`)
2. Gemini also has a **native API** with different request/response format
3. The library already has a working OpenAI provider implementation
4. Other providers (Anthropic, Ollama, OpenRouter) each have custom implementations

## Decision

**Implement Gemini using the OpenAI-compatible endpoint, with maximum code reuse from the existing OpenAI provider implementation.**

## Options Considered

### Option 1: Implement Native Gemini API ❌

**Approach**: Use Gemini's native `generateContent` API format.

**Pros**:
- Access to all Gemini-specific features
- More direct control over request format
- Potentially better performance

**Cons**:
- Different request/response format requires full implementation
- More code to write and maintain
- Different message format (Content objects vs. OpenAI messages)
- Tool calling format is different
- Increases testing surface area
- No code reuse from existing providers

**Verdict**: Rejected - Too much complexity for little benefit

---

### Option 2: Implement OpenAI-Compatible Endpoint ✅ (CHOSEN)

**Approach**: Use Gemini's OpenAI-compatible endpoint at `https://generativelanguage.googleapis.com/v1beta/openai/`.

**Pros**:
- **Maximum code reuse** - can share most logic with OpenAI provider
- Same request/response format (JSON structure)
- Same tool/function calling format
- Reduced implementation effort (days vs. weeks)
- Smaller test surface area
- Users get familiar API patterns
- Easier to maintain (one format to track)

**Cons**:
- Limited to features available in OpenAI compatibility layer
- Potential latency overhead from translation layer
- Beta endpoint may have stability concerns

**Verdict**: ✅ **Accepted** - Benefits far outweigh drawbacks

---

### Option 3: Support Both Native and Compatible APIs 🤔

**Approach**: Implement both, let users choose via configuration.

**Pros**:
- Best of both worlds
- Users can opt into native API for advanced features
- Fallback to compatible API for simplicity

**Cons**:
- Significantly more code to write (2x implementation)
- More testing needed (2x test surface)
- Configuration complexity
- Maintenance burden doubled
- Risk of feature divergence

**Verdict**: Rejected - Over-engineering for v1. Can revisit later if needed.

---

## Implementation Strategy

### 1. Class Hierarchy

Create `gemini-provider` as a standard `llm-provider` subclass:

```lisp
(defclass gemini-provider (llm-provider)
  ()
  (:documentation "Google Gemini API provider using OpenAI-compatible endpoint"))
```

**No inheritance from `openai-provider`**—keep class hierarchy flat for simplicity.

### 2. Code Reuse Approach

**Share implementation logic via helper functions**, not inheritance:

```lisp
;; Shared helpers (in protocol.lisp or utilities)
(defun make-openai-completion-request (provider messages &key ...)
  "Build OpenAI-compatible completion request body"
  ...)

(defun parse-openai-completion-response (raw-response &key ...)
  "Parse OpenAI-compatible response"
  ...)

;; Use in both providers
(defmethod send-completion-request ((provider openai-provider) messages &key ...)
  (make-openai-completion-request provider messages ...))

(defmethod send-completion-request ((provider gemini-provider) messages &key ...)
  (make-openai-completion-request provider messages ...))
```

**Rationale**: Composition over inheritance. Both providers share helpers but remain independent.

### 3. What to Override

Gemini provider overrides **only provider-specific metadata**:

| Method | Override? | Value |
|--------|-----------|-------|
| `provider-type` | ✅ Yes | `:gemini` |
| `provider-name` | ✅ Yes | `"Google Gemini"` |
| `provider-default-base-url` | ✅ Yes | `"https://generativelanguage.googleapis.com/v1beta/openai/"` |
| `provider-api-key-env-var` | ✅ Yes | `"GEMINI_API_KEY"` |
| `provider-capabilities` | ✅ Yes | `(:tools t :embeddings t :streaming t :vision t)` |
| `model-metadata` | ✅ Yes | Gemini-specific pricing/limits |
| `send-completion-request` | ❌ No | Shared helper |
| `parse-completion-response` | ❌ No | Shared helper |
| `send-embedding-request` | ❌ No | Shared helper |
| `parse-embedding-response` | ❌ No | Shared helper |
| `send-streaming-request` | ❌ No | Shared helper |
| `parse-stream-chunk` | ❌ No | Shared helper |
| `translate-tool-to-provider` | ❌ No | Default OpenAI format |
| `parse-tool-calls` | ❌ No | Default OpenAI parser |

### 4. Model Metadata

Create `*gemini-model-registry*` in `src/model-registry.lisp`:

```lisp
(defparameter *gemini-model-registry*
  (make-model-registry
   :provider :gemini
   :models
   '(("gemini-3-flash-preview"
      :context-window 1048576
      :max-output-tokens 8192
      :supports-tools t
      :supports-vision t
      :input-cost-per-1m-tokens 0.075
      :output-cost-per-1m-tokens 0.30)
     ("gemini-3-pro-preview"
      :context-window 2097152
      :max-output-tokens 8192
      :supports-tools t
      :supports-vision t
      :supports-audio t
      :input-cost-per-1m-tokens 1.25
      :output-cost-per-1m-tokens 5.00)
     ("gemini-embedding-001"
      :output-dimensions 768
      :input-cost-per-1m-tokens 0.0
      :output-cost-per-1m-tokens 0.0))))
```

### 5. File Structure

```
src/
├── providers/
│   ├── openai.lisp          # Existing
│   ├── anthropic.lisp       # Existing
│   ├── gemini.lisp          # NEW - Gemini provider
│   └── ...
├── model-registry.lisp      # Add *gemini-model-registry*
└── protocol.lisp            # Add shared OpenAI helpers (if not already present)
```

### 6. Testing Strategy

**Unit Tests** (`tests/test-gemini-provider.lisp`):
- Provider introspection (type, name, capabilities)
- Base URL and API key configuration
- Request body construction (via shared helpers)
- Response parsing (via shared helpers)
- Error handling

**Integration Tests** (optional, gated by env var):
- Basic completion with real API
- Function calling round-trip
- Streaming response
- Vision input
- Embedding generation

**Mock Tests**:
- Use recorded OpenAI-format responses
- Avoids hitting real API during test runs

## Trade-offs

### ✅ Accepted Trade-offs

1. **Beta Endpoint Risk**: `/v1beta/` may change. Mitigation: Monitor changelog, add version warnings.
2. **Limited to OpenAI Features**: Native API has more features. Mitigation: Most users need standard features only.
3. **Potential Latency**: Translation layer may add overhead. Mitigation: Likely negligible for LLM response times.

### ❌ Rejected Alternatives

1. **Full Native Implementation**: Too much code for marginal benefits
2. **Dual API Support**: Over-engineering for v1, adds maintenance burden

## Success Criteria

- ✅ Gemini provider passes all protocol conformance tests
- ✅ Code reuse > 80% (share helpers with OpenAI)
- ✅ Implementation complete in < 200 lines of code
- ✅ All scenarios in `gemini-provider-usage.md` work
- ✅ Zero breaking changes to existing providers
- ✅ User can switch from OpenAI to Gemini with one line change

## Migration Path (If Native API Needed Later)

If we later need native Gemini API features:

1. Add `gemini-native-provider` class
2. Keep `gemini-provider` as-is (OpenAI-compatible)
3. Let users choose: `:gemini` (compatible) vs. `:gemini-native`
4. Document trade-offs in user guide

This preserves backward compatibility.

## Dependencies

- Existing OpenAI provider implementation (for shared logic)
- HTTP client (dexador) - already present
- JSON parser (yason) - already present
- No new dependencies required

## Timeline Estimate

- **Specification**: 1 day (✅ complete)
- **Implementation**: 2-3 days
  - Day 1: Core provider (completion, embedding)
  - Day 2: Streaming, model registry, error handling
  - Day 3: Testing, documentation
- **Integration**: 1 day
  - Update README with Gemini examples
  - Add to supported providers table
  - Update API reference

**Total**: ~4-5 days

## Risks and Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Beta endpoint changes format | Medium | High | Monitor changelog, add tests, version warnings |
| Missing features in compatible API | Low | Medium | Document limitations, provide workarounds |
| Authentication differences | Low | High | Test thoroughly, good error messages |
| Rate limits more restrictive | Medium | Low | Document limits, good error handling |

## Approval

**Status**: Draft - Pending review

**Stakeholders**:
- Implementation team
- Users (via documentation)

**Next Steps**:
1. Review this decision with team
2. Implement per strategy above
3. Test against specification scenarios
4. Update user documentation
5. Deploy as part of v0.2.0

## Related Artifacts

- [gemini-api.md](../contracts/gemini-api.md) - API contract
- [gemini-provider-usage.md](../scenarios/gemini-provider-usage.md) - Usage scenarios
- [vocabulary.md](../vocabulary.md) - Provider vocabulary

## Revision History

- **2026-01-16**: Initial decision - OpenAI-compatible endpoint chosen
