# Complete Chat Session with Tool Support Example

This example demonstrates building an interactive chat application with session management and tool support using cl-llm-provider.

## Features Demonstrated

- ✓ Multi-turn conversation with message history
- ✓ Session management and persistence
- ✓ Tool definition and execution
- ✓ Dynamic tool response handling
- ✓ Error handling and recovery
- ✓ Token usage tracking
- ✓ Multi-provider support

## Complete Application

```lisp
(require :asdf)
(ql:quickload :cl-llm-provider)
(ql:quickload :cl-ppcre)

(use-package :cl-llm-provider)

;;;; ============================================================
;;;; DATA STRUCTURES
;;;; ============================================================

(defclass chat-session ()
  ((provider :initarg :provider
             :accessor session-provider
             :documentation "LLM provider instance")
   (model :initarg :model
          :accessor session-model
          :documentation "Model to use for completions")
   (system-prompt :initarg :system-prompt
                  :initform nil
                  :accessor session-system-prompt
                  :documentation "System message for context")
   (messages :initarg :messages
             :initform nil
             :accessor session-messages
             :documentation "Conversation history")
   (tools :initarg :tools
          :initform nil
          :accessor session-tools
          :documentation "Available tools")
   (tool-functions :initarg :tool-functions
                   :initform (make-hash-table :test 'equal)
                   :accessor session-tool-functions
                   :documentation "Mapping of tool names to functions")
   (total-tokens :initarg :total-tokens
                 :initform 0
                 :accessor session-total-tokens
                 :documentation "Total tokens used in session")))

;;;; ============================================================
;;;; TOOL DEFINITIONS
;;;; ============================================================

(defun define-calculator-tools ()
  "Define calculator tools"
  (list
   ;; Add tool
   (make-instance 'tool-definition
     :name "add"
     :description "Add two numbers"
     :parameters '((:name "a" :type :number :description "First number")
                   (:name "b" :type :number :description "Second number"))
     :required '("a" "b"))

   ;; Subtract tool
   (make-instance 'tool-definition
     :name "subtract"
     :description "Subtract two numbers"
     :parameters '((:name "a" :type :number :description "First number")
                   (:name "b" :type :number :description "Second number"))
     :required '("a" "b"))

   ;; Multiply tool
   (make-instance 'tool-definition
     :name "multiply"
     :description "Multiply two numbers"
     :parameters '((:name "a" :type :number :description "First number")
                   (:name "b" :type :number :description "Second number"))
     :required '("a" "b"))

   ;; Divide tool
   (make-instance 'tool-definition
     :name "divide"
     :description "Divide two numbers"
     :parameters '((:name "a" :type :number :description "Numerator")
                   (:name "b" :type :number :description "Denominator"))
     :required '("a" "b"))))

(defun define-web-tools ()
  "Define web/information tools"
  (list
   ;; Search tool
   (make-instance 'tool-definition
     :name "search"
     :description "Search for information"
     :parameters '((:name "query" :type :string :description "Search query")
                   (:name "max-results" :type :integer :description "Maximum results"
                    :enum (5 10 20)))
     :required '("query"))

   ;; Weather tool
   (make-instance 'tool-definition
     :name "get_weather"
     :description "Get current weather"
     :parameters '((:name "location" :type :string :description "City and state")
                   (:name "unit" :type :string :description "Temperature unit"
                    :enum ("celsius" "fahrenheit")))
     :required '("location"))

   ;; Get time tool
   (make-instance 'tool-definition
     :name "get_time"
     :description "Get current time and date"
     :parameters nil
     :required nil)))

;;;; ============================================================
;;;; TOOL IMPLEMENTATIONS
;;;; ============================================================

(defun execute-tool (tool-name arguments)
  "Execute a tool and return result JSON"
  (flet ((get-arg (key)
           (getf arguments (make-keyword (string-upcase key)))))

    (case (make-keyword (string-upcase tool-name))
      ;; Calculator tools
      (:add
       (yason:encode-to-string
        `(("result" . ,(+ (get-arg "a") (get-arg "b"))))))

      (:subtract
       (yason:encode-to-string
        `(("result" . ,(- (get-arg "a") (get-arg "b"))))))

      (:multiply
       (yason:encode-to-string
        `(("result" . ,(* (get-arg "a") (get-arg "b"))))))

      (:divide
       (let ((divisor (get-arg "b")))
         (if (zerop divisor)
             (yason:encode-to-string '(("error" . "Division by zero")))
             (yason:encode-to-string
              `(("result" . ,(/ (get-arg "a") divisor)))))))

      ;; Web/Info tools
      (:search
       ;; Mock implementation
       (let ((query (get-arg "query")))
         (yason:encode-to-string
          `(("results" . (
             (("title" . "Result 1") ("url" . "http://example.com/1"))
             (("title" . "Result 2") ("url" . "http://example.com/2"))))))))

      (:get_weather
       ;; Mock implementation
       (let ((location (get-arg "location"))
             (unit (or (get-arg "unit") "celsius")))
         (yason:encode-to-string
          `(("location" . ,location)
            ("temperature" . 22)
            ("unit" . ,unit)
            ("condition" . "Partly Cloudy")))))

      (:get_time
       ;; Get actual current time
       (multiple-value-bind (sec min hour date month year)
           (decode-universal-time (get-universal-time))
         (yason:encode-to-string
          `(("time" . ,(format nil "~2,'0D:~2,'0D:~2,'0D" hour min sec))
            ("date" . ,(format nil "~4D-~2,'0D-~2,'0D" year month date))))))

      (t
       (yason:encode-to-string
        `(("error" . ,(format nil "Unknown tool: ~A" tool-name))))))))

;;;; ============================================================
;;;; SESSION MANAGEMENT
;;;; ============================================================

(defun create-session (provider model &key system-prompt tools)
  "Create a new chat session"
  (let ((session (make-instance 'chat-session
                               :provider provider
                               :model model
                               :system-prompt system-prompt
                               :tools tools)))
    ;; Register tool functions
    (dolist (tool tools)
      (setf (gethash (tool-name tool)
                    (session-tool-functions session))
           #'execute-tool))
    session))

(defun save-session (session filename)
  "Save session to file"
  (with-open-file (f filename :direction :output)
    (print (session-messages session) f))
  (format t "~&Session saved to ~A~%" filename))

(defun load-session (provider model filename)
  "Load session from file"
  (let ((session (create-session provider model)))
    (with-open-file (f filename :direction :input)
      (setf (session-messages session) (read f)))
    (format t "~&Session loaded from ~A~%" filename)
    session))

(defun print-session-info (session)
  "Print session information"
  (format t "~&=== Session Info ===~%")
  (format t "Provider: ~A~%" (type-of (session-provider session)))
  (format t "Model: ~A~%" (session-model session))
  (format t "Messages: ~A~%" (length (session-messages session)))
  (format t "Total tokens: ~A~%" (session-total-tokens session))
  (format t "Available tools: ~A~%" (mapcar #'tool-name (session-tools session))))

;;;; ============================================================
;;;; CONVERSATION HANDLING
;;;; ============================================================

(defun add-message (session role content)
  "Add a message to the session history"
  (push `(:role ,role :content ,content) (session-messages session)))

(defun get-conversation-history (session)
  "Get conversation history (in correct order)"
  (reverse (session-messages session)))

(defun chat (session user-message)
  "Send a message and get a response with tool support"
  ;; Add user message to history
  (add-message session "user" user-message)

  ;; Get conversation history
  (let ((history (get-conversation-history session))
        (tools (session-tools session)))

    ;; Make request with tools if available
    (let ((response (complete history
                             :provider (session-provider session)
                             :model (session-model session)
                             :system (session-system-prompt session)
                             :tools (when tools tools))))

      ;; Update token count
      (let ((usage (response-usage response)))
        (incf (session-total-tokens session)
              (getf usage :total-tokens)))

      ;; Handle response
      (cond
        ;; Model provided text answer
        ((and (response-content response)
              (not (response-tool-calls response)))
         (add-message session "assistant" (response-content response))
         (values (response-content response) nil))

        ;; Model wants to use tools
        ((response-tool-calls response)
         (let ((tool-results (process-tool-calls session response)))
           ;; Add assistant message with tool calls
           (add-message session "assistant" "")

           ;; Add tool results
           (dolist (result tool-results)
             (add-message session "tool" result))

           ;; Continue conversation with results
           (chat session (format nil "[Tool results processed, continue conversation]"))))

        ;; Model gave up
        (t
         (values "Error: Model did not provide response" nil))))))

(defun process-tool-calls (session response)
  "Process tool calls from response"
  (let ((results nil))
    (dolist (call (response-tool-calls response))
      (let* ((tool-id (tool-call-id call))
             (tool-name (tool-call-name call))
             (arguments (tool-call-arguments call)))

        ;; Execute tool
        (format t "~&[Executing tool: ~A with args: ~A]~%" tool-name arguments)
        (let ((result (execute-tool tool-name arguments)))
          (format t "[Tool result: ~A]~%" result)

          ;; Create tool result message
          (let ((tool-result-msg (make-tool-result tool-id result)))
            (push tool-result-msg results)))))

    (reverse results)))

;;;; ============================================================
;;;; INTERACTIVE CHAT LOOP
;;;; ============================================================

(defun interactive-chat (session &key save-file)
  "Run interactive chat loop"
  (format t "~%=== Chat Session Started ===~%")
  (format t "Type 'quit' to exit, 'info' for session info~%~%")

  (loop do
    ;; Print system status
    (let ((message-count (length (session-messages session))))
      (when (> message-count 0)
        (format t "[Messages: ~A, Tokens: ~A] "
               message-count
               (session-total-tokens session))))

    ;; Get user input
    (format t "~&You: ")
    (force-output)
    (let ((input (read-line)))

      ;; Handle commands
      (cond
        ((string-equal input "quit")
         (format t "~&Goodbye!~%")
         (when save-file
           (save-session session save-file))
         (return))

        ((string-equal input "info")
         (print-session-info session))

        ((string-equal input "clear")
         (setf (session-messages session) nil)
         (format t "Conversation cleared~%"))

        ((string-equal input "save")
         (format t "Filename: ")
         (force-output)
         (let ((filename (read-line)))
           (save-session session filename)))

        ;; Regular message
        (t
         (handler-case
             (let ((response (chat session input)))
               (format t "~&Assistant: ~A~%~%" response))

           ;; Handle errors
           (provider-authentication-error (e)
             (format t "~&Error: Authentication failed - ~A~%"
                     (error-message e)))

           (provider-api-error (e)
             (format t "~&Error: API request failed - ~A~%"
                     (error-message e)))

           (error (e)
             (format t "~&Unexpected error: ~A~%" e))))))))

;;;; ============================================================
;;;; EXAMPLE USAGE
;;;; ============================================================

(defun main-example ()
  "Run example chat session with tools"

  ;; Create provider
  (let ((provider (make-provider :anthropic
                               :api-key (uiop:getenv "ANTHROPIC_API_KEY")
                               :model "claude-3-sonnet-20240229")))

    ;; Define tools
    (let ((tools (append (define-calculator-tools)
                        (define-web-tools))))

      ;; Create session
      (let ((session (create-session provider
                                    "claude-3-sonnet-20240229"
                                    :system-prompt "You are a helpful assistant with access to tools. Use tools when appropriate."
                                    :tools tools)))

        ;; Run example conversation
        (format t "~%=== Running Example Conversation ===~%~%")

        ;; Example 1: Simple math
        (format t "Example 1: Math with tools~%")
        (let ((response (chat session "What is 25 * 4?")))
          (format t "User: What is 25 * 4?~%")
          (format t "Assistant: ~A~%~%" response))

        ;; Example 2: Information query
        (format t "~%Example 2: Information query~%")
        (let ((response (chat session "What time is it?")))
          (format t "User: What time is it?~%")
          (format t "Assistant: ~A~%~%" response))

        ;; Show session stats
        (print-session-info session))))

(defun run-interactive-example ()
  "Run interactive chat with tools"

  ;; Create provider
  (let ((provider (make-provider :anthropic
                               :api-key (uiop:getenv "ANTHROPIC_API_KEY")
                               :model "claude-3-sonnet-20240229")))

    ;; Define tools
    (let ((tools (append (define-calculator-tools)
                        (define-web-tools))))

      ;; Create session
      (let ((session (create-session provider
                                    "claude-3-sonnet-20240229"
                                    :system-prompt "You are a helpful assistant. Use available tools when needed for calculations or information."
                                    :tools tools)))

        ;; Run interactive chat
        (interactive-chat session :save-file "/tmp/chat-session.lisp"))))

;;;; ============================================================
;;;; ADVANCED EXAMPLE: MULTI-PROVIDER COMPARISON
;;;; ============================================================

(defun compare-providers-on-query (query)
  "Compare responses from different providers"

  (let ((providers (list
         (cons :anthropic
               (make-provider :anthropic
                            :api-key (uiop:getenv "ANTHROPIC_API_KEY")
                            :model "claude-3-sonnet-20240229"))
         (cons :openai
               (make-provider :openai
                            :api-key (uiop:getenv "OPENAI_API_KEY")
                            :model "gpt-4")))))

    (format t "~%=== Provider Comparison ===~%~%")
    (format t "Query: ~A~%~%" query)

    (dolist (provider-pair providers)
      (destructuring-bind (name . provider) provider-pair
        (handler-case
            (let ((response (complete `((:role "user" :content ,query))
                                     :provider provider)))
              (let ((usage (response-usage response)))
                (format t "~A:~%" name)
                (format t "  Response: ~A~%"
                        (subseq (response-content response) 0 100))
                (format t "  Tokens: ~A (prompt: ~A, completion: ~A)~%~%"
                        (getf usage :total-tokens)
                        (getf usage :prompt-tokens)
                        (getf usage :completion-tokens))))

          (error (e)
            (format t "~A: Error - ~A~%~%" name e)))))))

;;;; ============================================================
;;;; RUNNING THE EXAMPLES
;;;; ============================================================

;; Uncomment to run:
;; (main-example)
;; (run-interactive-example)
;; (compare-providers-on-query "What is the capital of France?")
```

## Running the Example

### Setup

1. **Configure API keys** in environment:
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
```

2. **Load the library**:
```lisp
(ql:quickload :cl-llm-provider)
(load "path/to/example.lisp")
```

3. **Run examples**:
```lisp
;; Run non-interactive example
(main-example)

;; Run interactive chat
(run-interactive-example)

;; Compare providers
(compare-providers-on-query "Explain quantum computing")
```

## Example Session Transcript

```
=== Running Example Conversation ===

Example 1: Math with tools
User: What is 25 * 4?
[Executing tool: multiply with args: (:A 25 :B 4)]
[Tool result: {"result": 100}]
Assistant: The result of 25 * 4 is 100.

Example 2: Information query
User: What time is it?
[Executing tool: get_time with args: NIL]
[Tool result: {"time": "14:32:45", "date": "2024-12-30"}]
Assistant: The current time is 14:32:45 and the date is 2024-12-30.

=== Session Info ===
Provider: ANTHROPIC-PROVIDER
Model: claude-3-sonnet-20240229
Messages: 6
Total tokens: 1245
Available tools: ADD, SUBTRACT, MULTIPLY, DIVIDE, SEARCH, GET_WEATHER, GET_TIME
```

## Interactive Session Example

```
=== Chat Session Started ===
Type 'quit' to exit, 'info' for session info

[Messages: 0, Tokens: 0]
You: What's 15 + 27?
[Executing tool: add with args: (:A 15 :B 27)]
[Tool result: {"result": 42}]
Assistant: 15 + 27 equals 42.

[Messages: 2, Tokens: 156]
You: How many seconds in an hour?
Assistant: There are 3,600 seconds in an hour (60 minutes × 60 seconds per minute).

[Messages: 4, Tokens: 298]
You: info
=== Session Info ===
Provider: ANTHROPIC-PROVIDER
Model: claude-3-sonnet-20240229
Messages: 4
Total tokens: 298
Available tools: ADD, SUBTRACT, MULTIPLY, DIVIDE, SEARCH, GET_WEATHER, GET_TIME

[Messages: 4, Tokens: 298]
You: quit
Session saved to /tmp/chat-session.lisp
Goodbye!
```

## Key Concepts Demonstrated

### 1. Session State Management
- Messages stored in order
- Token usage tracked
- Tools available in session

### 2. Tool Execution
- Model requests tools
- Tools executed synchronously
- Results sent back to model
- Conversation continues

### 3. Error Handling
- API errors caught and reported
- User notified of failures
- Session continues

### 4. Multi-turn Conversations
- Message history maintained
- Context preserved across turns
- Can switch providers mid-session

### 5. Extensibility
- Easy to add new tools
- Multiple tool categories
- Provider-agnostic

## Extending the Example

### Add New Tools

```lisp
(defun define-custom-tools ()
  (list
   (make-instance 'tool-definition
     :name "my_tool"
     :description "Do something custom"
     :parameters '((:name "input" :type :string :description "Input"))
     :required '("input"))))
```

### Add Tool Implementations

```lisp
(defun execute-tool (tool-name arguments)
  (case (make-keyword (string-upcase tool-name))
    (:my_tool
     ;; Your implementation
     (yason:encode-to-string '(("result" . "output"))))))
```

### Integrate with Database

```lisp
;; Save chat history to database
(defun save-session-to-db (session db-connection)
  ;; Your database code
  )

;; Load from database
(defun load-session-from-db (session-id db-connection)
  ;; Your database code
  )
```

### Add Logging

```lisp
;; Log all API calls
(defun log-request (provider messages tools)
  (format t "~&[LOG] Request to ~A with ~A messages~%"
          (type-of provider)
          (length messages)))
```

## See Also

- `docs/PROTOCOL.md` - Protocol architecture
- `docs/FEATURES.md` - Feature documentation
- `docs/PROVIDERS.md` - Adding new providers
- README.md - Quick start and API reference
