;;; ABOUTME: Practical examples of using enhanced tools functionality
;;; This file demonstrates real-world usage patterns for safety, categories,
;;; validators, registry, approval, hooks, and execution.

;;;; Setup - Load required packages

(use-package :cl-llm-provider)
(use-package :cl-llm-provider.tools)

;;;; Example 1: Simple Tool with Categories
;;;
;;; Demonstrates basic category usage for tool organization.

(define-tool "search_web"
  "Search the web for information"
  '((:name "query" :type :string :description "What to search for")
    (:name "limit" :type :integer :description "Max results (1-50)"))
  :required '("query")
  :safety-level :safe
  :categories '(:search :external-api)
  :parameter-validators '(("limit" . (:type :integer :min 1 :max 50)))
  :handler (lambda (args)
             ;; In a real app, this would call a search API
             (format nil "Search results for: ~A (~A results)"
                     (getf args :query)
                     (or (getf args :limit) 10))))

;;;; Example 2: Database Tool with Validation
;;;
;;; Demonstrates parameter validation to prevent SQL injection and bad data.

(define-tool "query_database"
  "Query the database with parameterized queries"
  '((:name "table" :type :string :description "Table name")
    (:name "where" :type :string :description "WHERE clause")
    (:name "limit" :type :integer :description "Result limit"))
  :required '("table")
  :safety-level :moderate
  :categories '(:database :search)
  :parameter-validators
  '(("table" . (:pattern "^[a-zA-Z_][a-zA-Z0-9_]*$"))  ; Valid table name
    ("where" . (:length-validator :max-length 500))     ; Prevent huge queries
    ("limit" . (:type :integer :min 1 :max 1000)))     ; Reasonable limits
  :handler (lambda (args)
             (format nil "Query: SELECT * FROM ~A WHERE ~A LIMIT ~A"
                     (getf args :table)
                     (getf args :where)
                     (or (getf args :limit) 100))))

;;;; Example 3: File System Tool with Approval
;;;
;;; Demonstrates approval workflow for destructive operations with logging hooks.

(define-tool "delete_file"
  "Delete a file from the server"
  '((:name "path" :type :string :description "Full path to delete"))
  :required '("path")
  :safety-level :dangerous
  :categories '(:filesystem :destructive)
  :requires-approval :always  ; Always require approval
  :parameter-validators '(("path" . (:pattern "^/data/uploads/")))  ; Only in safe dir
  :on-start (lambda (call args)
              (format t "~&[⚠️  WARNING] About to delete: ~A~%" (getf args :path))
              (force-output))
  :handler (lambda (args)
             (let ((path (getf args :path)))
               (if (probe-file path)
                   (progn (delete-file path)
                          (format nil "✓ Deleted: ~A" path))
                   (format nil "⚠ File not found: ~A" path)))))

;;;; Example 4: Payment Tool with Safety-Based Approval
;;;
;;; Demonstrates conditional approval based on safety level.

(define-tool "transfer_money"
  "Transfer funds between accounts"
  '((:name "from_account" :type :string :description "Source account ID")
    (:name "to_account" :type :string :description "Destination account ID")
    (:name "amount" :type :number :description "Amount in USD"))
  :required '("from_account" "to_account" "amount")
  :safety-level :dangerous
  :categories '(:payment :destructive)
  :requires-approval :always
  :parameter-validators
  '(("from_account" . (:pattern "^ACC-[0-9]{8}$"))
    ("to_account" . (:pattern "^ACC-[0-9]{8}$"))
    ("amount" . (:type :number :min 0.01 :max 100000)))
  :on-start (lambda (call args)
              (format t "~&━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%")
              (format t "💰 PAYMENT TRANSACTION~%")
              (format t "From: ~A~%" (getf args :from_account))
              (format t "To: ~A~%" (getf args :to_account))
              (format t "Amount: $~A~%" (getf args :amount))
              (format t "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%"))
  :handler (lambda (args)
             (format nil "Transferred $~A from ~A to ~A"
                     (getf args :amount)
                     (getf args :from_account)
                     (getf args :to_account))))

;;;; Example 5: Tool Registry with Discovery
;;;
;;; Demonstrates creating a registry and filtering tools by category/safety.

(defun create-app-registry ()
  "Create and populate tool registry for an application"
  (let ((registry (make-tool-registry
                    :name "my-assistant"
                    :default-safety-level :safe)))

    ;; Define and register tools
    (register-tool registry (define-tool "search_web" ...))
    (register-tool registry (define-tool "query_database" ...))
    (register-tool registry (define-tool "delete_file" ...))
    (register-tool registry (define-tool "transfer_money" ...))

    registry))

