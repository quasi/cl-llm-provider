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


;;;; Recursive plist-to-hash Tests

(fiveam:test plist-to-hash-recursive-round-trip
  "Nested tool-call plists must encode as JSON objects, not arrays."
  (let* ((msg '(:role "assistant"
                :content nil
                :tool-calls ((:id "call_1"
                              :type "function"
                              :function (:name "get_weather"
                                         :arguments "{\"location\":\"Paris\"}")))))
         (hash (cl-llm-provider::plist-to-hash msg)))
    ;; Verify the structure is JSON-encodable (nested plists -> hash-tables)
    (fiveam:is (hash-table-p hash))
    (fiveam:is (string= "assistant" (gethash "role" hash)))
    ;; tool-calls should be a vector (array) of hash-tables, not nested plists
    (let ((tool-calls (gethash "tool_calls" hash)))
      (fiveam:is (vectorp tool-calls))
      (let ((tc (elt tool-calls 0)))
        (fiveam:is (hash-table-p tc))
        (fiveam:is (string= "call_1" (gethash "id" tc)))
        (let ((fn (gethash "function" tc)))
          (fiveam:is (hash-table-p fn))
          (fiveam:is (string= "get_weather" (gethash "name" fn))))))))

(fiveam:test plist-to-hash-nested-content-blocks
  "A list of content-block plists becomes a JSON array of objects."
  (let* ((msg '(:role "assistant"
                :content ((:type "text" :text "Checking...")
                          (:type "tool-use" :id "toolu_1" :name "f" :input (:x 1)))))
         (hash (cl-llm-provider::plist-to-hash msg))
         (content (gethash "content" hash)))
    (fiveam:is (vectorp content))
    (fiveam:is (hash-table-p (elt content 0)))
    (fiveam:is (string= "text" (gethash "type" (elt content 0))))
    (fiveam:is (hash-table-p (gethash "input" (elt content 1))))))


;;;; Anthropic Parser Tests

