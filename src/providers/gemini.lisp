(in-package :cl-llm-provider)

;;;; Google Gemini Provider Implementation

(defmethod provider-default-base-url ((provider gemini-provider))
  "https://generativelanguage.googleapis.com/v1beta/openai")

(defmethod provider-api-key-env-var ((provider gemini-provider))
  "GEMINI_API_KEY")

;;; Provider Introspection

(defmethod provider-type ((provider gemini-provider))
  :gemini)

(defmethod provider-name ((provider gemini-provider))
  "Google Gemini")

(defmethod provider-capabilities ((provider gemini-provider))
  '(:tools t
    :embeddings t
    :streaming t
    :vision t
    :function-calling t))

(defmethod model-metadata ((provider gemini-provider) model-name)
  (get-model-metadata *gemini-model-registry* model-name))

;;; Completion Protocol

(defmethod send-completion-request ((provider gemini-provider) messages
                                    &key model max-tokens temperature
                                         system tools tool-choice stop)
  "Send completion request to Gemini using OpenAI-compatible endpoint.
Reuses OpenAI request format since Gemini's /v1beta/openai/ endpoint is compatible."
  (let* ((url (format nil "~A/chat/completions" (provider-base-url provider)))
         (headers (make-http-headers provider))
         (encoded-body nil))

    ;; Build and encode request body (with timing)
    (with-performance-timing (:encode-time)
      (let ((body (make-hash-table :test 'equal)))
        ;; Build request body (OpenAI format)
        (setf (gethash "model" body) model)
        (setf (gethash "messages" body)
              (if system
                  ;; Add system message at the beginning
                  (cons (plist-to-hash (list :role "system" :content system))
                        (mapcar #'plist-to-hash messages))
                  ;; No system message
                  (mapcar #'plist-to-hash messages)))

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
                  (string tool-choice))))

        ;; Encode to JSON
        (setf encoded-body
              (with-output-to-string (s)
                (yason:encode body s)))))

    ;; Make HTTP request (with timing)
    (multiple-value-bind (response-body status-code)
        (with-performance-timing (:api-time)
          (handler-case
              (dex:post url
                        :headers headers
                        :content encoded-body
                        :force-string t)
            (dex:http-request-failed (e)
              (values (dex:response-body e) (dex:response-status e)))
            (error (e)
              (error 'provider-network-error
                     :provider provider
                     :url url
                     :operation :completion
                     :original-error e
                     :message (format nil "Network error: ~A" e)))))

      (if (and (>= status-code 200) (< status-code 300))
          (yason:parse response-body)
          (handle-http-error status-code
                            (handler-case (yason:parse response-body)
                              (error () response-body))
                            provider)))))

(defmethod parse-completion-response ((provider gemini-provider) raw-response
                                      &key performance)
  "Parse Gemini completion response (OpenAI-compatible format)."
  (let* ((choices (gethash "choices" raw-response))
         (first-choice (when (and choices (> (length choices) 0))
                        (elt choices 0)))
         (message (gethash "message" first-choice))
         (content (gethash "content" message))
         (finish-reason (gethash "finish_reason" first-choice))
         (usage (gethash "usage" raw-response))
         (tool-calls-raw (gethash "tool_calls" message))
         (tool-calls (when tool-calls-raw
                      (parse-tool-calls provider raw-response))))

    (make-instance 'completion-response
                   :id (gethash "id" raw-response)
                   :model (gethash "model" raw-response)
                   :content content
                   :message (alexandria:hash-table-plist message)
                   :tool-calls tool-calls
                   :finish-reason (intern (string-upcase finish-reason) :keyword)
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
                              ;; Extract created timestamp
                              (when-let ((created (gethash "created" raw-response)))
                                (setf (getf metadata :created) created))
                              metadata))))

;;; Embedding Protocol

(defmethod send-embedding-request ((provider gemini-provider) input
                                   &key model dimensions)
  "Send embedding request to Gemini using OpenAI-compatible endpoint."
  (let* ((url (format nil "~A/embeddings" (provider-base-url provider)))
         (headers (make-http-headers provider))
         (encoded-body nil))

    ;; Build and encode request body (with timing)
    (with-performance-timing (:encode-time)
      (let ((body (make-hash-table :test 'equal)))
        ;; Build request body (OpenAI format)
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
    (multiple-value-bind (response-body status-code)
        (with-performance-timing (:api-time)
          (handler-case
              (dex:post url
                        :headers headers
                        :content encoded-body
                        :force-string t)
            (dex:http-request-failed (e)
              (values (dex:response-body e) (dex:response-status e)))
            (error (e)
              (error 'provider-network-error
                     :provider provider
                     :url url
                     :operation :embedding
                     :original-error e
                     :message (format nil "Network error: ~A" e)))))

      (if (and (>= status-code 200) (< status-code 300))
          (yason:parse response-body)
          (handle-http-error status-code
                            (handler-case (yason:parse response-body)
                              (error () response-body))
                            provider)))))

(defmethod parse-embedding-response ((provider gemini-provider) raw-response
                                     &key performance)
  "Parse Gemini embedding response (OpenAI-compatible format)."
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

;;; Streaming Protocol

(defmethod send-streaming-request ((provider gemini-provider) messages
                                   &key model max-tokens temperature
                                        system tools tool-choice stop)
  "Send streaming completion request to Gemini."
  (let* ((url (format nil "~A/chat/completions" (provider-base-url provider)))
         (headers (make-http-headers provider))
         (body (make-hash-table :test 'equal)))

    ;; Build request body (OpenAI format with stream=true)
    (setf (gethash "model" body) (or model (provider-default-model provider) "gemini-3-flash-preview"))
    (setf (gethash "stream" body) t)  ; Enable streaming

    ;; Convert messages, prepending system if provided
    (let ((all-messages (if system
                           (cons (list :role "system" :content system) messages)
                           messages)))
      (setf (gethash "messages" body)
            (map 'vector #'plist-to-hash all-messages)))

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
                        :want-stream t)
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
                                    (error () "Stream error"))
                                  provider)))
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
