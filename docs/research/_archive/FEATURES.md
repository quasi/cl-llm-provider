# Features Documentation

Comprehensive documentation of cl-llm-provider's features and capabilities.

## Table of Contents

1. [Text Completion](#text-completion)
2. [Tool/Function Calling](#toolfunction-calling)
3. [Embeddings](#embeddings)
4. [Token Counting](#token-counting)
5. [Provider Metadata](#provider-metadata)
6. [Performance Profiling](#performance-profiling)
7. [Error Handling](#error-handling)
8. [Configuration](#configuration)
9. [Multi-Provider Support](#multi-provider-support)

## Text Completion

### Basic Completion

Send a simple message to get a response:

```lisp
(let ((response (complete '((:role "user" :content "What is Lisp?")))))
  (format t "~A~%" (response-content response)))
```

### Multi-Turn Conversations

Build conversational context by passing message history:

```lisp
(let* ((turn1 (complete '((:role "user" :content "What is 2+2?"))))
       (turn2 (complete (list '(:role "user" :content "What is 2+2?")
                             (response-message turn1)
                             '(:role "user" :content "And if you multiply by 3?")))))
  (format t "~A~%" (response-content turn2)))
```

### System Messages

Provide context and behavior instructions to the model:

```lisp
(complete '((:role "user" :content "Translate to French: Hello"))
         :system "You are a professional translator. Provide only the translation.")
```

### Request Parameters

Control model behavior with various parameters:

```lisp
(complete messages
         :model "gpt-4-turbo"        ; Model to use
         :max-tokens 200             ; Maximum response length
         :temperature 0.7            ; Creativity (0=precise, 2=creative)
         :stop '("\n\n" "---")      ; Stop at these sequences
         :provider provider)         ; Specific provider
```

**Parameter Details**:

- **model**: Model identifier (provider-specific)
  - OpenAI: `gpt-4-turbo`, `gpt-4`, `gpt-3.5-turbo`
  - Anthropic: `claude-3-opus-20240229`, `claude-3-sonnet-20240229`
  - Ollama: `llama2`, `mistral`, `neural-chat`

- **max-tokens**: Maximum tokens in response
  - Prevents runaway responses
  - Affects cost on API-based providers
  - Default: None (use provider default)
  - Anthropic: Required (default 4096)

- **temperature**: Controls randomness in generation
  - Range: 0.0 to 2.0
  - 0.0: Deterministic, always same response
  - 1.0: Default, balanced
  - 2.0: Maximum creativity
  - Use 0.0 for factual tasks, 1.5+ for creative writing

- **stop**: List of strings to stop generation at
  - Useful for structured outputs
  - Example: `'("\n---" "END")`

## Tool/Function Calling

### Defining Tools

Create reusable tool definitions:

```lisp
(defparameter *weather-tool*
  (make-instance 'tool-definition
    :name "get_weather"
    :description "Get current weather in a location"
    :parameters '((:name "location"
                   :type :string
                   :description "City and state, e.g. San Francisco, CA")
                  (:name "unit"
                   :type :string
                   :enum ("celsius" "fahrenheit")
                   :description "Temperature unit"))
    :required '("location")))
```

**Parameter Types**:
- `:string` - Text values
- `:integer` - Whole numbers
- `:number` - Decimal numbers
- `:boolean` - True/false
- `:array` - Lists
- `:object` - Nested structures

### Using Tools

Request the model to use available tools:

```lisp
(let ((response (complete
                 '((:role "user" :content "What's the weather in London?"))
                 :tools (list *weather-tool*))))

  ;; Check if model wants to use a tool
  (dolist (call (response-tool-calls response))
    (format t "Tool: ~A~%" (tool-call-name call))
    (format t "Args: ~A~%" (tool-call-arguments call))

    ;; Execute tool (your implementation)
    (let ((result (execute-weather-tool (tool-call-arguments call))))
      ;; Send result back to model
      (let ((final (complete
                   (append (list (response-message response))
                          (list (make-tool-result (tool-call-id call) result)))))))
        (format t "Answer: ~A~%" (response-content final))))))
```

### Tool Choice

Control whether and how tools are used:

```lisp
;; Model decides when to use tools (default)
(complete messages :tools tools :tool-choice :auto)

;; Force model to use a tool
(complete messages :tools tools :tool-choice :required)

;; Disable tool use
(complete messages :tools tools :tool-choice :none)

;; Force specific tool
(complete messages :tools tools :tool-choice "calculator")
```

### Handling Tool Calls

Extract and process tool calls from responses:

```lisp
(let ((response (complete messages :tools tools)))
  (when (eq (response-finish-reason response) :tool-calls)
    ;; Response contains tool calls instead of text
    (let ((calls (response-tool-calls response)))
      (dolist (call calls)
        ;; Each call has id, name, and arguments
        (let* ((call-id (tool-call-id call))
               (tool-name (tool-call-name call))
               (args (tool-call-arguments call))
               ;; Execute tool - your implementation
               (result (execute-tool tool-name args))
               ;; Create result message
               (result-msg (make-tool-result call-id result)))

          ;; Continue conversation with result
          )))))
```

### Multiple Tool Calls

A single response can request multiple tool executions:

```lisp
(let ((response (complete messages :tools tools)))
  (dolist (call (response-tool-calls response))
    ;; Process each tool call
    (let ((result (execute-tool (tool-call-name call)
                               (tool-call-arguments call))))
      ;; Gather all results
      )))
```

### Multi-Turn Tool Conversations

Implement agentic loops with tools:

```lisp
(defun tool-agent (initial-message tools)
  (loop with messages = (list `(:role "user" :content ,initial-message))
        for response = (complete messages :tools tools)
        do (cond
             ;; Model provided text answer
             ((and (response-content response)
                   (not (response-tool-calls response)))
              (format t "Final answer: ~A~%" (response-content response))
              (return (response-content response)))

             ;; Model wants to use tools
             ((response-tool-calls response)
              ;; Execute all tool calls
              (let ((tool-results
                     (mapcar (lambda (call)
                              (let ((result (execute-tool (tool-call-name call)
                                                         (tool-call-arguments call))))
                                (make-tool-result (tool-call-id call) result)))
                            (response-tool-calls response))))

                ;; Add to conversation history
                (setf messages (append messages
                                      (list (response-message response))
                                      tool-results))))

             ;; Model gave up or hit length limit
             (t
              (format t "Conversation ended with: ~A~%"
                      (response-finish-reason response))
              (return nil)))))
```

## Embeddings

### Single Embedding

Get embedding vector for a single text:

```lisp
(let ((response (embedding "Common Lisp is powerful"
                          :model "text-embedding-3-small")))
  (let ((vector (first (response-embeddings response))))
    (format t "Embedding dimension: ~A~%" (length vector))))
```

### Batch Embeddings

Embed multiple texts efficiently:

```lisp
(let ((texts '("First document"
               "Second document"
               "Third document")))
  (let ((response (embedding texts :model "text-embedding-3-small")))
    (let ((vectors (response-embeddings response)))
      (format t "Got ~A embeddings~%" (length vectors)))))
```

### Embedding Models

Different providers offer different embedding models:

- **OpenAI**:
  - `text-embedding-3-small` - 1536 dimensions
  - `text-embedding-3-large` - 3072 dimensions

- **Anthropic**: No embeddings API (use OpenAI or other)

- **Ollama**:
  - `nomic-embed-text` - 768 dimensions
  - `mxbai-embed-large` - 1024 dimensions

### Vector Similarity

Use embeddings for semantic search:

```lisp
(defun cosine-similarity (vec1 vec2)
  "Calculate cosine similarity between two vectors"
  (let ((dot-product (loop for a in vec1
                          for b in vec2
                          sum (* a b)))
        (mag1 (sqrt (loop for a in vec1 sum (* a a))))
        (mag2 (sqrt (loop for b in vec2 sum (* b b)))))
    (/ dot-product (* mag1 mag2))))

(let* ((query-text "Common Lisp programming")
       (docs '("Lisp tutorial" "Functional programming" "Scheme dialect"))
       (query-resp (embedding query-text :model "text-embedding-3-small"))
       (doc-resps (embedding docs :model "text-embedding-3-small"))
       (query-vec (first (response-embeddings query-resp)))
       (doc-vecs (response-embeddings doc-resps)))

  (loop for doc in docs
        for vec in doc-vecs
        for score = (cosine-similarity query-vec vec)
        collect (cons score doc)
        into results
        finally (return (sort results #'> :key #'car))))
```

## Token Counting

### Access Token Usage

Get token counts from any completion:

```lisp
(let ((response (complete messages)))
  (let ((usage (response-usage response)))
    (format t "Prompt tokens: ~A~%" (getf usage :prompt-tokens))
    (format t "Completion tokens: ~A~%" (getf usage :completion-tokens))
    (format t "Total tokens: ~A~%" (getf usage :total-tokens))))
```

### Estimate Costs

Calculate API costs based on token usage:

```lisp
(defun estimate-cost (response pricing-per-1k)
  "Estimate cost given token usage and pricing"
  (let* ((usage (response-usage response))
         (prompt-tokens (getf usage :prompt-tokens))
         (completion-tokens (getf usage :completion-tokens))
         (prompt-price (car pricing-per-1k))
         (completion-price (cdr pricing-per-1k)))
    (+ (* prompt-tokens prompt-price 0.001)
       (* completion-tokens completion-price 0.001))))

;; Example: GPT-4 pricing ($0.03 per 1K prompt, $0.06 per 1K completion)
(let ((response (complete messages)))
  (let ((cost (estimate-cost response '(0.03 . 0.06))))
    (format t "Estimated cost: $~,4F~%" cost)))
```

### Token Limits

Monitor token usage to avoid exceeding context windows:

```lisp
(let ((max-context-tokens 8192)
      (response-tokens-needed 512)
      (current-messages messages))

  ;; Check if we're approaching limit
  (let ((messages-tokens (estimate-messages-tokens current-messages)))
    (when (> (+ messages-tokens response-tokens-needed) max-context-tokens)
      (format t "Warning: Approaching context limit~%")
      ;; Remove oldest messages to make room
      (setf current-messages (drop-oldest-messages current-messages)))))
```

## Provider Metadata

### Access Provider-Specific Data

Get metadata from responses:

```lisp
(let ((response (complete messages)))
  (let ((metadata (response-metadata response)))
    ;; Content varies by provider
    (when metadata
      (dolist (key-value-pair (mapcar #'list
                                     (loop for i from 0 by 2
                                          while (< i (length metadata))
                                          collect (elt metadata i))
                                     (loop for i from 1 by 2
                                          while (< i (length metadata))
                                          collect (elt metadata i))))
        (format t "~A: ~A~%" (car key-value-pair) (cadr key-value-pair))))))
```

### OpenAI Metadata

```lisp
;; Available fields in metadata:
;; :system-fingerprint - Model configuration identifier
;; :created - Unix timestamp
;; :completion-tokens-details - Breakdown for reasoning/cache tokens
;; :prompt-tokens-details - Breakdown for cache/audio tokens
```

### Anthropic Metadata

```lisp
;; Available fields in metadata:
;; :stop-sequence - Which stop sequence was used
```

### Ollama Metadata

```lisp
;; Available fields in metadata:
;; :total-duration-ns - Complete request duration
;; :load-duration-ns - Model load time
;; :prompt-eval-duration-ns - Prompt processing time
;; :eval-duration-ns - Response generation time
;; :created-at - ISO8601 timestamp
```

### Thinking/Reasoning Traces

Access reasoning output from reasoning models:

```lisp
;; For Ollama reasoning models (DeepSeek-R1, Qwen)
(let ((response (complete messages :provider *ollama* :model "deepseek-r1")))
  (let ((content (response-content response)))
    ;; Content includes <thinking>...</thinking> blocks
    (when (search "<thinking>" content)
      (format t "Model showed reasoning traces~%"))))
```

## Performance Profiling

### Enable Timing Data

Measure request performance:

```lisp
(let ((*performance-profiling* t))
  (let ((response (complete messages)))
    (let ((perf (response-performance response)))
      (format t "Encode time: ~,3F seconds~%" (getf perf :encode-time))
      (format t "API time: ~,3F seconds~%" (getf perf :api-time))
      (format t "Decode time: ~,3F seconds~%" (getf perf :decode-time))
      (let ((total (+ (getf perf :encode-time)
                     (getf perf :api-time)
                     (getf perf :decode-time))))
        (format t "Total time: ~,3F seconds~%" total)))))
```

### Performance Metrics

- **encode-time**: JSON encoding of request (usually 1-10ms)
- **api-time**: HTTP request + response (main bottleneck, typically 100-5000ms)
- **decode-time**: JSON parsing of response (usually 1-50ms)

### Identify Bottlenecks

Find performance issues:

```lisp
(defun find-slowest-phase ()
  (let ((*performance-profiling* t)
        (total-encode 0) (total-api 0) (total-decode 0)
        (calls 10))

    ;; Run multiple times
    (loop repeat calls
          do (let ((response (complete messages)))
               (let ((perf (response-performance response)))
                 (incf total-encode (getf perf :encode-time))
                 (incf total-api (getf perf :api-time))
                 (incf total-decode (getf perf :decode-time)))))

    ;; Report averages
    (format t "~&Average encode time: ~,3F ms~%" (* 1000 (/ total-encode calls)))
    (format t "Average API time: ~,3F ms~%" (* 1000 (/ total-api calls)))
    (format t "Average decode time: ~,3F ms~%" (* 1000 (/ total-decode calls)))))
```

## Error Handling

### Catching Specific Errors

Handle different error types:

```lisp
(handler-case
    (complete messages)

  ;; Authentication failed
  (provider-authentication-error (e)
    (format t "Auth failed: ~A~%" (error-message e))
    ;; Restart with new key
    (invoke-restart 'use-value "new-api-key"))

  ;; Rate limited
  (provider-rate-limit-error (e)
    (format t "Rate limited, waiting ~A seconds~%"
            (error-retry-after e))
    ;; Automatic retry after delay
    (invoke-restart 'wait-and-retry))

  ;; Other API error
  (provider-api-error (e)
    (format t "API error ~A: ~A~%"
            (error-status-code e)
            (error-message e)))

  ;; Configuration issue
  (provider-configuration-error (e)
    (format t "Config error: ~A~%"
            (error-message e))))
```

### Retry Strategies

Implement exponential backoff:

```lisp
(defun call-with-retry (fn &key max-retries initial-delay)
  (loop for attempt from 1 to (or max-retries 3)
        do (handler-case
               (return (funcall fn))

             ;; Transient errors - retry
             (provider-rate-limit-error (e)
               (if (< attempt max-retries)
                   (let ((delay (* (or initial-delay 1) (expt 2 (- attempt 1)))))
                     (format t "Retry in ~A seconds~%" delay)
                     (sleep delay))
                   (error e)))

             ;; Permanent errors - don't retry
             (provider-authentication-error (e)
               (error e)))))

(call-with-retry (lambda () (complete messages))
                 :max-retries 3
                 :initial-delay 1)
```

## Configuration

### Global Configuration

Set defaults for all requests:

```lisp
(configure-defaults :provider (make-provider :openai :model "gpt-4")
                   :temperature 0.7
                   :max-tokens 1000)
```

### Per-Request Override

Override defaults for specific requests:

```lisp
(complete messages :temperature 0.2)  ; Override global default
(complete messages :provider *ollama*) ; Use different provider
```

### Configuration File

Store configuration in `~/.config/cl-llm-provider/config.lisp`:

```lisp
;;; Set API keys
(setf (uiop:getenv "OPENAI_API_KEY") "sk-...")
(setf (uiop:getenv "ANTHROPIC_API_KEY") "sk-ant-...")

;;; Configure defaults
(configure-defaults :provider (make-provider :anthropic)
                   :model "claude-3-sonnet-20240229"
                   :temperature 1.0)
```

Then load it manually in your application (opt-in only):

```lisp
;; Load from default location
(load-configuration-from-file)

;; Or specify custom path
(load-configuration-from-file :path "~/my-config.lisp")
```

## Multi-Provider Support

### Same Code, Different Providers

Write provider-agnostic code:

```lisp
(defun ask-all-providers (question)
  "Get responses from multiple providers"
  (let ((providers (list *openai* *anthropic* *ollama*)))
    (mapcar (lambda (provider)
              (cons (type-of provider)
                   (response-content (complete `((:role "user" :content ,question))
                                              :provider provider))))
           providers)))
```

### Provider Capabilities Matrix

Check what each provider supports:

```
Feature                 | OpenAI | Anthropic | Ollama
text-completion         | ✓      | ✓         | ✓
tool-calling           | ✓      | ✓         | ✓
embeddings             | ✓      | ✗         | ✓
system-messages        | In messages | Separate param | In messages
max-tokens-required    | No     | Yes       | No
streaming              | No     | No        | No
vision                 | Yes    | Yes       | Limited
token-counting         | ✓      | ✓         | ✓
```

### Local vs. Cloud

Switch between local and cloud providers:

```lisp
(let ((use-local-p (> (current-hour) 18)))  ; Use local after 6 PM
  (let ((provider (if use-local-p
                     (make-provider :ollama :model "llama2")
                     (make-provider :anthropic :model "claude-3-sonnet"))))
    (complete messages :provider provider)))
```

## See Also

- `docs/PROTOCOL.md` - How the protocol works
- `docs/PROVIDERS.md` - Adding new providers
- `docs/examples/CHAT_WITH_TOOLS.md` - Complete example
- README.md - Quick start and API reference
