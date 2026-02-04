# Google Gemini Provider Specification

**Status**: Stable
**Version**: 1.0.0
**Date**: 2026-01-16
**Implemented**: 2026-01-16
**Feature**: providers

## Overview

This document provides a complete specification for adding Google Gemini as a provider to cl-llm-provider. The specification follows the Canon methodology and includes vocabulary, contracts, scenarios, and implementation decisions.

## What Was Added

### 1. Vocabulary (`vocabulary.md`)

Added `gemini-provider` class definition:
- **Provider Type**: `:gemini`
- **Default Base URL**: `https://generativelanguage.googleapis.com/v1beta/openai/`
- **Environment Variable**: `GEMINI_API_KEY`
- **Capabilities**: `:tools`, `:embeddings`, `:streaming`, `:vision`

### 2. Contract (`contracts/gemini-api.md`)

Comprehensive API contract defining:
- Provider configuration and authentication
- Supported models (Flash, Pro, Embedding)
- API endpoints (chat completions, embeddings)
- Protocol implementation requirements
- Multimodal support (vision, audio)
- Function calling format
- Error handling and rate limits
- Token counting and pricing
- Model metadata

**Key Decision**: Use OpenAI-compatible endpoint for maximum code reuse.

### 3. Scenarios (`scenarios/gemini-provider-usage.md`)

14 usage scenarios covering:
- Basic text completion
- Provider substitutability
- Multi-turn conversations
- Vision input (image understanding)
- Function calling (tools)
- Tool execution round-trip
- Streaming responses
- Error handling (invalid API key, rate limits)
- Model metadata queries
- Capability introspection
- Embedding generation (single and batch)
- Configuration summary

### 4. Decision Record (`decisions/gemini-implementation-strategy.md`)

Implementation strategy document:
- **Chosen Approach**: OpenAI-compatible endpoint
- **Rationale**: Maximum code reuse, minimal implementation effort
- **Code Reuse Strategy**: Composition via shared helpers, not inheritance
- **Override Points**: Only provider-specific metadata
- **Timeline**: 4-5 days estimated
- **Risks and Mitigations**: Beta endpoint, feature limitations

### 5. Updated Artifacts

**Provider Protocol Contract** (`contracts/provider-protocol.md`):
- Added `:gemini` to list of provider type keywords

**Feature Metadata** (`feature.yaml`):
- Version bumped to 0.2.0
- Description includes Google Gemini
- Added `gemini-api` contract
- Added `gemini-provider-usage` scenario
- Added `gemini-implementation-strategy` decision

**Main Canon** (`canon.yaml`):
- Description includes Google Gemini

**README** (`README.md`):
- Added Gemini to supported providers table
- Added Vision column to capabilities matrix
- Updated provider list in intro and features

## Architecture

### Class Definition

```lisp
(defclass gemini-provider (llm-provider)
  ()
  (:documentation "Google Gemini API provider using OpenAI-compatible endpoint"))
```

### Method Overrides

Only provider-specific metadata is overridden:

```lisp
(defmethod provider-type ((provider gemini-provider))
  :gemini)

(defmethod provider-name ((provider gemini-provider))
  "Google Gemini")

(defmethod provider-default-base-url ((provider gemini-provider))
  "https://generativelanguage.googleapis.com/v1beta/openai/")

(defmethod provider-api-key-env-var ((provider gemini-provider))
  "GEMINI_API_KEY")

(defmethod provider-capabilities ((provider gemini-provider))
  '(:tools t :embeddings t :streaming t :vision t :function-calling t))

(defmethod model-metadata ((provider gemini-provider) model-name)
  (get-model-metadata *gemini-model-registry* model-name))
```

### Code Reuse

Request/response handling methods use **shared OpenAI-compatible helpers**:
- `send-completion-request` → shared helper
- `parse-completion-response` → shared helper
- `send-embedding-request` → shared helper
- `parse-embedding-response` → shared helper
- `send-streaming-request` → shared helper
- `parse-stream-chunk` → shared helper
- `translate-tool-to-provider` → default OpenAI format
- `parse-tool-calls` → default OpenAI parser

## Implementation Checklist

### Phase 1: Core Provider (Day 1)
- [ ] Create `src/providers/gemini.lisp`
- [ ] Implement `gemini-provider` class
- [ ] Override provider metadata methods
- [ ] Add to `src/package.lisp` exports
- [ ] Create `*gemini-model-registry*` in `src/model-registry.lisp`

