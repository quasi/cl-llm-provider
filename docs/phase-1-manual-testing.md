# Phase 1 Manual Testing Guide

This guide provides detailed instructions for manually testing all Phase 1 features of cl-llm-provider. Phase 1 includes:
- **Streaming Support** - Real-time response streaming from LLM APIs
- **Token Counting** - Character-based token estimation
- **Cost Estimation** - Pre-request cost calculation
- **Observability Hooks** - Logging, tracing, and monitoring callbacks

## Prerequisites

### 1. API Keys

You'll need API keys for at least one provider to test streaming:

```bash
# OpenAI (for GPT models)
export OPENAI_API_KEY="sk-..."

# Anthropic (for Claude models)
export ANTHROPIC_API_KEY="sk-ant-..."

# Ollama (for local models - no key needed)
# Install from: https://ollama.ai
ollama pull llama2  # or any model
```

### 2. Load the Library

```bash
# Start SBCL REPL
sbcl

# Load the library
(ql:quickload :cl-llm-provider)  # or (asdf:load-system :cl-llm-provider)

# Use the package for convenience
(use-package :cl-llm-provider)
```

### 3. Verify Installation

Run automated tests first to ensure everything works:

```lisp
;; All tests should pass before manual testing
(ql:quickload :cl-llm-provider/tests)
```

---

## Test Group 1: Streaming Support

### Test 1.1: Basic OpenAI Streaming

**Purpose**: Verify streaming works with OpenAI's API (data-only SSE format).

**Code**:
```lisp
(defun test-openai-streaming ()
  "Test basic OpenAI streaming with GPT-4o-mini"
  (format t "~%=== Test 1.1: OpenAI Streaming ===~%~%")

  (let* ((provider (make-provider :openai :model "gpt-4o-mini"))
         (messages '((:role "user" :content "Count from 1 to 10, one number per line.")))
         (stream (complete-stream messages :provider provider)))

    (format t "Reading chunks from stream...~%~%")

    ;; Read and display chunks
    (loop for chunk = (read-stream-chunk stream)
          while chunk
          do (let ((delta (chunk-delta chunk)))
               (when (and delta (> (length delta) 0))
                 (format t "~A" delta)
                 (force-output))))

    (format t "~%~%Stream complete. State: ~A~%" (stream-state stream))
    (format t "Total chunks: ~D~%" (length (stream-chunks stream)))
    (format t "Accumulated content:~%~A~%" (stream-accumulated-content stream))

    ;; Verify
    (assert (eq (stream-state stream) :closed) nil "Stream should be closed")
    (assert (> (length (stream-chunks stream)) 0) nil "Should have received chunks")
    (assert (> (length (stream-accumulated-content stream)) 0) nil "Should have content")

    (format t "~%✓ Test 1.1 PASSED~%")))

;; Run the test
(test-openai-streaming)
```

**Expected Output**:
```
=== Test 1.1: OpenAI Streaming ===

Reading chunks from stream...

1
2
3
4
5
6
7
8
9
10

Stream complete. State: CLOSED
Total chunks: 12
Accumulated content:
1
2
3
4
5
6
7
8
9
10

✓ Test 1.1 PASSED
```

**What to Verify**:
- ✅ Numbers appear one at a time (streaming, not all at once)
- ✅ No errors or warnings
- ✅ Stream state is `:closed` at end
- ✅ Accumulated content matches displayed output

---

### Test 1.2: Anthropic Streaming

**Purpose**: Verify streaming works with Anthropic's API (event-typed SSE format).

**Code**:
```lisp
(defun test-anthropic-streaming ()
  "Test Anthropic streaming with Claude"
  (format t "~%=== Test 1.2: Anthropic Streaming ===~%~%")

  (let* ((provider (make-provider :anthropic :model "claude-3-5-haiku-20241022"))
         (messages '((:role "user" :content "List 5 programming languages, one per line.")))
         (stream (complete-stream messages
                                  :provider provider
                                  :max-tokens 200)))

    (format t "Reading chunks from Anthropic stream...~%~%")

    (loop for chunk = (read-stream-chunk stream)
          while chunk
          do (let ((delta (chunk-delta chunk)))
               (when (and delta (> (length delta) 0))
                 (format t "~A" delta)
                 (force-output))))

    (format t "~%~%Stream state: ~A~%" (stream-state stream))
    (format t "Final finish reason: ~A~%"
            (when (stream-chunks stream)
              (chunk-finish-reason (car (last (stream-chunks stream))))))

    ;; Verify
    (assert (eq (stream-state stream) :closed))
    (assert (> (length (stream-accumulated-content stream)) 0))

    (format t "~%✓ Test 1.2 PASSED~%")))

;; Run the test
(test-anthropic-streaming)
```

