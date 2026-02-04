---
type: contract
name: tool-validation
version: 0.1.0
status: draft
feature: tools
depends_on:
  - features/tools/contracts/tool-definition
  - features/tools/contracts/tool-call
  - core/foundation/vocabulary#validation
---

# Tool Validation Contract

This contract defines the parameter validation system for tool calls, including built-in validators, custom validators, and validation specifications.

## Overview

Tool validation ensures that arguments passed to tool calls conform to defined schemas and constraints before execution. It supports built-in validators, custom functions, declarative specs, and composite validation.

## Built-in Validators

### Numeric Validators

| Validator | Type | Constraint |
|-----------|------|------------|
| `:positive-integer` | integer | `> 0` |
| `:non-negative-integer` | integer | `>= 0` |
| `:positive-number` | number | `> 0` |
| `:non-negative-number` | number | `>= 0` |

### String Validators

| Validator | Type | Constraint |
|-----------|------|------------|
| `:string` | string | Any string |
| `:non-empty-string` | string | Length > 0 |
| `:email` | string | Valid email format |
| `:url` | string | Starts with `http://` or `https://` |

### Type Validators

| Validator | Type | Constraint |
|-----------|------|------------|
| `:boolean` | boolean | `t` or `nil` |
| `:integer` | integer | Any integer |
| `:number` | number | Any number |

## Validator Specification Formats

### Named Validator

Use a built-in validator keyword:

```lisp
:parameter-validators '(("age" . :positive-integer)
                        ("email" . :email))
```

### Custom Function

Provide a lambda that returns boolean:

```lisp
:parameter-validators
  '(("password" . ,(lambda (v)
                     (and (stringp v)
                          (>= (length v) 8)))))
```

### Declarative Spec

Use a plist with validation constraints:

```json-schema
{
  "type": "object",
  "properties": {
    "type": {
      "type": "string",
      "enum": ["integer", "string", "number"],
      "description": "Parameter type to validate"
    },
    "min": {
      "type": "number",
      "description": "Minimum value (for numbers)"
    },
    "max": {
      "type": "number",
      "description": "Maximum value (for numbers)"
    },
    "min-length": {
      "type": "integer",
      "description": "Minimum length (for strings/sequences)"
    },
    "max-length": {
      "type": "integer",
      "description": "Maximum length (for strings/sequences)"
    },
    "pattern": {
      "type": "string",
      "description": "Regex pattern (for strings)"
    },
    "enum": {
      "type": "array",
      "description": "List of allowed values"
    }
  }
}
```

**Examples**:

```lisp
;; Range validation
'(("age" . (:type :integer :min 0 :max 120)))

;; String length
'(("username" . (:type :string :min-length 3 :max-length 20)))

;; Pattern matching
'(("zip_code" . (:pattern "^\\d{5}$")))

;; Enum validation
'(("status" . (:enum ("active" "inactive" "pending"))))
```

## Validator Factory Functions

### `make-range-validator`

```lisp
(make-range-validator min max) → validator-function
```

Create a validator for numeric range `[min, max]`. Either can be `nil` for open-ended ranges.

**Example**:
```lisp
(make-range-validator 0 100)  ; 0 <= value <= 100
(make-range-validator 0 nil)  ; value >= 0
(make-range-validator nil 100) ; value <= 100
```

### `make-pattern-validator`

```lisp
(make-pattern-validator pattern) → validator-function
```

Create a validator for regex pattern matching.

**Example**:
```lisp
(make-pattern-validator "^[A-Z]{2}\\d{4}$")  ; State code format
```

### `make-length-validator`

```lisp
(make-length-validator &key min-length max-length) → validator-function
```

Create a validator for string/sequence length.

**Example**:
```lisp
(make-length-validator :min-length 8 :max-length 64)  ; Password length
```

### `make-enum-validator`

```lisp
(make-enum-validator allowed-values &key test) → validator-function
```

Create a validator for enumerated values.

**Example**:
```lisp
(make-enum-validator '("red" "green" "blue") :test #'string=)
```

### `make-type-validator`

```lisp
(make-type-validator type-spec) → validator-function
```

Create a validator using Common Lisp `typep`.

**Example**:
```lisp
(make-type-validator '(integer 0 100))  ; Integer between 0 and 100
```

