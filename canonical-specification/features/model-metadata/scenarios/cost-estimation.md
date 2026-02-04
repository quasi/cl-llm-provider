---
type: scenario
name: cost-estimation
version: 0.1.0
feature: model-metadata
tags:
  - happy-path
  - budget-planning
---

# Cost Estimation

## Context

User needs to estimate API costs before making requests to plan budgets, compare models, and avoid unexpected expenses.

## Scenario 1: Estimate cost for simple request

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *messages* '((:role "user" :content "What is Common Lisp?")))
```

### Steps

#### 1. Estimate cost

**Action**: Call estimate-cost
```lisp
(multiple-value-bind (input-cost output-cost total-cost)
    (estimate-cost *messages*
                   :provider *provider*
                   :model "gpt-4"
                   :max-tokens 100)
  (list :input input-cost :output output-cost :total total-cost))
```

**Expected**:
- Returns three cost values
- All values > 0
- Total = input + output
- Costs in reasonable range

#### 2. Format cost for display

**Action**: Format total cost
```lisp
(format-cost total-cost nil)
```

**Expected**:
- Returns formatted string like "$0.0062"
- 4 decimal places
- Clear currency symbol

### Verification

```
ASSERT input-cost > 0
ASSERT output-cost > 0
ASSERT total-cost == (+ input-cost output-cost)
ASSERT total-cost < 1.0  ; Simple request should be under $1
ASSERT (format-cost total-cost nil) matches "$\\d+\\.\\d{4}"
```

## Scenario 2: Compare costs across models

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *messages* '((:role "user" :content "Explain quantum computing")))
```

### Steps

#### 1. Estimate for expensive model (GPT-4)

**Action**: Cost for GPT-4
```lisp
(setf *gpt4-cost*
      (nth-value 2 (estimate-cost *messages*
                                  :provider *provider*
                                  :model "gpt-4"
                                  :max-tokens 500)))
```

#### 2. Estimate for cheap model (GPT-4o-mini)

**Action**: Cost for GPT-4o-mini
```lisp
(setf *mini-cost*
      (nth-value 2 (estimate-cost *messages*
                                  :provider *provider*
                                  :model "gpt-4o-mini"
                                  :max-tokens 500)))
```

#### 3. Compare costs

**Action**: Calculate cost difference
```lisp
(/ *gpt4-cost* *mini-cost*)
```

**Expected**:
- GPT-4 significantly more expensive
- Ratio > 10x (GPT-4 is ~100x more expensive typically)
- Clear cost difference for informed choice

### Verification

```
ASSERT *gpt4-cost* > *mini-cost*
ASSERT (/ *gpt4-cost* *mini-cost*) > 10
```

