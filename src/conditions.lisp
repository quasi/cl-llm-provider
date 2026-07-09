(in-package :cl-llm-provider)

;;;; Condition Hierarchy

(define-condition/i llm-provider-error (error)
  ((provider :initarg :provider
             :initform nil
             :reader error-provider
             :documentation "The provider that signaled the error.")
   (message :initarg :message
            :initform nil
            :reader error-message
            :documentation "Error message."))
  (:feature error-recovery)
  (:purpose "Base condition for all cl-llm-provider errors")
  (:documentation "Base condition for all cl-llm-provider errors.")
  (:report (lambda (c s)
             (format s "LLM Provider error~@[ (~A)~]~@[: ~A~]"
                     (when (error-provider c)
                       (type-of (error-provider c)))
                     (error-message c)))))

(define-condition/i provider-configuration-error (llm-provider-error)
  ((missing-key :initarg :missing-key
                :initform nil
                :reader error-missing-key
                :documentation "Name of the missing configuration key."))
  (:feature configuration)
  (:purpose "Signal missing or invalid provider configuration")
  (:documentation "Signaled when required provider configuration is missing.")
  (:report (lambda (c s)
             (format s "Provider configuration error~@[: missing ~A~]~@[. ~A~]"
                     (error-missing-key c)
                     (error-message c)))))

(define-condition/i provider-api-error (llm-provider-error)
  ((status-code :initarg :status-code
                :initform nil
                :reader error-status-code
                :documentation "HTTP status code from the API.")
   (body :initarg :body
         :initform nil
         :reader error-body
         :documentation "Response body from the API."))
  (:feature http-transport)
  (:purpose "Signal HTTP-level API failures with status code and body")
  (:documentation "Signaled when an API request fails.")
  (:report (lambda (c s)
             (format s "~&━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%")
             (format s "~A API Error~%"
                     (let ((provider (error-provider c)))
                       (if provider
                           (handler-case (provider-name provider)
                             (error () "Provider"))
                           "Provider")))
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
               (format s "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%"))))

(define-condition/i provider-rate-limit-error (provider-api-error)
  ((retry-after :initarg :retry-after
                :initform nil
                :reader error-retry-after
                :documentation "Seconds to wait before retrying."))
  (:feature http-transport)
  (:purpose "Signal rate limit exceeded with retry-after hint")
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
             (format s "  • WAIT-AND-RETRY - Wait per retry-after hint, then retry~%")
             (format s "  • RETRY - Retry immediately~%")
             (format s "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%"))))

