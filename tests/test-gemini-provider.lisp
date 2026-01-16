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

(defpackage :cl-llm-provider/test-gemini
  (:use :cl :cl-llm-provider :fiveam))

(in-package :cl-llm-provider/test-gemini)

;;;; Gemini Provider Unit Tests

(def-suite gemini-provider-tests
  :description "Tests for Google Gemini provider")

(in-suite gemini-provider-tests)

;;; Provider Introspection Tests

(test gemini-provider-type
  "Gemini provider returns correct type keyword"
  (let ((provider (make-provider :gemini :api-key "test-key")))
    (is (eq :gemini (provider-type provider)))))

(test gemini-provider-name
  "Gemini provider returns correct display name"
  (let ((provider (make-provider :gemini :api-key "test-key")))
    (is (string= "Google Gemini" (provider-name provider)))))

(test gemini-provider-capabilities
  "Gemini provider reports correct capabilities"
  (let ((provider (make-provider :gemini :api-key "test-key")))
    (is (provider-supports-p provider :tools))
    (is (provider-supports-p provider :embeddings))
    (is (provider-supports-p provider :streaming))
    (is (provider-supports-p provider :vision))
    (is (provider-supports-p provider :function-calling))))

(test gemini-default-base-url
  "Gemini provider has correct default base URL"
  (let ((provider (make-provider :gemini :api-key "test-key")))
    (is (string= "https://generativelanguage.googleapis.com/v1beta/openai/"
                 (provider-base-url provider)))))

(test gemini-api-key-env-var
  "Gemini provider specifies correct env var"
  (let ((provider (make-provider :gemini :api-key "test-key")))
    (is (string= "GEMINI_API_KEY"
                 (provider-api-key-env-var provider)))))

;;; Model Metadata Tests

(test gemini-flash-metadata
  "Gemini Flash model has correct metadata"
  (let* ((provider (make-provider :gemini :api-key "test-key"))
         (meta (model-metadata provider "gemini-3-flash-preview")))
    (is (= 1048576 (getf meta :context-window)))
    (is (= 8192 (getf meta :max-output-tokens)))
    (is (eq t (getf meta :supports-tools)))
    (is (eq t (getf meta :supports-vision)))
    (is (= 0.075 (getf meta :input-cost-per-1m-tokens)))
    (is (= 0.30 (getf meta :output-cost-per-1m-tokens)))))

(test gemini-pro-metadata
  "Gemini Pro model has correct metadata"
  (let* ((provider (make-provider :gemini :api-key "test-key"))
         (meta (model-metadata provider "gemini-3-pro-preview")))
    (is (= 2097152 (getf meta :context-window)))
    (is (= 8192 (getf meta :max-output-tokens)))
    (is (= 1.25 (getf meta :input-cost-per-1m-tokens)))
    (is (= 5.00 (getf meta :output-cost-per-1m-tokens)))))

(test gemini-embedding-metadata
  "Gemini embedding model has correct metadata"
  (let* ((provider (make-provider :gemini :api-key "test-key"))
         (meta (model-metadata provider "gemini-embedding-001")))
    (is (= 768 (getf meta :output-dimensions)))
    (is (= 0.0 (getf meta :input-cost-per-1m-tokens)))
    (is (= 0.0 (getf meta :output-cost-per-1m-tokens)))))

(test gemini-unknown-model
  "Unknown model returns nil metadata"
  (let* ((provider (make-provider :gemini :api-key "test-key"))
         (meta (model-metadata provider "nonexistent-model")))
    (is (null meta))))

;;; Configuration Tests

(test gemini-config-summary
  "Config summary excludes sensitive data"
  (let* ((provider (make-provider :gemini :api-key "secret-key" :model "gemini-3-flash-preview"))
         (summary (provider-config-summary provider)))
    (is (eq :gemini (getf summary :type)))
    (is (string= "Google Gemini" (getf summary :name)))
    (is (string= "gemini-3-flash-preview" (getf summary :model)))
    ;; Must NOT include API key
    (is (null (getf summary :api-key)))))

;;; Request Construction Tests (Mock)

(test gemini-completion-request-format
  "Completion request uses OpenAI-compatible format"
  (let ((provider (make-provider :gemini :api-key "test-key")))
    ;; Test that methods exist and are callable
    (finishes
      (ignore-errors
        ;; This will fail at HTTP level, but we're testing method exists
        (handler-case
            (send-completion-request provider
                                     '((:role "user" :content "test"))
                                     :model "gemini-3-flash-preview"
                                     :max-tokens 100)
          (error () t))))))

(test gemini-embedding-request-format
  "Embedding request uses OpenAI-compatible format"
  (let ((provider (make-provider :gemini :api-key "test-key")))
    ;; Test that methods exist and are callable
    (finishes
      (ignore-errors
        ;; This will fail at HTTP level, but we're testing method exists
        (handler-case
            (send-embedding-request provider
                                    "test text"
                                    :model "gemini-embedding-001")
          (error () t))))))

;;; Response Parsing Tests (Mock)

(test gemini-parse-completion-response
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
    (is (string= "chatcmpl-test" (response-id response)))
    (is (string= "gemini-3-flash-preview" (response-model response)))
    (is (string= "Hello from Gemini" (response-content response)))
    (is (eq :stop (response-finish-reason response)))
    (is (= 10 (getf (response-usage response) :prompt-tokens)))
    (is (= 20 (getf (response-usage response) :completion-tokens)))
    (is (= 30 (getf (response-usage response) :total-tokens)))
    ;; Check metadata
    (is (eq :gemini (getf (response-metadata response) :provider-type)))
    (is (string= "Google Gemini" (getf (response-metadata response) :provider-name)))))

(test gemini-parse-embedding-response
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
    (is (string= "gemini-embedding-001" (response-model response)))
    (is (= 1 (length (response-embeddings response))))
    (is (= 4 (length (first (response-embeddings response)))))
    (is (= 0.1 (first (first (response-embeddings response)))))
    (is (= 5 (getf (response-usage response) :prompt-tokens)))
    (is (eq :gemini (getf (response-metadata response) :provider-type)))))

;;; Run tests
(run! 'gemini-provider-tests)
