# Enhanced Tools Migration Guide

Guide for upgrading existing code to use new enhanced tools features.

## Overview

Enhanced tools are **100% backward compatible**. Existing code requires no changes.

This guide shows how to gradually adopt new features.

## What's New

### New Capabilities

1. **Safety levels** - Classify tools by risk
2. **Categories** - Organize tools by function
3. **Validators** - Validate parameters before execution
4. **Registry** - Discover and manage tools
5. **Approval** - Require human approval for sensitive operations
6. **Hooks** - Execute code at lifecycle events
7. **Execution engine** - Full-featured tool execution

### Backward Compatibility

All existing code continues to work:

```lisp
;; This still works exactly as before
(define-tool "search"
  "Search the web"
  '((:name "query" :type :string)))

(complete messages :tools (list search-tool))
```

## Migration Path

### Phase 1: No Changes Needed (Optional)

You can keep using tools exactly as before. All new features are optional.

### Phase 2: Add Safety Classification (Recommended)

Classify tools by risk:

```lisp
;; Before
(define-tool "search" "Search" '((:name "q" :type :string)))

;; After - add safety-level
(define-tool "search" "Search" '((:name "q" :type :string))
  :safety-level :safe)  ; NEW

;; For dangerous operations
(define-tool "delete" "Delete" '((:name "path" :type :string))
  :safety-level :dangerous)  ; NEW
```

### Phase 3: Add Categories (Recommended)

Organize tools for discovery:

```lisp
;; Before
(define-tool "query_db" "Query" '((:name "sql" :type :string)))

;; After - add categories
(define-tool "query_db" "Query" '((:name "sql" :type :string))
  :categories '(:database :search))  ; NEW
```

### Phase 4: Add Parameter Validation (Recommended)

Catch bad inputs early:

```lisp
;; Before
(define-tool "update" "Update" '((:name "id" :type :string)))

;; After - add validators
(define-tool "update" "Update" '((:name "id" :type :string))
  :parameter-validators '(("id" . (:pattern "^[0-9]+$"))))  ; NEW
```

### Phase 5: Use Registry (Recommended)

Manage tools dynamically:

```lisp
;; Before
(let ((tools (list search-tool delete-tool read-tool)))
  (complete messages :tools tools))

;; After - use registry
(let ((registry (make-tool-registry :name "my-app")))
  (dolist (tool (list search-tool delete-tool read-tool))
    (register-tool registry tool))

  ;; Get only safe tools for LLM
  (complete messages :tools (tools-for-llm :registry registry)))
```

### Phase 6: Add Approval (For Sensitive Operations)

Require approval for dangerous tools:

```lisp
;; Before
(define-tool "delete" "Delete" '((:name "path" :type :string))
  :handler (lambda (args) (delete-file (getf args :path))))

;; After - add approval
(define-tool "delete" "Delete" '((:name "path" :type :string))
  :requires-approval :always  ; NEW
  :handler (lambda (args) (delete-file (getf args :path))))

;; Execute with approval
(execute-tool-calls response
                    :registry registry
                    :approval-callback (make-interactive-approval-callback))  ; NEW
```

### Phase 7: Add Hooks (For Logging/Metrics)

Track tool execution:

```lisp
;; Before
(define-tool "process" "Process" '((:name "data" :type :string))
  :handler (lambda (args) ...))

;; After - add hooks
(define-tool "process" "Process" '((:name "data" :type :string))
  :on-start (lambda (call args)
              (log "Starting: ~A" (tool-call-name call)))  ; NEW
  :on-complete (lambda (call args result)
                 (log "Done: ~A" (tool-call-name call)))   ; NEW
  :handler (lambda (args) ...))
```

## Migration Examples

### Example 1: Simple Tool → Classified Tool

**Before:**
```lisp
(define-tool "search"
  "Search for information"
  '((:name "query" :type :string))
  :required '("query")
  :handler (lambda (args) ...))
```