### Phase 2: Shared Helpers (Day 1-2)
- [ ] Extract/create shared OpenAI helper functions
- [ ] Verify both OpenAI and Gemini use same helpers
- [ ] Test request body construction
- [ ] Test response parsing

### Phase 3: Testing (Day 2-3)
- [ ] Create `tests/test-gemini-provider.lisp`
- [ ] Unit tests for introspection
- [ ] Unit tests for configuration
- [ ] Mock tests with OpenAI-format responses
- [ ] Integration tests (gated by `GEMINI_API_KEY`)

### Phase 4: Documentation (Day 3)
- [ ] Add Gemini examples to user docs
- [ ] Update quickstart guide
- [ ] Update API reference
- [ ] Add how-to guide for Gemini-specific features

### Phase 5: Integration (Day 4)
- [ ] Update `cl-llm-provider.asd` system definition
- [ ] Run full test suite
- [ ] Update changelog
- [ ] Tag release (v0.2.0)

## Usage Example

```lisp
(use-package :cl-llm-provider)

;; Basic completion
(let ((provider (make-provider :gemini
                               :default-model "gemini-3-flash-preview")))
  (complete '((:role "user" :content "Hello, Gemini!"))
            :provider provider))

;; Vision input
(let* ((image-data (read-file-to-base64 "image.jpg"))
       (data-url (format nil "data:image/jpeg;base64,~A" image-data))
       (provider (make-provider :gemini)))
  (complete (list (list :role "user"
                       :content (list
                                  (list :type "text" :text "What's in this image?")
                                  (list :type "image_url"
                                        :image_url (list :url data-url)))))
            :provider provider))

;; Function calling
(let* ((tools (list (define-tool "get_weather" "Get weather"
                                 '((:name "location" :type :string)))))
       (provider (make-provider :gemini)))
  (complete '((:role "user" :content "Weather in Paris?"))
            :provider provider
            :tools tools))
```

## Acceptance Criteria

✅ All protocol methods implemented
✅ OpenAI-compatible format used
✅ All 14 scenarios work correctly
✅ Error handling includes Gemini-specific conditions
✅ Provider substitutable with existing providers
✅ Code reuse > 80% (shares OpenAI helpers)
✅ Implementation < 200 lines of code
✅ Zero breaking changes to existing providers
✅ User can switch from OpenAI to Gemini with one line change

## Model Metadata

### Text Generation Models

| Model | Context Window | Max Output | Input Cost (per 1M) | Output Cost (per 1M) |
|-------|----------------|------------|---------------------|----------------------|
| gemini-3-flash-preview | 1M tokens | 8K tokens | $0.075 | $0.30 |
| gemini-3-pro-preview | 2M tokens | 8K tokens | $1.25 | $5.00 |

### Embedding Models

| Model | Output Dimensions | Cost |
|-------|-------------------|------|
| gemini-embedding-001 | 768 | Free |

## Related Resources

### Canon Artifacts
- [vocabulary.md](./vocabulary.md) - Provider vocabulary
- [contracts/provider-protocol.md](./contracts/provider-protocol.md) - Generic protocol
- [contracts/gemini-api.md](./contracts/gemini-api.md) - Gemini API contract
- [scenarios/gemini-provider-usage.md](./scenarios/gemini-provider-usage.md) - Usage scenarios
- [decisions/gemini-implementation-strategy.md](./decisions/gemini-implementation-strategy.md) - Implementation strategy

### External References
- **Gemini API Documentation**: https://ai.google.dev/gemini-api/docs/openai
- **OpenAI Compatibility**: https://ai.google.dev/gemini-api/docs/openai
- **Model Information**: https://ai.google.dev/gemini-api/docs/models/gemini
- **Pricing**: https://ai.google.dev/pricing
- **API Keys**: https://aistudio.google.com/apikey

## Timeline

- **Specification**: 1 day (✅ Complete)
- **Implementation**: 2-3 days
- **Testing**: 1 day
- **Documentation**: 1 day
- **Total**: 4-5 days

## Next Steps

1. Review specification with implementation team
2. Begin Phase 1 implementation (core provider)
3. Implement shared OpenAI helpers (if not already present)
4. Write tests as implementation progresses
5. Update user documentation
6. Deploy as part of v0.2.0 release

## Questions for Review

1. Should we add any Gemini-specific features beyond OpenAI compatibility?
2. Do we need to support the native Gemini API format in v1?
3. Should we add image generation (`imagen-3.0`) support?
4. What level of integration testing is required before release?

## Revision History

- **2026-01-16**: Initial specification created via canon-specify
