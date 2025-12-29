(in-package :cl-llm-provider)

;;;; OpenAI Provider Implementation

(defmethod provider-default-base-url ((provider openai-provider))
  "https://api.openai.com/v1")

(defmethod provider-api-key-env-var ((provider openai-provider))
  "OPENAI_API_KEY")

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
              (values (dex:response-body e) (dex:response-status e)))))

      (if (and (>= status-code 200) (< status-code 300))
          (yason:parse response-body)
          (handle-http-error status-code
                            (handler-case (yason:parse response-body)
                              (error () response-body))
                            provider)))))

(defmethod parse-completion-response ((provider openai-provider) raw-response
                                      &key performance)
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
                   :usage (list :prompt-tokens (gethash "prompt_tokens" usage)
                                :completion-tokens (gethash "completion_tokens" usage)
                                :total-tokens (gethash "total_tokens" usage))
                   :raw raw-response
                   :performance performance
                   :metadata (let ((metadata nil))
                              ;; Extract system fingerprint
                              (when-let ((fingerprint (gethash "system_fingerprint" raw-response)))
                                (setf (getf metadata :system-fingerprint) fingerprint))
                              ;; Extract created timestamp
                              (when-let ((created (gethash "created" raw-response)))
                                (setf (getf metadata :created) created))
                              ;; Extract detailed token usage (o1/o3 reasoning, caching, audio)
                              (when-let ((completion-details (gethash "completion_tokens_details" usage)))
                                (setf (getf metadata :completion-tokens-details)
                                      (alexandria:hash-table-plist completion-details)))
                              (when-let ((prompt-details (gethash "prompt_tokens_details" usage)))
                                (setf (getf metadata :prompt-tokens-details)
                                      (alexandria:hash-table-plist prompt-details)))
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
    (multiple-value-bind (response-body status-code)
        (with-performance-timing (:api-time)
          (handler-case
              (dex:post url
                        :headers headers
                        :content encoded-body
                        :force-string t)
            (dex:http-request-failed (e)
              (values (dex:response-body e) (dex:response-status e)))))

      (if (and (>= status-code 200) (< status-code 300))
          (yason:parse response-body)
          (handle-http-error status-code
                            (handler-case (yason:parse response-body)
                              (error () response-body))
                            provider)))))

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
                   :usage (list :prompt-tokens (gethash "prompt_tokens" usage)
                                :total-tokens (gethash "total_tokens" usage))
                   :raw raw-response
                   :performance performance
                   :metadata (let ((metadata nil))
                              ;; Extract created timestamp
                              (when-let ((created (gethash "created" raw-response)))
                                (setf (getf metadata :created) created))
                              ;; Extract object type
                              (when-let ((object (gethash "object" raw-response)))
                                (setf (getf metadata :object) object))
                              metadata))))
