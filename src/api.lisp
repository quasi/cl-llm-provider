(in-package :cl-llm-provider)

;;;; High-Level API
;;;;
;;;; This file provides the main user-facing API functions.

(defun/i make-provider (provider-type &key api-key base-url model options)
  "Create a provider instance for API interactions.

PROVIDER-TYPE - One of :anthropic, :gemini, :openai, :ollama, :openrouter, :openai-compatible
API-KEY - API key (falls back to environment/config if nil)
BASE-URL - Override default API endpoint
MODEL - Default model for this provider
OPTIONS - Provider-specific options (plist)

Returns a provider instance (subclass of llm-provider).
Signals provider-configuration-error if required config missing.

Example:
  ;; Explicit configuration
  (make-provider :anthropic
                 :api-key \"sk-ant-...\"
                 :model \"claude-3-sonnet-20240229\")

  ;; Using environment variables (reads ANTHROPIC_API_KEY)
  (make-provider :anthropic :model \"claude-3-sonnet-20240229\")

  ;; Local Ollama
  (make-provider :ollama
                 :base-url \"http://localhost:11434\"
                 :model \"llama3\")

  ;; OpenAI-compatible (e.g., Groq)
  (make-provider :openai-compatible
                 :api-key \"gsk_...\"
                 :base-url \"https://api.groq.com/openai/v1\"
                 :model \"mixtral-8x7b-32768\")"
  (:feature completion-api)
  (:purpose "Factory function to create configured provider instances")
  (let* ((provider-class (ecase provider-type
                           (:anthropic 'anthropic-provider)
                           (:gemini 'gemini-provider)
                           (:openai 'openai-provider)
                           (:ollama 'ollama-provider)
                           (:openrouter 'openrouter-provider)
                           (:openai-compatible 'openai-compatible-provider)))
         (provider (make-instance provider-class
                                  :api-key api-key
                                  :base-url base-url
                                  :model model
                                  :options options)))

    ;; Set base-url from default if not provided
    (unless (provider-base-url provider)
      (when-let ((default-url (provider-default-base-url provider)))
        (setf (provider-base-url provider) default-url)))

    ;; Get API key from environment if not provided (and not Ollama which doesn't need it)
    (when (and (not (typep provider 'ollama-provider))
               (not (provider-api-key provider)))
      (when-let ((env-var (provider-api-key-env-var provider)))
        (setf (provider-api-key provider)
              (get-env-or-error env-var
                                (format nil "API key required for ~A" provider-type)))))

    provider))

(defun/i complete (messages &key provider model max-tokens temperature
                              system tools tool-choice stop
                              hooks on-request on-response on-error)
  "Send a completion request to an LLM provider.

MESSAGES - List of message plists ((:role \"user\" :content \"Hello\"))
PROVIDER - Provider instance (uses *default-provider* if nil)
MODEL - Model identifier (uses provider/global default if nil)
MAX-TOKENS - Maximum tokens in response (integer)
TEMPERATURE - Sampling temperature (0.0-2.0)
SYSTEM - System prompt (string)
TOOLS - List of tool definitions
TOOL-CHOICE - Tool selection strategy (keyword, string, or nil)
STOP - Stop sequences (string or list)

OBSERVABILITY:
HOOKS - hooks structure from make-hooks
ON-REQUEST - Callback (lambda (request-plist) ...) before request
ON-RESPONSE - Callback (lambda (response timing) ...) after response
ON-ERROR - Callback (lambda (error) ...) on error

Returns a completion-response object.

Signals:
  - provider-api-error on API errors
  - provider-rate-limit-error on rate limiting
  - provider-authentication-error on auth failures

Example:
  ;; Simple completion using defaults
  (complete '((:role \"user\" :content \"What is Common Lisp?\")))

  ;; With explicit provider and parameters
  (complete '((:role \"user\" :content \"Explain monads\"))
            :provider *anthropic*
            :model \"claude-3-opus-20240229\"
            :max-tokens 1000
            :temperature 0.7
            :system \"You are a functional programming expert.\")

  ;; Multi-turn conversation
  (complete '((:role \"user\" :content \"What is 2+2?\")
              (:role \"assistant\" :content \"2+2 equals 4.\")
              (:role \"user\" :content \"And if you add 3?\"))

  ;; With observability hooks
  (complete messages
            :hooks my-hooks
            :on-request (lambda (info)
                         (format t \"Sending request to ~A~%\" (getf info :provider)))
            :on-response (lambda (response timing)
                          (format t \"Got response in ~,2Fs~%\" timing)))"
  (:feature completion-api)
  (:purpose "Send completion request with provider resolution, hooks, and error handling")
  (let* ((prov (or provider *default-provider*))
         (mod (or model
                  (and prov (provider-default-model prov))
                  *default-model*))
         (max-tok (or max-tokens *default-max-tokens*))
         (temp (or temperature *default-temperature*))
         (all-hooks (or hooks *global-hooks*))
         (start-time (get-internal-real-time))
         (request-info (list :provider (when prov (provider-type prov))
                            :model mod
                            :message-count (length messages)
                            :has-tools (not (null tools)))))

    (unless prov
      (setf prov
            (restart-case
                (error 'provider-configuration-error
                       :message "No provider specified and *default-provider* is nil")
              (use-provider (p)
                :report "Supply a provider to use"
                :interactive (lambda ()
                               (format t "Enter provider form: ")
                               (list (eval (read))))
                p))))

    (unless mod
      (setf mod
            (restart-case
                (error 'provider-configuration-error
                       :message "No model specified and no default model configured")
              (use-model (m)
                :report "Supply a model name"
                :interactive (lambda ()
                               (format t "Enter model name: ")
                               (list (read-line)))
                m))))

    ;; Validate tools if provided
    (when tools
      (validate-tools tools))

    ;; Invoke before-request hooks
    (when all-hooks
      (invoke-hooks all-hooks :before-request prov mod messages))
    (when on-request
      (funcall on-request request-info))

    ;; Use handler-bind (not handler-case) to preserve restart stack from deeper calls.
    ;; This allows agents using handler-bind + invoke-restart to recover from errors
    ;; signaled by handle-http-error, provider methods, etc.
    (handler-bind
        ((error (lambda (e)
                  (when all-hooks
                    (invoke-hooks all-hooks :on-error prov mod e))
                  (when on-error
                    (funcall on-error e)))))
      ;; Send request and parse response (with performance tracking if enabled)
      (let ((response
              (if *performance-profiling*
                  (let ((*performance-stats* (make-performance-stats)))
                    (let* ((raw-response (send-completion-request prov messages
                                                                   :model mod
                                                                   :max-tokens max-tok
                                                                   :temperature temp
                                                                   :system system
                                                                   :tools tools
                                                                   :tool-choice tool-choice
                                                                   :stop stop))
                           (resp (with-performance-timing (:decode-time)
                                   (parse-completion-response prov raw-response
                                                             :performance nil))))
                      ;; Update response with complete performance stats (including decode time)
                      (setf (response-performance resp) (get-performance-stats))
                      resp))
                  ;; No profiling - standard path
                  (let ((raw-response (send-completion-request prov messages
                                                                :model mod
                                                                :max-tokens max-tok
                                                                :temperature temp
                                                                :system system
                                                                :tools tools
                                                                :tool-choice tool-choice
                                                                :stop stop)))
                    (parse-completion-response prov raw-response))))
            (timing (/ (- (get-internal-real-time) start-time)
                      internal-time-units-per-second)))

        ;; Invoke after-response hooks (only on success path)
        (when all-hooks
          (invoke-hooks all-hooks :after-response prov mod response timing))
        (when on-response
          (funcall on-response response timing))

        response))))

(defun/i embedding (input &key provider model dimensions)
  "Generate vector embeddings for text.

INPUT - Text to embed (string or list of strings)
PROVIDER - Provider instance (uses *default-provider* if nil)
MODEL - Embedding model identifier (uses provider/global default if nil)
DIMENSIONS - Output dimensions if model supports (integer)

Returns an embedding-response object.

Signals: provider-api-error, provider-authentication-error

Example:
  ;; Single text
  (embedding \"Common Lisp is a powerful language\")

  ;; Batch embeddings
  (embedding '(\"First document\" \"Second document\" \"Third document\")
             :model \"text-embedding-3-small\")"
  (:feature completion-api)
  (:purpose "Generate vector embeddings with provider resolution and profiling")
  (let* ((prov (or provider *default-provider*))
         (mod (or model
                  (and prov (provider-default-model prov))
                  *default-model*)))

    (unless prov
      (setf prov
            (restart-case
                (error 'provider-configuration-error
                       :message "No provider specified and *default-provider* is nil")
              (use-provider (p)
                :report "Supply a provider to use"
                :interactive (lambda ()
                               (format t "Enter provider form: ")
                               (list (eval (read))))
                p))))

    (unless mod
      (setf mod
            (restart-case
                (error 'provider-configuration-error
                       :message "No model specified and no default model configured")
              (use-model (m)
                :report "Supply a model name"
                :interactive (lambda ()
                               (format t "Enter model name: ")
                               (list (read-line)))
                m))))

    ;; Send request and parse response (with performance tracking if enabled)
    (if *performance-profiling*
        (let ((*performance-stats* (make-performance-stats)))
          (let* ((raw-response (send-embedding-request prov input
                                                        :model mod
                                                        :dimensions dimensions))
                 (response (with-performance-timing (:decode-time)
                             (parse-embedding-response prov raw-response
                                                      :performance nil))))
            ;; Update response with complete performance stats (including decode time)
            (setf (response-performance response) (get-performance-stats))
            response))
        ;; No profiling - standard path
        (let ((raw-response (send-embedding-request prov input
                                                     :model mod
                                                     :dimensions dimensions)))
          (parse-embedding-response prov raw-response)))))

(defun/i complete-stream (messages &key provider model max-tokens temperature
                                      system tools tool-choice stop
                                      on-chunk on-complete on-error)
  "Send a streaming completion request to an LLM provider.

MESSAGES - List of message plists ((:role \"user\" :content \"Hello\"))
PROVIDER - Provider instance (uses *default-provider* if nil)
MODEL - Model identifier (uses provider/global default if nil)
MAX-TOKENS - Maximum tokens in response (integer)
TEMPERATURE - Sampling temperature (0.0-2.0)
SYSTEM - System prompt (string)
TOOLS - List of tool definitions
TOOL-CHOICE - Tool selection strategy
STOP - Stop sequences

CALLBACKS:
ON-CHUNK - Function (lambda (chunk) ...) called for each chunk
ON-COMPLETE - Function (lambda (full-content final-chunk) ...) called when done
ON-ERROR - Function (lambda (error) ...) called on error

Returns a completion-stream object.

Example:
  ;; Callback-based usage
  (complete-stream messages
    :on-chunk (lambda (chunk)
                (format t \"~A\" (chunk-delta chunk)))
    :on-complete (lambda (content final)
                   (format t \"~%Done! ~D tokens~%\"
                           (getf (chunk-usage final) :total-tokens))))

  ;; Manual iteration
  (let ((stream (complete-stream messages)))
    (loop for chunk = (read-stream-chunk stream)
          while chunk
          do (format t \"~A\" (chunk-delta chunk))))"
  (:feature streaming-api)
  (:purpose "Send streaming completion with optional chunk/complete/error callbacks")
  (let* ((prov (or provider *default-provider*))
         (mod (or model
                  (and prov (provider-default-model prov))
                  *default-model*))
         (max-tok (or max-tokens *default-max-tokens*))
         (temp (or temperature *default-temperature*)))

    (unless prov
      (setf prov
            (restart-case
                (error 'provider-configuration-error
                       :message "No provider specified and *default-provider* is nil")
              (use-provider (p)
                :report "Supply a provider to use"
                :interactive (lambda ()
                               (format t "Enter provider form: ")
                               (list (eval (read))))
                p))))

    (unless mod
      (setf mod
            (restart-case
                (error 'provider-configuration-error
                       :message "No model specified and no default model configured")
              (use-model (m)
                :report "Supply a model name"
                :interactive (lambda ()
                               (format t "Enter model name: ")
                               (list (read-line)))
                m))))

    ;; Validate tools if provided
    (when tools
      (validate-tools tools))

    (let ((stream (send-streaming-request prov messages
                                          :model mod
                                          :max-tokens max-tok
                                          :temperature temp
                                          :system system
                                          :tools tools
                                          :tool-choice tool-choice
                                          :stop stop)))

      ;; If callbacks provided, start reading in current thread
      (when (or on-chunk on-complete on-error)
        (handler-case
            (loop for chunk = (read-stream-chunk stream)
                  while chunk
                  do (when on-chunk (funcall on-chunk chunk))
                  finally (when on-complete
                            (funcall on-complete
                                    (stream-accumulated-content stream)
                                    (car (stream-chunks stream)))))
          (error (e)
            (if on-error
                (funcall on-error e)
                (error e)))))

      stream)))
