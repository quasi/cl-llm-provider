# Enhanced Tools Quick Start

Get started with enhanced tools in 5 minutes.

## 1. Basic Tool Definition

```lisp
(use-package :cl-llm-provider)

(define-tool "search"
  "Search the web"
  '((:name "query" :type :string))
  :required '("query")
  :handler (lambda (args)
             (format nil "Results for: ~A" (getf args :query))))
```

**That's it!** Tools work exactly as before. New features are optional.

## 2. Add Safety Levels

```lisp
;; Safe - read-only, no risk
(define-tool "search"
  "Search the web"
  '((:name "query" :type :string))
  :safety-level :safe        ; NEW
  :handler (lambda (args) ...))

;; Dangerous - irreversible operations
(define-tool "delete_file"
  "Delete a file"
  '((:name "path" :type :string))
  :safety-level :dangerous   ; NEW
  :requires-approval :always ; NEW - require approval
  :handler (lambda (args) ...))
```

## 3. Add Categories

```lisp
(define-tool "query_db"
  "Query database"
  '((:name "sql" :type :string))
  :categories '(:database :search)  ; NEW
  :handler (lambda (args) ...))
```

**Predefined categories**: `:search`, `:database`, `:filesystem`, `:payment`, `:destructive`, etc.

## 4. Add Validators

```lisp
(define-tool "update_user"
  "Update user record"
  '((:name "id" :type :string)
    (:name "age" :type :integer))
  :parameter-validators         ; NEW
  '(("id" . (:pattern "^[0-9]+$"))
    ("age" . (:type :integer :min 0 :max 150)))
  :handler (lambda (args) ...))
```

## 5. Create Registry

```lisp
(use-package :cl-llm-provider.tools)

;; Create registry
(defvar *tools* (make-tool-registry :name "my-app"))

;; Register tools
(register-tool *tools* search-tool)
(register-tool *tools* delete-tool)

;; Find tools
(find-tool *tools* "search")
(tools-by-category :database :registry *tools*)

;; Get safe tools only
(tools-for-llm :registry *tools* :max-safety-level :safe)
```

## 6. Add Hooks

```lisp
(define-tool "process"
  "Process data"
  '((:name "data" :type :string))
  :on-start (lambda (call args)
              (format t "Starting: ~A~%" (tool-call-name call)))
  :on-complete (lambda (call args result)
                 (format t "Complete: ~A~%" (tool-call-name call)))
  :on-error (lambda (call args condition)
              (format t "Error: ~A~%" condition))
  :handler (lambda (args) ...))
```

## 7. Execute Tools

```lisp
;; Single tool
(let ((tool (find-tool *tools* "search"))
      (call (make-instance 'tool-call
                          :id "call-1"
                          :name "search"
                          :arguments '(:query "lisp"))))
  (execute-tool tool call :registry *tools*))

;; All tools from LLM response
(let ((response (complete messages :tools (tools-for-llm :registry *tools*))))
  (when (response-tool-calls response)
    (let ((results (execute-tool-calls response :registry *tools*)))
      ;; Continue conversation with results
      (complete (append messages (execution-results-to-tool-messages results))))))
```

## 8. Add Approval

```lisp
;; Automatic approval
(let ((callback (make-auto-approve-callback)))
  (execute-tool tool call :approval-callback callback))

;; Interactive approval
(let ((callback (make-interactive-approval-callback)))
  (execute-tool tool call :approval-callback callback))
  ;; User sees: [A]pprove / [R]eject / [E]dit arguments:

;; Safety-based approval
(let ((callback (make-safety-based-callback :max-level :moderate)))
  (execute-tool tool call :approval-callback callback))
```

## 9. Complete Example

```lisp
(use-package :cl-llm-provider)
(use-package :cl-llm-provider.tools)

;; 1. Define tools
(define-tool "search"
  "Search for information"
  '((:name "query" :type :string))
  :safety-level :safe
  :categories '(:search)
  :handler (lambda (args) (format nil "Results for: ~A" (getf args :query))))

(define-tool "delete_file"
  "Delete a file"
  '((:name "path" :type :string))
  :safety-level :dangerous
  :categories '(:filesystem :destructive)
  :requires-approval :always
  :parameter-validators '(("path" . (:pattern "^/tmp/")))
  :handler (lambda (args) (delete-file (getf args :path)) "Deleted"))

;; 2. Create registry
(defvar *registry* (make-tool-registry :name "my-app"))

;; 3. Register tools
(dolist (tool (list search-tool delete-tool))
  (register-tool *registry* tool))

;; 4. Use in conversation
(defun chat (message)
  (let* ((response (complete `((:role "user" :content ,message))
                             :tools (tools-for-llm :registry *registry*))))
    (if (response-tool-calls response)
        (let ((results (execute-tool-calls response
                                           :registry *registry*
                                           :approval-callback (make-interactive-approval-callback))))
          (execution-results-to-tool-messages results))
        (response-content response))))

;; 5. Call it
(chat "Search for Lisp information")
```

## Common Patterns

### Pattern 1: Safe Tools for Public API

```lisp
;; Only provide safe, read-only tools
(complete messages
         :tools (tools-for-llm :registry *registry*
                              :max-safety-level :safe))
```

### Pattern 2: Admin Operations with Approval

```lisp
;; All tools available, but require approval for dangerous ones
(execute-tool-calls response
                    :registry *registry*
                    :approval-callback (make-interactive-approval-callback))
