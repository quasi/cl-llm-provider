---
type: specification
version: 1.0.0
applies-to: [cl-llm-provider]
requires: [API-SPEC.agent.md]
---

# Metadata and Introspection API Specification

**Scope**: Provider introspection, model metadata, response metadata enhancement for cl-llm-provider.

**Purpose**: Enable clients to query provider capabilities, model metadata, and response context without fragile `typecase` dispatch or runtime trial-and-error.

---

## Terminology

- **provider**: Instance of a class inheriting from `llm-provider` (e.g., `openai-provider`, `anthropic-provider`)
- **provider-type**: Keyword uniquely identifying provider class (`:openai`, `:anthropic`, `:ollama`, `:openrouter`, `:openai-compatible`)
- **capability**: Boolean feature flag indicating provider support (`:tools`, `:embeddings`, `:streaming`, `:vision`, `:function-calling`)
- **model-metadata**: Plist containing context window, pricing, and capability data for specific model
- **response-metadata**: Plist in response object containing provider context and request tracking data
- **registry**: Hash table mapping model names (strings) to metadata plists
- **introspection**: Querying provider properties without invoking API calls

---

## Normative Rules

### RULE-001: Provider Type Stability

**Rule**: `provider-type` MUST return stable keyword across provider instances.

**Applies to**: All provider classes.

**Rationale**: Keywords are eql-comparable, enabling efficient dispatch and case statements.

**Violation consequence**: Client code using `case` or `eql` specializers breaks.

**Agent action**: Flag. Verify return value is keyword, not string or symbol from different package.

### RULE-002: Provider Name Is String

**Rule**: `provider-name` MUST return string, not keyword or symbol.

**Applies to**: All provider classes.

**Rationale**: Strings are suitable for display and concatenation without format conversion.

**Violation consequence**: Runtime type error when concatenating for display.

**Agent action**: Auto-fix allowed (wrap return value with `(format nil "~A" ...)`).

### RULE-003: Capabilities Are Plist

**Rule**: `provider-capabilities` MUST return plist with keyword keys and boolean (T/NIL) values.

**Applies to**: All provider classes.

**Rationale**: Plist enables `getf` lookups without hash table overhead. Boolean values enable direct conditional use.

**Violation consequence**: `provider-supports-p` returns incorrect results.

**Agent action**: Flag. Verify structure: `(and (listp result) (keywordp (first result)))`.

### RULE-004: No API Keys In Config Summary

**Rule**: `provider-config-summary` MUST NOT include `:api-key` or any sensitive credentials.

**Applies to**: All implementations of `provider-config-summary`.

**Rationale**: Config summaries may be logged, serialized, or displayed. Credential leakage violates security.

**Violation consequence**: API key exposure in logs or UI.

**Agent action**: Flag violation. Auto-fix forbidden (requires human security review).

### RULE-005: Model Metadata NIL For Unknown Models

**Rule**: `model-metadata` MUST return NIL for models not in registry.

**Applies to**: All implementations of `model-metadata`.

**Rationale**: NIL is distinguishable from empty plist and signals "unknown" explicitly.

**Violation consequence**: Client cannot distinguish "no metadata" from "model exists but has no properties".

**Agent action**: Auto-fix allowed (add `(or (gethash ...) nil)` guard).

### RULE-006: Model Registry Keys Are Strings

**Rule**: Model registries MUST use `(make-hash-table :test 'equal)` and string keys.

**Applies to**: `*openai-model-registry*`, `*anthropic-model-registry*`, custom registries.

**Rationale**: Model names from API responses are strings. Using `'eq` or `'eql` test breaks lookups.

**Violation consequence**: `model-metadata` always returns NIL despite registered models.

**Agent action**: Flag. Verify hash table test is `'equal` at creation time.

### RULE-007: Response Metadata Always Includes Provider Type

**Rule**: `parse-completion-response` and `parse-embedding-response` MUST set `:provider-type` in metadata plist.

