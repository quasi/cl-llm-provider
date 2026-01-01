# Tutorial: Advanced Features

Learn token counting, performance profiling, and advanced error handling.

**What you'll learn**:
- Count tokens to estimate costs
- Profile request performance
- Handle errors with restarts
- Use embeddings
- Switch providers dynamically

**Prerequisites**: [Tutorial: Tool Calling](02-tool-calling.md) complete.

---

## Token Counting: Estimating Costs

Know how much your API calls will cost by counting tokens:

```lisp
(use-package :cl-llm-provider)

;; Count tokens in a message
(let ((tokens (token-count "This is a test message")))
  (format t "Tokens: ~A~%" tokens))

;; Count tokens in a conversation
(let ((messages '((:role "user" :content "What is Lisp?")
                  (:role "assistant" :content "Lisp is a programming language..."))))
  (let ((tokens (token-count messages)))
    (format t "Tokens in conversation: ~A~%" tokens)))

;; Estimate cost (rough: $0.01 per 1K tokens)
(let* ((messages '(...))
       (tokens (token-count messages))
       (cost (/ tokens 100000.0)))  ; Rough estimate for Claude
  (format t "Estimated cost: $~2,2F~%" cost))
```

Tokens are used by LLM APIs for billing. Counting tokens before sending helps:
- Estimate costs
- Avoid hitting rate limits
- Optimize long conversations

## Performance Profiling

See where time is spent in your requests:

```lisp
(use-package :cl-llm-provider)

;; Enable profiling for this request
(let ((response (complete messages
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

## Error Handling with Restarts

Handle API errors gracefully with Common Lisp restarts:

```lisp
(use-package :cl-llm-provider)

;; Basic error handling
(handler-case
  (let ((response (complete messages)))
    (format t "~A~%" (response-content response)))

  ;; Handle rate limiting
  (rate-limit-error (e)
    (format t "Rate limited. Wait and retry...~%")
    (sleep 5)
    (complete messages))

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
(defun complete-with-retry (messages &key (max-retries 3))
  "Complete a request, retrying on transient errors."
  (loop
    (handler-case
      (return (complete messages))

      ;; Retry on transient errors
      ((or rate-limit-error timeout-error) (e)
        (if (< retry-count max-retries)
          (progn
            (format t "Retrying... (~A/~A)~%" retry-count max-retries)
            (sleep (expt 2 retry-count)))  ; Exponential backoff
          (error e)))

      ;; Don't retry on permanent errors
      ((or authentication-error provider-error) (e)
        (error e)))))
```

## Embeddings: Vector Representations

Convert text to embeddings (vector representations) for similarity search:

```lisp
(use-package :cl-llm-provider)

;; Get embedding for a single text
(let ((embedding (embedding "The quick brown fox")))
  (format t "Embedding: ~A~%" embedding))

;; Get embeddings for multiple texts
(let ((texts '("The quick brown fox"
               "A fast, brown fox"
               "The slow turtle")))
  (let ((embeddings (embedding texts)))
    (dolist (e embeddings)
      (format t "Embedding length: ~A~%" (length e)))))

;; Use embeddings for similarity search
(let* ((text1 "The quick brown fox")
       (text2 "A fast brown fox")
       (text3 "The slow turtle")
       (embed1 (embedding text1))
       (embed2 (embedding text2))
       (embed3 (embedding text3)))

  ;; Similarity = dot product of normalized vectors
  (format t "Similarity (fox/fox): ~A~%" (similarity embed1 embed2))
  (format t "Similarity (fox/turtle): ~A~%" (similarity embed1 embed3)))
```

**Use embeddings for**:
- Semantic search
- Document clustering
- Similarity matching
- Recommendation systems

## Provider Metadata

Get provider-specific information from responses:

```lisp
(let ((response (complete messages)))
  ;; Standard fields
  (format t "Model: ~A~%" (response-model response))
  (format t "Tokens: ~A~%" (response-token-count response))

  ;; Provider metadata (varies by provider)
  (when (response-metadata response)
    (let ((meta (response-metadata response)))
      ;; Anthropic-specific
      (format t "Usage: ~A~%" (getf meta :usage))

      ;; OpenAI-specific
      (format t "Finish reason: ~A~%" (getf meta :finish-reason)))))
```

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
                                       :model "claude-3-sonnet-20240229"))))
  ...)

;; Use GPT-4
(let ((response (complete messages
                :provider (make-provider :openai
                                       :model "gpt-4"))))
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

## Batch Processing with Tokens and Cost

Process multiple requests efficiently:

```lisp
(use-package :cl-llm-provider)

(defun batch-process (requests &key (max-tokens-per-batch 100000))
  "Process requests, batching within token limit."
  (let ((batch '())
        (batch-tokens 0)
        (results '()))

    (dolist (request requests)
      (let ((tokens (token-count (getf request :messages))))
        (if (> (+ batch-tokens tokens) max-tokens-per-batch)
          ;; Start new batch
          (progn
            (setf results (append results (process-batch batch)))
            (setf batch (list request))
            (setf batch-tokens tokens))
          ;; Add to current batch
          (progn
            (push request batch)
            (incf batch-tokens tokens)))))

    ;; Process final batch
    (append results (process-batch batch))))

(defun process-batch (requests)
  "Process a batch of requests."
  (mapcar (lambda (req)
            (complete (getf req :messages)))
          requests))
```

## Profiling with Token Counting

Combine profiling and token counting for detailed analysis:

```lisp
(let ((response (complete messages
                :enable-profiling t)))

  ;; Tokens
  (let ((tokens (response-token-count response)))
    (format t "Tokens: ~A~%" tokens))

  ;; Performance
  (when (response-profiling response)
    (let ((prof (response-profiling response)))
      (format t "API time: ~Ams~%" (getf prof :api-time))))

  ;; Cost estimate
  (let* ((tokens (response-token-count response))
         (cost (/ tokens 1000000.0 0.003)))  ; $0.003 per 1M tokens (example)
    (format t "Cost: $~6,6F~%" cost)))
```

## Checkpoint: What You Can Now Do

- ✅ Count tokens and estimate costs
- ✅ Profile request performance
- ✅ Handle errors with retries
- ✅ Generate embeddings for similarity search
- ✅ Access provider-specific metadata
- ✅ Switch providers without rewriting code
- ✅ Batch requests efficiently

## Next Steps

- **Tool safety and validation**: [How-To: Advanced Tools](../how-to/tools.md)
- **Complete example with all features**: [Example: Chat with Tools](../examples/CHAT_WITH_TOOLS.md)
- **Reference documentation**: [Reference: Complete API](../reference/api.md)

---

**Prev**: [Tool Calling](02-tool-calling.md) | **Home**: [Documentation](../quickstart.md)
