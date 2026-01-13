# Tutorial: Advanced Features

Learn streaming responses, token counting, cost estimation, observability, and performance profiling.

**What you'll learn**:
- Stream responses in real-time
- Count tokens and estimate costs
- Add logging and monitoring with hooks
- Profile request performance
- Handle errors with restarts
- Use embeddings
- Switch providers dynamically

**Prerequisites**: [Tutorial: Tool Calling](02-tool-calling.md) complete.

---

## Streaming: Real-Time Responses

Stream LLM responses as they're generated instead of waiting for completion:

```lisp
(use-package :cl-llm-provider)

;; Basic streaming with manual chunk reading
(let ((stream (complete-stream
               '((:role "user" :content "Count from 1 to 5"))
               :provider (make-provider :openai :model "gpt-4o-mini"))))

  ;; Read and display chunks
  (loop for chunk = (read-stream-chunk stream)
        while chunk
        do (format t "~A" (chunk-delta chunk)))

  ;; Final content
  (format t "~%Done: ~A~%" (stream-accumulated-content stream)))
```

**What happens**:
1. `complete-stream` starts the request, returns immediately
2. `read-stream-chunk` reads next chunk (text appears incrementally)
3. `chunk-delta` contains new text in this chunk
4. Loop continues until stream ends

### Streaming with Callbacks

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
                (format t "~%Complete!~%"))
 :on-error (lambda (error)
             ;; Called on error
             (format t "Error: ~A~%" error)))
```

**Why stream?**
- Better user experience (see responses immediately)
- Start processing before completion
- Build chat interfaces with typewriter effects
- Handle long responses incrementally

**Learn more**: [How-To: Streaming](../how-to/streaming.md)

---

## Token Counting: Estimating Costs

Count tokens before making requests to estimate costs:

```lisp
(use-package :cl-llm-provider)

;; Count tokens in messages
(let* ((messages '((:role "user" :content "What is Lisp?")
                   (:role "assistant" :content "Lisp is a programming language...")
                   (:role "user" :content "Tell me more")))
       (token-count (count-tokens messages)))
  (format t "Conversation tokens: ~D~%" token-count))
