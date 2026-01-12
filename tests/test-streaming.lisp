;; ABOUTME: Tests for streaming response functionality - stream-chunk and completion-stream classes
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

(defpackage :cl-llm-provider/test-streaming
  (:use :cl :cl-llm-provider :fiveam))

(in-package :cl-llm-provider/test-streaming)

(def-suite streaming-suite :description "Streaming response tests")
(in-suite streaming-suite)

(test stream-chunk-creation
  "Test stream-chunk object creation"
  (let ((chunk (make-instance 'cl-llm-provider::stream-chunk
                              :content "Hello"
                              :delta "Hello"
                              :finish-reason nil
                              :index 0)))
    (is (string= "Hello" (cl-llm-provider::chunk-content chunk)))
    (is (string= "Hello" (cl-llm-provider::chunk-delta chunk)))
    (is (null (cl-llm-provider::chunk-finish-reason chunk)))
    (is (= 0 (cl-llm-provider::chunk-index chunk)))))

;;; Run Tests

(format t "~%~%=== Running Streaming Test Suite ===~%~%")
(fiveam:run! 'streaming-suite)
