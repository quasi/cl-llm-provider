# Enhanced Tools Documentation Index

Welcome to the cl-llm-provider enhanced tools documentation. This is your entry point to all resources about the new safety, categories, validators, registry, approval, and execution features.

## Quick Navigation

**I want to...**

| Goal | Document | Time |
|------|----------|------|
| Get started quickly | [TOOLS-QUICK-START.md](TOOLS-QUICK-START.md) | 5 min |
| Understand all features | [TOOLS-ADVANCED.md](TOOLS-ADVANCED.md) | 30 min |
| Find API documentation | [TOOLS-API-REFERENCE.md](TOOLS-API-REFERENCE.md) | Ref |
| See code examples | [examples/tools-advanced-examples.lisp](examples/tools-advanced-examples.lisp) | 15 min |
| Learn how to migrate | [TOOLS-MIGRATION.md](TOOLS-MIGRATION.md) | 20 min |
| Write and run tests | [TOOLS-TESTING.md](TOOLS-TESTING.md) | 20 min |

## Documentation Map

### 1. [TOOLS-QUICK-START.md](TOOLS-QUICK-START.md) - START HERE

**For**: Developers who want to get started in 5 minutes

**Covers**:
- Basic tool definition with new features
- Adding safety levels
- Creating registries
- Running your first execution
- Common patterns and troubleshooting

**Best for**: Quick introduction, simple examples, immediate results

---

### 2. [TOOLS-ADVANCED.md](TOOLS-ADVANCED.md) - COMPREHENSIVE GUIDE

**For**: Developers who want to understand everything

**Covers**:
- Core concepts and design
- Safety levels (values, usage, comparisons)
- Tool categories (predefined and custom)
- Parameter validators (built-in and custom)
- Tool registry (CRUD, search, filtering)
- Approval system (modes, callbacks, workflows)
- Lifecycle hooks (types, global hooks, factories)
- Tool execution (single, batch, error handling)
- Complete working examples
- Best practices and migration guide

**Best for**: Complete understanding, reference, best practices

**Length**: ~600 lines

---

### 3. [TOOLS-API-REFERENCE.md](TOOLS-API-REFERENCE.md) - API DOCUMENTATION

**For**: Developers looking up specific functions and classes

**Covers**:
- All exported symbols organized by feature
- Function signatures and parameters
- Return values and error signals
- Complete class and slot documentation
- Condition hierarchy
- Package exports

**Best for**: Function lookup, API contracts, detailed specifications

**Format**: Reference documentation with tables and examples

---

### 4. [examples/tools-advanced-examples.lisp](examples/tools-advanced-examples.lisp) - CODE EXAMPLES

**For**: Developers who learn best from working code

**Covers**:
- 12 practical examples including:
  1. Simple tool with categories
  2. Database tool with validation
  3. File system tool with approval
  4. Payment tool with safety-based approval
  5. Tool registry with discovery
  6. Registry with global hooks
  7. Interactive approval workflow
  8. Custom approval logic
  9. Tool execution with error handling
  10. Complete application
  11. Dynamic tool discovery
  12. Validator composition

**Best for**: Learning patterns, copy-paste starting points, real-world usage

**Format**: Annotated Lisp code with docstrings

---

### 5. [TOOLS-MIGRATION.md](TOOLS-MIGRATION.md) - UPGRADE GUIDE

**For**: Existing users upgrading to enhanced tools

**Covers**:
- What's new in a nutshell
- Backward compatibility guarantees
- Phase-by-phase migration path
- Migration examples (before/after)
- Step-by-step migration for large codebases
- Breaking changes (none!)
- Deprecations (none!)
- Common migration questions and answers
- Rollback plan

**Best for**: Planning upgrades, understanding impact, gradual adoption

---

### 6. [TOOLS-TESTING.md](TOOLS-TESTING.md) - TESTING GUIDE

**For**: Developers writing tests for tools

**Covers**:
- Test coverage breakdown (83 automated checks)
- How to run test suites
- Test organization and structure
- Writing custom tests
- Testing patterns and best practices
- Performance testing
- CI/CD integration
- Debugging failed tests
- Test data and fixtures

**Best for**: Writing tests, CI/CD setup, quality assurance

---

## Feature Overview

### Safety Levels

Classify tools by risk to prevent accidental execution of dangerous operations.

```lisp
:safe       ; Read-only, no risk
:moderate   ; May modify data
:dangerous  ; Irreversible operations
```

