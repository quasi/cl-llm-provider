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
  "Translate to Anthropic tool format."
  (let ((result (make-hash-table :test 'equal))
        (input-schema (make-hash-table :test 'equal)))

    (setf (gethash "name" result) (tool-name tool))
    (setf (gethash "description" result) (tool-description tool))

    ;; Build input schema
    (setf (gethash "type" input-schema) "object")
    (setf (gethash "properties" input-schema) (make-hash-table :test 'equal))

    ;; Convert parameters
    (dolist (param (tool-parameters tool))
      (let* ((param-name (getf param :name))
             (param-type (getf param :type))
             (param-desc (getf param :description))
             (param-enum (getf param :enum))
             (param-spec (make-hash-table :test 'equal)))

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

        (setf (gethash param-name (gethash "properties" input-schema))
              param-spec)))

    ;; Set required parameters
    (when (tool-required-params tool)
      (setf (gethash "required" input-schema) (tool-required-params tool)))

    (setf (gethash "input_schema" result) input-schema)
    result))

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
              (map 'vector #'plist-to-hash messages))

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

(defmethod parse-completion-response ((provider anthropic-provider) raw-response
                                      &key performance)
  (let* ((content-blocks (gethash "content" raw-response))
         (first-block (when (and content-blocks (> (length content-blocks) 0))
                       (elt content-blocks 0)))
         (content-type (gethash "type" first-block))
         (text-content (when (string= content-type "text")
                        (gethash "text" first-block)))
         (finish-reason (gethash "stop_reason" raw-response))
         (usage (gethash "usage" raw-response))
         (tool-calls nil))

    ;; Parse tool uses from content blocks
    (loop for block in (coerce content-blocks 'list)
          for block-type = (gethash "type" block)
          when (string= block-type "tool_use")
          collect (make-instance 'tool-call
                                 :id (gethash "id" block)
                                 :name (gethash "name" block)
                                 :arguments (gethash "input" block))
          into calls
          finally (setf tool-calls calls))

    ;; Build message for conversation continuation
    (let ((message (list :role "assistant")))
      (if tool-calls
          (setf (getf message :tool-calls) tool-calls)
          (setf (getf message :content) text-content)))

    (make-instance 'completion-response
                   :id (gethash "id" raw-response)
                   :model (gethash "model" raw-response)
                   :content text-content
                   :message message
                   :tool-calls tool-calls
                   :finish-reason (intern (string-upcase finish-reason) :keyword)
                   :usage (list :prompt-tokens (gethash "input_tokens" usage)
                                :completion-tokens (gethash "output_tokens" usage)
                                :total-tokens (+ (gethash "input_tokens" usage)
                                                (gethash "output_tokens" usage)))
                   :raw raw-response
                   :performance performance
                   :metadata (let ((metadata nil))
                              ;; Provider introspection
                              (setf (getf metadata :provider-type) (provider-type provider))
                              (setf (getf metadata :provider-name) (provider-name provider))
                              ;; Extract stop sequence if present
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