**After (minimal):**
```lisp
(define-tool "search"
  "Search for information"
  '((:name "query" :type :string))
  :required '("query")
  :safety-level :safe           ; NEW: Classify as safe
  :categories '(:search)        ; NEW: Add category
  :handler (lambda (args) ...))
```

### Example 2: Ad-Hoc Tool List → Registry

**Before:**
```lisp
(defvar *tools*
  (list search-tool delete-tool read-tool))

(complete messages :tools *tools*)
```

**After (with filtering):**
```lisp
(defvar *registry* (make-tool-registry :name "my-app"))
(dolist (tool (list search-tool delete-tool read-tool))
  (register-tool *registry* tool))

;; Only safe tools
(complete messages :tools (tools-for-llm :registry *registry* :max-safety-level :safe))

;; Only database tools
(complete messages :tools (tools-by-category :database :registry *registry*))
```

### Example 3: Basic Execution → Full Lifecycle

**Before:**
```lisp
(let ((response (complete messages :tools *tools*)))
  (when (response-tool-calls response)
    ;; No execution, just get calls
    (response-tool-calls response)))
```

**After (with validation, approval, hooks):**
```lisp
(let ((response (complete messages :tools (tools-for-llm :registry *registry*))))
  (when (response-tool-calls response)
    ;; Execute with full lifecycle
    (let ((results (execute-tool-calls response
                                        :registry *registry*
                                        :max-safety-level :moderate
                                        :approval-callback (make-interactive-approval-callback))))
      ;; Continue conversation
      (complete (append messages (execution-results-to-tool-messages results))))))
```

## Breaking Changes

**None.** All changes are backward compatible.

Existing code works without modification. New features are entirely optional.

## Deprecations

**None.** No existing APIs are deprecated.

## New Dependencies

No new external dependencies. Enhanced tools use existing cl-llm-provider infrastructure.

## Performance Impact

**Negligible.**

- Feature detection: < 1ms
- Registry lookup: O(1) hash table
- Validation: Only if enabled
- Hooks: Only if registered

## Common Migration Questions

### Q: Do I need to change my code?

**A**: No. Everything works as before. But we recommend gradually adding:
1. Safety levels
2. Categories
3. Validators (for inputs)

### Q: Can I use new features gradually?

**A**: Yes. Each feature is independent:
- Add safety without registry
- Add registry without approval
- Add validation without hooks
- Mix and match as needed

### Q: How do I add safety to 50 tools?

**A**: Use a helper:

```lisp
(defun add-safety (tool level category)
  "Copy tool with added safety info"
  (let ((new-tool (cl-llm-provider:define-tool
                    (tool-name tool)
                    (tool-description tool)
                    (tool-parameters tool)
                    :required (tool-required-params tool)
                    :safety-level level
                    :categories (list category))))
    new-tool))

;; Apply to all tools
(defvar *safe-tools*
  (mapcar (lambda (t) (add-safety t :safe :custom)) *tools*))
```

### Q: How do I migrate to registry without changing all call sites?

**A**: Keep the tool list, but also populate registry:

```lisp
(defvar *tools* (list search-tool delete-tool))
(defvar *registry* (make-tool-registry))

;; Populate registry from list
(dolist (tool *tools*)
  (register-tool *registry* tool))

;; Now use registry in new code, keep *tools* for backward compat
(complete messages :tools *tools*)  ; Old code still works
(complete messages :tools (tools-for-llm :registry *registry*))  ; New code
```

### Q: How do I add validation to existing tools?

**A**: Rebuild with validators:

```lisp
;; Old tool
(define-tool "update" "Update" '((:name "id" :type :string)))

;; New tool with validators
(define-tool "update" "Update" '((:name "id" :type :string))
  :parameter-validators '(("id" . (:pattern "^[0-9]+$"))))
```

Or create a wrapper:

```lisp
(defun validated-execute (tool call args-validators)
  "Execute tool with validation"
  ;; Validate each argument
  (dolist ((param . validator) args-validators)
    (let ((value (getf (tool-call-arguments call) (intern param :keyword))))
      (unless (funcall validator value)
        (error "Invalid ~A: ~A" param value))))
  ;; Execute
  (funcall (tool-handler tool) (tool-call-arguments call)))
```

