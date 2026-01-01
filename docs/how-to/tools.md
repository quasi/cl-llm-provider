# How-To: Advanced Tool Features

Deep dive into tool safety, validation, categories, and approval workflows.

**Prerequisites**: [Tutorial: Tool Calling](../tutorials/02-tool-calling.md) complete.

---

## Tool Safety Levels

Mark tools with risk levels so you can filter by safety:

```lisp
(define-tool "search_web"
  "Search the internet"
  '((:name "query" :type :string))
  :required '("query")
  :safety-level :safe          ; Read-only, no side effects
  :handler (lambda (args) ...))

(define-tool "send_email"
  "Send an email"
  '((:name "to" :type :string)
    (:name "body" :type :string))
  :required '("to" "body")
  :safety-level :moderate       ; Has side effects but reversible
  :handler (lambda (args) ...))

(define-tool "delete_database"
  "Delete the entire database"
  '()
  :safety-level :dangerous      ; Irreversible, high risk
  :requires-approval :always    ; Require approval every time
  :handler (lambda (args) ...))
```

**Safety Levels**:
- `:safe` - Read-only, no risk. Can run without approval.
- `:moderate` - Has side effects but reversible. May need approval.
- `:dangerous` - Irreversible or high-risk. Should always require approval.

## Requiring Approval

For sensitive tools, require user approval before execution:

```lisp
;; Always require approval
(define-tool "transfer_money"
  "Transfer funds between accounts"
  '((:name "from" :type :string)
    (:name "to" :type :string)
    (:name "amount" :type :number))
  :required '("from" "to" "amount")
  :safety-level :dangerous
  :requires-approval :always
  :handler (lambda (args) ...))

;; Require approval only for large amounts
(define-tool "transfer_money_conditional"
  "Transfer funds"
  '((:name "amount" :type :number))
  :required '("amount")
  :requires-approval (lambda (args)
                      (> (getf args :amount) 1000))  ; Approve if > $1000
  :handler (lambda (args) ...))
```

When a tool requires approval, it won't execute until you approve it:

```lisp
;; When a tool call needs approval
(let ((tool-call (list :name "transfer_money" :arguments '(:amount 5000))))
  ;; Instead of auto-executing, ask user
  (format t "Tool requests approval: ~A~%" tool-call)
  (format t "Approve? (y/n): ")
  (if (string= (read-line) "y")
    ;; Execute if approved
    (handle-tool-call tool-call)
    ;; Reject if not approved
    (format t "Rejected.~%")))
```

## Tool Categories

Organize tools by function for filtering:

```lisp
(define-tool "search_web"
  "Search the internet"
  '((:name "query" :type :string))
  :required '("query")
  :categories '(:search :external-api)
  :handler (lambda (args) ...))

(define-tool "query_database"
  "Query the database"
  '((:name "sql" :type :string))
  :required '("sql")
  :categories '(:database :search)
  :handler (lambda (args) ...))

(define-tool "delete_file"
  "Delete a file"
  '((:name "path" :type :string))
  :required '("path")
  :categories '(:filesystem :destructive)
  :handler (lambda (args) ...))
```

**Predefined Categories**:
- `:search` - Information lookup
- `:database` - Database operations
- `:filesystem` - File operations
- `:network` - Network calls
- `:calculation` - Math/computation
- `:destructive` - Irreversible operations
- `:authentication` - Auth/security
- `:payment` - Financial transactions
- `:admin` - Administration
- `:external-api` - Third-party APIs
- `:ai` - AI/ML operations
- `:messaging` - Communications

**Custom categories allowed**: Use any keyword, not just predefined ones.

Filter tools by category:

```lisp
;; Get only safe tools
(let ((tools (list (get-tool "search_web")
                  (get-tool "query_database"))))
  (let ((safe-tools (filter-by-safety tools :safe)))
    (format t "Safe tools: ~A~%" (mapcar #'tool-name safe-tools))))

;; Get only read-only tools
(let ((readonly-tools (filter-by-categories tools '(:search :database))))
  (format t "Read-only tools: ~A~%" readonly-tools))

;; Get destructive tools (for manual review)
(let ((dangerous-tools (filter-by-categories tools '(:destructive))))
  (format t "Dangerous tools: ~A~%" dangerous-tools))
```

## Parameter Validation

Validate tool parameters before execution:

```lisp
(define-tool "delete_file"
  "Delete a file"
  '((:name "path" :type :string)
    (:name "force" :type :boolean))
  :required '("path")
  ;; Validate parameters
  :parameter-validators '(
    ;; Path must be absolute and in /tmp
    ("path" . (:pattern "^/tmp/"))
    ;; Don't allow wildcards
    ("path" . (:no-pattern "\\*"))
    ;; Force must be boolean
    ("force" . (:type :boolean)))
  :handler (lambda (args) ...))
```

**Validator Types**:
- `:pattern` - Regex pattern (must match)
- `:no-pattern` - Regex pattern (must NOT match)
- `:type` - Type check
- `:enum` - Must be one of allowed values
- `:min` / `:max` - Numeric range
- `:length` - String length

Example validators:

```lisp
:parameter-validators '(
  ;; URL must start with https://
  ("url" . (:pattern "^https://"))

  ;; Email must be valid
  ("email" . (:pattern "^[^@]+@[^@]+\\.[^@]+$"))

  ;; Port must be 80, 443, or 8080
  ("port" . (:enum (80 443 8080)))

  ;; Batch size between 1 and 100
  ("batch_size" . (:min 1 :max 100))

  ;; API key must be at least 32 chars
  ("api_key" . (:length (:min 32)))
)
```