**Expected Output**:
```
=== Test 1.2: Anthropic Streaming ===

Reading chunks from Anthropic stream...

1. Python
2. JavaScript
3. Java
4. C++
5. Go

Stream state: CLOSED
Final finish reason: END_TURN

✓ Test 1.2 PASSED
```

**What to Verify**:
- ✅ Content streams in real-time
- ✅ Finish reason is `:end-turn` or `:max-tokens`
- ✅ No errors parsing Anthropic's event format

---

### Test 1.3: Streaming with Callbacks

**Purpose**: Test `complete-stream` callback API for incremental processing.

**Code**:
```lisp
(defun test-streaming-callbacks ()
  "Test streaming with on-chunk, on-complete, and on-error callbacks"
  (format t "~%=== Test 1.3: Streaming Callbacks ===~%~%")

  (let ((chunk-count 0)
        (final-content nil)
        (error-caught nil))

    (complete-stream
     '((:role "user" :content "Say hello in 3 languages."))
     :provider (make-provider :openai :model "gpt-4o-mini")
     :on-chunk (lambda (chunk)
                 (incf chunk-count)
                 (format t "."))  ; Progress indicator
     :on-complete (lambda (full-content final-chunk)
                    (setf final-content full-content)
                    (format t "~%~%Complete! Received ~D chunks.~%" chunk-count)
                    (format t "Final content:~%~A~%" full-content))
     :on-error (lambda (error)
                 (setf error-caught error)
                 (format t "~%ERROR: ~A~%" error)))

    (format t "~%Chunk count: ~D~%" chunk-count)

    ;; Verify
    (assert (> chunk-count 0) nil "Should receive chunks")
    (assert (not (null final-content)) nil "Should have final content")
    (assert (null error-caught) nil "Should not have errors")

    (format t "~%✓ Test 1.3 PASSED~%")))

;; Run the test
(test-streaming-callbacks)
```

**Expected Output**:
```
=== Test 1.3: Streaming Callbacks ===

.........

Complete! Received 9 chunks.
Final content:
Hello - English
Bonjour - French
Hola - Spanish

Chunk count: 9

✓ Test 1.3 PASSED
```

**What to Verify**:
- ✅ `on-chunk` called multiple times (dots appear)
- ✅ `on-complete` called once at end with full content
- ✅ `on-error` not called (no errors)

---

### Test 1.4: Streaming Error Handling

**Purpose**: Verify streaming handles errors gracefully (invalid API key, network issues).

**Code**:
```lisp
(defun test-streaming-error-handling ()
  "Test streaming with invalid API key to verify error handling"
  (format t "~%=== Test 1.4: Streaming Error Handling ===~%~%")

  (let ((error-caught nil)
        (chunk-received nil))

    ;; Use invalid API key
    (handler-case
        (let* ((bad-provider (make-instance 'openai-provider
                                           :api-key "sk-invalid-key-12345"
                                           :model "gpt-4o-mini"))
               (stream (complete-stream
                       '((:role "user" :content "Hello"))
                       :provider bad-provider
                       :on-chunk (lambda (chunk)
                                   (setf chunk-received t)
                                   (format t "Chunk: ~A~%" chunk))
                       :on-error (lambda (error)
                                   (setf error-caught error)
                                   (format t "Error caught by callback: ~A~%" error)))))

          (format t "Stream state: ~A~%" (stream-state stream)))

      (error (e)
        (format t "Error caught by handler-case: ~A~%" e)
        (setf error-caught e)))

    ;; Verify error was caught
    (assert (not (null error-caught)) nil "Should catch authentication error")
    (assert (null chunk-received) nil "Should not receive chunks with bad key")

    (format t "~%✓ Test 1.4 PASSED - Error handling works~%")))

;; Run the test
(test-streaming-error-handling)
```

**Expected Output**:
```
=== Test 1.4: Streaming Error Handling ===

Error caught by callback: HTTP request failed with status 401: Unauthorized
Error caught by handler-case: HTTP request failed with status 401: Unauthorized

✓ Test 1.4 PASSED - Error handling works
```

**What to Verify**:
- ✅ Authentication error is caught
- ✅ No chunks received with invalid key
- ✅ Error callback fires before exception propagates

---

## Test Group 2: Token Counting

### Test 2.1: Basic Token Counting

**Purpose**: Verify token counting provides reasonable estimates.

