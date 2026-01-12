(in-package :cl-llm-provider)

;;;; Observability Hooks
;;;;
;;;; Provides callback mechanisms for logging, tracing, and monitoring
;;;; LLM API calls.

(defstruct hooks
  "Container for observability hooks.

Supported hook types:
  :before-request - (lambda (provider model messages) ...)
  :after-response - (lambda (provider model response timing) ...)
  :on-error - (lambda (provider model error) ...)
  :on-stream-chunk - (lambda (provider model chunk) ...)"
  (before-request nil :type list)
  (after-response nil :type list)
  (on-error nil :type list)
  (on-stream-chunk nil :type list))

(defun add-hook (hooks hook-type function)
  "Add FUNCTION to HOOKS for HOOK-TYPE.

HOOKS - hooks structure from make-hooks
HOOK-TYPE - One of :before-request, :after-response, :on-error, :on-stream-chunk
FUNCTION - Callback function

Returns HOOKS (for chaining)."
  (ecase hook-type
    (:before-request
     (push function (hooks-before-request hooks)))
    (:after-response
     (push function (hooks-after-response hooks)))
    (:on-error
     (push function (hooks-on-error hooks)))
    (:on-stream-chunk
     (push function (hooks-on-stream-chunk hooks))))
  hooks)

(defun remove-hook (hooks hook-type function)
  "Remove FUNCTION from HOOKS for HOOK-TYPE.

Returns HOOKS (for chaining)."
  (ecase hook-type
    (:before-request
     (setf (hooks-before-request hooks)
           (remove function (hooks-before-request hooks))))
    (:after-response
     (setf (hooks-after-response hooks)
           (remove function (hooks-after-response hooks))))
    (:on-error
     (setf (hooks-on-error hooks)
           (remove function (hooks-on-error hooks))))
    (:on-stream-chunk
     (setf (hooks-on-stream-chunk hooks)
           (remove function (hooks-on-stream-chunk hooks)))))
  hooks)

(defun invoke-hooks (hooks hook-type &rest args)
  "Invoke all hooks of HOOK-TYPE with ARGS.

Errors in hooks are caught and logged, not propagated."
  (let ((hook-list (ecase hook-type
                    (:before-request (hooks-before-request hooks))
                    (:after-response (hooks-after-response hooks))
                    (:on-error (hooks-on-error hooks))
                    (:on-stream-chunk (hooks-on-stream-chunk hooks)))))
    (dolist (hook hook-list)
      (handler-case
          (apply hook args)
        (error (e)
          ;; Log but don't propagate hook errors
          (warn "Observability hook error: ~A" e))))))

;;; Global hooks variable
(defvar *global-hooks* nil
  "Global hooks applied to all requests when non-nil.
Set with (setf *global-hooks* (make-hooks)) and add hooks.")