### `make-composite-validator`

```lisp
(make-composite-validator &rest validators) → validator-function
```

Create a validator requiring ALL sub-validators to pass.

**Example**:
```lisp
(make-composite-validator
  (make-type-validator 'string)
  (make-length-validator :min-length 8)
  (make-pattern-validator ".*[0-9].*"))  ; String, length >= 8, contains digit
```

## Validation Execution

### Generic Function: `validate-tool-arguments`

```lisp
(validate-tool-arguments tool-definition arguments) → boolean
```

Validate that `arguments` conform to the tool's parameter validators.

**Returns**:
- `t` if all validations pass
- Signals `tool-validation-error` on first validation failure

**Error Information**:
- `:tool` - tool-definition object
- `:parameter` - name of failing parameter
- `:value` - invalid value
- `:validator` - validator that failed

### Validation Order

1. **Type checking**: Verify parameter types match schema
2. **Required parameters**: Check all required parameters present
3. **Custom validators**: Run parameter-specific validators
4. **Enum constraints**: Validate against allowed values
5. **Range constraints**: Check numeric bounds
6. **Pattern matching**: Validate string patterns

## Usage Examples

### Basic Validation

```lisp
(define-tool "create_user"
  "Create a new user account"
  '((:name "username" :type :string :description "Username")
    (:name "age" :type :integer :description "User age")
    (:name "email" :type :string :description "Email address"))
  :required '("username" "email")
  :parameter-validators
    '(("username" . (:min-length 3 :max-length 20))
      ("age" . :positive-integer)
      ("email" . :email)))
```

### Complex Validation

```lisp
(define-tool "schedule_task"
  "Schedule a task for execution"
  '((:name "task_name" :type :string :description "Task name")
    (:name "delay" :type :integer :description "Delay in seconds")
    (:name "priority" :type :integer :description "Priority level"))
  :required '("task_name")
  :parameter-validators
    `(("task_name" . ,(make-composite-validator
                        (make-type-validator 'string)
                        (make-length-validator :min-length 1 :max-length 50)
                        (make-pattern-validator "^[a-zA-Z0-9_-]+$")))
      ("delay" . (:min 0 :max 86400))   ; Max 1 day
      ("priority" . (:enum (1 2 3 4 5)))))
```

## Error Handling

### Condition: `tool-validation-error`

Signaled when validation fails.

**Slots**:
- `tool` - tool-definition that failed validation
- `parameter` - parameter name that failed
- `value` - the invalid value
- `validator` - validator that rejected the value
- `message` - human-readable error message

**Restart**:
- `:use-value` - Provide corrected value
- `:skip-validation` - Proceed without validation (dangerous)
- `:abort-tool-call` - Cancel tool execution

### Example Error Handling

```lisp
(handler-case
    (validate-tool-arguments tool args)
  (tool-validation-error (e)
    (format t "Validation failed for ~A: ~A~%"
            (validation-error-parameter e)
            (validation-error-message e))
    (invoke-restart 'abort-tool-call)))
```

## Invariants

1. **Validator determinism**: Validators MUST be deterministic (same input → same output)
2. **No side effects**: Validators MUST NOT modify the value or have external side effects
3. **Boolean return**: Validators MUST return boolean (`t` or `nil`)
4. **Required before optional**: Required parameter validation happens before optional parameters
5. **Fail-fast**: Validation stops at first failure

## Best Practices

1. **Specific messages**: Include helpful error messages explaining why validation failed
2. **Whitelist over blacklist**: Use `:enum` to specify allowed values rather than rejecting bad ones
3. **Layered validation**: Use composite validators for complex constraints
4. **Performance**: Keep validators fast (< 1ms); avoid expensive operations
5. **Clear failure reasons**: Make validation errors actionable for debugging

## Related Contracts

- [tool-definition.md](./tool-definition.md) - Defining tools with validators
- [tool-call.md](./tool-call.md) - Tool invocation
- [tool-approval.md](./tool-approval.md) - Approval workflow

## Implementation Notes

- Built-in validators are defined in `*built-in-validators*` plist
- Declarative specs are parsed into validator functions at tool creation time
- Validation happens before approval (validate → approve → execute)
- Composite validators use AND semantics (all must pass)