;; => Conversation tokens: 28
```

### Count with System Message

```lisp
;; Include system message in count
(let* ((messages '((:role "user" :content "Hello!")))
       (system "You are a helpful assistant.")
       (total-tokens (count-tokens-with-system messages system)))
  (format t "Total tokens (with system): ~D~%" total-tokens))
;; => Total tokens (with system): 12
```

### Estimate Request Cost

```lisp
;; Estimate cost before making request
(let* ((messages '((:role "user" :content "Write a 100 word essay on AI.")))
       (provider (make-provider :openai :model "gpt-4o")))

  (multiple-value-bind (input-cost output-cost total-cost)
      (estimate-cost messages
                    :provider provider
                    :model "gpt-4o"
                    :max-tokens 500)

    (format t "Estimated cost: ~A~%" (format-cost total-cost))
    (format t "  Input:  ~A~%" (format-cost input-cost))
    (format t "  Output: ~A (for ~D tokens)~%" (format-cost output-cost) 500)))

;; Output:
;; Estimated cost: $0.0016
;;   Input:  $0.0001
;;   Output: $0.0015 (for 500 tokens)
```

### Compare Provider Costs

```lisp
;; Compare costs across providers
(defun compare-costs (messages max-tokens)
  "Compare estimated costs for different providers/models."
  (let ((providers '((:openai "gpt-4o")
                     (:openai "gpt-4o-mini")
                     (:anthropic "claude-3-5-sonnet-20241022")
                     (:anthropic "claude-3-5-haiku-20241022"))))

    (dolist (provider-spec providers)
      (let ((provider (make-provider (first provider-spec)
                                    :model (second provider-spec))))
        (multiple-value-bind (input-cost output-cost total)
            (estimate-cost messages
                          :provider provider
                          :model (second provider-spec)
                          :max-tokens max-tokens)
          (format t "~A ~A: ~A~%"
                  (first provider-spec)
                  (second provider-spec)
                  (format-cost total)))))))

(compare-costs '((:role "user" :content "Hello, world!")) 100)
;; Output:
;; OPENAI gpt-4o: $0.0004
;; OPENAI gpt-4o-mini: $0.0001
;; ANTHROPIC claude-3-5-sonnet-20241022: $0.0008
;; ANTHROPIC claude-3-5-haiku-20241022: $0.0001
```

### Budget Validation

```lisp
(defun complete-with-budget (messages budget &rest args)
  "Complete request only if within budget."
  (multiple-value-bind (input-cost output-cost total)
      (apply #'estimate-cost messages args)

    (if (<= total budget)
        (progn
          (format t "Within budget (~A <= ~A)~%"
                  (format-cost total)
                  (format-cost budget))
          (apply #'complete messages args))
        (error "Request exceeds budget: ~A > ~A"
               (format-cost total)
               (format-cost budget)))))
```

**Note**: Token counting uses character-based estimation (~4 chars/token). Typical accuracy: ±10-15%.

---

## Observability: Logging and Monitoring

Add logging, tracing, and monitoring to your LLM applications:

### Simple Request Logging

```lisp
;; Create logging hooks
(let ((hooks (make-logging-hooks :level :info)))
  (complete '((:role "user" :content "Hello!"))
            :provider (make-provider :openai :model "gpt-4o-mini")
            :hooks hooks))

;; Output:
;; [14:23:45] LLM Request: OPENAI gpt-4o-mini (1 messages)
;; [14:23:46] LLM Response: 0.42s, 12 tokens
```

### Debug Level Logging

See full messages and responses:

```lisp
(let ((hooks (make-logging-hooks :level :debug)))
  (complete messages :provider provider :hooks hooks))

;; Output:
;; [14:23:45] LLM Request: OPENAI gpt-4o-mini (1 messages)
;;   Messages: ((:ROLE "user" :CONTENT "Hello!"))
;; [14:23:46] LLM Response: 0.42s, 12 tokens
;;   Content: "Hello! How can I help you today?"
```

### Log to File

```lisp
(with-open-file (log-stream "/var/log/llm-requests.log"
                            :direction :output
                            :if-exists :append
                            :if-does-not-exist :create)
  (let ((hooks (make-logging-hooks :stream log-stream :level :info)))
    (complete messages :provider provider :hooks hooks)))
```

### Custom Hooks

Build your own monitoring:

```lisp
(let ((hooks (make-hooks)))
  ;; Track requests
  (add-hook hooks :before-request
            (lambda (provider model messages)
              (format t "→ Calling ~A ~A (~D messages)~%"
                      (provider-type provider)
                      model
                      (length messages))))

  ;; Track responses
  (add-hook hooks :after-response
            (lambda (provider model response timing)
              (format t "← Got response in ~,2Fs~%" timing)))

  ;; Track errors
  (add-hook hooks :on-error
            (lambda (provider model error)
              (format t "✗ Error: ~A~%" error)))

  (complete messages :provider provider :hooks hooks))
```

### Global Hooks

Apply hooks to all requests automatically:

```lisp
;; Set once at startup
(setf *global-hooks* (make-logging-hooks :level :info))

;; All requests automatically logged
(complete messages1 :provider provider)  ; Logged
(complete messages2 :provider provider)  ; Logged
```

**Learn more**: [How-To: Observability](../how-to/observability.md)

---

## Performance Profiling

See where time is spent in your requests:

```lisp
(use-package :cl-llm-provider)

;; Enable profiling for this request
(let ((response (complete messages
                          :provider provider
                          :enable-profiling t)))

  ;; Get timing breakdown
  (when (response-profiling response)
    (let ((prof (response-profiling response)))
      (format t "Encoding time: ~Ams~%" (getf prof :encode-time))
      (format t "API time: ~Ams~%" (getf prof :api-time))
      (format t "Decoding time: ~Ams~%" (getf prof :decode-time))
      (format t "Total time: ~Ams~%" (getf prof :total-time)))))
```

Use profiling to:
- Identify bottlenecks (network vs. encoding)
- Optimize batch operations
- Monitor production performance

---

## Error Handling with Restarts

Handle API errors gracefully with Common Lisp restarts:

```lisp
(use-package :cl-llm-provider)

;; Basic error handling
(handler-case
    (let ((response (complete messages :provider provider)))
      (format t "~A~%" (response-content response)))

  ;; Handle rate limiting
  (rate-limit-error (e)
    (format t "Rate limited. Waiting...~%")
    (sleep 60)
    (complete messages :provider provider))

  ;; Handle authentication failures
  (authentication-error (e)
    (format t "Auth error. Check API key.~%"))

  ;; Handle all other errors
  (error (e)
    (format t "Error: ~A~%" e)))
```

**Common Error Types**:

| Error | When | What to Do |
|-------|------|-----------|
| `rate-limit-error` | Too many requests | Wait and retry |
| `authentication-error` | Invalid API key | Check credentials |
| `provider-error` | API returned error | Check message format |
| `network-error` | Connection failed | Retry with backoff |
| `timeout-error` | Request took too long | Increase timeout |

### Retry Pattern with Backoff

```lisp
(defun complete-with-retry (messages &key provider (max-retries 3))
  "Complete a request, retrying on transient errors."
  (let ((retry-count 0))
    (loop
      (handler-case
          (return (complete messages :provider provider))

        ;; Retry on transient errors
        ((or rate-limit-error timeout-error) (e)
          (if (< retry-count max-retries)
              (progn
                (incf retry-count)
                (let ((wait-time (expt 2 retry-count)))
                  (format t "Retrying in ~D seconds... (~D/~D)~%"
                          wait-time retry-count max-retries)
                  (sleep wait-time)))
              (error e)))

        ;; Don't retry on permanent errors
        ((or authentication-error provider-error) (e)
          (error e))))))
```

---

## Embeddings: Vector Representations

Convert text to embeddings (vector representations) for similarity search:

```lisp
(use-package :cl-llm-provider)

;; Get embedding for a single text
(let ((embedding (embedding "The quick brown fox"
                           :provider (make-provider :openai))))
  (format t "Embedding dimensions: ~D~%" (length embedding)))
;; => Embedding dimensions: 1536

;; Get embeddings for multiple texts
(let ((texts '("The quick brown fox"
               "A fast, brown fox"
               "The slow turtle")))
  (let ((embeddings (embedding texts :provider (make-provider :openai))))
    (format t "Got ~D embeddings~%" (length embeddings))))
;; => Got 3 embeddings

;; Use embeddings for similarity search
(defun cosine-similarity (v1 v2)
  "Calculate cosine similarity between two vectors."
  (let ((dot-product (reduce #'+ (map 'list #'* v1 v2)))
        (magnitude1 (sqrt (reduce #'+ (map 'list (lambda (x) (* x x)) v1))))
        (magnitude2 (sqrt (reduce #'+ (map 'list (lambda (x) (* x x)) v2)))))
    (/ dot-product (* magnitude1 magnitude2))))

(let* ((text1 "The quick brown fox")
       (text2 "A fast brown fox")
       (text3 "The slow turtle")
       (provider (make-provider :openai))
       (embed1 (embedding text1 :provider provider))
       (embed2 (embedding text2 :provider provider))
       (embed3 (embedding text3 :provider provider)))

  (format t "Similarity (fox/fox):    ~,3F~%"
          (cosine-similarity embed1 embed2))
  (format t "Similarity (fox/turtle): ~,3F~%"
          (cosine-similarity embed1 embed3)))
;; Output:
;; Similarity (fox/fox):    0.932
;; Similarity (fox/turtle): 0.687
```

**Use embeddings for**:
- Semantic search
- Document clustering
- Similarity matching
- Recommendation systems

---

## Provider Metadata

Get provider-specific information from responses:

```lisp
(let ((response (complete messages :provider provider)))
  ;; Standard fields
  (format t "Model: ~A~%" (response-model response))
  (format t "Tokens: ~A~%" (getf (response-usage response) :total-tokens))

  ;; Provider metadata (varies by provider)
  (when (response-metadata response)
    (let ((meta (response-metadata response)))
      ;; Anthropic-specific
      (format t "Usage: ~A~%" (getf meta :usage))

      ;; OpenAI-specific
      (format t "Finish reason: ~A~%" (getf meta :finish-reason)))))
```

---

## Switching Providers Dynamically

Change providers without changing your code:

```lisp
(use-package :cl-llm-provider)

;; Default provider (from API key)
(let ((response (complete messages)))
  ...)

;; Use Claude instead
(let ((response (complete messages
                          :provider (make-provider :anthropic
                                                  :model "claude-3-5-sonnet-20241022"))))
  ...)

;; Use GPT-4
(let ((response (complete messages
                          :provider (make-provider :openai
                                                  :model "gpt-4o"))))
  ...)

;; Use local Ollama
(let ((response (complete messages
                          :provider (make-provider :ollama
                                                  :model "mistral"))))
  ...)

;; Custom OpenAI-compatible API
(let ((response (complete messages
                          :provider (make-provider :openai-compatible
                                                  :base-url "https://api.example.com"
                                                  :model "my-model"))))
  ...)
```

**Common providers**:
- `:anthropic` - Claude
- `:openai` - GPT-4, GPT-3.5
- `:ollama` - Local models
- `:openrouter` - Multi-provider
- `:openai-compatible` - Groq, vLLM, etc.

---

## Combining Features

Use multiple advanced features together:

### Streaming + Hooks + Cost Tracking

```lisp
(let* ((messages '((:role "user" :content "Count from 1 to 10")))
       (provider (make-provider :openai :model "gpt-4o-mini"))
       (hooks (make-logging-hooks :level :info)))

  ;; Estimate cost first
  (multiple-value-bind (input-cost output-cost total)
      (estimate-cost messages :provider provider :max-tokens 50)
    (format t "Estimated cost: ~A~%~%" (format-cost total)))

  ;; Stream with hooks
  (complete-stream messages
                   :provider provider
                   :max-tokens 50
                   :hooks hooks  ; Logs request/response
                   :on-chunk (lambda (chunk)
                               (format t "~A" (chunk-delta chunk)))
                   :on-complete (lambda (content final-chunk)
                                  (format t "~%~%Stream complete!~%"))))

;; Output:
;; Estimated cost: $0.0001
;;
;; [14:30:15] LLM Request: OPENAI gpt-4o-mini (1 messages)
;; 1
;; 2
;; 3
;; ...
;; 10
;; [14:30:16] LLM Response: 0.52s, 15 tokens
;;
;; Stream complete!
```

### Tool Calling + Error Handling + Logging

```lisp
(let ((hooks (make-logging-hooks :level :debug))
      (tools (list (define-tool "get_weather" "Get weather"
                                '((:name "city" :type :string))))))

  (handler-case
      (let ((response (complete messages
                               :provider provider
                               :tools tools
                               :hooks hooks)))  ; Debug logging

        (when (response-tool-calls response)
          (format t "Model wants to call tools!~%")))

    (error (e)
      (format t "Error (logged): ~A~%" e))))
```

---

## Checkpoint: What You Can Now Do

- ✅ Stream responses in real-time for better UX
- ✅ Count tokens and estimate costs before requests
- ✅ Add logging and monitoring with hooks
- ✅ Profile request performance
- ✅ Handle errors with retries and backoff
- ✅ Generate embeddings for similarity search
- ✅ Access provider-specific metadata
- ✅ Switch providers without rewriting code
- ✅ Combine features for production applications

---

## Next Steps

- **Detailed streaming guide**: [How-To: Streaming](../how-to/streaming.md)
- **Observability patterns**: [How-To: Observability](../how-to/observability.md)
- **Tool safety and validation**: [How-To: Advanced Tools](../how-to/tools.md)
- **Complete example**: [Example: Chat with Tools](../examples/CHAT_WITH_TOOLS.md)
- **Reference documentation**: [Reference: Complete API](../reference/api.md)

---

**Prev**: [Tool Calling](02-tool-calling.md) | **Home**: [Documentation](../quickstart.md)
