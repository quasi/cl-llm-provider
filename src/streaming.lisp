;; ABOUTME: SSE (Server-Sent Events) parsing for streaming LLM responses
;; Handles parsing of streaming responses from OpenAI-compatible and Anthropic APIs
(in-package :cl-llm-provider)

;;;; SSE (Server-Sent Events) Parsing
;;;;
;;;; Handles parsing of streaming responses from LLM providers.
;;;; OpenAI and compatible APIs use SSE format.
;;;; Anthropic uses a different event format.

(defun/i parse-sse-line (line)
  "Parse a single SSE line into (type . data) cons or nil.
LINE - A string from the SSE stream

Returns:
  (:data . \"content\") for data lines
  (:event . \"event-name\") for event type lines
  NIL for empty lines or comments"
  (:feature streaming-api)
  (:purpose "Parse Server-Sent Events wire format into typed cons pairs")
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

(defun/i parse-openai-stream-data (data index)
  "Parse OpenAI streaming data payload.
DATA - The data portion after 'data: ' prefix
INDEX - Current chunk index

Returns:
  :done if data is \"[DONE]\"
  stream-chunk object otherwise
  nil for empty data"
  (:feature streaming-api)
  (:purpose "Parse OpenAI-format SSE data into stream-chunk or done signal")
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

(defun/i parse-anthropic-stream-event (event-type data index)
  "Parse Anthropic streaming event.
EVENT-TYPE - The SSE event type (string)
DATA - JSON data payload (string)
INDEX - Current chunk index

Returns:
  :done for message_stop
  stream-chunk for content
  nil for metadata events"
  (:feature streaming-api)
  (:purpose "Parse Anthropic-format typed SSE events into stream-chunks")
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

;;;; Buffer Accumulation

(defun/i buffer-append (buffer string)
  "Append STRING to adjustable string BUFFER. Amortized O(1) per character."
  (:feature streaming-api)
  (:purpose "Efficient string accumulation for streaming content")
  (loop for ch across string do (vector-push-extend ch buffer))
  buffer)

;;;; Stream Reading

(defmethod read-stream-chunk :around ((stream completion-stream) &key timeout)
  "Dispatch to provider-specific stream reader."
  (declare (ignore timeout))
  (let ((provider (stream-provider stream)))
    (if (typep provider 'anthropic-provider)
        (read-anthropic-stream-chunk stream)
        (call-next-method))))

(defmethod read-stream-chunk ((stream completion-stream) &key timeout)
  "Read next chunk from completion-stream (OpenAI-compatible format)."
  (declare (ignore timeout))  ; TODO: implement timeout
  (when (stream-closed-p stream)
    (return-from read-stream-chunk nil))

  (let ((http-stream (stream-http-stream stream))
        (provider (stream-provider stream))
        (index (length (stream-chunks stream))))
    (declare (ignore provider))
    (unwind-protect
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
                          (return nil))
                         (chunk
                          ;; Accumulate content into buffer (amortized O(1))
                          (let ((delta (chunk-delta chunk)))
                            (when (and delta (stringp delta))
                              (buffer-append (stream-accumulated-buffer stream) delta)))
                          (push chunk (stream-chunks stream))
                          (return chunk))))))))
           (error (e)
             (setf (stream-state stream) :error)
             (setf (stream-error-condition stream) e)
             (restart-case
                 (error 'stream-interrupted-error
                        :stream-object stream
                        :phase :reading
                        :chunks-received (length (stream-chunks stream))
                        :accumulated-content (stream-accumulated-content stream)
                        :provider (stream-provider stream)
                        :message (format nil "Stream interrupted: ~A" e))
               (return-partial-content ()
                 :report "Return content accumulated so far"
                 nil)
               (abort-stream ()
                 :report "Abort and close stream"
                 (setf (stream-state stream) :closed)
                 nil))))
      ;; Cleanup: always close HTTP stream when done or on error
      (when (stream-closed-p stream)
        (handler-case (close http-stream)
          (error (e)
            (warn "Failed to close HTTP stream: ~A" e)))))))

(defun read-anthropic-stream-chunk (stream)
  "Read next chunk from Anthropic streaming response."
  (when (stream-closed-p stream)
    (return-from read-anthropic-stream-chunk nil))

  (let ((http-stream (stream-http-stream stream))
        (index (length (stream-chunks stream)))
        (current-event nil))
    (unwind-protect
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
                           (return nil))
                          (chunk
                           ;; Accumulate content into buffer (amortized O(1))
                           (let ((delta (chunk-delta chunk)))
                             (when (and delta (stringp delta))
                               (buffer-append (stream-accumulated-buffer stream) delta)))
                           (push chunk (stream-chunks stream))
                           (return chunk)))))))))
           (error (e)
             (setf (stream-state stream) :error)
             (setf (stream-error-condition stream) e)
             (restart-case
                 (error 'stream-interrupted-error
                        :stream-object stream
                        :phase :reading
                        :chunks-received (length (stream-chunks stream))
                        :accumulated-content (stream-accumulated-content stream)
                        :provider (stream-provider stream)
                        :message (format nil "Stream interrupted: ~A" e))
               (return-partial-content ()
                 :report "Return content accumulated so far"
                 nil)
               (abort-stream ()
                 :report "Abort and close stream"
                 (setf (stream-state stream) :closed)
                 nil))))
      ;; Cleanup: always close HTTP stream when done or on error
      (when (stream-closed-p stream)
        (handler-case (close http-stream)
          (error (e)
            (warn "Failed to close HTTP stream: ~A" e)))))))
