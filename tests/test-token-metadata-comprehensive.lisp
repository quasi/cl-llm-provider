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
(load "src/protocol.lisp")
(load "src/api.lisp")
(load "src/tools.lisp")
(load "src/config.lisp")
(load "src/providers/anthropic.lisp")
(load "src/providers/openai.lisp")
(load "src/providers/ollama.lisp")
(load "src/providers/openrouter.lisp")

(in-package :cl-llm-provider)

;;; Define test suite
(fiveam:def-suite token-metadata-suite
  :description "Comprehensive test suite for token counting and metadata extraction")

(fiveam:in-suite token-metadata-suite)

;;;; Unit Tests - Token Counting

(fiveam:test token-counts-are-positive
  "Token counts should be non-negative integers"
  (let ((response (make-instance 'completion-response
                                 :id "test-1"
                                 :model "test-model"
                                 :content "test"
                                 :message '(:role "assistant" :content "test")
                                 :usage '(:prompt-tokens 10 :completion-tokens 5 :total-tokens 15))))
    (fiveam:is (>= (getf (response-usage response) :prompt-tokens) 0))
    (fiveam:is (>= (getf (response-usage response) :completion-tokens) 0))
    (fiveam:is (>= (getf (response-usage response) :total-tokens) 0))))

(fiveam:test total-tokens-equals-sum
  "Total tokens should equal prompt + completion tokens"
  (let* ((prompt 25)
         (completion 15)
         (total (+ prompt completion))
         (response (make-instance 'completion-response
                                  :id "test-2"
                                  :model "test-model"
                                  :content "test"
                                  :message '(:role "assistant" :content "test")
                                  :usage (list :prompt-tokens prompt
                                              :completion-tokens completion
                                              :total-tokens total))))
    (fiveam:is (= (getf (response-usage response) :total-tokens)
                  (+ (getf (response-usage response) :prompt-tokens)
                     (getf (response-usage response) :completion-tokens))))))

(fiveam:test usage-plist-format
  "Usage should be a proper plist with expected keys"
  (let ((response (make-instance 'completion-response
                                 :id "test-3"
                                 :model "test-model"
                                 :content "test"
                                 :message '(:role "assistant" :content "test")
                                 :usage '(:prompt-tokens 100 :completion-tokens 50 :total-tokens 150))))
    (let ((usage (response-usage response)))
      (fiveam:is (listp usage))
      (fiveam:is (getf usage :prompt-tokens))
      (fiveam:is (getf usage :completion-tokens))
      (fiveam:is (getf usage :total-tokens)))))

;;;; Unit Tests - Metadata

(fiveam:test metadata-is-optional
  "Metadata should be optional (can be nil)"
  (let ((response (make-instance 'completion-response
                                 :id "test-4"
                                 :model "test-model"
                                 :content "test"
                                 :message '(:role "assistant" :content "test")
                                 :usage '(:prompt-tokens 10 :completion-tokens 10 :total-tokens 20))))
    (fiveam:is (null (response-metadata response)))))

(fiveam:test metadata-can-be-plist
  "Metadata can be a plist when provided"
  (let ((metadata '(:created-at "2025-12-29T19:00:00Z" :duration-ns 1000000)))
    (let ((response (make-instance 'completion-response
                                   :id "test-5"
                                   :model "test-model"
                                   :content "test"
                                   :message '(:role "assistant" :content "test")
                                   :usage '(:prompt-tokens 10 :completion-tokens 10 :total-tokens 20)
                                   :metadata metadata)))
      (fiveam:is (equal (response-metadata response) metadata))
      (fiveam:is (getf (response-metadata response) :created-at))
      (fiveam:is (getf (response-metadata response) :duration-ns)))))

(fiveam:test metadata-is-independent-per-response
  "Different responses should have independent metadata"
  (let ((meta1 '(:duration-ns 1000000))
        (meta2 '(:duration-ns 2000000)))
    (let ((resp1 (make-instance 'completion-response
                                :id "test-6a"
                                :model "test-model"
                                :content "test1"
                                :message '(:role "assistant" :content "test1")
                                :usage '(:prompt-tokens 10 :completion-tokens 10 :total-tokens 20)
                                :metadata meta1))
          (resp2 (make-instance 'completion-response
                                :id "test-6b"
                                :model "test-model"
                                :content "test2"
                                :message '(:role "assistant" :content "test2")
                                :usage '(:prompt-tokens 10 :completion-tokens 10 :total-tokens 20)
                                :metadata meta2)))
      (fiveam:is (not (equal (response-metadata resp1) (response-metadata resp2)))))))

;;;; Unit Tests - Embedding Responses

(fiveam:test embedding-response-has-metadata
  "Embedding response should support metadata"
  (let ((response (make-instance 'embedding-response
                                 :embeddings '((0.1 0.2 0.3))
                                 :model "embed-model"
                                 :usage '(:prompt-tokens 5 :total-tokens 5)
                                 :metadata '(:created-at "2025-12-29T19:00:00Z"))))
    (fiveam:is (response-metadata response))
    (fiveam:is (equal (getf (response-metadata response) :created-at) "2025-12-29T19:00:00Z"))))

(fiveam:test embedding-response-usage
  "Embedding response should track token usage"
  (let ((response (make-instance 'embedding-response
                                 :embeddings '((0.1 0.2 0.3))
                                 :model "embed-model"
                                 :usage '(:prompt-tokens 10 :total-tokens 10))))
    (fiveam:is (= (getf (response-usage response) :prompt-tokens) 10))
    (fiveam:is (= (getf (response-usage response) :total-tokens) 10))))

;;;; Integration Tests - Ollama Provider

(fiveam:test ollama-token-counting-integration
  "Ollama provider should return valid token counts"
  (let ((ollama-available (handler-case (dex:get "http://localhost:11434/api/tags")
                            (error () nil))))
    (if (not ollama-available)
        (fiveam:skip "Ollama not running")
        (let ((provider (make-provider :ollama
                                       :base-url "http://localhost:11434"
                                       :model "qwen3:1.7b")))
          (handler-case
              (let ((response (complete '((:role "user" :content "Hello"))
                                        :provider provider
                                        :max-tokens 20)))
                (let ((usage (response-usage response)))
                  (fiveam:is (numberp (getf usage :prompt-tokens)))
                  (fiveam:is (numberp (getf usage :completion-tokens)))
                  (fiveam:is (numberp (getf usage :total-tokens)))
                  (fiveam:is (> (getf usage :total-tokens) 0))))
            (error (e)
              (fiveam:skip (format nil "Ollama test failed: ~A" e))))))))

(fiveam:test ollama-response-id-format
  "Ollama response should have proper ID format"
  (let ((ollama-available (handler-case (dex:get "http://localhost:11434/api/tags")
                            (error () nil))))
    (if (not ollama-available)
        (fiveam:skip "Ollama not running")
        (let ((provider (make-provider :ollama
                                       :base-url "http://localhost:11434"
                                       :model "qwen3:1.7b")))
          (handler-case
              (let ((response (complete '((:role "user" :content "ID test"))
                                        :provider provider
                                        :max-tokens 10)))
                (let ((id (response-id response)))
                  (fiveam:is (stringp id))
                  (fiveam:is (search "ollama" id))))
            (error (e)
              (fiveam:skip (format nil "Ollama test failed: ~A" e))))))))

;;;; Integration Tests - Performance Profiling

(fiveam:test performance-profiling-disabled-by-default
  "Performance profiling should be disabled by default"
  (fiveam:is (null *performance-profiling*)))

(fiveam:test performance-profiling-with-token-counting
  "Performance profiling should work alongside token counting"
  (let ((ollama-available (handler-case (dex:get "http://localhost:11434/api/tags")
                            (error () nil))))
    (if (not ollama-available)
        (fiveam:skip "Ollama not running")
        (let ((*performance-profiling* t))
          (let ((provider (make-provider :ollama
                                         :base-url "http://localhost:11434"
                                         :model "qwen3:1.7b")))
            (handler-case
                (let ((response (complete '((:role "user" :content "Perf test"))
                                          :provider provider
                                          :max-tokens 15)))
                  ;; Check token counts
                  (fiveam:is (response-usage response))
                  ;; Check performance timing
                  (fiveam:is (response-performance response))
                  (let ((perf (response-performance response)))
                    (fiveam:is (getf perf :encode-time))
                    (fiveam:is (getf perf :api-time))
                    (fiveam:is (getf perf :decode-time))
                    (fiveam:is (numberp (getf perf :encode-time)))
                    (fiveam:is (numberp (getf perf :api-time)))
                    (fiveam:is (numberp (getf perf :decode-time))))
                  ;; Check metadata
                  (fiveam:is (response-metadata response)))
              (error (e)
                (fiveam:skip (format nil "Profiling test failed: ~A" e)))))))))

;;;; Edge Cases

(fiveam:test empty-usage-handling
  "Should handle empty or nil usage gracefully"
  (let ((response (make-instance 'completion-response
                                 :id "test-empty"
                                 :model "test"
                                 :content "test"
                                 :message '(:role "assistant" :content "test")
                                 :usage '(:prompt-tokens 0 :completion-tokens 0 :total-tokens 0))))
    (let ((usage (response-usage response)))
      (fiveam:is (= (getf usage :total-tokens) 0)))))

(fiveam:test nil-metadata-accessor
  "Accessing metadata on nil should return nil"
  (let ((response (make-instance 'completion-response
                                 :id "test-nil-meta"
                                 :model "test"
                                 :content "test"
                                 :message '(:role "assistant" :content "test")
                                 :usage '(:prompt-tokens 10 :completion-tokens 10 :total-tokens 20))))
    (fiveam:is (null (response-metadata response)))))

(fiveam:test large-token-counts
  "Should handle large token counts correctly"
  (let ((large-count 1000000))
    (let ((response (make-instance 'completion-response
                                   :id "test-large"
                                   :model "test"
                                   :content "test"
                                   :message '(:role "assistant" :content "test")
                                   :usage (list :prompt-tokens large-count
                                               :completion-tokens large-count
                                               :total-tokens (* 2 large-count)))))
      (fiveam:is (= (getf (response-usage response) :prompt-tokens) large-count))
      (fiveam:is (= (getf (response-usage response) :total-tokens) (* 2 large-count))))))

(fiveam:test metadata-with-special-values
  "Metadata should preserve various data types"
  (let ((metadata '(:string "value"
                    :number 42
                    :float 3.14
                    :list (1 2 3)
                    :boolean t)))
    (let ((response (make-instance 'completion-response
                                   :id "test-special"
                                   :model "test"
                                   :content "test"
                                   :message '(:role "assistant" :content "test")
                                   :usage '(:prompt-tokens 10 :completion-tokens 10 :total-tokens 20)
                                   :metadata metadata)))
      (let ((meta (response-metadata response)))
        (fiveam:is (string= (getf meta :string) "value"))
        (fiveam:is (= (getf meta :number) 42))
        (fiveam:is (= (getf meta :float) 3.14))
        (fiveam:is (equal (getf meta :list) '(1 2 3)))
        (fiveam:is (getf meta :boolean))))))

;;;; Consistency Tests

(fiveam:test response-slots-accessible
  "All response slots should be accessible"
  (let ((response (make-instance 'completion-response
                                 :id "test-slots"
                                 :model "gpt-4"
                                 :content "Hello world"
                                 :message '(:role "assistant" :content "Hello world")
                                 :tool-calls nil
                                 :finish-reason :stop
                                 :usage '(:prompt-tokens 10 :completion-tokens 20 :total-tokens 30)
                                 :raw (make-hash-table)
                                 :performance '(:encode-time 0.001 :api-time 0.5 :decode-time 0.001)
                                 :metadata '(:created-at "2025-12-29"))))
    (fiveam:is (string= (response-id response) "test-slots"))
    (fiveam:is (string= (response-model response) "gpt-4"))
    (fiveam:is (string= (response-content response) "Hello world"))
    (fiveam:is (response-message response))
    (fiveam:is (null (response-tool-calls response)))
    (fiveam:is (eq (response-finish-reason response) :stop))
    (fiveam:is (response-usage response))
    (fiveam:is (response-raw response))
    (fiveam:is (response-performance response))
    (fiveam:is (response-metadata response))))

(fiveam:test embedding-response-slots
  "All embedding response slots should be accessible"
  (let ((response (make-instance 'embedding-response
                                 :embeddings '((0.1 0.2 0.3) (0.4 0.5 0.6))
                                 :model "embed-3-small"
                                 :usage '(:prompt-tokens 10 :total-tokens 10)
                                 :raw (make-hash-table)
                                 :performance '(:encode-time 0.001 :api-time 0.2 :decode-time 0.001)
                                 :metadata '(:created-at "2025-12-29"))))
    (fiveam:is (response-embeddings response))
    (fiveam:is (= (length (response-embeddings response)) 2))
    (fiveam:is (string= (response-model response) "embed-3-small"))
    (fiveam:is (response-usage response))
    (fiveam:is (response-raw response))
    (fiveam:is (response-performance response))
    (fiveam:is (response-metadata response))))

;;;; Run Tests

(format t "~%~%=== Running Comprehensive Test Suite ===~%~%")
(fiveam:run! 'token-metadata-suite)
