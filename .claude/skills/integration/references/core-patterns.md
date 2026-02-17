---
type: patterns
version: 1.0.0
applies-to: [cl-llm-provider]
companion-to: SPEC.agent.md
---

# cl-llm-provider Exemplar Patterns

Complete, runnable code patterns demonstrating idiomatic usage. Each pattern satisfies rules from SPEC.agent.md.

## Pattern Index

| Pattern | Category | Complexity |
|---------|----------|------------|
| PATTERN-001 | Basic completion | Simple |
| PATTERN-002 | Multi-turn conversation | Simple |
| PATTERN-003 | Tool calling workflow | Medium |
| PATTERN-004 | Error handling with restarts | Medium |
| PATTERN-005 | Provider switching | Simple |
| PATTERN-006 | Message normalization | Simple |
| PATTERN-007 | Performance profiling | Simple |
| PATTERN-008 | Configuration from environment | Simple |
| PATTERN-009 | Multi-turn tool conversation | Complex |
| PATTERN-010 | Batch processing with error recovery | Complex |
| EDGE-001 | Empty tool calls response | Edge case |
| EDGE-002 | Length-limited completion | Edge case |
| EDGE-003 | Rate limit with exponential backoff | Edge case |
| EDGE-004 | Missing API key recovery | Edge case |

---

## PATTERN-001: Basic Completion

**Scenario**: Simple single-turn question answering

**Complete Example**:
```lisp
(defun basic-question (question)
  "Ask a single question and return the answer.
   Demonstrates minimal viable completion flow."
  ;; Create provider (reads ANTHROPIC_API_KEY from environment)
  (let ((provider (make-provider :anthropic
                                 :model "claude-3-5-sonnet-20241022")))
    ;; Build message - RULE-002: valid role, RULE-013: non-empty content
    (let* ((messages (list (list :role "user" :content question)))
           ;; Call completion - RULE-008: provider configured before use
           (response (complete messages :provider provider)))

      ;; Extract content - response object is immutable (RULE-004)
      (response-content response))))

;; Usage
(basic-question "What is Common Lisp?")
;; => "Common Lisp is a multi-paradigm programming language..."
```

**Rules Satisfied**: R002 (message role), R004 (immutability), R008 (config before use), R013 (non-empty content)

**Why This Shape**:
- Provider creation separate from use enables reuse across calls
- Message list structure (not string concatenation) preserves turn boundaries
- Direct content extraction safe because no tools involved

**Variations**:

| Scenario | Modification |
|----------|--------------|
| Use global default | `(complete messages)` without `:provider` |
| Override model | Add `:model "claude-3-opus-20240229"` |
| Set temperature | Add `:temperature 0.7` |
| Use system prompt | Add `:system "You are a helpful teacher"` |

**Anti-pattern**:
```lisp
;; DON'T manually concatenate
(complete (list (list :role "user"
                      :content (format nil "Q: ~A~%A:" question))))
;; Loses structure, breaks tool calling
```

---

## PATTERN-002: Multi-Turn Conversation

**Scenario**: Maintaining conversation context across multiple exchanges

**Complete Example**:
```lisp
(defun chat-session ()
  "Interactive conversation maintaining message history.
   Demonstrates proper message ordering and accumulation."
  (let ((provider (make-provider :anthropic
                                 :model "claude-3-5-sonnet-20241022"))
        (messages nil))  ; Start with empty history

    (flet ((send-message (user-input)
             ;; Add user message - RULE-006: chronological ordering
             (push (list :role "user" :content user-input) messages)
             (setf messages (nreverse messages))  ; Maintain oldest-first order

             ;; Get response
             (let ((response (complete messages :provider provider)))

               ;; Add assistant response to history using response-message
               ;; This preserves all response metadata for continuation
               (push (response-message response) messages)
               (setf messages (nreverse messages))

               ;; Return text for display
               (response-content response))))

      ;; Conversation flow
      (send-message "What is 2+2?")
      ;; => "2 + 2 equals 4."

      (send-message "What if I add 3 to that?")
      ;; => "If you add 3 to 4, you get 7."
      ;; This response understands "that" refers to 4 from context

      ;; Return final history for inspection
      messages)))
```

**Rules Satisfied**: R006 (message ordering), R013 (non-empty content), ANTI-001 (avoid string concat)

