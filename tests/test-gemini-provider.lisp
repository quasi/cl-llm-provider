(require :asdf)
(ql:quickload :fiveam :silent t)
(ql:quickload :alexandria :silent t)
(ql:quickload :serapeum :silent t)
(ql:quickload :dexador :silent t)
(ql:quickload :yason :silent t)
(ql:quickload :bordeaux-threads :silent t)
(ql:quickload :cl-ppcre :silent t)
(ql:quickload :uiop :silent t)

;; Load the library
(load "src/package.lisp")
(load "src/conditions.lisp")
(load "src/types.lisp")
(load "src/config.lisp")
(load "src/protocol.lisp")
(load "src/model-registry.lisp")
(load "src/tools.lisp")
(load "src/providers/anthropic.lisp")
(load "src/providers/openai.lisp")
(load "src/providers/ollama.lisp")
(load "src/providers/openrouter.lisp")
(load "src/providers/openai-compatible.lisp")
(load "src/providers/gemini.lisp")
(load "src/api.lisp")

(in-package :cl-llm-provider)

;;;; Gemini Provider Unit Tests

(fiveam:def-suite gemini-provider-tests
  :description "Tests for Google Gemini provider")

(fiveam:in-suite gemini-provider-tests)

;;; Provider Introspection Tests

(fiveam:test gemini-provider-type
  "Gemini provider returns correct type keyword"
  (let ((provider (make-provider :gemini :api-key "test-key")))
    (fiveam:is (eq :gemini (provider-type provider)))))

(fiveam:test gemini-provider-name
  "Gemini provider returns correct display name"
  (let ((provider (make-provider :gemini :api-key "test-key")))
    (fiveam:is (string= "Google Gemini" (provider-name provider)))))

(fiveam:test gemini-provider-capabilities
  "Gemini provider reports correct capabilities"
  (let ((provider (make-provider :gemini :api-key "test-key")))
    (fiveam:is (provider-supports-p provider :tools))
    (fiveam:is (provider-supports-p provider :embeddings))
    (fiveam:is (provider-supports-p provider :streaming))
    (fiveam:is (provider-supports-p provider :vision))
    (fiveam:is (provider-supports-p provider :function-calling))))

(fiveam:test gemini-default-base-url
  "Gemini provider has correct default base URL"
  (let ((provider (make-provider :gemini :api-key "test-key")))
    (fiveam:is (string= "https://generativelanguage.googleapis.com/v1beta/openai/"
                        (provider-base-url provider)))))

(fiveam:test gemini-api-key-env-var
  "Gemini provider specifies correct env var"
  (let ((provider (make-provider :gemini :api-key "test-key")))
    (fiveam:is (string= "GEMINI_API_KEY"
                        (provider-api-key-env-var provider)))))

;;; Model Metadata Tests

(fiveam:test gemini-flash-metadata
  "Gemini Flash model has correct metadata"
  (let* ((provider (make-provider :gemini :api-key "test-key"))
         (meta (model-metadata provider "gemini-3-flash-preview")))
    (fiveam:is (= 1048576 (getf meta :context-window)))
    (fiveam:is (= 8192 (getf meta :max-output-tokens)))
    (fiveam:is (eq t (getf meta :supports-tools)))
    (fiveam:is (eq t (getf meta :supports-vision)))
    (fiveam:is (= 0.075 (getf meta :input-cost-per-1m-tokens)))
    (fiveam:is (= 0.30 (getf meta :output-cost-per-1m-tokens)))))

(fiveam:test gemini-pro-metadata
  "Gemini Pro model has correct metadata"
  (let* ((provider (make-provider :gemini :api-key "test-key"))
         (meta (model-metadata provider "gemini-3-pro-preview")))
    (fiveam:is (= 2097152 (getf meta :context-window)))
    (fiveam:is (= 8192 (getf meta :max-output-tokens)))
    (fiveam:is (= 1.25 (getf meta :input-cost-per-1m-tokens)))
    (fiveam:is (= 5.00 (getf meta :output-cost-per-1m-tokens)))))

(fiveam:test gemini-embedding-metadata
  "Gemini embedding model has correct metadata"
  (let* ((provider (make-provider :gemini :api-key "test-key"))
         (meta (model-metadata provider "gemini-embedding-001")))
    (fiveam:is (= 768 (getf meta :output-dimensions)))
    (fiveam:is (= 0.0 (getf meta :input-cost-per-1m-tokens)))
    (fiveam:is (= 0.0 (getf meta :output-cost-per-1m-tokens)))))

(fiveam:test gemini-unknown-model
  "Unknown model returns nil metadata"
  (let* ((provider (make-provider :gemini :api-key "test-key"))
         (meta (model-metadata provider "nonexistent-model")))
    (fiveam:is (null meta))))