**Applies to**: All provider implementations of response parsing methods.

**Rationale**: Response objects must be traceable to provider for debugging and dispatch.

**Violation consequence**: Cannot determine provider from response object alone.

**Agent action**: Auto-fix allowed (add `(setf (getf metadata :provider-type) (provider-type provider))`).

### RULE-008: Provider Capabilities Are Static

**Rule**: `provider-capabilities` MUST return same plist for all instances of same provider class.

**Applies to**: All provider implementations.

**Rationale**: Capabilities are class properties, not instance properties. Variation breaks caching and optimization.

**Violation consequence**: Inconsistent behavior across instances.

**Agent action**: Flag if implementation accesses instance slots (should be literal plist or class variable).

### RULE-009: Registry Modification Is Thread-Safe

**Rule**: `register-model-metadata` MAY be called from multiple threads. No corruption permitted.

**Applies to**: `register-model-metadata` function.

**Rationale**: Common Lisp hash tables are not inherently thread-safe for mutation.

**Violation consequence**: Registry corruption under concurrent modification.

**Agent action**: Flag for human review. Auto-fix: Add lock or document single-threaded requirement.

### RULE-010: Provider-Supports-P Returns Boolean

**Rule**: `provider-supports-p` MUST return T or NIL, never other truthy values.

**Applies to**: `provider-supports-p` function implementation.

**Rationale**: Callers expect boolean for conditional logic. Non-NIL values like strings or numbers are truthy but semantically incorrect.

**Violation consequence**: Confusing return values in conditional checks.

**Agent action**: Auto-fix allowed (wrap with `(if ... t nil)`).

---

## Invariants

### INV-001: Provider Type Is Unique Per Class

`∀ provider-class: (= (length (remove-duplicates (mapcar #'provider-type instances) :test #'eq)) 1)`

**Check**: All instances of same provider class return identical keyword.

### INV-002: Capability Keys Are Superset

`∀ provider: (subset '(:tools :embeddings :streaming :vision :function-calling) (plist-keys (provider-capabilities provider)))`

**Check**: All capability plists include standard keys (may have additional keys).

### INV-003: Config Summary Is Serializable

`∀ provider: (stringp (format nil "~S" (provider-config-summary provider)))`

**Check**: Config summary can be written to string without error.

### INV-004: Model Metadata Values Are Plists Or NIL

`∀ registry model: (or (null (model-metadata registry model)) (listp (model-metadata registry model)))`

**Check**: Metadata lookup never returns hash table, array, or other non-plist structure.

### INV-005: Response Metadata Contains Provider Name

`∀ response: (stringp (getf (response-metadata response) :provider-name))`

**Check**: After Phase 3 implementation, all responses include string provider name.

---

## Patterns

### PATTERN-001: Provider Identification

**Scenario**: Client needs to determine provider type without inspecting class name.

**Complete Example**:

```lisp
;; File: src/client-code.lisp

(defun log-completion-request (provider messages)
  "Log which provider is handling request."
  ;; Use provider-type for stable dispatch - returns keyword for eql comparison
  (format t "[~A] Sending completion: ~{~A~^, ~}~%"
          (provider-type provider)  ; :openai, :anthropic, etc.
          (mapcar (lambda (msg) (getf msg :role)) messages)))

;; Dispatch based on provider type
(defun estimate-cost (provider model tokens)
  "Estimate cost based on provider and model."
  (case (provider-type provider)  ; Keywords work in case statements
    (:openai (openai-cost-estimate model tokens))
    (:anthropic (anthropic-cost-estimate model tokens))
    ((:ollama :openai-compatible) 0.0)  ; Local providers are free
    (t (warn "Unknown provider type: ~A" (provider-type provider))
       nil)))
```

**Rules Satisfied**: R001 (stable keywords), R002 (string names)

**Why This Shape**:
- `provider-type` returns keyword (not string) for efficient `case` dispatch
- Keywords are interned, so `eq` comparison is fast
- Fallback case handles unknown providers gracefully