**Why This Shape**:
- `messages` accumulates chronologically (oldest first)
- `response-message` captures complete assistant turn (handles tool calls)
- Push + nreverse maintains order while building incrementally
- Each turn adds exactly 2 messages (user + assistant)

**Variations**:

| Scenario | Modification |
|----------|--------------|
| System prompt | Initialize with `(list (list :role "system" :content "..."))` |
| Token tracking | Accumulate `(response-usage response)` in session state |
| Max history | Truncate `messages` to last N turns before calling |

**Anti-pattern**:
```lisp
;; DON'T ignore response-message structure
(push (list :role "assistant" :content (response-content response)) messages)
;; Loses tool-calls data, breaks tool conversation continuation
```

---

## PATTERN-003: Tool Calling Workflow

**Scenario**: LLM requests tool execution, user executes, sends result back

**Complete Example**:
```lisp
(defun weather-query-with-tool ()
  "Single-turn tool calling: request → execute → final answer.
   Demonstrates complete tool workflow."

  ;; Define tool - RULE-003: valid name pattern, RULE-011: valid types
  (let ((weather-tool
          (define-tool "get_weather"
            "Get current weather for a location"
            '((:name "location"
               :type :string
               :description "City name, e.g. 'Paris'")
              (:name "unit"
               :type :string
               :enum ("celsius" "fahrenheit")
               :description "Temperature unit"))
            :required '("location")))
        (provider (make-provider :anthropic
                                 :model "claude-3-5-sonnet-20241022")))

    ;; Initial request with tool available
    (let* ((messages (list (list :role "user"
                                 :content "What's the weather in Tokyo?")))
           (response (complete messages
                               :provider provider
                               :tools (list weather-tool))))

      ;; Check finish reason - ANTI-002: don't ignore finish-reason
      (case (response-finish-reason response)
        (:tool-calls
         ;; Extract tool calls
         (let ((calls (response-tool-calls response)))
           ;; Process first call (can loop for multiple)
           (let* ((call (first calls))
                  (args (tool-call-arguments call))

                  ;; Execute tool - user implements this
                  (result (format nil "{\"temperature\": 22, \"condition\": \"sunny\", \"unit\": \"~A\"}"
                                  (getf args :|unit|)))

                  ;; Build result message - RULE-007: preserve exact ID
                  (tool-result (make-tool-result (tool-call-id call) result))

                  ;; Continue conversation with result
                  (final-messages (append messages
                                          (list (response-message response))
                                          (list tool-result)))
                  (final-response (complete final-messages
                                            :provider provider
                                            :tools (list weather-tool))))

             ;; Return final answer
             (response-content final-response))))

        (:stop
         ;; Model answered directly without tools
         (response-content response))))))

;; => "The weather in Tokyo is currently sunny with a temperature of 22°C."
```

**Rules Satisfied**: R003 (tool name), R007 (ID correlation), R011 (param types), R015 (finish-reason normalization), ANTI-002 (check finish-reason)

**Why This Shape**:
- `case` on finish-reason handles both tool-calls and direct answer
- `response-message` preserves complete assistant turn including tool-calls
- `tool-call-id` extracted and preserved through result creation
- Message flow: user → assistant-with-tools → tool-result → assistant-final
- Tools list passed to both complete calls (model can re-use if needed)

**Variations**:

| Scenario | Modification |
|----------|--------------|
| Multiple tools | Loop over `(response-tool-calls response)`, create multiple results |
| Parallel execution | Map tool execution in parallel before building results |
| Tool error | Pass `:is-error t` to `make-tool-result` on exception |
| Automatic execution | Use tool `:handler` and execution framework |

**Anti-pattern**:
```lisp
;; DON'T create fake tool call ID
(make-tool-result "tool_123" result)  ; Violates R007 - wrong ID

;; DON'T skip finish-reason check
(dolist (call (response-tool-calls response)) ...)
;; Fails when finish-reason is :stop and tool-calls is nil
```

---

## PATTERN-004: Error Handling with Restarts

**Scenario**: Graceful recovery from rate limits and auth failures

