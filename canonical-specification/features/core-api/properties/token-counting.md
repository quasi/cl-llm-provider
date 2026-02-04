---
type: property
name: token-counting-rules
version: 0.1.0
status: draft
feature: core-api
source: src/tokenizer.lisp
confidence: medium
---

# Token Counting Invariants

[DRAFT] - Inferred from tokenizer implementation

## Overview

Properties governing token count estimation for cost calculation and context window management.

**Confidence**: Medium - These are estimations based on character-to-token ratios, not exact counts.

---

## PROP-TOKEN-001: Character-to-Token Ratio

**Statement**: Token count is estimated using ~4 characters per token ratio.

**Formal Expression**:
```lisp
∀ text ∈ String:
  estimate-tokens(text) ≈ ceiling(length(text) / 4.0)
```

**Rationale**: LLM tokenizers vary, but 4 chars/token is a reasonable approximation for English text.

**Implementation**: `src/tokenizer.lisp`:
```lisp
(defconstant +chars-per-token+ 4.0
  "Average characters per token (rough approximation)")
```

**Accuracy**: ±20% typically. Exact count requires provider-specific tokenizer.

**Violation Impact**: Cost estimates may be inaccurate; context window checks may be wrong.

---

## PROP-TOKEN-002: Message Overhead

**Statement**: Each message has 4 tokens of formatting overhead.

**Formal Expression**:
```lisp
∀ msg ∈ Message:
  count-tokens(msg) = 4 + count-tokens(msg.content)
```

**Rationale**: Role marker, delimiters, and message structure consume tokens.

**Implementation**: `src/tokenizer.lisp`:
```lisp
(defconstant +message-overhead+ 4
  "Token overhead per message (role + formatting)")
```

**Applies To**: All message types (user, assistant, system, tool).

---

## PROP-TOKEN-003: System Prompt Overhead

**Statement**: System prompt has 4 tokens of overhead plus content tokens.

**Formal Expression**:
```lisp
∀ system-prompt ∈ String:
  count-tokens-system(system-prompt) = 4 + ceiling(length(system-prompt) / 4.0)
```

**Rationale**: System prompt formatted similarly to messages with additional framing.

**Implementation**: Uses same +message-overhead+ constant.

---

## PROP-TOKEN-004: Total Token Composition

**Statement**: Total message tokens equals sum of individual message tokens.

**Formal Expression**:
```lisp
∀ messages ∈ List[Message]:
  count-tokens(messages) = Σ(count-message-tokens(msg) for msg in messages)
```

**Rationale**: Token count is additive across messages.

**Implementation**: `src/tokenizer.lisp`:
```lisp
(defun count-tokens (messages)
  (reduce #'+ messages :key #'count-message-tokens))
```

---

## PROP-TOKEN-005: Non-Negativity

**Statement**: Token counts are always non-negative integers.

**Formal Expression**:
```lisp
∀ text ∈ String:
  count-tokens(text) ≥ 0 ∧ (integerp count-tokens(text))
```

**Rationale**: Token counts represent discrete quantities. Negative values are nonsensical.

**Implementation**: `ceiling` always returns non-negative for non-negative inputs.

**Violation Impact**: Arithmetic errors in cost calculation.

---

## PROP-TOKEN-006: Response Token Relationship

**Statement**: In completion response, total tokens equals prompt tokens plus completion tokens.

**Formal Expression**:
```lisp
∀ response ∈ CompletionResponse:
  let usage = (response-usage response)
  (getf usage :total-tokens) =
    (getf usage :prompt-tokens) + (getf usage :completion-tokens)
```

**Rationale**: Total usage is sum of input and output tokens.

**Implementation**: Enforced by provider response parsing.

**Test Coverage**: `tests/test-integration-full-flow.lisp` - token usage tests

**Violation Impact**: Usage tracking becomes inconsistent; cost calculation fails.

---

## PROP-TOKEN-007: Estimation Bounds

**Statement**: Estimated tokens provide lower bound; actual count may be higher.

**Formal Expression**:
```lisp
∀ text ∈ String:
  estimate-tokens(text) ≤ actual-tokens(text) ≤ estimate-tokens(text) * 1.3
```

**Rationale**: Character-based estimation cannot account for multi-byte characters, special tokens, or subword tokenization.

**Typical Error**:
- Short text: ±30%
- Long text: ±10%
- Code/technical: +20% (more tokens)

**Recommendation**: Add 20% buffer for context window checks.

---

## PROP-TOKEN-008: Empty Message Tokens

**Statement**: Empty message has minimum of 4 tokens (overhead only).

**Formal Expression**:
```lisp
∀ msg ∈ Message where (length msg.content) = 0:
  count-tokens(msg) = 4
```

**Rationale**: Message structure itself consumes tokens even without content.

**Implementation**: Overhead added regardless of content length.

---

## Cost Estimation Properties

### PROP-COST-001: Linear Cost Relationship

**Statement**: Cost is linear in token count.

**Formal Expression**:
```lisp
∀ tokens ∈ ℕ, price-per-1M ∈ ℝ⁺:
  cost(tokens, price-per-1M) = (tokens / 1,000,000) * price-per-1M
```

**Rationale**: Providers charge per million tokens at flat rate.

**Implementation**: `src/tokenizer.lisp:estimate-cost`

### PROP-COST-002: Separate Input/Output Costs

**Statement**: Total cost equals sum of input cost and output cost.

**Formal Expression**:
```lisp
∀ response ∈ CompletionResponse:
  total-cost(response) =
    cost(prompt-tokens, input-price) + cost(completion-tokens, output-price)
```

**Rationale**: Most providers charge different rates for input vs output tokens.

---

## Accuracy Considerations

### When Estimation is Sufficient

- ✅ Cost forecasting (within 20% acceptable)
- ✅ Context window headroom checks (with 20% buffer)
- ✅ Usage analytics (aggregate trends)

### When Exact Count is Required

- ❌ Billing (use provider's actual count)
- ❌ Strict context window limits (use provider tokenizer)
- ❌ Token-level optimization

**Recommendation**: For exact counts, use provider-specific tokenizers:
- Anthropic: Use Claude tokenizer API
- OpenAI: Use tiktoken library
- Ollama: Use model-specific tokenizer

---

## Test Evidence Summary

| Property | Test File | Test Name | Status |
|----------|-----------|-----------|--------|
| PROP-TOKEN-002 | test-tokenizer.lisp | message-overhead | ✅ |
| PROP-TOKEN-004 | test-tokenizer.lisp | total-composition | ✅ |
| PROP-TOKEN-005 | test-tokenizer.lisp | non-negative | ✅ |
| PROP-TOKEN-006 | test-integration-full-flow.lisp | token-usage-tracking | ✅ |

---

## Related Properties

- [Response Structure](./response-structure.md) - Usage plist format
- [Model Metadata](../model-metadata/properties/metadata-accuracy.md) - Pricing data
