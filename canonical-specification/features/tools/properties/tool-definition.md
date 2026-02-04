---
type: property
name: tool-definition-invariants
version: 0.1.0
status: draft
feature: tools
source: src/tools.lisp:122-173, src/types.lisp:209-273
---

# Tool Definition Invariants

[DRAFT] - Inferred from validation code

## Overview

Properties that must hold for all tool definitions to ensure valid tool specification and runtime behavior.

---

## PROP-TOOL-001: Non-Empty Tool Name

**Statement**: Tool name must be a non-empty string.

**Formal Expression**:
```lisp
∀ tool ∈ ToolDefinition:
  (stringp (tool-name tool)) ∧ (> (length (tool-name tool)) 0)
```

**Rationale**: Tool names are used as identifiers for tool invocation. Empty names cannot uniquely identify tools and break the tool calling protocol.

**Validation**: `validate-tool-definition` checks in `src/tools.lisp:128-131`:
```lisp
(unless (and (tool-name tool)
             (stringp (tool-name tool))
             (not (string= (tool-name tool) "")))
  (error 'tool-schema-error
         :tool tool
         :reason "Tool name must be a non-empty string"))
```

**Violation Impact**: Signals `tool-schema-error`, prevents tool registration.

**Test Coverage**: `tests/test-tools-support.lisp:135-141`

---

## PROP-TOOL-002: String Description

**Statement**: Tool description must be a string (can be empty).

**Formal Expression**:
```lisp
∀ tool ∈ ToolDefinition:
  (stringp (tool-description tool))
```

**Rationale**: Descriptions are used by LLMs to understand tool purpose. While empty descriptions are allowed, they reduce LLM's ability to select appropriate tools.

**Validation**: `validate-tool-definition` checks in `src/tools.lisp:133-136`:
```lisp
(unless (and (tool-description tool)
             (stringp (tool-description tool)))
  (error 'tool-schema-error
         :tool tool
         :reason "Tool description must be a string"))
```

**Violation Impact**: Signals `tool-schema-error`.

---

## PROP-TOOL-003: Parameter List Type

**Statement**: Tool parameters must be a list (can be empty for parameterless tools).

**Formal Expression**:
```lisp
∀ tool ∈ ToolDefinition:
  (listp (tool-parameters tool))
```

**Rationale**: Parameters are iterated during validation and translation. Non-list values break iteration logic.

**Validation**: `validate-tool-definition` checks in `src/tools.lisp:138-141`:
```lisp
(unless (listp (tool-parameters tool))
  (error 'tool-schema-error
         :tool tool
         :reason "Tool parameters must be a list"))
```

**Violation Impact**: Signals `tool-schema-error`.

**Test Coverage**: `tests/test-tools-support.lisp:56-62` (parameterless tool)

---

## PROP-TOOL-004: Parameter Name Requirement

**Statement**: Every parameter must have a `:name` key.

**Formal Expression**:
```lisp
∀ tool ∈ ToolDefinition:
  ∀ param ∈ (tool-parameters tool):
    (getf param :name) ≠ nil
```

**Rationale**: Parameter names are required for argument matching during tool invocation.

**Validation**: Checked per-parameter in `src/tools.lisp:147-150`:
```lisp
(unless (getf param :name)
  (error 'tool-schema-error
         :tool tool
         :reason (format nil "Parameter missing :name: ~S" param)))
```

**Violation Impact**: Signals `tool-schema-error` during validation.

---

## PROP-TOOL-005: Parameter Type Requirement

**Statement**: Every parameter must have a `:type` key with valid type keyword.

**Formal Expression**:
```lisp
∀ tool ∈ ToolDefinition:
  ∀ param ∈ (tool-parameters tool):
    (getf param :type) ∈ {:string, :integer, :number, :boolean, :array, :object}
```

**Rationale**: Types are translated to JSON Schema for provider APIs. Invalid types cannot be translated.

**Validation**: Checked per-parameter in `src/tools.lisp:152-163`:
```lisp
(unless (getf param :type)
  (error 'tool-schema-error
         :tool tool
         :reason (format nil "Parameter missing :type: ~S" param)))

(unless (member (getf param :type)
                '(:string :integer :number :boolean :array :object))
  (error 'tool-schema-error
         :tool tool
         :reason (format nil "Invalid parameter type ~S..." (getf param :type))))
```

