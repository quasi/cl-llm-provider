# Enhanced Tools: Advanced Features Guide

This guide covers the enhanced tools functionality in cl-llm-provider, including safety layers, approvals, validators, categories, lifecycle hooks, and tool discovery mechanisms.

## Table of Contents

1. [Overview](#overview)
2. [Core Concepts](#core-concepts)
3. [Safety Levels](#safety-levels)
4. [Tool Categories](#tool-categories)
5. [Parameter Validators](#parameter-validators)
6. [Tool Registry](#tool-registry)
7. [Approval System](#approval-system)
8. [Lifecycle Hooks](#lifecycle-hooks)
9. [Tool Execution](#tool-execution)
10. [Complete Examples](#complete-examples)

## Overview

The enhanced tools system adds multiple layers of safety, control, and introspection to tool definitions and execution:

- **Safety Classification**: Classify tools by risk level (`:safe`, `:moderate`, `:dangerous`)
- **Categories**: Organize tools by function (search, database, payment, etc.)
- **Validators**: Validate parameters before execution
- **Registry**: Discover and filter tools dynamically
- **Approvals**: Require human approval for sensitive operations
- **Hooks**: Execute code at tool lifecycle events
- **Execution Engine**: Full-featured tool execution with safety checks

## Core Concepts

### Tool Definition Enhancement

The `define-tool` function now accepts enhanced parameters:

```lisp
(define-tool "delete_file"
  "Delete a file from disk"
  '((:name "path" :type :string))
  :required '("path")
  ;; Enhanced parameters:
  :safety-level :dangerous
  :categories '(:filesystem :destructive)
  :requires-approval :always
  :parameter-validators '(("path" . (:pattern "^/tmp/")))
  :on-start (lambda (call args) ...)
  :on-complete (lambda (call args result) ...)
  :on-error (lambda (call args condition) ...)
  :handler (lambda (args) (delete-file (getf args :path)))
  :metadata '(:requires-admin t))
```

### Backward Compatibility

All new features are **completely optional**. Existing tools work without modification:

```lisp
;; This still works as before
(define-tool "search"
  "Search the web"
  '((:name "query" :type :string)))
```

## Safety Levels

Tools can be classified by risk level to prevent LLMs from executing dangerous operations.

### Safety Level Values

```lisp
:safe       ; No data loss, no system access (default)
:moderate   ; May modify data or access system resources
:dangerous  ; Irreversible operations (deletion, payments, etc.)
```

### Using Safety Levels

```lisp
;; Safe tool - can be executed freely
(define-tool "get_weather"
  "Get current weather"
  '((:name "location" :type :string))
  :safety-level :safe)

;; Moderate tool - requires some caution
(define-tool "update_database"
  "Update database record"
  '((:name "id" :type :string) (:name "data" :type :object))
  :safety-level :moderate)

;; Dangerous tool - human approval required
(define-tool "transfer_funds"
  "Transfer money between accounts"
  '((:name "from" :type :string) (:name "to" :type :string) (:name "amount" :type :number))
  :safety-level :dangerous
  :requires-approval :always)
```

### Checking Safety Levels

```lisp
(use-package :cl-llm-provider.tools)

;; Check if tool exceeds a safety level
(let ((tool (find-tool registry "delete_file")))
  (if (safety-level<= (tool-safety-level tool) :moderate)
      (execute-tool tool call)
      (error "Tool exceeds maximum safety level")))

;; Compare safety levels
(safety-level<= :safe :moderate)        ; => T
(safety-level<= :dangerous :safe)       ; => NIL
```

## Tool Categories

Tools can be organized into categories for discovery and filtering.

### Predefined Categories

```lisp
:search              ; Information retrieval
:database            ; Database operations
:filesystem          ; File system access
:network             ; Network/HTTP operations
:calculation         ; Math/computation
:destructive         ; Data deletion/modification
:authentication      ; Auth/identity operations
:payment             ; Financial transactions
:admin               ; Administrative actions
:external-api        ; Third-party API calls
:ai                  ; AI/ML operations
:messaging           ; Email/SMS/notifications
```

### Using Categories

```lisp
;; A tool can belong to multiple categories
(define-tool "search_database"
  "Search database for records"
  '((:name "query" :type :string))
  :categories '(:database :search))

;; Custom categories are also allowed
(define-tool "custom_operation"
  "Do something custom"
  nil
  :categories '(:custom :internal))
```

### Validating Categories

```lisp
(valid-category-p :search)         ; => T
(valid-category-p :custom)         ; => T (custom allowed)
(valid-category-p "string")        ; => NIL (must be keyword)
(normalize-categories :search)      ; => (:search)
(normalize-categories '(:search :database)) ; => (:search :database)
```

## Parameter Validators

Validate tool arguments before execution to catch errors early.

### Built-in Validators

```lisp
(use-package :cl-llm-provider.tools)

;; Available built-in validators
(list-built-in-validators)
; => (:positive-integer :non-negative-integer :email :url
;     :non-empty-string :http-method :iso8601-date :json-string)
```

### Creating Validators

```lisp
;; Range validator
(make-range-validator 0 100)        ; Validates 0-100
(make-range-validator 1.0 10.0)     ; Works with floats too

;; Pattern validator (regex)
(make-pattern-validator "^[a-z]+$") ; Lowercase letters only

;; Length validator
(make-length-validator :min-length 3 :max-length 20)

;; Enum validator
(make-enum-validator '("apple" "banana" "orange"))

;; Type validator
(make-type-validator :integer)
(make-type-validator :string)
```

### Using Validators in Tools

```lisp
(define-tool "update_user"
  "Update user record"
  '((:name "id" :type :string)
    (:name "age" :type :integer)
    (:name "email" :type :string))
  :parameter-validators
  '(("id" . (:pattern "^[0-9]+$"))
    ("age" . (:type :integer :min 0 :max 150))
    ("email" . :email))
  :handler (lambda (args) ...))
```

### Validator Spec Formats

```lisp
;; As a function
(lambda (value) (> value 0))

;; As a keyword (built-in)
:positive-integer

;; As a plist spec
(:type :integer :min 0 :max 100)

;; Composite validators
(make-composite-validator
  (make-pattern-validator "^/tmp/")
  (make-length-validator :max-length 256))
```

## Tool Registry

The tool registry provides dynamic tool discovery and management.

### Creating a Registry

```lisp
(use-package :cl-llm-provider.tools)

;; Create a registry
(defvar *my-tools* (make-tool-registry :name "my-app"))

;; Or use the global registry
(setq *tool-registry* (ensure-registry))
```

### Registering Tools

```lisp
;; Register individual tools
(register-tool *my-tools* search-tool)
(register-tool *my-tools* delete-tool)

;; Or use convenience function
(register search-tool :registry *my-tools*)
(register delete-tool :registry *my-tools*)
```

### Finding and Listing Tools

```lisp
;; Find by name
(find-tool *my-tools* "search_database")

;; List all tools
(list-tools *my-tools*)

;; Get by category
(tools-by-category :database :registry *my-tools*)

;; Get only safe tools
(safe-tools :registry *my-tools*)
```

### Searching Tools

```lisp
;; Search by various criteria
(search-tools *my-tools*
              :categories '(:database :search)
              :max-safety-level :moderate)

;; Search by name pattern
(search-tools *my-tools*
              :name-pattern "search.*")

;; Get tools suitable for LLM (safe by default)
(tools-for-llm :registry *my-tools*
               :max-safety-level :safe
               :categories '(:search :calculation))
```

### Registry Configuration

```lisp
;; Set default safety level
(defvar *registry*
  (make-tool-registry
    :name "secure-app"
    :default-safety-level :safe))

;; Set approval callback
(setf (registry-approval-callback *registry*)
      (make-interactive-approval-callback))

;; Set global hooks
(setf (registry-global-hooks *registry*)
      (list :on-start (lambda (call args) (log "Starting: ~A" (tool-call-name call)))
            :on-complete (lambda (call args result) (log "Completed"))))
```

## Approval System

Require human approval for sensitive tool executions.

### Approval Modes

```lisp
;; No approval needed
:requires-approval nil

;; Always approve
:requires-approval t
:requires-approval :always

;; Approve only dangerous tools
:requires-approval :if-dangerous
```

### Checking Approval Requirements

```lisp
(use-package :cl-llm-provider.tools)

(needs-approval-p safe-tool)        ; => NIL
(needs-approval-p dangerous-tool)   ; => T (if :if-dangerous)
```

### Approval Callbacks

Callbacks receive `(tool tool-call arguments)` and return approval decisions:

```lisp
;; Approval response formats
:approved                              ; Simple approval
(list :approved)                       ; Explicit approval
(list :approved new-arguments)         ; Approve with modified args
:rejected                              ; Simple rejection
(list :rejected reason)                ; Rejection with reason
(list :edited new-arguments)           ; Approve but with edited args
```

### Built-in Approval Callbacks

```lisp
;; Auto-approve all
(make-auto-approve-callback :log-fn (lambda (msg) (format t "~A~%" msg)))

;; Auto-reject all
(make-auto-reject-callback :reason "All tools rejected")

;; Approve based on safety level
(make-safety-based-callback
  :max-level :moderate
  :on-exceed :reject
  :rejection-reason "Tool too dangerous")

;; Interactive (REPL) approval
(make-interactive-approval-callback :stream *query-io*)
```

### Interactive Approval Example

```lisp
(define-tool "delete_file"
  "Delete a file"
  '((:name "path" :type :string))
  :safety-level :dangerous
  :requires-approval :always)

;; User runs this
(let ((call (make-instance 'tool-call
                          :id "call-1"
                          :name "delete_file"
                          :arguments '(:path "/tmp/old.txt")))
      (tool (find-tool *registry* "delete_file")))

  ;; This prompts the user:
  ;; ═══════════════════════════════════════
  ;; Tool Approval Required
  ;; ═══════════════════════════════════════
  ;; Tool: delete_file
  ;; Safety: dangerous
  ;; Arguments: (:PATH "/tmp/old.txt")
  ;; ───────────────────────────────────────
  ;; [A]pprove / [R]eject / [E]dit arguments:
  (execute-tool tool call
                :approval-callback (make-interactive-approval-callback)))
```

## Lifecycle Hooks

Execute code at key points in tool execution.

### Hook Types

```lisp
:on-start    ; Before execution: (call arguments)
:on-complete ; After successful execution: (call arguments result)
:on-error    ; On execution error: (call arguments condition)
```

### Tool-Specific Hooks

```lisp
(define-tool "process_data"
  "Process some data"
  '((:name "data" :type :string))
  :on-start (lambda (call args)
              (log "Starting: ~A with ~S" (tool-call-name call) args))
  :on-complete (lambda (call args result)
                 (log "Completed: ~A => ~S" (tool-call-name call) result))
  :on-error (lambda (call args condition)
              (log "Error in ~A: ~A" (tool-call-name call) condition))
  :handler (lambda (args) ...))
```

### Global Registry Hooks

```lisp
;; Add global hooks to registry
(let ((hooks (list
              :on-start (lambda (call args)
                          (format t "~&[LOG] Starting: ~A~%" (tool-call-name call)))
              :on-complete (lambda (call args result)
                             (format t "~&[LOG] Completed: ~A~%" (tool-call-name call)))
              :on-error (lambda (call args condition)
                          (format t "~&[LOG] Error: ~A~%" condition)))))
  (setf (registry-global-hooks *registry*) hooks))
```

### Built-in Hook Factories

```lisp
;; Logging hook
(make-logging-hook :on-start
                   :stream *standard-output*
                   :format-fn (lambda (stream hook-type call &rest args)
                                (format stream "~&[~A] ~A~%" hook-type (tool-call-name call))))

;; Timing hooks
(let ((timing-hooks (make-timing-hook
                      :on-complete-action (lambda (call duration-ms)
                                            (format t "~A took ~Dms~%"
                                                    (tool-call-name call)
                                                    duration-ms)))))
  (setf (registry-global-hooks *registry*) timing-hooks))

;; Combine multiple hooks
(combine-hooks :on-start
               (make-logging-hook :on-start)
               (lambda (call args) (log-metrics call)))
```

## Tool Execution

Execute tools with full lifecycle support.

### Basic Execution

```lisp
(use-package :cl-llm-provider.tools)

;; Execute a single tool
(let ((tool (find-tool *registry* "search_db"))
      (call (make-instance 'tool-call
                          :id "call-1"
                          :name "search_db"
                          :arguments '(:query "lisp"))))
  (execute-tool tool call :registry *registry*))
```

### Execution with Options

```lisp
;; Execute with safety checks
(execute-tool tool call
              :max-safety-level :moderate)

;; Execute with approval
(execute-tool tool call
              :approval-callback (make-interactive-approval-callback))

;; Skip validation for known-good data
(execute-tool tool call
              :skip-validation t)

;; Skip approval for admin operations
(execute-tool tool call
              :skip-approval t)
```

### Batch Execution

```lisp
;; Execute all tool calls from an LLM response
(let ((response (complete messages :tools (tools-for-llm :registry *registry*))))
  (when (response-tool-calls response)
    (let ((results (execute-tool-calls response
                                        :registry *registry*
                                        :max-safety-level :safe)))
      ;; Convert results to tool messages for continuation
      (let ((tool-messages (execution-results-to-tool-messages results)))
        (complete (append messages tool-messages))))))
```

### Handling Execution Errors

```lisp
;; Execution returns execution context with all details
(handler-case
    (execute-tool tool call :registry *registry*)

  (tool-safety-violation (e)
    (format t "Tool ~A exceeds safety level~%"
            (error-tool e)))

  (tool-validation-error (e)
    (format t "Invalid argument ~A: ~A~%"
            (error-parameter e)
            (error-value e)))

  (tool-approval-error (e)
    (format t "Tool approval rejected~%"))

  (error (e)
    (format t "Unexpected error: ~A~%" e)))
```

### Execution Context

The `tool-execution-context` tracks execution details:

```lisp
(defparameter *ctx* (execute-tool tool call :registry *registry*))

;; Access execution details
(context-tool-call *ctx*)           ; The tool-call object
(context-tool-definition *ctx*)     ; The tool definition
(context-arguments *ctx*)           ; Validated arguments
(context-approval-status *ctx*)     ; :approved, :rejected, :edited, or NIL
(context-edited-arguments *ctx*)    ; Arguments after user edit (if any)
(context-result *ctx*)              ; Result of execution
(context-error *ctx*)               ; Error condition if failed
(context-start-time *ctx*)          ; Execution start time
(context-end-time *ctx*)            ; Execution end time
```

## Complete Examples

### Example 1: Simple Tool with Category

```lisp
(use-package :cl-llm-provider)
(use-package :cl-llm-provider.tools)

;; Define a simple search tool
(define-tool "search_web"
  "Search the web for information"
  '((:name "query" :type :string :description "Search query")
    (:name "limit" :type :integer :description "Max results"))
  :required '("query")
  :safety-level :safe
  :categories '(:search :external-api)
  :handler (lambda (args)
             (format nil "Searching for: ~A" (getf args :query))))

;; Register and use
(let ((registry (make-tool-registry :name "search-app")))
  (register-tool registry (define-tool "search_web" ...))

  ;; Provide to LLM
  (let ((response (complete '((:role "user" :content "Find information about Lisp"))
                            :tool-registry registry)))
    (print response)))
```

### Example 2: Dangerous Tool with Approval

```lisp
;; Define a dangerous operation requiring approval
(define-tool "delete_file"
  "Delete a file from the filesystem"
  '((:name "path" :type :string :description "File path"))
  :required '("path")
  :safety-level :dangerous
  :categories '(:filesystem :destructive)
  :requires-approval :always
  :parameter-validators '(("path" . (:pattern "^/tmp/")))
  :on-start (lambda (call args)
              (format t "~&[WARNING] About to delete: ~A~%" (getf args :path)))
  :handler (lambda (args)
             (let ((path (getf args :path)))
               (if (uiop:file-exists-p path)
                   (progn (delete-file path) "File deleted")
                   "File not found"))))

;; Use with interactive approval
(let ((registry (make-tool-registry :name "file-app")))
  (register-tool registry (define-tool "delete_file" ...))

  (let ((response (complete messages :tool-registry registry)))
    (when (response-tool-calls response)
      (execute-tool-calls response
                          :registry registry
                          :approval-callback (make-interactive-approval-callback)))))
```

### Example 3: Full Application with Multiple Tools

```lisp
(use-package :cl-llm-provider)
(use-package :cl-llm-provider.tools)

;; Define tool registry
(defvar *app-tools* (make-tool-registry
                      :name "assistant-app"
                      :default-safety-level :safe))

;; Define tools
(defvar *tools*
  (list
    (define-tool "search"
      "Search for information"
      '((:name "query" :type :string))
      :categories '(:search)
      :safety-level :safe
      :handler (lambda (args) (format nil "Found results for ~A" (getf args :query))))

    (define-tool "read_file"
      "Read file contents"
      '((:name "path" :type :string))
      :categories '(:filesystem)
      :safety-level :safe
      :parameter-validators '(("path" . (:pattern "^/data/")))
      :handler (lambda (args) (uiop:read-file-string (getf args :path))))

    (define-tool "write_file"
      "Write to a file"
      '((:name "path" :type :string) (:name "content" :type :string))
      :categories '(:filesystem)
      :safety-level :moderate
      :parameter-validators '(("path" . (:pattern "^/data/")))
      :requires-approval :if-dangerous
      :handler (lambda (args)
                 (with-open-file (f (getf args :path) :direction :output)
                   (write-string (getf args :content) f))
                 "File written"))

    (define-tool "delete_file"
      "Delete a file"
      '((:name "path" :type :string))
      :categories '(:filesystem :destructive)
      :safety-level :dangerous
      :parameter-validators '(("path" . (:pattern "^/tmp/")))
      :requires-approval :always
      :handler (lambda (args)
                 (delete-file (getf args :path))
                 "File deleted"))))

;; Register all tools
(dolist (tool *tools*)
  (register-tool *app-tools* tool))

;; Set up hooks for logging
(setf (registry-global-hooks *app-tools*)
      (list :on-start (lambda (call args)
                        (format t "~&[EXEC] Starting: ~A~%" (tool-call-name call)))
            :on-complete (lambda (call args result)
                           (format t "~&[EXEC] Completed: ~A~%" (tool-call-name call)))))

;; Run conversation
(defun chat (user-message)
  "Run a single turn of conversation"
  (let* ((messages `((:role "user" :content ,user-message)))
         (response (complete messages :tool-registry *app-tools*)))

    ;; If tools were called, execute them
    (if (response-tool-calls response)
        (let ((results (execute-tool-calls response
                                            :registry *app-tools*
                                            :max-safety-level :moderate
                                            :approval-callback (make-interactive-approval-callback))))
          ;; Continue conversation with tool results
          (complete (append messages
                            (list (:role "assistant" :content (response-content response)))
                            (execution-results-to-tool-messages results))))
        (response-content response))))

;; Use it
(print (chat "Search for information about Common Lisp"))
```

### Example 4: Dynamic Tool Discovery

```lisp
(use-package :cl-llm-provider.tools)

;; Create registry with many tools
(defvar *tools* (make-tool-registry :name "full-app"))

;; ... register many tools ...

;; Create a filtered set for different contexts

;; For read-only operations
(defparameter *safe-tools*
  (tools-for-llm :registry *tools* :max-safety-level :safe))

;; For administrative interface
(defparameter *admin-tools*
  (tools-for-llm :registry *tools*))

;; For data processing
(defparameter *data-tools*
  (search-tools *tools* :categories '(:database :calculation)))

;; For file operations
(defparameter *file-tools*
  (search-tools *tools* :categories '(:filesystem)))

;; Use appropriate tools in different contexts
(let ((user-role "admin"))
  (complete messages
           :tools (case user-role
                    (admin *admin-tools*)
                    (user *safe-tools*))))
```

## Best Practices

1. **Set safety levels appropriately**: Use `:dangerous` for operations that cannot be easily undone
2. **Validate parameters**: Always validate user-controlled parameters, especially paths and SQL queries
3. **Use categories**: Organize tools logically for discovery and filtering
4. **Require approvals**: Always require approval for `:destructive` and `:payment` category tools
5. **Log operations**: Use hooks to log tool executions for audit trails
6. **Test validators**: Ensure validators work correctly with edge cases
7. **Filter by safety**: Provide only safe tools unless explicitly authorized
8. **Handle errors gracefully**: Catch and handle tool execution errors appropriately
9. **Isolate tools**: Use separate registries for different application contexts
10. **Document handlers**: Include clear docstrings explaining what each tool does

## Migration Guide

Existing code using `define-tool` continues to work without modification. To adopt new features:

1. **Add safety levels** to tools based on risk assessment
2. **Categorize tools** for discovery
3. **Create a registry** to manage tools
4. **Add validators** for parameters that need validation
5. **Implement approval** for sensitive operations
6. **Add hooks** for logging or metrics

All changes are backward compatible and can be adopted incrementally.
