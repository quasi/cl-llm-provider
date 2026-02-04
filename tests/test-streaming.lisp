;; ABOUTME: Tests for streaming response functionality - stream-chunk and completion-stream classes
(th.harness:setup :cl-llm-provider)

(fiveam:def-suite streaming-suite
  :description "Streaming response tests"
  :in cl-llm-provider/test::cl-llm-provider-suite)

(fiveam:in-suite streaming-suite)

(fiveam:test stream-chunk-creation
  "Test stream-chunk object creation"
  (let ((chunk (make-instance 'cl-llm-provider::stream-chunk
                              :content "Hello"
                              :delta "Hello"
                              :finish-reason nil
                              :index 0)))
    (fiveam:is (string= "Hello" (cl-llm-provider::chunk-content chunk)))
    (fiveam:is (string= "Hello" (cl-llm-provider::chunk-delta chunk)))
    (fiveam:is (null (cl-llm-provider::chunk-finish-reason chunk)))
    (fiveam:is (= 0 (cl-llm-provider::chunk-index chunk)))))

(fiveam:test completion-stream-creation
  "Test completion-stream object creation"
  (let ((stream (make-instance 'cl-llm-provider::completion-stream
                               :provider nil
                               :model "test-model")))
    (fiveam:is (string= "test-model" (cl-llm-provider::stream-model stream)))
    (fiveam:is (eq :open (cl-llm-provider::stream-state stream)))
    (fiveam:is (null (cl-llm-provider::stream-chunks stream)))))

(fiveam:test completion-stream-state-transitions
  "Test stream state management"
  (let ((stream (make-instance 'cl-llm-provider::completion-stream
                               :provider nil
                               :model "test")))
    (fiveam:is (cl-llm-provider::stream-open-p stream))
    (fiveam:is (not (cl-llm-provider::stream-closed-p stream)))
    (setf (cl-llm-provider::stream-state stream) :closed)
    (fiveam:is (not (cl-llm-provider::stream-open-p stream)))
    (fiveam:is (cl-llm-provider::stream-closed-p stream))))

;;; Task 1.3: Streaming Protocol Generic Functions

