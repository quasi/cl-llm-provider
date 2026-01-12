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
(load "src/streaming.lisp")
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

(test completion-stream-creation
  "Test completion-stream object creation"
  (let ((stream (make-instance 'cl-llm-provider::completion-stream
                               :provider nil
                               :model "test-model")))
    (is (string= "test-model" (cl-llm-provider::stream-model stream)))
    (is (eq :open (cl-llm-provider::stream-state stream)))
    (is (null (cl-llm-provider::stream-chunks stream)))))

(test completion-stream-state-transitions
  "Test stream state management"
  (let ((stream (make-instance 'cl-llm-provider::completion-stream
                               :provider nil
                               :model "test")))
    (is (cl-llm-provider::stream-open-p stream))
    (is (not (cl-llm-provider::stream-closed-p stream)))
    (setf (cl-llm-provider::stream-state stream) :closed)
    (is (not (cl-llm-provider::stream-open-p stream)))
    (is (cl-llm-provider::stream-closed-p stream))))

;;; Task 1.3: Streaming Protocol Generic Functions

(test streaming-protocol-exists
  "Test that streaming protocol generic functions exist"
  (is (fboundp 'cl-llm-provider::send-streaming-request))
  (is (fboundp 'cl-llm-provider::parse-stream-chunk))
  (is (fboundp 'cl-llm-provider::read-stream-chunk)))

;;; Task 1.4: SSE Parser for OpenAI-Compatible Streams

(test parse-sse-line
  "Test SSE line parsing"
  (is (equal '(:data . "{\"id\":\"1\"}")
             (cl-llm-provider::parse-sse-line "data: {\"id\":\"1\"}")))
  (is (equal '(:data . "[DONE]")
             (cl-llm-provider::parse-sse-line "data: [DONE]")))
  (is (null (cl-llm-provider::parse-sse-line "")))
  (is (null (cl-llm-provider::parse-sse-line ": keep-alive"))))

(test parse-sse-line-event-type
  "Test SSE event type line parsing"
  (is (equal '(:event . "content_block_delta")
             (cl-llm-provider::parse-sse-line "event: content_block_delta")))
  (is (equal '(:event . "message_stop")
             (cl-llm-provider::parse-sse-line "event: message_stop"))))

(test parse-openai-stream-chunk
  "Test OpenAI streaming chunk parsing"
  (let* ((raw-data "{\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}")
         (chunk (cl-llm-provider::parse-openai-stream-data raw-data 0)))
    (is (string= "Hello" (cl-llm-provider::chunk-delta chunk)))
    (is (null (cl-llm-provider::chunk-finish-reason chunk)))))

(test parse-openai-stream-done
  "Test OpenAI stream completion detection"
  (let ((chunk (cl-llm-provider::parse-openai-stream-data "[DONE]" 0)))
    (is (eq :done chunk))))

(test parse-openai-stream-with-finish-reason
  "Test OpenAI streaming chunk with finish reason"
  (let* ((raw-data "{\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}")
         (chunk (cl-llm-provider::parse-openai-stream-data raw-data 5)))
    (is (eq :stop (cl-llm-provider::chunk-finish-reason chunk)))
    (is (= 5 (cl-llm-provider::chunk-index chunk)))))

(test parse-openai-stream-empty-data
  "Test OpenAI streaming chunk with empty/nil data"
  (is (null (cl-llm-provider::parse-openai-stream-data "" 0)))
  (is (null (cl-llm-provider::parse-openai-stream-data nil 0))))

;;; Run Tests

(format t "~%~%=== Running Streaming Test Suite ===~%~%")
(fiveam:run! 'streaming-suite)