## Tool Lifecycle Hooks

Execute code at different points in a tool's lifecycle:

```lisp
(define-tool "fetch_url"
  "Fetch a web page"
  '((:name "url" :type :string))
  :required '("url")

  ;; Called before execution
  :on-start (lambda (tool-call args)
             (format t "[TOOL] Starting: ~A ~A~%"
                     (getf tool-call :name) args)
             (format-time-string "%H:%M:%S"))

  ;; Called after successful execution
  :on-complete (lambda (tool-call args result)
                (format t "[TOOL] Completed: ~A~%" (getf tool-call :name))
                result)

  ;; Called on error
  :on-error (lambda (tool-call args condition)
            (format t "[TOOL] Error in ~A: ~A~%"
                    (getf tool-call :name) condition)
            nil)

  :handler (lambda (args)
            (fetch-page (getf args :url))))
```

**Use cases**:
- **`:on-start`** - Log when tools are called, increment counters
- **`:on-complete`** - Clean up resources, update databases
- **`:on-error`** - Log errors, send alerts, rollback changes

## Tool Metadata

Attach arbitrary metadata to tools:

```lisp
(define-tool "translate"
  "Translate text"
  '((:name "text" :type :string)
    (:name "language" :type :string))
  :required '("text" "language")
  :metadata '(
    :api-endpoint "https://api.example.com/translate"
    :rate-limit 100  ; Requests per minute
    :cost-per-call 0.001
    :latency-ms 500
    :requires-admin t)
  :handler (lambda (args) ...))

;; Access metadata
(let ((tool (get-tool "translate")))
  (format t "Cost per call: $~A~%" (getf (tool-metadata tool) :cost-per-call)))
```

## Tool Registry and Discovery

List and filter tools:

```lisp
;; List all tools
(dolist (tool (list-tools))
  (format t "~A: ~A~%" (tool-name tool) (tool-description tool)))

;; Find tools by name
(get-tool "search_web")

;; Find tools by category
(let ((search-tools (filter-tools-by-category :search)))
  ...)

;; Find safe tools
(let ((safe-tools (filter-tools-by-safety :safe)))
  ...)

;; Find tools that require approval
(let ((approval-tools (filter-tools (lambda (tool)
                                     (tool-requires-approval tool)))))
  ...)
```

## Error Handling in Tools

Handle errors gracefully:

```lisp
(define-tool "fetch_data"
  "Fetch data from API"
  '((:name "endpoint" :type :string))
  :required '("endpoint")
  :on-error (lambda (tool-call args condition)
            ;; Log the error
            (format t "Tool error: ~A~%" condition)
            ;; Return error message instead of crashing
            (format nil "Error fetching ~A: ~A"
                   (getf args :endpoint) condition))
  :handler (lambda (args)
           (handler-case
             (fetch-api-data (getf args :endpoint))
             (network-error (e)
              (error "Network error: ~A" e))
             (timeout-error (e)
              (error "Timeout: ~A" e))
             (error (e)
              (error "Unknown error: ~A" e)))))
```

## Complete Example: Payment Tool

A real-world tool with all safety features:

```lisp
(define-tool "send_payment"
  "Send payment to a recipient"
  '((:name "recipient" :type :string)
    (:name "amount" :type :number)
    (:name "description" :type :string))
  :required '("recipient" "amount")

  ;; Safety configuration
  :safety-level :dangerous
  :requires-approval :always
  :categories '(:payment :destructive)

  ;; Parameter validation
  :parameter-validators '(
    ;; Recipient must be valid email
    ("recipient" . (:pattern "^[^@]+@[^@]+\\.[^@]+$"))
    ;; Amount must be positive and under $10k
    ("amount" . (:min 0.01 :max 10000)))

  ;; Metadata
  :metadata '(:api-cost 0.002 :requires-2fa t)

  ;; Lifecycle
  :on-start (lambda (call args)
            (format t "[PAY] Initiating payment to ~A for $~A~%"
                    (getf args :recipient) (getf args :amount)))

  :on-complete (lambda (call args result)
               (format t "[PAY] Payment confirmed: ~A~%" result)
               ;; Log to database, send confirmation email
               )

  :on-error (lambda (call args condition)
            (format t "[PAY] Payment failed: ~A~%" condition)
            ;; Alert administrator
            )

  ;; Actual implementation
  :handler (lambda (args)
           (let ((recipient (getf args :recipient))
                 (amount (getf args :amount)))
             ;; In reality, call payment API with 2FA, etc.
             (format nil "Payment of $~A sent to ~A"
                    amount recipient))))
```

## Testing Tools

See [How-To: Testing Tools](testing.md) for complete testing guide.

## Troubleshooting

**Tool calls not happening?**
- Check that tool is registered: `(get-tool "name")`
- Verify tool description is clear
- Ensure parameters are well-documented

**Tool validation failing?**
- Review validator patterns: `(tool-parameter-validators tool)`
- Test patterns manually: `(cl-ppcre:scan pattern input)`

**Approval not working?**
- Check `:requires-approval` is set correctly
- Verify approval function returns boolean

---

**See Also**:
- [Tutorial: Tool Calling](../tutorials/02-tool-calling.md)
- [How-To: Testing Tools](testing.md)
- [How-To: Error Handling](error-handling.md)
