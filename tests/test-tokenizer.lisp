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

;;; Run tests
(format t "~%~%Running tokenizer tests...~%")
(fiveam:run! 'tokenizer-suite)
