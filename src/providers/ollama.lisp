(in-package :cl-llm-provider)

;;;; Ollama Provider Implementation

(defmethod provider-default-base-url ((provider ollama-provider))
  (or (uiop:getenv "OLLAMA_BASE_URL")
      "http://localhost:11434"))

(defmethod provider-api-key-env-var ((provider ollama-provider))
  nil)  ; Ollama doesn't require API key for local usage

;;; Provider Introspection

(defmethod provider-type ((provider ollama-provider))
  :ollama)

(defmethod provider-name ((provider ollama-provider))
  "Ollama")

(defmethod provider-capabilities ((provider ollama-provider))
  '(:tools t
    :embeddings t
    :streaming nil  ; no send-streaming-request implemented yet (NDJSON /api/chat)
    :vision nil  ; Model-dependent, conservative default
    :function-calling t))

(defvar *ollama-tool-call-counter* 0)
(defvar *ollama-tool-call-lock* (bt:make-lock "ollama-tool-call-ids")
  "Serializes tool-call id generation; Ollama responses carry no ids of their own.")

(defun %next-ollama-tool-call-id ()
  (bt:with-lock-held (*ollama-tool-call-lock*)
    (format nil "call_~D" (incf *ollama-tool-call-counter*))))

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
              (let ((all (if system
                             (cons (list :role "system" :content system) messages)
                             messages)))
                (map 'vector
                     (lambda (m) (translate-message-to-provider provider m))
                     all)))

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
        ;; Default off since most models don't support it;
        ;; enable via :options (list :think t) for reasoning models
        (setf (gethash "think" body)
              (getf (provider-options provider) :think yason:false))

        ;; Encode to JSON
        (setf encoded-body
              (with-output-to-string (s)
                (yason:encode body s)))))

    ;; Make HTTP request (with timing)
    (with-performance-timing (:api-time)
      (provider-http-post provider url headers encoded-body :operation :completion))))

(defmethod parse-completion-response ((provider ollama-provider) raw-response
                                      &key performance)
  (let* ((message (gethash "message" raw-response))
         ;; guard: message may be NIL
         (content (when message (gethash "content" message)))
         (thinking (when message (gethash "thinking" message)))  ; Reasoning trace for models like DeepSeek-R1
         (role (or (when message (gethash "role" message)) "assistant"))
         ;; Combine thinking and content if both present
         (full-content (cond
                         ((and thinking content)
                          (format nil "<thinking>~%~A~%</thinking>~%~%~A" thinking content))
                         (thinking thinking)
                         (content content)
                         (t "")))
         (tool-calls-raw (when message (gethash "tool_calls" message)))
         (tool-calls (when tool-calls-raw
                      (loop for tc in (coerce tool-calls-raw 'list)
                            for function = (gethash "function" tc)
                            for name = (gethash "name" function)
                            collect (make-instance 'tool-call
                                                   :id (or (gethash "id" tc)
                                                          (%next-ollama-tool-call-id))
                                                   :name name
                                                   :arguments (%parse-tool-arguments
                                                               (gethash "arguments" function)
                                                               name)))))
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
                              ;; Provider introspection
                              (setf (getf metadata :provider-type) (provider-type provider))
                              (setf (getf metadata :provider-name) (provider-name provider))
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
  (let* ((url (format nil "~A/api/embed" (provider-base-url provider)))
         (headers (list (cons "Content-Type" "application/json")))
         (encoded-body nil))

    (when dimensions
      (warn 'llm-provider-warning
            :provider provider
            :message "Ollama does not support the :dimensions parameter; ignoring it"))

    ;; Build and encode request body (with timing)
    (with-performance-timing (:encode-time)
      (let ((body (make-hash-table :test 'equal)))
        ;; Build request body
        (setf (gethash "model" body) model)
        (setf (gethash "input" body)
              (etypecase input
                (string input)
                (list input)))

        ;; Encode to JSON
        (setf encoded-body
              (with-output-to-string (s)
                (yason:encode body s)))))

    ;; Make HTTP request (with timing)
    (with-performance-timing (:api-time)
      (provider-http-post provider url headers encoded-body :operation :embedding))))

(defmethod parse-embedding-response ((provider ollama-provider) raw-response
                                     &key performance)
  (let ((embeddings (or (gethash "embeddings" raw-response)
                        (when-let ((embedding (gethash "embedding" raw-response)))
                          (vector embedding)))))
    (make-instance 'embedding-response
                   :embeddings (map 'list (lambda (embedding)
                                            (coerce embedding 'list))
                                    (or embeddings #()))
                   :model (or (gethash "model" raw-response) "unknown")
                   :usage (list :prompt-tokens
                                (or (gethash "prompt_eval_count" raw-response) 0)
                                :total-tokens
                                (or (gethash "prompt_eval_count" raw-response) 0))
                   :raw raw-response
                   :performance performance
                   :metadata (let ((metadata nil))
                              ;; Provider introspection
                              (setf (getf metadata :provider-type) (provider-type provider))
                              (setf (getf metadata :provider-name) (provider-name provider))
                              ;; Extract timing information if available
                              (when-let ((total-dur (gethash "total_duration" raw-response)))
                                (setf (getf metadata :total-duration-ns) total-dur))
                              (when-let ((load-dur (gethash "load_duration" raw-response)))
                                (setf (getf metadata :load-duration-ns) load-dur))
                              metadata))))
