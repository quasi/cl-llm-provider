# How-To: Testing Tools and Providers

Write tests for tools, providers, and completions.

**Prerequisites**: Familiarity with [FiveAM testing framework](https://fiveam.common-lisp.dev/).

---

## Test Structure

Tests are organized by functionality:

```
tests/
├── test-provider-protocols.lisp       # Provider protocol tests
├── test-request-response-handling.lisp # Message formatting tests
├── test-token-metadata-comprehensive.lisp # Token counting tests
├── test-tools-support.lisp            # Tool calling tests
└── test-integration-full-flow.lisp    # End-to-end tests
```

Run all tests:

```bash
sbcl --noinform --non-interactive --load tests/test-tools-support.lisp
```

## Testing Tools

### 1. Tool Definition Tests

Verify tools are defined correctly:

```lisp
(in-package :cl-llm-provider-tests)

(def-suite tool-definition-tests)
(in-suite tool-definition-tests)

;; Test basic definition
(test define-tool-basic
  "Test basic tool definition"
  (define-tool "search"
    "Search the internet"
    '((:name "query" :type :string))
    :required '("query")
    :handler (lambda (args) "results"))

  ;; Verify tool was created
  (let ((tool (get-tool "search")))
    (is (not (null tool)))
    (is (string= (tool-name tool) "search"))
    (is (string= (tool-description tool) "Search the internet"))))

;; Test tool parameters
(test tool-parameters
  "Test parameter definitions"
  (define-tool "api-call"
    "Call an API"
    '((:name "endpoint" :type :string)
      (:name "limit" :type :integer))
    :required '("endpoint")
    :handler (lambda (args) "{}"))

  (let ((tool (get-tool "api-call")))
    (let ((params (tool-parameters tool)))
      (is (= (length params) 2))
      (is (string= (getf (first params) :name) "endpoint")))))

;; Test tool metadata
(test tool-metadata
  "Test tool metadata"
  (define-tool "query"
    "Query database"
    '((:name "sql" :type :string))
    :required '("sql")
    :safety-level :moderate
    :categories '(:database :search)
    :metadata '(:api-cost 0.001)
    :handler (lambda (args) "{}"))

  (let ((tool (get-tool "query")))
    (is (eq (tool-safety-level tool) :moderate))
    (is (member :database (tool-categories tool)))
    (is (= (getf (tool-metadata tool) :api-cost) 0.001))))
```

### 2. Tool Execution Tests

Test that tools execute correctly:

```lisp
;; Test simple execution
(test tool-execution-basic
  "Test basic tool execution"
  (define-tool "add"
    "Add two numbers"
    '((:name "a" :type :number)
      (:name "b" :type :number))
    :required '("a" "b")
    :handler (lambda (args)
             (+ (getf args :a) (getf args :b))))

  (let ((result (execute-tool "add" (list :a 5 :b 3))))
    (is (= result 8))))

;; Test error handling in tools
(test tool-execution-error-handling
  "Test tool error handling"
  (define-tool "risky"
    "A risky operation"
    '((:name "force" :type :boolean))
    :required '()
    :handler (lambda (args)
             (if (getf args :force)
               (error "Forced error")
               "success")))

  ;; Successful execution
  (let ((result (execute-tool "risky" (list :force nil))))
    (is (string= result "success")))

  ;; Error execution
  (signals error
    (execute-tool "risky" (list :force t))))

;; Test parameter validation
(test tool-validation
  "Test parameter validation"
  (define-tool "delete"
    "Delete something"
    '((:name "path" :type :string))
    :required '("path")
    :parameter-validators '(
      ("path" . (:pattern "^/tmp/")))
    :handler (lambda (args) "deleted"))

  ;; Valid path
  (let ((result (execute-tool "delete" (list :path "/tmp/file"))))
    (is (string= result "deleted")))

  ;; Invalid path
  (signals validation-error
    (execute-tool "delete" (list :path "/home/user/file"))))
```

### 3. Tool Calling in Completions

Test that tool calls work end-to-end:

```lisp
(test tool-calling-in-completion
  "Test LLM requesting tool calls"
  ;; Define a tool
  (define-tool "weather"
    "Get weather"
    '((:name "city" :type :string))
    :required '("city")
    :handler (lambda (args)
             (format nil "Weather in ~A: sunny" (getf args :city))))

  ;; Mock API response with tool calls
  (let ((response (mock-completion-with-tools
                  '((:role "user" :content "What's the weather in Paris?"))
                  (list (get-tool "weather")))))

    ;; Verify tool was called
    (is (response-tool-calls response))
    (let ((tool-call (first (response-tool-calls response))))
      (is (string= (getf tool-call :name) "weather"))
      (is (string= (getf (getf tool-call :arguments) :city) "Paris")))))
```

## Testing Providers

### 1. Provider Initialization

```lisp
(test provider-creation
  "Test creating provider instances"
  ;; Anthropic
  (let ((provider (make-provider :anthropic)))
    (is (typep provider 'anthropic-provider)))

  ;; OpenAI
  (let ((provider (make-provider :openai :model "gpt-4")))
    (is (typep provider 'openai-provider))
    (is (string= (provider-default-model provider) "gpt-4"))))

(test provider-api-key
  "Test provider API key handling"
  (let ((provider (make-provider :anthropic
                               :api-key "sk-test-123")))
    (is (string= (provider-api-key provider) "sk-test-123"))))
```

### 2. Message Normalization

```lisp
(test provider-message-normalization
  "Test message format conversion"
  (let ((messages '((:role "user" :content "Hello")
                   (:role "assistant" :content "Hi there"))))

    ;; Anthropic format
    (let ((norm (normalize-messages-for-provider messages :anthropic)))
      (is (string= (getf (first norm) :role) "user")))

    ;; OpenAI format
    (let ((norm (normalize-messages-for-provider messages :openai)))
      (is (string= (getf (first norm) :role) "user")))))
```

### 3. Response Parsing

```lisp
(test provider-response-parsing
  "Test parsing provider responses"
  ;; Mock response from Anthropic
  (let ((http-response "{\"id\":\"msg_123\",\"content\":[{\"type\":\"text\",\"text\":\"Hello\"}]}")
        (provider (make-provider :anthropic)))

    (let ((response (parse-anthropic-response http-response)))
      (is (string= (response-id response) "msg_123"))
      (is (string= (response-content response) "Hello"))
      (is (eq (response-provider response) :anthropic)))))
```

## Mocking External Services

For testing without API calls:

### 1. Mock HTTP Responses

```lisp
(defmacro with-mock-api (bindings &body body)
  "Execute code with mocked API responses."
  `(let ((dexador:*mock-responses* (list ,@bindings)))
     ,@body))

