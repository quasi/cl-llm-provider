;;; ABOUTME: Tests for agent-oriented conditions, restarts, and recovery helpers
(th.harness:setup :cl-llm-provider)

(in-package :cl-llm-provider)

(fiveam:def-suite conditions-restarts-suite
  :description "Tests for conditions, restarts, recovery helpers, and telos integration"
  :in cl-llm-provider/test::cl-llm-provider-suite)

(fiveam:in-suite conditions-restarts-suite)

(defclass failing-test-provider (openai-provider) ())
(defclass working-test-provider (openai-provider) ())

(defvar *fallback-test-calls* nil)

(defmethod send-completion-request ((p failing-test-provider) messages
                                    &key &allow-other-keys)
  (declare (ignore messages))
  (push :failing *fallback-test-calls*)
  (error 'provider-api-error :provider p :message "down"))

(defmethod send-completion-request ((p working-test-provider) messages
                                    &key &allow-other-keys)
  (declare (ignore messages))
  (push :working *fallback-test-calls*)
  (yason:parse "{\"id\":\"r1\",\"model\":\"m\",\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"role\":\"assistant\",\"content\":\"ok\"}}]}"))

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
    (fiveam:is (= 30 (error-retry-after caught)))
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
                       llm-stream-error
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
  "Stream error subtypes caught by llm-stream-error handler"
  (dolist (cond-type '(stream-interrupted-error stream-parse-error))
    (let ((caught nil))
      (handler-case
          (error cond-type :message "test")
        (llm-stream-error (e)
          (setf caught e)))
      (fiveam:is (not (null caught))
                 (format nil "~A should be caught as llm-stream-error" cond-type)))))

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
  (let* ((provider (make-provider :ollama :model "test"))
         (body (make-hash-table :test 'equal))
         (err (make-hash-table :test 'equal)))
    (setf (gethash "message" err) "The model gpt-5 does not exist")
    (setf (gethash "error" body) err)
    (multiple-value-bind (cond-type extra)
        (classify-api-error provider 404 body "Model not found")
      (declare (ignore extra))
      (fiveam:is (eq 'provider-model-not-found-error cond-type)))))

(fiveam:test classify-context-length
  "classify-api-error detects context length from 400 + body"
  (let ((provider (make-provider :ollama :model "test"))
        (body "maximum context length exceeded, token count 150000"))
    (multiple-value-bind (cond-type extra)
        (classify-api-error provider 400 body "context length exceeded")
      (declare (ignore extra))
      (fiveam:is (eq 'provider-context-length-error cond-type)))))

(fiveam:test classify-content-filter
  "classify-api-error detects content filter from 400 + body"
  (let ((provider (make-provider :ollama :model "test"))
        (body "content flagged by safety filter"))
    (multiple-value-bind (cond-type extra)
        (classify-api-error provider 400 body "content filtered")
      (declare (ignore extra))
      (fiveam:is (eq 'provider-content-filter-error cond-type)))))

(fiveam:test classify-overloaded
  "classify-api-error detects overloaded from 503"
  (let ((provider (make-provider :ollama :model "test")))
    (multiple-value-bind (cond-type extra)
        (classify-api-error provider 503 "server busy" "overloaded")
      (declare (ignore extra))
      (fiveam:is (eq 'provider-overloaded-error cond-type)))))

(fiveam:test classify-generic-error
  "classify-api-error falls back to provider-api-error for unknown errors"
  (let ((provider (make-provider :ollama :model "test")))
    (multiple-value-bind (cond-type extra)
        (classify-api-error provider 500 "internal server error" "server error")
      (declare (ignore extra))
      (fiveam:is (eq 'provider-api-error cond-type)))))

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

(fiveam:test use-provider-restart-accepts-keyword
  "use-provider can supply a keyword provider designator without eval."
  (let ((*default-provider* nil))
    (handler-bind
        ((provider-configuration-error
          (lambda (e)
            (declare (ignore e))
            (invoke-restart 'use-provider :ollama))))
      (let ((provider (%resolve-provider nil)))
        (fiveam:is (typep provider 'ollama-provider))))))

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
              (let ((r (find-restart 'retry)))
                (when r (invoke-restart r)))))))
      (restart-case
          (error 'provider-rate-limit-error
                 :status-code 429
                 :retry-after 1
                 :message "rate limited")
        (wait-and-retry ()
          :report "Wait and retry"
          :waited)
        (retry ()
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
                    (let ((r (find-restart 'use-fallback-provider)))
                      (when r (invoke-restart r fallback-provider))))))
              (restart-case
                  (error 'provider-rate-limit-error
                         :status-code 429
                         :message "rate limited")
                (wait-and-retry () nil)
                (retry () nil)
                (use-fallback-provider (p)
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
            (invoke-restart (find-restart 'retry e)))))
    (handle-http-error 429 "rate limited" (make-provider :ollama :model "test")))
    (fiveam:is (member 'wait-and-retry restarts-found))
    (fiveam:is (member 'retry restarts-found))
    ;; use-fallback-provider now lives at the COMPLETE/EMBEDDING/COMPLETE-STREAM
    ;; level, where the whole request can actually be re-issued.
    ))

(fiveam:test handle-http-error-retry-returns-directive
  "Invoking retry from handle-http-error returns the provider-http-post directive."
  (let ((provider (make-instance 'openai-provider)))
    (handler-bind
        ((provider-rate-limit-error
          (lambda (e)
            (declare (ignore e))
            (invoke-restart 'retry))))
      (fiveam:is (eq :retry
                     (handle-http-error 429 "slow down" provider))))))

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
            (invoke-restart (find-restart 'retry e)))))
    (handle-http-error 500 "internal error" (make-provider :ollama :model "test")))
    (fiveam:is (member 'retry restarts-found))
    ;; use-fallback-provider now lives at the COMPLETE/EMBEDDING/COMPLETE-STREAM
    ;; level, where the whole request can actually be re-issued.
    ))

(fiveam:test handle-http-error-generic-retry-returns-directive
  "Generic API retry restarts also return the retry directive."
  (let ((provider (make-instance 'openai-provider)))
    (handler-bind
        ((provider-api-error
          (lambda (e)
            (declare (ignore e))
            (invoke-restart 'retry))))
      (fiveam:is (eq :retry
                     (handle-http-error 500 "boom" provider))))))

(fiveam:test parse-retry-after-normalizes-strings
  "retry-after hints are normalized before reaching sleep."
  (let ((body (make-hash-table :test 'equal)))
    (setf (gethash "retry_after" body) "30")
    (fiveam:is (= 30 (parse-retry-after body)))
    (setf (gethash "retry_after" body) 15)
    (fiveam:is (= 15 (parse-retry-after body)))
    (setf (gethash "retry_after" body) '(:junk))
    (fiveam:is (null (parse-retry-after body)))))

(fiveam:test use-fallback-provider-reissues-request
  "use-fallback-provider re-issues COMPLETE against the supplied provider."
  (setf *fallback-test-calls* nil)
  (let ((failing (make-instance 'failing-test-provider :model "m"))
        (working (make-instance 'working-test-provider :model "m")))
    (handler-bind
        ((provider-api-error
          (lambda (e)
            (declare (ignore e))
            (invoke-restart 'use-fallback-provider working))))
      (let ((response (complete '((:role "user" :content "hi"))
                                :provider failing
                                :model "m")))
        (fiveam:is (string= "ok" (response-content response)))
        (fiveam:is (equal '(:working :failing) *fallback-test-calls*))))))

;;; 4.3 tools.lisp restarts: skip-validation, use-value

(fiveam:test restart-tool-validation-skip
  "skip-validation restart skips a failing tool check"
  (let ((tool (make-instance 'tool-definition :name "" :description "test" :parameters nil)))
    ;; Empty name should fail validation; skip-validation lets it pass
    (handler-bind
        ((tool-schema-error
          (lambda (e)
            (declare (ignore e))
            (invoke-restart (find-restart 'skip-validation)))))
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
            (let ((r (find-restart 'skip-invalid-tool)))
              (if r
                  (invoke-restart r)
                  ;; If skip-invalid-tool not available, try skip-validation
                  (invoke-restart (find-restart 'skip-validation)))))))
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
                  (invoke-restart (find-restart 'return-partial-content)))))
            (restart-case
                (error 'stream-interrupted-error
                       :chunks-received 3
                       :accumulated-content "partial"
                       :message "stream died")
              (return-partial-content ()
                :report "Return partial"
                nil)
              (abort-stream ()
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
                  (invoke-restart (find-restart 'abort-stream)))))
            (restart-case
                (error 'stream-interrupted-error
                       :chunks-received 3
                       :accumulated-content "partial"
                       :message "stream died")
              (return-partial-content ()
                :report "Return partial"
                nil)
              (abort-stream ()
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

(fiveam:test make-retry-handler-invokes-retry-without-restart-sleep
  "make-retry-handler prefers the retry restart after doing its own wait."
  (let ((handler (make-retry-handler
                  :max-retries 1
                  :backoff-fn (lambda (attempt)
                                (declare (ignore attempt))
                                0)))
        (invoked nil))
    (restart-case
        (progn
          (funcall handler
                   (make-condition 'provider-network-error :message "test"))
          nil)
      (retry ()
        (setf invoked t)))
    (fiveam:is (eq t invoked))))

(fiveam:test available-recovery-options-returns-plists
  "available-recovery-options returns structured restart data"
  (let ((options nil))
    (handler-bind
        ((provider-rate-limit-error
          (lambda (e)
            (setf options (available-recovery-options e))
            ;; Must handle to prevent unwind
            (invoke-restart (find-restart 'retry e)))))
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

(fiveam:test with-auto-recovery-does-not-capture-block-names
  "with-auto-recovery uses hygienic block/tag names."
  (fiveam:is (eq :escaped
                 (block auto-recovery
                   (with-auto-recovery ()
                     (return-from auto-recovery :escaped))
                   :not-escaped))))

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

(fiveam:test api-error-report-names-gemini
  "provider-api-error reports use provider-name, including Gemini."
  (let ((condition (make-condition 'provider-api-error
                                   :provider (make-instance 'gemini-provider)
                                   :status-code 500
                                   :message "boom")))
    (fiveam:is (search "Google Gemini" (princ-to-string condition)))))

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

(fiveam:test tool-calling-feature-symbol-is-shared
  "Tool declarations in both packages refer to the defined feature symbol."
  (multiple-value-bind (tools-symbol status)
      (find-symbol "TOOL-CALLING" :cl-llm-provider.tools)
    (fiveam:is (eq status :inherited))
    (fiveam:is (eq tools-symbol 'cl-llm-provider:tool-calling))
    (fiveam:is (member tools-symbol (telos:list-features) :test #'eq))))

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

;;;; ============================================================
;;;; Section 5: Cross-provider failover — the model has to travel too
;;;;
;;;; WRITTEN BEFORE THE FIX (2026-08-04). Measured first, in the image, against
;;;; a live local endpoint and a dead one:
;;;;
;;;;   handler ran            T
;;;;   use-fallback-provider  found
;;;;   restart invoked        -> "Model not found: NIL"
;;;;
;;;; USE-FALLBACK-PROVIDER SWITCHES THE PROVIDER AND KEEPS THE MODEL. Its body
;;;; re-resolves (%resolve-model model prov) where MODEL is the caller's ORIGINAL
;;;; argument, and %resolve-model is (or model ...) — so an explicit model always
;;;; wins and travels to a provider that has never heard of it. Every real
;;;; local->cloud failover is exactly that case: "gemma-4-26B-A4B-it-QAT-MLX-4bit"
;;;; means nothing to OpenRouter.
;;;;
;;;; WHY THE EXISTING TEST DID NOT CATCH IT. use-fallback-provider-reissues-request
;;;; builds both providers with :model "m" and passes :model "m". One value in
;;;; three places cannot show that the value travelled — the same blind spot as a
;;;; tier table tested with one tier. The fixtures below use DIFFERENT model names
;;;; per provider and RECORD what each was handed, which is the only way the
;;;; question can be asked at all.
;;;; ============================================================

(defclass model-recording-provider (openai-provider) ())

(defvar *models-seen* nil
  "Every model string a recording provider was handed, newest first.")

(defmethod send-completion-request ((p model-recording-provider) messages
                                    &key model &allow-other-keys)
  (declare (ignore messages))
  (push (list (provider-default-model p) model) *models-seen*)
  ;; A provider that refuses anything but its OWN model, the way a real endpoint
  ;; does. Returning success regardless would let a test assert on *models-seen*
  ;; and still not prove the request could have been served.
  (unless (equal model (provider-default-model p))
    (error 'provider-model-not-found-error
           :provider p
           :requested-model model
           :status-code 404
           :message "Model not found"))
  (yason:parse "{\"id\":\"r1\",\"model\":\"m\",\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"role\":\"assistant\",\"content\":\"ok\"}}]}"))

(defclass unreachable-test-provider (openai-provider) ())

(defmethod send-completion-request ((p unreachable-test-provider) messages
                                    &key &allow-other-keys)
  (declare (ignore messages))
  (error 'provider-network-error :provider p :url "http://nowhere/v1"
                                 :operation :completion))

(fiveam:test use-fallback-provider-can-carry-the-fallbacks-own-model
  "THE CROSS-PROVIDER FAILOVER. Switching provider must be able to switch model.

DISCRIMINATING: the two providers answer to DIFFERENT model names and the
fallback REFUSES anything but its own, so a restart that carries the original
model over cannot pass by accident — it fails with the very
provider-model-not-found-error this test exists to prevent. Asserting only that
a response came back would pass against a fixture that ignored :model, which is
why the fallback checks."
  (setf *models-seen* nil)
  (let ((local (make-instance 'unreachable-test-provider :model "local-only-model"))
        (cloud (make-instance 'model-recording-provider  :model "cloud-only-model")))
    (let ((response
            (handler-bind
                ((provider-network-error
                   (lambda (c)
                     (let ((r (find-restart 'cl-llm-provider:use-fallback-provider c)))
                       (when r (invoke-restart r cloud "cloud-only-model"))))))
              (complete '((:role "user" :content "hi"))
                        :provider local
                        ;; the shape ghost's own call site uses: an EXPLICIT model,
                        ;; named for the provider we were hoping to reach
                        :model "local-only-model"))))
      (fiveam:is (string= "ok" (response-content response))
                 "the fallback served the request")
      (fiveam:is (equal '("cloud-only-model" "cloud-only-model") (first *models-seen*))
                 "and it was asked for ITS OWN model, not the dead endpoint's"))))

(defclass permissive-recording-provider (openai-provider) ())

(defmethod send-completion-request ((p permissive-recording-provider) messages
                                    &key model &allow-other-keys)
  (declare (ignore messages))
  (push (list (provider-default-model p) model) *models-seen*)
  (yason:parse "{\"id\":\"r1\",\"model\":\"m\",\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"role\":\"assistant\",\"content\":\"ok\"}}]}"))

(fiveam:test use-fallback-provider-without-a-model-is-unchanged
  "THE CONTROL, and without it the test above is a licence to change semantics.

A one-argument use-fallback-provider must behave exactly as it did before: keep
the caller's model and re-resolve it against the new provider. Callers switching
between two endpoints serving the SAME model depend on that, and a fix that
quietly flipped the precedence to prefer the new provider's own default would
break them with no test failing anywhere.

THE TWO NAMES MUST DIFFER, and the first draft of this control got that wrong: it
gave the caller and the fallback provider the SAME model string, so 'kept the
caller's model' and 'used the fallback's default' were the same green — the exact
blind spot that let use-fallback-provider-reissues-request pass for years over a
restart that cannot cross a model boundary. Here the fallback's own default is
deliberately a different string, and the assertion is that it was NOT used.

The fixture is permissive rather than refusing: a refusing one would fail the
request instead of recording what it was handed, and the recording IS the
measurement."
  (setf *models-seen* nil)
  (let ((local (make-instance 'unreachable-test-provider :model "the-callers-model"))
        (mirror (make-instance 'permissive-recording-provider
                               :model "the-fallbacks-own-default")))
    (let ((response
            (handler-bind
                ((provider-network-error
                   (lambda (c)
                     (let ((r (find-restart 'cl-llm-provider:use-fallback-provider c)))
                       (when r (invoke-restart r mirror))))))
              (complete '((:role "user" :content "hi"))
                        :provider local :model "the-callers-model"))))
      (fiveam:is (string= "ok" (response-content response)))
      (fiveam:is (equal "the-callers-model" (second (first *models-seen*)))
                 "the caller's model survived a no-model fallback, as it always has")
      (fiveam:is (not (equal "the-fallbacks-own-default" (second (first *models-seen*))))
                 "and the fallback's own default did NOT quietly displace it"))))

(fiveam:test use-model-re-issues-against-the-same-provider
  "'That model is not here, try this one' is a choice, so it is a restart.

R-CS-002: provider-model-not-found-error offered retry and use-fallback-provider
and nothing that could actually fix a model name — the one thing wrong. Switching
provider to solve a model typo is a sledgehammer, and retrying unchanged repeats
the same 404.

DISCRIMINATING: asserts the SECOND attempt carried the corrected name. A test that
only asserted a response came back would pass for an implementation that ignored
the argument and got lucky on a permissive fixture."
  (setf *models-seen* nil)
  (let ((p (make-instance 'model-recording-provider :model "the-real-model")))
    (let ((response
            (handler-bind
                ((provider-model-not-found-error
                   (lambda (c)
                     (let ((r (find-restart 'cl-llm-provider:use-model c)))
                       (when r (invoke-restart r "the-real-model"))))))
              (complete '((:role "user" :content "hi"))
                        :provider p :model "a-model-with-a-typo"))))
      (fiveam:is (string= "ok" (response-content response)))
      (fiveam:is (= 2 (length *models-seen*))
                 "two attempts — the typo, then the correction")
      (fiveam:is (equal "a-model-with-a-typo" (second (second *models-seen*)))
                 "the first attempt carried the typo")
      (fiveam:is (equal "the-real-model" (second (first *models-seen*)))
                 "and the second carried what the handler supplied"))))

(fiveam:test a-model-not-found-error-names-the-model-it-could-not-find
  "Measured 2026-08-04 against a live MLX server: 'Model not found: NIL'.

classify-api-error reads :requested-model out of a nested (error.model) field
almost no server sends, and handle-http-error is never told which model the
caller asked for — so the report names nothing. An operator is told that
something was not found and not what, which is the least useful true sentence
available, and it cost this session one wrong diagnosis before the fix.

DISCRIMINATING: asserts the model NAME appears in the printed report, not merely
that the slot is set. The report is what an operator reads off a spool file."
  (let ((caught nil))
    (handler-case
        (handle-http-error 404
                           (let ((h (make-hash-table :test #'equal)))
                             (setf (gethash "error" h) "model not found")
                             h)
                           (make-instance 'openai-provider :model "d" :api-key "k")
                           :requested-model "gemma-4-26B-A4B-it-QAT-MLX-4bit")
      (provider-model-not-found-error (c) (setf caught c)))
    (fiveam:is (not (null caught)) "the 404 classified as model-not-found")
    (when caught
      (fiveam:is (equal "gemma-4-26B-A4B-it-QAT-MLX-4bit"
                        (error-requested-model caught))
                 "the requested model reached the condition")
      (fiveam:is (search "gemma-4-26B-A4B-it-QAT-MLX-4bit" (princ-to-string caught))
                 "and it is in the SENTENCE, which is what an operator reads"))))

(fiveam:test the-bodys-own-model-name-outranks-the-callers
  "THE CONTROL for the fix above. When the server DOES name the model it refused,
that name wins — it is the authority on what it rejected, and a caller-supplied
value overwriting it would replace a fact with an assumption.

Without this, 'fill in the model' and 'always use the caller's model' are the
same green."
  (let ((caught nil))
    (handler-case
        (handle-http-error 404
                           (let ((h (make-hash-table :test #'equal))
                                 (e (make-hash-table :test #'equal)))
                             (setf (gethash "message" e) "model not found"
                                   (gethash "model" e) "what-the-server-says"
                                   (gethash "error" h) e)
                             h)
                           (make-instance 'openai-provider :model "d" :api-key "k")
                           :requested-model "what-the-caller-says")
      (provider-model-not-found-error (c) (setf caught c)))
    (fiveam:is (not (null caught)))
    (when caught
      (fiveam:is (equal "what-the-server-says" (error-requested-model caught))
                 "the server's own name for what it refused was not overwritten"))))

;;;; ------------------------------------------------------------
;;;; One restart name, one contract, across all three entry points
;;;; ------------------------------------------------------------

(defclass recording-embedding-provider (openai-provider) ())

(defmethod send-embedding-request ((p recording-embedding-provider) input
                                   &key model &allow-other-keys)
  (declare (ignore input))
  (push (list (provider-default-model p) model) *models-seen*)
  (yason:parse "{\"data\":[{\"embedding\":[0.1,0.2],\"index\":0}],\"model\":\"m\",\"usage\":{\"prompt_tokens\":1,\"total_tokens\":1}}"))

(defclass unreachable-embedding-provider (openai-provider) ())

(defmethod send-embedding-request ((p unreachable-embedding-provider) input
                                   &key &allow-other-keys)
  (declare (ignore input))
  (error 'provider-network-error :provider p :url "http://nowhere/v1"
                                 :operation :embedding))

(defclass recording-stream-provider (openai-provider) ())

(defmethod send-streaming-request ((p recording-stream-provider) messages
                                   &key model &allow-other-keys)
  (declare (ignore messages))
  (push (list (provider-default-model p) model) *models-seen*)
  ;; No on-chunk/on-complete is passed by the test, so COMPLETE-STREAM returns
  ;; this without reading it — no http-stream needed.
  (make-instance 'completion-stream :provider p :model model :state :open))

(defclass unreachable-stream-provider (openai-provider) ())

(defmethod send-streaming-request ((p unreachable-stream-provider) messages
                                   &key &allow-other-keys)
  (declare (ignore messages))
  (error 'provider-network-error :provider p :url "http://nowhere/v1"
                                 :operation :streaming))

(fiveam:test every-entry-point-offers-the-same-recovery-contract
  "ONE RESTART NAME, ONE CONTRACT, across COMPLETE, EMBEDDING and COMPLETE-STREAM.

Found by writing the how-to, not by a test, and that is the point. The
cross-provider fix landed in COMPLETE alone and left the other two with a
same-named restart that refused the second argument. A caller writes the
two-argument form, watches it work against COMPLETE, reuses the same recovery
handler for a STREAMING turn — the path an agent actually runs — and dies on
arity, at the moment its provider is already down.

DISCRIMINATING: INVOKES the two-argument form against each entry point and
asserts the supplied model is what arrived. Arity is not introspectable — a
restart-case clause's lambda list cannot be read back — so presence checks via
COMPUTE-RESTARTS would pass whether the argument were accepted or rejected.
Invoking is the only form that can tell those apart, and a wrong arity fails as
SB-INT:SIMPLE-PROGRAM-ERROR rather than as a quiet assertion.

Three explicit cases and no loop: there is no registry of entry points to iterate,
which is precisely how the three came apart."
  ;; COMPLETE
  (setf *models-seen* nil)
  (handler-bind
      ((provider-network-error
         (lambda (c)
           (let ((r (find-restart 'cl-llm-provider:use-fallback-provider c)))
             (when r (invoke-restart r
                                     (make-instance 'permissive-recording-provider
                                                    :model "its-own-default")
                                     "supplied-to-complete"))))))
    (complete '((:role "user" :content "hi"))
              :provider (make-instance 'unreachable-test-provider :model "dead")
              :model "dead"))
  (fiveam:is (equal "supplied-to-complete" (second (first *models-seen*)))
             "COMPLETE's use-fallback-provider took a model")

  ;; COMPLETE-STREAM — the path an agent's turn actually takes
  (setf *models-seen* nil)
  (handler-bind
      ((provider-network-error
         (lambda (c)
           (let ((r (find-restart 'cl-llm-provider:use-fallback-provider c)))
             (when r (invoke-restart r
                                     (make-instance 'recording-stream-provider
                                                    :model "its-own-default")
                                     "supplied-to-stream"))))))
    (complete-stream '((:role "user" :content "hi"))
                     :provider (make-instance 'unreachable-stream-provider :model "dead")
                     :model "dead"))
  (fiveam:is (equal "supplied-to-stream" (second (first *models-seen*)))
             "COMPLETE-STREAM's use-fallback-provider took a model too")

  ;; EMBEDDING
  (setf *models-seen* nil)
  (handler-bind
      ((provider-network-error
         (lambda (c)
           (let ((r (find-restart 'cl-llm-provider:use-fallback-provider c)))
             (when r (invoke-restart r
                                     (make-instance 'recording-embedding-provider
                                                    :model "its-own-default")
                                     "supplied-to-embedding"))))))
    (embedding "hi"
               :provider (make-instance 'unreachable-embedding-provider :model "dead")
               :model "dead"))
  (fiveam:is (equal "supplied-to-embedding" (second (first *models-seen*)))
             "EMBEDDING's use-fallback-provider took a model too"))

(defclass fussy-stream-provider (openai-provider) ())

(defmethod send-streaming-request ((p fussy-stream-provider) messages
                                   &key model &allow-other-keys)
  (declare (ignore messages))
  (push (list (provider-default-model p) model) *models-seen*)
  (unless (equal model (provider-default-model p))
    (error 'provider-model-not-found-error
           :provider p :requested-model model :status-code 404
           :message "Model not found"))
  (make-instance 'completion-stream :provider p :model model :state :open))

(fiveam:test use-model-is-offered-on-the-streaming-path-too
  "USE-MODEL travels with USE-FALLBACK-PROVIDER, or the pair is half-useful.

An agent handed a model-not-found on a STREAMING turn could otherwise only change
provider or repeat the same 404 — the gap that made this restart necessary on
COMPLETE, left open on the entry point an agent's turn actually uses.

DISCRIMINATING: asserts the SECOND attempt carried the correction, on a provider
that refuses anything but its own model. A test asserting only that a stream came
back would pass against a fixture that ignored :model."
  (setf *models-seen* nil)
  (let ((p (make-instance 'fussy-stream-provider :model "the-real-model")))
    (handler-bind
        ((provider-model-not-found-error
           (lambda (c)
             (let ((r (find-restart 'cl-llm-provider:use-model c)))
               (when r (invoke-restart r "the-real-model"))))))
      (complete-stream '((:role "user" :content "hi"))
                       :provider p :model "a-typo"))
    (fiveam:is (= 2 (length *models-seen*))
               "two attempts — the typo, then the correction")
    (fiveam:is (equal "a-typo" (second (second *models-seen*)))
               "the first carried the typo")
    (fiveam:is (equal "the-real-model" (second (first *models-seen*)))
               "and the second carried what the handler supplied")))
