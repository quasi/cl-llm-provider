(in-package :cl-llm-provider)

;;;; OpenAI Provider Implementation

(defmethod provider-default-base-url ((provider openai-provider))
  "https://api.openai.com/v1")

(defmethod provider-api-key-env-var ((provider openai-provider))
  "OPENAI_API_KEY")

;;; Provider Introspection

(defmethod provider-type ((provider openai-provider))
  :openai)

(defmethod provider-name ((provider openai-provider))
  "OpenAI")

(defmethod provider-capabilities ((provider openai-provider))
  '(:tools t
    :embeddings t
    :streaming t
    :vision t
    :function-calling t))

(defmethod model-metadata ((provider openai-provider) model-name)
  (get-model-metadata *openai-model-registry* model-name))

(defmethod send-completion-request ((provider openai-provider) messages
                                    &key model max-tokens temperature
                                         system tools tool-choice stop)
  (let* ((url (format nil "~A/chat/completions" (provider-base-url provider)))
         (headers (make-http-headers provider))
         (encoded-body nil))

    ;; Build and encode request body (with timing)
    (with-performance-timing (:encode-time)
      (let ((body (make-hash-table :test 'equal)))
        ;; Build request body
        (setf (gethash "model" body) model)
        (setf (gethash "messages" body)
              (let ((all (if system
                             (cons (list :role "system" :content system) messages)
                             messages)))
                (map 'vector
                     (lambda (m) (translate-message-to-provider provider m))
                     all)))

        (when max-tokens
          (setf (gethash "max_tokens" body) max-tokens))

        (when temperature
          (setf (gethash "temperature" body) temperature))

        (when stop
          (setf (gethash "stop" body) (ensure-list stop)))

        (when tools
          (setf (gethash "tools" body)
                (map 'vector
                     (lambda (tool) (translate-tool-to-provider provider tool))
                     tools)))

        (when tool-choice
          (setf (gethash "tool_choice" body)
                (etypecase tool-choice
                  (keyword (string-downcase (symbol-name tool-choice)))
                  ;; A named function must be a structured object; a bare
                  ;; string is rejected (only none/auto/required are valid).
                  (string (plist-to-hash (list :type "function"
                                               :function (list :name tool-choice)))))))

        ;; Encode to JSON
        (setf encoded-body
              (with-output-to-string (s)
                (yason:encode body s)))))

    ;; Make HTTP request (with timing)
    (with-performance-timing (:api-time)
      (provider-http-post provider url headers encoded-body :operation :completion))))

(defmethod parse-completion-response ((provider openai-provider) raw-response
                                      &key performance)
  (let* ((choices (gethash "choices" raw-response))
         ;; guard: first-choice may be NIL (empty choices)
         (first-choice (when (and choices (> (length choices) 0))
                        (elt choices 0)))
         (message (when first-choice (gethash "message" first-choice)))
         (content (when message (gethash "content" message)))
         (finish-reason (when first-choice (gethash "finish_reason" first-choice)))
         (usage (gethash "usage" raw-response))
         (tool-calls-raw (when message (gethash "tool_calls" message)))
         (tool-calls (when tool-calls-raw
                      (parse-tool-calls provider raw-response))))

    (make-instance 'completion-response
                   :id (gethash "id" raw-response)
                   :model (gethash "model" raw-response)
                   :content content
                   :message (%json-hash-to-keyword-plist message)
                   :tool-calls tool-calls
                   :finish-reason (when finish-reason
                                    (intern (string-upcase finish-reason) :keyword))
                   :usage (when usage
                            (list :prompt-tokens (or (gethash "prompt_tokens" usage) 0)
                                  :completion-tokens (or (gethash "completion_tokens" usage) 0)
                                  :total-tokens (or (gethash "total_tokens" usage) 0)))
                   :raw raw-response
                   :performance performance
                   :metadata (let ((metadata nil))
                              ;; Provider introspection
                              (setf (getf metadata :provider-type) (provider-type provider))
                              (setf (getf metadata :provider-name) (provider-name provider))
                              ;; Extract system fingerprint
                              (when-let ((fingerprint (gethash "system_fingerprint" raw-response)))
                                (setf (getf metadata :system-fingerprint) fingerprint))
                              ;; Extract created timestamp
                              (when-let ((created (gethash "created" raw-response)))
                                (setf (getf metadata :created) created))
                              ;; Extract detailed token usage (o1/o3 reasoning, caching, audio)
                              (when usage
                                (when-let ((completion-details (gethash "completion_tokens_details" usage)))
                                  (setf (getf metadata :completion-tokens-details)
                                        (alexandria:hash-table-plist completion-details)))
                                (when-let ((prompt-details (gethash "prompt_tokens_details" usage)))
                                  (setf (getf metadata :prompt-tokens-details)
                                        (alexandria:hash-table-plist prompt-details))))
                              metadata))))

(defmethod send-embedding-request ((provider openai-provider) input
                                   &key model dimensions)
  (let* ((url (format nil "~A/embeddings" (provider-base-url provider)))
         (headers (make-http-headers provider))
         (encoded-body nil))

    ;; Build and encode request body (with timing)
    (with-performance-timing (:encode-time)
      (let ((body (make-hash-table :test 'equal)))
        ;; Build request body
        (setf (gethash "model" body) model)
        (setf (gethash "input" body)
              (etypecase input
                (string input)
                (list input)))

        (when dimensions
          (setf (gethash "dimensions" body) dimensions))

        ;; Encode to JSON
        (setf encoded-body
              (with-output-to-string (s)
                (yason:encode body s)))))

    ;; Make HTTP request (with timing)
    (with-performance-timing (:api-time)
      (provider-http-post provider url headers encoded-body :operation :embedding))))

(defmethod parse-embedding-response ((provider openai-provider) raw-response
                                     &key performance)
  (let* ((data (gethash "data" raw-response))
         (usage (gethash "usage" raw-response))
         (embeddings (map 'list
                          (lambda (item)
                            (let ((embedding (gethash "embedding" item)))
                              (coerce embedding 'list)))
                          data)))

    (make-instance 'embedding-response
                   :embeddings embeddings
                   :model (gethash "model" raw-response)
                   :usage (when usage
                            (list :prompt-tokens (or (gethash "prompt_tokens" usage) 0)
                                  :total-tokens (or (gethash "total_tokens" usage) 0)))
                   :raw raw-response
                   :performance performance
                   :metadata (let ((metadata nil))
                              ;; Provider introspection
                              (setf (getf metadata :provider-type) (provider-type provider))
                              (setf (getf metadata :provider-name) (provider-name provider))
                              ;; Extract created timestamp
                              (when-let ((created (gethash "created" raw-response)))
                                (setf (getf metadata :created) created))
                              ;; Extract object type
                              (when-let ((object (gethash "object" raw-response)))
                                (setf (getf metadata :object) object))
                              metadata))))

(defmethod send-streaming-request ((provider openai-provider) messages
                                   &key model max-tokens temperature
                                        system tools tool-choice stop)
  "Send streaming completion request to OpenAI."
  (let* ((url (format nil "~A/chat/completions" (provider-base-url provider)))
         (headers (make-http-headers provider))
         (body (make-hash-table :test 'equal)))

    ;; Build request body
    (setf (gethash "model" body) (or model (provider-default-model provider) "gpt-4"))
    (setf (gethash "stream" body) t)  ; Enable streaming

    ;; Convert messages, prepending system if provided
    (let ((all-messages (if system
                           (cons (list :role "system" :content system) messages)
                           messages)))
      (setf (gethash "messages" body)
            (map 'vector
                 (lambda (m) (translate-message-to-provider provider m))
                 all-messages)))

    (when max-tokens
      (setf (gethash "max_tokens" body) max-tokens))
    (when temperature
      (setf (gethash "temperature" body) temperature))
    (when stop
      (setf (gethash "stop" body) (ensure-list stop)))
    (when tools
      (setf (gethash "tools" body)
            (map 'vector (lambda (tool) (translate-tool-to-provider provider tool)) tools)))
    (when tool-choice
      (setf (gethash "tool_choice" body)
            (etypecase tool-choice
              (keyword (string-downcase (symbol-name tool-choice)))
              (string (plist-to-hash (list :type "function"
                                           :function (list :name tool-choice)))))))

    ;; Make streaming HTTP request
    (let ((encoded-body (with-output-to-string (s)
                         (yason:encode body s))))
      (handler-case
          (multiple-value-bind (response-stream status-code response-headers)
              (dex:post url
                        :headers headers
                        :content encoded-body
                        :want-stream t
                        :read-timeout (getf (provider-options provider) :timeout 120))
            (declare (ignore response-headers))
            (if (and (>= status-code 200) (< status-code 300))
                (make-instance 'completion-stream
                               :provider provider
                               :model (or model (provider-default-model provider))
                               :http-stream response-stream
                               :state :open)
                (handle-http-error status-code
                                  (handler-case
                                      (let ((body-text (alexandria:read-stream-content-into-string response-stream)))
                                        (yason:parse body-text))
                                    (error ()
                                      "Stream error"))
                                  provider)))
        ;; Handle HTTP errors raised by dexador (e.g., when want-stream is true)
        (dex:http-request-failed (e)
          (handle-http-error (dex:response-status e)
                            (handler-case
                                (yason:parse (dex:response-body e))
                              (error () (dex:response-body e)))
                            provider))
        (error (e)
          (error 'provider-network-error
                 :provider provider
                 :url url
                 :operation :streaming
                 :original-error e
                 :message (format nil "Network error: ~A" e)))))))