**Anti-pattern**:

```lisp
;; DON'T do this
(cond
  ((typep provider 'openai-provider) ...)  ; Fragile - breaks on subclasses
  ((string= (type-of provider) "OPENAI-PROVIDER") ...))  ; Wrong - string comparison
```

---

### PATTERN-002: Capability Checking

**Scenario**: Before using feature (tools, embeddings), verify provider supports it.

**Complete Example**:

```lisp
;; File: src/client-code.lisp

(defun complete-with-tools-if-supported (provider messages tools)
  "Use tools only if provider supports them."
  (if (provider-supports-p provider :tools)  ; Boolean check - returns T or NIL
      (progn
        (format t "~A supports tools, enabling~%" (provider-name provider))
        (complete messages :provider provider :tools tools))
      (progn
        (warn "~A does not support tools, falling back to plain completion"
              (provider-name provider))
        (complete messages :provider provider))))

;; Check multiple capabilities
(defun validate-provider-for-task (provider)
  "Ensure provider meets task requirements."
  (let ((caps (provider-capabilities provider)))  ; Get full plist once
    (unless (getf caps :tools)
      (error "Provider must support tools"))
    (unless (getf caps :vision)
      (error "Provider must support vision"))
    ;; All checks passed
    t))
```

**Rules Satisfied**: R003 (plist structure), R010 (boolean return)

**Why This Shape**:
- `provider-supports-p` wraps `getf` lookup, ensuring boolean result
- Calling `provider-capabilities` once and reusing plist is efficient for multiple checks
- T/NIL returns enable direct conditional use

**Variations**:

| Scenario | Modification |
|----------|--------------|
| Require multiple capabilities | Call `provider-supports-p` for each, combine with `and` |
| Prefer capability but allow fallback | Use `if` instead of `unless` |

**Anti-pattern**:

```lisp
;; DON'T do this
(when (getf (provider-capabilities provider) :tools)  ; Works but less clear intent
  ...)

(if (provider-supports-p provider :tools)
    ...
    nil)  ; Returning NIL explicitly is redundant - provider-supports-p already returns boolean
```

---

### PATTERN-003: Display-Friendly Provider Info

**Scenario**: Show provider information to user in logs, UI, or error messages.

**Complete Example**:

```lisp
;; File: src/logging.lisp

(defun format-provider-info (provider)
  "Format provider info for display."
  ;; provider-name returns string - suitable for concatenation
  (format nil "~A (~A) using model ~A"
          (provider-name provider)        ; "OpenAI", "Anthropic", etc.
          (provider-type provider)        ; :openai, :anthropic, etc.
          (provider-default-model provider)))

;; Example output: "OpenAI (:openai) using model gpt-4o"

(defun log-provider-status (provider)
  "Log provider configuration summary."
  (let ((summary (provider-config-summary provider)))
    ;; Summary is serializable plist - safe for logging
    (format t "Provider config: ~{~A: ~S~^, ~}~%"
            summary)
    ;; No API key present - safe for logs
    (assert (null (getf summary :api-key)))))
```

**Rules Satisfied**: R002 (string names), R004 (no API keys)

**Why This Shape**:
- `provider-name` returns string, no conversion needed
- `provider-type` returns keyword, formats as `:keyword` symbol
- Config summary excludes sensitive data by design

**Anti-pattern**:

```lisp
;; DON'T do this
(format nil "~A" (type-of provider))  ; Prints class name "OPENAI-PROVIDER", not "OpenAI"
(format t "API Key: ~A" (provider-api-key provider))  ; Security violation - leaks credentials
```

---

### PATTERN-004: Model Metadata Lookup

**Scenario**: Query model context window, pricing, or capabilities before sending request.

**Complete Example**:

