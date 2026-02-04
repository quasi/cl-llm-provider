(th.harness:setup :cl-llm-provider)

(fiveam:def-suite observability-suite
  :description "Observability hooks tests"
  :in cl-llm-provider/test::cl-llm-provider-suite)

(fiveam:in-suite observability-suite)

(fiveam:test hooks-container-creation
  "Test hooks container creation"
  (let ((hooks (cl-llm-provider:make-hooks)))
    (fiveam:is (not (null hooks)))
    (fiveam:is (cl-llm-provider::hooks-p hooks))))

(fiveam:test add-and-invoke-hook
  "Test adding and invoking hooks"
  (let ((hooks (cl-llm-provider:make-hooks))
        (called nil))
    (cl-llm-provider:add-hook hooks :before-request
                              (lambda (provider model messages)
                                (declare (ignore provider model messages))
                                (setf called t)))
    (cl-llm-provider::invoke-hooks hooks :before-request nil "test" nil)
    (fiveam:is (eq called t))))

(fiveam:test complete-has-hooks-integration
  "Test that complete function can be called with hooks parameters"
  ;; Basic check that the function exists
  (fiveam:is (fboundp 'cl-llm-provider:complete))
  ;; The actual integration will be tested via behavior
  (fiveam:pass "Hooks parameter will be validated via integration"))

(fiveam:test complete-invokes-on-request-callback
  "Test that complete function invokes :on-request callback"
  (let ((called nil)
        (captured-info nil)
        ;; Create a mock provider with invalid API key to trigger network error
        (provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "invalid-key-for-test"
                                 :model "gpt-4o")))
    (handler-case
        (cl-llm-provider:complete
         '((:role "user" :content "test"))
         :provider provider
         :on-request (lambda (info)
                      (setf called t)
                      (setf captured-info info)))
      (error () nil))
    ;; The callback should have been invoked before the network request
    (fiveam:is (eq called t) "on-request callback should be invoked")
    (fiveam:is (not (null captured-info)) "request info should be captured")
    (when captured-info
      (fiveam:is (getf captured-info :provider) "request info should contain provider")
      (fiveam:is (getf captured-info :model) "request info should contain model"))))

(fiveam:test complete-invokes-on-error-callback
  "Test that complete function invokes :on-error callback on errors"
  (let ((error-called nil)
        (captured-error nil)
        ;; Create a mock provider with invalid API key
        (provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "invalid-key-for-test"
                                 :model "gpt-4o")))
    (handler-case
        (cl-llm-provider:complete
         '((:role "user" :content "test"))
         :provider provider
         :on-error (lambda (e)
                    (setf error-called t)
                    (setf captured-error e)))
      (error () nil))
    (fiveam:is (eq error-called t) "on-error callback should be invoked")
    (fiveam:is (not (null captured-error)) "error should be captured")))

(fiveam:test complete-invokes-hooks-structure
  "Test that complete function invokes hooks from hooks structure"
  (let ((before-called nil)
        (error-called nil)
        (hooks (cl-llm-provider:make-hooks))
        ;; Create a mock provider with invalid API key
        (provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "invalid-key-for-test"
                                 :model "gpt-4o")))

    (cl-llm-provider:add-hook hooks :before-request
                              (lambda (provider model messages)
                                (declare (ignore provider model messages))
                                (setf before-called t)))

    (cl-llm-provider:add-hook hooks :on-error
                              (lambda (provider model error)
                                (declare (ignore provider model error))
                                (setf error-called t)))

    ;; This will error on network call due to invalid API key
    (handler-case
        (cl-llm-provider:complete
         '((:role "user" :content "test"))
         :provider provider
         :hooks hooks)
      (error () nil))

    (fiveam:is (eq before-called t) "before-request hook should be invoked")
    (fiveam:is (eq error-called t) "on-error hook should be invoked")))

(fiveam:test logging-hook-helper
  "Test logging hook helper"
  (let* ((log-output (make-string-output-stream))
         (hooks (cl-llm-provider:make-logging-hooks :stream log-output))
         (provider (make-instance 'cl-llm-provider::openai-provider
                                  :api-key "test-key"
                                  :model "gpt-4")))
    ;; Invoke before-request hook
    (cl-llm-provider::invoke-hooks hooks :before-request
                                   provider "gpt-4" '((:role "user" :content "Hi")))
    (let ((output (get-output-stream-string log-output)))
      (fiveam:is (search "gpt-4" output) "Output should contain model name")
      (fiveam:is (search "LLM Request" output) "Output should contain request marker"))))

(fiveam:test logging-hook-logs-before-request
  "Test that logging hook logs before request with correct details"
  (let* ((log-output (make-string-output-stream))
         (hooks (cl-llm-provider:make-logging-hooks :stream log-output))
         (provider (make-instance 'cl-llm-provider::openai-provider
                                  :api-key "test-key"
                                  :model "gpt-4o")))
    (cl-llm-provider::invoke-hooks hooks :before-request
                                   provider "gpt-4o"
                                   '((:role "user" :content "Test message 1")
                                     (:role "assistant" :content "Reply")
                                     (:role "user" :content "Test message 2")))
    (let ((output (get-output-stream-string log-output)))
      (fiveam:is (search "gpt-4o" output) "Should log model name")
      (fiveam:is (search "3 messages" output) "Should log message count")
      (fiveam:is (search "OpenAI" output) "Should log provider name"))))

(fiveam:test logging-hook-logs-after-response
  "Test that logging hook logs after response with timing and token info"
  (let* ((log-output (make-string-output-stream))
         (hooks (cl-llm-provider:make-logging-hooks :stream log-output))
         (provider (make-instance 'cl-llm-provider::openai-provider
                                  :api-key "test-key"))
         (mock-response (make-instance 'cl-llm-provider::completion-response
                                       :content "Hello"
                                       :usage '(:total-tokens 42))))
    (cl-llm-provider::invoke-hooks hooks :after-response
                                   provider "gpt-4" mock-response 1.25)
    (let ((output (get-output-stream-string log-output)))
      (fiveam:is (search "LLM Response" output) "Should contain response marker")
      (fiveam:is (search "1.25s" output) "Should log timing")
      (fiveam:is (search "42 tokens" output) "Should log token count"))))

(fiveam:test logging-hook-logs-errors
  "Test that logging hook logs errors"
  (let* ((log-output (make-string-output-stream))
         (hooks (cl-llm-provider:make-logging-hooks :stream log-output))
         (provider (make-instance 'cl-llm-provider::openai-provider
                                  :api-key "test-key"))
         (mock-error (make-condition 'simple-error
                                     :format-control "Test error message")))
    (cl-llm-provider::invoke-hooks hooks :on-error
                                   provider "gpt-4" mock-error)
    (let ((output (get-output-stream-string log-output)))
      (fiveam:is (search "LLM Error" output) "Should contain error marker")
      (fiveam:is (search "Test error message" output) "Should log error message"))))

(fiveam:test logging-hook-debug-level
  "Test that logging hook at debug level includes message content"
  (let* ((log-output (make-string-output-stream))
         (hooks (cl-llm-provider:make-logging-hooks :stream log-output :level :debug))
         (provider (make-instance 'cl-llm-provider::openai-provider
                                  :api-key "test-key")))
    (cl-llm-provider::invoke-hooks hooks :before-request
                                   provider "gpt-4"
                                   '((:role "user" :content "Debug content")))
    (let ((output (get-output-stream-string log-output)))
      (fiveam:is (search "Debug content" output) "Debug level should include message content"))))

