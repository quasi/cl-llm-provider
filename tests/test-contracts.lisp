;;; ABOUTME: Contract tests for cl-llm-provider using cl-test-hardening/contract
;;; Defines response schemas for each provider and validates parse-completion-response.

(th.harness:setup :cl-llm-provider)

(in-package :cl-llm-provider)

(fiveam:def-suite contract-suite
  :description "Contract-based response validation tests"
  :in cl-llm-provider/test::cl-llm-provider-suite)

(fiveam:in-suite contract-suite)

;;;; Response Schemas

(th.contract:defschema openai-completion-response
  (:id (type-of string))
  (:model (type-of string))
  (:choices (array-of (object-with
                       :message (object-with
                                 :role (one-of "assistant")
                                 :content (any-value))
                       :finish_reason (one-of "stop" "length" "tool_calls" "content_filter")
                       :index (type-of integer))))
  (:usage (object-with
           :prompt_tokens (type-of integer)
           :completion_tokens (type-of integer)
           :total_tokens (type-of integer))))

(th.contract:defschema anthropic-completion-response
  (:id (type-of string))
  (:model (type-of string))
  (:type (one-of "message"))
  (:role (one-of "assistant"))
  (:content (array-of (object-with
                       :type (one-of "text" "tool_use"))))
  (:stop_reason (one-of "end_turn" "max_tokens" "stop_sequence" "tool_use"))
  (:usage (object-with
           :input_tokens (type-of integer)
           :output_tokens (type-of integer))))

(th.contract:defschema ollama-chat-response
  (:model (type-of string))
  (:message (object-with
             :role (one-of "assistant")
             :content (type-of string))))

;;;; Schema validation helpers

