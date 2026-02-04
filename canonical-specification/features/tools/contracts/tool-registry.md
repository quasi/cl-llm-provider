---
type: contract
name: tool-registry
version: 0.1.0
status: draft
feature: tools
---

# Tool Registry Contract

This contract defines the tool registry system for centralized tool management, search, and filtering.

## Overview

The tool registry provides a centralized location for registering, discovering, and managing tool definitions. It supports multiple registries, safety levels, default approval callbacks, and global lifecycle hooks.

## Class: `tool-registry`

Central registry for tool definitions with search and filtering capabilities.

### Slots

| Slot | Type | Description |
|------|------|-------------|
| `tools` | hash-table | Maps tool names (strings) to tool-definition objects |
| `name` | string | Human-readable registry name |
| `description` | string | Description of registry purpose |
| `default-safety-level` | keyword | Default safety level (`:safe`, `:moderate`, `:dangerous`) |
| `approval-callback` | function | Default approval callback for tools requiring approval |
| `global-hooks` | plist | Global lifecycle hooks (`:on-start`, `:on-complete`, `:on-error`) |

## Functions

### `make-tool-registry`

Create a new tool registry.

```lisp
(make-tool-registry &key name description default-safety-level
                         approval-callback global-hooks)
→ tool-registry
```

**Parameters**:
- `name`: Human-readable registry name
- `description`: Purpose description
- `default-safety-level`: Default safety level for tools (default: `:safe`)
- `approval-callback`: Default approval function
- `global-hooks`: Plist of global hooks

**Example**:
```lisp
(defvar *my-registry*
  (make-tool-registry
    :name "search-tools"
    :description "Tools for searching external APIs"
    :default-safety-level :moderate
    :approval-callback #'my-approval-fn
    :global-hooks '(:on-start #'log-tool-start
                    :on-complete #'log-tool-complete)))
```

### `ensure-registry`

Ensure the global registry exists, creating it if needed.

```lisp
(ensure-registry) → tool-registry
```

Returns `*tool-registry*`, creating a default registry if it doesn't exist.

## Generic Functions

### `register-tool`

Register a tool in the registry.

```lisp
(register-tool registry tool &key replace) → tool-definition
```

**Parameters**:
- `registry`: Tool registry instance
- `tool`: tool-definition object
- `replace`: If `t`, replace existing tool; if `nil` (default), signal error on conflict

**Error Conditions**:
- `tool-already-registered`: Tool with same name exists and `:replace` is `nil`

**Example**:
```lisp
(let ((tool (define-tool "get_weather" ...)))
  (register-tool *tool-registry* tool))
```

### `unregister-tool`

Remove a tool from the registry.

```lisp
(unregister-tool registry tool-name) → tool-definition-or-nil
```

Returns the removed tool-definition or `nil` if not found.

### `find-tool`

Find a tool by exact name.

```lisp
(find-tool registry name) → tool-definition-or-nil
```

**Example**:
```lisp
(find-tool *tool-registry* "get_weather")
```

### `list-tools`

List all registered tools.

```lisp
(list-tools registry) → list-of-tool-definitions
```

### `search-tools`

Search tools by criteria.

```lisp
(search-tools registry &key category safety-level name-pattern
                            requires-approval capabilities)
→ list-of-tool-definitions
```

**Filter Parameters**:
- `category`: Match any tool with this category
- `safety-level`: Match tools with this safety level
- `name-pattern`: Regex pattern to match tool names
- `requires-approval`: Match tools requiring approval (boolean)
- `capabilities`: Match tools with specific capabilities

**Example**:
```lisp
;; Find all dangerous database tools
(search-tools *tool-registry*
              :category :database
              :safety-level :dangerous)

;; Find tools with "search" in name
(search-tools *tool-registry*
              :name-pattern ".*search.*")
```

### `filter-tools`

Filter tools with a custom predicate.

```lisp
(filter-tools registry predicate) → list-of-tool-definitions
```

**Example**:
```lisp
;; Find tools with more than 3 parameters
(filter-tools *tool-registry*
              (lambda (tool)
                (> (length (tool-parameters tool)) 3)))
```

## Global Registry

### Variable: `*tool-registry*`

The global tool registry instance. Initialize with `(ensure-registry)` or manually set.

### Quick Registration

```lisp
;; Register to global registry
(register-tool (ensure-registry) my-tool)

;; Find in global registry
(find-tool (ensure-registry) "tool_name")
```

## Registry Operations Schema

### Registration Request

```json-schema
{
  "type": "object",
  "properties": {
    "operation": {
      "type": "string",
      "enum": ["register", "unregister", "find", "search"]
    },
    "tool_name": {
      "type": "string",
      "description": "Tool name for register/unregister/find"
    },
    "tool_definition": {
      "type": "object",
      "description": "Tool definition for register operation"
    },
    "filters": {
      "type": "object",
      "properties": {
        "category": {"type": "string"},
        "safety_level": {"type": "string", "enum": ["safe", "moderate", "dangerous"]},
        "name_pattern": {"type": "string"},
        "requires_approval": {"type": "boolean"}
      },
      "description": "Filters for search operation"
    }
  },
  "required": ["operation"]
}
```

## Invariants

1. **Unique names**: Tool names MUST be unique within a registry
2. **Valid safety level**: Default safety level MUST be `:safe`, `:moderate`, or `:dangerous`
3. **Hook signature**: Global hooks MUST have correct function signatures
4. **Registry isolation**: Multiple registries MUST NOT share tool-definition objects (each tool belongs to one registry)
5. **Registration atomicity**: `register-tool` MUST be atomic (either fully succeeds or leaves registry unchanged)

## Usage Patterns

### Single Global Registry

```lisp
;; Initialize global registry
(ensure-registry)

;; Register tools
(register-tool (ensure-registry) (define-tool "tool1" ...))
(register-tool (ensure-registry) (define-tool "tool2" ...))

;; Use in completion
(complete messages :tools (list-tools (ensure-registry)))
```

### Multiple Specialized Registries

```lisp
;; Safe read-only tools
(defvar *read-only-registry*
  (make-tool-registry :name "read-only"
                      :default-safety-level :safe))

;; Dangerous write operations
(defvar *admin-registry*
  (make-tool-registry :name "admin"
                      :default-safety-level :dangerous
                      :approval-callback #'admin-approval))

;; Use appropriate registry based on context
(complete user-messages
          :tools (if (admin-user-p user)
                     (list-tools *admin-registry*)
                     (list-tools *read-only-registry*)))
```

## Error Conditions

| Error | Condition | Recovery |
|-------|-----------|----------|
| `tool-already-registered` | Attempting to register a tool with existing name when `:replace` is nil | Use `:replace t` or choose different name |
| `invalid-tool-definition` | Tool definition missing required fields or has invalid metadata | Fix tool definition before registration |
| `tool-not-found` | Attempting to unregister or find non-existent tool | Check tool name spelling |
| `invalid-registry` | Registry argument is not a hash-table | Pass valid registry object |

## Related Contracts

- [tool-definition.md](./tool-definition.md) - Defining tools
- [tool-validation.md](./tool-validation.md) - Parameter validation
- [tool-approval.md](./tool-approval.md) - Approval workflows

## Implementation Notes

- The registry uses a hash table for O(1) tool lookup by name
- Search and filter operations are O(n) but typically operate on small tool sets (< 100 tools)
- Multiple registries enable security boundaries (safe vs. dangerous tools)
- Global hooks apply to all tools in the registry unless overridden at tool level
