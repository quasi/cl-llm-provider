;;; ABOUTME: Shared test fixtures for cl-llm-provider using cl-test-hardening/fixture
;;; Provides reusable factory functions for common test objects.

(in-package :cl-llm-provider)

;;; Provider fixtures

(th.fixture:define-fixture :openai-provider (&key (api-key "test-key") (model "gpt-4"))
  "Create an OpenAI provider for testing."
  (make-provider :openai :api-key api-key :model model))

(th.fixture:define-fixture :anthropic-provider (&key (api-key "test-key") (model "claude-3-opus"))
  "Create an Anthropic provider for testing."
  (make-provider :anthropic :api-key api-key :model model))

(th.fixture:define-fixture :ollama-provider (&key (base-url "http://localhost:11434") (model "llama2"))
  "Create an Ollama provider for testing."
  (make-provider :ollama :base-url base-url :model model))

(th.fixture:define-fixture :openrouter-provider (&key (api-key "test-key") (model "openai/gpt-4"))
  "Create an OpenRouter provider for testing."
  (make-provider :openrouter :api-key api-key :model model))

(th.fixture:define-fixture :gemini-provider (&key (api-key "test-key") (model "gemini-3-flash-preview"))
  "Create a Gemini provider for testing."
  (make-provider :gemini :api-key api-key :model model))

(th.fixture:define-fixture :openai-compatible-provider (&key (base-url "http://localhost:8000")
                                                             (api-key "test-key")
                                                             (model "local-model"))
  "Create an OpenAI-compatible provider for testing."
  (make-provider :openai-compatible :base-url base-url :api-key api-key :model model))

;;; Tool fixtures

(th.fixture:define-fixture :simple-tool (&key (name "search") (description "Search for something"))
  "Create a minimal tool definition."
  (make-instance 'tool-definition
                 :name name
                 :description description
                 :parameters nil))

(th.fixture:define-fixture :calculator-tool ()
  "Create a calculator tool with numeric parameters."
  (make-instance 'tool-definition
                 :name "calculator"
                 :description "Perform arithmetic"
                 :parameters '((:name "operation" :type :string :description "Add, subtract, multiply, divide")
                               (:name "a" :type :number :description "First number")
                               (:name "b" :type :number :description "Second number"))
                 :required '("operation" "a" "b")))

(th.fixture:define-fixture :search-tool ()
  "Create a search tool with string parameter."
  (make-instance 'tool-definition
                 :name "search"
                 :description "Search the knowledge base"
                 :parameters '((:name "query" :type :string :description "Search query")
                               (:name "limit" :type :integer :description "Max results"))
                 :required '("query")))

;;; Tool call fixtures

(th.fixture:define-fixture :tool-call (&key (id "call-123") (name "calculator") (arguments '(:a 5 :b 3)))
  "Create a tool-call instance."
  (make-instance 'tool-call
                 :id id
                 :name name
                 :arguments arguments))

;;; Response fixtures

(th.fixture:define-fixture :completion-response (&key (id "resp-1")
                                                      (model "gpt-4")
                                                      (content "Hello world")
                                                      (finish-reason :stop)
                                                      (prompt-tokens 10)
                                                      (completion-tokens 5))
  "Create a completion response object."
  (make-instance 'completion-response
                 :id id
                 :model model
                 :content content
                 :message (list :role "assistant" :content content)
                 :finish-reason finish-reason
                 :usage (list :prompt-tokens prompt-tokens
                              :completion-tokens completion-tokens
                              :total-tokens (+ prompt-tokens completion-tokens))))

(th.fixture:define-fixture :embedding-response (&key (dims 3) (count 1) (model "text-embedding-3-small"))
  "Create an embedding response object."
  (let ((embeddings (loop repeat count
                          collect (loop repeat dims
                                        collect (/ (random 100) 100.0)))))
    (make-instance 'embedding-response
                   :embeddings embeddings
                   :model model
                   :usage (list :prompt-tokens 5 :total-tokens 5))))

;;; Mock raw response fixtures (hash-tables mimicking provider JSON)

(th.fixture:define-fixture :openai-raw-response (&key (content "Hello") (model "gpt-4") (id "chatcmpl-123"))
  "Create a hash-table mimicking an OpenAI API JSON response."
  (let ((raw (make-hash-table :test 'equal))
        (choice (make-hash-table :test 'equal))
        (message (make-hash-table :test 'equal))
        (usage (make-hash-table :test 'equal)))
    (setf (gethash "role" message) "assistant")
    (setf (gethash "content" message) content)
    (setf (gethash "message" choice) message)
    (setf (gethash "finish_reason" choice) "stop")
    (setf (gethash "index" choice) 0)
    (setf (gethash "id" raw) id)
    (setf (gethash "model" raw) model)
    (setf (gethash "choices" raw) (vector choice))
    (setf (gethash "prompt_tokens" usage) 10)
    (setf (gethash "completion_tokens" usage) 5)
    (setf (gethash "total_tokens" usage) 15)
    (setf (gethash "usage" raw) usage)
    raw))

(th.fixture:define-fixture :anthropic-raw-response (&key (content "Hello") (model "claude-3-opus-20240229")
                                                          (id "msg_123"))
  "Create a hash-table mimicking an Anthropic API JSON response."
  (let ((raw (make-hash-table :test 'equal))
        (content-block (make-hash-table :test 'equal))
        (usage (make-hash-table :test 'equal)))
    (setf (gethash "type" content-block) "text")
    (setf (gethash "text" content-block) content)
    (setf (gethash "id" raw) id)
    (setf (gethash "model" raw) model)
    (setf (gethash "type" raw) "message")
    (setf (gethash "role" raw) "assistant")
    (setf (gethash "content" raw) (vector content-block))
    (setf (gethash "stop_reason" raw) "end_turn")
    (setf (gethash "input_tokens" usage) 10)
    (setf (gethash "output_tokens" usage) 5)
    (setf (gethash "usage" raw) usage)
    raw))

;;; Message fixtures

(th.fixture:define-fixture :messages (&key (count 3))
  "Create a simple conversation message list."
  (let ((roles #("user" "assistant")))
    (loop for i from 0 below count
          collect (list :role (aref roles (mod i 2))
                        :content (format nil "Message ~D" (1+ i))))))
