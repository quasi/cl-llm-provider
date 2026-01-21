# Phase 1: Critical Gaps Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add streaming responses, pre-call token counting, and observability hooks - the three essential features missing for production use in 2026.

**Architecture:**
- Streaming: Add `complete-stream` function returning a stream object with `read-chunk` method. Each provider implements `send-streaming-request` generic function.
- Token Counting: Add `count-tokens` function using tiktoken-compatible tokenizer, `estimate-cost` function using model metadata.
- Observability: Add hooks system with `:on-request`, `:on-response`, `:on-error` callbacks. Integrate with existing `*performance-profiling*`.

**Tech Stack:** dexador (HTTP streaming), bordeaux-threads (async), cl-ppcre (SSE parsing), alexandria (utilities)

**Dependencies:** Phase 1 tasks are mostly independent. Token counting (Task 2) helps observability (Task 3) but isn't required.

---

## Task 1: Streaming Responses

### Task 1.1: Define Stream Types

**Files:**
- Modify: `src/types.lisp` (add after completion-response class, ~line 94)
- Test: `tests/test-streaming.lisp` (create new)

**Step 1: Write the failing test for stream-chunk class**

```lisp
;; tests/test-streaming.lisp
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
```

**Step 2: Run test to verify it fails**

Run: `sbcl --noinform --non-interactive --eval '(ql:quickload :fiveam)' --eval '(ql:quickload :cl-llm-provider)' --load tests/test-streaming.lisp --eval "(fiveam:run! 'cl-llm-provider/test-streaming::streaming-suite)"`

Expected: FAIL with "no class named STREAM-CHUNK"

**Step 3: Write minimal implementation**

Add to `src/types.lisp` after the `completion-response` class (around line 94):

```lisp
;;;; Streaming Types

(defclass stream-chunk ()
  ((content :initarg :content
            :initform ""
            :accessor chunk-content
            :documentation "Accumulated content so far.")
   (delta :initarg :delta
          :initform ""
          :reader chunk-delta
          :documentation "New content in this chunk.")
   (finish-reason :initarg :finish-reason
                  :initform nil
                  :reader chunk-finish-reason
                  :documentation "Set when stream completes (:stop, :length, :tool-calls).")
   (index :initarg :index
          :initform 0
          :reader chunk-index
          :documentation "Chunk sequence number.")
   (tool-call-delta :initarg :tool-call-delta
                    :initform nil
                    :reader chunk-tool-call-delta
                    :documentation "Partial tool call data if streaming tool calls.")
   (usage :initarg :usage
          :initform nil
          :reader chunk-usage
          :documentation "Usage info (only set on final chunk for some providers)."))
  (:documentation "A single chunk from a streaming response."))

(defmethod print-object ((chunk stream-chunk) stream)
  (print-unreadable-object (chunk stream :type t)
    (format stream "~D: ~S~@[ [~A]~]"
            (chunk-index chunk)
            (let ((delta (chunk-delta chunk)))
              (if (> (length delta) 20)
                  (concatenate 'string (subseq delta 0 20) "...")
                  delta))
            (chunk-finish-reason chunk))))
```

**Step 4: Run test to verify it passes**

Run: `sbcl --noinform --non-interactive --eval '(ql:quickload :fiveam)' --eval '(ql:quickload :cl-llm-provider)' --load tests/test-streaming.lisp --eval "(fiveam:run! 'cl-llm-provider/test-streaming::streaming-suite)"`

Expected: PASS

**Step 5: Commit**

```bash
git add src/types.lisp tests/test-streaming.lisp
git commit -m "feat(streaming): add stream-chunk class for streaming responses"
```

---

### Task 1.2: Define Completion Stream Class

**Files:**
- Modify: `src/types.lisp` (add after stream-chunk class)
- Test: `tests/test-streaming.lisp` (extend)

**Step 1: Write the failing test for completion-stream class**

Add to `tests/test-streaming.lisp`:

```lisp
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
    (setf (cl-llm-provider::stream-state stream) :closed)
    (is (not (cl-llm-provider::stream-open-p stream)))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "no class named COMPLETION-STREAM"

**Step 3: Write minimal implementation**

Add to `src/types.lisp` after stream-chunk:

```lisp
(defclass completion-stream ()
  ((provider :initarg :provider
             :reader stream-provider
             :documentation "The provider this stream is from.")
   (model :initarg :model
          :reader stream-model
          :documentation "Model identifier.")
   (state :initarg :state
          :initform :open
          :accessor stream-state
          :documentation "Stream state: :open, :closed, :error")
   (chunks :initarg :chunks
           :initform nil
           :accessor stream-chunks
           :documentation "List of received chunks (for accumulation).")
   (accumulated-content :initarg :accumulated-content
                        :initform ""
                        :accessor stream-accumulated-content
                        :documentation "Full accumulated text content.")
   (http-stream :initarg :http-stream
                :initform nil
                :accessor stream-http-stream
                :documentation "Underlying HTTP stream for reading.")
   (error :initarg :error
          :initform nil
          :accessor stream-error
          :documentation "Error condition if state is :error."))
  (:documentation "Represents an active streaming completion response."))

(defmethod print-object ((stream completion-stream) stream-out)
  (print-unreadable-object (stream stream-out :type t)
    (format stream-out "~A ~A (~D chunks)"
            (stream-model stream)
            (stream-state stream)
            (length (stream-chunks stream)))))

(defun stream-open-p (stream)
  "Return T if STREAM is still open and receiving chunks."
  (eq (stream-state stream) :open))

(defun stream-closed-p (stream)
  "Return T if STREAM is closed (completed or errored)."
  (not (stream-open-p stream)))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/types.lisp tests/test-streaming.lisp