**Complete Example**:
```lisp
(defun resilient-completion (messages &key provider)
  "Completion with automatic retry on rate limit, manual recovery on auth failure.
   Demonstrates condition handling and restart system."

  (handler-bind
      ;; Rate limit: automatic retry with delay - uses restart system
      ((provider-rate-limit-error
        (lambda (condition)
          (format t "~&Rate limited. Waiting ~A seconds...~%"
                  (error-retry-after condition))
          ;; Invoke wait-and-retry restart (defined by library)
          (invoke-restart 'wait-and-retry)))

       ;; Auth error: prompt for new key - uses restart system
       (provider-authentication-error
        (lambda (condition)
          (declare (ignore condition))
          (format t "~&Authentication failed. Enter new API key: ")
          (finish-output)
          (let ((new-key (read-line)))
            ;; Invoke use-value restart with new key
            (invoke-restart 'use-value new-key))))

       ;; Other API errors: log and propagate
       (provider-api-error
        (lambda (condition)
          (format t "~&API error: ~A~%" (error-message condition))
          ;; Don't invoke restart - let it propagate
          )))

    ;; Make the call - errors handled by handlers above
    (complete messages :provider provider)))

;; Usage - handles errors transparently
(resilient-completion '((:role "user" :content "Hello"))
                      :provider my-provider)
```

**Rules Satisfied**: R010 (condition hierarchy - all inherit from llm-provider-error), R012 (protocol methods signal conditions)

**Why This Shape**:
- `handler-bind` installs handlers without unwinding stack
- Restarts (`wait-and-retry`, `use-value`) defined by library at error site
- Rate limit handler automatic (invokes restart without user prompt)
- Auth handler interactive (prompts user, passes value to restart)
- Generic API error handler logs but doesn't recover (lets propagate)
- Handlers ordered specific-to-general (rate-limit before generic api-error)

**Variations**:

| Scenario | Modification |
|----------|--------------|
| Fallback provider | Add `use-fallback-provider` restart handler |
| Exponential backoff | Track retry count, compute delay, invoke `retry` restart |
| Silent retry | Use `ignore-errors` wrapper for fire-and-forget |
| Max retries | Count invocations, propagate after threshold |

**Anti-pattern**:
```lisp
;; DON'T use ignore-errors for everything
(ignore-errors (complete messages :provider provider))
;; Silently swallows all errors including auth failures that need human intervention

;; DON'T tight retry loop without delay - ANTI-005
(loop repeat 10
      for result = (ignore-errors (complete messages :provider provider))
      when result return result)
;; Amplifies rate limiting, no backoff, wastes quota
```

---

## PATTERN-005: Provider Switching

**Scenario**: Compare responses from multiple providers or fallback on failure

**Complete Example**:
```lisp
(defun multi-provider-query (question providers)
  "Query multiple providers, return first successful response.
   Demonstrates provider abstraction and fallback."

  (dolist (provider providers)
    (handler-case
        ;; Try each provider - same message format works across all
        (let* ((messages (list (list :role "user" :content question)))
               (response (complete messages
                                   :provider provider
                                   :max-tokens 100)))

          ;; Success - return result with provider type
          (return-from multi-provider-query
            (list :provider (type-of provider)
                  :model (response-model response)
                  :content (response-content response)
                  :tokens (getf (response-usage response) :total-tokens))))

      ;; Provider failed - try next
      (provider-api-error (condition)
        (format t "~&~A failed: ~A~%"
                (type-of provider)
                (error-message condition))
        ;; Continue to next provider
        )))

  ;; All providers failed
  (error "All providers failed"))

;; Usage - automatic fallback
(multi-provider-query
  "Explain monads briefly"
  (list (make-provider :anthropic :model "claude-3-5-sonnet-20241022")
        (make-provider :openai :model "gpt-4-turbo")
        (make-provider :ollama :model "llama3")))

;; => (:PROVIDER ANTHROPIC-PROVIDER
;;     :MODEL "claude-3-5-sonnet-20241022"
;;     :CONTENT "A monad is a design pattern..."
;;     :TOKENS 87)
```

**Rules Satisfied**: ANTI-003 (no hardcoded provider logic - same code for all), R001 (protocol ensures consistent behavior)

**Why This Shape**:
- Single `complete` call works identically across all provider types
- Protocol abstraction means no provider-specific code paths
- `handler-case` per iteration isolates failures
- `return-from` exits on first success
- Token usage accessible via same `response-usage` accessor
- Provider type available via `type-of` for logging/metrics

**Variations**:

