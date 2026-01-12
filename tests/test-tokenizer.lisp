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
(load "src/model-registry.lisp")
(load "src/providers/anthropic.lisp")
(load "src/providers/openai.lisp")
(load "src/providers/ollama.lisp")
(load "src/providers/openrouter.lisp")
(load "src/tokenizer.lisp")

(in-package :cl-llm-provider)

;;; Define test suite
(fiveam:def-suite tokenizer-suite
  :description "Token counting tests")

(fiveam:in-suite tokenizer-suite)

(fiveam:test count-tokens-basic
  "Test basic token counting"
  (let ((count (cl-llm-provider:count-tokens
                '((:role "user" :content "Hello, world!"))
                :model "gpt-4")))
    (fiveam:is (numberp count))
    (fiveam:is (> count 0))))

(fiveam:test count-tokens-estimates-reasonably
  "Test token count is reasonable for known text"
  ;; "Hello, world!" is ~4 tokens in most tokenizers
  (let ((count (cl-llm-provider:count-tokens
                '((:role "user" :content "Hello, world!"))
                :model "gpt-4")))
    (fiveam:is (>= count 2))   ; At least 2 tokens
    (fiveam:is (<= count 10)))) ; At most 10 tokens (with overhead)

(fiveam:test estimate-cost-basic
  "Test basic cost estimation"
  (let ((provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "test"
                                 :model "gpt-4o")))
    (multiple-value-bind (input-cost output-cost total)
        (cl-llm-provider:estimate-cost
         '((:role "user" :content "Hello!"))
         :provider provider
         :model "gpt-4o"
         :max-tokens 100)
      (fiveam:is (numberp input-cost))
      (fiveam:is (numberp output-cost))
      (fiveam:is (numberp total))
      (fiveam:is (> total 0)))))

(fiveam:test estimate-cost-uses-model-metadata
  "Test that cost estimation uses model pricing"
  (let ((provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "test")))
    ;; gpt-4o-mini is cheaper than gpt-4o
    (let ((cheap-cost (cl-llm-provider:estimate-cost
                       '((:role "user" :content "Test"))
                       :provider provider
                       :model "gpt-4o-mini"
                       :max-tokens 100))
          (expensive-cost (cl-llm-provider:estimate-cost
                          '((:role "user" :content "Test"))
                          :provider provider
                          :model "gpt-4o"
                          :max-tokens 100)))
      (fiveam:is (< cheap-cost expensive-cost)))))

(fiveam:test format-cost-basic
  "Test basic cost formatting"
  (let ((formatted (with-output-to-string (s)
                     (cl-llm-provider:format-cost 0.0025 s))))
    (fiveam:is (stringp formatted))
    (fiveam:is (search "$" formatted))
    (fiveam:is (search "0.0025" formatted))))

(fiveam:test format-cost-nil
  "Test formatting nil cost"
  (let ((formatted (with-output-to-string (s)
                     (cl-llm-provider:format-cost nil s))))
    (fiveam:is (stringp formatted))
    (fiveam:is (search "N/A" formatted))))

;;; Run tests
(format t "~%~%Running tokenizer tests...~%")
(fiveam:run! 'tokenizer-suite)
