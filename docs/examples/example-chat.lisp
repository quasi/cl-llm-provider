;;;; example-chat.lisp
;;;; Complete chat application demonstrating cl-llm-provider features
;;;;
;;;; Load and run:
;;;;   (load "example-chat.lisp")
;;;;   (example-chat:start-chat)
;;;;
;;;; Prerequisites:
;;;;   (ql:quickload :cl-llm-provider)
;;;;   (ql:quickload :str)

(defpackage #:example-chat
  (:use #:cl)
  (:export #:start-chat
           #:chat
           #:chat-stream
           #:setup-providers
           #:setup-tools
           #:clear-messages
           #:switch-provider
           #:list-providers
           #:*messages*
           #:*current-provider*
           #:*providers*
           #:*streaming-enabled*))

(in-package #:example-chat)

;;;; Configuration

(defvar *messages* nil
  "Conversation history - list of message plists")

(defvar *current-provider* nil
  "Currently active LLM provider")

(defvar *providers* (make-hash-table :test 'eq)
  "Available LLM providers")

(defvar *tools* nil
  "Available function calling tools")

(defvar *total-tokens* 0
  "Total tokens used this session")

(defvar *streaming-enabled* nil
  "Whether to stream responses word-by-word")

;;;; Helper: Get Environment Variables

(defun get-env (key)
  "Get environment variable by name"
  (uiop:getenv key))

;;;; Provider Setup

(defun setup-providers ()
  "Create all available LLM providers based on environment"
  (clrhash *providers*)

  ;; Ollama (local, no API key needed)
  (handler-case
      (setf (gethash :ollama *providers*)
            (cl-llm-provider:make-provider
             :ollama
             :base-url "http://localhost:11434"
             :model "llama3.2"))
    (error (e)
      (format t "[WARN] Could not setup Ollama: ~A~%" e)))

  ;; OpenAI
  (when-let ((api-key (get-env "OPENAI_API_KEY")))
    (handler-case
        (setf (gethash :openai *providers*)
              (cl-llm-provider:make-provider
               :openai
               :api-key api-key
               :model "gpt-4o-mini"))
      (error (e)
        (format t "[WARN] Could not setup OpenAI: ~A~%" e))))

  ;; Anthropic Claude
  (when-let ((api-key (get-env "ANTHROPIC_API_KEY")))
    (handler-case
        (setf (gethash :claude *providers*)
              (cl-llm-provider:make-provider
               :anthropic
               :api-key api-key
               :model "claude-3-5-sonnet-20241022"))
      (error (e)
        (format t "[WARN] Could not setup Anthropic: ~A~%" e))))

  ;; Google Gemini
  (when-let ((api-key (get-env "GEMINI_API_KEY")))
    (handler-case
        (setf (gethash :gemini *providers*)
              (cl-llm-provider:make-provider
               :gemini
               :api-key api-key
               :model "gemini-2.0-flash-exp"))
      (error (e)
        (format t "[WARN] Could not setup Gemini: ~A~%" e))))

  (format t "[SETUP] Configured ~D provider(s): ~{~A~^, ~}~%"
          (hash-table-count *providers*)
          (loop for key being the hash-keys of *providers*
                collect key))

  ;; Set default provider
  (unless *current-provider*
    (setf *current-provider*
          (or (gethash :ollama *providers*)
              (gethash :openai *providers*)
              (gethash :claude *providers*)
              (gethash :gemini *providers*))))

  *providers*)

;;;; Tools / Function Calling

(defun check-weather (location)
  "Simulate weather check - replace with real API"
  (format nil "Weather in ~A: Sunny, 72°F (simulated)" location))

(defun get-time (timezone)
  "Get current time in timezone"
  (declare (ignore timezone))
  (multiple-value-bind (sec min hour day month year)
      (get-decoded-time)
    (format nil "~4D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D"
            year month day hour min sec)))

(defun setup-tools ()
  "Create function calling tools for the AI"
  (setf *tools*
        (list
         ;; Weather tool
         (cl-llm-provider:define-tool
          "check_weather"
          "Get current weather for a location"
          '((:name "location"
             :type :string
             :description "City name (e.g., 'Tokyo', 'Paris')"))
          :required '("location")
          :handler (lambda (args)
                     (check-weather (getf args :location))))

         ;; Time tool
         (cl-llm-provider:define-tool
          "get_time"
          "Get current time in a timezone"
          '((:name "timezone"
             :type :string
             :description "Timezone like 'America/New_York'"))
          :required '("timezone")
          :handler (lambda (args)
                     (get-time (getf args :timezone)))))))

;;;; Message Management

(defun add-message (role content &key tool-call-id)
  "Add message to conversation history"
  (let ((msg (list :role role :content content)))
    (when tool-call-id
      (setf (getf msg :tool-call-id) tool-call-id))
    (push msg *messages*)))

(defun clear-messages ()
  "Clear conversation history"
  (setf *messages* nil)
  (format t "[CLEAR] Conversation history cleared~%"))

(defun get-history ()
  "Get conversation history in correct order (oldest first)"
  (reverse *messages*))

;;;; Core Chat Functions

(defun chat (user-input &key (provider *current-provider*) (use-tools t))
  "Send message to AI and return response"
  (unless provider
    (error "No provider available. Set up providers first."))

  ;; Add user message
  (add-message "user" user-input)

  (let ((response (cl-llm-provider:complete
                   (get-history)
                   :provider provider
                   :tools (when use-tools *tools*)
                   :max-tokens 1000)))

    ;; Update token count
    (let ((usage (cl-llm-provider:response-usage response)))
      (incf *total-tokens* (getf usage :total-tokens)))

    ;; Handle response
    (cond
      ;; AI wants to call functions
      ((cl-llm-provider:response-tool-calls response)
       (format t "[TOOL CALLS] AI is using tools...~%")
       (handle-tool-calls response provider))

      ;; Normal text response
      ((cl-llm-provider:response-content response)
       (let ((content (cl-llm-provider:response-content response)))
         (add-message "assistant" content)
         content))

      ;; Empty response
      (t
       "[No response from AI]"))))

(defun chat-stream (user-input &key (provider *current-provider*))
  "Send message with streaming response"
  (unless provider
    (error "No provider available. Set up providers first."))

  ;; Add user message
  (add-message "user" user-input)

  (format t "~%Assistant: ")
  (force-output)

  (let ((full-content ""))
    (cl-llm-provider:complete-stream
     (get-history)
     :provider provider
     :max-tokens 1000
     :on-chunk (lambda (chunk)
                 (let ((delta (cl-llm-provider:chunk-delta chunk)))
                   (when (and delta (> (length delta) 0))
                     (format t "~A" delta)
                     (force-output)
                     (setf full-content
                           (concatenate 'string full-content delta)))))
     :on-complete (lambda (content final-chunk)
                    (declare (ignore content))
                    (format t "~%")
                    (let ((usage (cl-llm-provider:chunk-usage final-chunk)))
                      (when usage
                        (incf *total-tokens* (getf usage :total-tokens)))))
     :on-error (lambda (error)
                 (format t "~%[ERROR] ~A~%" error)))

    ;; Add to history
    (add-message "assistant" full-content)
    full-content))

;;;; Tool Call Handling

(defun handle-tool-calls (response provider)
  "Execute tool calls and continue conversation"
  (let ((tool-calls (cl-llm-provider:response-tool-calls response)))

    ;; Add assistant message with tool calls
    (push (cl-llm-provider:response-message response)
          *messages*)

    ;; Execute each tool
    (dolist (call tool-calls)
      (let* ((tool-name (cl-llm-provider:tool-call-name call))
             (tool-args-ht (cl-llm-provider:tool-call-arguments call))
             (tool-id (cl-llm-provider:tool-call-id call))
             (tool (find tool-name *tools*
                         :key #'cl-llm-provider:tool-name
                         :test #'string=)))

        ;; Convert hash table to plist
        (let ((args-plist nil))
          (maphash (lambda (k v)
                     (push v args-plist)
                     (push (intern (string-upcase k) :keyword) args-plist))
                   tool-args-ht)

          (format t "[CALL] ~A(~{~A: ~S~^, ~})~%" tool-name args-plist)

          ;; Execute tool
          (if tool
              (handler-case
                  (let* ((handler (cl-llm-provider:tool-handler tool))
                         (result (funcall handler args-plist)))
                    (format t "[RESULT] ~A~%" result)
                    ;; Add tool result to history
                    (push (list :role "tool"
                                :tool-call-id tool-id
                                :content (format nil "~A" result))
                          *messages*))
                (error (e)
                  (format t "[ERROR] Tool execution failed: ~A~%" e)
                  (push (list :role "tool"
                              :tool-call-id tool-id
                              :content (format nil "Error: ~A" e))
                        *messages*)))
              (progn
                (format t "[ERROR] Tool ~A not found~%" tool-name)
                (push (list :role "tool"
                            :tool-call-id tool-id
                            :content (format nil "Tool not available"))
                      *messages*))))))

    ;; Continue conversation with tool results
    (let ((response (cl-llm-provider:complete
                     (get-history)
                     :provider provider
                     :max-tokens 1000)))

      (let ((content (cl-llm-provider:response-content response)))
        (add-message "assistant" content)
        content))))

;;;; Provider Management

(defun list-providers ()
  "Show available providers"
  (format t "~%=== Available Providers ===~%")
  (if (zerop (hash-table-count *providers*))
      (format t "No providers configured!~%")
      (maphash (lambda (key provider)
                 (format t "~:[  ~;* ~]~A - ~A (model: ~A)~%"
                         (eq provider *current-provider*)
                         key
                         (type-of provider)
                         (cl-llm-provider:provider-default-model provider)))
               *providers*))
  (format t "~%"))

(defun switch-provider (provider-key)
  "Switch to different provider"
  (let ((provider (gethash provider-key *providers*)))
    (if provider
        (progn
          (setf *current-provider* provider)
          (format t "[SWITCH] Now using ~A~%" provider-key))
        (format t "[ERROR] Provider ~A not available~%" provider-key))))

;;;; Statistics

(defun show-stats ()
  "Display session statistics"
  (format t "~%=== Session Statistics ===~%")
  (format t "Current provider: ~A~%"
          (loop for key being the hash-keys of *providers*
                  using (hash-value provider)
                when (eq provider *current-provider*)
                return key))
  (format t "Messages: ~D~%" (length *messages*))
  (format t "Total tokens: ~D~%" *total-tokens*)
  (format t "Streaming: ~A~%" (if *streaming-enabled* "ON" "OFF"))
  (format t "~%"))

;;;; Interactive Loop

(defun print-help ()
  "Print available commands"
  (format t "~%=== Commands ===~%")
  (format t "/help           - Show this help~%")
  (format t "/providers      - List available providers~%")
  (format t "/switch <name>  - Switch provider (ollama, openai, claude, gemini)~%")
  (format t "/stream on|off  - Toggle streaming mode~%")
  (format t "/clear          - Clear conversation history~%")
  (format t "/stats          - Show session statistics~%")
  (format t "/quit           - Exit chat~%")
  (format t "~%Type your message and press Enter to chat.~%~%"))

(defun start-chat ()
  "Start interactive chat session"
  (format t "~%")
  (format t "╔════════════════════════════════════════════════════════╗~%")
  (format t "║         Example Chat - cl-llm-provider Demo           ║~%")
  (format t "╚════════════════════════════════════════════════════════╝~%")
  (format t "~%")

  ;; Initialize
  (setup-providers)
  (setup-tools)

  (unless *current-provider*
    (format t "~%[ERROR] No providers available!~%")
    (format t "~%To use this example:~%")
    (format t "1. Install Ollama: https://ollama.ai~%")
    (format t "2. Run: ollama serve~%")
    (format t "3. Run: ollama pull llama3.2~%")
    (format t "~%Or set environment variables:~%")
    (format t "  OPENAI_API_KEY=sk-your-key~%")
    (format t "  ANTHROPIC_API_KEY=sk-ant-your-key~%")
    (format t "  GEMINI_API_KEY=your-key~%")
    (return-from start-chat))

  (format t "Chat started! Type /help for commands.~%")
  (list-providers)

  ;; Main loop
  (loop
    (format t "You: ")
    (force-output)

    (let ((input (read-line *standard-input* nil :eof)))
      (when (eq input :eof)
        (format t "~%Goodbye!~%")
        (return))

      (let ((trimmed (string-trim '(#\Space #\Tab #\Newline) input)))
        (cond
          ;; Empty input
          ((zerop (length trimmed))
           nil)

          ;; Quit
          ((string= trimmed "/quit")
           (format t "~%Goodbye!~%")
           (return))

          ;; Help
          ((string= trimmed "/help")
           (print-help))

          ;; List providers
          ((string= trimmed "/providers")
           (list-providers))

          ;; Switch provider
          ((str:starts-with-p "/switch " trimmed)
           (let ((provider-name (string-trim '(#\Space)
                                             (subseq trimmed 8))))
             (switch-provider (intern (string-upcase provider-name)
                                      :keyword))))

          ;; Toggle streaming
          ((str:starts-with-p "/stream " trimmed)
           (let ((mode (string-trim '(#\Space) (subseq trimmed 8))))
             (cond
               ((string-equal mode "on")
                (setf *streaming-enabled* t)
                (format t "[STREAM] Enabled~%"))
               ((string-equal mode "off")
                (setf *streaming-enabled* nil)
                (format t "[STREAM] Disabled~%"))
               (t
                (format t "Usage: /stream on|off~%")))))

          ;; Clear history
          ((string= trimmed "/clear")
           (clear-messages))

          ;; Statistics
          ((string= trimmed "/stats")
           (show-stats))

          ;; Regular chat message
          (t
           (handler-case
               (if *streaming-enabled*
                   (chat-stream trimmed)
                   (let ((response (chat trimmed)))
                     (format t "~%Assistant: ~A~%~%" response)))
             (error (e)
               (format t "~%[ERROR] ~A~%~%" e)))))))))

;;; EOF
