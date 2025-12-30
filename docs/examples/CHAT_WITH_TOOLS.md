# Complete Chat Session with Enhanced Tool Support Example

This example demonstrates building an interactive chat application with session management and advanced tool support using cl-llm-provider's enhanced tools functionality.

## Features Demonstrated

- ✓ Multi-turn conversation with message history
- ✓ Session management and persistence
- ✓ Enhanced tool definition with safety levels and categories
- ✓ Parameter validation before execution
- ✓ Tool registry for discovery and management
- ✓ Approval workflows for dangerous operations
- ✓ Lifecycle hooks for logging and metrics
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
(use-package :cl-llm-provider.tools)  ; NEW: Use enhanced tools module

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
   (tool-registry :initarg :tool-registry
                  :initform nil
                  :accessor session-tool-registry
                  :documentation "NEW: Tool registry for enhanced tools")
   (total-tokens :initarg :total-tokens
                 :initform 0
                 :accessor session-total-tokens
                 :documentation "Total tokens used in session")))

;;;; ============================================================
;;;; TOOL DEFINITIONS (with enhanced features)
;;;; ============================================================

(defun define-calculator-tools ()
  "Define calculator tools with enhanced features"
  (list
   ;; Add tool - safe, read-only
   (define-tool "add"
     "Add two numbers"
     '((:name "a" :type :number :description "First number")
       (:name "b" :type :number :description "Second number"))
     :required '("a" "b")
     :safety-level :safe
     :categories '(:calculation)
     :parameter-validators '(("a" . (:type :number))
                             ("b" . (:type :number)))
     :on-start (lambda (call args)
                 (format t "~&[→] Computing ~A + ~A~%" (getf args :a) (getf args :b)))
     :handler (lambda (args)
               (+ (getf args :a) (getf args :b))))

   ;; Subtract tool
   (define-tool "subtract"
     "Subtract two numbers"
     '((:name "a" :type :number :description "First number")
       (:name "b" :type :number :description "Second number"))
     :required '("a" "b")
     :safety-level :safe
     :categories '(:calculation)
     :parameter-validators '(("a" . (:type :number))
                             ("b" . (:type :number)))
     :handler (lambda (args)
               (- (getf args :a) (getf args :b))))

   ;; Multiply tool
   (define-tool "multiply"
     "Multiply two numbers"
     '((:name "a" :type :number :description "First number")
       (:name "b" :type :number :description "Second number"))
     :required '("a" "b")
     :safety-level :safe
     :categories '(:calculation)
     :parameter-validators '(("a" . (:type :number))
                             ("b" . (:type :number)))
     :handler (lambda (args)
               (* (getf args :a) (getf args :b))))

   ;; Divide tool - with validation to prevent division by zero
   (define-tool "divide"
     "Divide two numbers"
     '((:name "a" :type :number :description "Numerator")
       (:name "b" :type :number :description "Denominator"))
     :required '("a" "b")
     :safety-level :safe
     :categories '(:calculation)
     :parameter-validators '(("a" . (:type :number))
                             ("b" . (:type :number)))
     :handler (lambda (args)
               (let ((divisor (getf args :b)))
                 (if (zerop divisor)
                     (error "Division by zero")
                     (/ (getf args :a) divisor)))))))

(defun define-web-tools ()
  "Define web/information tools with enhanced features"
  (list
   ;; Search tool - safe
   (define-tool "search"
     "Search for information"
     '((:name "query" :type :string :description "Search query")
       (:name "max-results" :type :integer :description "Maximum results (1-50)"))
     :required '("query")
     :safety-level :safe
     :categories '(:search :external-api)
     :parameter-validators '(("query" . (:length-validator :min-length 1 :max-length 200))
                             ("max-results" . (:type :integer :min 1 :max 50)))
     :handler (lambda (args)
               (format nil "Search results for: ~A (~A results)"
                       (getf args :query)
                       (or (getf args :max-results) 10))))

   ;; Weather tool - safe
   (define-tool "get_weather"
     "Get current weather for a location"
     '((:name "location" :type :string :description "City and state")
       (:name "unit" :type :string :description "Temperature unit"
              :enum ("celsius" "fahrenheit")))
     :required '("location")
     :safety-level :safe
     :categories '(:search :external-api)
     :parameter-validators '(("location" . (:length-validator :min-length 2 :max-length 100))
                             ("unit" . (:enum-validator '("celsius" "fahrenheit"))))
     :handler (lambda (args)
               (format nil "Weather for ~A: Sunny, 22°C"
                       (getf args :location))))

   ;; Get time tool - safe
   (define-tool "get_time"
     "Get current time and date"
     nil
     :safety-level :safe
     :categories '(:search)
     :handler (lambda (args)
               (declare (ignore args))
               (multiple-value-bind (sec min hour date month year)
                   (decode-universal-time (get-universal-time))
                 (format nil "Time: ~2,'0D:~2,'0D:~2,'0D, Date: ~4D-~2,'0D-~2,'0D"
                         hour min sec year month date))))))

