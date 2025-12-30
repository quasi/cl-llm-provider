;;; ABOUTME: Approval system for tool execution with callback-based human-in-the-loop
(in-package :cl-llm-provider.tools)

;;;; Approval Checking

(defun needs-approval-p (tool-definition)
  "Check if TOOL-DEFINITION requires approval before execution.

   Returns T if approval is required based on:
   - requires-approval slot value (NIL, T, :always, :if-dangerous)
   - safety-level when requires-approval is :if-dangerous

   This function does NOT check if an approval callback is configured."
  (let ((req (tool-requires-approval tool-definition)))
    (cond
      ((null req) nil)
      ((eq req t) t)
      ((eq req :always) t)
      ((eq req :if-dangerous)
       (eq (tool-safety-level tool-definition) :dangerous))
      (t nil))))

;;;; Approval Protocol

(defgeneric request-tool-approval (tool-definition tool-call arguments &key callback)
  (:documentation "Request approval for tool execution.

   TOOL-DEFINITION - the tool being executed
   TOOL-CALL - the tool-call object from the LLM
   ARGUMENTS - the parsed arguments plist
   CALLBACK - approval callback function (optional, can use registry default)

   Returns multiple values:
   - decision: :approved, :rejected, or :edited
   - arguments: original or edited arguments (plist)
   - reason: optional reason string (for rejection)

   Signals tool-approval-required if no callback is available.
   Signals tool-approval-error if rejected (for convenience in execution flow)."))

(defmethod request-tool-approval ((tool tool-definition) tool-call arguments &key callback)
  "Default implementation using callback function."
  (unless callback
    (error 'tool-approval-required
           :tool tool
           :tool-call tool-call))

  (let ((result (funcall callback tool tool-call arguments)))
    (multiple-value-bind (decision new-args reason)
        (normalize-approval-result result arguments)
      (values decision new-args reason))))

;;;; Approval Result Normalization

(defun normalize-approval-result (result original-arguments)
  "Normalize approval callback result to standard format.

   Callbacks can return various formats:
   - T or :approved -> approved with original arguments
   - NIL or :rejected -> rejected without reason
   - (list :approved) -> approved with original arguments
   - (list :rejected reason) -> rejected with reason
   - (list :edited new-arguments) -> approved with modified arguments
   - (list :approved new-arguments) -> approved with modified arguments

   Returns multiple values:
   - decision: :approved, :rejected, or :edited
   - arguments: original or edited arguments
   - reason: rejection reason or NIL"
  (cond
    ;; Simple approval
    ((eq result t) (values :approved original-arguments nil))
    ((eq result :approved) (values :approved original-arguments nil))

    ;; Simple rejection
    ((null result) (values :rejected original-arguments nil))
    ((eq result :rejected) (values :rejected original-arguments nil))

    ;; List format
    ((listp result)
     (let ((action (first result))
           (payload (second result)))
       (case action
         (:approved
          (if payload
              (values :approved payload nil)
              (values :approved original-arguments nil)))
         (:rejected
          (values :rejected original-arguments payload))
         (:edited
          (values :edited payload nil))
         (otherwise
          (error "Invalid approval result format: ~S" result)))))

    (t (error "Invalid approval result: ~S" result))))

;;;; Approval Callback Helpers

(defun make-auto-approve-callback (&key (log-fn nil))
  "Create a callback that automatically approves all requests.
   Optionally logs approval if LOG-FN is provided."
  (lambda (tool tool-call arguments)
    (declare (ignore tool-call arguments))
    (when log-fn
      (funcall log-fn "Auto-approved: ~A" (tool-name tool)))
    :approved))

(defun make-auto-reject-callback (&key (reason "Automatic rejection"))
  "Create a callback that automatically rejects all requests."
  (lambda (tool tool-call arguments)
    (declare (ignore tool tool-call arguments))
    (list :rejected reason)))

(defun make-safety-based-callback (&key (max-level :moderate)
                                        (on-exceed :reject)
                                        (rejection-reason nil))
  "Create a callback that approves based on safety level.

   MAX-LEVEL - maximum safety level to auto-approve (:safe or :moderate)
   ON-EXCEED - action when tool exceeds max-level (:reject or :prompt)
   REJECTION-REASON - reason to give when rejecting

   Note: :prompt is a placeholder - actual prompting requires UI integration."
  (lambda (tool tool-call arguments)
    (declare (ignore tool-call arguments))
    (if (safety-level<= (tool-safety-level tool) max-level)
        :approved
        (case on-exceed
          (:reject (list :rejected (or rejection-reason
                                        (format nil "Tool ~A exceeds maximum safety level ~A"
                                                (tool-name tool) max-level))))
          (otherwise :rejected)))))

(defun make-interactive-approval-callback (&key (stream *query-io*))
  "Create a simple interactive approval callback for REPL use.

   Prompts user with Y/N/E (yes/no/edit) and handles response.
   For :edit, reads new arguments as a plist from the stream.

   STREAM - the stream to use for interaction (default *query-io*)"
  (lambda (tool tool-call arguments)
    (format stream "~&═══════════════════════════════════════~%")
    (format stream "Tool Approval Required~%")
    (format stream "═══════════════════════════════════════~%")
    (format stream "Tool: ~A~%" (tool-name tool))
    (format stream "Safety: ~A~%" (tool-safety-level tool))
    (format stream "Call ID: ~A~%" (tool-call-id tool-call))
    (format stream "Arguments: ~S~%" arguments)
    (format stream "───────────────────────────────────────~%")
    (format stream "[A]pprove / [R]eject / [E]dit arguments: ")
    (finish-output stream)
    (let ((input (read-line stream)))
      (cond
        ((member (char-upcase (char input 0)) '(#\A #\Y))
         :approved)
        ((member (char-upcase (char input 0)) '(#\R #\N))
         (format stream "Reason (optional): ")
         (finish-output stream)
         (let ((reason (read-line stream)))
           (if (string= reason "")
               :rejected
               (list :rejected reason))))
        ((char-equal (char input 0) #\E)
         (format stream "Enter new arguments plist: ")
         (finish-output stream)
         (let ((new-args (read stream)))
           (list :edited new-args)))
        (t
         (format stream "Invalid input. Rejecting.~%")
         :rejected)))))