**Code**:
```lisp
(defun test-token-counting ()
  "Test token counting with various message types"
  (format t "~%=== Test 2.1: Token Counting ===~%~%")

  ;; Test 1: Simple message
  (let* ((msg1 '((:role "user" :content "Hello, world!")))
         (count1 (count-tokens msg1)))
    (format t "Message: ~S~%" (getf (car msg1) :content))
    (format t "Token count: ~D~%" count1)
    (format t "Characters: ~D~%" (length (getf (car msg1) :content)))
    (format t "Chars/token ratio: ~,2F~%~%" (/ (length (getf (car msg1) :content)) count1)))

  ;; Test 2: Multi-turn conversation
  (let* ((conversation '((:role "user" :content "What is 2+2?")
                        (:role "assistant" :content "2+2 equals 4.")
                        (:role "user" :content "What about 3+3?")))
         (count2 (count-tokens conversation)))
    (format t "Conversation: ~D messages~%" (length conversation))
    (format t "Total token count: ~D~%" count2)
    (format t "Average tokens/message: ~,1F~%~%" (/ count2 (length conversation))))

  ;; Test 3: Long message
  (let* ((long-text (make-string 1000 :initial-element #\a))
         (msg3 `((:role "user" :content ,long-text)))
         (count3 (count-tokens msg3)))
    (format t "Long message: ~D characters~%" (length long-text))
    (format t "Token count: ~D~%" count3)
    (format t "Chars/token ratio: ~,2F~%~%" (/ (length long-text) count3)))

  ;; Test 4: With system message
  (let* ((messages '((:role "user" :content "Hello")))
         (system "You are a helpful assistant.")
         (count4 (count-tokens-with-system messages system)))
    (format t "Messages + system: ~D tokens~%" count4)
    (format t "System overhead: ~D tokens~%~%"
            (- count4 (count-tokens messages))))

  (format t "✓ Test 2.1 PASSED~%"))

;; Run the test
(test-token-counting)
```

**Expected Output**:
```
=== Test 2.1: Token Counting ===

Message: "Hello, world!"
Token count: 7
Characters: 13
Chars/token ratio: 1.86

Conversation: 3 messages
Total token count: 27
Average tokens/message: 9.0

Long message: 1000 characters
Token count: 254
Chars/token ratio: 3.94

Messages + system: 19 tokens
System overhead: 11 tokens