| Scenario | Modification |
|----------|--------------|
| Parallel queries | Use threads/futures to query all simultaneously |
| Cost optimization | Sort providers by cost, try cheapest first |
| Quality comparison | Collect all responses, score quality |
| Load balancing | Round-robin or random selection |

**Anti-pattern**:
```lisp
;; DON'T hardcode provider-specific logic - ANTI-003
(if (typep provider 'anthropic-provider)
    (parse-anthropic-response ...)
    (parse-openai-response ...))
;; Defeats abstraction, breaks when adding providers
```

---

## PATTERN-006: Message Normalization

**Scenario**: Convert user input formats to canonical message structure

**Complete Example**:
```lisp
(defun normalize-message (input)
  "Convert various input formats to canonical message plist.
   Handles string, keyword roles, message reconstruction."

  (etypecase input
    ;; String → user message (common shorthand)
    (string
     (list :role "user" :content input))

    ;; Plist already → normalize role keyword to string
    (list
     (let ((role (getf input :role))
           (content (getf input :content)))

       ;; RULE-002: roles must be valid strings
       (unless (member role '("user" "assistant" "system" "tool" :user :assistant :system :tool))
         (error "Invalid message role: ~A" role))

       ;; RULE-013: content must be non-empty (unless tool message)
       (unless (or content
                   (getf input :tool-calls)
                   (getf input :tool-call-id))
         (error "Message must have :content, :tool-calls, or :tool-call-id"))

       ;; Normalize keyword role to string
       (list :role (if (keywordp role)
                       (string-downcase (symbol-name role))
                       role)
             :content content
             :tool-calls (getf input :tool-calls)
             :tool-call-id (getf input :tool-call-id))))))

(defun normalize-messages (inputs)
  "Normalize list of mixed-format inputs to canonical messages."
  (mapcar #'normalize-message inputs))

;; Usage
(normalize-messages
  '("Hello"  ; String shorthand
    (:role :assistant :content "Hi there!")  ; Keyword role
    (:role "user" :content "How are you?")))  ; Already canonical

;; => ((:ROLE "user" :CONTENT "Hello" :TOOL-CALLS NIL :TOOL-CALL-ID NIL)
;;     (:ROLE "assistant" :CONTENT "Hi there!" :TOOL-CALLS NIL :TOOL-CALL-ID NIL)
;;     (:ROLE "user" :CONTENT "How are you?" :TOOL-CALLS NIL :TOOL-CALL-ID NIL))
```

**Rules Satisfied**: R002 (valid roles), R013 (non-empty content), R006 (preserves ordering)

**Why This Shape**:
- `etypecase` handles multiple input formats safely
- Keyword roles converted to strings (provider requirement)
- Validation ensures rule compliance before API call
- Preserves optional fields (tool-calls, tool-call-id) when present
- Batch normalization via `mapcar` maintains message order

**Variations**:

| Scenario | Modification |
|----------|--------------|
| Strip empty messages | Filter before normalization |
| Add timestamps | Include `:timestamp (get-universal-time)` |
| Trim whitespace | Apply `string-trim` to content |
| Deduplicate | Remove consecutive identical messages |

---

## PATTERN-007: Performance Profiling

**Scenario**: Measure encode/API/decode timing for optimization

**Complete Example**:
```lisp
(defun profile-completion (messages &key provider)
  "Run completion with performance profiling enabled.
   Demonstrates timing collection and analysis."

  ;; Enable profiling - RULE-009: don't modify *performance-stats* directly
  (let ((*performance-profiling* t))
    (let ((response (complete messages :provider provider)))

      ;; Extract performance data - INV-006: standard keys present
      (let ((perf (response-performance response)))
        (when perf
          (format t "~&Performance Breakdown:~%")
          (format t "  Encode time: ~6,3F seconds~%" (getf perf :encode-time))
          (format t "  API time:    ~6,3F seconds~%" (getf perf :api-time))
          (format t "  Decode time: ~6,3F seconds~%" (getf perf :decode-time))
          (format t "  Total time:  ~6,3F seconds~%"
                  (+ (getf perf :encode-time)
                     (getf perf :api-time)
                     (getf perf :decode-time)))

          ;; Token efficiency
          (let ((usage (response-usage response)))
            (format t "~&Token Usage:~%")
            (format t "  Prompt:     ~D tokens~%" (getf usage :prompt-tokens))
            (format t "  Completion: ~D tokens~%" (getf usage :completion-tokens))
            (format t "  Total:      ~D tokens~%" (getf usage :total-tokens))
            (format t "~&Throughput: ~6,1F tokens/second~%"
                    (/ (getf usage :total-tokens)
                       (getf perf :api-time))))))

      response)))

;; Usage
(profile-completion
  '((:role "user" :content "Explain Common Lisp briefly"))
  :provider (make-provider :anthropic :model "claude-3-5-sonnet-20241022"))

;; Output:
;; Performance Breakdown:
;;   Encode time:  0.002 seconds
;;   API time:     1.234 seconds
;;   Decode time:  0.001 seconds
;;   Total time:   1.237 seconds
;; Token Usage:
;;   Prompt:     15 tokens
;;   Completion: 89 tokens
;;   Total:      104 tokens
;; Throughput: 84.3 tokens/second
```

