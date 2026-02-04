---
type: scenario
name: model-metadata-lookup
version: 0.1.0
feature: model-metadata
tags:
  - happy-path
  - introspection
---

# Model Metadata Lookup

## Context

User needs to retrieve model capabilities, limits, and pricing before making API requests for validation and cost estimation.

## Scenario 1: Lookup known model metadata

### Setup

```lisp
(setf *provider* (make-provider :openai))
```

### Steps

#### 1. Query model metadata

**Action**: Get metadata for GPT-4o
```lisp
(setf *metadata* (model-metadata *provider* "gpt-4o"))
```

**Expected**:
- Returns metadata plist
- Contains all required fields
- Values are reasonable

#### 2. Check context window

**Action**: Extract context window
```lisp
(getf *metadata* :context-window)
```

**Expected**:
- Returns positive integer
- Value = 128000 (for GPT-4o)

#### 3. Check tool support

**Action**: Check if tools supported
```lisp
(getf *metadata* :supports-tools)
```

**Expected**:
- Returns T (GPT-4o supports tools)

#### 4. Check pricing

**Action**: Extract pricing
```lisp
(list :input (getf *metadata* :input-cost-per-1m-tokens)
      :output (getf *metadata* :output-cost-per-1m-tokens))
```

**Expected**:
- Input cost > 0
- Output cost > input cost (typical)
- Values are reasonable (< $100 per 1M tokens)

### Verification

```
ASSERT *metadata* != NIL
ASSERT (getf *metadata* :context-window) == 128000
ASSERT (getf *metadata* :max-output-tokens) == 16384
ASSERT (getf *metadata* :supports-tools) == T
ASSERT (getf *metadata* :supports-vision) == T
ASSERT (getf *metadata* :input-cost-per-1m-tokens) > 0
ASSERT (getf *metadata* :output-cost-per-1m-tokens) > 0
```

## Scenario 2: Lookup unknown model

### Setup

```lisp
(setf *provider* (make-provider :openai))
```

### Steps

#### 1. Query unknown model

**Action**: Request metadata for non-existent model
```lisp
(model-metadata *provider* "unknown-model-xxx")
```

**Expected**:
- Returns NIL
- No error raised

#### 2. Handle missing metadata

**Action**: Use fallback for unknown model
```lisp
(or (model-metadata *provider* "unknown-model-xxx")
    '(:context-window 4096
      :max-output-tokens 4096
      :supports-tools nil
      :supports-vision nil
      :input-cost-per-1m-tokens 0.0
      :output-cost-per-1m-tokens 0.0))
```

**Expected**:
- Fallback metadata used
- Conservative defaults applied

### Verification

```
ASSERT (model-metadata *provider* "unknown-model-xxx") == NIL
ASSERT fallback metadata is used
```

## Scenario 3: Validate request against context window

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *messages* (list (:role "user" :content (make-string 100000 :initial-element #\a))))
(setf *model* "gpt-4o")
```

### Steps

#### 1. Get context limit

**Action**: Lookup model metadata
```lisp
(setf *metadata* (model-metadata *provider* *model*))
(setf *ctx-limit* (getf *metadata* :context-window))
```

#### 2. Count input tokens

**Action**: Estimate tokens in messages
```lisp
(setf *input-tokens* (count-tokens *messages*))
```

#### 3. Validate against limit

**Action**: Check if input fits
```lisp
(if (> *input-tokens* *ctx-limit*)
    (error "Input (~D tokens) exceeds context window (~D tokens)"
           *input-tokens* *ctx-limit*)
    t)
```

**Expected**:
- Validation detects overflow (100K chars ≈ 25K tokens > some models)
- Error message clear and actionable

### Verification

```
ASSERT *ctx-limit* > 0
ASSERT validation correctly detects overflow
```

## Scenario 4: Check model capabilities

### Setup

```lisp
(setf *provider* (make-provider :openai))
```

### Steps

#### 1. Check tool support before using tools

**Action**: Validate model supports tools
```lisp
(let ((metadata (model-metadata *provider* "gpt-4o")))
  (unless (getf metadata :supports-tools)
    (error "Model doesn't support tools")))
```

**Expected**:
- GPT-4o metadata shows `:supports-tools` = T
- No error raised

#### 2. Check vision support before sending images

**Action**: Validate model supports vision
```lisp
(let ((metadata (model-metadata *provider* "gpt-3.5-turbo")))
  (when (and has-images (not (getf metadata :supports-vision)))
    (warn "Model doesn't support vision inputs")))
```

**Expected**:
- GPT-3.5 metadata shows `:supports-vision` = NIL
- Warning issued if images present

### Verification

```
ASSERT capability checks correctly identify model features
ASSERT appropriate errors/warnings raised
```

## Scenario 5: Compare models by metadata

### Setup

```lisp
(setf *provider* (make-provider :openai))
```

### Steps

#### 1. Gather metadata for multiple models

**Action**: Query metadata for model comparison
```lisp
(setf *models* '("gpt-4o" "gpt-4o-mini" "gpt-3.5-turbo"))
(setf *comparison*
      (loop for model in *models*
            for meta = (model-metadata *provider* model)
            collect (list :model model
                         :ctx (getf meta :context-window)
                         :cost (getf meta :input-cost-per-1m-tokens))))
```

**Expected**:
- All models have metadata
- Comparison shows different capabilities/costs

#### 2. Select cheapest model

**Action**: Find lowest cost model
```lisp
(reduce (lambda (a b)
          (if (< (getf a :cost) (getf b :cost)) a b))
        *comparison*)
```

**Expected**:
- Returns model with lowest input cost
- Enables cost-aware model selection

### Verification

```
ASSERT (length *comparison*) == 3
ASSERT all entries have :model, :ctx, :cost
ASSERT costs vary between models
```

## Performance Criteria

- Metadata lookup: O(1) hash table access
- Lookup time < 1μs
- No network calls (all cached locally)
- Memory: ~200 bytes per model entry
