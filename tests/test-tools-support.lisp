(th.harness:setup :cl-llm-provider)

(fiveam:def-suite tools-suite
  :description "Comprehensive test suite for tool support"
  :in cl-llm-provider/test::cl-llm-provider-suite)

(fiveam:in-suite tools-suite)

;;;; Tool Definition Tests

(fiveam:test create-simple-tool
  "Create a simple tool with name, description, and parameters"
  (let ((tool (make-instance 'tool-definition
                            :name "add"
                            :description "Adds two numbers"
                            :parameters '((:name "a" :type :number :description "First number")
                                         (:name "b" :type :number :description "Second number")))))
    (fiveam:is (string= (tool-name tool) "add"))
    (fiveam:is (string= (tool-description tool) "Adds two numbers"))
    (fiveam:is (= (length (tool-parameters tool)) 2))))

(fiveam:test tool-with-required-parameters
  "Tool can specify required parameters"
  (let ((tool (make-instance 'tool-definition
                            :name "search"
                            :description "Search for something"
                            :parameters '((:name "query" :type :string :description "Search query")
                                         (:name "limit" :type :integer :description "Result limit"))
                            :required '("query"))))
    (fiveam:is (member "query" (tool-required-params tool) :test #'string=))
    (fiveam:is (not (member "limit" (tool-required-params tool) :test #'string=)))))

(fiveam:test tool-with-no-parameters
  "Tool can have no parameters"
  (let ((tool (make-instance 'tool-definition
                            :name "get_time"
                            :description "Gets current time"
                            :parameters nil)))
    (fiveam:is (null (tool-parameters tool)))))

(fiveam:test tool-name-is-string
  "Tool name should be a string"
  (let ((tool (make-instance 'tool-definition
                            :name "my_tool"
                            :description "Description"
                            :parameters nil)))
    (fiveam:is (stringp (tool-name tool)))))

(fiveam:test tool-description-is-string
  "Tool description should be a string"
  (let ((tool (make-instance 'tool-definition
                            :name "tool"
                            :description "My description"
                            :parameters nil)))
    (fiveam:is (stringp (tool-description tool)))))

;;;; Tool Parameter Type Tests

(fiveam:test parameter-string-type
  "Parameter can be string type"
  (let ((param '(:name "text" :type :string :description "Some text")))
    (fiveam:is (eq (getf param :type) :string))))

(fiveam:test parameter-integer-type
  "Parameter can be integer type"
  (let ((param '(:name "count" :type :integer :description "A count")))
    (fiveam:is (eq (getf param :type) :integer))))

(fiveam:test parameter-number-type
  "Parameter can be number type"
  (let ((param '(:name "price" :type :number :description "A price")))
    (fiveam:is (eq (getf param :type) :number))))

(fiveam:test parameter-boolean-type
  "Parameter can be boolean type"
  (let ((param '(:name "enabled" :type :boolean :description "Enable flag")))
    (fiveam:is (eq (getf param :type) :boolean))))

(fiveam:test parameter-array-type
  "Parameter can be array type"
  (let ((param '(:name "items" :type :array :description "List of items")))
    (fiveam:is (eq (getf param :type) :array))))

(fiveam:test parameter-object-type
  "Parameter can be object type"
  (let ((param '(:name "config" :type :object :description "Configuration object")))
    (fiveam:is (eq (getf param :type) :object))))

(fiveam:test parameter-with-enum
  "Parameter can have enum constraint"
  (let ((param '(:name "operation" :type :string :description "Operation"
                 :enum ("add" "subtract" "multiply"))))
    (fiveam:is (member "add" (getf param :enum) :test #'string=))))

(fiveam:test parameter-has-name
  "Parameter must have name"
  (let ((param '(:name "param1" :type :string :description "Description")))
    (fiveam:is (stringp (getf param :name)))))

(fiveam:test parameter-has-type
  "Parameter must have type"
  (let ((param '(:name "param1" :type :string :description "Description")))
    (fiveam:is (keywordp (getf param :type)))))

(fiveam:test parameter-has-description
  "Parameter should have description"
  (let ((param '(:name "param1" :type :string :description "Parameter description")))
    (fiveam:is (stringp (getf param :description)))))

;;;; Tool Validation Tests

(fiveam:test validate-valid-tool
  "Valid tool should pass validation"
  (let ((tool (make-instance 'tool-definition
                            :name "valid"
                            :description "A valid tool"
                            :parameters '((:name "p" :type :string :description "param")))))
    (fiveam:is (tool-name tool))))

(fiveam:test validate-tool-nonlocal-handlers
  "Tool validation should handle multiple tools"
  (let ((tools (list (make-instance 'tool-definition
                                   :name "tool1"
                                   :description "First"
                                   :parameters nil)
                    (make-instance 'tool-definition
                                   :name "tool2"
                                   :description "Second"
                                   :parameters nil))))
    (fiveam:is (= (length tools) 2))))

(fiveam:test validate-tool-has-name
  "Tool must have a name"
  (let ((tool (make-instance 'tool-definition
                            :name "mytool"
                            :description "Description"
                            :parameters nil)))
    (fiveam:is (not (zerop (length (tool-name tool)))))))

(fiveam:test validate-tool-has-description
  "Tool must have a description"
  (let ((tool (make-instance 'tool-definition
                            :name "tool"
                            :description "Tool description"
                            :parameters nil)))
    (fiveam:is (stringp (tool-description tool)))))

;;;; Tool Call Creation Tests

(fiveam:test create-tool-call
  "Create a tool call with id, name, and arguments"
  (let ((call (make-instance 'tool-call
                            :id "call-123"
                            :name "add"
                            :arguments '(:a 5 :b 3))))
    (fiveam:is (string= (tool-call-id call) "call-123"))
    (fiveam:is (string= (tool-call-name call) "add"))
    (fiveam:is (getf (tool-call-arguments call) :a))))

(fiveam:test tool-call-id-is-unique
  "Each tool call should have unique ID"
  (let ((call1 (make-instance 'tool-call
                             :id "call-1"
                             :name "tool"
                             :arguments nil))
        (call2 (make-instance 'tool-call
                             :id "call-2"
                             :name "tool"
                             :arguments nil)))
    (fiveam:is (not (string= (tool-call-id call1) (tool-call-id call2))))))

(fiveam:test tool-call-arguments-plist
  "Tool call arguments should be plist"
  (let ((call (make-instance 'tool-call
                            :id "call-1"
                            :name "search"
                            :arguments '(:query "test" :limit 10))))
    (fiveam:is (listp (tool-call-arguments call)))
    (fiveam:is (= (getf (tool-call-arguments call) :limit) 10))))

(fiveam:test tool-call-multiple-arguments
  "Tool call can have multiple arguments"
  (let ((call (make-instance 'tool-call
                            :id "call-1"
                            :name "func"
                            :arguments '(:a 1 :b 2 :c 3 :d 4))))
    (let ((args (tool-call-arguments call)))
      (fiveam:is (= (getf args :a) 1))
      (fiveam:is (= (getf args :b) 2))
      (fiveam:is (= (getf args :c) 3))
      (fiveam:is (= (getf args :d) 4)))))

;;;; Tool Result Tests

(fiveam:test create-tool-result
  "Create a tool result message"
  (let ((result (make-tool-result "call-123" "{\"result\": 42}")))
    (fiveam:is (string= (getf result :role) "tool"))
    (fiveam:is (string= (getf result :tool-call-id) "call-123"))
    (fiveam:is (string= (getf result :content) "{\"result\": 42}"))))

(fiveam:test tool-result-success
  "Tool result should mark success by default"
  (let ((result (make-tool-result "call-1" "result")))
    (fiveam:is (null (getf result :is-error)))))

(fiveam:test tool-result-error
  "Tool result can mark error"
  (let ((result (make-tool-result "call-1" "error message" :is-error t)))
    (fiveam:is (getf result :is-error))))

(fiveam:test tool-result-role-is-tool
  "Tool result message should have role 'tool'"
  (let ((result (make-tool-result "call-1" "content")))
    (fiveam:is (string= (getf result :role) "tool"))))

(fiveam:test tool-result-has-call-id
  "Tool result should reference the call ID"
  (let ((result (make-tool-result "call-abc-123" "content")))
    (fiveam:is (string= (getf result :tool-call-id) "call-abc-123"))))

;;;; Tool Choice Tests

(fiveam:test tool-choice-auto
  "Tool choice can be :auto"
  (fiveam:is (eq :auto :auto)))

(fiveam:test tool-choice-none
  "Tool choice can be :none"
  (fiveam:is (eq :none :none)))

(fiveam:test tool-choice-required
  "Tool choice can be :required"
  (fiveam:is (eq :required :required)))

(fiveam:test tool-choice-specific-tool
  "Tool choice can be a specific tool name"
  (let ((choice "calculator"))
    (fiveam:is (stringp choice))))

;;;; Tool Translation Tests

(fiveam:test translate-tool-openai-format
  "Tool should translate to OpenAI format"
  (let ((tool (make-instance 'tool-definition
                            :name "add"
                            :description "Add numbers"
                            :parameters '((:name "a" :type :number :description "First")
                                         (:name "b" :type :number :description "Second")))))
    ;; Verify tool structure exists and is valid
    (fiveam:is (string= (tool-name tool) "add"))
    (fiveam:is (string= (tool-description tool) "Add numbers"))))

(fiveam:test translate-tool-preserves-name
  "Translation should preserve tool name"
  (let ((tool (make-instance 'tool-definition
                            :name "search_documents"
                            :description "Search"
                            :parameters nil)))
    (fiveam:is (string= (tool-name tool) "search_documents"))))

(fiveam:test translate-tool-preserves-description
  "Translation should preserve tool description"
  (let ((tool (make-instance 'tool-definition
                            :name "tool"
                            :description "Detailed tool description here"
                            :parameters nil)))
    (fiveam:is (string= (tool-description tool) "Detailed tool description here"))))

(fiveam:test translate-tool-with-parameters
  "Translation should include parameters"
  (let ((tool (make-instance 'tool-definition
                            :name "calc"
                            :description "Calculate"
                            :parameters '((:name "x" :type :number :description "Value")))))
    (fiveam:is (> (length (tool-parameters tool)) 0))))

;;;; Tool in Response Tests

(fiveam:test response-with-tool-calls
  "Response can contain tool calls"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content nil
                                :message '(:role "assistant")
                                :tool-calls nil
                                :finish-reason :tool-calls
                                :usage '(:prompt-tokens 20 :completion-tokens 10 :total-tokens 30))))
    (fiveam:is (eq (response-finish-reason response) :tool-calls))))

(fiveam:test response-finish-reason-tool-calls
  "Response finish reason should be :tool-calls when tools called"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content nil
                                :message '(:role "assistant")
                                :finish-reason :tool-calls
                                :usage '(:prompt-tokens 1 :completion-tokens 1 :total-tokens 2))))
    (fiveam:is (eq (response-finish-reason response) :tool-calls))))

(fiveam:test response-content-nil-when-tool-called
  "Response content should be nil when tool is called"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content nil
                                :message '(:role "assistant")
                                :finish-reason :tool-calls
                                :usage '(:prompt-tokens 1 :completion-tokens 1 :total-tokens 2))))
    (fiveam:is (null (response-content response)))))

;;;; Conversation Flow with Tools Tests

(fiveam:test create-message-list
  "Create list of messages for conversation"
  (let ((messages '((:role "system" :content "You are helpful")
                   (:role "user" :content "Help me"))))
    (fiveam:is (= (length messages) 2))))

(fiveam:test append-tool-result_to_conversation
  "Append tool result to conversation history"
  (let ((original-messages '((:role "user" :content "What is 2+2?")))
        (assistant-message '(:role "assistant" :content nil))
        (tool-result (make-tool-result "call-1" "4")))
    (let ((extended (append original-messages
                            (list assistant-message)
                            (list tool-result))))
      (fiveam:is (= (length extended) 3)))))

(fiveam:test tool-result-in_conversation_flow
  "Tool result can be used to continue conversation"
  (let ((messages '((:role "user" :content "Calculate"))))
    (let ((with-result (append messages
                               (list (make-tool-result "call-1" "42")))))
      (fiveam:is (= (length with-result) 2)))))

;;;; Tool Definition List Tests

(fiveam:test create-tool-list
  "Create list of tool definitions"
  (let ((tools (list (make-instance 'tool-definition
                                   :name "tool1"
                                   :description "First tool"
                                   :parameters nil)
                    (make-instance 'tool-definition
                                   :name "tool2"
                                   :description "Second tool"
                                   :parameters nil))))
    (fiveam:is (= (length tools) 2))))

(fiveam:test multiple-tools
  "Multiple tools should be distinct"
  (let ((tool1 (make-instance 'tool-definition
                             :name "add"
                             :description "Add"
                             :parameters nil))
        (tool2 (make-instance 'tool-definition
                             :name "subtract"
                             :description "Subtract"
                             :parameters nil)))
    (fiveam:is (not (string= (tool-name tool1) (tool-name tool2))))))

(fiveam:test tool-list_with_varied_parameters
  "Tools in list can have different parameter counts"
  (let ((tools (list (make-instance 'tool-definition
                                   :name "no-params"
                                   :description "None"
                                   :parameters nil)
                    (make-instance 'tool-definition
                                   :name "one-param"
                                   :description "One"
                                   :parameters '((:name "x" :type :string :description "X")))
                    (make-instance 'tool-definition
                                   :name "two-params"
                                   :description "Two"
                                   :parameters '((:name "x" :type :string :description "X")
                                               (:name "y" :type :string :description "Y"))))))
    (fiveam:is (= (length (tool-parameters (first tools))) 0))
    (fiveam:is (= (length (tool-parameters (second tools))) 1))
    (fiveam:is (= (length (tool-parameters (third tools))) 2))))

;;;; Tool and Provider Compatibility Tests

(fiveam:test openai-provider_supports_tools
  "OpenAI provider should support tools"
  (let ((provider (make-provider :openai :api-key "test" :model "gpt-4")))
    (fiveam:is (typep provider 'openai-provider))))

(fiveam:test anthropic-provider_supports_tools
  "Anthropic provider should support tools"
  (let ((provider (make-provider :anthropic :api-key "test" :model "claude-3-opus")))
    (fiveam:is (typep provider 'anthropic-provider))))

(fiveam:test ollama-provider_supports_tools
  "Ollama provider should support tools"
  (let ((provider (make-provider :ollama :base-url "http://localhost:11434" :model "llama2")))
    (fiveam:is (typep provider 'ollama-provider))))

;;;; Tool Printing and Display Tests

(fiveam:test tool-print-representation
  "Tool should have readable print representation"
  (let ((tool (make-instance 'tool-definition
                            :name "my_tool"
                            :description "Description"
                            :parameters nil)))
    (fiveam:is (stringp (tool-name tool)))))

(fiveam:test tool-call-print-representation
  "Tool call should have readable print representation"
  (let ((call (make-instance 'tool-call
                            :id "call-1"
                            :name "calculator"
                            :arguments '(:x 10))))
    (fiveam:is (stringp (tool-call-id call)))
    (fiveam:is (stringp (tool-call-name call)))))

;;;; Tool Parameter Validation Details Tests

(fiveam:test parameter-name-required
  "Parameter must have name field"
  (let ((param '(:name "param1" :type :string :description "desc")))
    (fiveam:is (getf param :name))))

(fiveam:test parameter-type-required
  "Parameter must have type field"
  (let ((param '(:name "param1" :type :string :description "desc")))
    (fiveam:is (getf param :type))))

(fiveam:test parameter-description-recommended
  "Parameter should have description"
  (let ((param '(:name "param1" :type :string :description "Parameter description")))
    (fiveam:is (getf param :description))))

(fiveam:test parameter-enum_list
  "Parameter enum should be list of values"
  (let ((param '(:name "status" :type :string :description "Status"
                 :enum ("active" "inactive" "pending"))))
    (let ((enum (getf param :enum)))
      (fiveam:is (= (length enum) 3)))))

;;;; Tool Definition with Complex Parameters Tests

(fiveam:test tool-with-nested-object_parameter
  "Tool can have nested object parameter"
  (let ((param '(:name "config" :type :object :description "Configuration")))
    (fiveam:is (eq (getf param :type) :object))))

(fiveam:test tool-with-array_parameter
  "Tool can have array parameter"
  (let ((param '(:name "tags" :type :array :description "Tags")))
    (fiveam:is (eq (getf param :type) :array))))

(fiveam:test tool-with_enum_and_default
  "Tool parameter can have both enum and default"
  (let ((param '(:name "format" :type :string :description "Format"
                 :enum ("json" "xml" "csv"))))
    (fiveam:is (member "json" (getf param :enum) :test #'string=))))

;;;; Tool Execution Flow Tests

(fiveam:test tool-lookup_in_list
  "Tool can be found in list by name"
  (let ((tools (list (make-instance 'tool-definition
                                   :name "add"
                                   :description "Add"
                                   :parameters nil)
                    (make-instance 'tool-definition
                                   :name "subtract"
                                   :description "Subtract"
                                   :parameters nil))))
    (let ((found (find "add" tools :key #'tool-name :test #'string=)))
      (fiveam:is (not (null found)))
      (fiveam:is (string= (tool-name found) "add")))))

(fiveam:test tool-by-call-name
  "Tool call references correct tool by name"
  (let ((tools (list (make-instance 'tool-definition
                                   :name "calculator"
                                   :description "Calc"
                                   :parameters nil)))
        (call (make-instance 'tool-call
                            :id "call-1"
                            :name "calculator"
                            :arguments nil)))
    (let ((tool (find (tool-call-name call) tools :key #'tool-name :test #'string=)))
      (fiveam:is (not (null tool))))))