**Rules Satisfied**: R009 (performance stats immutability), INV-006 (standard perf keys), INV-002 (non-negative tokens)

**Why This Shape**:
- Dynamic binding `*performance-profiling*` scopes profiling to call
- Library automatically populates `*performance-stats*` via `with-performance-timing`
- Response object captures timing snapshot (immutable after creation)
- Three phases measured independently: encode (JSON build), API (network), decode (parse)
- Throughput calculation uses API time (actual processing, excludes encode/decode overhead)

**Variations**:

| Scenario | Modification |
|----------|--------------|
| Batch analysis | Collect multiple responses, compute statistics (mean, p95, p99) |
| Compare providers | Profile same query across providers, compare API time |
| Optimization | Identify encode/decode bottlenecks for caching |
| Cost analysis | Combine timing with token usage for $/hour metrics |

---

## PATTERN-008: Configuration from Environment

**Scenario**: Load provider configuration from environment variables and config file

**Complete Example**:
```lisp
(defun setup-providers-from-env ()
  "Initialize providers using environment variables and optional config file.
   Demonstrates config precedence and fallback."

  (let ((providers (make-hash-table :test 'eq)))

    ;; Anthropic - RULE-008: reads ANTHROPIC_API_KEY automatically
    (when (uiop:getenv "ANTHROPIC_API_KEY")
      (setf (gethash :anthropic providers)
            (make-provider :anthropic
                           :model "claude-3-5-sonnet-20241022")))

    ;; OpenAI - explicit key if available
    (when-let ((key (uiop:getenv "OPENAI_API_KEY")))
      (setf (gethash :openai providers)
            (make-provider :openai
                           :api-key key
                           :model "gpt-4-turbo")))

    ;; Ollama - local, no key required
    (setf (gethash :ollama providers)
          (make-provider :ollama
                         :base-url "http://localhost:11434"
                         :model "llama3"))

    ;; Optional: load from config file (opt-in)
    (let ((config-file (merge-pathnames "cl-llm-provider/config.lisp"
                                        (uiop:xdg-config-home))))
      (when (probe-file config-file)
        (format t "~&Loading config from ~A~%" config-file)
        (load config-file)))

    providers))

;; Usage
(defparameter *providers* (setup-providers-from-env))
(complete '((:role "user" :content "Hello"))
          :provider (gethash :anthropic *providers*))
```

**Rules Satisfied**: R005 (API keys from env, not source), R008 (config before use)

**Why This Shape**:
- `make-provider` auto-reads env vars when key not specified
- Explicit `uiop:getenv` check before creating provider (fails fast)
- Ollama created unconditionally (no key required)
- Config file load optional (opt-in, not automatic)
- Hash table keyed by provider type enables easy lookup

**Variations**:

| Scenario | Modification |
|----------|--------------|
| Default provider | Set `*default-provider*` to preferred provider |
| Validation | Probe API with test request after setup |
| Multi-environment | Use `APP_ENV` to switch key sets |
| Secrets manager | Fetch from vault instead of env |

---

## PATTERN-009: Multi-Turn Tool Conversation

**Scenario**: Multiple tool calls across conversation turns

