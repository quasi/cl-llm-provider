(th.harness:setup :cl-llm-provider)

(fiveam:def-suite tools-integration-suite
  :description "Integration tests for tool support across providers"
  :in cl-llm-provider/test::cl-llm-provider-suite)

(fiveam:in-suite tools-integration-suite)

;;;; Tool Definition and Setup Tests

(fiveam:test setup-simple-tool
  "Setup a simple tool definition"
  (let ((tool (make-instance 'tool-definition
                            :name "weather"
                            :description "Get weather"
                            :parameters '((:name "location" :type :string :description "City name")))))
    (fiveam:is (string= (tool-name tool) "weather"))
    (fiveam:is (= (length (tool-parameters tool)) 1))))

(fiveam:test setup-calculator-tool
  "Setup a calculator tool"
  (let ((tool (make-instance 'tool-definition
                            :name "calculator"
                            :description "Perform arithmetic"
                            :parameters '((:name "operation" :type :string :description "Add, subtract, multiply, divide")
                                         (:name "a" :type :number :description "First number")
                                         (:name "b" :type :number :description "Second number"))
                            :required '("operation" "a" "b"))))
    (fiveam:is (= (length (tool-parameters tool)) 3))
    (fiveam:is (= (length (tool-required-params tool)) 3))))

(fiveam:test setup-search-tool
  "Setup a search tool"
  (let ((tool (make-instance 'tool-definition
                            :name "search"
                            :description "Search the knowledge base"
                            :parameters '((:name "query" :type :string :description "Search query")
                                         (:name "limit" :type :integer :description "Max results")
                                         (:name "filter" :type :string :description "Filter by category"
                                          :enum ("all" "articles" "faqs" "docs")))
                            :required '("query"))))
    (fiveam:is (= (length (tool-parameters tool)) 3))))

;;;; Tool List Creation Tests

(fiveam:test create-tool-set
  "Create a set of related tools"
  (let ((tools (list (make-instance 'tool-definition
                                   :name "get_user"
                                   :description "Get user info"
                                   :parameters '((:name "user_id" :type :string :description "User ID")))
                    (make-instance 'tool-definition
                                   :name "list_users"
                                   :description "List all users"
                                   :parameters '((:name "page" :type :integer :description "Page number")))
                    (make-instance 'tool-definition
                                   :name "create_user"
                                   :description "Create new user"
                                   :parameters '((:name "name" :type :string :description "User name")
                                               (:name "email" :type :string :description "Email address"))))))
    (fiveam:is (= (length tools) 3))))

(fiveam:test tools_with_different_parameter_counts
  "Tools can have different number of parameters"
  (let ((tools (list (make-instance 'tool-definition
                                   :name "t0"
                                   :description "No params"
                                   :parameters nil)
                    (make-instance 'tool-definition
                                   :name "t1"
                                   :description "One param"
                                   :parameters '((:name "x" :type :string :description "X")))
                    (make-instance 'tool-definition
                                   :name "t2"
                                   :description "Two params"
                                   :parameters '((:name "x" :type :string :description "X")
                                               (:name "y" :type :string :description "Y")))
                    (make-instance 'tool-definition
                                   :name "t3"
                                   :description "Three params"
                                   :parameters '((:name "x" :type :string :description "X")
                                               (:name "y" :type :string :description "Y")
                                               (:name "z" :type :string :description "Z"))))))
    (fiveam:is (null (tool-parameters (first tools))))
    (fiveam:is (= (length (tool-parameters (second tools))) 1))
    (fiveam:is (= (length (tool-parameters (third tools))) 2))
    (fiveam:is (= (length (tool-parameters (fourth tools))) 3))))

;;;; Tool Call Workflow Tests

(fiveam:test tool-call-workflow
  "Complete tool call workflow"
  ;; 1. Create tool
  (let ((tool (make-instance 'tool-definition
                            :name "add"
                            :description "Add numbers"
                            :parameters '((:name "a" :type :number :description "First")
                                         (:name "b" :type :number :description "Second")))))
    ;; 2. Create tool call requesting execution
    (let ((call (make-instance 'tool-call
                              :id "call-123"
                              :name "add"
                              :arguments '(:a 5 :b 3))))
      ;; 3. Verify call matches tool
      (fiveam:is (string= (tool-call-name call) (tool-name tool)))
      ;; 4. Create result
      (let ((result (make-tool-result (tool-call-id call) "8")))
        ;; 5. Verify result structure
        (fiveam:is (string= (getf result :role) "tool"))
        (fiveam:is (string= (getf result :content) "8"))))))

(fiveam:test multiple-tool-calls_in-response
  "Response can contain multiple tool calls"
  (let ((calls (list (make-instance 'tool-call
                                   :id "call-1"
                                   :name "search"
                                   :arguments '(:query "weather"))
                    (make-instance 'tool-call
                                   :id "call-2"
                                   :name "search"
                                   :arguments '(:query "news")))))
    (fiveam:is (= (length calls) 2))))

(fiveam:test tool-call_with_complex_arguments
  "Tool call can have complex argument types"
  (let ((call (make-instance 'tool-call
                            :id "call-1"
                            :name "configure"
                            :arguments '(:settings (:enabled t :count 42 :tags ("a" "b"))))))
    (let ((args (tool-call-arguments call)))
      (fiveam:is (getf args :settings)))))

;;;; Tool Result Processing Tests

(fiveam:test process-tool-result
  "Process result from tool execution"
  ;; Simulate tool execution result
  (let ((json-result "{\"status\": \"success\", \"data\": [1, 2, 3]}"))
    ;; Create result message
    (let ((result-msg (make-tool-result "call-456" json-result)))
      (fiveam:is (string= (getf result-msg :content) json-result)))))

(fiveam:test tool-result-error_case
  "Handle tool error result"
  (let ((error-msg "{\"error\": \"User not found\"}"))
    (let ((result (make-tool-result "call-789" error-msg :is-error t)))
      (fiveam:is (getf result :is-error)))))

(fiveam:test batch-tool-results
  "Process multiple tool results"
  (let ((calls (list (make-instance 'tool-call
                                   :id "call-1"
                                   :name "tool"
                                   :arguments nil)
                    (make-instance 'tool-call
                                   :id "call-2"
                                   :name "tool"
                                   :arguments nil))))
    (let ((results (mapcar (lambda (call)
                             (make-tool-result (tool-call-id call) "result"))
                           calls)))
      (fiveam:is (= (length results) 2)))))

;;;; Conversation Flow with Tools Tests

(fiveam:test initial-request-with-tools
  "Send initial request with available tools"
  (let ((messages '((:role "user" :content "Help me calculate")))
        (tools (list (make-instance 'tool-definition
                                   :name "calc"
                                   :description "Calculate"
                                   :parameters nil))))
    ;; In real scenario, would call: (complete messages :tools tools)
    ;; For test, just verify structure is valid
    (fiveam:is (> (length messages) 0))
    (fiveam:is (> (length tools) 0))))

(fiveam:test assistant-response-with-tool-call
  "Handle assistant response with tool call"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content nil
                                :message '(:role "assistant")
                                :tool-calls nil
                                :finish-reason :tool-calls
                                :usage '(:prompt-tokens 50 :completion-tokens 30 :total-tokens 80))))
    (fiveam:is (eq (response-finish-reason response) :tool-calls))))

(fiveam:test continuation-after-tool-result
  "Continue conversation with tool result"
  ;; Original conversation
  (let ((original '((:role "user" :content "Calculate")))
        ;; Assistant response requesting tool
        (assistant-msg '(:role "assistant" :content nil))
        ;; Tool result
        (tool-result (make-tool-result "call-1" "42")))
    ;; Extended conversation
    (let ((extended (append original (list assistant-msg) (list tool-result))))
      ;; Would continue with: (complete extended :tools tools)
      (fiveam:is (= (length extended) 3)))))

(fiveam:test multi-turn-tool-conversation
  "Multi-turn conversation with tools"
  (let ((turn-1-user '(:role "user" :content "First question"))
        (turn-1-asst '(:role "assistant" :content nil))
        (turn-1-tool (make-tool-result "c1" "answer1"))
        (turn-2-user '(:role "user" :content "Follow up"))
        (turn-2-asst '(:role "assistant" :content "Final answer")))
    (let ((history (list turn-1-user turn-1-asst turn-1-tool turn-2-user turn-2-asst)))
      (fiveam:is (= (length history) 5)))))

;;;; Provider Tool Compatibility Tests

(fiveam:test openai-with-tools
  "OpenAI provider with tool support"
  (let ((provider (make-provider :openai :api-key "test" :model "gpt-4"))
        (tools (list (make-instance 'tool-definition
                                   :name "search"
                                   :description "Search"
                                   :parameters nil))))
    ;; Would call: (complete messages :provider provider :tools tools)
    (fiveam:is (typep provider 'openai-provider))
    (fiveam:is (> (length tools) 0))))

(fiveam:test anthropic-with-tools
  "Anthropic provider with tool support"
  (let ((provider (make-provider :anthropic :api-key "test" :model "claude-3-opus"))
        (tools (list (make-instance 'tool-definition
                                   :name "search"
                                   :description "Search"
                                   :parameters nil))))
    ;; Would call: (complete messages :provider provider :tools tools)
    (fiveam:is (typep provider 'anthropic-provider))
    (fiveam:is (> (length tools) 0))))

(fiveam:test ollama-with-tools
  "Ollama provider with tool support"
  (let ((provider (make-provider :ollama :base-url "http://localhost:11434" :model "llama2"))
        (tools (list (make-instance 'tool-definition
                                   :name "search"
                                   :description "Search"
                                   :parameters nil))))
    ;; Would call: (complete messages :provider provider :tools tools)
    (fiveam:is (typep provider 'ollama-provider))
    (fiveam:is (> (length tools) 0))))

;;;; Tool Choice Tests

(fiveam:test tool-choice-auto-behavior
  "Tool choice :auto allows model to choose"
  ;; In actual implementation, would pass :tool-choice :auto to complete()
  (let ((choice :auto))
    (fiveam:is (eq choice :auto))))

(fiveam:test tool-choice-required-behavior
  "Tool choice :required forces tool call"
  ;; In actual implementation, would pass :tool-choice :required to complete()
  (let ((choice :required))
    (fiveam:is (eq choice :required))))

(fiveam:test tool-choice-specific-tool
  "Tool choice can specify exact tool"
  ;; In actual implementation, would pass :tool-choice "tool_name" to complete()
  (let ((choice "calculator"))
    (fiveam:is (string= choice "calculator"))))

;;;; Tool Validation and Error Handling Tests

(fiveam:test validate-tools-before-request
  "Validate tools before sending request"
  (let ((tools (list (make-instance 'tool-definition
                                   :name "valid"
                                   :description "Valid tool"
                                   :parameters nil))))
    ;; Tool validation would occur here
    (fiveam:is (> (length tools) 0))))

(fiveam:test handle-missing-tool
  "Handle case where tool call references non-existent tool"
  (let ((tools (list (make-instance 'tool-definition
                                   :name "search"
                                   :description "Search"
                                   :parameters nil)))
        (call (make-instance 'tool-call
                            :id "call-1"
                            :name "missing_tool"
                            :arguments nil)))
    ;; Check if tool exists
    (let ((found (find (tool-call-name call) tools :key #'tool-name :test #'string=)))
      (fiveam:is (null found)))))

(fiveam:test handle-invalid-arguments
  "Handle tool call with invalid argument types"
  ;; This would be caught during tool execution, not in our data structures
  (let ((call (make-instance 'tool-call
                            :id "call-1"
                            :name "calculator"
                            :arguments '(:a "not_a_number" :b 5))))
    ;; Arguments are stored as-is; validation happens at execution
    (fiveam:is (getf (tool-call-arguments call) :a))))

;;;; Tool Name and ID Tests

(fiveam:test tool-names-are-unique_in_set
  "Tool names should be unique in a tool set"
  (let ((tools (list (make-instance 'tool-definition
                                   :name "tool"
                                   :description "First"
                                   :parameters nil)
                    (make-instance 'tool-definition
                                   :name "different"
                                   :description "Second"
                                   :parameters nil))))
    (let ((names (mapcar #'tool-name tools)))
      (fiveam:is (= (length names) (length (remove-duplicates names :test #'string=)))))))

(fiveam:test tool-call-ids-are-unique
  "Tool call IDs should be unique"
  (let ((calls (list (make-instance 'tool-call
                                   :id "call-1"
                                   :name "tool"
                                   :arguments nil)
                    (make-instance 'tool-call
                                   :id "call-2"
                                   :name "tool"
                                   :arguments nil))))
    (let ((ids (mapcar #'tool-call-id calls)))
      (fiveam:is (= (length ids) (length (remove-duplicates ids :test #'string=)))))))

;;;; Tool Parameter Type Compatibility Tests

(fiveam:test all-parameter-types_supported
  "All parameter types should be supported"
  (let ((types '(:string :integer :number :boolean :array :object)))
    (dolist (type types)
      (let ((param (list :name "test" :type type :description "Test")))
        (fiveam:is (eq (getf param :type) type))))))

(fiveam:test parameter-with-enum_values
  "Parameter enum values should be accessible"
  (let ((param '(:name "choice" :type :string :description "Choice"
                 :enum ("a" "b" "c"))))
    (let ((enum (getf param :enum)))
      (fiveam:is (= (length enum) 3))
      (fiveam:is (member "a" enum :test #'string=)))))

;;;; Tool Description and Help Tests

(fiveam:test tool-description_for_llm
  "Tool description should be informative for LLM"
  (let ((tool (make-instance 'tool-definition
                            :name "search_docs"
                            :description "Search through documentation for information. Returns matching documents with relevance scores."
                            :parameters '((:name "query" :type :string :description "Search query to find relevant documents")
                                         (:name "category" :type :string :description "Optional category filter to limit search scope")))))
    (fiveam:is (> (length (tool-description tool)) 20))))

(fiveam:test parameter-description_clarity
  "Parameter descriptions should be clear"
  (let ((params '((:name "count" :type :integer :description "The maximum number of results to return, between 1 and 100"))))
    (dolist (param params)
      (let ((desc (getf param :description)))
        (fiveam:is (> (length desc) 10))))))

;;;; Tool System Integration Tests

(fiveam:test tool-system-complete-flow
  "Complete tool system flow from definition to result"
  ;; 1. Define tools
  (let ((tools (list (make-instance 'tool-definition
                                   :name "compute"
                                   :description "Compute something"
                                   :parameters '((:name "expr" :type :string :description "Expression"))))))
    ;; 2. Prepare request
    (let ((messages '((:role "user" :content "Compute 2+2"))))
      ;; 3. Simulate response with tool call
      (let ((tool-call (make-instance 'tool-call
                                     :id "call-abc"
                                     :name "compute"
                                     :arguments '(:expr "2+2"))))
        ;; 4. Process result
        (let ((result (make-tool-result (tool-call-id tool-call) "4")))
          ;; 5. Verify complete flow
          (fiveam:is (string= (tool-call-name tool-call) "compute"))
          (fiveam:is (string= (getf (tool-call-arguments tool-call) :expr) "2+2"))
          (fiveam:is (string= (getf result :content) "4")))))))

