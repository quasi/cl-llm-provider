;;; ABOUTME: Lifecycle hooks system for tool execution (on-start, on-complete, on-error)
(in-package :cl-llm-provider.tools)

;;;; Hook Types
;;;
;;; Three hook types are supported:
;;; - :on-start    (tool-call arguments) - called before execution
;;; - :on-complete (tool-call arguments result) - called after successful execution
;;; - :on-error    (tool-call arguments condition) - called on execution error

;;;; Hook Invocation

(defgeneric invoke-tool-hook (hook-type tool-definition tool-call &rest args)
  (:documentation "Invoke a lifecycle hook for a tool.

   HOOK-TYPE - keyword :on-start, :on-complete, or :on-error
   TOOL-DEFINITION - the tool being executed
   TOOL-CALL - the tool-call object from the LLM
   ARGS - additional arguments passed to the hook

   Hook signatures:
   - :on-start (tool-call arguments)
   - :on-complete (tool-call arguments result)
   - :on-error (tool-call arguments condition)

   Invokes both tool-specific hooks and registry global hooks (if registry provided).
   Errors in hooks are logged but do not interrupt execution."))

(defmethod invoke-tool-hook ((hook-type (eql :on-start)) tool-definition tool-call &rest args)
  "Invoke :on-start hook. ARGS should be (arguments)."
  (let ((arguments (first args)))
    ;; Tool-specific hook
    (when-let ((hook (tool-on-start tool-definition)))
      (safely-invoke-hook hook tool-call arguments
                          :on-error (lambda (e)
                                      (warn "Error in :on-start hook for ~A: ~A"
                                            (tool-name tool-definition) e))))))

(defmethod invoke-tool-hook ((hook-type (eql :on-complete)) tool-definition tool-call &rest args)
  "Invoke :on-complete hook. ARGS should be (arguments result)."
  (let ((arguments (first args))
        (result (second args)))
    ;; Tool-specific hook
    (when-let ((hook (tool-on-complete tool-definition)))
      (safely-invoke-hook hook tool-call arguments result
                          :on-error (lambda (e)
                                      (warn "Error in :on-complete hook for ~A: ~A"
                                            (tool-name tool-definition) e))))))

(defmethod invoke-tool-hook ((hook-type (eql :on-error)) tool-definition tool-call &rest args)
  "Invoke :on-error hook. ARGS should be (arguments condition)."
  (let ((arguments (first args))
        (condition (second args)))
    ;; Tool-specific hook
    (when-let ((hook (tool-on-error tool-definition)))
      (safely-invoke-hook hook tool-call arguments condition
                          :on-error (lambda (e)
                                      (warn "Error in :on-error hook for ~A: ~A"
                                            (tool-name tool-definition) e))))))

;;;; Registry Global Hooks

(defun/i invoke-global-hooks (registry hook-type tool-call &rest args)
  "Invoke global hooks from a registry.

   REGISTRY - tool-registry with global-hooks
   HOOK-TYPE - keyword :on-start, :on-complete, or :on-error
   TOOL-CALL - the tool-call object
   ARGS - arguments for the hook"
  (:feature tool-calling)
  (:purpose "Fire registry-wide lifecycle hooks for cross-cutting concerns")
  (when registry
    (let ((hooks (registry-global-hooks registry)))
      (when-let ((hook (getf hooks hook-type)))
        (safely-invoke-hook hook tool-call (first args) (second args)
                            :on-error (lambda (e)
                                        (warn "Error in global ~A hook: ~A"
                                              hook-type e)))))))

;;;; Hook Helper Functions

(defun/i safely-invoke-hook (hook &rest args)
  "Invoke HOOK with ARGS, catching and handling errors.

   Keyword argument :on-error can be a function to call with the error condition.
   Returns the hook's return value, or NIL if an error occurred."
  (:feature tool-calling)
  (:purpose "Error-safe hook invocation that prevents hook failures from disrupting execution")
  (let ((on-error-fn nil)
        (actual-args nil))
    ;; Find :on-error keyword position and extract positional args before it
    ;; TODO: accept :on-error via explicit &key.
    (let ((on-error-pos (position :on-error args)))
      (if on-error-pos
          (setf actual-args (subseq args 0 on-error-pos)
                on-error-fn (nth (1+ on-error-pos) args))
          (setf actual-args args)))

    (handler-case
        (apply hook actual-args)
      (error (e)
        (if on-error-fn
            (funcall on-error-fn e)
            (warn "Hook error with no handler: ~A" e))
        nil))))

;;;; Hook Utility Functions

(defun make-logging-hook (hook-type &key (stream *standard-output*) (format-fn nil))
  "Create a hook that logs execution information.

   HOOK-TYPE - :on-start, :on-complete, or :on-error
   STREAM - output stream for logging
   FORMAT-FN - optional custom formatting function"
  (case hook-type
    (:on-start
     (lambda (tool-call arguments)
       (if format-fn
           (funcall format-fn stream :on-start tool-call arguments)
           (format stream "~&[START] ~A with ~S~%"
                   (tool-call-name tool-call) arguments))))
    (:on-complete
     (lambda (tool-call arguments result)
       (declare (ignore arguments))
       (if format-fn
           (funcall format-fn stream :on-complete tool-call result)
           (format stream "~&[COMPLETE] ~A => ~S~%"
                   (tool-call-name tool-call) result))))
    (:on-error
     (lambda (tool-call arguments condition)
       (declare (ignore arguments))
       (if format-fn
           (funcall format-fn stream :on-error tool-call condition)
           (format stream "~&[ERROR] ~A: ~A~%"
                   (tool-call-name tool-call) condition))))))

(defun make-timing-hook (&key (on-start-action nil) (on-complete-action nil))
  "Create hooks that track execution timing.

   Returns a plist with :on-start and :on-complete hooks.
   ON-START-ACTION - optional function called with (tool-call start-time)
   ON-COMPLETE-ACTION - optional function called with (tool-call duration-ms)

   Example:
     (let ((hooks (make-timing-hook
                    :on-complete-action (lambda (call dur)
                                          (format t \"~A took ~Dms~%\" (tool-call-name call) dur)))))
       (setf (registry-global-hooks registry) hooks))"
  (let ((start-times (make-hash-table :test 'equal)))
    (list
     :on-start
     (lambda (tool-call arguments)
       (declare (ignore arguments))
       (let ((start (get-internal-real-time)))
         (setf (gethash (tool-call-id tool-call) start-times) start)
         (when on-start-action
           (funcall on-start-action tool-call start))))

     :on-complete
     (lambda (tool-call arguments result)
       (declare (ignore arguments result))
       (let* ((call-id (tool-call-id tool-call))
              (start (gethash call-id start-times))
              (end (get-internal-real-time))
              (duration-ms (when start
                             (round (* 1000 (/ (- end start)
                                               internal-time-units-per-second))))))
         (remhash call-id start-times)
         (when (and duration-ms on-complete-action)
           (funcall on-complete-action tool-call duration-ms))))

     :on-error
     (lambda (tool-call arguments condition)
       (declare (ignore arguments condition))
       ;; Clean up start-time entry on error to prevent hash-table leak
       (remhash (tool-call-id tool-call) start-times)))))

(defun combine-hooks (hook-type &rest hooks)
  "Combine multiple hooks of the same type into a single hook.
   All hooks are called in order. Errors in one hook don't prevent others."
  (lambda (&rest args)
    (dolist (hook hooks)
      (when hook
        (handler-case
            (apply hook args)
          (error (e)
            (warn "Error in combined ~A hook: ~A" hook-type e)))))))

;;; Telos Intent Annotations

(defintent invoke-tool-hook
  :feature tool-calling
  :purpose "Dispatch lifecycle hooks for tool execution events"
  :role "EQL-specialized generic dispatching :on-start, :on-complete, :on-error hooks")
