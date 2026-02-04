---
type: scenario
name: tool-definition-and-validation
version: 0.1.0
status: draft
feature: tools
test_evidence: tests/test-tools-support.lisp:34-62, tests/test-tools-enhanced.lisp:73-126
---

# Tool Definition and Validation

[DRAFT] - Extracted from test suite

## Overview

Tools are defined with name, description, parameters (typed with constraints), and optional enhanced features (safety levels, validators, approval requirements, lifecycle hooks).

## Scenario 1: Define Basic Tool

### Given

- Tool name: "search_web"
- Description: "Search the web for information"
- Parameters: Single parameter "query" of type string

### When

User creates tool via `define-tool`:

```lisp
(define-tool "search_web"
             "Search the web for information"
             '((:name "query"
                :type :string
                :description "Search query")))
```

### Then

- ✅ Tool object is created
- ✅ `tool-name` returns "search_web"
- ✅ `tool-description` returns description
- ✅ `tool-parameters` returns parameter list
- ✅ Tool passes validation

## Scenario 2: Define Tool with Required Parameters

### Given

- Tool requires certain parameters to function
- Optional parameters can be omitted

### When

```lisp
(define-tool "create_file"
             "Create a new file"
             '((:name "path" :type :string)
               (:name "content" :type :string)
               (:name "overwrite" :type :boolean))
             :required '("path" "content"))  ; overwrite is optional
```

### Then

- ✅ `tool-required-params` returns `'("path" "content")`
- ✅ LLM must provide required parameters
- ✅ Optional parameters can be omitted

## Scenario 3: Tool with No Parameters

### Given

- Tool that takes no input (e.g., "get_current_time")

### When

```lisp
(define-tool "get_current_time"
             "Get the current server time"
             nil)  ; No parameters
```

### Then

- ✅ Tool is created successfully
- ✅ `tool-parameters` returns `nil`
- ✅ Tool can be called without arguments

## Scenario 4: Tool with Multiple Parameter Types

### Given

- Tool needs parameters of different types

### When

```lisp
(define-tool "complex_query"
             "Execute complex database query"
             '((:name "table" :type :string)
               (:name "limit" :type :integer)
               (:name "score_threshold" :type :number)
               (:name "include_deleted" :type :boolean)
               (:name "tags" :type :array)
               (:name "options" :type :object)))
```

### Then

- ✅ All parameter types are preserved
- ✅ Each parameter's `:type` is accessible
- ✅ Types map to JSON Schema types during provider translation

**Supported Types**:
- `:string` → "string"
- `:integer` → "integer"
- `:number` → "number"
- `:boolean` → "boolean"
- `:array` → "array"
- `:object` → "object"

## Scenario 5: Parameter with Enum Constraints

### Given

- Parameter values must be from a predefined list

### When

```lisp
(define-tool "set_temperature"
             "Set thermostat temperature unit"
             '((:name "unit"
                :type :string
                :enum ("celsius" "fahrenheit" "kelvin"))))
```

### Then

- ✅ Parameter has `:enum` constraint
- ✅ LLM sees allowed values
- ✅ Validation can enforce enum membership

## Scenario 6: Tool with Parameter Validators

### Given

- Parameters need runtime validation beyond type checking

### When

```lisp
(define-tool "transfer_money"
             "Transfer money between accounts"
             '((:name "amount" :type :number)
               (:name "from_account" :type :string)
               (:name "to_account" :type :string))
             :required '("amount" "from_account" "to_account")
             :parameter-validators
             '(("amount" . (:type :number :min 0.01 :max 10000))
               ("from_account" . :non-empty-string)
               ("to_account" . :non-empty-string)))
```

### Then

- ✅ Validators are attached to tool
- ✅ Runtime validation enforces constraints
- ✅ Invalid values trigger `tool-validation-error`

**Built-in Validators**:
- `:positive-integer` - Integer > 0
- `:non-empty-string` - Non-blank string
- `:email` - Email format validation