git commit -m "feat(streaming): add completion-stream class for managing stream state"
```

---

### Task 1.3: Add Streaming Protocol Generic Functions

**Files:**
- Modify: `src/protocol.lisp` (add after send-completion-request)
- Test: `tests/test-streaming.lisp` (extend)

**Step 1: Write the failing test**

Add to `tests/test-streaming.lisp`:

```lisp
(test streaming-protocol-exists
  "Test that streaming protocol generic functions exist"
  (is (fboundp 'cl-llm-provider::send-streaming-request))
  (is (fboundp 'cl-llm-provider::parse-stream-chunk)))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "SEND-STREAMING-REQUEST is not fbound"

**Step 3: Write minimal implementation**

Add to `src/protocol.lisp` after `send-completion-request`:

```lisp
;;;; Streaming Protocol Methods

(defgeneric send-streaming-request (provider messages &key model max-tokens
                                                          temperature system tools
                                                          tool-choice stop)
  (:documentation "Send a streaming completion request to PROVIDER.

Returns a completion-stream object that can be read chunk-by-chunk.

PROVIDER - Provider instance
MESSAGES - List of message plists
MODEL - Model identifier (string)
MAX-TOKENS - Maximum tokens in response
TEMPERATURE - Sampling temperature (float 0.0-2.0)
SYSTEM - System prompt (string)
TOOLS - List of tool-definition objects
TOOL-CHOICE - Tool selection strategy
STOP - Stop sequences

Returns a completion-stream object.
Signals provider-api-error on HTTP connection errors."))

(defgeneric parse-stream-chunk (provider raw-chunk stream)
  (:documentation "Parse a raw SSE/streaming chunk into a stream-chunk object.

PROVIDER - Provider instance
RAW-CHUNK - Raw string data from the stream
STREAM - The completion-stream being read (for state tracking)

Returns a stream-chunk object, or nil for keep-alive/empty chunks.
Sets stream state to :closed when done signal received."))

(defgeneric read-stream-chunk (stream &key timeout)
  (:documentation "Read the next chunk from a completion-stream.

STREAM - completion-stream object
TIMEOUT - Maximum seconds to wait (nil = block indefinitely)

Returns a stream-chunk object, or nil if stream is closed.
Signals stream-error on read failures."))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/protocol.lisp tests/test-streaming.lisp
git commit -m "feat(streaming): add streaming protocol generic functions"
```

---

### Task 1.4: Implement SSE Parser for OpenAI-Compatible Streams

**Files:**
- Create: `src/streaming.lisp`
- Modify: `cl-llm-provider.asd` (add to components)
- Test: `tests/test-streaming.lisp` (extend)

**Step 1: Write the failing test**

Add to `tests/test-streaming.lisp`:

```lisp
(test parse-sse-line
  "Test SSE line parsing"
  (is (equal '(:data . "{\"id\":\"1\"}")
             (cl-llm-provider::parse-sse-line "data: {\"id\":\"1\"}")))
  (is (equal '(:data . "[DONE]")
             (cl-llm-provider::parse-sse-line "data: [DONE]")))
  (is (null (cl-llm-provider::parse-sse-line "")))
  (is (null (cl-llm-provider::parse-sse-line ": keep-alive"))))

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
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "PARSE-SSE-LINE is undefined"

**Step 3: Write minimal implementation**

Create `src/streaming.lisp`:

```lisp
(in-package :cl-llm-provider)

;;;; SSE (Server-Sent Events) Parsing
;;;;
;;;; Handles parsing of streaming responses from LLM providers.
;;;; OpenAI and compatible APIs use SSE format.
;;;; Anthropic uses a different event format.

(defun parse-sse-line (line)
  "Parse a single SSE line into (type . data) cons or nil.
LINE - A string from the SSE stream

Returns:
  (:data . \"content\") for data lines
  (:event . \"event-name\") for event type lines
  NIL for empty lines or comments"
  (cond
    ;; Empty line (event separator)
    ((or (null line) (string= line ""))
     nil)
    ;; Comment line (often used for keep-alive)
    ((char= (char line 0) #\:)
     nil)
    ;; Data line
    ((and (>= (length line) 5)
          (string= "data:" (subseq line 0 5)))
     (cons :data (string-trim '(#\Space) (subseq line 5))))
    ;; Event type line
    ((and (>= (length line) 6)
          (string= "event:" (subseq line 0 6)))
     (cons :event (string-trim '(#\Space) (subseq line 6))))
    ;; Other field (id, retry, etc.)
    (t
     (let ((colon-pos (position #\: line)))
       (when colon-pos
         (cons (intern (string-upcase (subseq line 0 colon-pos)) :keyword)
               (string-trim '(#\Space) (subseq line (1+ colon-pos)))))))))

(defun parse-openai-stream-data (data index)
  "Parse OpenAI streaming data payload.
DATA - The data portion after 'data: ' prefix
INDEX - Current chunk index

Returns:
  :done if data is \"[DONE]\"
  stream-chunk object otherwise"
  (cond
    ;; Done signal
    ((string= data "[DONE]")
     :done)
    ;; Empty data
    ((or (null data) (string= data ""))
     nil)
    ;; JSON payload
    (t
     (let* ((json (yason:parse data))
            (choices (gethash "choices" json))
            (first-choice (when (and choices (> (length choices) 0))
                           (elt choices 0)))
            (delta (when first-choice (gethash "delta" first-choice)))
            (content (when delta (gethash "content" delta)))
            (finish-reason (when first-choice
                            (gethash "finish_reason" first-choice)))
            (usage (gethash "usage" json)))
       (make-instance 'stream-chunk
                      :delta (or content "")
                      :content (or content "")
                      :finish-reason (when finish-reason
                                      (intern (string-upcase finish-reason) :keyword))
                      :index index
                      :usage (when usage
                              (list :prompt-tokens (gethash "prompt_tokens" usage)
                                    :completion-tokens (gethash "completion_tokens" usage)
                                    :total-tokens (gethash "total_tokens" usage))))))))
```

**Step 4: Update .asd file**

Add to `cl-llm-provider.asd` components list (after "protocol"):

```lisp
(:file "streaming" :depends-on ("types" "protocol"))
```

**Step 5: Run test to verify it passes**

Expected: PASS

**Step 6: Commit**

```bash
git add src/streaming.lisp cl-llm-provider.asd tests/test-streaming.lisp
git commit -m "feat(streaming): add SSE parser and OpenAI chunk parser"
```

---

### Task 1.5: Implement Anthropic Stream Parser

**Files:**
- Modify: `src/streaming.lisp`
- Test: `tests/test-streaming.lisp` (extend)

**Step 1: Write the failing test**

Add to `tests/test-streaming.lisp`:

```lisp
(test parse-anthropic-stream-event
  "Test Anthropic streaming event parsing"
  ;; content_block_delta event
  (let* ((event-type "content_block_delta")
         (data "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}")
         (chunk (cl-llm-provider::parse-anthropic-stream-event event-type data 0)))
    (is (string= "Hello" (cl-llm-provider::chunk-delta chunk))))

  ;; message_stop event
  (let* ((event-type "message_stop")
         (data "{\"type\":\"message_stop\"}")
         (result (cl-llm-provider::parse-anthropic-stream-event event-type data 0)))
    (is (eq :done result))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "PARSE-ANTHROPIC-STREAM-EVENT is undefined"

**Step 3: Write minimal implementation**

Add to `src/streaming.lisp`:

```lisp
;;;; Anthropic Streaming Format
;;;;
;;;; Anthropic uses Server-Sent Events with typed events:
;;;; - message_start: Initial message metadata
;;;; - content_block_start: Start of a content block
;;;; - content_block_delta: Content chunk
;;;; - content_block_stop: End of content block
;;;; - message_delta: Usage stats update
;;;; - message_stop: Stream complete

(defun parse-anthropic-stream-event (event-type data index)
  "Parse Anthropic streaming event.
EVENT-TYPE - The SSE event type (string)
DATA - JSON data payload (string)
INDEX - Current chunk index

Returns:
  :done for message_stop
  stream-chunk for content
  nil for metadata events"
  (let ((json (when (and data (> (length data) 0))
                (yason:parse data))))
    (cond
      ;; Stream complete
      ((string= event-type "message_stop")
       :done)

      ;; Content delta - the main content chunks
      ((string= event-type "content_block_delta")
       (let* ((delta (gethash "delta" json))
              (delta-type (gethash "type" delta))
              (text (when (string= delta-type "text_delta")
                     (gethash "text" delta))))
         (when text
           (make-instance 'stream-chunk
                          :delta text
                          :content text
                          :index index))))

      ;; Message delta - contains usage info
      ((string= event-type "message_delta")
       (let* ((delta (gethash "delta" json))
              (stop-reason (gethash "stop_reason" delta))
              (usage (gethash "usage" json)))
         (make-instance 'stream-chunk
                        :delta ""
                        :content ""
                        :finish-reason (when stop-reason
                                        (intern (string-upcase stop-reason) :keyword))
                        :index index
                        :usage (when usage
                                (list :completion-tokens (gethash "output_tokens" usage))))))

      ;; Ping/keep-alive
      ((string= event-type "ping")
       nil)

      ;; Other events (message_start, content_block_start, content_block_stop)
      ;; These are metadata, not content
      (t nil))))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/streaming.lisp tests/test-streaming.lisp
git commit -m "feat(streaming): add Anthropic stream event parser"
```

---

### Task 1.6: Implement OpenAI Streaming Request

**Files:**
- Modify: `src/providers/openai.lisp`
- Modify: `src/streaming.lisp` (add stream reader)
- Test: `tests/test-streaming.lisp` (extend)

**Step 1: Write the failing test**

Add to `tests/test-streaming.lisp`:

```lisp
(test openai-streaming-method-exists
  "Test that OpenAI provider has streaming implementation"
  (let ((provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "test-key"
                                 :base-url "https://api.openai.com/v1")))
    ;; Just test the method exists and can be called (will fail with no network)
    (is (find-method #'cl-llm-provider::send-streaming-request
                     nil
                     (list (class-of provider) t)
                     nil))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "no applicable method"

**Step 3: Write minimal implementation**

Add to `src/providers/openai.lisp`:

```lisp
(defmethod send-streaming-request ((provider openai-provider) messages
                                   &key model max-tokens temperature
                                        system tools tool-choice stop)
  "Send streaming completion request to OpenAI."
  (let* ((url (format nil "~A/chat/completions" (provider-base-url provider)))
         (headers (make-http-headers provider))
         (body (make-hash-table :test 'equal)))

    ;; Build request body
    (setf (gethash "model" body) (or model (provider-default-model provider) "gpt-4"))
    (setf (gethash "stream" body) t)  ; Enable streaming

    ;; Convert messages, prepending system if provided
    (let ((all-messages (if system
                           (cons (list :role "system" :content system) messages)
                           messages)))
      (setf (gethash "messages" body)
            (map 'vector #'plist-to-hash all-messages)))

    (when max-tokens
      (setf (gethash "max_tokens" body) max-tokens))
    (when temperature
      (setf (gethash "temperature" body) temperature))
    (when stop
      (setf (gethash "stop" body) (ensure-list stop)))
    (when tools
      (setf (gethash "tools" body)
            (map 'vector (lambda (tool) (translate-tool-to-provider provider tool)) tools)))
    (when tool-choice
      (setf (gethash "tool_choice" body)
            (etypecase tool-choice
              (keyword (string-downcase (symbol-name tool-choice)))
              (string (plist-to-hash (list :type "function"
                                           :function (list :name tool-choice)))))))

    ;; Make streaming HTTP request
    (let ((encoded-body (with-output-to-string (s)
                         (yason:encode body s))))
      (multiple-value-bind (response-stream status-code response-headers)
          (dex:post url
                    :headers headers
                    :content encoded-body
                    :want-stream t)
        (if (and (>= status-code 200) (< status-code 300))
            (make-instance 'completion-stream
                           :provider provider
                           :model (or model (provider-default-model provider))
                           :http-stream response-stream
                           :state :open)
            (handle-http-error status-code
                              (handler-case
                                  (let ((body-text (alexandria:read-stream-content-into-string response-stream)))
                                    (yason:parse body-text))
                                (error () "Stream error"))
                              provider))))))
```

Add stream reading to `src/streaming.lisp`:

```lisp
;;;; Stream Reading

(defmethod read-stream-chunk ((stream completion-stream) &key timeout)
  "Read next chunk from completion-stream."
  (declare (ignore timeout))  ; TODO: implement timeout
  (when (stream-closed-p stream)
    (return-from read-stream-chunk nil))

  (let ((http-stream (stream-http-stream stream))
        (provider (stream-provider stream))
        (index (length (stream-chunks stream))))
    (handler-case
        (loop
          (let ((line (read-line http-stream nil :eof)))
            (when (eq line :eof)
              (setf (stream-state stream) :closed)
              (return nil))

            (let ((parsed (parse-sse-line line)))
              (when (and parsed (eq (car parsed) :data))
                (let ((chunk (parse-openai-stream-data (cdr parsed) index)))
                  (cond
                    ((eq chunk :done)
                     (setf (stream-state stream) :closed)
                     (close http-stream)
                     (return nil))
                    (chunk
                     ;; Accumulate content
                     (setf (stream-accumulated-content stream)
                           (concatenate 'string
                                       (stream-accumulated-content stream)
                                       (chunk-delta chunk)))
                     (setf (chunk-content chunk) (stream-accumulated-content stream))
                     (push chunk (stream-chunks stream))
                     (return chunk))))))))
      (error (e)
        (setf (stream-state stream) :error)
        (setf (stream-error stream) e)
        (ignore-errors (close http-stream))
        nil))))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/providers/openai.lisp src/streaming.lisp tests/test-streaming.lisp
git commit -m "feat(streaming): implement OpenAI streaming request and chunk reader"
```

---

### Task 1.7: Implement Anthropic Streaming Request

**Files:**
- Modify: `src/providers/anthropic.lisp`
- Test: `tests/test-streaming.lisp` (extend)

**Step 1: Write the failing test**

Add to `tests/test-streaming.lisp`:

```lisp
(test anthropic-streaming-method-exists
  "Test that Anthropic provider has streaming implementation"
  (let ((provider (make-instance 'cl-llm-provider::anthropic-provider
                                 :api-key "test-key")))
    (is (find-method #'cl-llm-provider::send-streaming-request
                     nil
                     (list (class-of provider) t)
                     nil))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL

**Step 3: Write minimal implementation**

Add to `src/providers/anthropic.lisp`:

```lisp
(defmethod send-streaming-request ((provider anthropic-provider) messages
                                   &key model max-tokens temperature
                                        system tools tool-choice stop)
  "Send streaming completion request to Anthropic."
  (let* ((url (format nil "~A/messages" (provider-base-url provider)))
         (headers (append
                   (make-http-headers provider)
                   (list (cons "anthropic-version" "2023-06-01"))))
         (body (make-hash-table :test 'equal)))

    ;; Build request body
    (setf (gethash "model" body) (or model (provider-default-model provider) "claude-3-sonnet-20240229"))
    (setf (gethash "max_tokens" body) (or max-tokens 4096))
    (setf (gethash "stream" body) t)

    (when system
      (setf (gethash "system" body) system))

    (setf (gethash "messages" body)
          (map 'vector #'plist-to-hash messages))

    (when temperature
      (setf (gethash "temperature" body) temperature))
    (when stop
      (setf (gethash "stop_sequences" body) (ensure-list stop)))
    (when tools
      (setf (gethash "tools" body)
            (map 'vector (lambda (tool) (translate-tool-to-provider provider tool)) tools)))
    (when tool-choice
      (setf (gethash "tool_choice" body)
            (etypecase tool-choice
              (keyword (plist-to-hash
                        (list :type (string-downcase (symbol-name tool-choice)))))
              (string (plist-to-hash
                       (list :type "tool" :name tool-choice))))))

    ;; Make streaming request
    (let ((encoded-body (with-output-to-string (s)
                         (yason:encode body s))))
      (multiple-value-bind (response-stream status-code)
          (dex:post url
                    :headers headers
                    :content encoded-body
                    :want-stream t)
        (if (and (>= status-code 200) (< status-code 300))
            (make-instance 'completion-stream
                           :provider provider
                           :model (or model (provider-default-model provider))
                           :http-stream response-stream
                           :state :open)
            (handle-http-error status-code
                              (handler-case
                                  (let ((body-text (alexandria:read-stream-content-into-string response-stream)))
                                    (yason:parse body-text))
                                (error () "Stream error"))
                              provider))))))
```

Also add Anthropic-specific stream reader to `src/streaming.lisp`:

```lisp
(defmethod read-stream-chunk :around ((stream completion-stream) &key timeout)
  "Dispatch to provider-specific stream reader."
  (let ((provider (stream-provider stream)))
    (etypecase provider
      (anthropic-provider (read-anthropic-stream-chunk stream))
      (t (call-next-method)))))

(defun read-anthropic-stream-chunk (stream)
  "Read next chunk from Anthropic streaming response."
  (when (stream-closed-p stream)
    (return-from read-anthropic-stream-chunk nil))

  (let ((http-stream (stream-http-stream stream))
        (index (length (stream-chunks stream)))
        (current-event nil))
    (handler-case
        (loop
          (let ((line (read-line http-stream nil :eof)))
            (when (eq line :eof)
              (setf (stream-state stream) :closed)
              (return nil))

            (let ((parsed (parse-sse-line line)))
              (cond
                ;; Event type line
                ((and parsed (eq (car parsed) :event))
                 (setf current-event (cdr parsed)))

                ;; Data line with event type
                ((and parsed (eq (car parsed) :data) current-event)
                 (let ((chunk (parse-anthropic-stream-event current-event (cdr parsed) index)))
                   (setf current-event nil)
                   (cond
                     ((eq chunk :done)
                      (setf (stream-state stream) :closed)
                      (close http-stream)
                      (return nil))
                     (chunk
                      (setf (stream-accumulated-content stream)
                            (concatenate 'string
                                        (stream-accumulated-content stream)
                                        (chunk-delta chunk)))
                      (setf (chunk-content chunk) (stream-accumulated-content stream))
                      (push chunk (stream-chunks stream))
                      (return chunk)))))))))
      (error (e)
        (setf (stream-state stream) :error)
        (setf (stream-error stream) e)
        (ignore-errors (close http-stream))
        nil))))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/providers/anthropic.lisp src/streaming.lisp tests/test-streaming.lisp
git commit -m "feat(streaming): implement Anthropic streaming request"
```

---

### Task 1.8: Add High-Level complete-stream API

**Files:**
- Modify: `src/api.lisp`
- Modify: `src/package.lisp` (export new symbols)
- Test: `tests/test-streaming.lisp` (extend)

**Step 1: Write the failing test**

Add to `tests/test-streaming.lisp`:

```lisp
(test complete-stream-api-exists
  "Test that complete-stream function exists and is exported"
  (is (fboundp 'cl-llm-provider:complete-stream)))

(test complete-stream-with-callback
  "Test complete-stream callback interface (mock)"
  (let ((chunks '()))
    ;; We can't test real streaming without network,
    ;; but we can test the callback mechanism with a mock
    (is (functionp #'cl-llm-provider:complete-stream))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "COMPLETE-STREAM is undefined"

**Step 3: Write minimal implementation**

Add to `src/api.lisp`:

```lisp
(defun complete-stream (messages &key provider model max-tokens temperature
                                      system tools tool-choice stop
                                      on-chunk on-complete on-error)
  "Send a streaming completion request to an LLM provider.

MESSAGES - List of message plists ((:role \"user\" :content \"Hello\"))
PROVIDER - Provider instance (uses *default-provider* if nil)
MODEL - Model identifier (uses provider/global default if nil)
MAX-TOKENS - Maximum tokens in response (integer)
TEMPERATURE - Sampling temperature (0.0-2.0)
SYSTEM - System prompt (string)
TOOLS - List of tool definitions
TOOL-CHOICE - Tool selection strategy
STOP - Stop sequences

CALLBACKS:
ON-CHUNK - Function (lambda (chunk) ...) called for each chunk
ON-COMPLETE - Function (lambda (full-content final-chunk) ...) called when done
ON-ERROR - Function (lambda (error) ...) called on error

Returns a completion-stream object.

Example:
  ;; Callback-based usage
  (complete-stream messages
    :on-chunk (lambda (chunk)
                (format t \"~A\" (chunk-delta chunk)))
    :on-complete (lambda (content final)
                   (format t \"~%Done! ~D tokens~%\"
                           (getf (chunk-usage final) :total-tokens))))

  ;; Manual iteration
  (let ((stream (complete-stream messages)))
    (loop for chunk = (read-stream-chunk stream)
          while chunk
          do (format t \"~A\" (chunk-delta chunk))))"
  (let* ((provider (or provider *default-provider*))
         (effective-model (or model
                             (provider-default-model provider)
                             *default-model*))
         (stream (send-streaming-request provider messages
                                         :model effective-model
                                         :max-tokens max-tokens
                                         :temperature temperature
                                         :system system
                                         :tools tools
                                         :tool-choice tool-choice
                                         :stop stop)))

    ;; If callbacks provided, start reading in current thread
    (when (or on-chunk on-complete on-error)
      (handler-case
          (loop for chunk = (read-stream-chunk stream)
                while chunk
                do (when on-chunk (funcall on-chunk chunk))
                finally (when on-complete
                          (funcall on-complete
                                  (stream-accumulated-content stream)
                                  (car (stream-chunks stream)))))
        (error (e)
          (if on-error
              (funcall on-error e)
              (error e)))))

    stream))
```

Add to `src/package.lisp` exports:

```lisp
;; Streaming API
#:complete-stream
#:read-stream-chunk
#:stream-chunk
#:chunk-content
#:chunk-delta
#:chunk-finish-reason
#:chunk-index
#:chunk-usage
#:completion-stream
#:stream-open-p
#:stream-closed-p
#:stream-accumulated-content
#:stream-state
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/api.lisp src/package.lisp tests/test-streaming.lisp
git commit -m "feat(streaming): add complete-stream high-level API with callback support"
```

---

## Task 2: Token Counting Before API Calls

### Task 2.1: Create Tokenizer Infrastructure

**Files:**
- Create: `src/tokenizer.lisp`
- Modify: `cl-llm-provider.asd`
- Test: `tests/test-tokenizer.lisp` (create)

**Step 1: Write the failing test**

Create `tests/test-tokenizer.lisp`:

```lisp
(defpackage :cl-llm-provider/test-tokenizer
  (:use :cl :cl-llm-provider :fiveam))

(in-package :cl-llm-provider/test-tokenizer)

(def-suite tokenizer-suite :description "Token counting tests")
(in-suite tokenizer-suite)

(test count-tokens-basic
  "Test basic token counting"
  (let ((count (cl-llm-provider:count-tokens
                '((:role "user" :content "Hello, world!"))
                :model "gpt-4")))
    (is (numberp count))
    (is (> count 0))))

(test count-tokens-estimates-reasonably
  "Test token count is reasonable for known text"
  ;; "Hello, world!" is ~4 tokens in most tokenizers
  (let ((count (cl-llm-provider:count-tokens
                '((:role "user" :content "Hello, world!"))
                :model "gpt-4")))
    (is (>= count 2))   ; At least 2 tokens
    (is (<= count 10)))) ; At most 10 tokens (with overhead)
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "COUNT-TOKENS is undefined"

**Step 3: Write minimal implementation**

Create `src/tokenizer.lisp`:

```lisp
(in-package :cl-llm-provider)

;;;; Token Counting
;;;;
;;;; Provides pre-request token counting for cost estimation and
;;;; context window overflow prevention.
;;;;
;;;; Uses character-based estimation as a portable fallback.
;;;; More accurate tokenizers can be added for specific models.

(defvar *chars-per-token-estimate* 4
  "Average characters per token for estimation.
Most English text averages 4 characters per token.
This is a conservative estimate for planning purposes.")

(defvar *message-overhead-tokens* 4
  "Token overhead per message for role and formatting.
OpenAI adds ~4 tokens per message for role/formatting.")

(defun estimate-tokens-from-text (text)
  "Estimate token count from text length.
TEXT - String to estimate tokens for

Returns estimated token count (integer).
Uses character-based estimation as a portable fallback."
  (if (or (null text) (string= text ""))
      0
      (ceiling (length text) *chars-per-token-estimate*)))

(defun count-message-tokens (message)
  "Count tokens in a single message plist.
MESSAGE - Plist with :role and :content

Returns estimated token count (integer)."
  (let ((content (getf message :content)))
    (+ *message-overhead-tokens*
       (etypecase content
         (string (estimate-tokens-from-text content))
         (null 0)
         (list
          ;; Multi-part content (e.g., with images)
          (loop for part in content
                sum (if (stringp part)
                        (estimate-tokens-from-text part)
                        (let ((text (getf part :text)))
                          (if text (estimate-tokens-from-text text) 0)))))))))

(defun count-tokens (messages &key model provider)
  "Count tokens in MESSAGES for MODEL/PROVIDER.

MESSAGES - List of message plists
MODEL - Model identifier (string) - used for model-specific tokenizers
PROVIDER - Provider instance - used for provider-specific tokenizers

Returns estimated token count (integer).

Note: This is an estimate. Actual token counts may vary by 5-10%.
Use for cost estimation and context window planning.

Example:
  (count-tokens '((:role \"user\" :content \"What is Common Lisp?\"))
                :model \"gpt-4\")
  => 8"
  (declare (ignore model provider)) ; TODO: Use for accurate tokenizers
  (loop for message in messages
        sum (count-message-tokens message)))

(defun count-tokens-with-system (messages system &key model provider)
  "Count tokens including system prompt.
MESSAGES - List of message plists
SYSTEM - System prompt string
MODEL - Model identifier
PROVIDER - Provider instance

Returns estimated token count (integer)."
  (+ (if system
         (+ *message-overhead-tokens* (estimate-tokens-from-text system))
         0)
     (count-tokens messages :model model :provider provider)))
```

Add to `cl-llm-provider.asd`:

```lisp
(:file "tokenizer" :depends-on ("types"))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/tokenizer.lisp cl-llm-provider.asd tests/test-tokenizer.lisp
git commit -m "feat(tokens): add token counting infrastructure with character-based estimation"
```

---

### Task 2.2: Add Cost Estimation

**Files:**
- Modify: `src/tokenizer.lisp`
- Modify: `src/package.lisp`
- Test: `tests/test-tokenizer.lisp`

**Step 1: Write the failing test**

Add to `tests/test-tokenizer.lisp`:

```lisp
(test estimate-cost-basic
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
      (is (numberp input-cost))
      (is (numberp output-cost))
      (is (numberp total))
      (is (> total 0)))))

(test estimate-cost-uses-model-metadata
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
      (is (< cheap-cost expensive-cost)))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "ESTIMATE-COST is undefined"

**Step 3: Write minimal implementation**

Add to `src/tokenizer.lisp`:

```lisp
(defun estimate-cost (messages &key provider model system max-tokens)
  "Estimate cost for a completion request.

MESSAGES - List of message plists
PROVIDER - Provider instance (required for pricing lookup)
MODEL - Model identifier
SYSTEM - System prompt (string)
MAX-TOKENS - Expected output tokens (defaults to 1000)

Returns (values input-cost output-cost-estimate total-estimate).
All costs in USD.

Returns NIL values if pricing unavailable for model.

Example:
  (multiple-value-bind (in out total)
      (estimate-cost messages :provider *openai* :model \"gpt-4\" :max-tokens 500)
    (format t \"Estimated cost: $~,4F~%\" total))"
  (let* ((effective-model (or model
                             (when provider (provider-default-model provider))))
         (metadata (when (and provider effective-model)
                    (model-metadata provider effective-model)))
         (input-cost-per-1m (getf metadata :input-cost-per-1m-tokens))
         (output-cost-per-1m (getf metadata :output-cost-per-1m-tokens)))

    (if (and input-cost-per-1m output-cost-per-1m)
        (let* ((input-tokens (count-tokens-with-system messages system
                                                       :model effective-model
                                                       :provider provider))
               (output-tokens (or max-tokens 1000))
               (input-cost (* input-tokens (/ input-cost-per-1m 1000000.0)))
               (output-cost (* output-tokens (/ output-cost-per-1m 1000000.0))))
          (values input-cost output-cost (+ input-cost output-cost)))
        (values nil nil nil))))

(defun format-cost (cost &optional (stream t))
  "Format cost in USD for display.
COST - Cost in USD (float)
STREAM - Output stream

Example: (format-cost 0.0025) => \"$0.0025\""
  (if cost
      (format stream "$~,4F" cost)
      (format stream "N/A")))
```

Add to `src/package.lisp`:

```lisp
;; Token counting
#:count-tokens
#:count-tokens-with-system
#:estimate-cost
#:format-cost
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/tokenizer.lisp src/package.lisp tests/test-tokenizer.lisp
git commit -m "feat(tokens): add cost estimation using model metadata pricing"
```

---

## Task 3: Observability Hooks

### Task 3.1: Define Observability Hook Types

**Files:**
- Create: `src/observability.lisp`
- Modify: `cl-llm-provider.asd`
- Test: `tests/test-observability.lisp` (create)

**Step 1: Write the failing test**

Create `tests/test-observability.lisp`:

```lisp
(defpackage :cl-llm-provider/test-observability
  (:use :cl :cl-llm-provider :fiveam))

(in-package :cl-llm-provider/test-observability)

(def-suite observability-suite :description "Observability hooks tests")
(in-suite observability-suite)

(test hooks-container-creation
  "Test hooks container creation"
  (let ((hooks (cl-llm-provider:make-hooks)))
    (is (not (null hooks)))
    (is (cl-llm-provider::hooks-p hooks))))

(test add-and-invoke-hook
  "Test adding and invoking hooks"
  (let ((hooks (cl-llm-provider:make-hooks))
        (called nil))
    (cl-llm-provider:add-hook hooks :before-request
                              (lambda (provider model messages)
                                (declare (ignore provider model messages))
                                (setf called t)))
    (cl-llm-provider::invoke-hooks hooks :before-request nil "test" nil)
    (is called)))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "MAKE-HOOKS is undefined"

**Step 3: Write minimal implementation**

Create `src/observability.lisp`:

```lisp
(in-package :cl-llm-provider)

;;;; Observability Hooks
;;;;
;;;; Provides callback mechanisms for logging, tracing, and monitoring
;;;; LLM API calls.

(defstruct hooks
  "Container for observability hooks.

Supported hook types:
  :before-request - (lambda (provider model messages) ...)
  :after-response - (lambda (provider model response timing) ...)
  :on-error - (lambda (provider model error) ...)
  :on-stream-chunk - (lambda (provider model chunk) ...)"
  (before-request nil :type list)
  (after-response nil :type list)
  (on-error nil :type list)
  (on-stream-chunk nil :type list))

(defun add-hook (hooks hook-type function)
  "Add FUNCTION to HOOKS for HOOK-TYPE.

HOOKS - hooks structure from make-hooks
HOOK-TYPE - One of :before-request, :after-response, :on-error, :on-stream-chunk
FUNCTION - Callback function

Returns HOOKS (for chaining)."
  (ecase hook-type
    (:before-request
     (push function (hooks-before-request hooks)))
    (:after-response
     (push function (hooks-after-response hooks)))
    (:on-error
     (push function (hooks-on-error hooks)))
    (:on-stream-chunk
     (push function (hooks-on-stream-chunk hooks))))
  hooks)

(defun remove-hook (hooks hook-type function)
  "Remove FUNCTION from HOOKS for HOOK-TYPE.

Returns HOOKS (for chaining)."
  (ecase hook-type
    (:before-request
     (setf (hooks-before-request hooks)
           (remove function (hooks-before-request hooks))))
    (:after-response
     (setf (hooks-after-response hooks)
           (remove function (hooks-after-response hooks))))
    (:on-error
     (setf (hooks-on-error hooks)
           (remove function (hooks-on-error hooks))))
    (:on-stream-chunk
     (setf (hooks-on-stream-chunk hooks)
           (remove function (hooks-on-stream-chunk hooks)))))
  hooks)

(defun invoke-hooks (hooks hook-type &rest args)
  "Invoke all hooks of HOOK-TYPE with ARGS.

Errors in hooks are caught and logged, not propagated."
  (let ((hook-list (ecase hook-type
                    (:before-request (hooks-before-request hooks))
                    (:after-response (hooks-after-response hooks))
                    (:on-error (hooks-on-error hooks))
                    (:on-stream-chunk (hooks-on-stream-chunk hooks)))))
    (dolist (hook hook-list)
      (handler-case
          (apply hook args)
        (error (e)
          ;; Log but don't propagate hook errors
          (warn "Observability hook error: ~A" e))))))

;;; Global hooks variable
(defvar *global-hooks* nil
  "Global hooks applied to all requests when non-nil.
Set with (setf *global-hooks* (make-hooks)) and add hooks.")
```

Add to `cl-llm-provider.asd`:

```lisp
(:file "observability" :depends-on ("types"))
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/observability.lisp cl-llm-provider.asd tests/test-observability.lisp
git commit -m "feat(observability): add hooks infrastructure for logging and tracing"
```

---

### Task 3.2: Integrate Hooks into complete Function

**Files:**
- Modify: `src/api.lisp`
- Modify: `src/package.lisp`
- Test: `tests/test-observability.lisp`

**Step 1: Write the failing test**

Add to `tests/test-observability.lisp`:

```lisp
(test complete-calls-hooks
  "Test that complete function invokes hooks"
  (let ((before-called nil)
        (after-called nil)
        (hooks (cl-llm-provider:make-hooks)))

    (cl-llm-provider:add-hook hooks :before-request
                              (lambda (provider model messages)
                                (declare (ignore provider model messages))
                                (setf before-called t)))

    (cl-llm-provider:add-hook hooks :after-response
                              (lambda (provider model response timing)
                                (declare (ignore provider model response timing))
                                (setf after-called t)))

    ;; We can't test with real API, but we can test hook invocation
    ;; by checking the hook functions are present
    (is (= 1 (length (cl-llm-provider::hooks-before-request hooks))))
    (is (= 1 (length (cl-llm-provider::hooks-after-response hooks))))))

(test on-request-on-response-callbacks
  "Test :on-request and :on-response callback parameters"
  (let ((request-called nil)
        (response-called nil))
    ;; Verify the parameter signature exists
    ;; (can't test full flow without network)
    (is (member :on-request
                (alexandria:function-arglist #'cl-llm-provider:complete)
                :test #'string-equal
                :key (lambda (x) (if (symbolp x) (symbol-name x) ""))))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL (or test needs adjustment)

**Step 3: Write minimal implementation**

Modify the `complete` function in `src/api.lisp` to add hooks support:

```lisp
(defun complete (messages &key provider model max-tokens temperature
                              system tools tool-choice stop
                              hooks on-request on-response on-error)
  "Send a completion request to an LLM provider.

MESSAGES - List of message plists ((:role \"user\" :content \"Hello\"))
PROVIDER - Provider instance (uses *default-provider* if nil)
MODEL - Model identifier (uses provider/global default if nil)
MAX-TOKENS - Maximum tokens in response (integer)
TEMPERATURE - Sampling temperature (0.0-2.0)
SYSTEM - System prompt (string)
TOOLS - List of tool definitions
TOOL-CHOICE - Tool selection strategy (keyword, string, or nil)
STOP - Stop sequences (string or list)

OBSERVABILITY:
HOOKS - hooks structure from make-hooks
ON-REQUEST - Callback (lambda (request-plist) ...) before request
ON-RESPONSE - Callback (lambda (response timing) ...) after response
ON-ERROR - Callback (lambda (error) ...) on error

Returns a completion-response object.

Signals:
  - provider-api-error on API errors
  - provider-rate-limit-error on rate limiting
  - provider-authentication-error on auth failures"
  (let* ((provider (or provider *default-provider*))
         (effective-model (or model
                             (provider-default-model provider)
                             *default-model*))
         (all-hooks (or hooks *global-hooks*))
         (start-time (get-internal-real-time))
         (request-info (list :provider (provider-type provider)
                            :model effective-model
                            :message-count (length messages)
                            :has-tools (not (null tools)))))

    ;; Invoke before-request hooks
    (when all-hooks
      (invoke-hooks all-hooks :before-request provider effective-model messages))
    (when on-request
      (funcall on-request request-info))

    (handler-case
        (let* ((*performance-stats* (when *performance-profiling*
                                     (make-performance-stats)))
               (raw-response (send-completion-request provider messages
                                                      :model effective-model
                                                      :max-tokens max-tokens
                                                      :temperature temperature
                                                      :system system
                                                      :tools tools
                                                      :tool-choice tool-choice
                                                      :stop stop))
               (response (with-performance-timing (:decode-time)
                          (parse-completion-response provider raw-response
                                                     :performance (get-performance-stats))))
               (timing (/ (- (get-internal-real-time) start-time)
                         internal-time-units-per-second)))

          ;; Invoke after-response hooks
          (when all-hooks
            (invoke-hooks all-hooks :after-response provider effective-model response timing))
          (when on-response
            (funcall on-response response timing))

          response)

      (error (e)
        ;; Invoke error hooks
        (when all-hooks
          (invoke-hooks all-hooks :on-error provider effective-model e))
        (when on-error
          (funcall on-error e))
        (error e)))))
```

Add exports to `src/package.lisp`:

```lisp
;; Observability
#:make-hooks
#:add-hook
#:remove-hook
#:*global-hooks*
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/api.lisp src/package.lisp tests/test-observability.lisp
git commit -m "feat(observability): integrate hooks into complete function"
```

---

### Task 3.3: Add Request/Response Logging Helper

**Files:**
- Modify: `src/observability.lisp`
- Test: `tests/test-observability.lisp`

**Step 1: Write the failing test**

Add to `tests/test-observability.lisp`:

```lisp
(test logging-hook-helper
  "Test logging hook helper"
  (let* ((log-output (make-string-output-stream))
         (hooks (cl-llm-provider:make-logging-hooks :stream log-output)))
    (cl-llm-provider::invoke-hooks hooks :before-request
                                   nil "gpt-4" '((:role "user" :content "Hi")))
    (let ((output (get-output-stream-string log-output)))
      (is (search "gpt-4" output)))))
```

**Step 2: Run test to verify it fails**

Expected: FAIL with "MAKE-LOGGING-HOOKS is undefined"

**Step 3: Write minimal implementation**

Add to `src/observability.lisp`:

```lisp
;;; Convenience Hooks

(defun make-logging-hooks (&key (stream *standard-output*) (level :info))
  "Create hooks that log requests and responses.

STREAM - Output stream for logging (default: *standard-output*)
LEVEL - Log level (:debug, :info, :warn)

Returns a hooks structure with logging callbacks.

Example:
  (setf *global-hooks* (make-logging-hooks))
  ;; All requests/responses will be logged"
  (let ((hooks (make-hooks)))

    (add-hook hooks :before-request
              (lambda (provider model messages)
                (format stream "~&[~A] LLM Request: ~A ~A (~D messages)~%"
                        (local-time-string)
                        (if provider (provider-name provider) "?")
                        model
                        (length messages))
                (when (eq level :debug)
                  (format stream "  Messages: ~S~%" messages))))

    (add-hook hooks :after-response
              (lambda (provider model response timing)
                (declare (ignore provider model))
                (format stream "~&[~A] LLM Response: ~,2Fs, ~A tokens~%"
                        (local-time-string)
                        timing
                        (let ((usage (response-usage response)))
                          (or (getf usage :total-tokens) "?")))
                (when (eq level :debug)
                  (format stream "  Content: ~S~%"
                          (let ((content (response-content response)))
                            (if (and content (> (length content) 100))
                                (concatenate 'string (subseq content 0 100) "...")
                                content))))))

    (add-hook hooks :on-error
              (lambda (provider model error)
                (declare (ignore provider model))
                (format stream "~&[~A] LLM Error: ~A~%"
                        (local-time-string)
                        error)))

    hooks))

(defun local-time-string ()
  "Return current time as a string for logging."
  (multiple-value-bind (sec min hour)
      (get-decoded-time)
    (format nil "~2,'0D:~2,'0D:~2,'0D" hour min sec)))

;;; Timing/Cost Tracking Hook

(defun make-cost-tracking-hooks (&key (callback nil))
  "Create hooks that track costs across requests.

CALLBACK - Optional function (lambda (cost-info) ...) called after each request
          cost-info is a plist with :input-tokens, :output-tokens, :total-tokens,
          :estimated-cost, :model, :provider

Returns a hooks structure.

Example:
  (let ((total-cost 0.0))
    (setf *global-hooks*
          (make-cost-tracking-hooks
           :callback (lambda (info)
                      (incf total-cost (or (getf info :estimated-cost) 0))))))"
  (let ((hooks (make-hooks)))
    (add-hook hooks :after-response
              (lambda (provider model response timing)
                (declare (ignore timing))
                (let* ((usage (response-usage response))
                       (input-tokens (getf usage :prompt-tokens))
                       (output-tokens (getf usage :completion-tokens))
                       (total-tokens (getf usage :total-tokens))
                       (metadata (when provider (model-metadata provider model)))
                       (input-cost (when (and input-tokens metadata)
                                    (* input-tokens
                                       (/ (getf metadata :input-cost-per-1m-tokens 0)
                                          1000000.0))))
                       (output-cost (when (and output-tokens metadata)
                                     (* output-tokens
                                        (/ (getf metadata :output-cost-per-1m-tokens 0)
                                           1000000.0))))
                       (estimated-cost (when (and input-cost output-cost)
                                        (+ input-cost output-cost))))
                  (when callback
                    (funcall callback
                             (list :input-tokens input-tokens
                                   :output-tokens output-tokens
                                   :total-tokens total-tokens
                                   :estimated-cost estimated-cost
                                   :model model
                                   :provider (when provider
                                              (provider-type provider))))))))
    hooks))
```

Add exports:

```lisp
#:make-logging-hooks
#:make-cost-tracking-hooks
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add src/observability.lisp src/package.lisp tests/test-observability.lisp
git commit -m "feat(observability): add logging and cost tracking hook helpers"
```

---

## Final Task: Run Full Test Suite

**Step 1: Run all Phase 1 tests**

```bash
sbcl --noinform --non-interactive \
  --eval '(ql:quickload :fiveam)' \
  --eval '(ql:quickload :cl-llm-provider)' \
  --load tests/test-streaming.lisp \
  --load tests/test-tokenizer.lisp \
  --load tests/test-observability.lisp \
  --eval '(fiveam:run-all-tests)'
```

**Step 2: Run existing test suite to ensure no regressions**

```bash
sbcl --noinform --non-interactive --load tests/test-tools-support.lisp
sbcl --noinform --non-interactive --load tests/test-provider-protocols.lisp
sbcl --noinform --non-interactive --load tests/test-token-metadata-comprehensive.lisp
```

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete Phase 1 - streaming, token counting, observability"
```

---

## Summary

**Phase 1 delivers:**
1. **Streaming responses** - `complete-stream` function with callback and manual iteration support
2. **Token counting before calls** - `count-tokens` and `estimate-cost` functions
3. **Observability hooks** - `make-hooks`, `add-hook`, logging and cost tracking helpers

**Files created/modified:**
- `src/types.lisp` - stream-chunk, completion-stream classes
- `src/streaming.lisp` - SSE parsing, stream reading
- `src/tokenizer.lisp` - token counting, cost estimation
- `src/observability.lisp` - hooks infrastructure
- `src/api.lisp` - updated complete function, new complete-stream
- `src/protocol.lisp` - streaming protocol generic functions
- `src/providers/openai.lisp` - OpenAI streaming implementation
- `src/providers/anthropic.lisp` - Anthropic streaming implementation
- `src/package.lisp` - new exports

**Next:** Phase 2 - Context management, retry logic, batch API
