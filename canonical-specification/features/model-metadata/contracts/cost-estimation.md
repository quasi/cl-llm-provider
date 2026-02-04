---
type: contract
name: cost-estimation
version: 0.1.0
status: draft
feature: model-metadata
---

# Cost Estimation Contract

This contract defines the cost estimation system for calculating expected LLM API costs before making requests.

## Overview

Cost estimation combines token counting with model pricing metadata to calculate expected costs for completion requests. Provides input cost, output cost estimate, and total cost.

## Function: `estimate-cost`

Estimate cost for a completion request.

```lisp
(estimate-cost messages &key provider model system max-tokens)
→ (values input-cost output-cost total-cost)
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `messages` | list | required | Conversation messages |
| `provider` | provider | required | Provider instance (for pricing lookup) |
| `model` | string | provider default | Model identifier |
| `system` | string | `nil` | System prompt |
| `max-tokens` | integer | `1000` | Expected output tokens |

### Return Values

Returns three values:
1. **input-cost**: Cost for input tokens (USD)
2. **output-cost**: Estimated cost for output tokens (USD)
3. **total-cost**: Sum of input and output costs (USD)

Returns `(values nil nil nil)` if pricing unavailable for model.

### Examples

#### Basic Usage

```lisp
(multiple-value-bind (in out total)
    (estimate-cost '((:role "user" :content "Hello, world!"))
                   :provider *openai-provider*
                   :model "gpt-4"
                   :max-tokens 100)
  (format t "Input: $~,4F~%" in)
  (format t "Output: $~,4F~%" out)
  (format t "Total: $~,4F~%" total))
;; Output:
;; Input: $0.0002
;; Output: $0.0060
;; Total: $0.0062
```

#### With System Prompt

```lisp
(estimate-cost '((:role "user" :content "What is Common Lisp?"))
               :provider *openai-provider*
               :model "gpt-4o"
               :system "You are a helpful programming assistant."
               :max-tokens 500)
;; → Returns estimated cost including system prompt tokens
```

#### Unknown Model

```lisp
(estimate-cost messages
               :provider *openai-provider*
               :model "unknown-model")
;; → (values NIL NIL NIL)
```

## Cost Calculation Algorithm

### Step 1: Determine Model

```lisp
effective-model = model OR provider-default-model(provider)
```

### Step 2: Lookup Pricing

```lisp
metadata = model-metadata(provider, effective-model)
input-cost-per-1m = metadata[:input-cost-per-1m-tokens]
output-cost-per-1m = metadata[:output-cost-per-1m-tokens]
```

If pricing unavailable, return `(nil nil nil)`.

### Step 3: Count Input Tokens

```lisp
input-tokens = count-tokens-with-system(messages, system, model, provider)
```

### Step 4: Estimate Output Tokens

```lisp
output-tokens = max-tokens OR 1000  ; Default to 1000 if not specified
```

### Step 5: Calculate Costs

```lisp
input-cost = input-tokens × (input-cost-per-1m / 1,000,000)
output-cost = output-tokens × (output-cost-per-1m / 1,000,000)
total-cost = input-cost + output-cost
```

## Cost Calculation Schema

```json-schema
{
  "type": "object",
  "properties": {
    "input_tokens": {
      "type": "integer",
      "minimum": 0,
      "description": "Estimated input tokens"
    },
    "output_tokens": {
      "type": "integer",
      "minimum": 0,
      "description": "Expected output tokens"
    },
    "input_cost_per_1m": {
      "type": "number",
      "minimum": 0,
      "description": "USD per 1M input tokens"
    },
    "output_cost_per_1m": {
      "type": "number",
      "minimum": 0,
      "description": "USD per 1M output tokens"
    },
    "input_cost": {
      "type": "number",
      "minimum": 0,
      "description": "Total input cost (USD)"
    },
    "output_cost": {
      "type": "number",
      "minimum": 0,
      "description": "Total output cost (USD)"
    },
    "total_cost": {
      "type": "number",
      "minimum": 0,
      "description": "Total estimated cost (USD)"
    }
  }
}
```

## Function: `format-cost`

Format cost in USD for display.

```lisp
(format-cost cost &optional stream) → formatted-string-or-nil
```

**Parameters**:
- `cost`: Cost in USD (float) or `nil`
- `stream`: Output stream (default: `t` for stdout)

**Returns**: Formatted string when stream is `nil`, otherwise writes to stream

**Examples**:
```lisp
(format-cost 0.0025)
;; Prints: $0.0025

(format-cost 0.0001)
;; Prints: $0.0001

(format-cost 1.2345)
;; Prints: $1.2345

(format-cost nil)
;; Prints: N/A

(format-cost 0.123456 nil)
;; Returns: "$0.1235"  (rounded to 4 decimal places)
```

## Usage Patterns

### Budget Checking

```lisp
(defun check-budget (messages provider model max-tokens budget)
  "Check if request fits within BUDGET (USD)."
  (multiple-value-bind (in out total)
      (estimate-cost messages
                     :provider provider
                     :model model
                     :max-tokens max-tokens)
    (when (and total (> total budget))
      (error "Estimated cost $~,4F exceeds budget $~,4F" total budget))
    total))