**Learn more**: [TOOLS-ADVANCED.md#safety-levels](TOOLS-ADVANCED.md#safety-levels)

### Categories

Organize tools for discovery and filtering.

**Predefined**: `:search`, `:database`, `:filesystem`, `:payment`, `:destructive`, `:authentication`, `:admin`, `:external-api`, `:ai`, `:messaging`, `:calculation`, `:network`

**Learn more**: [TOOLS-ADVANCED.md#tool-categories](TOOLS-ADVANCED.md#tool-categories)

### Parameter Validators

Validate tool arguments before execution.

**Built-in validators**:
- `:positive-integer`, `:non-empty-string`, `:email`, `:url`
- Range, pattern, length, enum, type validators

**Learn more**: [TOOLS-ADVANCED.md#parameter-validators](TOOLS-ADVANCED.md#parameter-validators)

### Tool Registry

Dynamically discover and manage tools.

```lisp
(make-tool-registry :name "my-app")
(register-tool registry tool)
(find-tool registry "tool_name")
(tools-for-llm :registry registry :max-safety-level :safe)
```

**Learn more**: [TOOLS-ADVANCED.md#tool-registry](TOOLS-ADVANCED.md#tool-registry)

### Approval System

Require human approval for sensitive operations.

**Modes**: `:always`, `:if-dangerous`, `NIL`

**Learn more**: [TOOLS-ADVANCED.md#approval-system](TOOLS-ADVANCED.md#approval-system)

### Lifecycle Hooks

Execute code at tool execution events.

**Types**: `:on-start`, `:on-complete`, `:on-error`

**Learn more**: [TOOLS-ADVANCED.md#lifecycle-hooks](TOOLS-ADVANCED.md#lifecycle-hooks)

### Tool Execution

Execute tools with full lifecycle support.

```lisp
(execute-tool tool call :registry registry :max-safety-level :safe)
(execute-tool-calls response :registry registry :approval-callback callback)
```

**Learn more**: [TOOLS-ADVANCED.md#tool-execution](TOOLS-ADVANCED.md#tool-execution)

## Statistics

| Metric | Value |
|--------|-------|
| New slots in tool-definition | 9 |
| New conditions | 4 |
| New exported symbols | 48 |
| Files in src/tools/ module | 7 |
| Lines of implementation | ~1,200 |
| Automated checks | 83 |
| Test pass rate | 100% |
| Backward compatibility | 100% |
| Breaking changes | 0 |

## Getting Started

### For New Users

1. Start with **[TOOLS-QUICK-START.md](TOOLS-QUICK-START.md)** (5 minutes)
2. Try examples from **[examples/tools-advanced-examples.lisp](examples/tools-advanced-examples.lisp)**
3. Deep dive into **[TOOLS-ADVANCED.md](TOOLS-ADVANCED.md)** as needed

### For Existing Users

1. Read **[TOOLS-MIGRATION.md](TOOLS-MIGRATION.md)** for upgrade path
2. Keep using existing code (fully backward compatible)
3. Gradually adopt new features

### For Developers

1. Check **[TOOLS-API-REFERENCE.md](TOOLS-API-REFERENCE.md)** for complete API
2. Use **[TOOLS-TESTING.md](TOOLS-TESTING.md)** for testing patterns
3. Review examples for implementation patterns

## Key Concepts

### Tool Definition

Enhanced tools extend the basic `define-tool`:

```lisp
(define-tool name description parameters
  &key required
       safety-level              ; NEW
       categories                ; NEW
       requires-approval         ; NEW
       parameter-validators      ; NEW
       on-start on-complete on-error  ; NEW
       handler                   ; NEW
       metadata)                 ; NEW
```

All new parameters are optional and have sensible defaults.

### Safe by Default

```lisp
:safety-level :safe              ; Default
:requires-approval nil           ; Default
:parameter-validators nil        ; Default
```

### Backward Compatible

All existing code works without modification:

```lisp
;; This still works exactly as before
(define-tool "search" "Search" '((:name "q" :type :string)))
(complete messages :tools (list my-tool))
```

## Package Structure

### Main Package: `cl-llm-provider`

Core library with basic tool support.

### Enhanced Package: `cl-llm-provider.tools`

New enhanced tools module with:
- Categories system
- Validators
- Registry
- Approval system
- Hooks
- Execution engine

**Usage**: `(use-package :cl-llm-provider.tools)`

**Exports**: 48 symbols

## Common Tasks

### Create a Safe Tool

```lisp
(define-tool "search" "Search" '((:name "q" :type :string))
  :safety-level :safe
  :categories '(:search)
  :handler (lambda (args) ...))
```

### Create a Dangerous Tool with Approval

```lisp
(define-tool "delete" "Delete" '((:name "path" :type :string))
  :safety-level :dangerous
  :categories '(:filesystem :destructive)
  :requires-approval :always
  :handler (lambda (args) ...))
```

### Set Up Registry

```lisp
(defvar *tools* (make-tool-registry :name "my-app"))
(register-tool *tools* tool1)
(register-tool *tools* tool2)
```

### Get Safe Tools for LLM

```lisp
(complete messages :tools (tools-for-llm :registry *tools* :max-safety-level :safe))
```

### Execute with Approval

```lisp
(execute-tool-calls response
                    :registry *tools*
                    :approval-callback (make-interactive-approval-callback))
```

## Architecture Overview

```
Enhanced Tools System
├── Categories (classification)
├── Safety Levels (risk assessment)
├── Validators (parameter checking)
├── Registry (tool management)
├── Approval (human approval)
├── Hooks (lifecycle events)
└── Execution (full lifecycle execution)

All built on:
- Tool definitions (tool-definition class)
- Tool calls (tool-call class)
- Conditions (error handling)
- Completion responses
```

## Testing

Run all enhanced tools tests:

```bash
sbcl --noinform --non-interactive --load tests/test-tools-enhanced.lisp
```

**Result**: 83 checks, 100% pass rate

All 125 existing tool tests continue to pass (backward compatibility verified).

## Support

### Finding Information

- **Quick answer**: [TOOLS-QUICK-START.md](TOOLS-QUICK-START.md)
- **Detailed info**: [TOOLS-ADVANCED.md](TOOLS-ADVANCED.md)
- **API lookup**: [TOOLS-API-REFERENCE.md](TOOLS-API-REFERENCE.md)
- **Code example**: [examples/tools-advanced-examples.lisp](examples/tools-advanced-examples.lisp)
- **Upgrade path**: [TOOLS-MIGRATION.md](TOOLS-MIGRATION.md)
- **Testing help**: [TOOLS-TESTING.md](TOOLS-TESTING.md)

### Learning Resources

1. **Best for learning**: Examples + TOOLS-QUICK-START.md
2. **Best for reference**: TOOLS-API-REFERENCE.md
3. **Best for migration**: TOOLS-MIGRATION.md
4. **Best for testing**: TOOLS-TESTING.md
5. **Best for everything**: TOOLS-ADVANCED.md

## Feature Checklist

- ✅ Safety levels (:safe, :moderate, :dangerous)
- ✅ 12 predefined categories (customizable)
- ✅ Built-in parameter validators
- ✅ Custom validator composition
- ✅ Tool registry with CRUD operations
- ✅ Search and filtering (by name, category, safety)
- ✅ Approval system (always, if-dangerous, custom)
- ✅ Interactive approval callbacks
- ✅ Lifecycle hooks (on-start, on-complete, on-error)
- ✅ Global registry hooks
- ✅ Tool execution with full lifecycle
- ✅ Batch execution (execute-tool-calls)
- ✅ Execution context tracking
- ✅ Complete error handling
- ✅ 100% backward compatibility
- ✅ Zero breaking changes
- ✅ 83 automated tests (100% pass)

## Next Steps

1. **Start using**: Read [TOOLS-QUICK-START.md](TOOLS-QUICK-START.md)
2. **Understand deeply**: Read [TOOLS-ADVANCED.md](TOOLS-ADVANCED.md)
3. **Look up details**: Use [TOOLS-API-REFERENCE.md](TOOLS-API-REFERENCE.md)
4. **See examples**: Check [examples/tools-advanced-examples.lisp](examples/tools-advanced-examples.lisp)
5. **Plan migration**: Read [TOOLS-MIGRATION.md](TOOLS-MIGRATION.md)

## Questions?

- Is it backward compatible? **Yes, 100%**
- Do I have to change anything? **No, everything is optional**
- Can I use features gradually? **Yes, each feature is independent**
- What about performance? **Negligible impact**
- Are there tests? **Yes, 83 automated checks**

---

**Version**: 1.0
**Status**: Production Ready
**Last Updated**: 2025-12-30

Start with [TOOLS-QUICK-START.md](TOOLS-QUICK-START.md) and happy building! 🚀
