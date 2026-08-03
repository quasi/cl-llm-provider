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

;;;; Streaming Protocol Methods

(defgeneric send-streaming-request (provider messages &key model max-tokens
                                                          temperature system tools
                                                          tool-choice stop)
  (:documentation "Send a streaming completion request to PROVIDER.

Returns a completion-stream object that can be read chunk-by-chunk.

PROVIDER - Provider instance
MESSAGES - List of message plists
MODEL - Model identifier (string)
MAX-TOKENS - Maximum tokens in response
TEMPERATURE - Sampling temperature (float 0.0-2.0)
SYSTEM - System prompt (string)
TOOLS - List of tool-definition objects
TOOL-CHOICE - Tool selection strategy
STOP - Stop sequences

Returns a completion-stream object.
Signals provider-api-error on HTTP connection errors."))

(defgeneric parse-stream-chunk (provider raw-chunk stream)
  (:documentation "Parse a raw SSE/streaming chunk into a stream-chunk object.

PROVIDER - Provider instance
RAW-CHUNK - Raw string data from the stream
STREAM - The completion-stream being read (for state tracking)

Returns a stream-chunk object, or nil for keep-alive/empty chunks.
Sets stream state to :closed when done signal received."))

(defgeneric read-stream-chunk (stream &key timeout)
  (:documentation "Read the next chunk from a completion-stream.

STREAM - completion-stream object
TIMEOUT - Maximum seconds to wait (nil = block indefinitely)

Returns a stream-chunk object, or nil if stream is closed.
Signals stream-error on read failures."))

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

;;; ============================================================
;;; Provider Introspection Protocol
;;; ============================================================

(defgeneric provider-type (provider)
  (:documentation "Return provider type as a keyword.
Returns one of: :openai, :anthropic, :gemini, :ollama, :openrouter, :openai-compatible.
The keyword is suitable for use in eql dispatch, equality tests, and serialization."))

(defgeneric provider-name (provider)
  (:documentation "Return human-readable provider name for display.
Returns a string suitable for UIs (e.g., \"OpenAI\", \"Anthropic\")."))

(defmethod provider-name ((provider llm-provider))
  "Fallback display name for custom providers without a specialized method."
  "Provider")

(defgeneric provider-capabilities (provider)
  (:documentation "Return plist of provider capabilities.
Keys: :tools, :embeddings, :streaming, :vision, :function-calling.
Values are T or NIL. Missing keys are equivalent to NIL (not supported)."))

(defgeneric provider-config-summary (provider)
  (:documentation "Return configuration summary plist (no sensitive data).
Keys: :type, :name, :model, :base-url, :capabilities.
Does NOT include API keys or other credentials."))

(defmethod provider-config-summary ((provider llm-provider))
  "Default implementation: aggregate data from other introspection functions."
  (list :type (provider-type provider)
        :name (provider-name provider)
        :model (provider-default-model provider)
        :base-url (provider-base-url provider)
        :capabilities (provider-capabilities provider)))

(defun/i provider-supports-p (provider capability)
  "Check if PROVIDER supports CAPABILITY (keyword).
Example: (provider-supports-p provider :tools)
Returns T if supported, NIL otherwise."
  (:feature provider-protocol)
  (:purpose "Check if provider supports a specific capability")
  (getf (provider-capabilities provider) capability))

(defgeneric model-metadata (provider model-name)
  (:documentation "Return metadata plist for MODEL-NAME, or NIL if unknown.
Keys: :context-window, :max-output-tokens, :supports-tools, :supports-vision,
      :input-cost-per-1m-tokens, :output-cost-per-1m-tokens.
Missing keys mean 'unknown' (not necessarily unsupported).
Providers may return NIL if they don't maintain model metadata."))

(defmethod model-metadata ((provider llm-provider) model-name)
  "Default: no metadata available."
  (declare (ignore model-name))
  nil)

(defgeneric translate-tool-to-provider (provider tool-definition)
  (:documentation "Translate generic tool definition to provider-specific format.

PROVIDER - Provider instance
TOOL-DEFINITION - tool-definition object

Returns provider-specific tool schema (hash-table or alist).
Default implementation returns OpenAI format."))

(defun parameter-specs-to-json-schema (tool)
  "Convert TOOL's parameter specs into a JSON Schema object."
  (let ((parameters (make-hash-table :test 'equal)))
    (setf (gethash "type" parameters) "object")
    (setf (gethash "properties" parameters) (make-hash-table :test 'equal))

    ;; Convert parameter specs to JSON Schema
    (dolist (param (tool-parameters tool))
      (let* ((param-name (getf param :name))
             (param-type (getf param :type))
             (param-desc (getf param :description))
             (param-enum (getf param :enum))
             (param-items (getf param :items))
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

        ;; For array types, include items schema (required by OpenAI)
        ;; Default to string items if not specified
        (when (eq param-type :array)
          (let ((items-spec (make-hash-table :test 'equal)))
            (if param-items
                ;; Use provided items spec (e.g., :items (:type :string))
                (progn
                  (setf (gethash "type" items-spec)
                        (ecase (getf param-items :type)
                          (:string "string")
                          (:integer "integer")
                          (:number "number")
                          (:boolean "boolean")
                          (:array "array")
                          (:object "object")))
                  (when (getf param-items :description)
                    (setf (gethash "description" items-spec)
                          (getf param-items :description))))
                ;; Default: array of strings
                (setf (gethash "type" items-spec) "string"))
            (setf (gethash "items" param-spec) items-spec)))

        (setf (gethash param-name (gethash "properties" parameters))
              param-spec)))

    ;; Set required parameters
    (when (tool-required-params tool)
      (setf (gethash "required" parameters) (tool-required-params tool)))

    parameters))

(defmethod translate-tool-to-provider ((provider llm-provider) (tool tool-definition))
  "Default implementation: OpenAI tool format."
  (declare (ignore provider))
  (let ((parameters (parameter-specs-to-json-schema tool)))
    ;; Return OpenAI function tool format
    (let ((result (make-hash-table :test 'equal)))
      (setf (gethash "type" result) "function")
      (let ((function (make-hash-table :test 'equal)))
        (setf (gethash "name" function) (tool-name tool))
        (setf (gethash "description" function) (tool-description tool))
        (setf (gethash "parameters" function) parameters)
        (setf (gethash "function" result) function))
      result)))

(defgeneric translate-message-to-provider (provider message)
  (:documentation "Translate a canonical message plist into PROVIDER's wire format.

MESSAGE is a keyword plist as produced by response-message, make-tool-result,
or user code (:role \"user\"/\"assistant\"/\"system\"/\"tool\", :content ...).

Returns a hash-table ready for yason encoding. The default method implements
the OpenAI chat format."))

(defmethod translate-message-to-provider ((provider llm-provider) message)
  "OpenAI format. Strips the library-internal :is-error key from tool messages."
  (declare (ignore provider))
  (let ((msg (copy-list message)))
    (remf msg :is-error)
    (plist-to-hash msg)))

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
                collect (let ((name (gethash "name" function)))
                          (make-instance 'tool-call
                                         :id tc-id
                                         :name name
                                         :arguments (%parse-tool-arguments
                                                     (gethash "arguments" function)
                                                     name)))))))))

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

(defun %json-plist-p (value)
  "True if VALUE is a keyword plist."
  (and (consp value) (keywordp (first value))))

(defun %lisp-to-json-value (value)
  "Recursively convert a Lisp VALUE into yason-encodable data.
Keyword plists become hash-tables, other lists become vectors, and atoms pass
through unchanged. Inverse of %json-hash-to-keyword-plist."
  (cond
    ((%json-plist-p value) (plist-to-hash value))
    ((consp value) (map 'vector #'%lisp-to-json-value value))
    (t value)))

(defun plist-to-hash (plist &key (test 'equal))
  "Convert a plist to a hash table with string keys, recursively.
Keywords like :role become \"role\", :tool-call-id becomes \"tool_call_id\";
string keys are preserved as-is. Values that are keyword plists become nested
hash-tables; other lists become vectors. Inverse of %json-hash-to-keyword-plist."
  (let ((hash (make-hash-table :test test)))
    (loop for (key value) on plist by #'cddr
          for string-key = (etypecase key
                            (keyword
                             ;; Convert hyphens to underscores for JSON compatibility
                             (substitute #\_ #\-
                                        (string-downcase (symbol-name key))))
                            (string key))
          do (setf (gethash string-key hash) (%lisp-to-json-value value)))
    hash))

(defun/i make-http-headers (provider &key content-type additional-headers)
  "Build HTTP headers for PROVIDER request.

PROVIDER - Provider instance
CONTENT-TYPE - Content-Type header value (default: \"application/json\")
ADDITIONAL-HEADERS - Alist of additional headers

Returns alist of headers."
  (:feature http-transport)
  (:purpose "Construct HTTP headers with auth for provider API calls")
  (append
   (list (cons "Content-Type" (or content-type "application/json")))
   (when (provider-api-key provider)
     (list (cons "Authorization" (format nil "Bearer ~A" (provider-api-key provider)))))
   additional-headers))

(defun/i extract-error-message (body)
  "Extract a user-friendly error message from response BODY.

BODY can be a string, hash-table, or other structure.
Returns a string describing the error."
  (:feature http-transport)
  (:purpose "Extract human-readable error from provider response bodies")
  (cond
    ;; String body - return as-is
    ((stringp body) body)

    ;; Hash table - try various common error formats
    ((hash-table-p body)
     (or
      ;; OpenAI/Anthropic format: {"error": {"message": "...", "type": "..."}}
      (when-let ((err (gethash "error" body)))
        (if (hash-table-p err)
            (format nil "~@[~A~]~@[ (~A)~]"
                    (gethash "message" err)
                    (gethash "type" err))
            (prin1-to-string err)))

      ;; Direct message field
      (gethash "message" body)

      ;; FastAPI/vLLM format
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

(defgeneric classify-api-error (provider status-code body error-message)
  (:documentation "Classify an HTTP error into a specific condition type based on status code and body.

PROVIDER - Provider instance (dispatches for provider-specific classification)
STATUS-CODE - HTTP status code
BODY - Response body (hash-table or string)
ERROR-MESSAGE - Pre-extracted error message string

Returns two values: a condition type symbol and extra initargs plist.

Specialize this generic function per provider to handle provider-specific error
formats. The default method handles common patterns across all providers."))

(defmethod classify-api-error ((provider llm-provider) status-code body error-message)
  "Default classification using common HTTP error patterns."
  (let ((body-str (if (stringp body) (string-downcase body)
                      (when (hash-table-p body)
                        (string-downcase (or (extract-error-message body) ""))))))
    (cond
      ;; 404 with model reference → model not found
      ((and (= status-code 404)
            body-str
            (or (search "model" body-str)
                (search "not found" body-str)))
       (values 'provider-model-not-found-error
               (list :requested-model
                     (when (hash-table-p body)
                       (let ((err (gethash "error" body)))
                         (when (hash-table-p err)
                           (gethash "model" err)))))))

      ;; 400 with context length / max tokens
      ((and (= status-code 400)
            body-str
            (or (search "context_length" body-str)
                (search "context length" body-str)
                (search "max_tokens" body-str)
                (search "maximum context" body-str)
                (search "token limit" body-str)
                (search "tokens exceeded" body-str)))
       (values 'provider-context-length-error nil))

      ;; 400 with content filter / safety
      ((and (= status-code 400)
            body-str
            (or (search "content_filter" body-str)
                (search "content filter" body-str)
                (search "safety" body-str)
                (search "harmful" body-str)
                (search "flagged" body-str)))
       (values 'provider-content-filter-error
               (list :filter-reason error-message)))

      ;; 503/529 → overloaded
      ((member status-code '(503 529))
       (values 'provider-overloaded-error
               (list :retry-after (parse-retry-after body))))

      ;; Default: generic provider-api-error
      (t (values 'provider-api-error nil)))))

(defintent classify-api-error
  :feature http-transport
  :purpose "Classify HTTP errors into specific condition types for agent recovery"
  :role "Extensible dispatch point for provider-specific error classification")

(defvar *requested-model* nil
  "The model the in-flight request is asking for, or NIL outside one.

BOUND BESIDE THE CONDITION, NEVER WRAPPED AROUND IT. This is how context reaches
a condition without changing a signature or re-signalling — the same pattern, and
for the same reason, as ghost's *supervision-office-name*: re-signalling to attach
context destroys the inner condition's restarts, and widening every provider
method's lambda list to carry one diagnostic string would touch nine call sites
across five files to say something COMPLETE already knows.

BOUND INSIDE THE RETRY LOOP, so a model corrected by USE-MODEL is the one a second
failure names. Bound outside it, the second failure would report the first
attempt's model and read exactly like the truth.")

(defun/i handle-http-error (status-code body provider &key requested-model)
  "Signal appropriate condition for HTTP error.

STATUS-CODE - HTTP status code (integer)
BODY - Response body (string or hash-table)
PROVIDER - Provider instance
REQUESTED-MODEL - The model this request asked for, when the caller knows it

Contract: if a handler invokes any restart established here, HANDLE-HTTP-ERROR
returns :RETRY and the caller re-issues the request. If no handler intervenes,
the condition propagates and this never returns.

WHY REQUESTED-MODEL IS A PARAMETER AND NOT DUG OUT OF THE BODY. It is dug out of
the body first — CLASSIFY-API-ERROR reads a nested (error.model) field — and
almost no server sends it. Measured 2026-08-04 against a live MLX server: a 404
for a model that did not exist reported \"Model not found: NIL\". The caller has
always known which model it asked for; it simply was not passed. An operator
being told that something was not found, and not what, is the least useful true
sentence available — and it cost one wrong diagnosis in the session that fixed it.

The body still WINS when it names a model. The server is the authority on what it
refused; a caller-supplied value overwriting that would replace a fact with an
assumption."
  (:feature http-transport)
  (:purpose "Classify HTTP errors and signal typed conditions with restarts")
  (let ((error-message (extract-error-message body)))
    (case status-code
      (401 (restart-case
               (error 'provider-authentication-error
                      :provider provider
                      :status-code status-code
                      :body body
                      :message error-message)
             (use-value (new-api-key)
               :report "Provide a new API key and retry"
               :interactive (lambda ()
                              (format *query-io* "Enter new API key: ")
                              (finish-output *query-io*)
                              (list (read-line *query-io*)))
               (setf (provider-api-key provider) new-api-key)
               :retry)))

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
                   (sleep retry-after))
                 :retry)
               (retry ()
                 :report "Retry immediately"
                 :retry))))

      (otherwise
       (multiple-value-bind (condition-type extra-initargs)
           (classify-api-error provider status-code body error-message)
         ;; Fill in the model the caller asked for ONLY where the classifier could
         ;; not find one in the body. Body first, caller second — see the note in
         ;; this function's :purpose. CLASSIFY-API-ERROR's own signature is
         ;; untouched on purpose: it is a public generic that callers specialize,
         ;; and a widened lambda list would break every specialization out there
         ;; to save one LIST* here.
         (let ((known-model (or requested-model *requested-model*)))
           (when (and known-model
                      (eq condition-type 'provider-model-not-found-error)
                      (null (getf extra-initargs :requested-model)))
             (setf extra-initargs
                   (list* :requested-model known-model extra-initargs))))
         (restart-case
             (apply #'error condition-type
                    :provider provider
                    :status-code status-code
                    :body body
                    :message error-message
                    extra-initargs)
           (retry ()
             :report "Retry the request"
             :retry)))))))

(defun/i parse-retry-after (body)
  "Extract retry-after value from error response body.

BODY - Response body (hash-table, string, or other)

Returns number of seconds to wait, or nil.
Checks top-level keys, nested error objects, and string bodies."
  (:feature http-transport)
  (:purpose "Extract retry delay from rate-limit response for automatic retry")
  (flet ((normalize (value)
           (typecase value
             (real value)
             (string (parse-integer value :junk-allowed t))
             (t nil)))
         (extract-from-hash (ht)
           (or (gethash "retry_after" ht)
               (gethash "retry-after" ht)
               (gethash "Retry-After" ht)
               ;; Check nested error object
               (let ((err (gethash "error" ht)))
                 (when (hash-table-p err)
                   (or (gethash "retry_after" err)
                       (gethash "retry-after" err)))))))
    (cond
      ((hash-table-p body) (normalize (extract-from-hash body)))
      ((stringp body) (normalize body))
      (t nil))))

(defun/i provider-http-post (provider url headers content &key (operation :completion))
  "POST CONTENT to URL for PROVIDER with typed error handling and working retries.

Returns the parsed JSON response body on 2xx. On HTTP errors delegates to
HANDLE-HTTP-ERROR; whenever a retry restart is invoked by a handler, the
request is re-issued from scratch. Honors provider option :timeout in seconds."
  (:feature http-transport)
  (:purpose "Single shared HTTP POST path with retry loop for all providers")
  (let ((read-timeout (getf (provider-options provider) :timeout 120)))
    (loop
      (multiple-value-bind (response-body status-code)
          (handler-case
              (dex:post url
                        :headers headers
                        :content content
                        :force-string t
                        :read-timeout read-timeout)
            (dex:http-request-failed (e)
              (values (dex:response-body e) (dex:response-status e)))
            (error (e)
              (error 'provider-network-error
                     :provider provider
                     :url url
                     :operation operation
                     :original-error e
                     :message (format nil "Network error: ~A" e))))
        (if (and (>= status-code 200) (< status-code 300))
            (return (yason:parse response-body))
            (let ((directive (handle-http-error
                              status-code
                              (handler-case (yason:parse response-body)
                                (error () response-body))
                              provider)))
              (unless (eq directive :retry)
                (return directive))))))))
