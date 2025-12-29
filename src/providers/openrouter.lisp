(in-package :cl-llm-provider)

;;;; OpenRouter Provider Implementation
;;;;
;;;; OpenRouter uses OpenAI-compatible API with additional headers

(defmethod provider-default-base-url ((provider openrouter-provider))
  "https://openrouter.ai/api/v1")

(defmethod provider-api-key-env-var ((provider openrouter-provider))
  "OPENROUTER_API_KEY")

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
              (if system
                  (cons (plist-to-hash (list :role "system" :content system))
                        (mapcar #'plist-to-hash messages))
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

;; OpenRouter uses OpenAI-compatible response format
(defmethod parse-completion-response ((provider openrouter-provider) raw-response
                                      &key performance)
  (call-next-method provider raw-response :performance performance))  ; Use openai-provider's implementation via inheritance

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

;; OpenRouter uses OpenAI-compatible embedding response format
(defmethod parse-embedding-response ((provider openrouter-provider) raw-response
                                     &key performance)
  (call-next-method provider raw-response :performance performance))  ; Use openai-provider's implementation via inheritance
