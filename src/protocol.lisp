(in-package :cl-llm-provider)

;;;; Provider Protocol
;;;;
;;;; This file defines the generic function protocol that all provider implementations
;;;; must follow. New providers are added by subclassing llm-provider and implementing
;;;; these generic functions.

;;;; Required Protocol Methods

(defgeneric send-completion-request (provider messages &key model max-tokens
                                                        temperature system tools
                                                        tool-choice stop)
  (:documentation "Send a completion request to PROVIDER and return raw response.

PROVIDER - Provider instance
MESSAGES - List of message plists ((:role \"user\" :content \"Hello\"))
MODEL - Model identifier (string)
MAX-TOKENS - Maximum tokens in response (integer)
TEMPERATURE - Sampling temperature (float 0.0-2.0)
SYSTEM - System prompt (string)
TOOLS - List of tool-definition objects
TOOL-CHOICE - Tool selection strategy (keyword, string, or nil)
STOP - Stop sequences (string or list of strings)

Returns the raw HTTP response body (hash-table or alist).
Signals provider-api-error on HTTP errors."))

(defgeneric parse-completion-response (provider raw-response &key performance)
  (:documentation "Parse provider-specific response into completion-response object.

PROVIDER - Provider instance
RAW-RESPONSE - Raw response from send-completion-request
PERFORMANCE - Optional performance timing plist (when *performance-profiling* is enabled)

Returns a completion-response object."))

(defgeneric send-embedding-request (provider input &key model dimensions)
  (:documentation "Send an embedding request to PROVIDER and return raw response.

PROVIDER - Provider instance
INPUT - Text to embed (string or list of strings)
MODEL - Embedding model identifier (string)
DIMENSIONS - Output dimensions if model supports (integer)

Returns the raw HTTP response body (hash-table or alist).
Signals provider-api-error on HTTP errors."))

(defgeneric parse-embedding-response (provider raw-response &key performance)
  (:documentation "Parse provider-specific response into embedding-response object.

PROVIDER - Provider instance
RAW-RESPONSE - Raw response from send-embedding-request
PERFORMANCE - Optional performance timing plist (when *performance-profiling* is enabled)

Returns an embedding-response object."))

;;;; Optional Protocol Methods (have default implementations)

(defgeneric provider-default-base-url (provider)
  (:documentation "Return default API base URL for this provider type.

Override this for custom provider types.
Default implementation returns nil (must be specified in constructor)."))

(defmethod provider-default-base-url ((provider llm-provider))
  nil)

(defgeneric provider-api-key-env-var (provider)
  (:documentation "Return environment variable name for API key.

Override this for custom provider types.
Default implementation returns nil (no standard env var)."))

(defmethod provider-api-key-env-var ((provider llm-provider))
  nil)

(defgeneric translate-tool-to-provider (provider tool-definition)
  (:documentation "Translate generic tool definition to provider-specific format.

PROVIDER - Provider instance
TOOL-DEFINITION - tool-definition object

Returns provider-specific tool schema (hash-table or alist).
Default implementation returns OpenAI format."))

(defmethod translate-tool-to-provider ((provider llm-provider) (tool tool-definition))
  "Default implementation: OpenAI tool format."
  (let ((parameters (make-hash-table :test 'equal)))
    (setf (gethash "type" parameters) "object")
    (setf (gethash "properties" parameters) (make-hash-table :test 'equal))

    ;; Convert parameter specs to JSON Schema
    (dolist (param (tool-parameters tool))
      (let* ((param-name (getf param :name))
             (param-type (getf param :type))
             (param-desc (getf param :description))
             (param-enum (getf param :enum))
             (param-spec (make-hash-table :test 'equal)))

        ;; Map CL type keywords to JSON Schema types
        (setf (gethash "type" param-spec)
              (ecase param-type
                (:string "string")
                (:integer "integer")
                (:number "number")
                (:boolean "boolean")
                (:array "array")
                (:object "object")))

        (when param-desc
          (setf (gethash "description" param-spec) param-desc))

        (when param-enum
          (setf (gethash "enum" param-spec) param-enum))

        (setf (gethash param-name (gethash "properties" parameters))
              param-spec)))

    ;; Set required parameters
    (when (tool-required-params tool)
      (setf (gethash "required" parameters) (tool-required-params tool)))

    ;; Return OpenAI function tool format
    (let ((result (make-hash-table :test 'equal)))
      (setf (gethash "type" result) "function")
      (let ((function (make-hash-table :test 'equal)))
        (setf (gethash "name" function) (tool-name tool))
        (setf (gethash "description" function) (tool-description tool))
        (setf (gethash "parameters" function) parameters)
        (setf (gethash "function" result) function))
      result)))

(defgeneric parse-tool-calls (provider raw-response)
  (:documentation "Extract tool calls from provider response format.

PROVIDER - Provider instance
RAW-RESPONSE - Raw response from send-completion-request

Returns list of tool-call objects, or nil if no tool calls.
Default implementation handles OpenAI format."))

(defmethod parse-tool-calls ((provider llm-provider) raw-response)
  "Default implementation: Parse OpenAI-style tool calls."
  (let ((choices (gethash "choices" raw-response)))
    (when (and choices (> (length choices) 0))
      (let* ((first-choice (elt choices 0))
             (message (gethash "message" first-choice))
             (tool-calls (gethash "tool_calls" message)))
        (when tool-calls
          (loop for tc in (coerce tool-calls 'list)
                for tc-id = (gethash "id" tc)
                for tc-type = (gethash "type" tc)
                for function = (gethash "function" tc)
                when (string= tc-type "function")
                collect (make-instance 'tool-call
                                       :id tc-id
                                       :name (gethash "name" function)
                                       :arguments (let ((args-str (gethash "arguments" function)))
                                                   (if (stringp args-str)
                                                       (yason:parse args-str)
                                                       args-str)))))))))

;;;; Performance Profiling Infrastructure

(defvar *performance-profiling* nil
  "When non-nil, collect timing statistics for API calls.
Timing data is included in the :performance slot of response objects.")

(defvar *performance-stats* nil
  "Dynamic variable holding current performance statistics during a request.
Bound automatically during API calls when *performance-profiling* is enabled.
Plist format: (:encode-time seconds :api-time seconds :decode-time seconds)")

(defun get-monotonic-time ()
  "Get monotonic time in seconds with high precision.
Uses get-internal-real-time for portability."
  (/ (get-internal-real-time) internal-time-units-per-second))

(defmacro with-performance-timing ((stat-key) &body body)
  "Execute BODY and record execution time in *performance-stats* under STAT-KEY.
STAT-KEY should be one of :encode-time, :api-time, or :decode-time.
Only records timing if *performance-profiling* is enabled.
Preserves multiple return values from BODY."
  (let ((start-time (gensym "START-TIME-"))
        (elapsed (gensym "ELAPSED-")))
    `(if *performance-profiling*
         (let ((,start-time (get-monotonic-time)))
           (multiple-value-prog1
               (progn ,@body)
             (let ((,elapsed (- (get-monotonic-time) ,start-time)))
               (setf (getf *performance-stats* ,stat-key) ,elapsed))))
         (progn ,@body))))

(defun make-performance-stats ()
  "Create a new performance stats plist.
Returns a plist with all timing fields initialized to nil."
  (list :encode-time nil :api-time nil :decode-time nil))

(defun get-performance-stats ()
  "Get current performance statistics.
Returns the plist from *performance-stats*, or nil if profiling is disabled."
  (when (and *performance-profiling* (boundp '*performance-stats*))
    (copy-list *performance-stats*)))

(defun format-performance-time (time-value)
  "Format a single performance timing value for display.
Returns 'not recorded' if TIME-VALUE is nil, otherwise formats as seconds."
  (if time-value
      (format nil "~,4f seconds" (coerce time-value 'float))
      "not recorded"))

(defun format-performance-stats (performance-plist &optional (stream t))
  "Format performance statistics for display.
PERFORMANCE-PLIST - The :performance slot from a response object
STREAM - Output stream (default: t for standard output)

Displays timing breakdown or 'not recorded' for each metric when profiling was disabled."
  (if performance-plist
      (progn
        (format stream "Performance Stats:~%")
        (format stream "  Encode time: ~A~%"
                (format-performance-time (getf performance-plist :encode-time)))
        (format stream "  API time:    ~A~%"
                (format-performance-time (getf performance-plist :api-time)))
        (format stream "  Decode time: ~A~%"
                (format-performance-time (getf performance-plist :decode-time))))
      (format stream "Performance profiling was not enabled~%")))

;;;; HTTP Request Helpers

(defun plist-to-hash (plist &key (test 'equal))
  "Convert a plist to a hash table with string keys.
Keywords like :role become \"role\", preserving string keys as-is."
  (let ((hash (make-hash-table :test test)))
    (loop for (key value) on plist by #'cddr
          for string-key = (etypecase key
                            (keyword (string-downcase (symbol-name key)))
                            (string key))
          do (setf (gethash string-key hash) value))
    hash))

(defun make-http-headers (provider &key content-type additional-headers)
  "Build HTTP headers for PROVIDER request.

PROVIDER - Provider instance
CONTENT-TYPE - Content-Type header value (default: \"application/json\")
ADDITIONAL-HEADERS - Alist of additional headers

Returns alist of headers."
  (append
   (list (cons "Content-Type" (or content-type "application/json")))
   (when (provider-api-key provider)
     (list (cons "Authorization" (format nil "Bearer ~A" (provider-api-key provider)))))
   additional-headers))

(defun extract-error-message (body)
  "Extract a user-friendly error message from response BODY.

BODY can be a string, hash-table, or other structure.
Returns a string describing the error."
  (cond
    ;; String body - return as-is
    ((stringp body) body)

    ;; Hash table - try various common error formats
    ((hash-table-p body)
     (or
      ;; OpenAI format: {"error": {"message": "...", "type": "...", "code": "..."}}
      (when-let ((error (gethash "error" body)))
        (if (hash-table-p error)
            (format nil "~@[~A~]~@[ (~A)~]"
                    (gethash "message" error)
                    (gethash "type" error))
            (prin1-to-string error)))

      ;; Direct message field
      (gethash "message" body)

      ;; Anthropic format: {"error": {"type": "...", "message": "..."}}
      (gethash "detail" body)

      ;; Try to create a readable summary
      (format nil "API error: ~{~A: ~S~^, ~}"
              (let ((pairs '()))
                (maphash (lambda (k v)
                           (push k pairs)
                           (push v pairs))
                         body)
                (nreverse pairs)))))

    ;; Unknown format - convert to string
    (t (prin1-to-string body))))

(defun handle-http-error (status-code body provider)
  "Signal appropriate condition for HTTP error.

STATUS-CODE - HTTP status code (integer)
BODY - Response body (string or hash-table)
PROVIDER - Provider instance"
  (let ((error-message (extract-error-message body)))
    (case status-code
      (401 (restart-case
               (error 'provider-authentication-error
                      :provider provider
                      :status-code status-code
                      :body body
                      :message error-message)
             (use-value (new-api-key)
               :report "Provide a new API key"
               :interactive (lambda ()
                              (format t "Enter new API key: ")
                              (list (read-line)))
               (setf (slot-value provider 'api-key) new-api-key))))

      (429 (let ((retry-after (parse-retry-after body)))
             (restart-case
                 (error 'provider-rate-limit-error
                        :provider provider
                        :status-code status-code
                        :body body
                        :message error-message
                        :retry-after retry-after)
               (wait-and-retry ()
                 :report (lambda (s)
                           (format s "Wait ~@[~A seconds ~]and retry" retry-after))
                 (when retry-after
                   (sleep retry-after)))
               (retry ()
                 :report "Retry immediately")
               (use-fallback-provider (fallback)
                 :report "Use a different provider"
                 :interactive (lambda ()
                                (format t "Enter fallback provider: ")
                                (list (read)))
                 fallback))))

      (otherwise
       (restart-case
           (error 'provider-api-error
                  :provider provider
                  :status-code status-code
                  :body body
                  :message error-message)
         (retry ()
           :report "Retry the request")
         (use-fallback-provider (fallback)
           :report "Use a different provider"
           :interactive (lambda ()
                          (format t "Enter fallback provider: ")
                          (list (read)))
           fallback))))))

(defun parse-retry-after (body)
  "Extract retry-after value from error response body.

BODY - Response body (hash-table or string)

Returns number of seconds to wait, or nil."
  (when (hash-table-p body)
    (or (gethash "retry_after" body)
        (gethash "retry-after" body))))
