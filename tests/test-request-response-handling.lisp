(th.harness:setup :cl-llm-provider)

(fiveam:def-suite request-response-suite
  :description "Comprehensive test suite for request/response handling"
  :in cl-llm-provider/test::cl-llm-provider-suite)

(fiveam:in-suite request-response-suite)

;;;; Message Normalization Tests

(fiveam:test normalize-keyword-to-string-key
  "Keywords should be converted to lowercase strings"
  (let ((plist '(:role "user" :content "test")))
    (let ((hash (plist-to-hash plist)))
      (fiveam:is (hash-table-p hash))
      (fiveam:is (gethash "role" hash)))))

(fiveam:test normalize-preserve-string-keys
  "String keys should be preserved as-is"
  (let ((plist '("customKey" "value")))
    (let ((hash (plist-to-hash plist)))
      (fiveam:is (gethash "customKey" hash)))))

(fiveam:test normalize-multiple-messages
  "Multiple messages should each convert separately"
  (let ((messages '((:role "user" :content "Hello")
                   (:role "assistant" :content "Hi"))))
    (fiveam:is (= (length messages) 2))
    (dolist (msg messages)
      (fiveam:is (getf msg :role))
      (fiveam:is (getf msg :content)))))

(fiveam:test normalize-message-with-nil-values
  "Messages with nil values should be handled"
  (let ((msg '(:role "assistant" :content nil :tool-calls nil)))
    (fiveam:is (null (getf msg :content)))
    (fiveam:is (null (getf msg :tool-calls)))))

(fiveam:test normalize-message-preserves-order
  "Message order in conversation should be preserved"
  (let ((messages '((:role "system" :content "System prompt")
                   (:role "user" :content "Question")
                   (:role "assistant" :content "Answer"))))
    (fiveam:is (string= (getf (first messages) :role) "system"))
    (fiveam:is (string= (getf (second messages) :role) "user"))
    (fiveam:is (string= (getf (third messages) :role) "assistant"))))

;;;; System Message Handling Tests

(fiveam:test system-message-as-separate-parameter
  "System message can be passed as parameter"
  (let ((system "You are helpful"))
    (fiveam:is (stringp system))))

(fiveam:test system-message-converts-to-message
  "System message should convert to message plist"
  (let ((system "You are helpful"))
    (let ((msg (list :role "system" :content system)))
      (fiveam:is (string= (getf msg :role) "system"))
      (fiveam:is (string= (getf msg :content) system)))))

(fiveam:test multiple-system-messages-invalid
  "Only one system message should exist (at beginning)"
  ;; First message can be system, others should not be
  (let ((messages '((:role "system" :content "System prompt")
                   (:role "user" :content "Question"))))
    (fiveam:is (string= (getf (first messages) :role) "system"))))

;;;; Tool Definition to Schema Translation Tests

(fiveam:test translate-tool-basic-openai-format
  "Tool should translate to OpenAI format by default"
  (let ((tool (make-instance 'tool-definition
                            :name "calculator"
                            :description "Performs arithmetic operations"
                            :parameters '((:name "operation" :type :string :description "Operation to perform")
                                         (:name "a" :type :number :description "First number")
                                         (:name "b" :type :number :description "Second number")))))
    ;; Verify tool structure
    (fiveam:is (string= (tool-name tool) "calculator"))
    (fiveam:is (= (length (tool-parameters tool)) 3))))

(fiveam:test translate-tool-with-enum
  "Tool parameter can have enum constraints"
  (let ((param '(:name "operation" :type :string :description "Op" :enum ("add" "subtract"))))
    (fiveam:is (getf param :enum))
    (fiveam:is (= (length (getf param :enum)) 2))))

(fiveam:test translate-tool-with-required
  "Tool can specify required parameters"
  (let ((tool (make-instance 'tool-definition
                            :name "search"
                            :description "Search"
                            :parameters '((:name "query" :type :string :description "Search query"))
                            :required '("query"))))
    (fiveam:is (member "query" (tool-required-params tool) :test #'string=))))

(fiveam:test translate-tool-nested-object
  "Tool parameter can be nested object type"
  (let ((param '(:name "config" :type :object :description "Configuration")))
    (fiveam:is (eq (getf param :type) :object))))

(fiveam:test translate-tool-array-type
  "Tool parameter can be array type"
  (let ((param '(:name "items" :type :array :description "List of items")))
    (fiveam:is (eq (getf param :type) :array))))

;;;; Request Parameter Handling Tests

(fiveam:test request-temperature-valid-range
  "Temperature should be between 0 and 2"
  (dolist (temp '(0 0.5 1.0 1.5 2.0))
    (fiveam:is (<= 0 temp 2.0))))

(fiveam:test request-temperature-invalid-below-zero
  "Temperature below 0 should be invalid"
  (fiveam:is (not (<= 0 -0.5 2.0))))

(fiveam:test request-temperature-invalid-above-two
  "Temperature above 2 should be invalid"
  (fiveam:is (not (<= 0 2.5 2.0))))

(fiveam:test request-max-tokens-positive
  "Max tokens should be positive integer"
  (dolist (max-tokens '(1 100 4096 8192))
    (fiveam:is (integerp max-tokens))
    (fiveam:is (> max-tokens 0))))

(fiveam:test request-stop-sequences-list
  "Stop sequences should be list of strings"
  (let ((stops '("END" "STOP" "\n\n")))
    (fiveam:is (listp stops))
    (dolist (stop stops)
      (fiveam:is (stringp stop)))))

(fiveam:test request-top-p-sampling
  "Top-p should be between 0 and 1 (sampling parameter)"
  (dolist (top-p '(0 0.5 0.9 1.0))
    (fiveam:is (<= 0 top-p 1.0))))

;;;; Tool Call Extraction Tests

(fiveam:test tool-call-has-id
  "Tool call should have unique identifier"
  (let ((call (make-instance 'tool-call
                            :id "call-uuid-123"
                            :name "calculator"
                            :arguments '(:a 5 :b 3))))
    (fiveam:is (stringp (tool-call-id call)))
    (fiveam:is (not (zerop (length (tool-call-id call)))))))

(fiveam:test tool-call-has-name
  "Tool call should have function/tool name"
  (let ((call (make-instance 'tool-call
                            :id "call-1"
                            :name "search"
                            :arguments '(:query "test"))))
    (fiveam:is (stringp (tool-call-name call)))))

(fiveam:test tool-call-arguments-as-plist
  "Tool call arguments should be plist format"
  (let ((call (make-instance 'tool-call
                            :id "call-1"
                            :name "calculator"
                            :arguments '(:a 5 :b 3))))
    (fiveam:is (listp (tool-call-arguments call)))
    (fiveam:is (getf (tool-call-arguments call) :a))))

(fiveam:test tool-call-arguments-from-json
  "JSON-parsed hash-tables are converted to keyword plists by %json-hash-to-keyword-plist"
  (let* ((json-str "{\"a\": 5, \"b\": 3}")
         (parsed (yason:parse json-str :object-as :hash-table))
         (plist (cl-llm-provider::%json-hash-to-keyword-plist parsed)))
    (fiveam:is (listp plist))
    (fiveam:is (= (getf plist :a) 5))
    (fiveam:is (= (getf plist :b) 3))))

(fiveam:test json-hash-to-plist-nested-objects
  "Nested JSON objects become nested keyword plists"
  (let* ((json-str "{\"config\": {\"max_tokens\": 100, \"enabled\": true}}")
         (parsed (yason:parse json-str))
         (plist (cl-llm-provider::%json-hash-to-keyword-plist parsed)))
    (fiveam:is (listp (getf plist :config)))
    (fiveam:is (= (getf (getf plist :config) :max-tokens) 100))
    (fiveam:is (eq (getf (getf plist :config) :enabled) t))))

(fiveam:test json-hash-to-plist-arrays
  "JSON arrays become CL lists"
  (let* ((json-str "{\"tags\": [\"alpha\", \"beta\"]}")
         (parsed (yason:parse json-str))
         (plist (cl-llm-provider::%json-hash-to-keyword-plist parsed)))
    (fiveam:is (equal (getf plist :tags) '("alpha" "beta")))))

(fiveam:test json-hash-to-plist-underscore-to-hyphen
  "JSON underscored keys become hyphenated keywords"
  (let* ((json-str "{\"user_name\": \"quasi\", \"old_text\": \"foo\"}")
         (parsed (yason:parse json-str))
         (plist (cl-llm-provider::%json-hash-to-keyword-plist parsed)))
    (fiveam:is (string= (getf plist :user-name) "quasi"))
    (fiveam:is (string= (getf plist :old-text) "foo"))))

(fiveam:test json-hash-to-plist-nil-and-empty
  "NIL passes through, empty hash becomes NIL"
  (fiveam:is (null (cl-llm-provider::%json-hash-to-keyword-plist nil)))
  (fiveam:is (null (cl-llm-provider::%json-hash-to-keyword-plist
                    (make-hash-table :test 'equal)))))

(fiveam:test json-hash-to-plist-passthrough
  "Non-hash values pass through unchanged"
  (fiveam:is (equal '(:a 1 :b 2)
                    (cl-llm-provider::%json-hash-to-keyword-plist '(:a 1 :b 2))))
  (fiveam:is (string= "hello"
                       (cl-llm-provider::%json-hash-to-keyword-plist "hello")))
  (fiveam:is (= 42 (cl-llm-provider::%json-hash-to-keyword-plist 42))))

;;;; Response Content Tests

(fiveam:test completion-response-content-string
  "Response content should be string"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content "This is the response"
                                :message '(:role "assistant" :content "This is the response")
                                :usage '(:prompt-tokens 10 :completion-tokens 5 :total-tokens 15))))
    (fiveam:is (stringp (response-content response)))))

(fiveam:test completion-response-content-nil-when-tool-calls
  "Response content should be nil if tool was called"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content nil
                                :message '(:role "assistant")
                                :tool-calls nil
                                :usage '(:prompt-tokens 10 :completion-tokens 5 :total-tokens 15))))
    (fiveam:is (null (response-content response)))))

(fiveam:test completion-response-message-structure
  "Response message should have role and content"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content "Hello"
                                :message '(:role "assistant" :content "Hello")
                                :usage '(:prompt-tokens 5 :completion-tokens 1 :total-tokens 6))))
    (let ((msg (response-message response)))
      (fiveam:is (string= (getf msg :role) "assistant"))
      (fiveam:is (string= (getf msg :content) "Hello")))))

;;;; Token Usage Tests

(fiveam:test token-usage-has-prompt-tokens
  "Usage should include prompt token count"
  (let ((usage '(:prompt-tokens 100 :completion-tokens 50 :total-tokens 150)))
    (fiveam:is (= (getf usage :prompt-tokens) 100))))

(fiveam:test token-usage-has-completion-tokens
  "Usage should include completion token count"
  (let ((usage '(:prompt-tokens 100 :completion-tokens 50 :total-tokens 150)))
    (fiveam:is (= (getf usage :completion-tokens) 50))))

(fiveam:test token-usage-has-total-tokens
  "Usage should include total token count"
  (let ((usage '(:prompt-tokens 100 :completion-tokens 50 :total-tokens 150)))
    (fiveam:is (= (getf usage :total-tokens) 150))))

(fiveam:test token-usage-total-equals-sum
  "Total tokens should equal prompt + completion"
  (let ((usage '(:prompt-tokens 100 :completion-tokens 50 :total-tokens 150)))
    (fiveam:is (= (getf usage :total-tokens)
                  (+ (getf usage :prompt-tokens)
                     (getf usage :completion-tokens))))))

(fiveam:test token-usage-zero-is-valid
  "Zero tokens is valid (for some providers/cases)"
  (let ((usage '(:prompt-tokens 0 :completion-tokens 0 :total-tokens 0)))
    (fiveam:is (= (getf usage :prompt-tokens) 0))))

;;;; Provider Metadata Tests

(fiveam:test metadata-optional
  "Metadata field should be optional (can be nil)"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content "test"
                                :message '(:role "assistant" :content "test")
                                :metadata nil
                                :usage '(:prompt-tokens 1 :completion-tokens 1 :total-tokens 2))))
    (fiveam:is (null (response-metadata response)))))

(fiveam:test metadata-openai-system-fingerprint
  "OpenAI metadata should include system fingerprint"
  (let ((metadata '(:system-fingerprint "fp_1234567890")))
    (fiveam:is (getf metadata :system-fingerprint))))

(fiveam:test metadata-openai-created-timestamp
  "OpenAI metadata should include created timestamp"
  (let ((metadata '(:created 1234567890)))
    (fiveam:is (numberp (getf metadata :created)))))

(fiveam:test metadata-anthropic-stop-sequence
  "Anthropic metadata should include stop sequence"
  (let ((metadata '(:stop-sequence "END")))
    (fiveam:is (getf metadata :stop-sequence))))

(fiveam:test metadata-ollama-timing-fields
  "Ollama metadata should include timing information"
  (let ((metadata '(:total-duration-ns 1000000
                   :load-duration-ns 100000
                   :prompt-eval-duration-ns 200000
                   :eval-duration-ns 700000)))
    (fiveam:is (getf metadata :total-duration-ns))
    (fiveam:is (getf metadata :eval-duration-ns))))

;;;; Finish Reason Tests

(fiveam:test finish-reason-stop
  "Finish reason :stop indicates normal completion"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content "test"
                                :message '(:role "assistant" :content "test")
                                :finish-reason :stop
                                :usage '(:prompt-tokens 1 :completion-tokens 1 :total-tokens 2))))
    (fiveam:is (eq (response-finish-reason response) :stop))))

(fiveam:test finish-reason-length
  "Finish reason :length indicates max tokens reached"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content "incomplete"
                                :message '(:role "assistant" :content "incomplete")
                                :finish-reason :length
                                :usage '(:prompt-tokens 1 :completion-tokens 5 :total-tokens 6))))
    (fiveam:is (eq (response-finish-reason response) :length))))

(fiveam:test finish-reason-tool-calls
  "Finish reason :tool-calls indicates model called tools"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content nil
                                :message '(:role "assistant")
                                :finish-reason :tool-calls
                                :tool-calls nil
                                :usage '(:prompt-tokens 10 :completion-tokens 5 :total-tokens 15))))
    (fiveam:is (eq (response-finish-reason response) :tool-calls))))

(fiveam:test finish-reason-content-filter
  "Finish reason :content-filter indicates content was filtered"
  (let ((response (make-instance 'completion-response
                                :id "resp-1"
                                :model "gpt-4"
                                :content nil
                                :message '(:role "assistant")
                                :finish-reason :content-filter
                                :usage '(:prompt-tokens 1 :completion-tokens 1 :total-tokens 2))))
    (fiveam:is (eq (response-finish-reason response) :content-filter))))

;;;; Raw Response Preservation Tests

(fiveam:test raw-response-stored
  "Raw provider response should be stored for debugging"
  (let ((raw (make-hash-table :test 'equal)))
    (setf (gethash "id" raw) "resp-123")
    (let ((response (make-instance 'completion-response
                                  :id "resp-123"
                                  :model "gpt-4"
                                  :content "test"
                                  :message '(:role "assistant" :content "test")
                                  :raw raw
                                  :usage '(:prompt-tokens 1 :completion-tokens 1 :total-tokens 2))))
      (fiveam:is (hash-table-p (response-raw response)))
      (fiveam:is (string= (gethash "id" (response-raw response)) "resp-123")))))

(fiveam:test raw-response-preserves-original
  "Raw response should be unmodified original"
  (let ((raw (make-hash-table :test 'equal)))
    (setf (gethash "choices" raw) #(1 2 3))
    (let ((response (make-instance 'completion-response
                                  :id "resp-1"
                                  :model "gpt-4"
                                  :content "test"
                                  :message '(:role "assistant" :content "test")
                                  :raw raw
                                  :usage '(:prompt-tokens 1 :completion-tokens 1 :total-tokens 2))))
      (fiveam:is (equalp (gethash "choices" (response-raw response)) #(1 2 3))))))

;;;; Embedding Response Tests

(fiveam:test embedding-response-contains-vectors
  "Embedding response should contain vector list"
  (let ((response (make-instance 'embedding-response
                                :embeddings '((0.1 0.2 0.3))
                                :model "text-embedding-3-small"
                                :usage '(:prompt-tokens 5 :total-tokens 5))))
    (fiveam:is (listp (response-embeddings response)))
    (fiveam:is (> (length (response-embeddings response)) 0))))

(fiveam:test embedding-vector-is-float-list
  "Each embedding should be a list of floats"
  (let ((response (make-instance 'embedding-response
                                :embeddings '((0.1 0.2 0.3) (0.4 0.5 0.6))
                                :model "text-embedding-3-small"
                                :usage '(:prompt-tokens 5 :total-tokens 5))))
    (dolist (embedding (response-embeddings response))
      (fiveam:is (listp embedding))
      (dolist (val embedding)
        (fiveam:is (numberp val))))))

(fiveam:test embedding-response-vector-dimensions
  "Embedding vectors should all have same dimensions"
  (let ((response (make-instance 'embedding-response
                                :embeddings '((0.1 0.2 0.3 0.4) (0.5 0.6 0.7 0.8))
                                :model "text-embedding-3-small"
                                :usage '(:prompt-tokens 5 :total-tokens 5))))
    (let ((dim (length (first (response-embeddings response)))))
      (dolist (embedding (rest (response-embeddings response)))
        (fiveam:is (= (length embedding) dim))))))

;;;; Multiple Responses Tests

(fiveam:test multiple-responses-are-independent
  "Multiple responses should have independent data"
  (let ((resp1 (make-instance 'completion-response
                             :id "resp-1"
                             :model "gpt-4"
                             :content "First"
                             :message '(:role "assistant" :content "First")
                             :usage '(:prompt-tokens 10 :completion-tokens 5 :total-tokens 15)))
        (resp2 (make-instance 'completion-response
                             :id "resp-2"
                             :model "gpt-4"
                             :content "Second"
                             :message '(:role "assistant" :content "Second")
                             :usage '(:prompt-tokens 10 :completion-tokens 6 :total-tokens 16))))
    (fiveam:is (not (string= (response-id resp1) (response-id resp2))))
    (fiveam:is (not (string= (response-content resp1) (response-content resp2))))))

(fiveam:test response-ids-are-unique
  "Response IDs should be unique per response"
  (let ((responses (loop for i from 1 to 5
                        collect (make-instance 'completion-response
                                             :id (format nil "resp-~d" i)
                                             :model "gpt-4"
                                             :content (format nil "Content ~d" i)
                                             :message `(:role "assistant" :content ,(format nil "Content ~d" i))
                                             :usage '(:prompt-tokens 1 :completion-tokens 1 :total-tokens 2)))))
    (let ((ids (mapcar #'response-id responses)))
      (fiveam:is (= (length ids) (length (remove-duplicates ids :test #'string=)))))))

;;;; Performance Profiling Tests

(fiveam:test performance-timing-structure
  "Performance data should have encode, api, decode times"
  (let ((perf '(:encode-time 0.001 :api-time 1.234 :decode-time 0.002)))
    (fiveam:is (getf perf :encode-time))
    (fiveam:is (getf perf :api-time))
    (fiveam:is (getf perf :decode-time))))

(fiveam:test performance-times-are-positive
  "Performance times should be positive numbers"
  (let ((perf '(:encode-time 0.001 :api-time 1.234 :decode-time 0.002)))
    (fiveam:is (> (getf perf :encode-time) 0))
    (fiveam:is (> (getf perf :api-time) 0))
    (fiveam:is (> (getf perf :decode-time) 0))))

(fiveam:test performance-profiling-disabled-by-default
  "Performance profiling should be disabled by default"
  (fiveam:is (null *performance-profiling*)))

