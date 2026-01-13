# How-To: Streaming Responses

Stream LLM responses in real-time for better user experience and incremental processing.

## When to Use Streaming

**Use streaming when**:
- Building interactive chat interfaces (users see responses as they're generated)
- Processing long responses incrementally (start work before completion)
- Providing progress feedback for long-running requests
- Building typewriter-style UI effects

**Don't use streaming when**:
- You need the complete response before processing
- You're doing batch/background processing
- Simple request/response is sufficient

---

## Basic Streaming

### Simple Stream with Manual Reading

```lisp
(use-package :cl-llm-provider)

;; Create a stream
(let ((stream (complete-stream
               '((:role "user" :content "Count from 1 to 10"))
               :provider (make-provider :openai :model "gpt-4o-mini"))))

  ;; Read chunks one at a time
  (loop for chunk = (read-stream-chunk stream)
        while chunk
        do (format t "~A" (chunk-delta chunk)))

  ;; Access complete response after streaming
  (format t "~%Complete: ~A~%" (stream-accumulated-content stream)))
```

**What happens**:
1. `complete-stream` starts the request, returns immediately
2. `read-stream-chunk` reads next chunk (blocks until available)
3. `chunk-delta` contains new text in this chunk
4. Loop continues until stream ends (returns `nil`)
5. `stream-accumulated-content` has full response

---

### Stream with Callbacks

More convenient for event-driven code:

```lisp
(complete-stream
 '((:role "user" :content "Tell me a story"))
 :provider (make-provider :openai :model "gpt-4o-mini")
 :on-chunk (lambda (chunk)
             ;; Called for each chunk
             (format t "~A" (chunk-delta chunk))
             (force-output))
 :on-complete (lambda (full-content final-chunk)
                ;; Called once at end
                (format t "~%Done! Total: ~D characters~%"
                        (length full-content)))
 :on-error (lambda (error)
             ;; Called if error occurs
             (format t "~%Error: ~A~%" error)))
```

**Benefits**:
- No manual loop needed
- Clear separation of concerns (chunk/complete/error)
- Automatic stream cleanup

---

## Provider-Specific Streaming

### OpenAI Streaming

OpenAI uses data-only Server-Sent Events (SSE):

```lisp
(let ((stream (complete-stream
               messages
               :provider (make-provider :openai :model "gpt-4o")
               :max-tokens 500)))

  ;; OpenAI streams work the same as any provider
  (loop for chunk = (read-stream-chunk stream)
        while chunk
        do (process-chunk chunk)))
```

**Finish reasons** (when stream ends):
- `:stop` - Natural completion
- `:length` - Hit max-tokens limit
- `:content-filter` - Content policy violation
- `:tool-calls` - Model wants to call tools

### Anthropic Streaming

Anthropic uses event-typed SSE:

```lisp
(let ((stream (complete-stream
               messages
               :provider (make-provider :anthropic
                                       :model "claude-3-5-sonnet-20241022")
               :max-tokens 1000)))

  (loop for chunk = (read-stream-chunk stream)
        while chunk
        do (let ((delta (chunk-delta chunk))
                (finish (chunk-finish-reason chunk)))
             (when delta (format t "~A" delta))
             (when finish (format t "~%Finished: ~A~%" finish)))))
```

**Finish reasons**:
- `:end-turn` - Natural completion
- `:max-tokens` - Hit token limit
- `:stop-sequence` - Hit stop sequence

### Ollama Streaming

Local models through Ollama:

```lisp
(let ((stream (complete-stream
               messages
               :provider (make-provider :ollama
                                       :model "llama2"
                                       :base-url "http://localhost:11434"))))

  ;; Ollama uses OpenAI-compatible format
  (loop for chunk = (read-stream-chunk stream)
        while chunk
        do (format t "~A" (chunk-delta chunk))))
```

---

## Accessing Chunk Information

### Chunk Object Fields

```lisp
(let ((chunk (read-stream-chunk stream)))
  ;; New text in this chunk
  (chunk-delta chunk)           ; => "Hello"

  ;; Accumulated content so far
  (chunk-content chunk)         ; => "Hello world"

  ;; Chunk index (0-based)
  (chunk-index chunk)           ; => 5

  ;; Finish reason (nil until last chunk)
  (chunk-finish-reason chunk)   ; => :STOP

  ;; Tool call delta (if model wants to call tools)
  (chunk-tool-call-delta chunk) ; => (:name "get_weather" ...)

  ;; Usage statistics (only in final chunk)
  (chunk-usage chunk))          ; => (:prompt-tokens 10 :completion-tokens 20)
```

### Stream Object Fields

```lisp
;; After streaming completes
(stream-state stream)              ; => :CLOSED (:OPEN, :ERROR, :CLOSED)
(stream-accumulated-content stream) ; => "Complete response text"
(stream-chunks stream)             ; => List of all chunks
(length (stream-chunks stream))    ; => 15 (total chunks)
(stream-provider stream)           ; => #<OPENAI-PROVIDER>
(stream-model stream)              ; => "gpt-4o-mini"

;; If error occurred
(stream-error-condition stream)    ; => #<HTTP-ERROR 429>
```

---

## Error Handling

### Basic Error Handling

```lisp
(handler-case
    (let ((stream (complete-stream messages :provider provider)))
      (loop for chunk = (read-stream-chunk stream)
            while chunk
            do (process-chunk chunk)))

  ;; Authentication errors
  (http-error (e)
    (when (= (http-error-status-code e) 401)
      (format t "Invalid API key~%")))

  ;; Rate limiting
  (http-error (e)
    (when (= (http-error-status-code e) 429)
      (format t "Rate limited, retry in ~A seconds~%"
              (http-error-retry-after e))))

  ;; Network errors
  (stream-error (e)
    (format t "Stream error: ~A~%" e)))
```

### Error Recovery with Callback

```lisp
(complete-stream
 messages
 :provider provider
 :on-chunk (lambda (chunk)
             (format t "~A" (chunk-delta chunk)))
 :on-error (lambda (error)
             ;; Log error
             (format t "~%Error occurred: ~A~%" error)

             ;; Attempt recovery
             (cond
               ((typep error 'rate-limit-error)
                (sleep 60)
                (complete-stream messages :provider provider))

               ((typep error 'network-error)
                (format t "Network failed, switching to fallback provider~%")
                (complete messages :provider fallback-provider))

               (t
                (format t "Unrecoverable error~%")))))
```

### Checking Stream State

```lisp
(let ((stream (complete-stream messages :provider provider)))
  (loop for chunk = (read-stream-chunk stream)
        while chunk
        do (format t "~A" (chunk-delta chunk))
        finally
           ;; Check why stream ended
           (case (stream-state stream)
             (:closed
              (format t "~%Completed successfully~%"))
             (:error
              (format t "~%Error: ~A~%"
                      (stream-error-condition stream))))))
```

---

## Advanced Patterns

### Progress Tracking

```lisp
(let ((chunk-count 0)
      (char-count 0)
      (start-time (get-internal-real-time)))

  (complete-stream
   messages
   :provider provider
   :on-chunk (lambda (chunk)
               (incf chunk-count)
               (incf char-count (length (chunk-delta chunk)))

               ;; Progress every 10 chunks
               (when (zerop (mod chunk-count 10))
                 (let ((elapsed (/ (- (get-internal-real-time) start-time)
                                  internal-time-units-per-second)))
                   (format t "~%[~D chunks, ~D chars, ~,1Fs]~%"
                           chunk-count char-count elapsed))))
   :on-complete (lambda (full-content final-chunk)
                  (format t "~%Complete: ~D chunks, ~D characters~%"
                          chunk-count (length full-content)))))
```

### Streaming to File

```lisp
(with-open-file (output "/tmp/llm-response.txt"
                        :direction :output
                        :if-exists :supersede)
  (complete-stream
   messages
   :provider provider
   :on-chunk (lambda (chunk)
               (write-string (chunk-delta chunk) output)
               (force-output output))
   :on-complete (lambda (full-content final-chunk)
                  (format t "~%Wrote ~D characters to file~%"
                          (length full-content)))))
```

### Streaming with Timeout

```lisp
(let ((stream (complete-stream messages :provider provider))
      (timeout-seconds 30))

  (loop for chunk = (read-stream-chunk stream :timeout timeout-seconds)
        while chunk
        do (format t "~A" (chunk-delta chunk))
        finally
           (when (eq (stream-state stream) :open)
             (format t "~%Timeout after ~D seconds~%" timeout-seconds))))
```

### Multi-Stream Processing

Process multiple streams concurrently:

```lisp
(let ((streams (list
                (complete-stream messages1 :provider provider1)
                (complete-stream messages2 :provider provider2)
                (complete-stream messages3 :provider provider3))))

  ;; Process all streams until all complete
  (loop while (some (lambda (s) (eq (stream-state s) :open)) streams)
        do (dolist (stream streams)
             (when (eq (stream-state stream) :open)
               (let ((chunk (read-stream-chunk stream :timeout 0.1)))
                 (when chunk
                   (format t "[Stream ~D] ~A"
                           (position stream streams)
                           (chunk-delta chunk))))))))
```

### Streaming with Token Counting

Estimate tokens as you stream:

```lisp
(let ((estimated-tokens 0))
  (complete-stream
   messages
   :provider provider
   :on-chunk (lambda (chunk)
               ;; Estimate tokens: ~4 chars per token
               (let ((delta-tokens (ceiling (length (chunk-delta chunk)) 4)))
                 (incf estimated-tokens delta-tokens)
                 (format t "~A [~D tokens so far]~%"
                         (chunk-delta chunk)
                         estimated-tokens)))
   :on-complete (lambda (full-content final-chunk)
                  ;; Get actual token count from final chunk
                  (let* ((usage (chunk-usage final-chunk))
                         (actual-tokens (getf usage :completion-tokens)))
                    (format t "~%Estimated: ~D, Actual: ~D tokens~%"
                            estimated-tokens actual-tokens)))))
```

---

## Integration with Observability

Combine streaming with hooks for logging:

```lisp
(let ((hooks (make-logging-hooks :level :info)))
  (complete-stream
   messages
   :provider provider
   :hooks hooks  ; Logs request/response
   :on-chunk (lambda (chunk)
               (format t "~A" (chunk-delta chunk)))
   :on-complete (lambda (full-content final-chunk)
                  (format t "~%Streaming complete!~%"))))
```

---

## Performance Considerations

### Buffering for UI

Don't update UI for every chunk (too frequent):

```lisp
(let ((buffer "")
      (last-update (get-internal-real-time)))

  (complete-stream
   messages
   :provider provider
   :on-chunk (lambda (chunk)
               (setf buffer (concatenate 'string buffer (chunk-delta chunk)))

               ;; Update UI every 100ms
               (let ((now (get-internal-real-time)))
                 (when (> (- now last-update)
                         (* 0.1 internal-time-units-per-second))
                   (update-ui buffer)
                   (setf last-update now))))
   :on-complete (lambda (full-content final-chunk)
                  ;; Final UI update
                  (update-ui full-content))))
```

### Memory Efficiency

For very long responses, process and discard chunks:

```lisp
;; Don't keep all chunks in memory
(let ((processed-length 0))
  (complete-stream
   messages
   :provider provider
   :on-chunk (lambda (chunk)
               ;; Process chunk
               (let ((delta (chunk-delta chunk)))
                 (process-text delta)
                 (incf processed-length (length delta)))

               ;; Don't accumulate in stream
               ;; (stream still accumulates internally, but you control usage)
               )
   :on-complete (lambda (full-content final-chunk)
                  (format t "~%Processed ~D characters~%" processed-length))))
```

---

## Common Patterns

### Chat Interface

```lisp
(defun stream-chat-response (user-message conversation-history ui-callback)
  "Stream a chat response, updating UI incrementally."
  (let* ((messages (append conversation-history
                          (list (list :role "user" :content user-message))))
         (response-buffer ""))

    (complete-stream
     messages
     :provider *default-provider*
     :on-chunk (lambda (chunk)
                 (let ((delta (chunk-delta chunk)))
                   (setf response-buffer
                         (concatenate 'string response-buffer delta))
                   (funcall ui-callback response-buffer)))
     :on-complete (lambda (full-content final-chunk)
                    ;; Add to conversation history
                    (push (list :role "assistant" :content full-content)
                          conversation-history)
                    (format t "~%Response added to history~%"))
     :on-error (lambda (error)
                 (funcall ui-callback
                          (format nil "Error: ~A" error))))))
```

### Streaming with Cost Control

Stop streaming if cost exceeds budget:

```lisp
(let ((budget 0.01)  ; $0.01
      (estimated-cost 0)
      (stream nil))

  (setf stream
        (complete-stream
         messages
         :provider provider
         :max-tokens 1000
         :on-chunk (lambda (chunk)
                     ;; Estimate cost: ~$0.01 per 1000 tokens (GPT-4o-mini)
                     (let* ((chars (length (chunk-delta chunk)))
                            (tokens (ceiling chars 4))
                            (cost-delta (* tokens 0.00001)))
                       (incf estimated-cost cost-delta)

                       ;; Stop if over budget
                       (when (> estimated-cost budget)
                         (format t "~%Budget exceeded, stopping stream~%")
                         (close-stream stream))))))
```

---

## Troubleshooting

### Stream Hangs

**Symptom**: `read-stream-chunk` never returns

**Causes**:
- Network timeout
- Server not sending data
- Invalid stream format

**Solution**:
```lisp
;; Always use timeout
(read-stream-chunk stream :timeout 30)  ; 30 second timeout
```

### Missing Chunks

**Symptom**: Some text not appearing

**Cause**: Not calling `force-output` after writing

**Solution**:
```lisp
(on-chunk (lambda (chunk)
            (format t "~A" (chunk-delta chunk))
            (force-output)))  ; Flush output buffer
```

### Memory Usage

**Symptom**: High memory usage with long streams

**Cause**: All chunks kept in memory

**Solution**: Process and discard chunks, don't accumulate:
```lisp
;; Instead of: (stream-accumulated-content stream)
;; Keep your own buffer and clear it:
(let ((buffer ""))
  (on-chunk (lambda (chunk)
              (setf buffer (concatenate 'string buffer (chunk-delta chunk)))
              (when (> (length buffer) 1000)
                (process-buffer buffer)
                (setf buffer "")))))
```

---

## See Also

- [Tutorial: Advanced Features](../tutorials/03-advanced.md) - Using streaming with other features
- [How-To: Observability](observability.md) - Logging streaming requests
- [How-To: Error Handling](error-handling.md) - Handling stream errors
- [Reference: API](../reference/api.md) - Complete streaming API reference
