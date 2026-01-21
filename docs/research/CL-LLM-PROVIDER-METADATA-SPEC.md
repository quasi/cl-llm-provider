# cl-llm-provider Metadata and Introspection API Specification

**Version:** 1.0.0
**Author:** Agent-Q Project
**Date:** 2026-01-12
**Status:** Proposed

---

## Executive Summary

This specification proposes a set of generic functions and methods for cl-llm-provider that enable clients to introspect provider configuration, capabilities, and metadata without relying on fragile `typecase` dispatch or maintaining parallel knowledge of provider class hierarchies.

**Core Principle:** The library should expose what it knows about itself through a stable, extensible API.

---

## Motivation

### Current Problems

1. **Provider Type Detection is Fragile**
   ```lisp
   ;; Client code (brittle)
   (typecase provider
     (openai-provider :openai)
     (anthropic-provider :anthropic)
     ...)
   ```
   - Breaks when new providers are added
   - Requires knowledge of class hierarchy
   - Order-dependent (subclass before parent)
   - Package-qualified names are verbose

2. **No Standard Way to Display Configuration**
   - Clients can't reliably show "Using OpenAI gpt-4" without hardcoding logic
   - No human-readable provider names

3. **Capability Discovery is Opaque**
   - Clients don't know if a provider supports tools, embeddings, streaming, etc.
   - Must try operations and catch errors

4. **Model Metadata is Inaccessible**
   - Context window sizes, token costs, capabilities live in docs or client code
   - No programmatic access

### Use Cases

1. **Configuration Display** (Agent-Q)
   - Show "Using OpenAI gpt-4o-mini" in chat UI
   - Store provider/model in session metadata

2. **Capability-Based UI** (general)
   - Enable/disable tool-calling UI based on provider support
   - Show token costs in UIs

3. **Provider Selection** (future)
   - "Show me all providers that support embeddings"
   - "What's the cheapest model with 100k+ context window?"

4. **Error Messages**
   - "Embeddings are not supported by Anthropic" (instead of generic API error)

---

## Specification

### 1. Provider Type Introspection

#### Generic Function: `provider-type`

**Signature:**
```lisp
(provider-type provider) → keyword
```

**Purpose:** Return a stable keyword identifying the provider type.

**Contract:**
- Returns a keyword symbol (`:openai`, `:anthropic`, `:ollama`, `:openrouter`, `:openai-compatible`)
- The keyword is suitable for use in `eql` dispatch, equality tests, and serialization
- The keyword is stable across library versions (part of the public API contract)

**Example Implementation:**
```lisp
(defgeneric provider-type (provider)
  (:documentation "Return provider type as a keyword.
Returns one of: :openai, :anthropic, :ollama, :openrouter, :openai-compatible."))

(defmethod provider-type ((provider openai-provider))
  :openai)

(defmethod provider-type ((provider anthropic-provider))
  :anthropic)

(defmethod provider-type ((provider ollama-provider))
  :ollama)

(defmethod provider-type ((provider openrouter-provider))
  :openrouter)

(defmethod provider-type ((provider openai-compatible-provider))
  :openai-compatible)
```

**Rationale:**
- Encapsulates provider type logic within the library
- Extensible: third-party providers can add methods
- No class hierarchy knowledge required by clients

---

#### Generic Function: `provider-name`

**Signature:**
```lisp
(provider-name provider) → string
```

**Purpose:** Return a human-readable name for the provider.

**Contract:**
- Returns a string suitable for display in UIs
- Capitalized, user-friendly (e.g., "OpenAI", "Anthropic Claude", "Ollama")
- Stable across library versions

**Example Implementation:**
```lisp
(defgeneric provider-name (provider)
  (:documentation "Return human-readable provider name for display."))

(defmethod provider-name ((provider openai-provider))
  "OpenAI")

(defmethod provider-name ((provider anthropic-provider))
  "Anthropic")

(defmethod provider-name ((provider ollama-provider))
  "Ollama")

(defmethod provider-name ((provider openrouter-provider))
  "OpenRouter")

(defmethod provider-name ((provider openai-compatible-provider))
  "OpenAI-Compatible")
```

**Usage Example:**
```lisp
(format nil "Using ~A ~A"
        (provider-name *provider*)
        (provider-default-model *provider*))
;; => "Using OpenAI gpt-4o-mini"
```

---

### 2. Provider Capabilities

