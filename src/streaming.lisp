;; ABOUTME: SSE (Server-Sent Events) parsing for streaming LLM responses
;; Handles parsing of streaming responses from OpenAI-compatible and Anthropic APIs
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
  stream-chunk object otherwise
  nil for empty data"
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