```lisp
;; File: src/cost-estimation.lisp

(defun check-context-limit (provider model messages)
  "Verify messages fit within model's context window."
  (let ((meta (model-metadata provider model)))
    (if meta
        (let ((ctx-window (getf meta :context-window))
              (estimated-tokens (estimate-message-tokens messages)))
          (if (> estimated-tokens ctx-window)
              (error "Messages (~D tokens) exceed ~A context window (~D)"
                     estimated-tokens model ctx-window)
              (format t "Messages fit in context (~D/~D tokens)~%"
                      estimated-tokens ctx-window)))
        ;; NIL means model not in registry - proceed cautiously
        (warn "No metadata for model ~A, cannot verify context limit" model))))

(defun estimate-completion-cost (provider model input-tokens output-tokens)
  "Calculate estimated cost based on model metadata."
  (let ((meta (model-metadata provider model)))
    (if meta
        (let ((input-cost (getf meta :input-cost-per-1m-tokens))
              (output-cost (getf meta :output-cost-per-1m-tokens)))
          ;; Costs are in USD per 1M tokens
          (+ (* input-tokens (/ input-cost 1000000.0))
             (* output-tokens (/ output-cost 1000000.0))))
        ;; Unknown model - return NIL to signal uncertainty
        nil)))
```

**Rules Satisfied**: R005 (NIL for unknown), R006 (string keys)

**Why This Shape**:
- NIL return explicitly signals "model not in registry"
- Clients must check for NIL before accessing plist properties
- Metadata lookup does not throw errors (enables graceful degradation)

**Variations**:

| Scenario | Modification |
|----------|--------------|
| Require metadata | `(or (model-metadata ...) (error "Unknown model"))` |
| Provide defaults | `(or (getf meta :context-window) 8192)` |

**Anti-pattern**:

```lisp
;; DON'T do this
(getf (model-metadata provider model) :context-window)  ; Fails if model-metadata returns NIL
(let ((meta (model-metadata provider model)))
  (getf meta :context-window 8192))  ; Default in getf works, but NIL check is clearer
```

---

### PATTERN-005: Custom Model Registration

**Scenario**: Register metadata for local model, custom endpoint, or newly-released model.

**Complete Example**:

```lisp
;; File: src/custom-setup.lisp

(defun setup-custom-models ()
  "Register metadata for custom models."
  ;; Create registry for custom provider or reuse existing
  (let ((custom-registry (make-hash-table :test 'equal)))  ; MUST use 'equal for string keys

    ;; Register local Ollama model
    (register-model-metadata custom-registry "llama3:70b-instruct"
      '(:context-window 8192
        :max-output-tokens 4096
        :supports-tools t
        :supports-vision nil
        :input-cost-per-1m-tokens 0.0   ; Local model - free
        :output-cost-per-1m-tokens 0.0))

    ;; Register custom fine-tuned model
    (register-model-metadata custom-registry "gpt-4-company-finetune"
      '(:context-window 128000
        :max-output-tokens 16384
        :supports-tools t
        :supports-vision t
        :input-cost-per-1m-tokens 30.00   ; Higher cost for fine-tuned
        :output-cost-per-1m-tokens 60.00))

    ;; Store registry globally or associate with provider
    (setf *custom-model-registry* custom-registry)))

;; Extend existing registry
(defun add-to-openai-registry (model-name metadata)
  "Add new model to OpenAI registry."
  ;; Directly modify global registry
  (register-model-metadata *openai-model-registry* model-name metadata))
```