## Scenario 3: Budget checking

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *budget* 0.10)  ; $0.10 limit
(setf *messages* '((:role "user" :content "Write a long essay on AI")))
```

### Steps

#### 1. Estimate request cost

**Action**: Estimate with large output
```lisp
(setf *estimated-cost*
      (nth-value 2 (estimate-cost *messages*
                                  :provider *provider*
                                  :model "gpt-4"
                                  :max-tokens 4000)))
```

#### 2. Check against budget

**Action**: Validate cost within budget
```lisp
(if (> *estimated-cost* *budget*)
    (error "Estimated cost $~,4F exceeds budget $~,4F"
           *estimated-cost* *budget*)
    t)
```

**Expected**:
- Large request with GPT-4 exceeds budget
- Error raised with clear message
- User can adjust model or max-tokens

#### 3. Find affordable alternative

**Action**: Try cheaper model
```lisp
(setf *mini-cost*
      (nth-value 2 (estimate-cost *messages*
                                  :provider *provider*
                                  :model "gpt-4o-mini"
                                  :max-tokens 4000)))
(< *mini-cost* *budget*)
```

**Expected**:
- Cheaper model fits budget
- User can make informed tradeoff

### Verification

```
ASSERT *estimated-cost* > *budget*
ASSERT *mini-cost* < *budget*
ASSERT error message clearly states costs
```

## Scenario 4: Actual vs estimated cost tracking

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *messages* '((:role "user" :content "Hello")))
```

### Steps

#### 1. Estimate before request

**Action**: Get pre-request estimate
```lisp
(multiple-value-bind (est-in est-out est-total)
    (estimate-cost *messages*
                   :provider *provider*
                   :model "gpt-4o"
                   :max-tokens 50)
  (setf *estimated* est-total))
```

#### 2. Make actual request

**Action**: Complete and get actual usage
```lisp
(setf *response* (complete *messages*
                           :provider *provider*
                           :model "gpt-4o"
                           :max-tokens 50))
(setf *usage* (response-usage *response*))
```

#### 3. Calculate actual cost

**Action**: Compute actual cost from usage
```lisp
(let* ((metadata (model-metadata *provider* "gpt-4o"))
       (input-cost-per-1m (getf metadata :input-cost-per-1m-tokens))
       (output-cost-per-1m (getf metadata :output-cost-per-1m-tokens))
       (input-tokens (getf *usage* :prompt-tokens))
       (output-tokens (getf *usage* :completion-tokens)))
  (setf *actual* (+ (* input-tokens (/ input-cost-per-1m 1000000.0))
                    (* output-tokens (/ output-cost-per-1m 1000000.0)))))
```

#### 4. Compare estimates

**Action**: Calculate accuracy
```lisp
(let ((accuracy (* 100 (/ (float *estimated*) *actual*))))
  (format t "Estimated: $~,4F~%" *estimated*)
  (format t "Actual: $~,4F~%" *actual*)
  (format t "Accuracy: ~,1F%~%" accuracy))
```

**Expected**:
- Input estimate accurate within 5-10%
- Output estimate often overestimates (assumed max-tokens)
- Total estimate reasonable for planning

### Verification

```
ASSERT (abs (- *estimated* *actual*)) / *actual* < 0.5  ; Within 50%
ASSERT *estimated* >= *actual* * 0.5  ; Not wildly off
```

## Scenario 5: Cost estimation with system prompt

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *messages* '((:role "user" :content "Hello")))
(setf *system* "You are a helpful assistant with extensive knowledge of programming.")
```

### Steps

#### 1. Estimate without system prompt

**Action**: Cost without system
```lisp
(setf *without-system*
      (nth-value 2 (estimate-cost *messages*
                                  :provider *provider*
                                  :model "gpt-4")))
```

#### 2. Estimate with system prompt

**Action**: Cost with system
```lisp
(setf *with-system*
      (nth-value 2 (estimate-cost *messages*
                                  :provider *provider*
                                  :model "gpt-4"
                                  :system *system*)))
```

#### 3. Verify system cost included

**Action**: Compare costs
```lisp
(> *with-system* *without-system*)
```

**Expected**:
- System prompt adds to cost
- Difference matches system prompt token count
- Accurate inclusion of system overhead

### Verification

```
ASSERT *with-system* > *without-system*
ASSERT (*with-system* - *without-system*) matches system prompt token cost
```

## Scenario 6: Handling unknown model pricing

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *messages* '((:role "user" :content "Test")))
```

### Steps

#### 1. Attempt estimate for unknown model

**Action**: Estimate with unregistered model
```lisp
(multiple-value-bind (in out total)
    (estimate-cost *messages*
                   :provider *provider*
                   :model "unknown-model")
  (list in out total))
```

**Expected**:
- Returns (NIL NIL NIL)
- No error raised
- User can detect missing pricing

#### 2. Handle missing pricing gracefully

**Action**: Provide fallback
```lisp
(or (nth-value 2 (estimate-cost *messages*
                                :provider *provider*
                                :model "unknown-model"))
    (progn
      (warn "Pricing unavailable for model")
      :unknown))
```

**Expected**:
- Graceful degradation
- Warning issued
- User aware of uncertainty

### Verification

```
ASSERT all values are NIL for unknown model
ASSERT no error raised
ASSERT fallback handling works
```

## Performance Criteria

- Cost estimation: < 1ms per request
- No network calls (uses cached pricing)
- Token counting: O(n) where n = total message characters
- Estimation accuracy: input ±10%, output overestimates (uses max-tokens)