✓ Test 2.1 PASSED
```

**What to Verify**:
- ✅ Char/token ratio is ~3-5 (typical for English)
- ✅ Token counts increase with message length
- ✅ System messages add overhead tokens
- ✅ Counts are reasonable (not 0, not astronomically high)

**Note**: These are estimates (4 chars/token). Real usage may vary ±5-10%.

---

### Test 2.2: Token Counting Accuracy Check

**Purpose**: Compare estimated tokens against actual API usage.

**Code**:
```lisp
(defun test-token-accuracy ()
  "Compare estimated tokens with actual API usage"
  (format t "~%=== Test 2.2: Token Accuracy Check ===~%~%")

  (let* ((messages '((:role "user" :content "Tell me a joke about programming.")))
         (estimated-input (count-tokens messages))
         (provider (make-provider :openai :model "gpt-4o-mini"))
         (response (complete messages :provider provider :max-tokens 100)))

    ;; Get actual usage from response
    (let* ((usage (response-usage response))
           (actual-input (getf usage :prompt-tokens))
           (actual-output (getf usage :completion-tokens))
           (estimated-output (count-tokens `((:role "assistant"
                                              :content ,(response-content response))))))

      (format t "INPUT TOKENS:~%")
      (format t "  Estimated: ~D~%" estimated-input)
      (format t "  Actual:    ~D~%" actual-input)
      (format t "  Error:     ~,1F%~%~%"
              (* 100 (/ (abs (- estimated-input actual-input)) actual-input)))

      (format t "OUTPUT TOKENS:~%")
      (format t "  Estimated: ~D~%" estimated-output)
      (format t "  Actual:    ~D~%" actual-output)
      (format t "  Error:     ~,1F%~%~%"
              (* 100 (/ (abs (- estimated-output actual-output)) actual-output)))

      (format t "Response: ~A~%~%" (response-content response))

      ;; Verify accuracy is reasonable (within 20%)
      (let ((input-error-pct (* 100 (/ (abs (- estimated-input actual-input)) actual-input))))
        (assert (< input-error-pct 20.0) nil
                "Input token estimate should be within 20% of actual"))

      (format t "✓ Test 2.2 PASSED~%"))))

;; Run the test
(test-token-accuracy)
```

**Expected Output**:
```
=== Test 2.2: Token Accuracy Check ===

INPUT TOKENS:
  Estimated: 10
  Actual:    9
  Error:     11.1%

OUTPUT TOKENS:
  Estimated: 28
  Actual:    30
  Error:     6.7%

Response: Why do programmers prefer dark mode? Because light attracts bugs!

✓ Test 2.2 PASSED
```

**What to Verify**:
- ✅ Estimation error is typically 5-15%
- ✅ Errors over 20% should be investigated
- ✅ Estimates are conservative (better to over-estimate slightly)

---

## Test Group 3: Cost Estimation

### Test 3.1: Basic Cost Estimation

**Purpose**: Verify cost calculation before making API calls.

**Code**:
```lisp
(defun test-cost-estimation ()
  "Test cost estimation for different providers and models"
  (format t "~%=== Test 3.1: Cost Estimation ===~%~%")

  (let ((messages '((:role "user" :content "Write a 100 word essay on AI."))))

    ;; Test OpenAI GPT-4o
    (format t "OpenAI GPT-4o:~%")
    (let ((provider (make-provider :openai :model "gpt-4o")))
      (multiple-value-bind (input-cost output-cost total)
          (estimate-cost messages
                        :provider provider
                        :model "gpt-4o"
                        :max-tokens 500)
        (format t "  Input:  ~A~%" (format-cost input-cost))
        (format t "  Output: ~A (est. 500 tokens)~%" (format-cost output-cost))
        (format t "  Total:  ~A~%~%" (format-cost total))))

    ;; Test Anthropic Claude
    (format t "Anthropic Claude 3.5 Sonnet:~%")
    (let ((provider (make-provider :anthropic :model "claude-3-5-sonnet-20241022")))
      (multiple-value-bind (input-cost output-cost total)
          (estimate-cost messages
                        :provider provider
                        :model "claude-3-5-sonnet-20241022"
                        :max-tokens 500)
        (format t "  Input:  ~A~%" (format-cost input-cost))
        (format t "  Output: ~A (est. 500 tokens)~%" (format-cost output-cost))
        (format t "  Total:  ~A~%~%" (format-cost total))))

    ;; Test cost comparison
    (format t "Cost comparison for same request:~%")
    (let* ((providers '((:openai "gpt-4o-mini")
                       (:anthropic "claude-3-5-haiku-20241022")))
           (costs (loop for (provider-type model) in providers
                       collect (multiple-value-bind (input-cost output-cost total)
                                   (estimate-cost messages
                                                 :provider (make-provider provider-type :model model)
                                                 :model model
                                                 :max-tokens 100)
                                 (list provider-type model total)))))

      (dolist (cost-info costs)
        (format t "  ~A ~A: ~A~%"
                (first cost-info)
                (second cost-info)
                (format-cost (third cost-info)))))

    (format t "~%✓ Test 3.1 PASSED~%")))

;; Run the test
(test-cost-estimation)
```

**Expected Output**:
```
=== Test 3.1: Cost Estimation ===

OpenAI GPT-4o:
  Input:  $0.0001
  Output: $0.0015 (est. 500 tokens)
  Total:  $0.0016

Anthropic Claude 3.5 Sonnet:
  Input:  $0.0001
  Output: $0.0075 (est. 500 tokens)
  Total:  $0.0076

Cost comparison for same request:
  OPENAI gpt-4o-mini: $0.0001
  ANTHROPIC claude-3-5-haiku-20241022: $0.0001

✓ Test 3.1 PASSED
```

**What to Verify**:
- ✅ Costs are calculated (not nil)
- ✅ Costs are reasonable (fractions of a cent for short messages)
- ✅ Different models have different costs
- ✅ GPT-4o is more expensive than GPT-4o-mini
- ✅ Output costs are higher than input costs (typical)

---

### Test 3.2: Cost Budget Validation

**Purpose**: Use cost estimation to validate requests stay within budget.

**Code**:
```lisp
(defun test-cost-budget ()
  "Test using cost estimation for budget validation"
  (format t "~%=== Test 3.2: Cost Budget Validation ===~%~%")

  (let ((budget 0.01)  ; $0.01 budget
        (provider (make-provider :openai :model "gpt-4o"))
        (messages '((:role "user" :content "Summarize this article in 50 words."))))

    (format t "Budget: ~A~%" (format-cost budget))

    ;; Check small request (should fit)
    (format t "~%Testing request with max-tokens=100:~%")
    (multiple-value-bind (input-cost output-cost total)
        (estimate-cost messages :provider provider :max-tokens 100)
      (format t "  Estimated cost: ~A~%" (format-cost total))
      (if (<= total budget)
          (format t "  ✓ Within budget - request would proceed~%")
          (format t "  ✗ Over budget - request would be rejected~%")))

    ;; Check large request (should exceed budget)
    (format t "~%Testing request with max-tokens=10000:~%")
    (multiple-value-bind (input-cost output-cost total)
        (estimate-cost messages :provider provider :max-tokens 10000)
      (format t "  Estimated cost: ~A~%" (format-cost total))
      (if (<= total budget)
          (format t "  ✓ Within budget - request would proceed~%")
          (format t "  ✗ Over budget - request would be rejected~%")))

    (format t "~%Example budget validation function:~%")
    (format t "~S~%"
            '(defun complete-with-budget (messages budget &rest args)
               (multiple-value-bind (input-cost output-cost total)
                   (apply #'estimate-cost messages args)
                 (if (<= total budget)
                     (apply #'complete messages args)
                     (error "Request exceeds budget: ~A > ~A"
                            (format-cost total) (format-cost budget))))))

    (format t "~%✓ Test 3.2 PASSED~%")))

;; Run the test
(test-cost-budget)
```

**Expected Output**:
```
=== Test 3.2: Cost Budget Validation ===

Budget: $0.0100

Testing request with max-tokens=100:
  Estimated cost: $0.0004
  ✓ Within budget - request would proceed

Testing request with max-tokens=10000:
  Estimated cost: $0.0380
  ✗ Over budget - request would be rejected

Example budget validation function:
(DEFUN COMPLETE-WITH-BUDGET (MESSAGES BUDGET &REST ARGS)
  (MULTIPLE-VALUE-BIND (INPUT-COST OUTPUT-COST TOTAL)
      (APPLY #'ESTIMATE-COST MESSAGES ARGS)
    (IF (<= TOTAL BUDGET)
        (APPLY #'COMPLETE MESSAGES ARGS)
        (ERROR "Request exceeds budget: ~A > ~A"
               (FORMAT-COST TOTAL) (FORMAT-COST BUDGET)))))

✓ Test 3.2 PASSED
```

**What to Verify**:
- ✅ Small requests fit within budget
- ✅ Large requests exceed budget
- ✅ Budget validation logic works correctly

---

## Test Group 4: Observability Hooks

### Test 4.1: Basic Hook Usage

**Purpose**: Test adding hooks to track requests/responses.

**Code**:
```lisp
(defun test-basic-hooks ()
  "Test basic hook functionality"
  (format t "~%=== Test 4.1: Basic Hooks ===~%~%")

  (let ((request-count 0)
        (response-count 0)
        (error-count 0)
        (hooks (make-hooks)))

    ;; Add hooks
    (add-hook hooks :before-request
              (lambda (provider model messages)
                (incf request-count)
                (format t "→ Request #~D: ~A ~A (~D messages)~%"
                        request-count
                        (provider-type provider)
                        model
                        (length messages))))

    (add-hook hooks :after-response
              (lambda (provider model response timing)
                (incf response-count)
                (format t "← Response #~D: ~,2Fs, ~A tokens~%"
                        response-count
                        timing
                        (getf (response-usage response) :total-tokens))))

    (add-hook hooks :on-error
              (lambda (provider model error)
                (incf error-count)
                (format t "✗ Error #~D: ~A~%" error-count error)))

    ;; Make successful request
    (format t "Making successful request...~%")
    (complete '((:role "user" :content "Say 'hello'"))
              :provider (make-provider :openai :model "gpt-4o-mini")
              :hooks hooks)

    ;; Make failing request
    (format t "~%Making failing request...~%")
    (handler-case
        (complete '((:role "user" :content "Hello"))
                  :provider (make-instance 'openai-provider
                                          :api-key "invalid"
                                          :model "gpt-4o-mini")
                  :hooks hooks)
      (error (e)
        (format t "Error handled: ~A~%" e)))

    (format t "~%Summary:~%")
    (format t "  Requests:  ~D~%" request-count)
    (format t "  Responses: ~D~%" response-count)
    (format t "  Errors:    ~D~%" error-count)

    ;; Verify
    (assert (= request-count 2) nil "Should have 2 requests")
    (assert (= response-count 1) nil "Should have 1 response")
    (assert (= error-count 1) nil "Should have 1 error")

    (format t "~%✓ Test 4.1 PASSED~%")))

;; Run the test
(test-basic-hooks)
```

**Expected Output**:
```
=== Test 4.1: Basic Hooks ===

Making successful request...
→ Request #1: OPENAI gpt-4o-mini (1 messages)
← Response #1: 0.45s, 12 tokens

Making failing request...
→ Request #2: OPENAI gpt-4o-mini (1 messages)
✗ Error #1: HTTP request failed with status 401
Error handled: HTTP request failed with status 401

Summary:
  Requests:  2
  Responses: 1
  Errors:    1

✓ Test 4.1 PASSED
```

**What to Verify**:
- ✅ `:before-request` called before each request
- ✅ `:after-response` called only on success
- ✅ `:on-error` called on failure
- ✅ Hook counts match request/response counts

---

### Test 4.2: Logging Hooks

**Purpose**: Test the convenience `make-logging-hooks` function.

**Code**:
```lisp
(defun test-logging-hooks ()
  "Test logging hooks at different levels"
  (format t "~%=== Test 4.2: Logging Hooks ===~%~%")

  ;; Test at :info level (default)
  (format t "INFO level logging:~%")
  (format t "-------------------~%")
  (let ((hooks (make-logging-hooks :level :info)))
    (complete '((:role "user" :content "Say hello"))
              :provider (make-provider :openai :model "gpt-4o-mini")
              :hooks hooks
              :max-tokens 20))

  ;; Test at :debug level (verbose)
  (format t "~%~%DEBUG level logging:~%")
  (format t "--------------------~%")
  (let ((hooks (make-logging-hooks :level :debug)))
    (complete '((:role "user" :content "Say goodbye"))
              :provider (make-provider :openai :model "gpt-4o-mini")
              :hooks hooks
              :max-tokens 20))

  ;; Test error logging
  (format t "~%~%Error logging:~%")
  (format t "--------------~%")
  (let ((hooks (make-logging-hooks)))
    (handler-case
        (complete '((:role "user" :content "Hello"))
                  :provider (make-instance 'openai-provider
                                          :api-key "bad-key"
                                          :model "gpt-4o-mini")
                  :hooks hooks)
      (error (e)
        (format t "Exception propagated after logging~%"))))

  (format t "~%✓ Test 4.2 PASSED~%"))

;; Run the test
(test-logging-hooks)
```

**Expected Output**:
```
=== Test 4.2: Logging Hooks ===

INFO level logging:
-------------------
[14:23:45] LLM Request: OPENAI gpt-4o-mini (1 messages)
[14:23:46] LLM Response: 0.43s, 6 tokens


DEBUG level logging:
--------------------
[14:23:46] LLM Request: OPENAI gpt-4o-mini (1 messages)
  Messages: ((:ROLE "user" :CONTENT "Say goodbye"))
[14:23:47] LLM Response: 0.38s, 7 tokens
  Content: "Goodbye! Take care."


Error logging:
--------------
[14:23:47] LLM Request: OPENAI gpt-4o-mini (1 messages)
[14:23:47] LLM Error: HTTP request failed with status 401
Exception propagated after logging

✓ Test 4.2 PASSED
```

**What to Verify**:
- ✅ Timestamps are formatted correctly (HH:MM:SS)
- ✅ :info level shows basic info (no message content)
- ✅ :debug level shows full messages and response content
- ✅ Errors are logged with timestamps
- ✅ Logs are human-readable

---

### Test 4.3: Custom Logging to File

**Purpose**: Test logging hooks with file output instead of stdout.

**Code**:
```lisp
(defun test-file-logging ()
  "Test logging hooks to file"
  (format t "~%=== Test 4.3: File Logging ===~%~%")

  (let ((log-file "/tmp/llm-provider-test.log"))

    ;; Delete old log if exists
    (when (probe-file log-file)
      (delete-file log-file))

    ;; Create logging hooks writing to file
    (with-open-file (stream log-file
                           :direction :output
                           :if-exists :append
                           :if-does-not-exist :create)
      (let ((hooks (make-logging-hooks :stream stream :level :debug)))

        (format t "Making 3 requests with file logging...~%")

        (loop for i from 1 to 3
              do (complete `((:role "user" :content ,(format nil "Test ~D" i)))
                          :provider (make-provider :openai :model "gpt-4o-mini")
                          :hooks hooks
                          :max-tokens 10))))

    ;; Read and display log file
    (format t "~%Log file contents:~%")
    (format t "==================~%")
    (with-open-file (stream log-file :direction :input)
      (loop for line = (read-line stream nil)
            while line
            do (format t "~A~%" line)))

    ;; Verify log file exists and has content
    (assert (probe-file log-file) nil "Log file should exist")
    (let ((size (with-open-file (stream log-file)
                  (file-length stream))))
      (assert (> size 0) nil "Log file should have content")
      (format t "~%Log file size: ~D bytes~%" size))

    (format t "~%✓ Test 4.3 PASSED~%")))

;; Run the test
(test-file-logging)
```

**Expected Output**:
```
=== Test 4.3: File Logging ===

Making 3 requests with file logging...

Log file contents:
==================
[14:25:10] LLM Request: OPENAI gpt-4o-mini (1 messages)
  Messages: ((:ROLE "user" :CONTENT "Test 1"))
[14:25:11] LLM Response: 0.42s, 8 tokens
  Content: "Test 1 received."
[14:25:11] LLM Request: OPENAI gpt-4o-mini (1 messages)
  Messages: ((:ROLE "user" :CONTENT "Test 2"))
[14:25:12] LLM Response: 0.39s, 8 tokens
  Content: "Test 2 received."
[14:25:12] LLM Request: OPENAI gpt-4o-mini (1 messages)
  Messages: ((:ROLE "user" :CONTENT "Test 3"))
[14:25:13] LLM Response: 0.41s, 8 tokens
  Content: "Test 3 received."

Log file size: 487 bytes

✓ Test 4.3 PASSED
```

**What to Verify**:
- ✅ Log file is created at specified path
- ✅ All requests are logged to file
- ✅ File can be read back correctly
- ✅ Timestamps are sequential

---

### Test 4.4: Global Hooks

**Purpose**: Test `*global-hooks*` for application-wide observability.

**Code**:
```lisp
(defun test-global-hooks ()
  "Test global hooks applied to all requests"
  (format t "~%=== Test 4.4: Global Hooks ===~%~%")

  (let ((request-log nil))

    ;; Set up global hooks
    (setf *global-hooks* (make-hooks))
    (add-hook *global-hooks* :before-request
              (lambda (provider model messages)
                (push (list :request
                           (provider-type provider)
                           model
                           (length messages))
                      request-log)))
    (add-hook *global-hooks* :after-response
              (lambda (provider model response timing)
                (push (list :response
                           (provider-type provider)
                           model
                           timing)
                      request-log)))

    (format t "Making requests without explicit hooks...~%")

    ;; Make requests without passing :hooks parameter
    (complete '((:role "user" :content "Hello"))
              :provider (make-provider :openai :model "gpt-4o-mini")
              :max-tokens 10)

    (complete '((:role "user" :content "Goodbye"))
              :provider (make-provider :anthropic :model "claude-3-5-haiku-20241022")
              :max-tokens 10)

    (format t "~%Request log (newest first):~%")
    (dolist (entry request-log)
      (format t "  ~A~%" entry))

    ;; Verify global hooks were called
    (assert (= (length request-log) 4) nil
            "Should have 4 entries (2 requests + 2 responses)")
    (assert (some (lambda (e) (eq (first e) :request)) request-log))
    (assert (some (lambda (e) (eq (first e) :response)) request-log))

    ;; Clean up
    (setf *global-hooks* nil)

    (format t "~%✓ Test 4.4 PASSED~%")))

;; Run the test
(test-global-hooks)
```

**Expected Output**:
```
=== Test 4.4: Global Hooks ===

Making requests without explicit hooks...

Request log (newest first):
  (:RESPONSE ANTHROPIC claude-3-5-haiku-20241022 0.52)
  (:REQUEST ANTHROPIC claude-3-5-haiku-20241022 1)
  (:RESPONSE OPENAI gpt-4o-mini 0.38)
  (:REQUEST OPENAI gpt-4o-mini 1)

✓ Test 4.4 PASSED
```

**What to Verify**:
- ✅ Global hooks apply to all requests without explicit `:hooks` parameter
- ✅ Both OpenAI and Anthropic requests are tracked
- ✅ Request and response hooks both fire
- ✅ Setting `*global-hooks*` to nil disables global hooks

---

## Test Group 5: Integration Tests

### Test 5.1: Streaming with Hooks and Cost Tracking

**Purpose**: Test all Phase 1 features together in a realistic scenario.

**Code**:
```lisp
(defun test-full-integration ()
  "Test streaming + hooks + cost estimation together"
  (format t "~%=== Test 5.1: Full Integration ===~%~%")

  (let* ((messages '((:role "user" :content "Count from 1 to 5")))
         (provider (make-provider :openai :model "gpt-4o-mini"))
         (max-tokens 50)
         (hooks (make-logging-hooks :level :info))
         (chunk-count 0)
         (start-time (get-internal-real-time)))

    ;; 1. Estimate cost before request
    (format t "STEP 1: Cost Estimation~%")
    (multiple-value-bind (input-cost output-cost total)
        (estimate-cost messages
                      :provider provider
                      :model "gpt-4o-mini"
                      :max-tokens max-tokens)
      (format t "  Estimated cost: ~A~%" (format-cost total))
      (format t "  Input: ~D tokens = ~A~%"
              (count-tokens messages)
              (format-cost input-cost))
      (format t "  Output: ~D tokens (max) = ~A~%~%"
              max-tokens
              (format-cost output-cost)))

    ;; 2. Stream with hooks
    (format t "STEP 2: Streaming Request with Hooks~%")
    (let ((stream (complete-stream messages
                                   :provider provider
                                   :max-tokens max-tokens
                                   :hooks hooks
                                   :on-chunk (lambda (chunk)
                                               (incf chunk-count)
                                               (format t "~A" (chunk-delta chunk)))
                                   :on-complete (lambda (content final-chunk)
                                                  (declare (ignore content final-chunk))
                                                  (format t "~%  Stream complete!~%")))))

      (let ((elapsed (/ (- (get-internal-real-time) start-time)
                       internal-time-units-per-second)))
        (format t "~%STEP 3: Results~%")
        (format t "  Chunks received: ~D~%" chunk-count)
        (format t "  Total elapsed: ~,2Fs~%" elapsed)
        (format t "  Final content: ~S~%~%" (stream-accumulated-content stream))

        ;; Verify
        (assert (> chunk-count 0) nil "Should receive chunks")
        (assert (> (length (stream-accumulated-content stream)) 0) nil "Should have content")
        (assert (eq (stream-state stream) :closed) nil "Stream should be closed")))

    (format t "✓ Test 5.1 PASSED - All Phase 1 features working together~%")))

;; Run the test
(test-full-integration)
```

**Expected Output**:
```
=== Test 5.1: Full Integration ===

STEP 1: Cost Estimation
  Estimated cost: $0.0001
  Input: 8 tokens = $0.0000
  Output: 50 tokens (max) = $0.0001

STEP 2: Streaming Request with Hooks
[14:30:15] LLM Request: OPENAI gpt-4o-mini (1 messages)
1
2
3
4
5
  Stream complete!
[14:30:16] LLM Response: 0.52s, 15 tokens

STEP 3: Results
  Chunks received: 7
  Total elapsed: 0.53s
  Final content: "1\n2\n3\n4\n5"

✓ Test 5.1 PASSED - All Phase 1 features working together
```

**What to Verify**:
- ✅ Cost is estimated before request
- ✅ Streaming works with hooks enabled
- ✅ Hooks log request and response
- ✅ Chunks stream in real-time
- ✅ All features work together without interference

---

## Troubleshooting

### Common Issues

#### Issue 1: "Package ANTHROPIC_API_KEY does not exist"
**Symptom**: Error when trying to use provider
**Solution**: Set environment variable before starting SBCL:
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
sbcl
```

#### Issue 2: Streaming hangs/freezes
**Symptom**: `read-stream-chunk` never returns
**Possible Causes**:
- Network timeout
- Invalid stream format
- Server not responding

**Debug**:
```lisp
;; Add timeout to streaming
(read-stream-chunk stream :timeout 5)  ; 5 second timeout
```

#### Issue 3: Token counts seem off
**Symptom**: Estimates are 20%+ off from actual
**Explanation**: Character-based estimation is approximate. Accuracy varies by:
- Language (non-English text has different ratios)
- Content type (code vs prose)
- Special tokens (not counted in character-based approach)

**Solution**: This is expected behavior for Phase 1. More accurate counting requires provider-specific tokenizers (planned for later).

#### Issue 4: Hooks not firing
**Symptom**: Hook functions not called
**Checklist**:
- ✅ Did you pass `:hooks` parameter to `complete` or `complete-stream`?
- ✅ Did you add hooks with `add-hook` before calling?
- ✅ Is `*global-hooks*` set if not using explicit hooks?

**Debug**:
```lisp
;; Verify hooks were added
(let ((hooks (make-hooks)))
  (add-hook hooks :before-request (lambda (&rest args) (format t "CALLED~%")))
  (format t "Before-request hooks: ~A~%" (cl-llm-provider::hooks-before-request hooks)))
```

#### Issue 5: "HTTP request failed with status 429"
**Symptom**: Rate limit error
**Solution**: You're making too many requests. Wait 60 seconds and retry, or use Phase 2's retry logic (when implemented).

---

## Success Criteria

Phase 1 manual testing is complete when:

- ✅ **Streaming**: Both OpenAI and Anthropic streaming work, chunks arrive incrementally
- ✅ **Token Counting**: Estimates are within 20% of actual usage
- ✅ **Cost Estimation**: Costs calculated correctly for different models
- ✅ **Observability**: Hooks fire at correct lifecycle points, logging works
- ✅ **Integration**: All features work together without errors

---

## Next Steps

After completing Phase 1 manual testing:

1. **Report Issues**: Document any bugs or unexpected behavior
2. **Performance Notes**: Record any performance observations (latency, throughput)
3. **API Feedback**: Note any API usability issues or missing features
4. **Phase 2 Planning**: Review Phase 2 features (context management, retry logic, batch API)

---

## Appendix: Quick Test Suite

Run all tests in sequence:

```lisp
(defun run-all-phase1-tests ()
  "Run all Phase 1 manual tests"
  (format t "~%╔══════════════════════════════════════════╗~%")
  (format t "║  Phase 1 Manual Testing Suite          ║~%")
  (format t "╚══════════════════════════════════════════╝~%")

  (handler-case
      (progn
        ;; Streaming tests
        (test-openai-streaming)
        (test-anthropic-streaming)
        (test-streaming-callbacks)
        (test-streaming-error-handling)

        ;; Token counting tests
        (test-token-counting)
        (test-token-accuracy)

        ;; Cost estimation tests
        (test-cost-estimation)
        (test-cost-budget)

        ;; Observability tests
        (test-basic-hooks)
        (test-logging-hooks)
        (test-file-logging)
        (test-global-hooks)

        ;; Integration tests
        (test-full-integration)

        (format t "~%╔══════════════════════════════════════════╗~%")
        (format t "║  ✓ ALL TESTS PASSED                     ║~%")
        (format t "╚══════════════════════════════════════════╝~%"))

    (error (e)
      (format t "~%╔══════════════════════════════════════════╗~%")
      (format t "║  ✗ TEST FAILED                          ║~%")
      (format t "╚══════════════════════════════════════════╝~%")
      (format t "Error: ~A~%" e))))

;; Run all tests
(run-all-phase1-tests)
```

**Total Runtime**: Approximately 5-10 minutes (depending on API latency)
