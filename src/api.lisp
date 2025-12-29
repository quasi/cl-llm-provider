(in-package :cl-llm-provider)

;;;; High-Level API
;;;;
;;;; This file provides the main user-facing API functions.

(defun make-provider (provider-type &key api-key base-url model options)
  "Create a provider instance for API interactions.

PROVIDER-TYPE - One of :anthropic, :openai, :ollama, :openrouter, :openai-compatible
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
  (let* ((provider-class (ecase provider-type
                           (:anthropic 'anthropic-provider)
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
        (setf (slot-value provider 'base-url) default-url)))

    ;; Get API key from environment if not provided (and not Ollama which doesn't need it)
    (when (and (not (typep provider 'ollama-provider))
               (not (provider-api-key provider)))
      (when-let ((env-var (provider-api-key-env-var provider)))
        (setf (slot-value provider 'api-key)
              (get-env-or-error env-var
                                (format nil "API key required for ~A" provider-type)))))

    provider))

(defun complete (messages &key provider model max-tokens temperature
                              system tools tool-choice stop)
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
              (:role \"user\" :content \"And if you add 3?\")))"
  (let* ((prov (or provider *default-provider*))
         (mod (or model
                  (and prov (provider-default-model prov))
                  *default-model*))
         (max-tok (or max-tokens *default-max-tokens*))
         (temp (or temperature *default-temperature*)))

    (unless prov
      (error 'provider-configuration-error
             :message "No provider specified and *default-provider* is nil"))

    (unless mod
      (error 'provider-configuration-error
             :message "No model specified and no default model configured"))

    ;; Validate tools if provided
    (when tools
      (validate-tools tools))

    ;; Send request and parse response (with performance tracking if enabled)
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
                 (response (with-performance-timing (:decode-time)
                             (parse-completion-response prov raw-response
                                                       :performance nil))))
            ;; Update response with complete performance stats (including decode time)
            (setf (slot-value response 'performance) (get-performance-stats))
            response))
        ;; No profiling - standard path
        (let ((raw-response (send-completion-request prov messages
                                                      :model mod
                                                      :max-tokens max-tok
                                                      :temperature temp
                                                      :system system
                                                      :tools tools
                                                      :tool-choice tool-choice
                                                      :stop stop)))
          (parse-completion-response prov raw-response)))))

(defun embedding (input &key provider model dimensions)
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
  (let* ((prov (or provider *default-provider*))
         (mod (or model
                  (and prov (provider-default-model prov))
                  *default-model*)))

    (unless prov
      (error 'provider-configuration-error
             :message "No provider specified and *default-provider* is nil"))

    (unless mod
      (error 'provider-configuration-error
             :message "No model specified and no default model configured"))

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
            (setf (slot-value response 'performance) (get-performance-stats))
            response))
        ;; No profiling - standard path
        (let ((raw-response (send-embedding-request prov input
                                                     :model mod
                                                     :dimensions dimensions)))
          (parse-embedding-response prov raw-response)))))