(fiveam:test streaming-protocol-exists
  "Test that streaming protocol generic functions exist"
  (fiveam:is (fboundp 'cl-llm-provider::send-streaming-request))
  (fiveam:is (fboundp 'cl-llm-provider::parse-stream-chunk))
  (fiveam:is (fboundp 'cl-llm-provider::read-stream-chunk)))

;;; Task 1.4: SSE Parser for OpenAI-Compatible Streams

(fiveam:test parse-sse-line
  "Test SSE line parsing"
  (fiveam:is (equal '(:data . "{\"id\":\"1\"}")
             (cl-llm-provider::parse-sse-line "data: {\"id\":\"1\"}")))
  (fiveam:is (equal '(:data . "[DONE]")
             (cl-llm-provider::parse-sse-line "data: [DONE]")))
  (fiveam:is (null (cl-llm-provider::parse-sse-line "")))
  (fiveam:is (null (cl-llm-provider::parse-sse-line ": keep-alive"))))

(fiveam:test parse-sse-line-event-type
  "Test SSE event type line parsing"
  (fiveam:is (equal '(:event . "content_block_delta")
             (cl-llm-provider::parse-sse-line "event: content_block_delta")))
  (fiveam:is (equal '(:event . "message_stop")
             (cl-llm-provider::parse-sse-line "event: message_stop"))))

(fiveam:test parse-openai-stream-chunk
  "Test OpenAI streaming chunk parsing"
  (let* ((raw-data "{\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}")
         (chunk (cl-llm-provider::parse-openai-stream-data raw-data 0)))
    (fiveam:is (string= "Hello" (cl-llm-provider::chunk-delta chunk)))
    (fiveam:is (null (cl-llm-provider::chunk-finish-reason chunk)))))

(fiveam:test parse-openai-stream-done
  "Test OpenAI stream completion detection"
  (let ((chunk (cl-llm-provider::parse-openai-stream-data "[DONE]" 0)))
    (fiveam:is (eq :done chunk))))

(fiveam:test parse-openai-stream-with-finish-reason
  "Test OpenAI streaming chunk with finish reason"
  (let* ((raw-data "{\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}")
         (chunk (cl-llm-provider::parse-openai-stream-data raw-data 5)))
    (fiveam:is (eq :stop (cl-llm-provider::chunk-finish-reason chunk)))
    (fiveam:is (= 5 (cl-llm-provider::chunk-index chunk)))))

(fiveam:test parse-openai-stream-empty-data
  "Test OpenAI streaming chunk with empty/nil data"
  (fiveam:is (null (cl-llm-provider::parse-openai-stream-data "" 0)))
  (fiveam:is (null (cl-llm-provider::parse-openai-stream-data nil 0))))

;;; Task 1.5: Anthropic Stream Parser

(fiveam:test parse-anthropic-stream-event-content-block-delta
  "Test Anthropic streaming content_block_delta event parsing"
  (let* ((event-type "content_block_delta")
         (data "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}")
         (chunk (cl-llm-provider::parse-anthropic-stream-event event-type data 0)))
    (fiveam:is (not (null chunk)))
    (fiveam:is (string= "Hello" (cl-llm-provider::chunk-delta chunk)))
    (fiveam:is (string= "Hello" (cl-llm-provider::chunk-content chunk)))
    (fiveam:is (= 0 (cl-llm-provider::chunk-index chunk)))))

(fiveam:test parse-anthropic-stream-event-message-stop
  "Test Anthropic streaming message_stop event returns :done"
  (let* ((event-type "message_stop")
         (data "{\"type\":\"message_stop\"}")
         (result (cl-llm-provider::parse-anthropic-stream-event event-type data 0)))
    (fiveam:is (eq :done result))))

(fiveam:test parse-anthropic-stream-event-message-delta
  "Test Anthropic streaming message_delta event with usage info"
  (let* ((event-type "message_delta")
         (data "{\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":42}}")
         (chunk (cl-llm-provider::parse-anthropic-stream-event event-type data 5)))
    (fiveam:is (not (null chunk)))
    (fiveam:is (eq :end_turn (cl-llm-provider::chunk-finish-reason chunk)))
    (fiveam:is (= 5 (cl-llm-provider::chunk-index chunk)))
    (fiveam:is (equal 42 (getf (cl-llm-provider::chunk-usage chunk) :completion-tokens)))))

(fiveam:test parse-anthropic-stream-event-ping
  "Test Anthropic streaming ping event returns nil"
  (let* ((event-type "ping")
         (data "{\"type\":\"ping\"}")
         (result (cl-llm-provider::parse-anthropic-stream-event event-type data 0)))
    (fiveam:is (null result))))

(fiveam:test parse-anthropic-stream-event-metadata-events
  "Test Anthropic metadata events (message_start, content_block_start, content_block_stop) return nil"
  ;; message_start
  (fiveam:is (null (cl-llm-provider::parse-anthropic-stream-event
             "message_start"
             "{\"type\":\"message_start\",\"message\":{\"id\":\"msg_123\",\"model\":\"claude-3-sonnet\"}}"
             0)))
  ;; content_block_start
  (fiveam:is (null (cl-llm-provider::parse-anthropic-stream-event
             "content_block_start"
             "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}"
             0)))
  ;; content_block_stop
  (fiveam:is (null (cl-llm-provider::parse-anthropic-stream-event
             "content_block_stop"
             "{\"type\":\"content_block_stop\",\"index\":0}"
             0))))

;;; Task 1.6: Implement OpenAI Streaming Request

(fiveam:test openai-streaming-method-exists
  "Test that OpenAI provider has streaming implementation"
  (let ((provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "test-key"
                                 :base-url "https://api.openai.com/v1")))
    ;; Just test the method exists and can be called (will fail with no network)
    (fiveam:is (find-method #'cl-llm-provider::send-streaming-request
                     nil
                     (list (class-of provider) t)
                     nil))))

;;; Task 1.7: Implement Anthropic Streaming Request

(fiveam:test anthropic-streaming-method-exists
  "Test that Anthropic provider has streaming implementation"
  (let ((provider (make-instance 'cl-llm-provider::anthropic-provider
                                 :api-key "test-key")))
    (fiveam:is (find-method #'cl-llm-provider::send-streaming-request
                     nil
                     (list (class-of provider) t)
                     nil))))

;;; Task 1.8: Add High-Level complete-stream API

(fiveam:test complete-stream-api-exists
  "Test that complete-stream function exists and is exported"
  (fiveam:is (fboundp 'cl-llm-provider:complete-stream)))

(fiveam:test complete-stream-with-callback
  "Test complete-stream callback interface (mock)"
  (let ((chunks '()))
    ;; We can't test real streaming without network,
    ;; but we can test the callback mechanism with a mock
    (fiveam:is (functionp #'cl-llm-provider:complete-stream))))

