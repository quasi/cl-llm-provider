# Enhanced Tools API Reference

Complete API reference for cl-llm-provider.tools module.

## Table of Contents

- [Categories](#categories)
- [Safety Levels](#safety-levels)
- [Validators](#validators)
- [Tool Registry](#tool-registry)
- [Approval System](#approval-system)
- [Lifecycle Hooks](#lifecycle-hooks)
- [Tool Execution](#tool-execution)
- [Conditions](#conditions)

## Categories

### Variables

#### `*tool-categories*`
**Type**: List of keywords

Predefined tool categories. Read-only constant.

**Value**:
```lisp
(:search :database :filesystem :network :calculation :destructive
 :authentication :payment :admin :external-api :ai :messaging)
```

### Functions

#### `valid-category-p` (category)
**Returns**: Boolean

Check if a category keyword is valid (predefined or custom).

```lisp
(valid-category-p :search)          ; => T
(valid-category-p :custom)          ; => T (custom allowed)
(valid-category-p "string")         ; => NIL
(valid-category-p 123)              ; => NIL
```

#### `normalize-categories` (categories)
**Arguments**:
- `categories`: Keyword, list of keywords, or nil

**Returns**: List of keywords

Convert category spec to normalized list.

```lisp
(normalize-categories nil)                    ; => NIL
(normalize-categories :search)                ; => (:search)
(normalize-categories '(:search :database))   ; => (:search :database)
```

---

## Safety Levels

### Constants

Three predefined safety levels with ordering:

| Level | Value | Meaning |
|-------|-------|---------|
| `:safe` | 0 | No risk, read-only operations |
| `:moderate` | 1 | May modify data or access system |
| `:dangerous` | 2 | Irreversible operations |

### Functions

#### `safety-level-value` (level)
**Returns**: Integer (0, 1, or 2)

Get numeric value of safety level for comparison.

```lisp
(safety-level-value :safe)         ; => 0
(safety-level-value :moderate)      ; => 1
(safety-level-value :dangerous)     ; => 2
```

#### `safety-level<=` (level1 level2)
**Returns**: Boolean

Check if level1 is less than or equal to level2 in safety ordering.

```lisp
(safety-level<= :safe :moderate)        ; => T
(safety-level<= :dangerous :safe)       ; => NIL
(safety-level<= :moderate :moderate)    ; => T
```

---

## Validators

### Variables

#### `*built-in-validators*`
**Type**: List of keywords

Available built-in validator names.

### Functions

#### `make-range-validator` (min max)
**Arguments**:
- `min`: Number
- `max`: Number

**Returns**: Validator function

Create validator checking if value is in range [min, max].

```lisp
(let ((v (make-range-validator 0 100)))
  (funcall v 50))   ; => T
  (funcall v 150))  ; => NIL
```

#### `make-pattern-validator` (regex-pattern)
**Arguments**:
- `regex-pattern`: String (PCRE regex)

**Returns**: Validator function

Create validator checking if string matches regex pattern.

```lisp
(let ((v (make-pattern-validator "^[a-z]+$")))
  (funcall v "hello"))   ; => T
  (funcall v "Hello"))   ; => NIL
```

#### `make-length-validator` (&key min-length max-length)
**Arguments**:
- `min-length`: Integer (optional)
- `max-length`: Integer (optional)

**Returns**: Validator function

Create validator checking string/sequence length.

```lisp
(let ((v (make-length-validator :min-length 3 :max-length 10)))
  (funcall v "hello"))     ; => T
  (funcall v "hi"))        ; => NIL
  (funcall v "too long"))  ; => NIL
```

#### `make-enum-validator` (allowed-values)
**Arguments**:
- `allowed-values`: List

**Returns**: Validator function

Create validator checking if value is in allowed set.

```lisp
(let ((v (make-enum-validator '("a" "b" "c"))))
  (funcall v "a"))   ; => T
  (funcall v "d"))   ; => NIL
```

#### `make-type-validator` (type-spec)
**Arguments**:
- `type-spec`: Keyword (:string, :integer, :number, :boolean, etc.)

**Returns**: Validator function

Create validator checking if value matches type.

```lisp
(let ((v (make-type-validator :integer)))
  (funcall v 42))     ; => T
  (funcall v "42"))   ; => NIL
```

#### `make-composite-validator` (&rest validators)
**Arguments**:
- `validators`: Multiple validator functions

**Returns**: Validator function

Create validator that requires ALL validators to pass.

```lisp
(let ((v (make-composite-validator
           (make-pattern-validator "^/tmp/")
           (make-length-validator :max-length 256))))
  (funcall v "/tmp/file.txt"))    ; => T
  (funcall v "/home/file.txt"))   ; => NIL
```

#### `parse-validator-spec` (spec)
**Arguments**:
- `spec`: Function | Keyword | Plist

**Returns**: Validator function

Convert various validator specs to validator function.

```lisp
;; From function
(parse-validator-spec (lambda (x) (> x 0)))

;; From keyword (built-in)
(parse-validator-spec :positive-integer)

;; From plist spec
(parse-validator-spec '(:type :integer :min 0 :max 100))
```

#### `validate-parameter` (validator param-name value)
**Arguments**:
- `validator`: Validator function
- `param-name`: String
- `value`: Any value

**Signals**: `tool-validation-error` on failure

**Returns**: Value if valid

Validate single parameter, signal error if invalid.

#### `validate-tool-arguments` (tool-definition arguments)
**Arguments**:
- `tool-definition`: Tool definition object
- `arguments`: Plist of arguments

**Signals**: `tool-validation-error` on failure

**Returns**: Nil if valid

Validate all arguments for a tool.

---

## Tool Registry

### Classes

#### `tool-registry`
**Slots**:
- `name` (reader: `registry-name`)
- `tools` (reader: `registry-tools`)
- `default-safety-level` (accessor: `registry-default-safety-level`)
- `approval-callback` (accessor: `registry-approval-callback`)
- `global-hooks` (accessor: `registry-global-hooks`)

### Variables

#### `*tool-registry*`
Global tool registry instance.

### Functions

#### `make-tool-registry` (&key name default-safety-level approval-callback)
**Arguments**:
- `name`: String (default "default")
- `default-safety-level`: Keyword (default :safe)
- `approval-callback`: Function (optional)

**Returns**: `tool-registry` instance

Create new tool registry.

```lisp
(make-tool-registry :name "my-app"
                    :default-safety-level :moderate)
```

#### `ensure-registry` ()
**Returns**: `tool-registry`

Get or create global registry.

```lisp
(ensure-registry)
```

#### `registry-tool-count` (registry)
**Returns**: Integer

Get number of tools in registry.

```lisp
(registry-tool-count *tools*)  ; => 5
```

#### `register-tool` (registry tool &key replace)
**Arguments**:
- `registry`: `tool-registry`
- `tool`: Tool definition
- `replace`: Boolean (default nil)

**Returns**: Tool definition

Register tool in registry. Signals error if already exists unless replace=t.

```lisp
(register-tool *registry* search-tool)
(register-tool *registry* new-tool :replace t)
```

#### `register` (tool &key registry replace)
**Arguments**:
- `tool`: Tool definition
- `registry`: `tool-registry` (default global)
- `replace`: Boolean

**Returns**: Tool definition

Convenience function to register tool.

```lisp
(register search-tool :registry *my-registry*)
```

#### `unregister-tool` (registry tool-name)
**Arguments**:
- `registry`: `tool-registry`
- `tool-name`: String

**Returns**: Nil

Unregister tool by name.

```lisp
(unregister-tool *registry* "old_tool")
```

#### `find-tool` (registry tool-name)
**Arguments**:
- `registry`: `tool-registry`
- `tool-name`: String

**Returns**: Tool definition or NIL

Find tool by name.

```lisp
(find-tool *registry* "search_db")
```

#### `find-tool-by-name` (name &key registry)
**Arguments**:
- `name`: String
- `registry`: `tool-registry` (default global)

**Returns**: Tool definition or NIL

Convenience function to find tool.

```lisp
(find-tool-by-name "search_db" :registry *my-registry*)
```

#### `list-tools` (registry &key categories safety-level)
**Arguments**:
- `registry`: `tool-registry`
- `categories`: List of keywords (optional)
- `safety-level`: Keyword (optional)

**Returns**: List of tool definitions

List tools with optional filtering.

```lisp
(list-tools *registry*)
(list-tools *registry* :categories '(:database))
(list-tools *registry* :safety-level :safe)
```

#### `search-tools` (registry &key name-pattern description-pattern categories safety-level max-safety-level)
**Arguments**:
- `registry`: `tool-registry`
- `name-pattern`: String regex (optional)
- `description-pattern`: String regex (optional)
- `categories`: List of keywords (optional)
- `safety-level`: Keyword (optional)
- `max-safety-level`: Keyword (optional)

**Returns**: List of matching tools

Search tools by multiple criteria.

```lisp
(search-tools *registry* :categories '(:database :search))
(search-tools *registry* :max-safety-level :moderate)
(search-tools *registry* :name-pattern "search.*")
```

#### `tools-by-category` (category &key registry)
**Arguments**:
- `category`: Keyword
- `registry`: `tool-registry` (default global)

**Returns**: List of tools in category

Get all tools with given category.

```lisp
(tools-by-category :database :registry *my-registry*)
```

#### `safe-tools` (&key registry)
**Arguments**:
- `registry`: `tool-registry` (default global)

**Returns**: List of safe tools

Get all tools with :safe safety level.

```lisp
(safe-tools :registry *my-registry*)
```

#### `tools-for-llm` (&key registry max-safety-level categories)
**Arguments**:
- `registry`: `tool-registry` (default global)
- `max-safety-level`: Keyword (default :safe)
- `categories`: List of keywords (optional)

**Returns**: List of filtered tools

Get tools suitable for LLM with safety filtering.

```lisp
(tools-for-llm :registry *registry* :max-safety-level :moderate)
```

---

## Approval System

### Functions

#### `needs-approval-p` (tool-definition)
**Returns**: Boolean

Check if tool requires approval before execution.

```lisp
(needs-approval-p dangerous-tool)  ; => T
(needs-approval-p safe-tool)       ; => NIL
```

#### `request-tool-approval` (tool-definition tool-call arguments &key callback)
**Arguments**:
- `tool-definition`: Tool definition
- `tool-call`: Tool call object
- `arguments`: Plist of arguments
- `callback`: Approval callback (optional)

**Signals**: `tool-approval-required` if no callback

**Returns**: (values decision arguments reason)

Request approval for tool execution.

#### `normalize-approval-result` (result original-arguments)
**Arguments**:
- `result`: Callback return value
- `original-arguments`: Original plist

**Returns**: (values decision arguments reason)

Normalize various callback formats to standard format.

**Result formats**:
- `T` or `:approved` → `:approved`
- `NIL` or `:rejected` → `:rejected`
- `(list :approved)` → `:approved`
- `(list :approved new-args)` → `:approved` with new args
- `(list :rejected reason)` → `:rejected` with reason
- `(list :edited new-args)` → `:edited` with new args

#### `make-auto-approve-callback` (&key log-fn)
**Arguments**:
- `log-fn`: Function (optional)

**Returns**: Approval callback

Create callback that auto-approves all requests.

```lisp
(make-auto-approve-callback :log-fn (lambda (msg) (print msg)))
```

#### `make-auto-reject-callback` (&key reason)
**Arguments**:
- `reason`: String (default "Automatic rejection")

**Returns**: Approval callback

Create callback that auto-rejects all requests.

```lisp
(make-auto-reject-callback :reason "Not authorized")
```

#### `make-safety-based-callback` (&key max-level on-exceed rejection-reason)
**Arguments**:
- `max-level`: Keyword (default :moderate)
- `on-exceed`: :reject or :prompt
- `rejection-reason`: String (optional)

**Returns**: Approval callback

Create callback that approves based on safety level.

```lisp
(make-safety-based-callback :max-level :moderate
                            :on-exceed :reject)
```

#### `make-interactive-approval-callback` (&key stream)
**Arguments**:
- `stream`: Stream (default *query-io*)

**Returns**: Approval callback

Create interactive callback for REPL use.

```lisp
(make-interactive-approval-callback :stream *standard-input*)
```

---

## Lifecycle Hooks

### Functions

#### `invoke-tool-hook` (hook-type tool-definition tool-call &rest args)
**Arguments**:
- `hook-type`: :on-start | :on-complete | :on-error
- `tool-definition`: Tool definition
- `tool-call`: Tool call object
- `args`: Additional arguments

**Returns**: Hook result (or nil if error)

Invoke lifecycle hook on tool. Errors in hooks are logged but don't interrupt execution.

**Hook signatures**:
- `:on-start`: (tool-call arguments)
- `:on-complete`: (tool-call arguments result)
- `:on-error`: (tool-call arguments condition)

#### `make-logging-hook` (hook-type &key stream format-fn)
**Arguments**:
- `hook-type`: :on-start | :on-complete | :on-error
- `stream`: Output stream (default *standard-output*)
- `format-fn`: Custom format function (optional)

**Returns**: Hook function

Create hook that logs execution info.

```lisp
(make-logging-hook :on-start :stream *trace-output*)
```

#### `make-timing-hook` (&key on-start-action on-complete-action)
**Arguments**:
- `on-start-action`: Function (tool-call, time)
- `on-complete-action`: Function (tool-call, duration-ms)

**Returns**: Plist with :on-start and :on-complete hooks

Create hooks that track execution timing.

```lisp
(let ((hooks (make-timing-hook
              :on-complete-action (lambda (call dur)
                                    (format t "~A took ~Dms~%"
                                            (tool-call-name call) dur)))))
  (setf (registry-global-hooks *registry*) hooks))
```

#### `combine-hooks` (hook-type &rest hooks)
**Arguments**:
- `hook-type`: :on-start | :on-complete | :on-error
- `hooks`: Multiple hook functions

**Returns**: Combined hook function

Combine multiple hooks of same type. All hooks called in order; errors in one don't prevent others.

```lisp
(combine-hooks :on-start
               (make-logging-hook :on-start)
               (lambda (call args) (record-metrics call)))
```

---

## Tool Execution

### Classes

#### `tool-execution-context`
**Slots**:
- `context-tool-call` (reader)
- `context-tool-definition` (reader)
- `context-arguments` (accessor)
- `context-approval-status` (accessor)
- `context-edited-arguments` (accessor)
- `context-result` (accessor)
- `context-error` (accessor)
- `context-start-time` (accessor)
- `context-end-time` (accessor)

Tracks tool execution state and results.

### Functions

#### `execute-tool` (tool-definition tool-call &key registry skip-approval skip-validation approval-callback max-safety-level)
**Arguments**:
- `tool-definition`: Tool to execute
- `tool-call`: Tool call from LLM
- `registry`: `tool-registry` (optional)
- `skip-approval`: Boolean (default nil)
- `skip-validation`: Boolean (default nil)
- `approval-callback`: Function (optional)
- `max-safety-level`: Keyword (optional)

**Signals**:
- `tool-safety-violation`: Tool exceeds max-safety-level
- `tool-validation-error`: Argument validation fails
- `tool-approval-error`: Approval rejected

**Returns**: Tool execution result

Execute tool with full lifecycle: validation → safety check → approval → on-start hook → handler → on-complete/on-error hook.

```lisp
(execute-tool tool call
              :registry *registry*
              :max-safety-level :moderate
              :approval-callback callback)
```

#### `execute-tool-calls` (response &key registry skip-approval skip-validation approval-callback max-safety-level on-missing-tool)
**Arguments**:
- `response`: Completion response with tool calls
- `registry`: `tool-registry`
- `skip-approval`: Boolean
- `skip-validation`: Boolean
- `approval-callback`: Function (optional)
- `max-safety-level`: Keyword (optional)
- `on-missing-tool`: :error | :skip | Function

**Returns**: List of (tool-call . result) pairs

Execute all tool calls from LLM response.

```lisp
(let ((results (execute-tool-calls response
                                    :registry *registry*
                                    :max-safety-level :safe)))
  (dolist ((call . result) results)
    (format t "~A => ~S~%" (tool-call-name call) result)))
```

#### `execution-results-to-tool-messages` (results)
**Arguments**:
- `results`: List of (tool-call . result) pairs

**Returns**: List of tool result message plists

Convert execution results to tool messages for LLM continuation.

```lisp
(let ((results (execute-tool-calls response :registry *registry*)))
  (let ((messages (execution-results-to-tool-messages results)))
    (complete (append conversation messages))))
```

---

## Conditions

All conditions inherit from `llm-provider-error`.

### `tool-validation-error`
**Slots**:
- `error-tool`: Tool definition
- `error-parameter`: Parameter name
- `error-value`: Invalid value
- `error-reason`: Error reason

Raised when parameter validation fails.

```lisp
(handler-case (execute-tool tool call)
  (tool-validation-error (e)
    (format t "Invalid ~A: ~A~%"
            (error-parameter e) (error-value e))))
```

### `tool-approval-error`
**Slots**:
- `error-tool`: Tool definition
- `error-tool-call`: Tool call object
- `error-reason`: Rejection reason

Raised when tool execution is not approved.

```lisp
(handler-case (execute-tool tool call)
  (tool-approval-error (e)
    (format t "Approval rejected~%")))
```

### `tool-approval-required`
**Slots**:
- `error-tool`: Tool definition
- `error-tool-call`: Tool call object

Raised when approval is needed but no callback available.

### `tool-safety-violation`
**Slots**:
- `error-tool`: Tool definition
- `error-required-level`: Max allowed safety level
- `error-actual-level`: Tool's actual safety level

Raised when tool safety level exceeds maximum.

```lisp
(handler-case (execute-tool tool call :max-safety-level :safe)
  (tool-safety-violation (e)
    (format t "Tool ~A exceeds safety level~%"
            (error-tool e))))
```

---

## Enhanced Tool Definition

The `define-tool` function now accepts additional keyword arguments:

```lisp
(define-tool name description parameters
  &key required
       safety-level              ; New: :safe | :moderate | :dangerous
       categories                ; New: list of keywords
       requires-approval         ; New: nil | t | :always | :if-dangerous
       parameter-validators      ; New: alist of (name . validator)
       on-start                  ; New: hook function
       on-complete               ; New: hook function
       on-error                  ; New: hook function
       handler                   ; New: execution function
       metadata)                 ; New: plist of metadata
```

All new parameters are optional and default to sensible values. Existing code continues to work unchanged.

---

## Package: `cl-llm-provider.tools`

Use this package for access to enhanced tools functionality:

```lisp
(use-package :cl-llm-provider.tools)
```

Exports 48 symbols covering all enhanced tools features.
