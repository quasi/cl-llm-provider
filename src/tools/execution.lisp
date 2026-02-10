;;; ABOUTME: Tool execution with full lifecycle (validation, safety, approval, hooks, handler)
(in-package :cl-llm-provider.tools)

;;;; Execution Context

(defclass tool-execution-context ()
  ((tool-call :initarg :tool-call
              :reader context-tool-call
              :documentation "The tool-call object being executed.")
   (tool-definition :initarg :tool-definition
                    :reader context-tool-definition
                    :documentation "The tool-definition being invoked.")
   (arguments :initarg :arguments
              :accessor context-arguments
              :documentation "Validated and processed arguments.")
   (start-time :initform nil
               :accessor context-start-time
               :documentation "Internal-real-time when execution started.")
   (end-time :initform nil
             :accessor context-end-time
             :documentation "Internal-real-time when execution completed.")
   (approval-status :initform nil
                    :accessor context-approval-status
                    :documentation "Approval result: NIL, :approved, :rejected, or :edited.")
   (edited-arguments :initform nil
                     :accessor context-edited-arguments
                     :documentation "Arguments after human editing (if approval was :edited).")
   (result :initform nil
           :accessor context-result
           :documentation "Result of tool execution.")
   (error-condition :initform nil
                    :accessor context-error
                    :documentation "Error condition if execution failed."))
  (:documentation "Context object tracking tool execution state.
Mutable: approval-status, edited-arguments, and arguments are updated during
the approval phase. result and error-condition are set after handler execution.
Callers should treat context as read-only after execute-tool returns."))

(defmethod print-object ((ctx tool-execution-context) stream)
  (print-unreadable-object (ctx stream :type t)
    (format stream "~A ~A"
            (when (context-tool-call ctx)
              (tool-call-name (context-tool-call ctx)))
            (or (context-approval-status ctx) "pending"))))

;;;; Execute Tool (Main Entry Point)

(defgeneric execute-tool (tool-definition tool-call
                          &key registry skip-approval skip-validation
                               approval-callback max-safety-level)
  (:documentation "Execute a tool with full lifecycle handling.

   TOOL-DEFINITION - the tool to execute (must have :handler)
   TOOL-CALL - the tool-call object from LLM response
   REGISTRY - optional registry for global hooks and default approval callback
   SKIP-APPROVAL - if T, skip approval even if tool requires it
   SKIP-VALIDATION - if T, skip parameter validation
   APPROVAL-CALLBACK - explicit approval callback (overrides registry default)
   MAX-SAFETY-LEVEL - maximum allowed safety level (signals tool-safety-violation if exceeded)

   Execution flow:
   1. Check safety level against max-safety-level
   2. Validate arguments (unless skip-validation)
   3. Request approval if required (unless skip-approval)
   4. Invoke :on-start hook
   5. Execute tool handler
   6. Invoke :on-complete or :on-error hook
   7. Return result

   Signals:
   - tool-safety-violation if tool exceeds max-safety-level
   - tool-validation-error if argument validation fails
   - tool-approval-error if approval is rejected
   - tool-approval-required if approval needed but no callback available
   - Any error from the tool handler itself

   Returns the result of the tool handler, or signals an error."))

(defmethod execute-tool ((tool tool-definition) (call tool-call)
                         &key registry skip-approval skip-validation
                              approval-callback max-safety-level)
  "Execute tool with full lifecycle."
  (let* ((arguments (tool-call-arguments call))
         (context (make-instance 'tool-execution-context
                                 :tool-call call
                                 :tool-definition tool
                                 :arguments arguments)))

    ;; Check handler exists
    (unless (tool-handler tool)
      (error "Tool ~A has no handler function" (tool-name tool)))

    ;; Step 1: Safety check
    (when max-safety-level
      (unless (safety-level<= (tool-safety-level tool) max-safety-level)
        (error 'tool-safety-violation
               :tool tool
               :required-level max-safety-level
               :actual-level (tool-safety-level tool))))

    ;; Step 2: Validate arguments
    (unless skip-validation
      (validate-tool-arguments tool arguments))

    ;; Step 3: Approval
    (unless skip-approval
      (when (needs-approval-p tool)
        (let ((callback (or approval-callback
                            (and registry (registry-approval-callback registry)))))
          (multiple-value-bind (decision new-args reason)
              (request-tool-approval tool call arguments :callback callback)
            (setf (context-approval-status context) decision)
            (case decision
              (:rejected
               (error 'tool-approval-error
                      :tool tool
                      :tool-call call
                      :reason reason))
              (:edited
               (setf (context-edited-arguments context) new-args)
               (setf arguments new-args)
               (setf (context-arguments context) new-args))
              (:approved
               ;; Continue with execution
               ))))))

    ;; Mark as approved if we got here without needing approval
    (unless (context-approval-status context)
      (setf (context-approval-status context) :approved))

    ;; Step 4: Invoke :on-start hook
    (invoke-tool-hook :on-start tool call arguments)
    (when registry
      (invoke-global-hooks registry :on-start call arguments))

    ;; Record start time
    (setf (context-start-time context) (get-internal-real-time))

    ;; Step 5: Execute handler
    ;; Note: We intentionally catch all errors here to ensure lifecycle hooks
    ;; (:on-error) always fire. The error is re-signaled after hooks run.
    (handler-case
        (let ((result (funcall (tool-handler tool) arguments)))
          ;; Record end time
          (setf (context-end-time context) (get-internal-real-time))
          (setf (context-result context) result)

          ;; Step 6a: Invoke :on-complete hook
          (invoke-tool-hook :on-complete tool call arguments result)
          (when registry
            (invoke-global-hooks registry :on-complete call arguments result))

          ;; Return result
          result)

      (error (e)
        ;; Record error
        (setf (context-end-time context) (get-internal-real-time))
        (setf (context-error context) e)

        ;; Step 6b: Invoke :on-error hook
        (invoke-tool-hook :on-error tool call arguments e)
        (when registry
          (invoke-global-hooks registry :on-error call arguments e))

        ;; Re-signal the error
        (error e)))))

;;;; Execute Multiple Tool Calls

(defun/i execute-tool-calls (response &key registry skip-approval skip-validation
                                         approval-callback max-safety-level
                                         on-missing-tool)
  "Execute all tool calls from a completion response.

   RESPONSE - completion-response object with tool-calls
   REGISTRY - tool-registry to look up tools by name
   SKIP-APPROVAL - if T, skip approval for all tools
   SKIP-VALIDATION - if T, skip validation for all tools
   APPROVAL-CALLBACK - explicit callback (overrides registry default)
   MAX-SAFETY-LEVEL - maximum safety level for all tools
   ON-MISSING-TOOL - action when tool not found:
     - :error (default) - signal an error
     - :skip - skip the tool call, include nil in results
     - function - call with (tool-name tool-call), use return value as result

   Returns list of (tool-call . result) pairs.
   For error cases, result may be a condition object if :skip is used."
  (:feature tool-calling)
  (:purpose "Batch-execute all tool calls from a completion response")
  (let ((calls (response-tool-calls response))
        (results nil))
    (dolist (call calls)
      (let* ((tool-name (tool-call-name call))
             (tool (when registry (find-tool registry tool-name))))
        (cond
          ;; Tool found - execute it
          (tool
           (handler-case
               (let ((result (execute-tool tool call
                                           :registry registry
                                           :skip-approval skip-approval
                                           :skip-validation skip-validation
                                           :approval-callback approval-callback
                                           :max-safety-level max-safety-level)))
                 (push (cons call result) results))
             (error (e)
               ;; Store error as result
               (push (cons call e) results))))

          ;; Tool not found - handle according to on-missing-tool
          (t
           (case on-missing-tool
             (:skip
              (push (cons call nil) results))
             ((nil :error)
              (error "Tool ~S not found in registry" tool-name))
             (otherwise
              (if (functionp on-missing-tool)
                  (handler-case
                      (let ((result (funcall on-missing-tool tool-name call)))
                        (push (cons call result) results))
                    (error (e)
                      (push (cons call e) results)))
                  (error "Tool ~S not found in registry" tool-name))))))))
    (nreverse results)))

;;;; Result Processing Helpers

(defun/i execution-results-to-tool-messages (results)
  "Convert execution results to tool result messages for LLM continuation.

   RESULTS - list of (tool-call . result) pairs from execute-tool-calls

   Returns list of message plists suitable for appending to conversation."
  (:feature tool-calling)
  (:purpose "Convert execution results to tool-result messages for conversation continuation")
  (loop for (call . result) in results
        collect (make-tool-result
                 (tool-call-id call)
                 (etypecase result
                   (string result)
                   (condition (format nil "Error: ~A" result))
                   (null "null")
                   (t (format nil "~S" result)))
                 :is-error (typep result 'condition))))

;;; Telos Intent Annotations

(defintent tool-execution-context
  :feature tool-calling
  :purpose "Track mutable state through tool execution lifecycle"
  :role "Context object recording approval, timing, result, and error for a single tool invocation")

(defintent execute-tool
  :feature tool-calling
  :purpose "Full lifecycle tool execution: safety check, validation, approval, hooks, handler"
  :role "Primary entry point for executing a tool with all safety and lifecycle guarantees")
