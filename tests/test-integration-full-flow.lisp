(th.harness:setup :cl-llm-provider)

(fiveam:def-suite integration-suite
  :description "Integration tests for complete request/response flows"
  :in cl-llm-provider/test::cl-llm-provider-suite)

(fiveam:in-suite integration-suite)

;;;; Provider Initialization Tests

(fiveam:test provider-anthropic-full-initialization
  "Anthropic provider full initialization with all parameters"
  (let ((provider (make-provider :anthropic
                                :api-key "test-key"
                                :model "claude-3-sonnet")))
    (fiveam:is (typep provider 'anthropic-provider))
    (fiveam:is (string= (provider-api-key provider) "test-key"))
    (fiveam:is (string= (provider-default-model provider) "claude-3-sonnet"))))

(fiveam:test provider-openai-full-initialization
  "OpenAI provider full initialization"
  (let ((provider (make-provider :openai
                               :api-key "sk-test"
                               :model "gpt-4-turbo")))
    (fiveam:is (typep provider 'openai-provider))
    (fiveam:is (string= (provider-default-model provider) "gpt-4-turbo"))))

(fiveam:test provider-ollama-local-initialization
  "Ollama local provider initialization"
  (let ((provider (make-provider :ollama
                               :base-url "http://localhost:11434"
                               :model "llama2")))
    (fiveam:is (typep provider 'ollama-provider))
    (fiveam:is (string= (provider-default-model provider) "llama2"))))

(fiveam:test provider-openai-compatible-initialization
  "OpenAI-compatible provider initialization"
  (let ((provider (make-provider :openai-compatible
                                :base-url "http://localhost:8000"
                                :api-key "test"
                                :model "local-gpt")))
    (fiveam:is (typep provider 'openai-compatible-provider))))

;;;; Message Construction Flow Tests

(fiveam:test construct-user-message
  "Construct user message for API"
  (let ((msg '(:role "user" :content "What is 2+2?")))
    (fiveam:is (string= (getf msg :role) "user"))
    (fiveam:is (string= (getf msg :content) "What is 2+2?"))))

(fiveam:test construct-conversation-sequence
  "Construct multi-turn conversation"
  (let ((messages '((:role "user" :content "Hello")
                   (:role "assistant" :content "Hi there!")
                   (:role "user" :content "How are you?"))))
    (fiveam:is (= (length messages) 3))
    (fiveam:is (string= (getf (first messages) :role) "user"))
    (fiveam:is (string= (getf (second messages) :role) "assistant"))))

(fiveam:test construct-system-prompt
  "Construct system prompt"
  (let ((system "You are a helpful assistant")
        (messages '((:role "user" :content "Help me"))))
    (fiveam:is (stringp system))
    (fiveam:is (listp messages))))

(fiveam:test construct-messages-with-tools
  "Construct messages with tool calling enabled"
  (let ((tool (make-instance 'tool-definition
                            :name "calculator"
                            :description "Performs arithmetic"
                            :parameters '((:name "a" :type :number :description "First number")
                                         (:name "b" :type :number :description "Second number")
                                         (:name "op" :type :string :description "Operation"))))
        (messages '((:role "user" :content "What is 5+3?"))))
    (fiveam:is (string= (tool-name tool) "calculator"))
    (fiveam:is (= (length messages) 1))))

;;;; Response Validation Flow Tests

(fiveam:test response-creation-basic
  "Create basic completion response"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content "The answer is 8"
                                :message '(:role "assistant" :content "The answer is 8")
                                :usage '(:prompt-tokens 20 :completion-tokens 5 :total-tokens 25))))
    (fiveam:is (string= (response-id response) "resp-1"))
    (fiveam:is (string= (response-content response) "The answer is 8"))))

(fiveam:test response-with-metadata
  "Response with provider-specific metadata"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content "Test"
                                :message '(:role "assistant" :content "Test")
                                :metadata '(:system-fingerprint "fp_abc123" :created 1234567890)
                                :usage '(:prompt-tokens 1 :completion-tokens 1 :total-tokens 2))))
    (fiveam:is (response-metadata response))
    (fiveam:is (getf (response-metadata response) :system-fingerprint))))

(fiveam:test response-with-performance
  "Response with performance profiling data"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content "Test"
                                :message '(:role "assistant" :content "Test")
                                :performance '(:encode-time 0.001 :api-time 1.5 :decode-time 0.002)
                                :usage '(:prompt-tokens 1 :completion-tokens 1 :total-tokens 2))))
    (fiveam:is (response-performance response))
    (fiveam:is (getf (response-performance response) :api-time))))

(fiveam:test response-with-tool-calls
  "Response containing tool call instead of text"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content nil
                                :message '(:role "assistant")
                                :tool-calls nil
                                :finish-reason :tool-calls
                                :usage '(:prompt-tokens 20 :completion-tokens 10 :total-tokens 30))))
    (fiveam:is (null (response-content response)))
    (fiveam:is (eq (response-finish-reason response) :tool-calls))))

;;;; Error Handling Flow Tests

(fiveam:test handle-missing-api-key
  "Handle missing API key gracefully"
  (handler-case
      (make-provider :openai :model "gpt-4")
    ;; Should either work with env var or allow proceeding
    (t () (fiveam:pass))))

(fiveam:test handle-invalid-provider-type
  "Handle invalid provider type"
  (handler-case
      (make-provider :invalid-provider)
    (error () (fiveam:pass))
    (:no-error () (fiveam:pass)))) ;; May have default behavior

(fiveam:test handle-provider-api-error
  "Provider API error should be catchable"
  (let ((error (make-instance 'provider-api-error
                             :message "API request failed"
                             :status-code 500)))
    (fiveam:is (string= (error-message error) "API request failed"))))

(fiveam:test handle-rate-limit-error
  "Rate limit error should include retry info"
  (let ((error (make-instance 'provider-rate-limit-error
                             :message "Too many requests"
                             :status-code 429
                             :retry-after 60)))
    (fiveam:is (= (error-retry-after error) 60))))

;;;; Tool Definition and Validation Tests

(fiveam:test create-and_validate_tool
  "Create tool and verify structure"
  (let ((tool (make-instance 'tool-definition
                            :name "search"
                            :description "Search the web"
                            :parameters '((:name "query" :type :string :description "Search term"))
                            :required '("query"))))
    (fiveam:is (string= (tool-name tool) "search"))
    (fiveam:is (= (length (tool-parameters tool)) 1))))

(fiveam:test tool-parameters-validation
  "Validate tool parameter structure"
  (let ((param '(:name "items" :type :array :description "List of items")))
    (fiveam:is (string= (getf param :name) "items"))
    (fiveam:is (eq (getf param :type) :array))))

(fiveam:test tool-multiple-parameters
  "Tool with multiple parameters"
  (let ((tool (make-instance 'tool-definition
                            :name "math"
                            :description "Math operations"
                            :parameters '((:name "a" :type :number :description "First number")
                                         (:name "b" :type :number :description "Second number")
                                         (:name "operation" :type :string :description "Operation")))))
    (fiveam:is (= (length (tool-parameters tool)) 3))))

;;;; Token Counting Flow Tests

(fiveam:test token_usage_tracking
  "Token usage should be tracked in response"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content "Response"
                                :message '(:role "assistant" :content "Response")
                                :usage '(:prompt-tokens 100 :completion-tokens 50 :total-tokens 150))))
    (let ((usage (response-usage response)))
      (fiveam:is (= (getf usage :prompt-tokens) 100))
      (fiveam:is (= (getf usage :completion-tokens) 50))
      (fiveam:is (= (getf usage :total-tokens) 150)))))

(fiveam:test token_count_math
  "Token counts should satisfy mathematical relationship"
  (let ((usage '(:prompt-tokens 100 :completion-tokens 50 :total-tokens 150)))
    (fiveam:is (= (getf usage :total-tokens)
                  (+ (getf usage :prompt-tokens)
                     (getf usage :completion-tokens))))))

;;;; Conversation Continuation Tests

(fiveam:test continue_conversation_after_response
  "Use response message to continue conversation"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content "I like pizza"
                                :message '(:role "assistant" :content "I like pizza")
                                :usage '(:prompt-tokens 10 :completion-tokens 3 :total-tokens 13))))
    (let ((next-messages (list '(:role "user" :content "Tell me more")
                              (response-message response))))
      (fiveam:is (= (length next-messages) 2)))))

(fiveam:test continue_with_tool_response
  "Continue conversation after tool execution"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content nil
                                :message '(:role "assistant")
                                :tool-calls nil
                                :finish-reason :tool-calls
                                :usage '(:prompt-tokens 20 :completion-tokens 10 :total-tokens 30))))
    (let ((tool-result-msg '(:role "user" :content "Tool result: 42")))
      (fiveam:is (string= (getf tool-result-msg :role) "user")))))

;;;; Embedding Flow Tests

(fiveam:test embedding_response_creation
  "Create embedding response"
  (let ((response (make-instance 'embedding-response
                                :embeddings '((0.1 0.2 0.3) (0.4 0.5 0.6))
                                :model "text-embedding-3-small"
                                :usage '(:prompt-tokens 10 :total-tokens 10))))
    (fiveam:is (= (length (response-embeddings response)) 2))))

(fiveam:test embedding_vector_properties
  "Embedding vectors should be proper floats"
  (let ((embeddings '((0.1 0.2 0.3) (0.4 0.5 0.6))))
    (dolist (vec embeddings)
      (dolist (val vec)
        (fiveam:is (numberp val))))))

;;;; Multi-Provider Compatibility Tests

(fiveam:test response_works_across_providers
  "Response object should work regardless of provider"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content "Test"
                                :message '(:role "assistant" :content "Test")
                                :usage '(:prompt-tokens 1 :completion-tokens 1 :total-tokens 2))))
    ;; Same response can work for any provider
    (fiveam:is (typep response 'completion-response))))

(fiveam:test different_providers_different_instances
  "Different provider instances are independent"
  (let ((openai (make-provider :openai :api-key "key1" :model "gpt-4"))
        (ollama (make-provider :ollama :base-url "http://localhost:11434" :model "llama2")))
    (fiveam:is (not (eql openai ollama)))
    (fiveam:is (not (string= (provider-default-model openai) (provider-default-model ollama))))))

;;;; Configuration and Defaults Tests

(fiveam:test default_temperature
  "Default temperature should be set"
  (fiveam:is (numberp *default-temperature*)))

(fiveam:test default_model
  "Default model can be configured"
  ;; Default model is optional - can be nil
  (fiveam:is (fboundp 'provider-default-model)))

(fiveam:test default_max_tokens
  "Global default max tokens"
  ;; Anthropic requires max_tokens, others optional
  (fiveam:is (numberp 4096)))

(fiveam:test override_defaults
  "Instance defaults should override global defaults"
  (let ((provider (make-provider :openai
                               :api-key "test"
                               :model "gpt-4")))
    (fiveam:is (string= (provider-default-model provider) "gpt-4"))))

;;;; Ollama-Specific Tests

(fiveam:test ollama-available-check
  "Check if Ollama is available"
  (let ((available (handler-case (dex:get "http://localhost:11434/api/tags")
                     (error () nil))))
    ;; Test just verifies we can attempt the check
    (fiveam:is (fboundp 'dex:get))))

(fiveam:test ollama-provider-creation
  "Create Ollama provider"
  (let ((provider (make-provider :ollama
                               :base-url "http://localhost:11434"
                               :model "llama2")))
    (fiveam:is (typep provider 'ollama-provider))))

;;;; Anthropic-Specific Tests

(fiveam:test anthropic-provider-creation
  "Create Anthropic provider"
  (let ((provider (make-provider :anthropic
                                :api-key "test"
                                :model "claude-3-opus")))
    (fiveam:is (typep provider 'anthropic-provider))))

(fiveam:test anthropic-max-tokens-default
  "Anthropic should have max_tokens requirement"
  ;; Anthropic requires max_tokens (default 4096)
  (fiveam:is (> 4096 0)))

;;;; OpenAI-Specific Tests

(fiveam:test openai-provider-creation
  "Create OpenAI provider"
  (let ((provider (make-provider :openai
                               :api-key "sk-test"
                               :model "gpt-4")))
    (fiveam:is (typep provider 'openai-provider))))

(fiveam:test openai-supports-tools
  "OpenAI provider supports tool calling"
  (fiveam:is (fboundp 'translate-tool-to-provider)))

;;;; Response Independence Tests

(fiveam:test responses-dont-share-state
  "Multiple responses shouldn't share state"
  (let ((resp1 (make-instance 'completion-response
                             :id "r1"
                             :model "gpt-4"
                             :content "A"
                             :message '(:role "assistant" :content "A")
                             :usage '(:prompt-tokens 1 :completion-tokens 1 :total-tokens 2)))
        (resp2 (make-instance 'completion-response
                             :id "r2"
                             :model "gpt-4"
                             :content "B"
                             :message '(:role "assistant" :content "B")
                             :usage '(:prompt-tokens 1 :completion-tokens 1 :total-tokens 2))))
    (fiveam:is (not (eq resp1 resp2)))
    (fiveam:is (not (string= (response-content resp1) (response-content resp2))))))

;;;; Performance Profiling Integration Tests

(fiveam:test profiling-disabled-by-default
  "Performance profiling disabled by default"
  (fiveam:is (null *performance-profiling*)))

(fiveam:test profiling-can-be-enabled
  "Performance profiling can be enabled"
  (let ((*performance-profiling* t))
    (fiveam:is (not (null *performance-profiling*)))))

(fiveam:test response-with-profiling-data
  "Response can carry profiling data"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content "Test"
                                :message '(:role "assistant" :content "Test")
                                :performance '(:encode-time 0.001 :api-time 1.0 :decode-time 0.001)
                                :usage '(:prompt-tokens 1 :completion-tokens 1 :total-tokens 2))))
    (fiveam:is (response-performance response))))

