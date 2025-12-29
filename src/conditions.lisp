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