**Complete Example**:
```lisp
(defun multi-turn-tool-chat ()
  "Conversation with multiple tool calls across turns.
   Demonstrates complex tool interaction pattern."

  (let ((tools (list
                (define-tool "get_weather"
                  "Get current weather"
                  '((:name "city" :type :string :description "City name"))
                  :required '("city"))

                (define-tool "get_time"
                  "Get current time"
                  '((:name "timezone" :type :string :description "Timezone"))
                  :required '("timezone"))))
        (provider (make-provider :anthropic :model "claude-3-5-sonnet-20241022"))
        (messages nil))

    (flet ((process-turn (user-input)
             ;; Add user message
             (push (list :role "user" :content user-input) messages)
             (setf messages (nreverse messages))

             ;; Loop until we get :stop finish-reason
             (loop
               (let ((response (complete messages :provider provider :tools tools)))

                 (case (response-finish-reason response)
                   (:tool-calls
                    ;; Execute all tool calls
                    (let ((tool-results
                            (loop for call in (response-tool-calls response)
                                  for name = (tool-call-name call)
                                  for args = (tool-call-arguments call)
                                  for result = (cond
                                                 ((string= name "get_weather")
                                                  (format nil "{\"temp\": 22, \"city\": \"~A\"}"
                                                          (getf args :|city|)))
                                                 ((string= name "get_time")
                                                  (format nil "{\"time\": \"14:30\", \"tz\": \"~A\"}"
                                                          (getf args :|timezone|))))
                                  collect (make-tool-result (tool-call-id call) result))))

                      ;; Add assistant message with tool calls
                      (push (response-message response) messages)
                      (setf messages (nreverse messages))

                      ;; Add all tool results
                      (dolist (result tool-results)
                        (push result messages))
                      (setf messages (nreverse messages))

                      ;; Loop continues - get final response
                      ))

                   (:stop
                    ;; Final answer reached
                    (push (response-message response) messages)
                    (setf messages (nreverse messages))
                    (return (response-content response))))))))

      ;; Turn 1: Single tool call
      (process-turn "What's the weather in Paris?")
      ;; => "The weather in Paris is currently 22°C."

      ;; Turn 2: Multiple tool calls
      (process-turn "Compare that with Tokyo's weather and time")
      ;; => "In Tokyo it's 14:30 with a temperature of 22°C, same as Paris."

      messages)))
```

**Rules Satisfied**: R006 (message ordering), R007 (tool ID preservation), ANTI-002 (check finish-reason)

**Why This Shape**:
- Inner loop handles multi-step tool execution within single turn
- `case` on finish-reason distinguishes tool-calls from final answer
- Multiple tool results appended sequentially (preserves correlation)
- Each tool call processed independently with proper ID tracking
- `response-message` preserves complete assistant turn state
- Message history maintains chronological order throughout

**Variations**:

| Scenario | Modification |
|----------|--------------|
| Parallel tool execution | Map tool execution concurrently before creating results |
| Tool error handling | Wrap execution in `handler-case`, pass `:is-error t` |
| Max iterations | Add iteration counter, bail after limit |
| Streaming tools | Yield partial results for long-running tools |

---

## PATTERN-010: Batch Processing with Error Recovery

**Scenario**: Process multiple items with per-item error handling and retry