```

### Pattern 3: Category-Specific Tools

```lisp
;; Only database-related tools
(complete messages
         :tools (search-tools *registry* :categories '(:database)))

;; Only payment tools
(complete messages
         :tools (search-tools *registry* :categories '(:payment)))
```

### Pattern 4: Audit Logging

```lisp
;; Add global hooks to registry
(setf (registry-global-hooks *registry*)
      (list
       :on-start (lambda (call args)
                   (log "Tool executed: ~A" (tool-call-name call)))
       :on-complete (lambda (call args result)
                      (log "Tool succeeded: ~A" (tool-call-name call)))
       :on-error (lambda (call args condition)
                   (log "Tool failed: ~A: ~A" (tool-call-name call) condition))))
```

## Key Types & Functions

### Tool Definition
```lisp
(define-tool name description parameters
  &key required safety-level categories requires-approval
       parameter-validators on-start on-complete on-error
       handler metadata)
```

### Registry
```lisp
(make-tool-registry :name "..." :default-safety-level :safe)
(register-tool registry tool)
(find-tool registry "tool_name")
(tools-for-llm :registry registry :max-safety-level :safe)
(search-tools registry :categories '(:database))
```

### Validators
```lisp
(make-range-validator min max)
(make-pattern-validator regex)
(make-length-validator :min-length 3 :max-length 100)
(make-enum-validator '("a" "b" "c"))
```

### Execution
```lisp
(execute-tool tool call :registry registry :approval-callback callback)
(execute-tool-calls response :registry registry)
(execution-results-to-tool-messages results)
```

### Approval
```lisp
(make-auto-approve-callback)
(make-interactive-approval-callback :stream *standard-input*)
(make-safety-based-callback :max-level :moderate)
```

## Troubleshooting

### "Tool validation failed"
Make sure all required parameters are present and match validators:
```lisp
(define-tool "my_tool"
  ...
  :parameter-validators
  '(("id" . (:pattern "^[0-9]+$")))  ; Must match pattern
  ...)
```

### "Tool safety violation"
Tool exceeds maximum safety level. Increase limit or remove tool:
```lisp
(execute-tool tool call :max-safety-level :dangerous)
```

### "Tool approval required"
Tool needs approval callback:
```lisp
(execute-tool tool call
              :approval-callback (make-interactive-approval-callback))
```

### "Tool not found in registry"
Make sure tool is registered:
```lisp
(register-tool *registry* my-tool)
(find-tool *registry* "tool_name")  ; Check it exists
```

## Next Steps

- Read **TOOLS-ADVANCED.md** for comprehensive guide
- Read **TOOLS-API-REFERENCE.md** for detailed API docs
- Check **examples/tools-advanced-examples.lisp** for more examples
- Look at **tests/test-tools-enhanced.lisp** for test patterns

## Full Example With Explanation

```lisp
(use-package :cl-llm-provider)
(use-package :cl-llm-provider.tools)

;; STEP 1: Define tools with safety and validation
(defvar *get_weather*
  (define-tool "get_weather"
    "Get current weather for a location"
    '((:name "location" :type :string :description "City name"))
    :required '("location")
    :safety-level :safe                        ; Read-only, safe
    :categories '(:search :external-api)       ; For discovery
    :handler (lambda (args)
              ;; In real app: call weather API
              (format nil "Weather for ~A: Sunny, 72°F"
                      (getf args :location)))))

(defvar *delete_data*
  (define-tool "delete_data"
    "Permanently delete user data"
    '((:name "user_id" :type :string))
    :required '("user_id")
    :safety-level :dangerous                   ; Irreversible!
    :categories '(:destructive :admin)         ; For categorization
    :requires-approval :always                 ; Always require approval
    :parameter-validators
    '(("user_id" . (:pattern "^user-[0-9]+$")))  ; Validate format
    :handler (lambda (args)
              ;; Delete user data
              (format nil "Deleted user: ~A" (getf args :user_id)))))

;; STEP 2: Create and populate registry
(defvar *registry* (make-tool-registry :name "my-api"))
(register-tool *registry* *get_weather*)
(register-tool *registry* *delete_data*)

;; STEP 3: Use different tool sets for different contexts
(defvar *public-tools*
  ;; Public API: only safe tools
  (tools-for-llm :registry *registry* :max-safety-level :safe))

(defvar *admin-tools*
  ;; Admin interface: all tools
  (list-tools *registry*))

;; STEP 4: Execute with appropriate controls
(defun execute-for-public (response)
  ;; Public: no approval needed (all safe)
  (execute-tool-calls response :registry *registry*))

(defun execute-for-admin (response)
  ;; Admin: dangerous tools need approval
  (execute-tool-calls response
                      :registry *registry*
                      :approval-callback (make-interactive-approval-callback)))

;; STEP 5: Use in conversation
(complete `((:role "user" :content "What's the weather in NYC?"))
         :tools *public-tools*)      ; Only get_weather available

(complete `((:role "user" :content "Delete all user data from 2020"))
         :tools *admin-tools*)       ; get_weather + delete_data available
                                     ; delete_data will require approval
```

That's it! You now have:
- ✅ Type-safe tools with validation
- ✅ Risk classification with safety levels
- ✅ Easy discovery with categories
- ✅ User approval workflows
- ✅ Audit logging with hooks
- ✅ Flexible registry management

Happy building!