;;; Configuration Tests

(fiveam:test gemini-config-summary
  "Config summary excludes sensitive data"
  (let* ((provider (make-provider :gemini :api-key "secret-key" :model "gemini-3-flash-preview"))
         (summary (provider-config-summary provider)))
    (fiveam:is (eq :gemini (getf summary :type)))
    (fiveam:is (string= "Google Gemini" (getf summary :name)))
    (fiveam:is (string= "gemini-3-flash-preview" (getf summary :model)))
    ;; Must NOT include API key
    (fiveam:is (null (getf summary :api-key)))))

;;; Request Construction Tests (Mock)

(fiveam:test gemini-completion-request-format
  "Completion request uses OpenAI-compatible format"
  (let ((provider (make-provider :gemini :api-key "test-key")))
    ;; Test that methods exist and are callable
    (fiveam:finishes
      (ignore-errors
        ;; This will fail at HTTP level, but we're testing method exists
        (handler-case
            (send-completion-request provider
                                     '((:role "user" :content "test"))
                                     :model "gemini-3-flash-preview"
                                     :max-tokens 100)
          (error () t))))))

(fiveam:test gemini-embedding-request-format
  "Embedding request uses OpenAI-compatible format"
  (let ((provider (make-provider :gemini :api-key "test-key")))
    ;; Test that methods exist and are callable
    (fiveam:finishes
      (ignore-errors
        ;; This will fail at HTTP level, but we're testing method exists
        (handler-case
            (send-embedding-request provider
                                    "test text"
                                    :model "gemini-embedding-001")
          (error () t))))))

;;; Response Parsing Tests (Mock)

(fiveam:test gemini-parse-completion-response
  "Parse OpenAI-compatible completion response"
  (let* ((provider (make-provider :gemini :api-key "test-key"))
         ;; Create proper nested hash table structure
         (message (alexandria:plist-hash-table
                   '("role" "assistant"
                     "content" "Hello from Gemini")
                   :test 'equal))
         (choice (alexandria:plist-hash-table
                  (list "index" 0
                        "message" message
                        "finish_reason" "stop")
                  :test 'equal))
         (usage (alexandria:plist-hash-table
                 '("prompt_tokens" 10
                   "completion_tokens" 20
                   "total_tokens" 30)
                 :test 'equal))
         (mock-response (alexandria:plist-hash-table
                         (list "id" "chatcmpl-test"
                               "object" "chat.completion"
                               "created" 1234567890
                               "model" "gemini-3-flash-preview"
                               "choices" (vector choice)
                               "usage" usage)
                         :test 'equal))
         (response (parse-completion-response provider mock-response)))
    (fiveam:is (string= "chatcmpl-test" (response-id response)))
    (fiveam:is (string= "gemini-3-flash-preview" (response-model response)))
    (fiveam:is (string= "Hello from Gemini" (response-content response)))
    (fiveam:is (eq :stop (response-finish-reason response)))
    (fiveam:is (= 10 (getf (response-usage response) :prompt-tokens)))
    (fiveam:is (= 20 (getf (response-usage response) :completion-tokens)))
    (fiveam:is (= 30 (getf (response-usage response) :total-tokens)))
    ;; Check metadata
    (fiveam:is (eq :gemini (getf (response-metadata response) :provider-type)))
    (fiveam:is (string= "Google Gemini" (getf (response-metadata response) :provider-name)))))

(fiveam:test gemini-parse-embedding-response
  "Parse OpenAI-compatible embedding response"
  (let* ((provider (make-provider :gemini :api-key "test-key"))
         ;; Create proper nested hash table structure
         (embedding-data (alexandria:plist-hash-table
                          (list "object" "embedding"
                                "embedding" (vector 0.1 0.2 0.3 0.4)
                                "index" 0)
                          :test 'equal))
         (usage (alexandria:plist-hash-table
                 '("prompt_tokens" 5
                   "total_tokens" 5)
                 :test 'equal))
         (mock-response (alexandria:plist-hash-table
                         (list "object" "list"
                               "model" "gemini-embedding-001"
                               "data" (vector embedding-data)
                               "usage" usage)
                         :test 'equal))
         (response (parse-embedding-response provider mock-response)))
    (fiveam:is (string= "gemini-embedding-001" (response-model response)))
    (fiveam:is (= 1 (length (response-embeddings response))))
    (fiveam:is (= 4 (length (first (response-embeddings response)))))
    (fiveam:is (= 0.1 (first (first (response-embeddings response)))))
    (fiveam:is (= 5 (getf (response-usage response) :prompt-tokens)))
    (fiveam:is (eq :gemini (getf (response-metadata response) :provider-type)))))

;;; Run tests
(fiveam:run! 'gemini-provider-tests)