(define-condition/i provider-authentication-error (provider-api-error)
  ()
  (:feature http-transport)
  (:purpose "Signal authentication failures from invalid or expired API key")
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

(define-condition/i tool-schema-error (llm-provider-error)
  ((tool :initarg :tool
         :initform nil
         :reader error-tool
         :documentation "The tool definition that caused the error.")
   (reason :initarg :reason
           :initform nil
           :reader error-reason
           :documentation "Reason for the schema error."))
  (:feature tool-calling)
  (:purpose "Signal invalid tool definition or schema translation failure")
  (:documentation "Signaled when a tool definition is invalid or schema translation fails.")
  (:report (lambda (c s)
             (format s "Tool schema error~@[ for ~A~]~@[: ~A~]"
                     (when (error-tool c)
                       (ignore-errors (tool-name (error-tool c))))
                     (or (error-reason c)
                         (error-message c))))))

(define-condition/i tool-registration-error (llm-provider-error)
  ((tool-name :initarg :tool-name
              :initform nil
              :reader error-tool-name
              :documentation "Name of the tool being registered."))
  (:feature tool-calling)
  (:purpose "Signal tool registry conflicts")
  (:documentation "Signaled when tool registration fails, such as a duplicate name.")
  (:report (lambda (c s)
             (format s "Tool registration error~@[ for ~S~]~@[: ~A~]"
                     (error-tool-name c)
                     (error-message c)))))

;;;; Enhanced Tool Conditions

(define-condition/i tool-validation-error (llm-provider-error)
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
  (:feature tool-calling)
  (:purpose "Signal parameter validation failure during tool execution")
  (:documentation "Signaled when parameter validation fails.")
  (:report (lambda (c s)
             (format s "Parameter validation failed~@[ for ~A~].~A: ~S~@[ - ~A~]"
                     (when (error-tool c)
                       (ignore-errors (tool-name (error-tool c))))
                     (or (error-parameter c) "?")
                     (error-value c)
                     (error-reason c)))))

(define-condition/i tool-approval-error (llm-provider-error)
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
  (:feature tool-calling)
  (:purpose "Signal tool execution rejection during approval")
  (:documentation "Signaled when tool execution is rejected during approval.")
  (:report (lambda (c s)
             (format s "Tool execution rejected~@[ for ~A~]~@[: ~A~]"
                     (when (error-tool-call c)
                       (ignore-errors (tool-call-name (error-tool-call c))))
                     (error-reason c)))))

(define-condition/i tool-approval-required (llm-provider-error)
  ((tool-call :initarg :tool-call
              :initform nil
              :reader error-tool-call
              :documentation "The tool call requiring approval.")
   (tool :initarg :tool
         :initform nil
         :reader error-tool
         :documentation "The tool definition."))
  (:feature tool-calling)
  (:purpose "Signal that approval is needed but no callback configured")
  (:documentation "Signaled when approval is required but no callback is configured.")
  (:report (lambda (c s)
             (format s "Tool ~A requires approval but no approval callback configured"
                     (if (error-tool-call c)
                         (ignore-errors (tool-call-name (error-tool-call c)))
                         (if (error-tool c)
                             (ignore-errors (tool-name (error-tool c)))
                             "?"))))))

(define-condition/i tool-safety-violation (llm-provider-error)
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
  (:feature tool-calling)
  (:purpose "Signal tool safety level exceeds allowed maximum")
  (:documentation "Signaled when attempting to use a tool that exceeds safety restrictions.")
  (:report (lambda (c s)
             (format s "Safety violation: tool ~A has level ~A but ~A or lower required"
                     (when (error-tool c)
                       (ignore-errors (tool-name (error-tool c))))
                     (error-actual-level c)
                     (error-required-level c)))))

;;;; New Agent-Oriented Conditions
;;;;
;;;; These conditions provide specific error types for programmatic recovery.
;;;; Agents can use handler-bind + invoke-restart to recover without debugging.

;;; Provider API Error Subtypes

(define-condition/i provider-model-not-found-error (provider-api-error)
  ((requested-model :initarg :requested-model
                    :initform nil
                    :reader error-requested-model
                    :documentation "The model name that was not found.")
   (available-models :initarg :available-models
                     :initform nil
                     :reader error-available-models
                     :documentation "List of available model names, if known."))
  (:feature http-transport)
  (:purpose "Signal that requested model does not exist or is not available")
  (:documentation "Signaled when the requested model is not found (HTTP 404 with model reference).")
  (:report (lambda (c s)
             (format s "Model not found: ~A~@[ (available: ~{~A~^, ~})~]"
                     (error-requested-model c)
                     (error-available-models c)))))

(define-condition/i provider-context-length-error (provider-api-error)
  ((token-count :initarg :token-count
                :initform nil
                :reader error-token-count
                :documentation "Number of tokens in the request.")
   (max-tokens :initarg :max-tokens
               :initform nil
               :reader error-max-tokens
               :documentation "Maximum tokens allowed by the model.")
   (model :initarg :model
          :initform nil
          :reader error-context-model
          :documentation "The model that rejected the request."))
  (:feature http-transport)
  (:purpose "Signal input exceeds model context window")
  (:documentation "Signaled when the request exceeds the model's context window (HTTP 400 + context_length).")
  (:report (lambda (c s)
             (format s "Context length exceeded~@[ for ~A~]~@[: ~D tokens~]~@[ (max ~D)~]"
                     (error-context-model c)
                     (error-token-count c)
                     (error-max-tokens c)))))

(define-condition/i provider-content-filter-error (provider-api-error)
  ((filter-reason :initarg :filter-reason
                  :initform nil
                  :reader error-filter-reason
                  :documentation "Reason the content was filtered."))
  (:feature http-transport)
  (:purpose "Signal content rejected by provider safety filter")
  (:documentation "Signaled when content is rejected by the provider's safety filter.")
  (:report (lambda (c s)
             (format s "Content filtered~@[: ~A~]"
                     (or (error-filter-reason c) (error-message c))))))

(define-condition/i provider-overloaded-error (provider-api-error)
  ((retry-after :initarg :retry-after
                :initform nil
                :reader error-retry-after
                :documentation "Seconds to wait before retrying."))
  (:feature http-transport)
  (:purpose "Signal provider is temporarily overloaded (HTTP 503/529)")
  (:documentation "Signaled when the provider is temporarily overloaded.")
  (:report (lambda (c s)
             (format s "Provider overloaded~@[, retry after ~A second~:P~]"
                     (error-retry-after c)))))

(define-condition/i provider-invalid-response-error (provider-api-error)
  ((expected-format :initarg :expected-format
                    :initform nil
                    :reader error-expected-format
                    :documentation "Description of expected response format.")
   (actual-value :initarg :actual-value
                 :initform nil
                 :reader error-actual-value
                 :documentation "The actual value received."))
  (:feature http-transport)
  (:purpose "Signal malformed or unexpected response from provider")
  (:documentation "Signaled when provider returns a response that cannot be parsed correctly.")
  (:report (lambda (c s)
             (format s "Invalid provider response~@[: expected ~A~]~@[, got ~S~]"
                     (error-expected-format c)
                     (error-actual-value c)))))

;;; Network Conditions

(define-condition/i provider-network-error (llm-provider-error)
  ((original-error :initarg :original-error
                   :initform nil
                   :reader error-original-condition
                   :documentation "The underlying network error condition.")
   (url :initarg :url
        :initform nil
        :reader error-url
        :documentation "The URL that failed.")
   (operation :initarg :operation
              :initform nil
              :reader error-operation
              :documentation "The operation being performed (:completion, :embedding, :streaming)."))
  (:feature http-transport)
  (:purpose "Signal network-level failure (connection refused, DNS, etc.)")
  (:documentation "Signaled when a network-level error occurs (not an HTTP error).")
  (:report (lambda (c s)
             (format s "Network error~@[ during ~A~]~@[ to ~A~]~@[: ~A~]"
                     (error-operation c)
                     (error-url c)
                     (error-original-condition c)))))

(define-condition/i provider-timeout-error (provider-network-error)
  ((timeout-seconds :initarg :timeout-seconds
                    :initform nil
                    :reader error-timeout-seconds
                    :documentation "The timeout value in seconds.")
   (phase :initarg :phase
          :initform nil
          :reader error-timeout-phase
          :documentation "Phase when timeout occurred (:connect, :read, :write)."))
  (:feature http-transport)
  (:purpose "Signal request timed out during specific phase")
  (:documentation "Signaled when a request times out.")
  (:report (lambda (c s)
             (format s "Request timed out~@[ during ~A~]~@[ after ~A second~:P~]"
                     (error-timeout-phase c)
                     (error-timeout-seconds c)))))

;;; Parse Conditions

(define-condition/i provider-json-parse-error (llm-provider-error)
  ((raw-body :initarg :raw-body
             :initform nil
             :reader error-raw-body
             :documentation "The raw response body that failed to parse.")
   (parse-error :initarg :parse-error
                :initform nil
                :reader error-parse-condition
                :documentation "The underlying parse error condition."))
  (:feature http-transport)
  (:purpose "Signal JSON parse failure on provider response")
  (:documentation "Signaled when a provider response cannot be parsed as JSON.")
  (:report (lambda (c s)
             (format s "JSON parse error~@[: ~A~]~@[~%Raw body: ~A~]"
                     (error-parse-condition c)
                     (when (error-raw-body c)
                       (let ((body (error-raw-body c)))
                         (if (> (length body) 200)
                             (concatenate 'string (subseq body 0 200) "...")
                             body)))))))

;;; Operation Conditions

(define-condition/i provider-unsupported-operation (llm-provider-error)
  ((operation :initarg :operation
              :initform nil
              :reader error-unsupported-operation
              :documentation "The operation that is not supported.")
   (provider-type :initarg :provider-type
                  :initform nil
                  :reader error-unsupported-provider-type
                  :documentation "The provider type that doesn't support the operation."))
  (:feature provider-protocol)
  (:purpose "Signal operation not supported by this provider")
  (:documentation "Signaled when an operation is not supported by the provider.")
  (:report (lambda (c s)
             (format s "Unsupported operation~@[: ~A~]~@[ for ~A~]"
                     (error-unsupported-operation c)
                     (error-unsupported-provider-type c)))))

;;; Streaming Conditions

(define-condition/i llm-stream-error (llm-provider-error)
  ((stream-object :initarg :stream
                  :initform nil
                  :reader error-stream-object
                  :documentation "The completion-stream that errored.")
   (phase :initarg :phase
          :initform nil
          :reader error-stream-phase
          :documentation "Phase when error occurred (:reading, :parsing, :accumulating)."))
  (:feature streaming-api)
  (:purpose "Base condition for streaming errors")
  (:documentation "Base condition for errors during stream processing.")
  (:report (lambda (c s)
             (format s "Stream error~@[ during ~A~]~@[: ~A~]"
                     (error-stream-phase c)
                     (error-message c)))))

(define-condition/i stream-interrupted-error (llm-stream-error)
  ((chunks-received :initarg :chunks-received
                    :initform 0
                    :reader error-chunks-received
                    :documentation "Number of chunks received before interruption.")
   (accumulated-content :initarg :accumulated-content
                        :initform nil
                        :reader error-accumulated-content
                        :documentation "Content accumulated before interruption."))
  (:feature streaming-api)
  (:purpose "Signal stream interrupted with partial content available")
  (:documentation "Signaled when a stream is interrupted mid-transfer. Partial content may be available.")
  (:report (lambda (c s)
             (format s "Stream interrupted after ~D chunk~:P~@[ (~D chars accumulated)~]"
                     (error-chunks-received c)
                     (when (error-accumulated-content c)
                       (length (error-accumulated-content c)))))))

(define-condition/i stream-parse-error (llm-stream-error)
  ((raw-chunk :initarg :raw-chunk
              :initform nil
              :reader error-raw-chunk
              :documentation "The raw chunk data that failed to parse.")
   (parse-error :initarg :parse-error
                :initform nil
                :reader error-chunk-parse-condition
                :documentation "The underlying parse error."))
  (:feature streaming-api)
  (:purpose "Signal SSE chunk parse failure during streaming")
  (:documentation "Signaled when an SSE chunk cannot be parsed.")
  (:report (lambda (c s)
             (format s "Stream parse error~@[: ~A~]~@[~%Raw chunk: ~S~]"
                     (error-chunk-parse-condition c)
                     (error-raw-chunk c)))))

;;; Tool Execution Conditions

(define-condition/i tool-execution-error (llm-provider-error)
  ((tool :initarg :tool
         :initform nil
         :reader error-tool
         :documentation "The tool definition.")
   (tool-call :initarg :tool-call
              :initform nil
              :reader error-tool-call
              :documentation "The tool call object.")
   (arguments :initarg :arguments
              :initform nil
              :reader error-arguments
              :documentation "Arguments passed to the tool handler.")
   (original-error :initarg :original-error
                   :initform nil
                   :reader error-execution-cause
                   :documentation "The underlying error from the handler."))
  (:feature tool-calling)
  (:purpose "Signal tool handler execution failure with context")
  (:documentation "Signaled when a tool handler raises an error during execution.")
  (:report (lambda (c s)
             (format s "Tool execution error~@[ in ~A~]~@[: ~A~]"
                     (when (error-tool c)
                       (ignore-errors (tool-name (error-tool c))))
                     (error-execution-cause c)))))

(define-condition/i tool-not-found-error (llm-provider-error)
  ((tool-name :initarg :tool-name
              :initform nil
              :reader error-missing-tool-name
              :documentation "Name of the tool that was not found.")
   (available-tools :initarg :available-tools
                    :initform nil
                    :reader error-available-tools
                    :documentation "List of available tool names."))
  (:feature tool-calling)
  (:purpose "Signal requested tool not found in registry")
  (:documentation "Signaled when a tool referenced by the LLM is not in the registry.")
  (:report (lambda (c s)
             (format s "Tool not found: ~A~@[ (available: ~{~A~^, ~})~]"
                     (error-missing-tool-name c)
                     (error-available-tools c)))))

(define-condition/i tool-handler-missing-error (llm-provider-error)
  ((tool :initarg :tool
         :initform nil
         :reader error-tool
         :documentation "The tool definition missing a handler."))
  (:feature tool-calling)
  (:purpose "Signal tool definition has no handler function")
  (:documentation "Signaled when a tool definition has no handler function configured.")
  (:report (lambda (c s)
             (format s "No handler configured for tool ~A"
                     (when (error-tool c)
                       (ignore-errors (tool-name (error-tool c))))))))

;;; Warning Conditions

(define-condition/i llm-provider-warning (warning)
  ((provider :initarg :provider
             :initform nil
             :reader warning-provider
             :documentation "The provider that issued the warning.")
   (message :initarg :message
            :initform nil
            :reader warning-message
            :documentation "Warning message."))
  (:feature observability)
  (:purpose "Base warning condition for non-fatal provider issues")
  (:documentation "Base warning for non-fatal issues during LLM operations.")
  (:report (lambda (c s)
             (format s "LLM Provider warning~@[: ~A~]"
                     (warning-message c)))))

(define-condition/i provider-deprecation-warning (llm-provider-warning)
  ((deprecated-feature :initarg :feature
                       :initform nil
                       :reader warning-deprecated-feature
                       :documentation "The feature or API that is deprecated.")
   (replacement :initarg :replacement
                :initform nil
                :reader warning-replacement
                :documentation "Suggested replacement."))
  (:feature observability)
  (:purpose "Signal deprecated feature usage with replacement guidance")
  (:documentation "Signaled when using a deprecated feature or API.")
  (:report (lambda (c s)
             (format s "Deprecated: ~A~@[. Use ~A instead.~]"
                     (warning-deprecated-feature c)
                     (warning-replacement c)))))
