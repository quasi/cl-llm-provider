(in-package :cl-llm-provider)

;;;; Anthropic Provider Implementation

(defmethod provider-default-base-url ((provider anthropic-provider))
  "https://api.anthropic.com/v1")

(defmethod provider-api-key-env-var ((provider anthropic-provider))
  "ANTHROPIC_API_KEY")

;;; Provider Introspection

(defmethod provider-type ((provider anthropic-provider))
  :anthropic)

(defmethod provider-name ((provider anthropic-provider))
  "Anthropic")

(defmethod provider-capabilities ((provider anthropic-provider))
  '(:tools t
    :embeddings nil
    :streaming t
    :vision t
    :function-calling t))

(defmethod model-metadata ((provider anthropic-provider) model-name)
  (get-model-metadata *anthropic-model-registry* model-name))

(defmethod translate-tool-to-provider ((provider anthropic-provider) (tool tool-definition))
  "Anthropic tool format: name/description/input_schema envelope."
  (declare (ignore provider))
  (let ((result (make-hash-table :test 'equal)))
    (setf (gethash "name" result) (tool-name tool))
    (setf (gethash "description" result) (tool-description tool))
    (setf (gethash "input_schema" result) (parameter-specs-to-json-schema tool))
    result))

(defun %tool-result-block (message)
  "Build an Anthropic tool_result content-block plist from a role=\"tool\" MESSAGE."
  (let ((block (list :type "tool_result"
                     :tool-use-id (getf message :tool-call-id)
                     :content (getf message :content))))
    (if (getf message :is-error)
        (append block (list :is-error t))
        block)))

(defmethod translate-message-to-provider ((provider anthropic-provider) message)
  "Anthropic format: tool results are tool_result content blocks in a user message."
  (if (equal (getf message :role) "tool")
      (plist-to-hash (list :role "user"
                           :content (list (%tool-result-block message))))
      (call-next-method)))

(defun %user-content-blocks (msg-hash)
  "Return MSG-HASH's content as a list of content-block hash-tables."
  (let ((content (gethash "content" msg-hash)))
    (etypecase content
      (string (list (plist-to-hash (list :type "text" :text content))))
      (list content)
      (vector (coerce content 'list)))))

(defun %merge-consecutive-user-turns (wire-list)
  "Merge adjacent role=\"user\" wire messages into one content-block message."
  (let ((merged '()))
    (dolist (msg wire-list (nreverse merged))
      (let ((prev (first merged)))
        (if (and prev
                 (equal (gethash "role" prev) "user")
                 (equal (gethash "role" msg) "user"))
            (setf (gethash "content" prev)
                  (append (%user-content-blocks prev)
                          (%user-content-blocks msg)))
            (push msg merged))))))

(defun %anthropic-wire-messages (provider messages)
  "Translate MESSAGES to Anthropic wire format with alternating turns."
  (let ((wire '())
        (pending-results '()))
    (flet ((flush-results ()
             (when pending-results
               (push (plist-to-hash (list :role "user"
                                          :content (nreverse pending-results)))
                     wire)
               (setf pending-results nil))))
      (dolist (msg messages)
        (if (equal (getf msg :role) "tool")
            (push (%tool-result-block msg) pending-results)
            (progn
              (flush-results)
              (push (translate-message-to-provider provider msg) wire))))
      (flush-results))
    (coerce (%merge-consecutive-user-turns (nreverse wire)) 'vector)))

(defmethod send-completion-request ((provider anthropic-provider) messages
                                    &key model max-tokens temperature
                                         system tools tool-choice stop)
  (let* ((url (format nil "~A/messages" (provider-base-url provider)))
         (headers (append
                   (make-http-headers provider)
                   (list (cons "anthropic-version" "2023-06-01"))))
         (encoded-body nil))

    ;; Build and encode request body (with timing)
    (with-performance-timing (:encode-time)
      (let ((body (make-hash-table :test 'equal)))
        ;; Build request body (Anthropic format)
        (setf (gethash "model" body) model)
        (setf (gethash "max_tokens" body) (or max-tokens 4096))

        ;; Anthropic uses separate system parameter
        (when system
          (setf (gethash "system" body) system))

        ;; Convert messages
        (setf (gethash "messages" body)
              (%anthropic-wire-messages provider messages))

        (when temperature
          (setf (gethash "temperature" body) temperature))

        (when stop
          (setf (gethash "stop_sequences" body) (ensure-list stop)))

        (when tools
          (setf (gethash "tools" body)
                (map 'vector
                     (lambda (tool) (translate-tool-to-provider provider tool))
                     tools)))

        (when tool-choice
          (setf (gethash "tool_choice" body)
                (etypecase tool-choice
                  (keyword (plist-to-hash
                            (list :type (string-downcase (symbol-name tool-choice)))))
                  (string (plist-to-hash
                           (list :type "tool" :name tool-choice))))))

        ;; Encode to JSON
        (setf encoded-body
              (with-output-to-string (s)
                (yason:encode body s)))))

    ;; Make HTTP request (with timing)
    (with-performance-timing (:api-time)
      (provider-http-post provider url headers encoded-body :operation :completion))))

(defmethod parse-completion-response ((provider anthropic-provider) raw-response
                                      &key performance)
  (let* ((content-blocks (gethash "content" raw-response))
         (text-content
           (let ((texts (loop for block in (coerce (or content-blocks #()) 'list)
                              when (string= (gethash "type" block) "text")
                              collect (gethash "text" block))))
             (when texts
               (format nil "~{~A~}" texts))))
         (finish-reason (gethash "stop_reason" raw-response))
         (usage (gethash "usage" raw-response))
         (tool-calls
           (loop for block in (coerce (or content-blocks #()) 'list)
                 when (string= (gethash "type" block) "tool_use")
                 collect (make-instance 'tool-call
                                        :id (gethash "id" block)
                                        :name (gethash "name" block)
                                        :arguments (gethash "input" block)))))
    (make-instance 'completion-response
                   :id (gethash "id" raw-response)
                   :model (gethash "model" raw-response)
                   :content text-content
                   ;; Message mirrors the raw content blocks so it can be echoed
                   ;; back to the API for conversation continuation (tool loops).
                   :message (list :role "assistant"
                                  :content (loop for block in (coerce (or content-blocks #()) 'list)
                                                 collect (%json-hash-to-keyword-plist block)))
                   :tool-calls tool-calls
                   :finish-reason (when finish-reason
                                    (intern (string-upcase finish-reason) :keyword))
                   :usage (when usage
                            (let ((in (or (gethash "input_tokens" usage) 0))
                                  (out (or (gethash "output_tokens" usage) 0)))
                              (list :prompt-tokens in
                                    :completion-tokens out
                                    :total-tokens (+ in out))))
                   :raw raw-response
                   :performance performance
                   :metadata (let ((metadata nil))
                               (setf (getf metadata :provider-type) (provider-type provider))
                               (setf (getf metadata :provider-name) (provider-name provider))
                               (when-let ((stop-seq (gethash "stop_sequence" raw-response)))
                                 (setf (getf metadata :stop-sequence) stop-seq))
                               metadata))))

(defmethod parse-tool-calls ((provider anthropic-provider) raw-response)
  "Parse Anthropic-style tool uses from content blocks."
  (let ((content-blocks (gethash "content" raw-response)))
    (loop for block in (coerce content-blocks 'list)
          for block-type = (gethash "type" block)
          when (string= block-type "tool_use")
          collect (make-instance 'tool-call
                                 :id (gethash "id" block)
                                 :name (gethash "name" block)
                                 :arguments (gethash "input" block)))))

(defmethod send-streaming-request ((provider anthropic-provider) messages
                                   &key model max-tokens temperature
                                        system tools tool-choice stop)
  "Send streaming completion request to Anthropic."
  (let* ((url (format nil "~A/messages" (provider-base-url provider)))
         (headers (append
                   (make-http-headers provider)
                   (list (cons "anthropic-version" "2023-06-01"))))
         (body (make-hash-table :test 'equal)))

    ;; Build request body
    (setf (gethash "model" body) (or model (provider-default-model provider) "claude-3-sonnet-20240229"))
    (setf (gethash "max_tokens" body) (or max-tokens 4096))
    (setf (gethash "stream" body) t)

    (when system
      (setf (gethash "system" body) system))

    (setf (gethash "messages" body)
          (%anthropic-wire-messages provider messages))

    (when temperature
      (setf (gethash "temperature" body) temperature))
    (when stop
      (setf (gethash "stop_sequences" body) (ensure-list stop)))
    (when tools
      (setf (gethash "tools" body)
            (map 'vector (lambda (tool) (translate-tool-to-provider provider tool)) tools)))
    (when tool-choice
      (setf (gethash "tool_choice" body)
            (etypecase tool-choice
              (keyword (plist-to-hash
                        (list :type (string-downcase (symbol-name tool-choice)))))
              (string (plist-to-hash
                       (list :type "tool" :name tool-choice))))))

    ;; Make streaming request
    (let ((encoded-body (with-output-to-string (s)
                         (yason:encode body s))))
      (handler-case
          (multiple-value-bind (response-stream status-code)
              (dex:post url
                        :headers headers
                        :content encoded-body
                        :want-stream t
                        :read-timeout (getf (provider-options provider) :timeout 120))
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

;; Anthropic doesn't support embeddings yet, use default error
(defmethod send-embedding-request ((provider anthropic-provider) input
                                   &key model dimensions)
  (declare (ignore input model dimensions))
  (error 'provider-api-error
         :provider provider
         :message "Anthropic does not support embeddings API"))

(defmethod parse-embedding-response ((provider anthropic-provider) raw-response
                                     &key performance)
  (declare (ignore raw-response performance))
  (error 'provider-api-error
         :provider provider
         :message "Anthropic does not support embeddings API"))
