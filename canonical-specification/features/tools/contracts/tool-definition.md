---
type: contract
name: tool-definition
version: 0.2.0
status: draft
feature: tools
---

# Tool Definition Contract

This contract defines the structure and requirements for defining tools that can be called by LLM providers.

## Overview

A tool definition describes a function that an LLM can call. It includes the function name, description, parameter schema, safety metadata, and optional execution handlers.

## Function: `define-tool`

Creates a tool definition object that can be passed to completion functions.

### Signature

```lisp
(define-tool name description parameters
             &key required safety-level categories requires-approval
                  parameter-validators on-start on-complete on-error
                  handler metadata)
```

### Parameters

#### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | string | Tool/function name |
| `description` | string | What the tool does (used by LLM for selection) |
| `parameters` | list of plists | Parameter specifications |

#### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `required` | list of strings | `nil` | Required parameter names |
| `safety-level` | keyword | `:safe` | `:safe`, `:moderate`, or `:dangerous` |
| `categories` | list of keywords | `nil` | Categories (`:search`, `:database`, `:filesystem`, etc.) |
| `requires-approval` | boolean/keyword | `nil` | `nil`, `t`, `:always`, or `:if-dangerous` |
| `parameter-validators` | alist | `nil` | Parameter validation rules |
| `on-start` | function | `nil` | Hook called before execution |
| `on-complete` | function | `nil` | Hook called after successful execution |
| `on-error` | function | `nil` | Hook called on execution error |
| `handler` | function | `nil` | Execution function |
| `metadata` | plist | `nil` | Additional metadata |

### Parameter Schema

Each parameter in the `parameters` list is a plist with:

```json-schema
{
  "type": "object",
  "properties": {
    "name": {
      "type": "string",
      "description": "Parameter name"
    },
    "type": {
      "type": "string",
      "enum": ["string", "integer", "number", "boolean", "array", "object"],
      "description": "Parameter type"
    },
    "description": {
      "type": "string",
      "description": "Parameter description for LLM"
    },
    "enum": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Optional list of allowed values"
    },
    "items": {
      "type": "object",
      "description": "For array types, schema of array items (v0.2.0+)"
    }
  },
  "required": ["name", "type", "description"]
}
```

### Return Value

Returns a `tool-definition` object with slots:
- `name` - tool name (string)
- `description` - tool description (string)
- `parameters` - parameter specifications (list)
- `required` - required parameter names (list)
- `safety-level` - safety level (keyword)
- `categories` - category keywords (list)
- `requires-approval` - approval setting
- `parameter-validators` - validation rules
- `on-start`, `on-complete`, `on-error` - lifecycle hooks
- `handler` - execution function
- `metadata` - additional metadata (plist)

## Examples

### Basic Tool Definition

```lisp
(define-tool "get_weather"
  "Get the current weather in a given location"
  '((:name "location"
     :type :string
     :description "City and state, e.g. San Francisco, CA")
    (:name "unit"
     :type :string
     :enum ("celsius" "fahrenheit")
     :description "Temperature unit"))
  :required '("location"))
```

### Tool with Array Parameters (v0.2.0+)

```lisp
(define-tool "search_multiple"
  "Search multiple queries in parallel"
  '((:name "queries"
     :type :array
     :description "List of search queries"
     :items (:type :string)))
  :required '("queries"))
```

### Enhanced Tool with Safety and Validation

```lisp
(define-tool "delete_file"
  "Delete a file from the filesystem"
  '((:name "path"
     :type :string
     :description "File path to delete"))
  :required '("path")
  :safety-level :dangerous
  :categories '(:filesystem :destructive)
  :requires-approval :always
  :parameter-validators '(("path" . (:pattern "^/tmp/")))
  :handler (lambda (args)
             (delete-file (getf args :path)))
  :metadata '(:version "1.0" :author "system"))
```

### Tool with Lifecycle Hooks

```lisp
(define-tool "database_query"
  "Execute a database query"
  '((:name "sql"
     :type :string
     :description "SQL query to execute"))
  :required '("sql")
  :safety-level :moderate
  :categories '(:database)
  :on-start (lambda (tool-call args)
              (log:info "Starting query: ~A" (getf args :sql)))
  :on-complete (lambda (tool-call args result)
                 (log:info "Query returned ~D rows" (length result)))
  :on-error (lambda (tool-call args condition)
              (log:error "Query failed: ~A" condition)))
```

## Invariants

1. **Name uniqueness**: Tool names MUST be unique within a tool set
2. **Required parameter existence**: All parameters listed in `:required` MUST exist in `:parameters`
3. **Enum validation**: If `:enum` is specified, it MUST be a non-empty list
4. **Safety level validity**: `:safety-level` MUST be one of `:safe`, `:moderate`, or `:dangerous`
5. **Hook signatures**: Lifecycle hooks MUST accept the correct number of arguments:
   - `on-start`: `(tool-call arguments)`
   - `on-complete`: `(tool-call arguments result)`
   - `on-error`: `(tool-call arguments condition)`
6. **Handler signature**: If provided, `:handler` MUST be a function accepting one argument (arguments plist)

## Error Conditions

| Condition | When | Recovery |
|-----------|------|----------|
| `invalid-tool-definition` | Invalid parameter schema | Fix schema definition |
| `missing-required-parameter` | Required parameter not in parameters list | Add missing parameter |
| `invalid-safety-level` | Unknown safety level | Use `:safe`, `:moderate`, or `:dangerous` |

## Related Contracts

- [tool-call.md](./tool-call.md) - Tool invocation by LLM
- [tool-result.md](./tool-result.md) - Tool execution results
- [tool-validation.md](./tool-validation.md) - Parameter validation

## Version History

- **v0.2.0**: Added `:items` property support for array parameters (DR-001)
- **v0.1.0**: Initial contract
