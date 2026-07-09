(in-package :cl-llm-provider)

;;;; OpenRouter Provider Implementation
;;;;
;;;; OpenRouter uses OpenAI-compatible API with additional headers

(defmethod provider-default-base-url ((provider openrouter-provider))
  "https://openrouter.ai/api/v1")

(defmethod provider-api-key-env-var ((provider openrouter-provider))
  "OPENROUTER_API_KEY")

;;; Provider Introspection

(defmethod provider-type ((provider openrouter-provider))
  :openrouter)

(defmethod provider-name ((provider openrouter-provider))
  "OpenRouter")

(defmethod provider-capabilities ((provider openrouter-provider))
  '(:tools t
    :embeddings nil  ; OpenRouter routes to models, not all support embeddings
    :streaming t
    :vision t  ; Model-dependent, but many models support it
    :function-calling t))

(defmethod send-completion-request ((provider openrouter-provider) messages
                                    &key model max-tokens temperature
                                         system tools tool-choice stop)
  (let* ((url (format nil "~A/chat/completions" (provider-base-url provider)))
         (headers (append
                   (make-http-headers provider)
                   ;; OpenRouter-specific headers
                   (list (cons "HTTP-Referer" "https://github.com/cl-llm-provider")
                         (cons "X-Title" "cl-llm-provider"))))
         (encoded-body nil))

    ;; Build and encode request body (with timing)
    (with-performance-timing (:encode-time)
      (let ((body (make-hash-table :test 'equal)))
        ;; Build request body (OpenAI-compatible format)
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
                  (string tool-choice))))

        ;; Encode to JSON
        (setf encoded-body
              (with-output-to-string (s)
                (yason:encode body s)))))

    ;; Make HTTP request (with timing)
    (with-performance-timing (:api-time)
      (provider-http-post provider url headers encoded-body :operation :completion))))

;; OpenRouter uses OpenAI-compatible response format
(defmethod parse-completion-response ((provider openrouter-provider) raw-response
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
                              metadata))))

(defmethod send-embedding-request ((provider openrouter-provider) input
                                   &key model dimensions)
  (let* ((url (format nil "~A/embeddings" (provider-base-url provider)))
         (headers (append
                   (make-http-headers provider)
                   (list (cons "HTTP-Referer" "https://github.com/cl-llm-provider")
                         (cons "X-Title" "cl-llm-provider"))))
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

;; OpenRouter uses OpenAI-compatible embedding response format
(defmethod parse-embedding-response ((provider openrouter-provider) raw-response
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
                              metadata))))