**Complete Example**:
```lisp
(defun batch-process-with-recovery (items provider &key (max-retries 3))
  "Process batch of items with exponential backoff retry.
   Demonstrates robust batch processing pattern."

  (let ((results (make-array (length items) :initial-element nil))
        (backoff-base 2))  ; Exponential backoff base (seconds)

    (loop for item in items
          for index from 0
          do
          (let ((retry-count 0))
            ;; Retry loop with exponential backoff
            (loop
              (handler-case
                  ;; Process item
                  (let* ((messages (list (list :role "user" :content item)))
                         (response (complete messages :provider provider :max-tokens 50)))

                    ;; Success - store result and exit retry loop
                    (setf (aref results index)
                          (list :success t
                                :input item
                                :output (response-content response)
                                :tokens (getf (response-usage response) :total-tokens)))
                    (return))  ; Exit retry loop

                ;; Rate limit - wait and retry
                (provider-rate-limit-error (condition)
                  (if (< retry-count max-retries)
                      (let ((wait-time (* backoff-base (expt 2 retry-count))))
                        (format t "~&Rate limited on item ~D. Waiting ~D seconds...~%"
                                index wait-time)
                        (sleep wait-time)
                        (incf retry-count))
                      ;; Max retries exceeded - record failure
                      (progn
                        (setf (aref results index)
                              (list :success nil
                                    :input item
                                    :error :rate-limit
                                    :message (error-message condition)))
                        (return))))

                ;; Other API errors - record and continue
                (provider-api-error (condition)
                  (setf (aref results index)
                        (list :success nil
                              :input item
                              :error :api-error
                              :status (error-status-code condition)
                              :message (error-message condition)))
                  (return))

                ;; Unexpected errors - record and continue
                (error (condition)
                  (setf (aref results index)
                        (list :success nil
                              :input item
                              :error :unexpected
                              :message (princ-to-string condition)))
                  (return))))))

    ;; Return results with summary
    (let ((successful (count-if (lambda (r) (getf r :success)) results))
          (failed (count-if (lambda (r) (not (getf r :success))) results)))
      (list :total (length items)
            :successful successful
            :failed failed
            :results (coerce results 'list)))))

;; Usage
(batch-process-with-recovery
  '("What is 2+2?" "Explain Lisp" "Define recursion")
  (make-provider :anthropic :model "claude-3-5-sonnet-20241022")
  :max-retries 3)

;; => (:TOTAL 3 :SUCCESSFUL 3 :FAILED 0
;;     :RESULTS ((:SUCCESS T :INPUT "What is 2+2?" :OUTPUT "4" :TOKENS 12)
;;               (:SUCCESS T :INPUT "Explain Lisp" :OUTPUT "..." :TOKENS 45)
;;               (:SUCCESS T :INPUT "Define recursion" :OUTPUT "..." :TOKENS 38)))
```

**Rules Satisfied**: ANTI-005 (exponential backoff, not tight loop), R010 (condition hierarchy)