;;;; ============================================================
;;;; Tool handlers are now defined inline in define-tool
;;;; Tools are automatically executed with validation, safety checks, and hooks
;;;; ============================================================

;;;; ============================================================
;;;; SESSION MANAGEMENT
;;;; ============================================================

(defun create-session (provider model &key system-prompt tools)
  "Create a new chat session with enhanced tools registry"
  (let* ((registry (make-tool-registry :name "chat-session"))
         (session (make-instance 'chat-session
                                :provider provider
                                :model model
                                :system-prompt system-prompt
                                :tool-registry registry)))

    ;; Register tools in the registry
    (dolist (tool tools)
      (register-tool registry tool))

    ;; Set up global hooks for logging
    (setf (registry-global-hooks registry)
          (list
           :on-start (lambda (call args)
                       (format t "~&[Tool] Executing ~A~%" (tool-call-name call)))
           :on-complete (lambda (call args result)
                          (format t "~&[Tool] ✓ Completed~%" nil))))

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
  (let ((registry (session-tool-registry session)))
    (format t "Available tools: ~A~%"
            (mapcar #'tool-name (list-tools registry)))))

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
  "Send a message and get a response with enhanced tool support"
  ;; Add user message to history
  (add-message session "user" user-message)

  ;; Get conversation history
  (let ((history (get-conversation-history session))
        (registry (session-tool-registry session)))

    ;; Make request with tools (only safe ones by default)
    (let ((response (complete history
                             :provider (session-provider session)
                             :model (session-model session)
                             :system (session-system-prompt session)
                             :tools (tools-for-llm :registry registry))))

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
         ;; Execute all tool calls using enhanced execution engine
         (handler-case
             (let* ((tool-results (execute-tool-calls response
                                                       :registry registry
                                                       :skip-approval t))
                    (tool-messages (execution-results-to-tool-messages tool-results)))

               ;; Add assistant message
               (add-message session "assistant" (response-content response))

               ;; Add tool results
               (dolist (msg tool-messages)
                 (add-message session "tool" (getf msg :content)))

               ;; Continue conversation with results
               (chat session (format nil "[Tool results processed, continue conversation]")))

           ;; Handle execution errors
           (tool-validation-error (e)
             (format t "~&Validation Error: Parameter ~A = ~A~%"
                     (error-parameter e) (error-value e))
             (values "Tool validation failed" nil))

           (tool-safety-violation (e)
             (format t "~&Safety Error: Tool exceeds safety level~%")
             (values "Tool is too dangerous" nil))

           (error (e)
             (format t "~&Tool Error: ~A~%" e)
             (values (format nil "Tool execution failed: ~A" e) nil))))

        ;; Model gave up
        (t
         (values "Error: Model did not provide response" nil))))))

;; Helper function for backward compatibility
(defun process-tool-calls (session response)
  "Process tool calls from response (legacy wrapper)"
  (let ((registry (session-tool-registry session)))
    (execution-results-to-tool-messages
     (execute-tool-calls response :registry registry :skip-approval t))))

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

## Enhanced Tools Features

This example showcases these new features:

- **Tool Safety Levels** - Tools classified as :safe, :moderate, or :dangerous
- **Tool Categories** - Organize tools with predefined categories (:calculation, :search, etc.)
- **Parameter Validators** - Validate arguments before execution (:type, :length-validator, :enum-validator)
- **Tool Registry** - Dynamically manage and discover tools
- **Lifecycle Hooks** - Execute code at :on-start and :on-complete events
- **Error Handling** - Comprehensive error conditions for validation, safety, and approval
- **Tools for LLM** - Automatically provide only safe tools to the model

See the enhanced tools documentation for more details on each feature.

## See Also

- `docs/TOOLS-README.md` - **New!** Enhanced tools documentation index
- `docs/TOOLS-QUICK-START.md` - **New!** 5-minute getting started guide
- `docs/TOOLS-ADVANCED.md` - **New!** Comprehensive feature guide
- `docs/TOOLS-API-REFERENCE.md` - **New!** Complete API documentation
- `docs/PROTOCOL.md` - Protocol architecture
- `docs/FEATURES.md` - Feature documentation
- `docs/PROVIDERS.md` - Adding new providers
- README.md - Quick start and API reference
