---
type: decision
name: DR-001-array-items-schema
date: 2025-01-22
status: accepted
change_type: modification
impacts:
  - core/foundation/vocabulary.md
  - features/tools
---

# Array Parameters Require Items Schema

## Change Request

OpenAI's function calling API rejects tool schemas where array-type parameters don't include an `items` property specifying the element type. This caused 400 Bad Request errors when making chat completion requests with tools containing array parameters.

## Impact Analysis Summary

- **Direct Impact**: `translate-tool-to-provider` in `src/protocol.lisp` and `src/providers/anthropic.lisp` needed modification
- **Vocabulary Impact**: Tool Definition term needed update to document `:items` property
- **Backwards Compatibility**: Maintained by defaulting to string items when not specified

Note: The Anthropic provider has its own `translate-tool-to-provider` implementation that required the same fix as the default implementation in protocol.lisp. Other providers (Gemini, OpenRouter, Ollama, OpenAI-compatible) inherit from the default and are covered by the protocol.lisp fix.

## Decision

1. Extend parameter specification to support `:items` property for array types
2. Default to `{"type": "string"}` when `:items` is not specified (backwards compatible)
3. Update vocabulary to document the new property

## Technical Details

**Parameter specification with items**:
```lisp
(:name "patterns"
 :type :array
 :items (:type :string)
 :description "List of patterns")
```

**Generated JSON Schema**:
```json
{
  "type": "array",
  "items": { "type": "string" },
  "description": "List of patterns"
}
```

## Alternatives Considered

1. **Require `:items` for all array parameters**: Rejected - breaks existing tool definitions
2. **Provider-specific handling**: Rejected - this is a JSON Schema requirement, applies universally

## Migration

No migration required. Existing tool definitions continue to work (default to string items).

**Recommended**: Explicitly specify `:items` for clarity:
```lisp
;; Before (still works)
(:name "tags" :type :array :description "Tags")

;; After (recommended)
(:name "tags" :type :array :items (:type :string) :description "Tags")
```
