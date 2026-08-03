;;; ABOUTME: Internal package for enhanced tool functionality (validators, registry, approval, hooks, execution)
(in-package :cl-user)

(defpackage :cl-llm-provider.tools
  (:use :cl :cl-llm-provider)
  (:import-from :cl-llm-provider.intent
                #:defun/i
                #:defintent)
  (:import-from :alexandria
                :if-let
                :when-let
                :hash-table-plist
                :plist-hash-table)
  (:export
   ;; Categories
   #:*tool-categories*
   #:valid-category-p
   #:normalize-categories

   ;; Validators
   #:*built-in-validators*
   #:make-range-validator
   #:make-pattern-validator
   #:make-length-validator
   #:make-enum-validator
   #:make-type-validator
   #:make-composite-validator
   #:parse-validator-spec
   #:validate-parameter
   #:validate-tool-arguments

   ;; Registry
   #:tool-registry
   #:make-tool-registry
   #:*tool-registry*
   #:ensure-registry
   #:registry-name
   #:registry-tools
   #:registry-default-safety-level
   #:registry-approval-callback
   #:registry-global-hooks
   #:register-tool
   #:unregister-tool
   #:find-tool
   #:search-tools
   #:list-tools
   #:registry-tool-count
   ;; Convenience functions
   #:register
   #:find-tool-by-name
   #:tools-by-category
   #:safe-tools
   #:tools-for-llm

   ;; Safety
   #:safety-level-value
   #:safety-level<=

   ;; Approval
   #:needs-approval-p
   #:request-tool-approval
   #:normalize-approval-result
   #:make-auto-approve-callback
   #:make-auto-reject-callback
   #:make-safety-based-callback
   #:make-interactive-approval-callback

   ;; Hooks
   #:invoke-tool-hook

   ;; Execution
   #:tool-execution-context
   #:context-tool-call
   #:context-tool-definition
   #:context-arguments
   #:context-start-time
   #:context-approval-status
   #:context-edited-arguments
   #:execute-tool
   #:execute-tool-calls
   #:execution-results-to-tool-messages))