(test completion-with-mock
  "Test completion using mock API"
  (with-mock-api
    (("https://api.anthropic.com/v1/messages"
      (list
       :status 200
       :body "{\"id\":\"msg_123\",\"content\":[{\"type\":\"text\",\"text\":\"Hello\"}]}")))

    (let ((response (complete '((:role "user" :content "Hi")))))
      (is (string= (response-content response) "Hello")))))
```

### 2. Stub Tool Execution

```lisp
(defun stub-tool-execution (tool-name result)
  "Stub a tool to always return a specific result."
  (let ((tool (get-tool tool-name)))
    (setf (tool-handler tool)
         (lambda (args) result))))

(test stubbed-tool-call
  "Test with stubbed tools"
  (define-tool "search" "Search" '() :handler (lambda (args) ""))
  (stub-tool-execution "search" "Results from search")

  (let ((result (execute-tool "search" '())))
    (is (string= result "Results from search"))))
```

## Testing Error Handling

### 1. Error Conditions

```lisp
(test api-error-handling
  "Test handling of API errors"

  ;; Rate limiting
  (signals rate-limit-error
    (with-mock-api
      (("https://api.example.com/v1/completions"
        (list :status 429 :body "{\"error\":\"rate limited\"}")))
      (complete messages)))

  ;; Authentication
  (signals authentication-error
    (with-mock-api
      (("https://api.example.com/v1/completions"
        (list :status 401 :body "{\"error\":\"unauthorized\"}")))
      (complete messages)))

  ;; Network error
  (signals network-error
    (with-mock-api
      (("https://api.example.com/v1/completions"
        (list :status 500 :body "{\"error\":\"server error\"}")))
      (complete messages))))

(test retry-on-transient-error
  "Test automatic retry logic"
  (let ((attempt-count 0))
    (handler-bind
      ((rate-limit-error (lambda (e)
                         (incf attempt-count)
                         (if (< attempt-count 3)
                           (invoke-restart 'retry)
                           nil))))
      (signals rate-limit-error
        (complete-with-retry messages :max-retries 2)))))
```

### 2. Graceful Degradation

```lisp
(test fallback-provider
  "Test falling back to alternative provider"
  (let ((calls '()))
    (flet ((mock-complete (msg provider)
            (push provider calls)
            (if (eq provider :anthropic)
              (error 'network-error)
              (make-instance 'completion-response
                            :content "Success"))))

      ;; Try primary, fall back to secondary
      (let ((response (complete-with-fallback
                      messages
                      :primary :anthropic
                      :fallback :openai)))
        (is (string= (response-content response) "Success"))
        (is (member :openai calls))))))
```

## Integration Tests

Full end-to-end workflows:

```lisp
(test full-chat-workflow
  "Test complete chat session with tools"
  (define-tool "search" "Search" '(:name "q" :type :string)
    :handler (lambda (args) "Search results"))

  ;; Turn 1: user asks question
  (let ((r1 (mock-complete
            '((:role "user" :content "Search for Lisp"))
            (list (get-tool "search")))))

    ;; Turn 2: respond to tool result
    (let ((r2 (mock-complete
              (list (list :role "user" :content "Search for Lisp")
                    (response-message r1)
                    (list :role "user" :content "Here are results: ..."))
              (list (get-tool "search")))))

      ;; Verify conversation history
      (is (= (length (mock-conversation-history)) 6)))))  ; 3 turns × 2 messages
```

## Performance Tests

Test performance and resource usage:

```lisp
(test token-counting-performance
  "Test token counting speed"
  (let* ((large-text (make-string 10000 :initial-element #\a))
         (start-time (get-internal-real-time))
         (tokens (token-count large-text))
         (elapsed (- (get-internal-real-time) start-time)))

    ;; Should count 10k chars in < 100ms
    (is (< (/ elapsed internal-time-units-per-second) 0.1))
    (is (> tokens 0))))

(test completion-latency
  "Test API latency tracking"
  (let ((response (complete messages :enable-profiling t)))
    (let ((prof (response-profiling response)))
      ;; Should have timing data
      (is (getf prof :api-time))
      (is (getf prof :encode-time))
      (is (getf prof :decode-time)))))
```

## Running Tests

```bash
# Run all tests
sbcl --noinform --non-interactive --load tests/run-all-tests.lisp

# Run specific test suite
sbcl --noinform --non-interactive --load tests/test-tools-support.lisp

# Run with coverage
sbcl --noinform --non-interactive --load tests/run-with-coverage.lisp
```

## Test Best Practices

1. **Test behavior, not implementation** - Test what tools do, not how
2. **Mock external services** - Don't make real API calls in tests
3. **Test error cases** - Include tests for failure modes
4. **Use fixtures** - Define common test data once
5. **Keep tests isolated** - Each test should be independent
6. **Test at multiple levels** - Unit, integration, and end-to-end

---

**See Also**:
- [How-To: Advanced Tools](tools.md)
- [Tutorial: Tool Calling](../tutorials/02-tool-calling.md)