**Why This Shape**:
- Exponential backoff: `2^retry_count` seconds prevents thundering herd
- Per-item retry counter isolated from other items
- Rate limit retries up to max, then records failure (not infinite loop)
- Other errors fail immediately (no retry - authentication won't fix itself)
- Results array pre-allocated for efficient updates
- Success/failure tracked per item for partial batch recovery
- Final summary provides batch-level statistics

**Variations**:

| Scenario | Modification |
|----------|--------------|
| Parallel processing | Use threads/futures, share semaphore for rate limiting |
| Priority queue | Reorder items, process high-priority first |
| Checkpointing | Save results periodically, resume from checkpoint |
| Jitter | Add randomness to backoff: `(+ base (random variance))` |

---

## EDGE-001: Empty Tool Calls Response

**Scenario**: Model returns no tool calls despite tools being available

**What Happens**:
1. Tools provided in request
2. Model generates direct text answer instead
3. `(response-tool-calls response)` returns `nil`
4. `(response-finish-reason response)` is `:stop`

**Idiomatic Handling**:
```lisp
(defun handle-optional-tools (messages tools provider)
  "Handle case where tools are available but model chooses not to use them.
   Finish-reason distinguishes tool-calls from direct answer."

  (let ((response (complete messages :provider provider :tools tools)))

    ;; ANTI-002: Always check finish-reason, not just presence of tool-calls
    (case (response-finish-reason response)
      (:tool-calls
       ;; Model chose to use tools
       (list :type :tool-use
             :calls (response-tool-calls response)))

      (:stop
       ;; Model answered directly without tools
       (list :type :direct-answer
             :content (response-content response)))

      (:length
       ;; Truncated mid-response
       (list :type :truncated
             :content (response-content response)
             :warning "Response was truncated")))))
```

**Why Not**:
```lisp
;; WRONG - assumes tool-calls presence means tool usage
(if (response-tool-calls response)
    (handle-tools ...)
    (handle-text ...))
;; Breaks when finish-reason is :length and tool-calls is nil
```

---

## EDGE-002: Length-Limited Completion

**Scenario**: Response truncated due to `max-tokens` limit

**What Happens**:
1. Request specifies `:max-tokens 50`
2. Model's natural response would be 150 tokens
3. Response truncates mid-sentence
4. `(response-finish-reason response)` is `:length`
5. `(response-content response)` contains partial text

**Idiomatic Handling**:
```lisp
(defun handle-truncation (messages provider max-tokens)
  "Detect and handle truncated responses with continuation."

  (let ((response (complete messages :provider provider :max-tokens max-tokens)))

    (case (response-finish-reason response)
      (:length
       ;; Truncated - optionally continue
       (format t "~&WARNING: Response truncated~%")

       ;; Option 1: Return partial
       (response-content response)

       ;; Option 2: Continue with increased limit
       ;; (let ((continued-messages (append messages
       ;;                                   (list (response-message response))
       ;;                                   (list (list :role "user"
       ;;                                               :content "Please continue.")))))
       ;;   (complete continued-messages :provider provider :max-tokens (* max-tokens 2)))
       )

      (:stop
       ;; Complete response
       (response-content response)))))
```

---

## EDGE-003: Rate Limit with Exponential Backoff

**Scenario**: Multiple requests hit rate limit requiring progressive backoff

**What Happens**:
1. First request succeeds
2. Second request → 429 rate limit
3. Immediate retry → still rate limited
4. Need exponential backoff to avoid amplifying problem

**Idiomatic Handling**:
```lisp
(defun request-with-backoff (messages provider &key (max-retries 5))
  "Exponential backoff on rate limit with jitter.
   Prevents thundering herd on retry."

  (let ((base-delay 1)   ; Start with 1 second
        (max-delay 60)   ; Cap at 60 seconds
        (jitter 0.1))    ; ±10% randomness

    (loop for attempt from 0 below max-retries
          do
          (handler-case
              ;; Attempt request
              (return (complete messages :provider provider))

            (provider-rate-limit-error (condition)
              ;; Calculate delay with exponential backoff + jitter
              (let* ((exponential-delay (min max-delay (* base-delay (expt 2 attempt))))
                     (jitter-amount (* exponential-delay jitter))
                     (actual-delay (+ exponential-delay
                                      (- (random (* 2 jitter-amount))
                                         jitter-amount))))

                (if (< attempt (1- max-retries))
                    (progn
                      (format t "~&Rate limited (attempt ~D/~D). Waiting ~,1F seconds...~%"
                              (1+ attempt) max-retries actual-delay)
                      (sleep actual-delay))
                    ;; Final attempt failed
                    (error condition))))

            ;; Non-retryable errors propagate immediately
            (provider-authentication-error (condition)
              (error condition)))

          finally
          (error "Max retries exceeded"))))
```

**Why This Shape**:
- Exponential: 1s, 2s, 4s, 8s, 16s (doubles each retry)
- Max delay cap prevents excessive waits
- Jitter prevents synchronized retries across multiple clients
- Rate limit retries, auth errors propagate immediately
- Attempt counter visible in logs for monitoring

---

## EDGE-004: Missing API Key Recovery

**Scenario**: API key missing at runtime, need interactive recovery

**What Happens**:
1. Provider created without key
2. `ANTHROPIC_API_KEY` environment variable not set
3. `make-provider` signals `provider-configuration-error`
4. Need to prompt user or load from alternate source

**Idiomatic Handling**:
```lisp
(defun get-provider-with-fallback (provider-type model)
  "Create provider with interactive fallback if key missing."

  (handler-case
      ;; Try automatic key discovery
      (make-provider provider-type :model model)

    (provider-configuration-error (condition)
      ;; Key missing - try fallbacks
      (format t "~&~A~%" (error-message condition))

      ;; Fallback 1: Check config file
      (let ((config-file (merge-pathnames "cl-llm-provider/config.lisp"
                                          (uiop:xdg-config-home))))
        (when (probe-file config-file)
          (format t "~&Loading config file: ~A~%" config-file)
          (load config-file)

          ;; Retry after loading config
          (handler-case
              (return-from get-provider-with-fallback
                (make-provider provider-type :model model))
            (provider-configuration-error ()
              ;; Still missing - continue to next fallback
              ))))

      ;; Fallback 2: Interactive prompt
      (format t "~&Enter API key for ~A: " provider-type)
      (finish-output)
      (let ((key (read-line)))
        (make-provider provider-type :api-key key :model model)))))
```

---

## Summary: Pattern Coverage

| Category | Patterns | Edge Cases |
|----------|----------|------------|
| Basic operations | 001, 002, 005, 006 | - |
| Tool calling | 003, 009 | 001 |
| Error handling | 004, 010 | 003, 004 |
| Configuration | 008 | 004 |
| Performance | 007 | - |
| Edge cases | - | 001, 002, 003, 004 |

**Total**: 10 core patterns + 4 edge case patterns = 14 complete, runnable examples

**Rules demonstrated**: R001-R015, INV-001-INV-007, ANTI-001-ANTI-005
