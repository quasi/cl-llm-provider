---
type: scenario
name: tool-result-handling
version: 0.1.0
feature: tools
covers:
  - tool-result
tags:
  - happy-path
  - tool-execution
---

# Tool Result - Construction and Handling

## Context

After executing a tool call, the result must be formatted correctly to send back to the LLM for continuation of the conversation.

## Scenario 1: Successful tool execution

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *tool-call* (make-instance 'tool-call
                                 :id "call_123"
                                 :name "get_weather"
                                 :arguments '(:location "Paris")))
```

### Steps

#### 1. Execute tool

**Action**: Simulate tool execution
```lisp
(defun execute-get-weather (location)
  (format nil "The weather in ~A is sunny, 22°C" location))

(setf *result-data* (execute-get-weather
                     (getf (tool-call-arguments *tool-call*) :location)))
```

**Expected**:
- Returns weather string
- No error raised

#### 2. Create tool result

**Action**: Construct result object
```lisp
(setf *tool-result* (make-tool-result (tool-call-id *tool-call*)
                                      *result-data*))
```

**Expected**:
- Returns tool-result object
- Contains call ID and result data
- `:is-error` is nil (default)

#### 3. Inspect result

**Action**: Extract result properties
```lisp
(list :id (tool-result-id *tool-result*)
      :content (tool-result-content *tool-result*)
      :is-error (tool-result-is-error *tool-result*))
```

**Expected**:
- ID matches tool-call ID ("call_123")
- Content is the weather string
- `is-error` is nil

### Verification

```
ASSERT (tool-result-id *tool-result*) == "call_123"
ASSERT (tool-result-content *tool-result*) includes "sunny"
ASSERT (tool-result-is-error *tool-result*) == nil
```

## Scenario 2: Tool execution error

### Setup

```lisp
(setf *tool-call* (make-instance 'tool-call
                                 :id "call_456"
                                 :name "divide"
                                 :arguments '(:a 10 :b 0)))
```

### Steps

#### 1. Execute tool with error

**Action**: Attempt division by zero
```lisp
(handler-case
    (let ((a (getf (tool-call-arguments *tool-call*) :a))
          (b (getf (tool-call-arguments *tool-call*) :b)))
      (/ a b))
  (division-by-zero (e)
    (setf *error-msg* (format nil "Error: ~A" e))))
```

**Expected**:
- Division error caught
- Error message stored

#### 2. Create error result

**Action**: Construct error result
```lisp
(setf *tool-result* (make-tool-result (tool-call-id *tool-call*)
                                      *error-msg*
                                      :is-error t))
```

**Expected**:
- Tool result created with error flag
- Contains error message

#### 3. Verify error flag

**Action**: Check is-error
```lisp
(tool-result-is-error *tool-result*)
```

**Expected**:
- Returns `t`
- Indicates error to LLM

### Verification

```
ASSERT (tool-result-is-error *tool-result*) == t
ASSERT (tool-result-content *tool-result*) includes "Error"
```

## Scenario 3: Continue conversation with tool result

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *messages* '((:role "user" :content "What's the weather in Paris?")))

;; First completion with tool call
(setf *response1* (complete *messages*
                            :provider *provider*
                            :tools (list (define-tool "get_weather" "Get weather"
                                                      '((:name "location" :type :string))))))

;; Tool was called
(setf *tool-call* (first (response-tool-calls *response1*)))
```

### Steps

#### 1. Execute tool

**Action**: Get weather data
```lisp
(setf *weather* "Sunny, 22°C")
(setf *tool-result* (make-tool-result (tool-call-id *tool-call*)
                                      *weather*))
```

#### 2. Build conversation history

**Action**: Append assistant message and tool result
```lisp
(setf *messages* (append *messages*
                         (list (response-message *response1*)
                               (tool-result-to-message *tool-result*))))
```

**Expected**:
- Messages now contain: user → assistant (tool call) → tool result
- Message format suitable for next completion

#### 3. Continue conversation

**Action**: Complete with tool result
```lisp
(setf *response2* (complete *messages*
                            :provider *provider*))
```

**Expected**:
- LLM receives tool result
- Generates natural language response
- Finish reason is `:stop` (not `:tool-calls`)

### Verification

```
ASSERT (response-finish-reason *response2*) == :stop
ASSERT (response-content *response2*) != nil
ASSERT (response-content *response2*) includes "22°C" or "sunny"
```

## Scenario 4: Multiple tool results

### Setup

```lisp
(setf *tool-calls* (list
                    (make-instance 'tool-call :id "call_1" :name "get_weather" :arguments nil)
                    (make-instance 'tool-call :id "call_2" :name "get_time" :arguments nil)))
```

### Steps

#### 1. Execute multiple tools

**Action**: Execute both tools
```lisp
(setf *results* (list
                 (make-tool-result "call_1" "Sunny, 22°C")
                 (make-tool-result "call_2" "14:30 JST")))
```

#### 2. Verify result count

**Action**: Check list length
```lisp
(length *results*)
```

**Expected**:
- Returns 2
- Each result has correct ID

#### 3. Map results to messages

**Action**: Convert to message format
```lisp
(mapcar #'tool-result-to-message *results*)
```

**Expected**:
- Returns list of 2 messages
- Each message has role "tool"
- IDs match original tool calls

### Verification

```
ASSERT (length *results*) == 2
ASSERT all results have unique IDs matching tool calls
```

## Scenario 5: Structured result data

### Setup

```lisp
(setf *tool-call* (make-instance 'tool-call
                                 :id "call_789"
                                 :name "search_database"
                                 :arguments nil))
```

### Steps

#### 1. Generate structured result

**Action**: Return JSON/plist result
```lisp
(setf *search-results* '(:results ((:title "Doc 1" :score 0.95)
                                  (:title "Doc 2" :score 0.87))
                        :total 2))
```

#### 2. Serialize for tool result

**Action**: Convert to string representation
```lisp
(setf *serialized* (format nil "~S" *search-results*))
(setf *tool-result* (make-tool-result (tool-call-id *tool-call*)
                                      *serialized*))
```

**Expected**:
- Tool result contains serialized data
- LLM can parse the structure

### Verification

```
ASSERT (tool-result-content *tool-result*) includes "Doc 1"
ASSERT (tool-result-content *tool-result*) includes "0.95"
```

## Performance Criteria

- Tool result creation: < 1ms
- Serialization overhead: < 5ms for typical results
- No memory leaks on repeated result creation
- Message conversion: O(1) for single result, O(n) for n results