;; Use registry to discover tools for different contexts
(let ((registry (create-app-registry)))

  ;; For a public/user interface - only safe tools
  (tools-for-llm :registry registry :max-safety-level :safe)
  ; => (search_web)

  ;; For an admin interface - moderate and safe
  (tools-for-llm :registry registry :max-safety-level :moderate)
  ; => (search_web query_database)

  ;; For data operations - specific categories
  (search-tools registry :categories '(:database))
  ; => (query_database)

  ;; Get tools by category
  (tools-by-category :filesystem :registry registry)
  ; => (delete_file)
  )

;;;; Example 6: Registry with Global Hooks for Logging
;;;
;;; Demonstrates adding global hooks to a registry for audit trails.

(defun create-audited-registry ()
  "Create registry with audit logging hooks"
  (let ((registry (create-app-registry))
        (execution-log nil))  ; Simple log storage

    ;; Set up global hooks for audit trail
    (setf (registry-global-hooks registry)
          (list
           :on-start (lambda (call args)
                       (format t "~&[LOG] EXEC START: ~A~%" (tool-call-name call))
                       (push (list :start (tool-call-name call) (get-universal-time))
                             execution-log))

           :on-complete (lambda (call args result)
                          (format t "~&[LOG] EXEC COMPLETE: ~A~%" (tool-call-name call))
                          (push (list :complete (tool-call-name call) (get-universal-time))
                                execution-log))

           :on-error (lambda (call args condition)
                       (format t "~&[LOG] EXEC ERROR: ~A - ~A~%"
                               (tool-call-name call) condition)
                       (push (list :error (tool-call-name call) condition (get-universal-time))
                             execution-log))))

    registry))

;;;; Example 7: Interactive Approval Workflow
;;;
;;; Demonstrates user interaction for tool approval.

(defun interactive-tool-execution (registry user-message)
  "Execute tools with user approval in a REPL"
  (let* ((messages `((:role "user" :content ,user-message)))
         (response (complete messages
                             :tools (tools-for-llm :registry registry))))

    (if (response-tool-calls response)
        (let ((approval-callback (make-interactive-approval-callback
                                   :stream *standard-input*)))
          ;; Execute each tool with interactive approval
          (let ((results (execute-tool-calls response
                                              :registry registry
                                              :approval-callback approval-callback
                                              :max-safety-level :moderate)))
            ;; Convert to messages for continuation
            (execution-results-to-tool-messages results)))
        (response-content response))))

;;;; Example 8: Custom Approval Logic
;;;
;;; Demonstrates implementing custom approval strategies.

(defun create-approval-callback-with-rules ()
  "Create approval callback with custom business rules"
  (lambda (tool tool-call arguments)
    (let ((tool-name (tool-name tool))
          (safety-level (tool-safety-level tool)))

      ;; Rule 1: Auto-approve safe tools
      (when (eq safety-level :safe)
        (return-from create-approval-callback-with-rules :approved))

      ;; Rule 2: Reject dangerous operations outside business hours
      (when (eq safety-level :dangerous)
        (let ((hour (nth 2 (multiple-value-list (decode-universal-time (get-universal-time))))))
          (if (or (< hour 9) (> hour 17))  ; Outside 9am-5pm
              (return-from create-approval-callback-with-rules
                (list :rejected "Dangerous operations only allowed during business hours")))))

      ;; Rule 3: Require approval for high-value payments
      (when (string= tool-name "transfer_money")
        (let ((amount (getf arguments :amount)))
          (when (> amount 10000)
            (return-from create-approval-callback-with-rules
              (list :rejected "Payments over $10,000 require manager approval")))))

      ;; Default: approve moderate tools
      :approved)))

;;;; Example 9: Tool Execution with Error Handling
;;;
;;; Demonstrates proper error handling during tool execution.

(defun safe-execute-tool (tool call registry)
  "Execute tool with comprehensive error handling"
  (handler-case
      (execute-tool tool call :registry registry :max-safety-level :moderate)

    (tool-safety-violation (e)
      (format t "❌ Safety violation: ~A exceeds level ~A~%"
              (tool-name (error-tool e))
              (error-required-level e))
      (format nil "Tool ~A is too dangerous" (tool-name (error-tool e))))

    (tool-validation-error (e)
      (format t "❌ Validation error in parameter ~A~%"
              (error-parameter e))
      (format nil "Invalid parameter ~A: ~A"
              (error-parameter e)
              (error-value e)))

    (tool-approval-error (e)
      (format t "❌ Approval denied for ~A~%"
              (tool-name (error-tool e)))
      "Tool execution was not approved")

    (error (e)
      (format t "❌ Unexpected error: ~A~%" e)
      (format nil "Tool execution failed: ~A" e))))

;;;; Example 10: Complete Application
;;;
;;; A minimal but complete assistant application using all enhanced features.

(defun create-secure-assistant-registry ()
  "Create a fully-configured registry for a secure assistant"
  (let ((registry (make-tool-registry
                    :name "secure-assistant"
                    :default-safety-level :safe))
        (metrics (make-hash-table :test 'equal)))

    ;; Define tools with varying safety levels
    (dolist (tool (list
                   ;; Safe tools
                   (define-tool "search"
                     "Search for information"
                     '((:name "query" :type :string))
                     :safety-level :safe
                     :categories '(:search :external-api)
                     :handler (lambda (args)
                                (format nil "Found info on: ~A" (getf args :query))))

                   ;; Moderate tools
                   (define-tool "read_file"
                     "Read a file"
                     '((:name "path" :type :string))
                     :safety-level :safe
                     :categories '(:filesystem)
                     :parameter-validators '(("path" . (:pattern "^/data/")))
                     :handler (lambda (args) (uiop:read-file-string (getf args :path))))

                   ;; Dangerous tools
                   (define-tool "delete_file"
                     "Delete a file"
                     '((:name "path" :type :string))
                     :safety-level :dangerous
                     :categories '(:filesystem :destructive)
                     :requires-approval :always
                     :parameter-validators '(("path" . (:pattern "^/tmp/")))
                     :handler (lambda (args)
                                (delete-file (getf args :path))
                                "File deleted"))))
      (register-tool registry tool))

    ;; Set up approval with business rules
    (setf (registry-approval-callback registry)
          (create-approval-callback-with-rules))

    ;; Set up comprehensive hooks
    (setf (registry-global-hooks registry)
          (list
           :on-start (lambda (call args)
                       (let ((name (tool-call-name call)))
                         (format t "~&[EXEC ~A] ~A~%" (get-universal-time) name)
                         (incf (gethash name metrics 0))))

           :on-complete (lambda (call args result)
                          (format t "  ✓ Complete~%"))

           :on-error (lambda (call args condition)
                       (format t "  ✗ Error: ~A~%" condition))))

    registry))

;; Use the complete application
(defun assistant-chat (user-message)
  "Run a single turn of the assistant with tool support"
  (let* ((registry (create-secure-assistant-registry))
         (messages `((:role "user" :content ,user-message)))
         (response (complete messages
                             :tools (tools-for-llm :registry registry))))

    (when (response-tool-calls response)
      (format t "~&Assistant used tools~%")

      ;; Execute tools with user confirmation
      (let* ((approval-callback (make-interactive-approval-callback))
             (results (execute-tool-calls response
                                          :registry registry
                                          :approval-callback approval-callback)))

        ;; Continue conversation
        (complete (append messages
                         (list (:role "assistant" :content (response-content response)))
                         (execution-results-to-tool-messages results)))))

    (response-content response)))

;; Example usage:
;; (assistant-chat "Search for information about Common Lisp")
;; (assistant-chat "Delete the file /tmp/old.txt")  ; Will require approval

;;;; Example 11: Validator Composition
;;;
;;; Demonstrates creating complex validators from simple ones.

(define-tool "upload_file"
  "Upload a file to the server"
  '((:name "filename" :type :string)
    (:name "content" :type :string))
  :safety-level :moderate
  :categories '(:filesystem)
  :parameter-validators
  (list
   ;; Filename: not too long, valid characters, must be txt/pdf/doc
   ("filename" . (make-composite-validator
                   (make-length-validator :max-length 256)
                   (make-pattern-validator "^[a-zA-Z0-9._-]+\\.(txt|pdf|doc|docx)$")))

   ;; Content: reasonable size, valid UTF-8
   ("content" . (make-composite-validator
                  (make-length-validator :max-length 10000000)  ; 10MB
                  (lambda (x) (stringp x)))))
  :handler (lambda (args)
             (format nil "Uploaded: ~A (~A bytes)"
                     (getf args :filename)
                     (length (getf args :content)))))

;;;; Example 12: Registry Search and Filter
;;;
;;; Demonstrates powerful discovery capabilities.

(defun search-registry-examples ()
  "Show various ways to search and filter tools"
  (let ((registry (create-app-registry)))

    ;; Find all database tools
    (format t "Database tools: ~A~%"
            (mapcar #'tool-name (search-tools registry :categories '(:database))))

    ;; Find all destructive tools
    (format t "Destructive tools: ~A~%"
            (mapcar #'tool-name (search-tools registry :categories '(:destructive))))

    ;; Find tools by name pattern
    (format t "Search-related tools: ~A~%"
            (mapcar #'tool-name (search-tools registry :name-pattern ".*search.*")))

    ;; Find safe tools suitable for public API
    (format t "Public API tools: ~A~%"
            (mapcar #'tool-name (tools-for-llm :registry registry :max-safety-level :safe)))))

;;;; Running Examples
;;;
;;; Uncomment to run:

;; (assistant-chat "Search for Lisp programming language information")
;; (search-registry-examples)

;;; End of examples