**Rules Satisfied**: R006 (string keys with 'equal), R009 (thread safety consideration)

**Why This Shape**:
- Hash table test MUST be `'equal` for string key lookups to work
- Metadata plist structure matches existing models (consistency)
- Zero cost for local models is explicit (not omitted)

**Thread Safety**:

```lisp
;; If registering from multiple threads, use lock
(defvar *registry-lock* (bt:make-lock "registry-lock"))

(defun safe-register-model (registry model-name metadata)
  "Thread-safe model registration."
  (bt:with-lock-held (*registry-lock*)
    (register-model-metadata registry model-name metadata)))
```

**Anti-pattern**:

```lisp
;; DON'T do this
(make-hash-table :test 'eq)      ; Wrong - breaks string key lookups
(make-hash-table :test 'eql)     ; Wrong - same issue
(setf (gethash model-name registry) metadata)  ; Bypasses register-model-metadata abstraction
```

---

### PATTERN-006: Response Metadata Extraction

**Scenario**: Access provider context from response object for logging or debugging.

**Complete Example**:

```lisp
;; File: src/response-logging.lisp

(defun log-completion-response (response)
  "Log response with provider context."
  (let ((meta (response-metadata response)))
    ;; Metadata always includes provider type and name (Phase 3)
    (format t "[~A] Response ID: ~A~%"
            (getf meta :provider-name)  ; "OpenAI", "Anthropic", etc.
            (response-id response))

    ;; Provider-specific metadata may be present
    (when-let ((fingerprint (getf meta :system-fingerprint)))
      (format t "  System fingerprint: ~A~%" fingerprint))

    (when-let ((created (getf meta :created)))
      (format t "  Created: ~A~%" created))

    ;; Cost tracking
    (when-let ((input-cost (getf meta :input-cost-per-1m-tokens)))
      (let ((tokens (getf (response-usage response) :prompt-tokens)))
        (format t "  Estimated cost: $~,4F~%"
                (* tokens (/ input-cost 1000000.0)))))))

(defun group-responses-by-provider (responses)
  "Group responses by provider type."
  (let ((groups (make-hash-table :test 'eq)))
    (dolist (response responses)
      (let ((provider-type (getf (response-metadata response) :provider-type)))
        (push response (gethash provider-type groups))))
    groups))
```

**Rules Satisfied**: R007 (provider type in metadata), R005 (response metadata plist)

**Why This Shape**:
- `response-metadata` accessor returns plist (consistent with other APIs)
- Provider type and name are guaranteed present (Phase 3 requirement)
- Optional metadata checked with `when-let` for graceful handling

**Anti-pattern**:

```lisp
;; DON'T do this
(getf (response-metadata response) :provider-type :unknown)  ; Default masks missing data
(case (type-of (response-provider response))  ; Wrong - provider not stored in response
  ((openai-provider) ...))
```

---

### PATTERN-007: Provider Selection Based On Capabilities

**Scenario**: Choose provider dynamically based on required features.

**Complete Example**:

```lisp
;; File: src/provider-selection.lisp

(defun select-provider-with-capabilities (providers required-capabilities)
  "Select first provider supporting all required capabilities."
  (find-if (lambda (provider)
             (every (lambda (cap)
                      (provider-supports-p provider cap))
                    required-capabilities))
           providers))

;; Usage
(let* ((providers (list (make-provider :openai :model "gpt-4o")
                        (make-provider :anthropic :model "claude-3-5-sonnet-20241022")
                        (make-provider :ollama :model "llama3")))
       (provider (select-provider-with-capabilities providers '(:tools :vision))))

  (if provider
      (format t "Selected ~A (supports tools + vision)~%"
              (provider-name provider))
      (error "No provider supports required capabilities")))

;; Prefer cheapest provider with capability
(defun select-cheapest-with-embeddings (providers)
  "Select provider with embeddings support and lowest cost."
  (let ((candidates (remove-if-not
                     (lambda (p) (provider-supports-p p :embeddings))
                     providers)))
    (when candidates
      ;; Sort by cost (requires model metadata lookup)
      (first (sort candidates #'<
                   :key (lambda (p)
                          (or (getf (model-metadata p (provider-default-model p))
                                    :input-cost-per-1m-tokens)
                              most-positive-fixnum)))))))  ; Unknown cost = expensive
```

**Rules Satisfied**: R003 (capabilities plist), R010 (boolean returns)

**Why This Shape**:
- `every` + `provider-supports-p` checks all required capabilities
- Returns NIL if no provider matches (explicit failure signal)
- Cost-based selection uses metadata when available, falls back gracefully

---

### PATTERN-008: Config Summary For Serialization

**Scenario**: Serialize provider configuration for logging, debugging, or API response.

**Complete Example**:

```lisp
;; File: src/api-server.lisp

(defun provider-status-endpoint (provider)
  "Return JSON-safe provider status."
  (let ((summary (provider-config-summary provider)))
    ;; Summary is plist - convert to JSON hash
    (yason:encode-plist summary)))

;; Example output:
;; {"type":"openai","name":"OpenAI","model":"gpt-4o",
;;  "base-url":"https://api.openai.com/v1",
;;  "capabilities":{"tools":true,"embeddings":true,...}}

(defun log-provider-config (provider)
  "Log provider configuration safely."
  (let ((summary (provider-config-summary provider)))
    ;; Verify no API key present (security check)
    (assert (null (getf summary :api-key))
            nil
            "Config summary contains API key - security violation")

    ;; Safe to log
    (format t "Provider config: ~S~%" summary)))
```

**Rules Satisfied**: R004 (no API keys), INV-003 (serializable)

**Why This Shape**:
- Config summary is designed for serialization (no sensitive data)
- Plist structure converts cleanly to JSON
- Assertion verifies security requirement at runtime

**Anti-pattern**:

```lisp
;; DON'T do this
(yason:encode (provider-api-key provider))  ; Security violation
(format t "Config: ~S~%" provider)  ; May expose slots including API key
```

---

### PATTERN-009: Fallback For Missing Metadata

**Scenario**: Handle missing model metadata gracefully with reasonable defaults.

**Complete Example**:

```lisp
;; File: src/estimation.lisp

(defun get-context-window-with-fallback (provider model)
  "Get context window or use conservative default."
  (let ((meta (model-metadata provider model)))
    (if meta
        (getf meta :context-window)
        ;; No metadata - use conservative default based on provider type
        (case (provider-type provider)
          (:openai 8192)     ; GPT-3.5 baseline
          (:anthropic 200000) ; Claude baseline
          (:ollama 4096)     ; Common local model size
          (t 4096)))))       ; Conservative default

(defun estimate-max-tokens-with-metadata (provider model input-tokens)
  "Calculate safe max_tokens parameter."
  (let* ((ctx-window (get-context-window-with-fallback provider model))
         (meta (model-metadata provider model))
         (max-output (if meta
                         (getf meta :max-output-tokens)
                         ;; No metadata - use 1/4 of context as safe default
                         (floor ctx-window 4)))
         (available (- ctx-window input-tokens)))
    ;; Return lesser of max-output and available space
    (min max-output available)))
```

**Rules Satisfied**: R005 (NIL for unknown), R001 (provider-type dispatch)

**Why This Shape**:
- NIL check separates known from unknown models
- Provider-type fallback provides sensible defaults
- Defensive programming - never exceed context limits

---

### PATTERN-010: Multi-Provider Cost Comparison

**Scenario**: Compare costs across providers for same task.

**Complete Example**:

```lisp
;; File: src/cost-comparison.lisp

(defun compare-provider-costs (providers model-pairs input-tokens output-tokens)
  "Compare estimated costs across providers.
   MODEL-PAIRS: List of (provider model-name) pairs."
  (mapcar (lambda (pair)
            (destructuring-bind (provider model-name) pair
              (let* ((meta (model-metadata provider model-name))
                     (cost (if meta
                               (+ (* input-tokens (/ (getf meta :input-cost-per-1m-tokens) 1000000.0))
                                  (* output-tokens (/ (getf meta :output-cost-per-1m-tokens) 1000000.0)))
                               nil)))  ; Unknown cost
                (list :provider (provider-name provider)
                      :model model-name
                      :cost cost
                      :cost-formatted (if cost
                                          (format nil "$~,6F" cost)
                                          "unknown")))))
          model-pairs))

;; Usage
(let ((comparisons
       (compare-provider-costs
        (list (make-provider :openai) (make-provider :anthropic))
        '((openai-prov "gpt-4o-mini")
          (anthropic-prov "claude-3-5-haiku-20241022"))
        1000   ; Input tokens
        500))) ; Output tokens

  ;; Sort by cost
  (dolist (comp (sort comparisons #'< :key (lambda (c) (or (getf c :cost) 0))))
    (format t "~A (~A): ~A~%"
            (getf comp :provider)
            (getf comp :model)
            (getf comp :cost-formatted))))
```

**Rules Satisfied**: R005 (NIL for unknown), R002 (string names)

**Why This Shape**:
- Handles missing metadata gracefully (NIL cost)
- Separates raw cost from formatted display
- Sorts with NIL handling (treats unknown as zero for comparison)

---

## Anti-Patterns

### ANTI-001: Typecase On Provider Class

**Description**: Using `typecase` or `typep` on provider instance instead of `provider-type`.

**Symptoms**:
```lisp
(typecase provider
  (openai-provider ...)
  (anthropic-provider ...))
```

**Why harmful**:
- Breaks on provider subclasses
- Requires compile-time knowledge of all provider classes
- Not extensible to custom providers
- Slower than keyword comparison

**Remediation**:
```lisp
(case (provider-type provider)
  (:openai ...)
  (:anthropic ...))
```

**Agent action**: Flag for human review. Auto-fix allowed if mapping is 1:1.

---

### ANTI-002: Capability Trial-And-Error

**Description**: Attempting operation to discover if provider supports it.

**Symptoms**:
```lisp
(handler-case
    (complete messages :provider provider :tools tools)
  (provider-api-error ()
    ;; Guess provider doesn't support tools
    (complete messages :provider provider)))
```

**Why harmful**:
- Wastes API calls (costs money)
- Unpredictable error types across providers
- Race condition if provider changes
- Poor user experience (retries visible to user)

**Remediation**:
```lisp
(if (provider-supports-p provider :tools)
    (complete messages :provider provider :tools tools)
    (complete messages :provider provider))
```

**Agent action**: Flag. Auto-fix allowed (replace try-catch with capability check).

---

### ANTI-003: Hash Table With Wrong Test

**Description**: Creating model registry with `'eq` or `'eql` test instead of `'equal`.

**Symptoms**:
```lisp
(defvar *custom-registry* (make-hash-table :test 'eq))
(register-model-metadata *custom-registry* "my-model" ...)
(model-metadata provider "my-model")  ; Returns NIL despite registration
```

**Why harmful**:
- String keys never match with `'eq` test (compares object identity)
- Silent failure (returns NIL, no error)
- Difficult to debug (registration appears successful)

**Remediation**:
```lisp
(defvar *custom-registry* (make-hash-table :test 'equal))
```

**Agent action**: Auto-fix allowed (change test to `'equal`).

---

### ANTI-004: Exposing API Keys

**Description**: Including API key or credentials in config summary, logs, or serialization.

**Symptoms**:
```lisp
(defmethod provider-config-summary ((provider my-provider))
  (list :type :my-provider
        :api-key (provider-api-key provider)))  ; SECURITY VIOLATION
```

**Why harmful**:
- Credential leakage in logs
- API key exposure in error messages or debugging UI
- Violates security best practices

**Remediation**:
```lisp
(defmethod provider-config-summary ((provider my-provider))
  (list :type :my-provider
        ;; Never include :api-key
        :model (provider-default-model provider)))
```

**Agent action**: Flag violation. Auto-fix forbidden (requires security review).

---

### ANTI-005: Mutable Capabilities Plist

**Description**: Returning capabilities plist that varies per instance or can be modified.

**Symptoms**:
```lisp
(defmethod provider-capabilities ((provider my-provider))
  ;; BAD - builds new plist each time, may vary
  (list :tools (some-runtime-check)
        :embeddings t))
```

**Why harmful**:
- Breaks caching assumptions
- Inconsistent behavior across instances
- Capabilities should be class properties, not instance properties

**Remediation**:
```lisp
(defmethod provider-capabilities ((provider my-provider))
  ;; GOOD - literal plist, always same
  '(:tools t :embeddings t :streaming t))
```

**Agent action**: Flag if implementation contains function calls or slot access.

---

## Allowed Transformations

| Transform | Scope | Conditions |
|-----------|-------|------------|
| Add metadata key to response | `parse-*-response` methods | Key is namespaced (e.g., `:my-lib/custom-data`) |
| Register new model | Global registries | Metadata plist matches existing schema |
| Add new capability key | `provider-capabilities` | Boolean value, documented in API |
| Extend config summary | `provider-config-summary` | No sensitive data, plist structure |

---

## Forbidden Transformations

| Transform | Reason |
|-----------|--------|
| Change `provider-type` return type | Breaking change (keyword required for dispatch) |
| Remove standard capability keys | Breaks `provider-supports-p` assumptions |
| Include credentials in config summary | Security violation |
| Return non-plist from `provider-capabilities` | Breaks `getf` lookups |
| Change hash table test in registries | Breaks model lookups |

---

## Ambiguity Resolution Order

1. **Invariants** (always true)
2. **Normative rules** (MUST/MUST NOT)
3. **This specification**
4. **API-SPEC.agent.md** (protocol contracts)
5. **Patterns** (idiomatic usage)
6. **Implementation discretion**

If ambiguity remains: **Defer to human.**

---

## Machine Checklist

```
[ ] All provider classes implement provider-type (returns keyword)
[ ] All provider classes implement provider-name (returns string)
[ ] All provider classes implement provider-capabilities (returns plist)
[ ] provider-config-summary excludes :api-key
[ ] Model registries use (make-hash-table :test 'equal)
[ ] model-metadata returns NIL for unknown models
[ ] Response metadata includes :provider-type and :provider-name
[ ] provider-supports-p returns T or NIL (not other values)
[ ] No typecase on provider instances
[ ] No trial-and-error for capability detection
```

---

## Edge Cases

### EDGE-001: Unknown Provider Type

**Scenario**: Client encounters provider-type value not recognized.

**What happens**:
```lisp
(case (provider-type custom-provider)
  (:openai ...)
  (:anthropic ...)
  ;; Falls through to default
  (t (warn "Unknown provider: ~A" (provider-type custom-provider))))
```

**Idiomatic handling**:
- Always include `t` clause in `case` statements
- Log unknown types for debugging
- Fail gracefully (don't crash)

---

### EDGE-002: Concurrent Registry Modification

**Scenario**: Multiple threads call `register-model-metadata` simultaneously.

**What happens**:
- Hash table internal structure may corrupt
- Some registrations may be lost
- No error signaled (silent failure)

**Idiomatic handling**:
```lisp
(defvar *registry-lock* (bt:make-lock "registry-lock"))

(defun safe-register (registry model metadata)
  (bt:with-lock-held (*registry-lock*)
    (register-model-metadata registry model metadata)))
```

**Why not**:
- Rely on "it probably won't happen" - race conditions are subtle
- Use CAS loops - overkill for infrequent registration
- Document as single-threaded - limits flexibility

---

### EDGE-003: Missing Model Metadata

**Scenario**: Model exists in API but not in local registry.

**What happens**:
- `model-metadata` returns NIL
- Client must handle gracefully
- Request proceeds without metadata (no blocking error)

**Idiomatic handling**:
```lisp
(let ((meta (model-metadata provider model)))
  (if meta
      (use-metadata meta)
      (warn "No metadata for ~A, using defaults" model)
      (use-defaults)))
```

**Why not**:
- Fail hard - prevents using new models before registry update
- Return empty plist - ambiguous (is model known or unknown?)
- Auto-register from API - requires network call, slow

---

## Version History

- **1.0.0** (2026-01-12): Initial specification covering all three phases