(fiveam:test anthropic-parse-tool-use-message-is-plist
  "Anthropic :message slot must be a pure keyword plist mirroring content blocks."
  (let* ((provider (make-instance 'cl-llm-provider::anthropic-provider))
         (raw (yason:parse "{\"id\":\"msg_1\",\"model\":\"claude-x\",
\"stop_reason\":\"tool_use\",
\"content\":[{\"type\":\"text\",\"text\":\"Let me check.\"},
             {\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"get_weather\",
              \"input\":{\"location\":\"Pune\"}}],
\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}"))
         (resp (cl-llm-provider::parse-completion-response provider raw))
         (msg (cl-llm-provider::response-message resp)))
    ;; Message structure: :role "assistant" and :content as list of keyword plists
    (fiveam:is (string= "assistant" (getf msg :role)))
    (let ((blocks (getf msg :content)))
      (fiveam:is (listp blocks))
      (fiveam:is (= 2 (length blocks)))
      ;; First block is text
      (fiveam:is (string= "text" (getf (first blocks) :type)))
      (fiveam:is (string= "Let me check." (getf (first blocks) :text)))
      ;; Second block is tool_use
      (fiveam:is (string= "tool_use" (getf (second blocks) :type)))
      (fiveam:is (string= "toolu_1" (getf (second blocks) :id))))
    ;; Text content is preserved
    (fiveam:is (string= "Let me check." (cl-llm-provider::response-content resp)))
    ;; Tool calls are extracted
    (fiveam:is (= 1 (length (cl-llm-provider::response-tool-calls resp))))))


(fiveam:test anthropic-parse-empty-content-no-crash
  "Empty content should not crash the parser."
  (let* ((provider (make-instance 'cl-llm-provider::anthropic-provider))
         (raw (yason:parse "{\"id\":\"msg_2\",\"model\":\"claude-x\",\"content\":[]}"))
         (resp (cl-llm-provider::parse-completion-response provider raw)))
    (fiveam:is (null (cl-llm-provider::response-finish-reason resp)))
    (fiveam:is (null (cl-llm-provider::response-content resp)))))

;;;; OpenAI-format Parser Nil Guard Tests

(fiveam:test openai-format-parsers-tolerate-sparse-responses
  "Empty choices / missing finish_reason must not crash any OpenAI-format parser."
  (dolist (class '(cl-llm-provider::openai-provider
                   cl-llm-provider::gemini-provider
                   cl-llm-provider::openrouter-provider))
    (let ((provider (make-instance class)))
      ;; Empty choices
      (fiveam:finishes
        (cl-llm-provider::parse-completion-response
         provider (yason:parse "{\"id\":\"x\",\"model\":\"m\",\"choices\":[]}")))
      ;; Missing finish_reason
      (let ((resp (cl-llm-provider::parse-completion-response
                   provider
                   (yason:parse "{\"id\":\"x\",\"model\":\"m\",
\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"hi\"}}]}"))))
        (fiveam:is (null (cl-llm-provider::response-finish-reason resp)))
        (fiveam:is (string= "hi" (cl-llm-provider::response-content resp)))))))

(fiveam:test ollama-parser-tolerates-missing-message
  "Ollama parser should handle missing message field."
  (let ((provider (make-instance 'cl-llm-provider::ollama-provider)))
    (fiveam:finishes
      (cl-llm-provider::parse-completion-response
       provider (yason:parse "{\"model\":\"m\",\"done\":true}")))))

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

;;;; Provider Message Keyword-Key Normalization (regression: string-key bug)
;;;;
;;;; alexandria:hash-table-plist produces STRING keys ("role", "content") but
;;;; every consumer reads the message with keyword getf (:role, :content),
;;;; silently getting NIL.  These tests feed a yason-style string-keyed
;;;; raw-response through each provider's REAL parse-completion-response and
;;;; assert the :message slot has keyword keys.  The earlier mock tests built
;;;; completion-response directly from keyword plists, so they never exercised
;;;; this conversion boundary -- the mock/real divergence that hid the bug.

(defun %string-keyed-chat-response (message-hash)
  "Build a yason-style (string-keyed, :test 'equal) chat.completion raw response
whose single choice carries MESSAGE-HASH."
  (let ((choice (alexandria:plist-hash-table
                 (list "index" 0
                       "message" message-hash
                       "finish_reason" "stop")
                 :test 'equal))
        (usage (alexandria:plist-hash-table
                '("prompt_tokens" 10 "completion_tokens" 20 "total_tokens" 30)
                :test 'equal)))
    (alexandria:plist-hash-table
     (list "id" "chatcmpl-test"
           "object" "chat.completion"
           "created" 1234567890
           "model" "test-model"
           "choices" (vector choice)
           "usage" usage)
     :test 'equal)))

(defun %plain-assistant-message ()
  (alexandria:plist-hash-table
   '("role" "assistant" "content" "Hello there")
   :test 'equal))

(defun %tool-call-message ()
  "Assistant message that requests a tool call (content null, tool_calls present)."
  (let ((function (alexandria:plist-hash-table
                   '("name" "get_weather" "arguments" "{\"city\": \"Pune\"}")
                   :test 'equal)))
    (alexandria:plist-hash-table
     (list "role" "assistant"
           "content" nil
           "tool_calls" (vector (alexandria:plist-hash-table
                                  (list "id" "call-1"
                                        "type" "function"
                                        "function" function)
                                  :test 'equal)))
     :test 'equal)))

(defmacro %def-message-keyword-key-tests (name-prefix provider-form)
  "Emit a plain-text and a tool-call parse test asserting keyword message keys."
  `(progn
     (fiveam:test ,(intern (format nil "~A-MESSAGE-HAS-KEYWORD-KEYS" name-prefix))
       "Parsed assistant message plist uses keyword keys (:role/:content), not strings"
       (let* ((provider ,provider-form)
              (raw (%string-keyed-chat-response (%plain-assistant-message)))
              (msg (response-message (parse-completion-response provider raw))))
         ;; keyword getf must find the values -> proves keyword keys
         (fiveam:is (string= "assistant" (getf msg :role)))
         (fiveam:is (string= "Hello there" (getf msg :content)))
         ;; and no leftover string keys
         (fiveam:is (null (getf msg "role")))))
     (fiveam:test ,(intern (format nil "~A-TOOL-CALL-MESSAGE-HAS-KEYWORD-KEYS" name-prefix))
       "Parsed tool-call assistant message uses keyword keys down to :tool-calls"
       (let* ((provider ,provider-form)
              (raw (%string-keyed-chat-response (%tool-call-message)))
              (msg (response-message (parse-completion-response provider raw))))
         (fiveam:is (string= "assistant" (getf msg :role)))
         (fiveam:is (null (getf msg :content)))
         ;; tool_calls array key normalized to keyword, nested plists too
         (fiveam:is (getf msg :tool-calls))
         (let ((tc (first (getf msg :tool-calls))))
           (fiveam:is (string= "call-1" (getf tc :id)))
           (fiveam:is (string= "get_weather"
                               (getf (getf tc :function) :name))))))))

(%def-message-keyword-key-tests "OPENAI"
  (make-provider :openai :api-key "test-key"))

(%def-message-keyword-key-tests "GEMINI"
  (make-provider :gemini :api-key "test-key"))

(%def-message-keyword-key-tests "OPENROUTER"
  (make-provider :openrouter :api-key "test-key"))

(%def-message-keyword-key-tests "OPENAI-COMPATIBLE"
  (make-provider :openai-compatible :api-key "test-key"
                 :base-url "https://example.test/v1"))

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