#### Generic Function: `provider-capabilities`

**Signature:**
```lisp
(provider-capabilities provider) → plist
```

**Purpose:** Return a plist describing what the provider supports.

**Contract:**
- Returns a plist with boolean flags for supported features
- Keys are keywords: `:tools`, `:embeddings`, `:streaming`, `:vision`, `:function-calling`
- Missing keys are equivalent to `nil` (not supported)
- May be extended with additional keys in future versions

**Example Implementation:**
```lisp
(defgeneric provider-capabilities (provider)
  (:documentation "Return plist of provider capabilities.
Keys: :tools, :embeddings, :streaming, :vision, :function-calling."))

(defmethod provider-capabilities ((provider openai-provider))
  '(:tools t
    :embeddings t
    :streaming t
    :vision t
    :function-calling t))

(defmethod provider-capabilities ((provider anthropic-provider))
  '(:tools t
    :embeddings nil
    :streaming t
    :vision t
    :function-calling t))

(defmethod provider-capabilities ((provider ollama-provider))
  '(:tools t
    :embeddings t
    :streaming t
    :vision nil  ; Model-dependent
    :function-calling t))
```

**Helper Function:**
```lisp
(defun provider-supports-p (provider capability)
  "Check if PROVIDER supports CAPABILITY (keyword).
Example: (provider-supports-p provider :tools)"
  (getf (provider-capabilities provider) capability))
```

**Usage Example:**
```lisp
(if (provider-supports-p provider :embeddings)
    (show-embedding-ui)
    (message "This provider doesn't support embeddings"))
```

---

### 3. Model Metadata (Optional, Phase 2)

#### Generic Function: `model-metadata`

**Signature:**
```lisp
(model-metadata provider model-name) → plist or nil
```

**Purpose:** Return metadata about a specific model.

**Contract:**
- Returns a plist with model information, or `nil` if unknown
- Supported keys:
  - `:context-window` - integer, max tokens (e.g., 128000)
  - `:max-output-tokens` - integer, max completion tokens
  - `:supports-tools` - boolean
  - `:supports-vision` - boolean
  - `:input-cost-per-1m-tokens` - float, USD per 1M input tokens
  - `:output-cost-per-1m-tokens` - float, USD per 1M output tokens
  - `:release-date` - string, ISO date (e.g., "2024-07-18")
  - `:deprecated` - boolean
- Missing keys mean "unknown" (not necessarily unsupported)
- Providers may return `nil` if they don't maintain model metadata

**Example Implementation:**
```lisp
(defgeneric model-metadata (provider model-name)
  (:documentation "Return metadata plist for MODEL-NAME, or NIL if unknown."))

(defmethod model-metadata ((provider openai-provider) model-name)
  (gethash model-name *openai-model-registry*))

(defmethod model-metadata ((provider anthropic-provider) model-name)
  (gethash model-name *anthropic-model-registry*))

;; Default: no metadata available
(defmethod model-metadata ((provider llm-provider) model-name)
  nil)
```

**Model Registry Example:**
```lisp
(defvar *openai-model-registry* (make-hash-table :test 'equal))

(setf (gethash "gpt-4o-mini" *openai-model-registry*)
      '(:context-window 128000
        :max-output-tokens 16384
        :supports-tools t
        :supports-vision t
        :input-cost-per-1m-tokens 0.15
        :output-cost-per-1m-tokens 0.60
        :release-date "2024-07-18"))
```

**Usage Example:**
```lisp
(let ((meta (model-metadata provider "gpt-4o-mini")))
  (when meta
    (format t "Context window: ~D tokens~%Cost: $~,2F/1M in, $~,2F/1M out~%"
            (getf meta :context-window)
            (getf meta :input-cost-per-1m-tokens)
            (getf meta :output-cost-per-1m-tokens))))
```

**Rationale:**
- Centralizes model metadata (currently scattered in docs/clients)
- Enables cost estimation in UIs
- Allows clients to choose models programmatically
- Optional: providers can return `nil` if maintaining registry is burdensome

---

### 4. Response Metadata Enhancements

#### Update `completion-response` slots

**Current:**
```lisp
(response-metadata response) → plist or nil
```

**Proposed Addition:** Standardize common metadata keys:
- `:provider-type` - keyword (result of `provider-type`)
- `:provider-name` - string (result of `provider-name`)
- `:request-id` - string, provider's request ID if available
- `:rate-limit-remaining` - integer, requests remaining (if available)
- `:rate-limit-reset` - universal-time, when rate limit resets

