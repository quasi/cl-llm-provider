;;; ABOUTME: Complete chat session with enhanced tool support
;;; A runnable example demonstrating interactive chat with safety levels,
;;; categories, validators, registry, hooks, and execution lifecycle.
;;; Load this file and run (interactive-chat-example) to start experimenting.

;;;; ============================================================
;;;; SETUP
;;;; ============================================================

(require :asdf)
(ql:quickload :cl-llm-provider :silent t)
(ql:quickload :cl-ppcre :silent t)

(use-package :cl-llm-provider)
(use-package :cl-llm-provider.tools)

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
                  :documentation "Tool registry for enhanced tools")
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
                          (format t "~&[Tool] ✓ Completed~%"))))

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

;;;; ============================================================
;;;; INTERACTIVE CHAT LOOP
;;;; ============================================================

(defun interactive-chat (session &key save-file)
  "Run interactive chat loop"
  (format t "~%=== Chat Session Started ===~%")
  (format t "Type 'quit' to exit, 'info' for session info, 'clear' to clear history~%~%")

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
;;;; EXAMPLE FUNCTIONS
;;;; ============================================================

(defun create-example-session ()
  "Create a session with example tools and provider"
  (let ((provider (make-provider :anthropic
                               :api-key (or (uiop:getenv "ANTHROPIC_API_KEY")
                                           (error "Please set ANTHROPIC_API_KEY environment variable"))
                               :model "claude-3-5-sonnet-20241022")))
    (let ((tools (append (define-calculator-tools)
                        (define-web-tools))))
      (create-session provider
                     "claude-3-5-sonnet-20241022"
                     :system-prompt "You are a helpful assistant with access to tools. Use tools when appropriate to help the user. For calculations, always use the calculator tools."
                     :tools tools))))

(defun simple-chat-example ()
  "Run a simple non-interactive chat example"
  (format t "~%=== Simple Chat Example ===~%~%")

  (let ((session (create-example-session)))
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
    (print-session-info session)))

(defun interactive-chat-example ()
  "Run interactive chat with tools - the main entry point"
  (let ((session (create-example-session)))
    (interactive-chat session :save-file "/tmp/chat-session.lisp")))

;;;; ============================================================
;;;; RUNNING THE EXAMPLES
;;;; ============================================================

(format t "~%╔════════════════════════════════════════════════════════╗~%")
(format t "║  Chat with Enhanced Tools Example - Loaded!             ║~%")
(format t "╚════════════════════════════════════════════════════════╝~%~%")

(format t "Usage:~%")
(format t "  (simple-chat-example)      - Run a non-interactive example~%")
(format t "  (interactive-chat-example) - Run interactive chat~%~%")

(format t "Features demonstrated:~%")
(format t "  ✓ Tool definitions with safety levels and categories~%")
(format t "  ✓ Parameter validators~%")
(format t "  ✓ Tool registry management~%")
(format t "  ✓ Lifecycle hooks for logging~%")
(format t "  ✓ Error handling with new conditions~%")
(format t "  ✓ Safe tool filtering~%~%")

(format t "Note: Set ANTHROPIC_API_KEY environment variable to use the example~%~%")

;; Uncomment to run automatically:
;; (simple-chat-example)
;; (interactive-chat-example)