**Violation Impact**: Signals `tool-schema-error`.

**Test Coverage**: `tests/test-tools-support.lisp:82-110` (per-type tests)

---

## PROP-TOOL-006: Required Parameter Validity

**Statement**: All names in `required` list must be strings.

**Formal Expression**:
```lisp
∀ tool ∈ ToolDefinition:
  (tool-required-params tool) ≠ nil ⟹
    ∀ name ∈ (tool-required-params tool):
      (stringp name)
```

**Rationale**: Required parameter names must match parameter definition names (strings) for validation.

**Validation**: Checked in `src/tools.lisp:166-170`:
```lisp
(when (tool-required-params tool)
  (unless (every #'stringp (tool-required-params tool))
    (error 'tool-schema-error
           :tool tool
           :reason "Required parameter names must be strings")))
```

**Violation Impact**: Signals `tool-schema-error`.

**Test Coverage**: `tests/test-tools-support.lisp:45-54`

---

## PROP-TOOL-007: Safety Level Ordering

**Statement**: Safety levels form a total order: `:safe` < `:moderate` < `:dangerous`.

**Formal Expression**:
```lisp
safety-value(:safe) = 0
safety-value(:moderate) = 1
safety-value(:dangerous) = 2

∀ a, b ∈ SafetyLevel:
  (safety-level<= a b) ⟺ (safety-value(a) ≤ safety-value(b))
```

**Rationale**: Safety comparison is used for filtering and enforcement. Ordering must be consistent.

**Implementation**: `src/tools/categories.lisp:28-30`:
```lisp
(defparameter *safety-level-values*
  '((:safe . 0) (:moderate . 1) (:dangerous . 2)))
```

**Violation Impact**: Safety enforcement becomes unpredictable.

**Test Coverage**: `tests/test-tools-enhanced.lisp:56-69`

---

## PROP-TOOL-008: Unique Tool Names

**Statement**: Within a registry, tool names must be unique (case-sensitive).

**Formal Expression**:
```lisp
∀ registry ∈ ToolRegistry:
  ∀ t1, t2 ∈ registry.tools:
    (tool-name t1) = (tool-name t2) ⟹ t1 = t2
```

**Rationale**: Tool lookup by name must return exactly one tool. Duplicates create ambiguity.

**Enforcement**: `register-tool` in `src/tools/registry.lisp`:
```lisp
(when (and (find-tool registry name) (not replace))
  (error "Tool with name ~S already registered" name))
```

**Violation Impact**: Registration fails unless `:replace t` specified.

**Test Coverage**: `tests/test-tools-enhanced.lisp:137-155`

---

## Composite Invariants

### INV-TOOL-COMPLETE: Complete Tool Definition

A tool is **complete** iff all of PROP-TOOL-001 through PROP-TOOL-006 hold.

**Verification**: `(validate-tool-definition tool)` returns `t` without signaling.

### INV-TOOL-EXECUTABLE: Executable Tool

A tool is **executable** iff:
1. INV-TOOL-COMPLETE holds
2. Tool has handler function: `(tool-handler tool) ≠ nil ∧ (functionp (tool-handler tool))`

**Verification**: Tool can be passed to `execute-tool` without immediate error.

---

## Test Evidence Summary

| Property | Test File | Test Name | Status |
|----------|-----------|-----------|--------|
| PROP-TOOL-001 | test-tools-support.lisp:135 | validate-valid-tool | ✅ |
| PROP-TOOL-002 | test-tools-support.lisp:135 | validate-valid-tool | ✅ |
| PROP-TOOL-003 | test-tools-support.lisp:56 | tool-with-no-parameters | ✅ |
| PROP-TOOL-004 | test-tools-support.lisp:147 | parameter-definition | ✅ |
| PROP-TOOL-005 | test-tools-support.lisp:82-110 | parameter-*-type | ✅ |
| PROP-TOOL-006 | test-tools-support.lisp:45 | tool-with-required | ✅ |
| PROP-TOOL-007 | test-tools-enhanced.lisp:56 | safety-level-order | ✅ |
| PROP-TOOL-008 | test-tools-enhanced.lisp:137 | register-and-find | ✅ |

---

## Related Properties

- [Safety and Approval](./safety-and-approval.md) - Safety level enforcement
- [Validation](./validation.md) - Parameter validation rules
- [Execution](./execution.md) - Execution lifecycle invariants