**Example:**
```lisp
(defmethod parse-completion-response ((provider openai-provider) raw-response ...)
  ...
  :metadata (list :provider-type :openai
                  :provider-name "OpenAI"
                  :request-id (gethash "id" raw-response)
                  :rate-limit-remaining (parse-integer
                                          (gethash "x-ratelimit-remaining" headers))
                  ...))
```

**Rationale:**
- Clients can log/display provider info without querying the provider object
- Useful for debugging and monitoring
- Rate limit info enables smarter retry logic

---

### 5. Configuration Summary

#### Generic Function: `provider-config-summary`

**Signature:**
```lisp
(provider-config-summary provider) → plist
```

**Purpose:** Return a summary of provider configuration suitable for display or serialization.

**Contract:**
- Returns a plist with provider configuration
- Keys:
  - `:type` - keyword from `provider-type`
  - `:name` - string from `provider-name`
  - `:model` - string from `provider-default-model` (or `nil`)
  - `:base-url` - string from `provider-base-url` (or `nil`)
  - `:capabilities` - plist from `provider-capabilities`
- Does NOT include sensitive data (API keys)

**Example Implementation:**
```lisp
(defgeneric provider-config-summary (provider)
  (:documentation "Return configuration summary (no sensitive data)."))

(defmethod provider-config-summary (provider)
  (list :type (provider-type provider)
        :name (provider-name provider)
        :model (provider-default-model provider)
        :base-url (provider-base-url provider)
        :capabilities (provider-capabilities provider)))
```

**Usage Example:**
```lisp
;; Display in UI
(let ((config (provider-config-summary *provider*)))
  (format t "~A (~A)~%"
          (getf config :name)
          (getf config :type))
  (format t "Model: ~A~%" (getf config :model))
  (when (provider-supports-p *provider* :tools)
    (format t "Tools: supported~%")))

;; Serialize to session
(list :session-id "..."
      :provider (provider-config-summary *provider*)
      :messages ...)
```

---

## Implementation Plan

### Phase 1: Core Introspection (Required)
- [ ] Add `provider-type` generic function and methods
- [ ] Add `provider-name` generic function and methods
- [ ] Add `provider-capabilities` generic function and methods
- [ ] Add `provider-supports-p` helper function
- [ ] Add `provider-config-summary` generic function and method
- [ ] Update all existing provider classes
- [ ] Add tests for new API
- [ ] Document in README and API docs

### Phase 2: Model Metadata (Optional)
- [ ] Add `model-metadata` generic function and methods
- [ ] Create model registries for OpenAI, Anthropic
- [ ] Populate registries with common models
- [ ] Add tests
- [ ] Document metadata schema

### Phase 3: Response Enhancements (Optional)
- [ ] Standardize response metadata keys
- [ ] Update `parse-completion-response` methods to include standardized metadata
- [ ] Document metadata schema

---

## Backward Compatibility

**All changes are additive:**
- No existing APIs are modified
- Existing code continues to work
- New APIs are opt-in

**Migration Path:**
```lisp
;; Old (still works)
(typecase provider
  (openai-provider :openai)
  ...)

;; New (recommended)
(provider-type provider)
```

---

## Testing Requirements

### Unit Tests
```lisp
(test provider-type
  (let ((provider (make-provider :openai :model "gpt-4")))
    (is (eq :openai (provider-type provider)))))

(test provider-name
  (let ((provider (make-provider :anthropic :model "claude-3")))
    (is (string= "Anthropic" (provider-name provider)))))

(test provider-supports-p
  (let ((provider (make-provider :openai :model "gpt-4")))
    (is-true (provider-supports-p provider :tools))
    (is-true (provider-supports-p provider :embeddings))))

(test provider-capabilities
  (let ((provider (make-provider :anthropic :model "claude-3")))
    (let ((caps (provider-capabilities provider)))
      (is-true (getf caps :tools))
      (is-false (getf caps :embeddings)))))

(test model-metadata
  (let ((provider (make-provider :openai :model "gpt-4o-mini")))
    (let ((meta (model-metadata provider "gpt-4o-mini")))
      (is (= 128000 (getf meta :context-window)))
      (is (numberp (getf meta :input-cost-per-1m-tokens))))))

(test provider-config-summary
  (let ((provider (make-provider :openai :model "gpt-4")))
    (let ((summary (provider-config-summary provider)))
      (is (eq :openai (getf summary :type)))
      (is (string= "OpenAI" (getf summary :name)))
      (is (string= "gpt-4" (getf summary :model)))
      (is (listp (getf summary :capabilities))))))
```

