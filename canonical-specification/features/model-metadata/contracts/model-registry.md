---
type: contract
name: model-registry
version: 0.1.0
status: draft
feature: model-metadata
depends_on:
  - features/model-metadata/contracts/model-metadata
  - core/foundation/vocabulary#registry
---

# Model Registry Contract

This contract defines the model registry system for storing and retrieving model metadata across providers.

## Overview

The model registry provides centralized storage for model metadata. Each provider maintains its own registry containing metadata for all supported models.

## Registry Variables

### Provider-Specific Registries

```lisp
(defvar *openai-model-registry* (make-hash-table :test 'equal)
  "Registry of OpenAI model metadata.")

(defvar *anthropic-model-registry* (make-hash-table :test 'equal)
  "Registry of Anthropic model metadata.")

(defvar *gemini-model-registry* (make-hash-table :test 'equal)
  "Registry of Google Gemini model metadata.")
```

Each registry is a hash table mapping model name (string) to metadata plist.

## Functions

### `register-model-metadata`

Register metadata for a model in a registry.

```lisp
(register-model-metadata registry model-name metadata) → metadata
```

**Parameters**:
- `registry`: Hash table registry (e.g., `*openai-model-registry*`)
- `model-name`: Model identifier (string)
- `metadata`: Metadata plist

**Returns**: The registered metadata plist

**Example**:
```lisp
(register-model-metadata *openai-model-registry* "gpt-4o"
  '(:context-window 128000
    :max-output-tokens 16384
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 2.50
    :output-cost-per-1m-tokens 10.00))
```

### `get-model-metadata`

Retrieve metadata for a model from a registry.

```lisp
(get-model-metadata registry model-name) → metadata-or-nil
```

**Parameters**:
- `registry`: Hash table registry
- `model-name`: Model identifier (string)

**Returns**: Metadata plist or `nil` if model not found

**Example**:
```lisp
(get-model-metadata *openai-model-registry* "gpt-4o")
;; → (:context-window 128000 ...)

(get-model-metadata *openai-model-registry* "unknown-model")
;; → NIL
```

## Registry Structure

### Hash Table Organization

```
Registry (hash-table :test 'equal)
├─ "model-name-1" → metadata-plist-1
├─ "model-name-2" → metadata-plist-2
└─ "model-name-n" → metadata-plist-n
```

**Key**: Model name string (exact match, case-sensitive)
**Value**: Metadata plist (see model-metadata.md schema)

### Metadata Plist Format

```lisp
(:context-window <integer>
 :max-output-tokens <integer>
 :supports-tools <boolean>
 :supports-vision <boolean>
 :input-cost-per-1m-tokens <number>
 :output-cost-per-1m-tokens <number>)
```

## Provider Integration

### Method Implementation

Providers implement `model-metadata` to query their registry:

```lisp
(defmethod model-metadata ((provider openai-provider) model-name)
  (get-model-metadata *openai-model-registry* model-name))

(defmethod model-metadata ((provider anthropic-provider) model-name)
  (get-model-metadata *anthropic-model-registry* model-name))

(defmethod model-metadata ((provider gemini-provider) model-name)
  (get-model-metadata *gemini-model-registry* model-name))
```

### Registry Initialization

Registries are populated at package load time:

```lisp
;; In package initialization
(register-model-metadata *openai-model-registry* "gpt-4o" ...)
(register-model-metadata *openai-model-registry* "gpt-4o-mini" ...)
(register-model-metadata *anthropic-model-registry* "claude-opus-4" ...)
(register-model-metadata *gemini-model-registry* "gemini-3-flash-preview" ...)
```

## Registry Operations

### Listing Models

```lisp
(defun list-registered-models (registry)
  "List all model names in REGISTRY."
  (loop for key being the hash-keys of registry
        collect key))

;; Usage
(list-registered-models *openai-model-registry*)
;; → ("gpt-4o" "gpt-4o-mini" "gpt-4-turbo" ...)
```

### Checking Existence

```lisp
(defun model-registered-p (registry model-name)
  "Check if MODEL-NAME is registered in REGISTRY."
  (nth-value 1 (gethash model-name registry)))

;; Usage
(model-registered-p *openai-model-registry* "gpt-4o")
;; → T

(model-registered-p *openai-model-registry* "unknown-model")
;; → NIL
```

### Bulk Registration