```

### Cost Comparison

```lisp
(defun compare-model-costs (messages models provider)
  "Compare cost across multiple models."
  (loop for model in models
        collect (multiple-value-bind (in out total)
                    (estimate-cost messages
                                   :provider provider
                                   :model model
                                   :max-tokens 1000)
                  (list :model model :cost total))))

;; Usage
(compare-model-costs messages
                     '("gpt-4" "gpt-4o-mini" "gpt-3.5-turbo")
                     *openai-provider*)
;; → ((:model "gpt-4" :cost 0.035)
;;    (:model "gpt-4o-mini" :cost 0.0008)
;;    (:model "gpt-3.5-turbo" :cost 0.0025))
```

### Running Cost Tracker

```lisp
(defvar *total-spent* 0.0)

(defun track-completion-cost (response)
  "Track actual cost from response usage."
  (let* ((usage (response-usage response))
         (input-tokens (getf usage :prompt-tokens))
         (output-tokens (getf usage :completion-tokens))
         (metadata (model-metadata provider model))
         (input-cost-per-1m (getf metadata :input-cost-per-1m-tokens))
         (output-cost-per-1m (getf metadata :output-cost-per-1m-tokens))
         (cost (+ (* input-tokens (/ input-cost-per-1m 1000000.0))
                  (* output-tokens (/ output-cost-per-1m 1000000.0)))))
    (incf *total-spent* cost)
    (format t "Request cost: $~,4F (Total: $~,4F)~%" cost *total-spent*)
    cost))
```

## Pricing Examples

### OpenAI Pricing (as of 2026-01)

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|------------------------|
| GPT-4o | $2.50 | $10.00 |
| GPT-4o-mini | $0.15 | $0.60 |
| GPT-4-turbo | $10.00 | $30.00 |
| GPT-4 | $30.00 | $60.00 |
| GPT-3.5-turbo | $0.50 | $1.50 |

### Anthropic Pricing (as of 2026-01)

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|------------------------|
| Claude Opus 4 | $15.00 | $75.00 |
| Claude Sonnet 4 | $3.00 | $15.00 |
| Claude Haiku 3.5 | $0.80 | $4.00 |

### Gemini Pricing (as of 2026-01)

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|------------------------|
| Gemini 3 Flash | $0.075 | $0.30 |
| Gemini 3 Pro | $1.25 | $5.00 |

## Accuracy

### Estimation vs Actual

**Input cost**: Typically accurate within 5-10% due to token estimation error

**Output cost**: Highly variable (estimate assumes `max-tokens` fully used)

**Actual cost**: Use `response-usage` for exact cost calculation

### Improving Accuracy

```lisp
;; Estimate before request
(multiple-value-bind (est-in est-out est-total)
    (estimate-cost messages :provider p :model m :max-tokens 500)
  (let ((response (complete messages :model m :max-tokens 500)))
    ;; Calculate actual cost
    (let* ((usage (response-usage response))
           (actual-in (* (getf usage :prompt-tokens)
                        (/ (getf metadata :input-cost-per-1m-tokens) 1000000.0)))
           (actual-out (* (getf usage :completion-tokens)
                         (/ (getf metadata :output-cost-per-1m-tokens) 1000000.0))))
      (format t "Estimated: $~,4F~%" est-total)
      (format t "Actual: $~,4F~%" (+ actual-in actual-out)))))
```

## Limitations

1. **Token estimation**: Uses approximate token counting (±5-10% error)
2. **Output tokens**: Estimate assumes full `max-tokens` used (often overestimate)
3. **Pricing changes**: Hardcoded pricing may become stale
4. **Tiered pricing**: Some models have different rates for long contexts (not modeled)
5. **Cached tokens**: Some providers offer cache discounts (not modeled)

## Invariants

1. **Non-negative costs**: All costs MUST be >= 0
2. **Total sum**: `total-cost` = `input-cost` + `output-cost`
3. **Nil consistency**: If pricing unavailable, all three values are `nil`
4. **Provider required**: `estimate-cost` MUST receive provider parameter
5. **Cost monotonicity**: More tokens → higher cost

## Best Practices

1. **Estimate before large requests**: Check cost for expensive models
2. **Use actual usage**: Track actual costs via response usage stats
3. **Budget alerts**: Set thresholds and alert when exceeded
4. **Model selection**: Compare costs across models for budget optimization
5. **Pricing updates**: Review and update pricing metadata quarterly

## Error Conditions

| Error | Condition | Recovery |
|-------|-----------|----------|
| `missing-provider` | Provider argument is nil | Provide valid provider instance |
| `unknown-model` | Model not found in registry (returns nil values) | Register model or use known model |
| `missing-pricing` | Metadata exists but pricing fields are nil (returns nil values) | Update metadata with pricing information |
| `invalid-messages` | Messages argument is not a list | Pass valid message list |
| `invalid-max-tokens` | max-tokens is negative or non-numeric | Use positive integer for max-tokens |

## Related Contracts

- [token-counting.md](./token-counting.md) - Token estimation
- [model-metadata.md](./model-metadata.md) - Pricing data

## Implementation Notes

- Cost calculation is pure function (no side effects)
- Returns `nil` values gracefully when pricing unavailable
- Output cost is estimate only (actual usage may be lower)
- Pricing is per 1 million tokens to avoid floating-point issues with small token counts
- Cost formatting uses 4 decimal places for sub-cent accuracy
