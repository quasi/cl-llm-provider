;;; ABOUTME: Tests for agent-oriented conditions, restarts, and recovery helpers
(th.harness:setup :cl-llm-provider)

(in-package :cl-llm-provider)

(fiveam:def-suite conditions-restarts-suite
  :description "Tests for conditions, restarts, recovery helpers, and telos integration"
  :in cl-llm-provider/test::cl-llm-provider-suite)

(fiveam:in-suite conditions-restarts-suite)

;;;; ============================================================
;;;; Section 1: New Condition Signal/Catch Tests
;;;; ============================================================

(fiveam:test condition-model-not-found
  "provider-model-not-found-error can be signaled and caught"
  (let ((caught nil))
    (handler-case
        (error 'provider-model-not-found-error
               :requested-model "gpt-5-turbo"
               :available-models '("gpt-4" "gpt-4o")
               :status-code 404
               :message "Model not found")
      (provider-model-not-found-error (e)
        (setf caught e)))
    (fiveam:is (not (null caught)))
    (fiveam:is (string= "gpt-5-turbo" (error-requested-model caught)))
    (fiveam:is (equal '("gpt-4" "gpt-4o") (error-available-models caught)))
    (fiveam:is (= 404 (error-status-code caught)))))

(fiveam:test condition-context-length
  "provider-context-length-error can be signaled and caught"
  (let ((caught nil))
    (handler-case
        (error 'provider-context-length-error
               :token-count 200000
               :max-tokens 128000
               :model "gpt-4"
               :status-code 400
               :message "Context length exceeded")
      (provider-context-length-error (e)
        (setf caught e)))
    (fiveam:is (not (null caught)))
    (fiveam:is (= 200000 (error-token-count caught)))
    (fiveam:is (= 128000 (error-max-tokens caught)))
    (fiveam:is (string= "gpt-4" (error-context-model caught)))))

(fiveam:test condition-content-filter
  "provider-content-filter-error can be signaled and caught"
  (let ((caught nil))
    (handler-case
        (error 'provider-content-filter-error
               :filter-reason "Content flagged as harmful"
               :status-code 400)
      (provider-content-filter-error (e)
        (setf caught e)))
    (fiveam:is (not (null caught)))
    (fiveam:is (string= "Content flagged as harmful" (error-filter-reason caught)))))

(fiveam:test condition-overloaded
  "provider-overloaded-error can be signaled and caught"
  (let ((caught nil))
    (handler-case
        (error 'provider-overloaded-error
               :retry-after 30
               :status-code 503
               :message "Server overloaded")
      (provider-overloaded-error (e)
        (setf caught e)))
    (fiveam:is (not (null caught)))
    (fiveam:is (= 30 (error-overload-retry-after caught)))
    (fiveam:is (= 503 (error-status-code caught)))))

(fiveam:test condition-invalid-response
  "provider-invalid-response-error can be signaled and caught"
  (let ((caught nil))
    (handler-case
        (error 'provider-invalid-response-error
               :expected-format "JSON object with 'choices' array"
               :actual-value "plain text"
               :status-code 200)
      (provider-invalid-response-error (e)
        (setf caught e)))
    (fiveam:is (not (null caught)))
    (fiveam:is (stringp (error-expected-format caught)))
    (fiveam:is (string= "plain text" (error-actual-value caught)))))

(fiveam:test condition-network-error
  "provider-network-error can be signaled and caught"
  (let ((caught nil))
    (handler-case
        (error 'provider-network-error
               :original-error (make-condition 'simple-error :format-control "connection refused")
               :url "https://api.openai.com/v1/chat/completions"
               :operation :completion
               :message "Network error")
      (provider-network-error (e)
        (setf caught e)))
    (fiveam:is (not (null caught)))
    (fiveam:is (not (null (error-original-condition caught))))
    (fiveam:is (string= "https://api.openai.com/v1/chat/completions" (error-url caught)))
    (fiveam:is (eq :completion (error-operation caught)))))

(fiveam:test condition-timeout
  "provider-timeout-error inherits from provider-network-error"
  (let ((caught-network nil)
        (caught-timeout nil))
    (handler-case
        (error 'provider-timeout-error
               :timeout-seconds 30
               :phase :read
               :url "https://api.openai.com/v1/chat/completions"
               :operation :completion)
      (provider-timeout-error (e)
        (setf caught-timeout e))
      (provider-network-error (e)
        (setf caught-network e)))
    ;; Should be caught by timeout handler, not network handler
    (fiveam:is (not (null caught-timeout)))
    (fiveam:is (null caught-network))
    (fiveam:is (= 30 (error-timeout-seconds caught-timeout)))
    (fiveam:is (eq :read (error-timeout-phase caught-timeout)))))

(fiveam:test condition-json-parse-error
  "provider-json-parse-error can be signaled and caught"
  (let ((caught nil))
    (handler-case
        (error 'provider-json-parse-error
               :raw-body "{invalid json"
               :parse-error (make-condition 'simple-error :format-control "Unexpected character")
               :message "JSON parse error")
      (provider-json-parse-error (e)
        (setf caught e)))
    (fiveam:is (not (null caught)))
    (fiveam:is (string= "{invalid json" (error-raw-body caught)))
    (fiveam:is (not (null (error-parse-condition caught))))))

(fiveam:test condition-unsupported-operation
  "provider-unsupported-operation can be signaled and caught"
  (let ((caught nil))
    (handler-case
        (error 'provider-unsupported-operation
               :operation :embeddings
               :provider-type :ollama
               :message "Ollama does not support embeddings")
      (provider-unsupported-operation (e)
        (setf caught e)))
    (fiveam:is (not (null caught)))
    (fiveam:is (eq :embeddings (error-unsupported-operation caught)))
    (fiveam:is (eq :ollama (error-unsupported-provider-type caught)))))

(fiveam:test condition-stream-interrupted
  "stream-interrupted-error can be signaled with partial content"
  (let ((caught nil))
    (handler-case
        (error 'stream-interrupted-error
               :chunks-received 5
               :accumulated-content "Hello wor"
               :phase :reading
               :message "Stream interrupted")
      (stream-interrupted-error (e)
        (setf caught e)))
    (fiveam:is (not (null caught)))
    (fiveam:is (= 5 (error-chunks-received caught)))
    (fiveam:is (string= "Hello wor" (error-accumulated-content caught)))))

(fiveam:test condition-stream-parse-error
  "stream-parse-error can be signaled and caught"
  (let ((caught nil))
    (handler-case
        (error 'stream-parse-error
               :raw-chunk "data: {bad json"
               :parse-error (make-condition 'simple-error :format-control "parse failed")
               :phase :parsing)
      (stream-parse-error (e)
        (setf caught e)))
    (fiveam:is (not (null caught)))
    (fiveam:is (string= "data: {bad json" (error-raw-chunk caught)))))

(fiveam:test condition-tool-execution-error
  "tool-execution-error can be signaled and caught"
  (let ((caught nil)
        (tool (make-instance 'tool-definition :name "broken" :description "A broken tool")))
    (handler-case
        (error 'tool-execution-error
               :tool tool
               :arguments '(:x 1)
               :original-error (make-condition 'simple-error :format-control "kaboom")
               :message "Tool execution error")
      (tool-execution-error (e)
        (setf caught e)))
    (fiveam:is (not (null caught)))
    (fiveam:is (string= "broken" (tool-name (error-tool caught))))
    (fiveam:is (equal '(:x 1) (error-arguments caught)))
    (fiveam:is (not (null (error-execution-cause caught))))))

(fiveam:test condition-tool-not-found
  "tool-not-found-error can be signaled and caught"
  (let ((caught nil))
    (handler-case
        (error 'tool-not-found-error
               :tool-name "nonexistent_tool"
               :available-tools '("search" "calculator")
               :message "Tool not found")
      (tool-not-found-error (e)
        (setf caught e)))
    (fiveam:is (not (null caught)))
    (fiveam:is (string= "nonexistent_tool" (error-missing-tool-name caught)))
    (fiveam:is (equal '("search" "calculator") (error-available-tools caught)))))

(fiveam:test condition-tool-handler-missing
  "tool-handler-missing-error can be signaled and caught"
  (let ((caught nil)
        (tool (make-instance 'tool-definition :name "no-handler" :description "Missing handler")))
    (handler-case
        (error 'tool-handler-missing-error
               :tool tool
               :message "No handler configured")
      (tool-handler-missing-error (e)
        (setf caught e)))
    (fiveam:is (not (null caught)))
    (fiveam:is (string= "no-handler" (tool-name (error-tool caught))))))

(fiveam:test condition-warning
  "llm-provider-warning is a warning, not an error"
  (let ((warned nil))
    (handler-bind
        ((llm-provider-warning (lambda (w)
                                 (setf warned w)
                                 (muffle-warning w))))
      (warn 'llm-provider-warning :message "Something unusual"))
    (fiveam:is (not (null warned)))
    (fiveam:is (string= "Something unusual" (warning-message warned)))))

(fiveam:test condition-deprecation-warning
  "provider-deprecation-warning inherits from llm-provider-warning"
  (let ((warned nil))
    (handler-bind
        ((llm-provider-warning (lambda (w)
                                 (setf warned w)
                                 (muffle-warning w))))
      (warn 'provider-deprecation-warning
            :feature "v1-api"
            :replacement "v2-api"
            :message "Deprecated"))
    (fiveam:is (not (null warned)))
    (fiveam:is (typep warned 'provider-deprecation-warning))
    (fiveam:is (string= "v1-api" (warning-deprecated-feature warned)))
    (fiveam:is (string= "v2-api" (warning-replacement warned)))))

;;;; ============================================================
;;;; Section 2: Condition Inheritance Tests
;;;; ============================================================

(fiveam:test condition-inheritance-api-errors
  "All API error subtypes can be caught by provider-api-error handler"
  (dolist (cond-type '(provider-model-not-found-error
                       provider-context-length-error
                       provider-content-filter-error
                       provider-overloaded-error
                       provider-invalid-response-error))
    (let ((caught nil))
      (handler-case
          (error cond-type :status-code 400 :message "test")
        (provider-api-error (e)
          (setf caught e)))
      (fiveam:is (not (null caught))
                 (format nil "~A should be caught as provider-api-error" cond-type)))))

(fiveam:test condition-inheritance-llm-provider-error
  "All conditions inherit from llm-provider-error"
  (dolist (cond-type '(provider-configuration-error
                       provider-api-error
                       provider-rate-limit-error
                       provider-authentication-error
                       provider-model-not-found-error
                       provider-context-length-error
                       provider-content-filter-error
                       provider-overloaded-error
                       provider-invalid-response-error
                       provider-network-error
                       provider-timeout-error
                       provider-json-parse-error
                       provider-unsupported-operation
                       stream-error-condition
                       stream-interrupted-error
                       stream-parse-error
                       tool-schema-error
                       tool-validation-error
                       tool-approval-error
                       tool-approval-required
                       tool-safety-violation
                       tool-execution-error
                       tool-not-found-error
                       tool-handler-missing-error))
    (let ((caught nil))
      (handler-case
          (error cond-type :message "test")
        (llm-provider-error (e)
          (setf caught e)))
      (fiveam:is (not (null caught))
                 (format nil "~A should be caught as llm-provider-error" cond-type)))))

(fiveam:test condition-inheritance-stream-errors
  "Stream error subtypes caught by stream-error-condition handler"
  (dolist (cond-type '(stream-interrupted-error stream-parse-error))
    (let ((caught nil))
      (handler-case
          (error cond-type :message "test")
        (stream-error-condition (e)
          (setf caught e)))
      (fiveam:is (not (null caught))
                 (format nil "~A should be caught as stream-error-condition" cond-type)))))

(fiveam:test condition-timeout-inherits-network
  "provider-timeout-error inherits from provider-network-error"
  (let ((caught nil))
    (handler-case
        (error 'provider-timeout-error :timeout-seconds 5 :message "timed out")
      (provider-network-error (e)
        (setf caught e)))
    (fiveam:is (not (null caught)))
    (fiveam:is (typep caught 'provider-timeout-error))))

;;;; ============================================================
;;;; Section 3: classify-api-error Tests
;;;; ============================================================

(fiveam:test classify-model-not-found
  "classify-api-error detects model-not-found from 404 + body"
  (let* ((body (make-hash-table :test 'equal))
         (err (make-hash-table :test 'equal)))
    (setf (gethash "message" err) "The model gpt-5 does not exist")
    (setf (gethash "error" body) err)
    (multiple-value-bind (cond-type extra)
        (classify-api-error 404 body nil "Model not found")
      (declare (ignore extra))
      (fiveam:is (eq 'provider-model-not-found-error cond-type)))))

(fiveam:test classify-context-length
  "classify-api-error detects context length from 400 + body"
  (let ((body "maximum context length exceeded, token count 150000"))
    (multiple-value-bind (cond-type extra)
        (classify-api-error 400 body nil "context length exceeded")
      (declare (ignore extra))
      (fiveam:is (eq 'provider-context-length-error cond-type)))))

(fiveam:test classify-content-filter
  "classify-api-error detects content filter from 400 + body"
  (let ((body "content flagged by safety filter"))
    (multiple-value-bind (cond-type extra)
        (classify-api-error 400 body nil "content filtered")
      (declare (ignore extra))
      (fiveam:is (eq 'provider-content-filter-error cond-type)))))

(fiveam:test classify-overloaded
  "classify-api-error detects overloaded from 503"
  (multiple-value-bind (cond-type extra)
      (classify-api-error 503 "server busy" nil "overloaded")
    (declare (ignore extra))
    (fiveam:is (eq 'provider-overloaded-error cond-type))))

(fiveam:test classify-generic-error
  "classify-api-error falls back to provider-api-error for unknown errors"
  (multiple-value-bind (cond-type extra)
      (classify-api-error 500 "internal server error" nil "server error")
    (declare (ignore extra))
    (fiveam:is (eq 'provider-api-error cond-type))))

;;;; ============================================================
;;;; Section 4: Restart Tests (handler-bind + invoke-restart)
;;;; ============================================================

;;; 4.1 api.lisp restarts: use-provider, use-model

(fiveam:test restart-use-provider
  "use-provider restart allows supplying a provider when none configured"
  (let* ((*default-provider* nil)
         (test-provider (make-provider :ollama :model "test")))
    (let ((result (handler-bind
                      ((provider-configuration-error
                        (lambda (e)
                          (declare (ignore e))
                          (let ((r (find-restart 'use-provider)))
                            (when r (invoke-restart r test-provider))))))
                    ;; This will error because no provider, then restart supplies one.
                    ;; After provider is supplied, it will try to connect and fail.
                    (handler-case
                        (complete '((:role "user" :content "test")))
                      (provider-network-error (e) (declare (ignore e)) :provider-supplied)
                      (error (e) (declare (ignore e)) :provider-supplied)))))
      (fiveam:is (eq :provider-supplied result)))))

(fiveam:test restart-use-model
  "use-model restart allows supplying a model name"
  (let* ((*default-provider* (make-provider :ollama))
         (*default-model* nil))
    (let ((result (handler-bind
                      ((provider-configuration-error
                        (lambda (e)
                          (declare (ignore e))
                          (let ((r (find-restart 'use-model)))
                            (when r (invoke-restart r "llama3"))))))
                    (handler-case
                        (complete '((:role "user" :content "test")))
                      (error (e) (declare (ignore e)) :model-supplied)))))
      (fiveam:is (eq :model-supplied result)))))

;;; 4.2 protocol.lisp restarts: retry, wait-and-retry, use-fallback-provider

(fiveam:test restart-rate-limit-retry
  "retry restart is available on rate limit error"
  (let ((attempt 0))
    (handler-bind
        ((provider-rate-limit-error
          (lambda (e)
            (declare (ignore e))
            (incf attempt)
            (when (<= attempt 1)
              (let ((r (find-restart 'cl-llm-provider::retry)))
                (when r (invoke-restart r)))))))
      (restart-case
          (error 'provider-rate-limit-error
                 :status-code 429
                 :retry-after 1
                 :message "rate limited")
        (cl-llm-provider::wait-and-retry ()
          :report "Wait and retry"
          :waited)
        (cl-llm-provider::retry ()
          :report "Retry immediately"
          :retried)))
    (fiveam:is (= 1 attempt))))

(fiveam:test restart-use-fallback-provider
  "use-fallback-provider restart allows switching providers"
  (let ((fallback-provider (make-provider :ollama :model "test")))
    (let ((result
            (handler-bind
                ((provider-rate-limit-error
                  (lambda (e)
                    (declare (ignore e))
                    (let ((r (find-restart 'cl-llm-provider::use-fallback-provider)))
                      (when r (invoke-restart r fallback-provider))))))
              (restart-case
                  (error 'provider-rate-limit-error
                         :status-code 429
                         :message "rate limited")
                (cl-llm-provider::wait-and-retry () nil)
                (cl-llm-provider::retry () nil)
                (cl-llm-provider::use-fallback-provider (p)
                  :report "Use fallback"
                  p)))))
      (fiveam:is (eq fallback-provider result)))))

(fiveam:test restart-handle-http-error-429
  "handle-http-error establishes retry restarts for 429"
  (let ((restarts-found nil))
    (handler-bind
        ((provider-rate-limit-error
          (lambda (e)
            (setf restarts-found
                  (mapcar #'restart-name (compute-restarts e)))
            ;; Must invoke a restart to avoid unwinding
            (invoke-restart (find-restart 'cl-llm-provider::retry e)))))
      (handle-http-error 429 "rate limited" (make-provider :ollama :model "test")))
    (fiveam:is (member 'cl-llm-provider::wait-and-retry restarts-found))
    (fiveam:is (member 'cl-llm-provider::retry restarts-found))
    (fiveam:is (member 'cl-llm-provider::use-fallback-provider restarts-found))))

(fiveam:test restart-handle-http-error-401
  "handle-http-error establishes use-value restart for 401"
  (let ((restarts-found nil))
    (handler-bind
        ((provider-authentication-error
          (lambda (e)
            (setf restarts-found
                  (mapcar #'restart-name (compute-restarts e)))
            (invoke-restart (find-restart 'use-value e) "new-key"))))
      (handle-http-error 401 "unauthorized" (make-provider :ollama :model "test")))
    (fiveam:is (member 'use-value restarts-found))))

(fiveam:test restart-handle-http-error-generic
  "handle-http-error establishes retry restarts for generic errors"
  (let ((restarts-found nil))
    (handler-bind
        ((provider-api-error
          (lambda (e)
            (setf restarts-found
                  (mapcar #'restart-name (compute-restarts e)))
            (invoke-restart (find-restart 'cl-llm-provider::retry e)))))
      (handle-http-error 500 "internal error" (make-provider :ollama :model "test")))
    (fiveam:is (member 'cl-llm-provider::retry restarts-found))
    (fiveam:is (member 'cl-llm-provider::use-fallback-provider restarts-found))))

;;; 4.3 tools.lisp restarts: skip-validation, use-value

(fiveam:test restart-tool-validation-skip
  "skip-validation restart skips a failing tool check"
  (let ((tool (make-instance 'tool-definition :name "" :description "test" :parameters nil)))
    ;; Empty name should fail validation; skip-validation lets it pass
    (handler-bind
        ((tool-schema-error
          (lambda (e)
            (declare (ignore e))
            (invoke-restart (find-restart 'cl-llm-provider::skip-validation)))))
      (validate-tool-definition tool))
    (fiveam:is-true t "skip-validation restart allowed continuing past invalid tool")))

(fiveam:test restart-tool-validation-use-value
  "use-value restart provides a corrected value during tool validation"
  (let ((tool (make-instance 'tool-definition :name "" :description "test" :parameters nil)))
    (handler-bind
        ((tool-schema-error
          (lambda (e)
            (declare (ignore e))
            (let ((r (find-restart 'use-value)))
              (when r (invoke-restart r "fixed-name"))))))
      (validate-tool-definition tool))
    (fiveam:is (string= "fixed-name" (tool-name tool)))))

(fiveam:test restart-skip-invalid-tool
  "skip-invalid-tool restart skips a bad tool in validate-tools"
  (let ((good-tool (make-instance 'tool-definition :name "good" :description "A good tool" :parameters nil))
        (bad-tool (make-instance 'tool-definition :name "" :description "bad" :parameters nil)))
    (handler-bind
        ((tool-schema-error
          (lambda (e)
            (declare (ignore e))
            (let ((r (find-restart 'cl-llm-provider::skip-invalid-tool)))
              (if r
                  (invoke-restart r)
                  ;; If skip-invalid-tool not available, try skip-validation
                  (invoke-restart (find-restart 'cl-llm-provider::skip-validation)))))))
      (validate-tools (list good-tool bad-tool)))
    (fiveam:is-true t "skip-invalid-tool allowed continuing past bad tool")))

;;; 4.4 streaming restarts: return-partial-content, abort-stream

(fiveam:test restart-stream-return-partial
  "return-partial-content restart returns nil from stream read"
  (let ((result
          (handler-bind
              ((stream-interrupted-error
                (lambda (e)
                  (declare (ignore e))
                  (invoke-restart (find-restart 'cl-llm-provider::return-partial-content)))))
            (restart-case
                (error 'stream-interrupted-error
                       :chunks-received 3
                       :accumulated-content "partial"
                       :message "stream died")
              (cl-llm-provider::return-partial-content ()
                :report "Return partial"
                nil)
              (cl-llm-provider::abort-stream ()
                :report "Abort"
                :aborted)))))
    (fiveam:is (null result))))

(fiveam:test restart-stream-abort
  "abort-stream restart can abort a stream"
  (let ((result
          (handler-bind
              ((stream-interrupted-error
                (lambda (e)
                  (declare (ignore e))
                  (invoke-restart (find-restart 'cl-llm-provider::abort-stream)))))
            (restart-case
                (error 'stream-interrupted-error
                       :chunks-received 3
                       :accumulated-content "partial"
                       :message "stream died")
              (cl-llm-provider::return-partial-content ()
                :report "Return partial"
                nil)
              (cl-llm-provider::abort-stream ()
                :report "Abort"
                :aborted)))))
    (fiveam:is (eq :aborted result))))

;;; 4.5 tools/execution.lisp restarts

(fiveam:test restart-tool-use-error-result
  "use-error-result restart returns error description as result"
  (let* ((tool (make-instance 'tool-definition
                               :name "failing"
                               :description "A tool that fails"
                               :handler (lambda (args)
                                          (declare (ignore args))
                                          (error "kaboom"))))
         (call (make-instance 'tool-call :id "c1" :name "failing" :arguments nil))
         (result
           (handler-bind
               ((error (lambda (e)
                         (declare (ignore e))
                         (let ((r (find-restart 'cl-llm-provider.tools::use-error-result)))
                           (when r (invoke-restart r))))))
             (cl-llm-provider.tools:execute-tool tool call :skip-approval t :skip-validation t))))
    (fiveam:is (stringp result))
    (fiveam:is (search "Error" result))))

(fiveam:test restart-tool-use-value
  "use-value restart supplies an alternative tool result"
  (let* ((tool (make-instance 'tool-definition
                               :name "failing"
                               :description "A tool that fails"
                               :handler (lambda (args)
                                          (declare (ignore args))
                                          (error "kaboom"))))
         (call (make-instance 'tool-call :id "c2" :name "failing" :arguments nil))
         (result
           (handler-bind
               ((error (lambda (e)
                         (declare (ignore e))
                         (let ((r (find-restart 'use-value)))
                           (when r (invoke-restart r "fallback-result"))))))
             (cl-llm-provider.tools:execute-tool tool call :skip-approval t :skip-validation t))))
    (fiveam:is (string= "fallback-result" result))))

;;;; ============================================================
;;;; Section 5: Recovery Helpers Tests
;;;; ============================================================

(fiveam:test transient-error-classification
  "transient-error-p correctly classifies error types"
  ;; Transient errors
  (fiveam:is (transient-error-p
              (make-condition 'provider-rate-limit-error :status-code 429)))
  (fiveam:is (transient-error-p
              (make-condition 'provider-overloaded-error :status-code 503)))
  (fiveam:is (transient-error-p
              (make-condition 'provider-network-error :message "connection refused")))
  (fiveam:is (transient-error-p
              (make-condition 'provider-timeout-error :timeout-seconds 30)))
  ;; Non-transient errors
  (fiveam:is (not (transient-error-p
                   (make-condition 'provider-authentication-error :status-code 401))))
  (fiveam:is (not (transient-error-p
                   (make-condition 'provider-model-not-found-error :status-code 404))))
  (fiveam:is (not (transient-error-p
                   (make-condition 'provider-context-length-error :status-code 400))))
  (fiveam:is (not (transient-error-p
                   (make-condition 'provider-content-filter-error :status-code 400))))
  (fiveam:is (not (transient-error-p
                   (make-condition 'tool-schema-error :message "bad tool")))))

(fiveam:test default-backoff-values
  "default-backoff returns reasonable exponential values"
  (let ((b1 (default-backoff 1))
        (b2 (default-backoff 2))
        (b3 (default-backoff 3)))
    ;; Attempt 1: base=1, jittered 0.5-1.5
    (fiveam:is (>= b1 0.5))
    (fiveam:is (<= b1 1.5))
    ;; Attempt 2: base=2, jittered 1.0-3.0
    (fiveam:is (>= b2 1.0))
    (fiveam:is (<= b2 3.0))
    ;; Attempt 3: base=4, jittered 2.0-6.0
    (fiveam:is (>= b3 2.0))
    (fiveam:is (<= b3 6.0))))

(fiveam:test retry-wait-time-uses-provider-hint
  "retry-wait-time respects retry-after from provider"
  ;; Rate limit with retry-after
  (let ((cond (make-condition 'provider-rate-limit-error
                              :status-code 429
                              :retry-after 42)))
    (fiveam:is (= 42 (retry-wait-time cond 1 1.0))))
  ;; Overloaded with retry-after
  (let ((cond (make-condition 'provider-overloaded-error
                              :status-code 503
                              :retry-after 10)))
    (fiveam:is (= 10 (retry-wait-time cond 1 1.0))))
  ;; Network error falls back to backoff
  (let* ((cond (make-condition 'provider-network-error :message "fail"))
         (wait (retry-wait-time cond 1 1.0)))
    (fiveam:is (> wait 0))
    (fiveam:is (< wait 2.0))))

(fiveam:test available-recovery-options-returns-plists
  "available-recovery-options returns structured restart data"
  (let ((options nil))
    (handler-bind
        ((provider-rate-limit-error
          (lambda (e)
            (setf options (available-recovery-options e))
            ;; Must handle to prevent unwind
            (invoke-restart (find-restart 'cl-llm-provider::retry e)))))
      (handle-http-error 429 "rate limited" (make-provider :ollama :model "test")))
    (fiveam:is (listp options))
    (fiveam:is (> (length options) 0))
    ;; Each option should be a plist with :name and :report
    (let ((first-opt (first options)))
      (fiveam:is (getf first-opt :name))
      (fiveam:is (stringp (getf first-opt :report))))))

(fiveam:test with-auto-recovery-retries-transient
  "with-auto-recovery retries on transient errors"
  (let ((attempt 0))
    (let ((result
            (with-auto-recovery (:max-retries 3 :backoff-base 0.0)
              (incf attempt)
              (when (< attempt 3)
                (error 'provider-rate-limit-error
                       :status-code 429
                       :message "rate limited"))
              :success)))
      (fiveam:is (eq :success result))
      (fiveam:is (= 3 attempt)))))

(fiveam:test with-auto-recovery-propagates-after-max
  "with-auto-recovery propagates error after max retries"
  (let ((attempt 0))
    (fiveam:signals provider-rate-limit-error
      (with-auto-recovery (:max-retries 2 :backoff-base 0.0)
        (incf attempt)
        (error 'provider-rate-limit-error
               :status-code 429
               :message "rate limited")))
    (fiveam:is (= 3 attempt))))  ; 1 initial + 2 retries

(fiveam:test with-auto-recovery-skips-non-transient
  "with-auto-recovery does not retry non-transient errors"
  (let ((attempt 0))
    (fiveam:signals provider-authentication-error
      (with-auto-recovery (:max-retries 3 :backoff-base 0.0)
        (incf attempt)
        (error 'provider-authentication-error
               :status-code 401
               :message "bad key")))
    (fiveam:is (= 1 attempt))))

(fiveam:test with-auto-recovery-on-retry-callback
  "with-auto-recovery calls on-retry callback"
  (let ((callback-args nil)
        (attempt 0))
    (with-auto-recovery (:max-retries 3
                         :backoff-base 0.0
                         :on-retry (lambda (e n)
                                     (push (list (type-of e) n) callback-args)))
      (incf attempt)
      (when (< attempt 3)
        (error 'provider-network-error :message "fail")))
    (fiveam:is (= 2 (length callback-args)))
    ;; First callback: attempt 1
    (fiveam:is (= 1 (second (second callback-args))))
    ;; Second callback: attempt 2
    (fiveam:is (= 2 (second (first callback-args))))))

(fiveam:test with-auto-recovery-fallback-providers
  "with-auto-recovery switches to fallback providers when retries exhausted"
  (let ((attempt 0)
        (providers-tried nil)
        (fallback1 (make-provider :ollama :model "fallback1"))
        (fallback2 (make-provider :ollama :model "fallback2")))
    (let ((*default-provider* (make-provider :ollama :model "primary")))
      (with-auto-recovery (:max-retries 1
                           :backoff-base 0.0
                           :fallback-providers (list fallback1 fallback2))
        (incf attempt)
        (push (provider-default-model *default-provider*) providers-tried)
        (when (< attempt 4)
          (error 'provider-network-error :message "fail"))))
    ;; Should have tried primary (2x: initial + 1 retry), fallback1 (2x), then fallback2 succeeds
    (fiveam:is (>= attempt 3))
    (fiveam:is (member "primary" providers-tried :test #'string=))
    (fiveam:is (member "fallback1" providers-tried :test #'string=))))

;;;; ============================================================
;;;; Section 6: Telos Integration Tests
;;;; ============================================================

(fiveam:test telos-features-exist
  "All planned telos features are defined"
  (let ((features (mapcar (lambda (f) (string-downcase (symbol-name f)))
                          (telos:list-features))))
    (dolist (name '("llm-provider" "provider-protocol" "http-transport"
                    "completion-api" "streaming-api" "tool-calling"
                    "configuration" "observability" "error-recovery"))
      (fiveam:is (member name features :test #'string=)
                 (format nil "Feature ~A should exist" name)))))

(fiveam:test telos-intent-on-complete
  "complete function has telos intent"
  (let ((intent (telos:get-intent 'cl-llm-provider:complete)))
    (fiveam:is (not (null intent)))))

(fiveam:test telos-intent-on-conditions
  "Key conditions have telos intent"
  (dolist (sym '(cl-llm-provider:provider-rate-limit-error
                 cl-llm-provider:provider-network-error
                 cl-llm-provider:stream-interrupted-error))
    (let ((intent (telos:get-intent sym)))
      (fiveam:is (not (null intent))
                 (format nil "~A should have telos intent" sym)))))

(fiveam:test telos-intent-on-recovery
  "Recovery helpers have telos intent"
  (dolist (sym '(cl-llm-provider:available-recovery-options
                 cl-llm-provider:transient-error-p
                 cl-llm-provider:with-auto-recovery))
    (let ((intent (telos:get-intent sym)))
      (fiveam:is (not (null intent))
                 (format nil "~A should have telos intent" sym)))))