```lisp
(defun register-models (registry models)
  "Register multiple models from alist of (name . metadata).
REGISTRY - Hash table registry
MODELS - Alist of (name . metadata-plist) pairs"
  (loop for (name . metadata) in models
        do (register-model-metadata registry name metadata)))

;; Usage
(register-models *openai-model-registry*
  '(("gpt-4o" . (:context-window 128000 ...))
    ("gpt-4o-mini" . (:context-window 128000 ...))))
```

## Model Naming

### Naming Conventions

**Specific versions** (preferred):
- `"gpt-4o-2024-11-20"` - Exact version with date
- `"claude-opus-4-20251101"` - Versioned model
- `"gemini-2.0-flash-exp"` - Explicit variant

**Aliases** (convenience):
- `"gpt-4o"` - Points to latest stable
- `"claude-opus-4"` - Generic name
- `"gemini-3-flash-preview"` - Named variant

### Version Resolution

When both alias and specific version exist:

```lisp
;; Register both
(register-model-metadata registry "gpt-4o"
  '(:context-window 128000 ...))

(register-model-metadata registry "gpt-4o-2024-11-20"
  '(:context-window 128000 ...))

;; Lookup prefers exact match
(get-model-metadata registry "gpt-4o-2024-11-20")  ; Specific version
(get-model-metadata registry "gpt-4o")              ; Alias
```

## Metadata Updates

### Updating Prices

When provider pricing changes:

```lisp
;; Old pricing
(register-model-metadata *openai-model-registry* "gpt-4o"
  '(:context-window 128000
    :max-output-tokens 16384
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 2.50
    :output-cost-per-1m-tokens 10.00))

;; Price drop announced
(register-model-metadata *openai-model-registry* "gpt-4o"
  '(:context-window 128000
    :max-output-tokens 16384
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 2.00  ; ← Updated
    :output-cost-per-1m-tokens 8.00)) ; ← Updated
```

### Version-Specific Metadata

Register metadata for specific versions to preserve accuracy:

```lisp
;; gpt-4o-2024-05-13 pricing
(register-model-metadata *openai-model-registry* "gpt-4o-2024-05-13"
  '(:input-cost-per-1m-tokens 5.00
    :output-cost-per-1m-tokens 15.00 ...))

;; gpt-4o-2024-11-20 pricing (newer, cheaper)
(register-model-metadata *openai-model-registry* "gpt-4o-2024-11-20"
  '(:input-cost-per-1m-tokens 2.50
    :output-cost-per-1m-tokens 10.00 ...))
```

## Registry Schema

```json-schema
{
  "type": "object",
  "description": "Hash table mapping model names to metadata",
  "patternProperties": {
    "^[a-zA-Z0-9\\-\\.]+$": {
      "type": "object",
      "properties": {
        "context_window": {"type": "integer", "minimum": 1},
        "max_output_tokens": {"type": "integer", "minimum": 1},
        "supports_tools": {"type": "boolean"},
        "supports_vision": {"type": "boolean"},
        "input_cost_per_1m_tokens": {"type": "number", "minimum": 0},
        "output_cost_per_1m_tokens": {"type": "number", "minimum": 0}
      },
      "required": [
        "context_window",
        "max_output_tokens",
        "supports_tools",
        "supports_vision",
        "input_cost_per_1m_tokens",
        "output_cost_per_1m_tokens"
      ]
    }
  }
}
```

## Invariants

1. **Unique keys**: Each model name maps to exactly one metadata plist
2. **Complete metadata**: All required fields MUST be present in metadata
3. **String keys**: Model names MUST be strings
4. **Immutable versioned entries**: Once registered with a version identifier, metadata SHOULD NOT change
5. **Registry isolation**: Provider registries MUST NOT share references

## Best Practices

1. **Version specificity**: Register specific versions rather than relying on aliases
2. **Metadata completeness**: Always provide all required fields
3. **Price accuracy**: Verify pricing against provider documentation
4. **Update frequency**: Review registries monthly for model updates
5. **Deprecation handling**: Keep metadata for deprecated models for backward compatibility

## Related Contracts

- [model-metadata.md](./model-metadata.md) - Metadata schema
- [provider-protocol.md](../../providers/contracts/provider-protocol.md) - Provider interface

## Implementation Notes

- Registries use `equal` test for string comparison
- Registry population happens at package load time (ASDF system definition)
- Each provider maintains its own registry to avoid naming collisions
- Registries are global variables for simplicity (no thread-safety guarantees)
