---
type: scenario
name: tool-call-basic
version: 0.1.0
feature: tools
covers:
  - tool-call
tags:
  - happy-path
  - tool-calling
---

# Tool Call - Basic Invocation

## Context

LLM requests to call a tool in response to a user query. The system must extract and parse the tool call from the response.

## Scenario 1: Single tool call

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *tool* (define-tool "get_weather"
                          "Get current weather for a location"
                          '((:name "location" :type :string :required t))))
(setf *messages* '((:role "user" :content "What's the weather in Paris?")))
```

### Steps

#### 1. Request completion with tools

**Action**: Call complete with tool definition
```lisp
(setf *response* (complete *messages*
                           :provider *provider*
                           :tools (list *tool*)))
```

**Expected**:
- Response has finish-reason `:tool-calls`
- `response-content` is nil
- `response-tool-calls` is non-nil list

#### 2. Extract tool calls

**Action**: Get tool calls from response
```lisp
(setf *tool-calls* (response-tool-calls *response*))
(setf *call* (first *tool-calls*))
```

**Expected**:
- `*tool-calls*` length = 1
- `*call*` is a tool-call object

#### 3. Inspect tool call

**Action**: Extract call details
```lisp
(list :id (tool-call-id *call*)
      :name (tool-call-name *call*)
      :args (tool-call-arguments *call*))
```

**Expected**:
- `tool-call-id` is non-empty string
- `tool-call-name` = "get_weather"
- `tool-call-arguments` is plist or hash-table
- Arguments contain `location` key with value "Paris"

### Verification

```
ASSERT (response-finish-reason *response*) == :tool-calls
ASSERT (response-content *response*) == nil
ASSERT (length (response-tool-calls *response*)) == 1
ASSERT (tool-call-name *call*) == "get_weather"
ASSERT (getf (tool-call-arguments *call*) :location) includes "Paris"
```

## Scenario 2: Multiple tool calls

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *tools* (list
               (define-tool "get_weather" "Get weather" '((:name "location" :type :string)))
               (define-tool "get_time" "Get time" '((:name "timezone" :type :string)))))
(setf *messages* '((:role "user" :content "What's the weather and time in Tokyo?")))
```

### Steps

#### 1. Request with multiple tools

**Action**: Complete with multiple tool definitions
```lisp
(setf *response* (complete *messages*
                           :provider *provider*
                           :tools *tools*))
```

**Expected**:
- Finish reason `:tool-calls`
- Multiple tool calls returned

#### 2. Extract all tool calls

**Action**: Get tool calls
```lisp
(setf *calls* (response-tool-calls *response*))
(mapcar #'tool-call-name *calls*)
```

**Expected**:
- Returns list of 2 tool call names
- Contains both "get_weather" and "get_time"

### Verification

```
ASSERT (length (response-tool-calls *response*)) == 2
ASSERT tool-call-names include "get_weather" and "get_time"
```

## Scenario 3: Tool call with complex arguments

### Setup

```lisp
(setf *tool* (define-tool "search"
                          "Search database"
                          '((:name "query" :type :string)
                            (:name "filters" :type :object)
                            (:name "limit" :type :integer))))
```

### Steps

#### 1. Request with complex tool

**Action**: Complete with multi-parameter tool
```lisp
(setf *response* (complete '((:role "user" :content "Search for blue shirts under $50, limit 10"))
                           :provider *provider*
                           :tools (list *tool*)))
```

#### 2. Extract arguments

**Action**: Get parsed arguments
```lisp
(let ((call (first (response-tool-calls *response*))))
  (tool-call-arguments call))
```

**Expected**:
- Arguments is structured data
- Contains `query`, `filters`, and `limit` keys
- Types match definition (string, object, integer)

### Verification

```
ASSERT arguments contain :query, :filters, :limit
ASSERT (integerp (getf arguments :limit))
ASSERT (getf arguments :limit) == 10
```

## Performance Criteria

- Tool call extraction: < 1ms
- Argument parsing: < 5ms
- No network calls (all client-side parsing)