### Integration Tests
- Verify all provider types return correct values
- Test third-party provider extension
- Verify serialization/deserialization of config summaries

---

## Documentation Requirements

### API Documentation
- Docstrings for all new generic functions
- Parameter descriptions
- Return value contracts
- Usage examples

### README Updates
- Add "Provider Introspection" section
- Show examples of capability checking
- Document model metadata schema (if implemented)

### Migration Guide
- Show before/after examples
- Explain when to use new APIs vs. old patterns

---

## Alternative Designs Considered

### Alternative 1: Symbol-based types instead of keywords
```lisp
(provider-type provider) → 'openai-provider
```
**Rejected:** Exposes implementation details (class names), not stable across refactoring

### Alternative 2: String-based types
```lisp
(provider-type provider) → "openai"
```
**Rejected:** Keywords are more idiomatic in Lisp, easier to use in `case` statements

### Alternative 3: Capabilities as separate generic functions
```lisp
(provider-supports-tools-p provider) → boolean
(provider-supports-embeddings-p provider) → boolean
```
**Rejected:** Too many functions, harder to extend, less flexible than plist

### Alternative 4: Provider registry with lookup
```lisp
(provider-info :openai) → plist
```
**Rejected:** Doesn't work for instances, can't be specialized per-instance

---

## Success Criteria

✅ **Clients can determine provider type without typecase**
✅ **Clients can display human-readable provider names**
✅ **Clients can check capabilities before attempting operations**
✅ **All existing code continues to work (backward compatible)**
✅ **Third-party providers can extend the API via standard methods**
✅ **Test coverage ≥ 90% for new APIs**
✅ **Documentation includes examples and migration guide**

---

## Related Issues

- Agent-Q issue: "Provider type shows as UNKNOWN in session metadata"
- General client pain point: Fragile provider type detection
- Future: Model selection UIs need capability/cost information

---

## References

- cl-llm-provider API-SPEC.agent.md
- cl-llm-provider types.lisp (current implementation)
- Agent-Q session management requirements

---

## Appendix A: Complete API Summary

```lisp
;;; Provider Introspection
(provider-type provider) → keyword
(provider-name provider) → string
(provider-capabilities provider) → plist
(provider-supports-p provider capability) → boolean
(provider-config-summary provider) → plist

;;; Model Metadata (Optional)
(model-metadata provider model-name) → plist or nil

;;; Response Metadata (Standardized keys)
(response-metadata response) → plist
;; Keys: :provider-type, :provider-name, :request-id,
;;       :rate-limit-remaining, :rate-limit-reset
```

---

## Appendix B: Example Client Usage (Agent-Q)

**Before:**
```lisp
;; Fragile, breaks on new providers
(defun provider-type-keyword (provider)
  (typecase provider
    (cl-llm-provider:openrouter-provider :openrouter)
    (cl-llm-provider:openai-compatible-provider :openai)
    (cl-llm-provider:openai-provider :openai)
    (cl-llm-provider:anthropic-provider :anthropic)
    (cl-llm-provider:ollama-provider :ollama)
    (t :unknown)))
```

**After:**
```lisp
;; Robust, automatic for new providers
(cl-llm-provider:provider-type provider) → :openai
```

**Session metadata:**
```lisp
;; Before
(list :session-id "..."
      :model "gpt-4o-mini"
      :provider "UNKNOWN"  ; Had to guess
      ...)

;; After
(list :session-id "..."
      :provider-config (cl-llm-provider:provider-config-summary provider)
      ...)
;; => (:type :openai :name "OpenAI" :model "gpt-4o-mini" ...)
```

**UI display:**
```elisp
;; Before (hardcoded)
(format "Using %s %s"
        (upcase provider-keyword)  ; "OPENAI"
        model)

;; After (from library)
(let ((summary (sly-eval '(cl-llm-provider:provider-config-summary *provider*))))
  (format "Using %s %s"
          (plist-get summary :name)   ; "OpenAI"
          (plist-get summary :model)))
```

---

**END OF SPECIFICATION**
