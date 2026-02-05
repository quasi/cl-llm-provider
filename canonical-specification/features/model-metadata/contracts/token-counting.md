---
type: contract
name: token-counting
version: 0.1.0
status: draft
feature: model-metadata
---

# Token Counting Contract

This contract defines the token counting system for estimating request token usage before sending to LLM providers.

## Overview

Token counting provides pre-request token estimation for cost calculation and context window validation. Uses character-based estimation as a portable fallback, with support for model-specific tokenizers in the future.

## Functions

### `estimate-tokens-from-text`

Estimate token count from text length.

```lisp
(estimate-tokens-from-text text) → integer
```

**Parameters**:
- `text`: String to estimate tokens for

**Returns**: Estimated token count

**Algorithm**: `ceiling(length(text) / *chars-per-token-estimate*)`

**Example**:
```lisp
(estimate-tokens-from-text "Hello, world!")
;; → 4  (13 chars / 4 = 3.25 → ceiling → 4)

(estimate-tokens-from-text "")
;; → 0

(estimate-tokens-from-text nil)
;; → 0
```

### JSON Schema: Token Estimation Parameters

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "text": {"type": ["string", "null"]},
    "chars_per_token": {"type": "number", "minimum": 1, "default": 4}
  }
}
```

### JSON Schema: Token Count Response

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "integer",
  "minimum": 0
}
```

### `count-message-tokens`

Count tokens in a single message.

```lisp
(count-message-tokens message) → integer
```

**Parameters**:
- `message`: Message plist with `:role` and `:content`

**Returns**: Estimated token count including overhead

**Calculation**:
```
tokens = *message-overhead-tokens* + content-tokens
```

**Examples**:
```lisp
;; Simple text message
(count-message-tokens '(:role "user" :content "What is Common Lisp?"))
;; → 8  (4 overhead + ~4 content)

;; Empty content
(count-message-tokens '(:role "assistant" :content ""))
;; → 4  (4 overhead + 0 content)

;; Multimodal content (list)
(count-message-tokens
  '(:role "user"
    :content ((:type "text" :text "What's in this image?")
              (:type "image_url" :image_url (:url "data:...")))))
;; → Counts text tokens + overhead (images not counted in current implementation)
```

### `count-tokens`

Count total tokens across all messages.

```lisp
(count-tokens messages &key model provider) → integer
```

**Parameters**:
- `messages`: List of message plists
- `model`: Model identifier (for model-specific tokenizers, currently ignored)
- `provider`: Provider instance (for provider-specific tokenizers, currently ignored)

**Returns**: Total estimated token count

**Example**:
```lisp
(count-tokens '((:role "system" :content "You are a helpful assistant.")
                (:role "user" :content "What is Common Lisp?")
                (:role "assistant" :content "Common Lisp is a dialect of Lisp.")))
;; → ~24 tokens (3 messages × 4 overhead + content)
```

### `count-tokens-with-system`

Count tokens including explicit system prompt.

```lisp
(count-tokens-with-system messages system &key model provider) → integer
```

**Parameters**:
- `messages`: List of message plists
- `system`: System prompt string
- `model`: Model identifier (optional)
- `provider`: Provider instance (optional)

**Returns**: Total token count including system prompt

**Example**:
```lisp
(count-tokens-with-system
  '((:role "user" :content "Hello"))
  "You are a helpful assistant."
  :model "gpt-4")
;; → ~11 tokens (system: 4 overhead + ~7 content, user: 4 overhead + ~1 content)
```

## Configuration

### `*chars-per-token-estimate*`

Average characters per token for estimation.

```lisp
(defvar *chars-per-token-estimate* 4)
```

**Rationale**: Most English text averages ~4 characters per token. This is a conservative estimate.

**Adjustment**: Can be set to different values for specific use cases:
```lisp
(let ((*chars-per-token-estimate* 3.5))  ; More aggressive estimate
  (estimate-tokens-from-text text))
```

### `*message-overhead-tokens*`

Token overhead per message for role and formatting.

```lisp
(defvar *message-overhead-tokens* 4)
```

**Rationale**: OpenAI adds ~4 tokens per message for role/formatting metadata.

## Token Counting Algorithm

### Text Messages

```
1. Get message content
2. Count content tokens: ceiling(length(content) / *chars-per-token-estimate*)
3. Add overhead: content-tokens + *message-overhead-tokens*
4. Return total
```

