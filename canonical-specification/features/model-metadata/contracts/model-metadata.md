---
type: contract
name: model-metadata
version: 0.1.0
status: draft
feature: model-metadata
---

# Model Metadata Contract

This contract defines the structure and semantics of model metadata including capabilities, limits, and pricing.

## Overview

Model metadata provides essential information about LLM models including context windows, output limits, supported features, and pricing. This information is used for request validation, cost estimation, and feature detection.

## Metadata Schema

```json-schema
{
  "type": "object",
  "properties": {
    "context_window": {
      "type": "integer",
      "minimum": 1,
      "description": "Maximum input tokens (including messages, system prompt, tools)"
    },
    "max_output_tokens": {
      "type": "integer",
      "minimum": 1,
      "description": "Maximum completion/output tokens"
    },
    "supports_tools": {
      "type": "boolean",
      "description": "Whether model supports function calling/tools"
    },
    "supports_vision": {
      "type": "boolean",
      "description": "Whether model supports image inputs"
    },
    "input_cost_per_1m_tokens": {
      "type": "number",
      "minimum": 0,
      "description": "USD cost per 1 million input tokens"
    },
    "output_cost_per_1m_tokens": {
      "type": "number",
      "minimum": 0,
      "description": "USD cost per 1 million output tokens"
    }
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
```

## Provider Method: `model-metadata`

Retrieve metadata for a specific model.

```lisp
(model-metadata provider model-name) → metadata-plist-or-nil
```

**Parameters**:
- `provider`: Provider instance
- `model-name`: Model identifier (string)

**Returns**: Metadata plist or `nil` if model unknown

**Example**:
```lisp
(model-metadata (make-provider :openai) "gpt-4")
;; → (:context-window 8192
;;     :max-output-tokens 8192
;;     :supports-tools t
;;     :supports-vision nil
;;     :input-cost-per-1m-tokens 30.00
;;     :output-cost-per-1m-tokens 60.00)
```

## Metadata Fields

### Context Window

Maximum number of tokens that can be sent to the model in a single request.

**Includes**:
- All message content
- System prompt
- Tool definitions (if provided)
- Message formatting overhead

**Usage**:
```lisp
(let* ((metadata (model-metadata provider model))
       (ctx-window (getf metadata :context-window))
       (input-tokens (count-tokens messages)))
  (when (> input-tokens ctx-window)
    (error "Input exceeds context window: ~D > ~D" input-tokens ctx-window)))
```

### Maximum Output Tokens

Maximum number of tokens the model can generate in a response.

**Usage**:
```lisp
(let* ((metadata (model-metadata provider model))
       (max-out (getf metadata :max-output-tokens)))
  (complete messages :max-tokens (min requested-tokens max-out)))
```

### Tool Support

Boolean indicating if the model supports function calling/tool use.

**Usage**:
```lisp
(let ((metadata (model-metadata provider model)))
  (if (getf metadata :supports-tools)
      (complete messages :tools my-tools)
      (warn "Model ~A doesn't support tools" model)))
```

### Vision Support

Boolean indicating if the model can process image inputs.

**Usage**:
```lisp
(let ((metadata (model-metadata provider model)))
  (unless (getf metadata :supports-vision)
    (error "Model ~A doesn't support vision inputs" model)))
```

### Input Cost

Cost in USD per 1 million input tokens.

**Calculation**:
```lisp
(let* ((metadata (model-metadata provider model))
       (input-cost-per-1m (getf metadata :input-cost-per-1m-tokens))
       (input-tokens (count-tokens messages))
       (cost (* input-tokens (/ input-cost-per-1m 1000000.0))))
  cost)
```

### Output Cost

Cost in USD per 1 million output tokens (completion tokens).

**Calculation**:
```lisp
(let* ((metadata (model-metadata provider model))
       (output-cost-per-1m (getf metadata :output-cost-per-1m-tokens))
       (output-tokens (response-usage-completion-tokens response))
       (cost (* output-tokens (/ output-cost-per-1m 1000000.0))))
  cost)
```

## Model Examples

### OpenAI GPT-4o

```lisp
(:context-window 128000
 :max-output-tokens 16384
 :supports-tools t
 :supports-vision t
 :input-cost-per-1m-tokens 2.50
 :output-cost-per-1m-tokens 10.00)
```

### Anthropic Claude Opus 4

```lisp
(:context-window 200000
 :max-output-tokens 4096
 :supports-tools t
 :supports-vision t
 :input-cost-per-1m-tokens 15.00
 :output-cost-per-1m-tokens 75.00)
```

### Google Gemini Flash

```lisp
(:context-window 1048576
 :max-output-tokens 8192
 :supports-tools t
 :supports-vision t
 :input-cost-per-1m-tokens 0.075
 :output-cost-per-1m-tokens 0.30)
```

## Metadata Lifecycle

### Registration

Models are registered at package load time:

```lisp
(register-model-metadata *openai-model-registry* "gpt-4o"
  '(:context-window 128000
    :max-output-tokens 16384
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 2.50
    :output-cost-per-1m-tokens 10.00))
```

### Lookup

Providers implement `model-metadata` to query their registry:

```lisp
(defmethod model-metadata ((provider openai-provider) model-name)
  (get-model-metadata *openai-model-registry* model-name))
```

### Updates

Metadata can be updated when model pricing or limits change:

```lisp
(register-model-metadata *openai-model-registry* "gpt-4o"
  '(:context-window 128000
    :max-output-tokens 16384
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 2.00  ; Updated price
    :output-cost-per-1m-tokens 8.00))
```

## Unknown Models

When metadata is unavailable:

```lisp
(model-metadata provider "unknown-model")
;; → NIL
```

**Handling**:
1. **Best effort**: Use conservative defaults (context: 4096, no tools, no vision)
2. **Error**: Signal `unknown-model` condition
3. **Skip validation**: Proceed without context/cost checks (risky)

## Invariants

1. **Positive limits**: Context window and max output tokens MUST be > 0
2. **Non-negative costs**: Pricing MUST be >= 0 (free models have cost 0.0)
3. **Total tokens**: `context-window` >= `max-output-tokens` typically holds
4. **Capability consistency**: If `supports-vision` is true, model accepts multimodal content
5. **Immutability**: Metadata for a specific model+version string MUST NOT change

## Best Practices

1. **Version-specific metadata**: Register specific model versions (e.g., "gpt-4-0613") not just aliases
2. **Pricing updates**: Check provider pricing pages regularly for updates
3. **Conservative estimates**: When unsure, use higher costs/lower limits
4. **Fallback chains**: Try specific version, then generic name, then defaults
5. **Validation**: Check metadata exists before attempting operations

## Error Conditions

| Error | Condition | Recovery |
|-------|-----------|----------|
| `unknown-model` | Metadata requested for model not in registry | Use default metadata or register model |
| `invalid-provider` | Provider argument is nil or not a provider instance | Pass valid provider |
| `metadata-validation-failed` | Metadata missing required fields or has invalid values | Fix metadata before registration |

## Related Contracts

- [model-registry.md](./model-registry.md) - Registry system
- [token-counting.md](./token-counting.md) - Token estimation
- [cost-estimation.md](./cost-estimation.md) - Cost calculation

## Implementation Notes

- Metadata is stored in provider-specific hash tables
- Pricing is subject to change; verify accuracy periodically
- Context windows are theoretical maximums; practical limits may be lower
- Some models have tiered pricing (e.g., different rates for long contexts)