### Q: How do I add approval to existing tools?

**A**: Pass approval callback to execute:

```lisp
;; Without changing tool definition:
(execute-tool tool call
              :approval-callback (make-interactive-approval-callback))
```

Or update tool:

```lisp
(define-tool "delete" "Delete" '((:name "path" :type :string))
  :requires-approval :always  ; Add this
  :handler (lambda (args) ...))
```

### Q: Can I use new features with old providers?

**A**: Yes. Enhanced tools work with all providers:

```lisp
;; Works with any provider
(complete messages
         :provider (make-provider :anthropic)
         :tools (tools-for-llm :registry *registry*))
```

## Step-by-Step Migration for Large Codebase

### Step 1: Audit Tools (1-2 hours)

```lisp
;; List all tools and categorize
(defvar *all-tools* nil)  ; Populate with your tools

;; Review each tool:
; - Is it read-only? (safe)
; - Is it modifying? (moderate)
; - Is it destructive? (dangerous)
(dolist (tool *all-tools*)
  (format t "~A: ~A~%" (tool-name tool) (tool-description tool)))
```

### Step 2: Add Safety to Tool Definitions (2-4 hours)

```lisp
;; Redefine tools with safety levels
(define-tool "search" "Search" ...
  :safety-level :safe)    ; NEW

(define-tool "delete" "Delete" ...
  :safety-level :dangerous)  ; NEW
```

### Step 3: Add Categories (1-2 hours)

```lisp
;; Add category to each tool
(define-tool "search" "Search" ...
  :categories '(:search :external-api))  ; NEW
```

### Step 4: Create Registry (1 hour)

```lisp
;; Create and populate registry
(defvar *registry* (make-tool-registry :name "my-app"))
(dolist (tool *all-tools*)
  (register-tool *registry* tool))
```

### Step 5: Update Call Sites (2-8 hours depending on size)

```lisp
;; Before
(complete messages :tools *all-tools*)

;; After
(complete messages :tools (tools-for-llm :registry *registry*))
```

### Step 6: Add Validation (4-8 hours)

```lisp
;; Add validators to tools that accept user input
(define-tool "query" "Query" ...
  :parameter-validators '(("id" . (:pattern "^[0-9]+$"))))
```

### Step 7: Add Approval (4-8 hours)

```lisp
;; Mark dangerous tools
(define-tool "delete" "Delete" ...
  :requires-approval :always)

;; Update execution
(execute-tool-calls response
                    :approval-callback (make-interactive-approval-callback))
```

### Step 8: Add Hooks (1-2 hours)

```lisp
;; Add logging/metrics
(setf (registry-global-hooks *registry*)
      (list :on-start (lambda (call args) (log "Start: ~A" ...))
            :on-complete (lambda (call args result) (log "Done"))))
```

**Total**: 15-35 hours depending on codebase size and complexity.

## Rollback Plan

If you need to roll back:

1. Existing code continues to work
2. Remove new features one by one
3. No database migrations needed
4. No breaking changes to revert

Example rollback:

```lisp
;; Disable registry, use simple tool list
(complete messages :tools *tool-list*)  ; Old way still works

;; Disable approval
(execute-tool-calls response :skip-approval t)

;; Disable validation
(execute-tool tool call :skip-validation t)
```

## Getting Help

- **TOOLS-QUICK-START.md** - 5-minute intro
- **TOOLS-ADVANCED.md** - Complete guide
- **TOOLS-API-REFERENCE.md** - Detailed API docs
- **examples/tools-advanced-examples.lisp** - Code examples
- **tests/test-tools-enhanced.lisp** - Test patterns

## Summary

Enhanced tools are designed for easy adoption:

1. **Start simple**: Use existing code as-is
2. **Add gradually**: One feature at a time
3. **Stay flexible**: Mix old and new approaches
4. **No risk**: Fully backward compatible

Happy migrating!