### Multimodal Messages

For content blocks:

```lisp
(:content ((:type "text" :text "Describe this image")
           (:type "image_url" :image_url (:url "..."))))
```

**Counting**:
1. Iterate through content list
2. For each block:
   - If string: `estimate-tokens-from-text(block)`
   - If plist with `:text`: `estimate-tokens-from-text(text)`
   - Otherwise: 0 (images not counted)
3. Sum all blocks
4. Add message overhead

### Tool Definitions

Tool definitions add tokens:

```
tool-tokens ≈ length(tool-name) + length(description) + parameter-schema-size
```

**Currently**: Tool tokens are NOT automatically counted. Users should include tool JSON size in manual estimates.

**Future**: `count-tokens-with-tools` function to estimate tool definition overhead.

## Accuracy

### Estimation Error

**Character-based**: ±5-10% error typical
**True range**: 3-5 characters per token depending on text type

| Text Type | Chars/Token | Accuracy |
|-----------|-------------|----------|
| English prose | ~4.0 | Good |
| Code | ~3.5 | Moderate |
| JSON/structured | ~2.5 | Poor |
| Unicode/emoji | ~6.0 | Poor |

### Improving Accuracy

**Model-specific tokenizers**:
```lisp
;; Future API
(count-tokens messages :model "gpt-4" :tokenizer (tiktoken "cl100k_base"))
```

**Manual calibration**:
```lisp
;; Measure actual vs estimated
(let ((estimated (count-tokens messages))
      (actual (response-usage-prompt-tokens response)))
  (format t "Accuracy: ~,1F%~%"
          (* 100 (/ (float estimated) actual))))
```

## Usage Patterns

### Context Window Validation

```lisp
(let* ((input-tokens (count-tokens messages :model model))
       (metadata (model-metadata provider model))
       (ctx-window (getf metadata :context-window)))
  (when (> input-tokens ctx-window)
    (error "Input (~D tokens) exceeds context window (~D tokens)"
           input-tokens ctx-window)))
```

### Truncation Planning

```lisp
(defun truncate-messages-to-fit (messages max-tokens)
  "Remove oldest messages until under MAX-TOKENS."
  (let ((tokens (count-tokens messages)))
    (if (<= tokens max-tokens)
        messages
        (truncate-messages-to-fit (rest messages) max-tokens))))
```

### Cost Estimation

See [cost-estimation.md](./cost-estimation.md) for integration with pricing.

## Limitations

1. **Estimation only**: Not exact token counts
2. **English-centric**: Optimized for English text
3. **No image tokens**: Images contribute to token count but aren't estimated
4. **No tool tokens**: Tool definitions not automatically counted
5. **Model-agnostic**: Same estimation for all models (currently)

## Future Enhancements

1. **Tiktoken integration**: Use exact tokenizers (e.g., `cl100k_base` for GPT-4)
2. **Image token estimation**: Estimate tokens for vision inputs based on resolution
3. **Tool definition counting**: Auto-count tool schema tokens
4. **Model-specific estimates**: Different chars/token for different model families
5. **Caching**: Cache token counts for static messages

## Invariants

1. **Non-negative**: Token counts MUST be >= 0
2. **Monotonic addition**: Adding text increases token count
3. **Overhead minimum**: Every message has at least `*message-overhead-tokens*` tokens
4. **Empty content**: `(estimate-tokens-from-text "")` = 0
5. **Nil safety**: `(estimate-tokens-from-text nil)` = 0

## Best Practices

1. **Conservative estimates**: Use estimates for planning, not exact billing
2. **Validation**: Check against actual usage from responses
3. **Calibration**: Track accuracy over time and adjust `*chars-per-token-estimate*`
4. **Buffer**: Leave 5-10% buffer when estimating context limits
5. **Tool overhead**: Manually add ~100-500 tokens per tool definition

## Related Contracts

- [cost-estimation.md](./cost-estimation.md) - Cost calculation using token counts
- [model-metadata.md](./model-metadata.md) - Context window limits

## Implementation Notes

- Character-based estimation is O(1) for strings (length is cached in Common Lisp)
- Message overhead is constant per message regardless of content
- Multimodal content requires iteration but is typically < 10 blocks
- Estimation happens client-side before HTTP request
- Actual token counts are returned in response `usage` field