**Custom Validators**:
- Plist: `(:type :number :min 0 :max 100)`
- Function: `(lambda (value) (> value 0))`
- Pattern: `(:pattern "^/tmp/")`
- Range: `(:min 0 :max 100)`
- Length: `(:min-length 3 :max-length 50)`
- Enum: `(:enum '("a" "b" "c"))`

## Scenario 7: Tool with Safety Level and Approval

### Given

- Tool performs dangerous operation requiring human approval

### When

```lisp
(define-tool "delete_file"
             "Delete a file from filesystem"
             '((:name "path" :type :string))
             :required '("path")
             :safety-level :dangerous
             :requires-approval :always
             :categories '(:filesystem :destructive))
```

### Then

- ✅ Tool has `:dangerous` safety level
- ✅ Tool requires approval before execution
- ✅ Tool is categorized for filtering
- ✅ Execution without approval triggers `tool-approval-required`

**Safety Levels**:
- `:safe` (0) - No side effects, read-only
- `:moderate` (1) - Reversible side effects
- `:dangerous` (2) - Irreversible or sensitive operations

**Approval Requirements**:
- `nil` - No approval needed
- `t` or `:always` - Always require approval
- `:if-dangerous` - Only if safety level is `:dangerous`

## Scenario 8: Tool with Lifecycle Hooks

### Given

- Tool execution should trigger logging or monitoring

### When

```lisp
(define-tool "api_call"
             "Call external API"
             '((:name "endpoint" :type :string))
             :on-start (lambda (tool-call arguments)
                        (log-api-call-start tool-call arguments))
             :on-complete (lambda (tool-call arguments result)
                           (log-api-call-complete result))
             :on-error (lambda (tool-call arguments condition)
                        (log-api-call-error condition)))
```

### Then

- ✅ `:on-start` is called before execution
- ✅ `:on-complete` is called after successful execution
- ✅ `:on-error` is called on execution failure
- ✅ Hooks receive tool-call, arguments, and result/error

## Validation Rules

### Tool Definition Validation

```lisp
(validate-tool-definition tool) → T or signals error
```

**Checks**:
1. Tool name must be non-empty string
2. Description must be string
3. Parameters must be list
4. Each parameter must have `:name` and `:type`
5. Parameter types must be valid (`:string`, `:integer`, `:number`, `:boolean`, `:array`, `:object`)
6. Required parameter names must be strings

**Signals**: `tool-schema-error` on validation failure

## Test Evidence

**Source**: `tests/test-tools-support.lisp:34-141`

```lisp
(fiveam:test create-simple-tool
  "Create a simple tool definition"
  (let ((tool (make-instance 'tool-definition
                             :name "test_tool"
                             :description "A test tool"
                             :parameters '((:name "param1" :type :string)))))
    (fiveam:is (string= (tool-name tool) "test_tool"))
    (fiveam:is (= (length (tool-parameters tool)) 1))))

(fiveam:test validate-valid-tool
  "Valid tool passes validation"
  (let ((tool (make-instance 'tool-definition
                            :name "valid_tool"
                            :description "A valid tool"
                            :parameters '((:name "p1" :type :string)))))
    (fiveam:is (validate-tool-definition tool))))
```

**Source**: `tests/test-tools-enhanced.lisp:73-126`

Validator tests demonstrate all built-in and custom validation scenarios.

## Acceptance Criteria

✅ Tools can be defined with varying complexity (0-N parameters)
✅ All parameter types are supported
✅ Enum constraints are preserved
✅ Required parameters are tracked
✅ Validation passes for well-formed tools
✅ Enhanced features (safety, approval, hooks, validators) are optional
✅ Parameter validators support multiple formats (function, plist, keyword)

## Related Scenarios

- [Tool Approval Workflows](./tool-approval-workflows.md) - Approval process
- [Tool Execution](./tool-execution.md) - Running tools
- [Parameter Validation](./parameter-validation.md) - Runtime validation

## Invariants

- **INV-TOOL-01**: Tool name must be unique within a registry
- **INV-TOOL-02**: All required parameters must be defined in parameters list
- **INV-TOOL-03**: Parameter types must be from valid enum
- **INV-TOOL-04**: Safety levels are ordered: safe < moderate < dangerous
