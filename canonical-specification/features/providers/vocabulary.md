# Providers Vocabulary

**Status**: Extracted from docs/agent/core-SPEC.agent.md and src/protocol.lisp
**Confidence**: High
**Last Updated**: 2026-01-16

Feature-specific terms that extend the core vocabulary for the providers subsystem.

---

## Provider Classes

### llm-provider

The abstract base class for all provider implementations.

**Slots**:
- `api-key` - API authentication key (string or nil)
- `base-url` - API endpoint URL (string)
- `default-model` - Default model for requests (string or nil)

**Invariant**: All providers must implement the required protocol methods (RULE-001).

---

### anthropic-provider

Provider implementation for Anthropic's Claude API.

**Provider Type**: `:anthropic`
**Default Base URL**: `https://api.anthropic.com/v1`
**Environment Variable**: `ANTHROPIC_API_KEY`
**Capabilities**: `:tools`, `:streaming`

---

### openai-provider

Provider implementation for OpenAI's API.

**Provider Type**: `:openai`
**Default Base URL**: `https://api.openai.com/v1`
**Environment Variable**: `OPENAI_API_KEY`
**Capabilities**: `:tools`, `:embeddings`, `:streaming`, `:vision`

---

### ollama-provider

Provider implementation for local Ollama models.

**Provider Type**: `:ollama`
**Default Base URL**: `http://localhost:11434`
**Environment Variable**: None (local)
**Capabilities**: `:tools`, `:embeddings`, `:streaming`

---

### openrouter-provider

Provider implementation for OpenRouter gateway.

**Provider Type**: `:openrouter`
**Default Base URL**: `https://openrouter.ai/api/v1`
**Environment Variable**: `OPENROUTER_API_KEY`
**Capabilities**: `:tools`, `:embeddings`, `:streaming`

---

### openai-compatible-provider

Generic provider for OpenAI-compatible APIs (Groq, Together, vLLM, etc.).

**Provider Type**: `:openai-compatible`
**Default Base URL**: User-specified
**Capabilities**: Varies by endpoint

---

### gemini-provider

Provider implementation for Google's Gemini API.

**Provider Type**: `:gemini`
**Default Base URL**: `https://generativelanguage.googleapis.com/v1beta/openai/`
**Environment Variable**: `GEMINI_API_KEY`
**Capabilities**: `:tools`, `:embeddings`, `:streaming`, `:vision`

**Notes**:
- Uses OpenAI-compatible endpoint format
- Supports multimodal input (text, images, audio)
- Function calling compatible with OpenAI format
- Model names: `gemini-3-flash-preview`, `gemini-3-pro-preview`, `gemini-embedding-001`

---

## Protocol Concepts

### Required Method Set

The four methods every provider MUST implement:
1. `send-completion-request`
2. `parse-completion-response`
3. `send-embedding-request`
4. `parse-embedding-response`

Plus introspection methods:
5. `provider-type`
6. `provider-name`
7. `provider-capabilities`

---

### Provider Substitutability

The principle that any provider implementing the protocol can be substituted for another without changing user code.

**Enabled by**:
- Normalized response objects
- Unified message format
- Standard tool translation

---

## Cross-Reference

| Term | Defined In | Relates To |
|------|-----------|------------|
| Provider | core/vocabulary.md | Protocol Method, Capability |
| Protocol Method | core/vocabulary.md | Required Method Set |
| Capability | core/vocabulary.md | Provider Substitutability |
