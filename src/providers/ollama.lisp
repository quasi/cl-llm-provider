(in-package :cl-llm-provider)

;;;; Ollama Provider Implementation

(defmethod provider-default-base-url ((provider ollama-provider))
  (or (uiop:getenv "OLLAMA_BASE_URL")
      "http://localhost:11434"))

(defmethod provider-api-key-env-var ((provider ollama-provider))
  nil)  ; Ollama doesn't require API key for local usage

(defmethod send-completion-request ((provider ollama-provider) messages
                                    &key model max-tokens temperature
                                         system tools tool-choice stop)
  (declare (ignore tool-choice))  ; Ollama uses tools directly if provided

  (let* ((url (format nil "~A/api/chat" (provider-base-url provider)))
         (headers (list (cons "Content-Type" "application/json")))
         (encoded-body nil))

    ;; Build and encode request body (with timing)
    (with-performance-timing (:encode-time)
      (let ((body (make-hash-table :test 'equal))
            (options (make-hash-table :test 'equal)))

        ;; Build request body (Ollama format)
        (setf (gethash "model" body) model)

        ;; Add system message if provided
        (setf (gethash "messages" body)
              (if system
                  (cons (plist-to-hash (list :role "system" :content system))
                        (mapcar #'plist-to-hash messages))
                  (mapcar #'plist-to-hash messages)))

        ;; Ollama uses options hash for parameters
        (when max-tokens
          (setf (gethash "num_predict" options) max-tokens))

        (when temperature
          (setf (gethash "temperature" options) temperature))

        (when stop
          (setf (gethash "stop" options) (ensure-list stop)))

        (when (> (hash-table-count options) 0)
          (setf (gethash "options" body) options))

        ;; Add tools if provided (Ollama supports OpenAI-compatible tool format)
        (when tools
          (setf (gethash "tools" body)
                (map 'vector
                     (lambda (tool) (translate-tool-to-provider provider tool))
                     tools)))

        ;; Ollama requires stream: false for non-streaming
        (setf (gethash "stream" body) yason:false)

        ;; Enable thinking mode for reasoning models (qwen, deepseek-r1, etc.)
        ;; This can be overridden via provider options
        (setf (gethash "think" body)
              (getf (provider-options provider) :think yason:true))

        ;; Encode to JSON
        (setf encoded-body
              (with-output-to-string (s)
                (yason:encode body s)))))

    ;; Make HTTP request (with timing)
    ;; Use longer timeout for reasoning models with thinking enabled (default 120s)
    (multiple-value-bind (response-body status-code)
        (with-performance-timing (:api-time)
          (handler-case
              (dex:post url
                        :headers headers
                        :content encoded-body
                        :force-string t
                        :read-timeout (getf (provider-options provider) :timeout 120))
            (dex:http-request-failed (e)
              (values (dex:response-body e) (dex:response-status e)))))

      (if (and (>= status-code 200) (< status-code 300))
          (yason:parse response-body)
          (handle-http-error status-code
                            (handler-case (yason:parse response-body)
                              (error () response-body))
                            provider)))))

(defmethod parse-completion-response ((provider ollama-provider) raw-response
                                      &key performance)
  (let* ((message (gethash "message" raw-response))
         (content (gethash "content" message))
         (thinking (gethash "thinking" message))  ; Reasoning trace for models like DeepSeek-R1
         (role (gethash "role" message))
         ;; Combine thinking and content if both present
         (full-content (cond
                         ((and thinking content)
                          (format nil "<thinking>~%~A~%</thinking>~%~%~A" thinking content))
                         (thinking thinking)
                         (content content)
                         (t "")))
         (tool-calls-raw (gethash "tool_calls" message))
         (tool-calls (when tool-calls-raw
                      (loop for tc in (coerce tool-calls-raw 'list)
                            for function = (gethash "function" tc)
                            collect (make-instance 'tool-call
                                                   :id (or (gethash "id" tc)
                                                          (format nil "call_~A" (random 1000000)))
                                                   :name (gethash "name" function)
                                                   :arguments (let ((args-str (gethash "arguments" function)))
                                                               (if (stringp args-str)
                                                                   (yason:parse args-str)
                                                                   args-str))))))
         (finish-reason (or (gethash "done_reason" raw-response) "stop")))

    (make-instance 'completion-response
                   :id (format nil "ollama-~A" (get-universal-time))
                   :model (gethash "model" raw-response)
                   :content full-content
                   :message (list :role role :content full-content)
                   :tool-calls tool-calls
                   :finish-reason (intern (string-upcase finish-reason) :keyword)
                   :usage (let ((eval-count (gethash "eval_count" raw-response))
                               (prompt-eval-count (gethash "prompt_eval_count" raw-response)))
                           (list :prompt-tokens (or prompt-eval-count 0)
                                 :completion-tokens (or eval-count 0)
                                 :total-tokens (+ (or prompt-eval-count 0)
                                                 (or eval-count 0))))
                   :raw raw-response
                   :performance performance
                   :metadata (let ((metadata nil))
                              ;; Extract timing information (in nanoseconds)
                              (when-let ((total-dur (gethash "total_duration" raw-response)))
                                (setf (getf metadata :total-duration-ns) total-dur))
                              (when-let ((load-dur (gethash "load_duration" raw-response)))
                                (setf (getf metadata :load-duration-ns) load-dur))
                              (when-let ((prompt-dur (gethash "prompt_eval_duration" raw-response)))
                                (setf (getf metadata :prompt-eval-duration-ns) prompt-dur))
                              (when-let ((eval-dur (gethash "eval_duration" raw-response)))
                                (setf (getf metadata :eval-duration-ns) eval-dur))
                              ;; Extract creation timestamp
                              (when-let ((created-at (gethash "created_at" raw-response)))
                                (setf (getf metadata :created-at) created-at))
                              metadata))))

(defmethod send-embedding-request ((provider ollama-provider) input
                                   &key model dimensions)
  (declare (ignore dimensions))  ; Ollama doesn't support dimensions parameter

  (let* ((url (format nil "~A/api/embeddings" (provider-base-url provider)))
         (headers (list (cons "Content-Type" "application/json")))
         (encoded-body nil))

    ;; Build and encode request body (with timing)
    (with-performance-timing (:encode-time)
      (let ((body (make-hash-table :test 'equal)))
        ;; Build request body
        (setf (gethash "model" body) model)
        (setf (gethash "prompt" body) input)

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
                        :force-string t
                        :read-timeout (getf (provider-options provider) :timeout 120))
            (dex:http-request-failed (e)
              (values (dex:response-body e) (dex:response-status e)))))

      (if (and (>= status-code 200) (< status-code 300))
          (yason:parse response-body)
          (handle-http-error status-code
                            (handler-case (yason:parse response-body)
                              (error () response-body))
                            provider)))))

(defmethod parse-embedding-response ((provider ollama-provider) raw-response
                                     &key performance)
  (let ((embedding (gethash "embedding" raw-response)))
    (make-instance 'embedding-response
                   :embeddings (list (coerce embedding 'list))
                   :model (or (gethash "model" raw-response) "unknown")
                   :usage (list :prompt-tokens 0 :total-tokens 0)
                   :raw raw-response
                   :performance performance
                   :metadata (let ((metadata nil))
                              ;; Extract timing information if available
                              (when-let ((total-dur (gethash "total_duration" raw-response)))
                                (setf (getf metadata :total-duration-ns) total-dur))
                              (when-let ((load-dur (gethash "load_duration" raw-response)))
                                (setf (getf metadata :load-duration-ns) load-dur))
                              metadata))))
