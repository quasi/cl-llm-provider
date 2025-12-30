(in-package :cl-llm-provider)

;;;; Condition Hierarchy

(define-condition llm-provider-error (error)
  ((provider :initarg :provider
             :initform nil
             :reader error-provider
             :documentation "The provider that signaled the error.")
   (message :initarg :message
            :initform nil
            :reader error-message
            :documentation "Error message."))
  (:documentation "Base condition for all cl-llm-provider errors.")
  (:report (lambda (c s)
             (format s "LLM Provider error~@[ (~A)~]~@[: ~A~]"
                     (when (error-provider c)
                       (type-of (error-provider c)))
                     (error-message c)))))

(define-condition provider-configuration-error (llm-provider-error)
  ((missing-key :initarg :missing-key
                :initform nil
                :reader error-missing-key
                :documentation "Name of the missing configuration key."))
  (:documentation "Signaled when required provider configuration is missing.")
  (:report (lambda (c s)
             (format s "Provider configuration error~@[: missing ~A~]~@[. ~A~]"
                     (error-missing-key c)
                     (error-message c)))))

(define-condition provider-api-error (llm-provider-error)
  ((status-code :initarg :status-code
                :initform nil
                :reader error-status-code
                :documentation "HTTP status code from the API.")
   (body :initarg :body
         :initform nil
         :reader error-body
         :documentation "Response body from the API."))
  (:documentation "Signaled when an API request fails.")
  (:report (lambda (c s)
             (let ((provider-type (when (error-provider c)
                                   (type-of (error-provider c)))))
               (format s "~&━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%")
               (format s "~A API Error~%"
                       (cond
                         ((equal provider-type 'anthropic-provider) "Anthropic")
                         ((equal provider-type 'openai-provider) "OpenAI")
                         ((equal provider-type 'ollama-provider) "Ollama")
                         ((equal provider-type 'openrouter-provider) "OpenRouter")
                         ((equal provider-type 'openai-compatible-provider) "OpenAI-Compatible")
                         (t "Provider")))
               (format s "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%")
               (format s "Status: ~A ~A~%"
                       (error-status-code c)
                       (case (error-status-code c)
                         (400 "Bad Request")
                         (401 "Unauthorized")
                         (403 "Forbidden")
                         (404 "Not Found")
                         (429 "Too Many Requests")
                         (500 "Internal Server Error")
                         (502 "Bad Gateway")
                         (503 "Service Unavailable")
                         (t "")))
               (when (error-message c)
                 (format s "~%~A~%" (error-message c)))
               (format s "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%")))))

(define-condition provider-rate-limit-error (provider-api-error)
  ((retry-after :initarg :retry-after
                :initform nil
                :reader error-retry-after
                :documentation "Seconds to wait before retrying."))
  (:documentation "Signaled when rate limit is exceeded.")
  (:report (lambda (c s)
             (format s "~&━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%")
             (format s "Rate Limit Exceeded~%")
             (format s "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%")
             (when (error-message c)
               (format s "~A~%~%" (error-message c)))
             (when (error-retry-after c)
               (format s "Retry after: ~A second~:P~%~%" (error-retry-after c)))
             (format s "Available restarts:~%")
             (format s "  • WAIT-AND-RETRY - Wait and retry automatically~%")
             (format s "  • RETRY - Retry immediately~%")
             (format s "  • USE-FALLBACK-PROVIDER - Switch to different provider~%")
             (format s "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%"))))

(define-condition provider-authentication-error (provider-api-error)
  ()
  (:documentation "Signaled when authentication fails (invalid or expired API key).")
  (:report (lambda (c s)
             (format s "~&━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%")
             (format s "Authentication Failed~%")
             (format s "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%")
             (when (error-message c)
               (format s "~A~%~%" (error-message c)))
             (format s "Possible causes:~%")
             (format s "  • API key is invalid or expired~%")
             (format s "  • API key not set in config file~%")
             (format s "  • Wrong API key for this provider~%")
             (format s "~%Check your configuration at: ~A~%"
                     (merge-pathnames "cl-llm-provider/config.lisp"
                                     (uiop:xdg-config-home)))
             (format s "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%"))))

(define-condition tool-schema-error (llm-provider-error)
  ((tool :initarg :tool
         :initform nil
         :reader error-tool
         :documentation "The tool definition that caused the error.")
   (reason :initarg :reason
           :initform nil
           :reader error-reason
           :documentation "Reason for the schema error."))
  (:documentation "Signaled when a tool definition is invalid or schema translation fails.")
  (:report (lambda (c s)
             (format s "Tool schema error~@[ for ~A~]~@[: ~A~]"
                     (when (error-tool c)
                       (ignore-errors (tool-name (error-tool c))))
                     (or (error-reason c)
                         (error-message c))))))

;;;; Enhanced Tool Conditions

(define-condition tool-validation-error (llm-provider-error)
  ((tool :initarg :tool
         :initform nil
         :reader error-tool
         :documentation "The tool definition.")
   (parameter :initarg :parameter
              :initform nil
              :reader error-parameter
              :documentation "Name of the parameter that failed validation.")
   (value :initarg :value
          :initform nil
          :reader error-value
          :documentation "The value that failed validation.")
   (validator :initarg :validator
              :initform nil
              :reader error-validator
              :documentation "The validator that failed.")
   (reason :initarg :reason
           :initform nil
           :reader error-reason
           :documentation "Human-readable reason for failure."))
  (:documentation "Signaled when parameter validation fails.")
  (:report (lambda (c s)
             (format s "Parameter validation failed~@[ for ~A~].~A: ~S~@[ - ~A~]"
                     (when (error-tool c)
                       (ignore-errors (tool-name (error-tool c))))
                     (or (error-parameter c) "?")
                     (error-value c)
                     (error-reason c)))))

(define-condition tool-approval-error (llm-provider-error)
  ((tool-call :initarg :tool-call
              :initform nil
              :reader error-tool-call
              :documentation "The tool call that was rejected.")
   (tool :initarg :tool
         :initform nil
         :reader error-tool
         :documentation "The tool definition.")
   (reason :initarg :reason
           :initform nil
           :reader error-reason
           :documentation "Reason for rejection."))
  (:documentation "Signaled when tool execution is rejected during approval.")
  (:report (lambda (c s)
             (format s "Tool execution rejected~@[ for ~A~]~@[: ~A~]"
                     (when (error-tool-call c)
                       (ignore-errors (tool-call-name (error-tool-call c))))
                     (error-reason c)))))

(define-condition tool-approval-required (llm-provider-error)
  ((tool-call :initarg :tool-call
              :initform nil
              :reader error-tool-call
              :documentation "The tool call requiring approval.")
   (tool :initarg :tool
         :initform nil
         :reader error-tool
         :documentation "The tool definition."))
  (:documentation "Signaled when approval is required but no callback is configured.")
  (:report (lambda (c s)
             (format s "Tool ~A requires approval but no approval callback configured"
                     (if (error-tool-call c)
                         (ignore-errors (tool-call-name (error-tool-call c)))
                         (if (error-tool c)
                             (ignore-errors (tool-name (error-tool c)))
                             "?"))))))

(define-condition tool-safety-violation (llm-provider-error)
  ((tool :initarg :tool
         :initform nil
         :reader error-tool
         :documentation "The tool that violated safety constraints.")
   (required-level :initarg :required-level
                   :initform nil
                   :reader error-required-level
                   :documentation "Maximum allowed safety level.")
   (actual-level :initarg :actual-level
                 :initform nil
                 :reader error-actual-level
                 :documentation "Actual safety level of the tool."))
  (:documentation "Signaled when attempting to use a tool that exceeds safety restrictions.")
  (:report (lambda (c s)
             (format s "Safety violation: tool ~A has level ~A but ~A or lower required"
                     (when (error-tool c)
                       (ignore-errors (tool-name (error-tool c))))
                     (error-actual-level c)
                     (error-required-level c)))))