(defun make-openai-response (&key (content "Hello") (model "gpt-4")
                                   (id "chatcmpl-123") (finish-reason "stop")
                                   (prompt-tokens 10) (completion-tokens 5))
  "Build an OpenAI-format raw response hash-table."
  (let ((raw (make-hash-table :test 'equal))
        (choice (make-hash-table :test 'equal))
        (message (make-hash-table :test 'equal))
        (usage (make-hash-table :test 'equal)))
    (setf (gethash "role" message) "assistant"
          (gethash "content" message) content)
    (setf (gethash "message" choice) message
          (gethash "finish_reason" choice) finish-reason
          (gethash "index" choice) 0)
    (setf (gethash "id" raw) id
          (gethash "model" raw) model
          (gethash "choices" raw) (vector choice))
    (setf (gethash "prompt_tokens" usage) prompt-tokens
          (gethash "completion_tokens" usage) completion-tokens
          (gethash "total_tokens" usage) (+ prompt-tokens completion-tokens))
    (setf (gethash "usage" raw) usage)
    raw))

(defun make-anthropic-response (&key (content "Hello") (model "claude-3-opus-20240229")
                                      (id "msg_123") (stop-reason "end_turn")
                                      (input-tokens 10) (output-tokens 5))
  "Build an Anthropic-format raw response hash-table."
  (let ((raw (make-hash-table :test 'equal))
        (content-block (make-hash-table :test 'equal))
        (usage (make-hash-table :test 'equal)))
    (setf (gethash "type" content-block) "text"
          (gethash "text" content-block) content)
    (setf (gethash "id" raw) id
          (gethash "model" raw) model
          (gethash "type" raw) "message"
          (gethash "role" raw) "assistant"
          (gethash "content" raw) (vector content-block)
          (gethash "stop_reason" raw) stop-reason)
    (setf (gethash "input_tokens" usage) input-tokens
          (gethash "output_tokens" usage) output-tokens)
    (setf (gethash "usage" raw) usage)
    raw))

(defun make-ollama-response (&key (content "Hello") (model "llama2")
                                   (done-reason "stop")
                                   (eval-count 5) (prompt-eval-count 10))
  "Build an Ollama-format raw response hash-table."
  (let ((raw (make-hash-table :test 'equal))
        (message (make-hash-table :test 'equal)))
    (setf (gethash "role" message) "assistant"
          (gethash "content" message) content)
    (setf (gethash "model" raw) model
          (gethash "message" raw) message
          (gethash "done_reason" raw) done-reason
          (gethash "eval_count" raw) eval-count
          (gethash "prompt_eval_count" raw) prompt-eval-count
          (gethash "created_at" raw) "2024-01-01T00:00:00Z")
    raw))

;;;; Contract: OpenAI parse-completion-response

(fiveam:test contract-openai-parse-content
  "OpenAI parse-completion-response extracts content correctly"
  (let* ((raw (make-openai-response :content "Test content" :model "gpt-4o"))
         (provider (make-provider :openai :api-key "test"))
         (result (parse-completion-response provider raw)))
    (fiveam:is (string= "Test content" (response-content result)))
    (fiveam:is (string= "gpt-4o" (response-model result)))
    (fiveam:is (eq :stop (response-finish-reason result)))))

(fiveam:test contract-openai-parse-usage
  "OpenAI parse-completion-response extracts usage correctly"
  (let* ((raw (make-openai-response :prompt-tokens 100 :completion-tokens 50))
         (provider (make-provider :openai :api-key "test"))
         (result (parse-completion-response provider raw)))
    (let ((usage (response-usage result)))
      (fiveam:is (= 100 (getf usage :prompt-tokens)))
      (fiveam:is (= 50 (getf usage :completion-tokens)))
      (fiveam:is (= 150 (getf usage :total-tokens))))))

(fiveam:test contract-openai-parse-finish-reasons
  "OpenAI parse-completion-response handles all finish reasons"
  (let ((provider (make-provider :openai :api-key "test")))
    (dolist (reason '("stop" "length"))
      (let* ((raw (make-openai-response :finish-reason reason))
             (result (parse-completion-response provider raw)))
        (fiveam:is (keywordp (response-finish-reason result)))))))

(fiveam:test contract-openai-parse-preserves-raw
  "OpenAI parse-completion-response stores raw response"
  (let* ((raw (make-openai-response))
         (provider (make-provider :openai :api-key "test"))
         (result (parse-completion-response provider raw)))
    (fiveam:is (eq raw (response-raw result)))))

;;;; Contract: Anthropic parse-completion-response

(fiveam:test contract-anthropic-parse-content
  "Anthropic parse-completion-response extracts content correctly"
  (let* ((raw (make-anthropic-response :content "Claude says hello" :model "claude-3-opus"))
         (provider (make-provider :anthropic :api-key "test"))
         (result (parse-completion-response provider raw)))
    (fiveam:is (string= "Claude says hello" (response-content result)))
    (fiveam:is (string= "claude-3-opus" (response-model result)))
    (fiveam:is (eq :end_turn (response-finish-reason result)))))

(fiveam:test contract-anthropic-parse-usage
  "Anthropic parse-completion-response extracts usage correctly"
  (let* ((raw (make-anthropic-response :input-tokens 80 :output-tokens 40))
         (provider (make-provider :anthropic :api-key "test"))
         (result (parse-completion-response provider raw)))
    (let ((usage (response-usage result)))
      (fiveam:is (= 80 (getf usage :prompt-tokens)))
      (fiveam:is (= 40 (getf usage :completion-tokens)))
      (fiveam:is (= 120 (getf usage :total-tokens))))))

(fiveam:test contract-anthropic-parse-preserves-raw
  "Anthropic parse-completion-response stores raw response"
  (let* ((raw (make-anthropic-response))
         (provider (make-provider :anthropic :api-key "test"))
         (result (parse-completion-response provider raw)))
    (fiveam:is (eq raw (response-raw result)))))

;;;; Contract: Ollama parse-completion-response

(fiveam:test contract-ollama-parse-content
  "Ollama parse-completion-response extracts content correctly"
  (let* ((raw (make-ollama-response :content "Ollama says hi" :model "llama3"))
         (provider (make-provider :ollama :base-url "http://localhost:11434"))
         (result (parse-completion-response provider raw)))
    (fiveam:is (string= "Ollama says hi" (response-content result)))
    (fiveam:is (string= "llama3" (response-model result)))))

(fiveam:test contract-ollama-parse-usage
  "Ollama parse-completion-response extracts usage correctly"
  (let* ((raw (make-ollama-response :eval-count 30 :prompt-eval-count 60))
         (provider (make-provider :ollama :base-url "http://localhost:11434"))
         (result (parse-completion-response provider raw)))
    (let ((usage (response-usage result)))
      (fiveam:is (= 60 (getf usage :prompt-tokens)))
      (fiveam:is (= 30 (getf usage :completion-tokens))))))

;;;; Contract: Gemini parse-completion-response (OpenAI-compatible format)

(fiveam:test contract-gemini-parse-content
  "Gemini parse-completion-response extracts content correctly"
  (let* ((raw (make-openai-response :content "Gemini response" :model "gemini-3-flash"))
         (provider (make-provider :gemini :api-key "test"))
         (result (parse-completion-response provider raw)))
    (fiveam:is (string= "Gemini response" (response-content result)))
    (fiveam:is (string= "gemini-3-flash" (response-model result)))
    (fiveam:is (eq :stop (response-finish-reason result)))))

;;;; Cross-provider contracts: all providers produce same output shape

(fiveam:test contract-all-providers-produce-completion-response
  "All providers parse into a completion-response with required fields"
  (let ((test-cases
          (list
           (cons (make-provider :openai :api-key "test")
                 (make-openai-response :content "A"))
           (cons (make-provider :anthropic :api-key "test")
                 (make-anthropic-response :content "B"))
           (cons (make-provider :ollama :base-url "http://localhost:11434")
                 (make-ollama-response :content "C"))
           (cons (make-provider :gemini :api-key "test")
                 (make-openai-response :content "D")))))
    (dolist (tc test-cases)
      (let* ((provider (car tc))
             (raw (cdr tc))
             (result (parse-completion-response provider raw)))
        (fiveam:is (typep result 'completion-response))
        (fiveam:is (stringp (response-content result)))
        (fiveam:is (stringp (response-model result)))
        (fiveam:is (keywordp (response-finish-reason result)))
        (fiveam:is (listp (response-usage result)))))))

;;;; Schema validation tests

(fiveam:test schema-openai-response-valid
  "OpenAI mock response conforms to schema"
  (let ((raw (make-openai-response)))
    (fiveam:is (th.contract:validate-against-schema 'openai-completion-response raw))))

(fiveam:test schema-anthropic-response-valid
  "Anthropic mock response conforms to schema"
  (let ((raw (make-anthropic-response)))
    (fiveam:is (th.contract:validate-against-schema 'anthropic-completion-response raw))))

(fiveam:test schema-ollama-response-valid
  "Ollama mock response conforms to schema"
  (let ((raw (make-ollama-response)))
    (fiveam:is (th.contract:validate-against-schema 'ollama-chat-response raw))))
