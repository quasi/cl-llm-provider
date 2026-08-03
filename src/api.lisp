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

(defun %coerce-provider (designator)
  "Accept a provider instance or a keyword designator."
  (etypecase designator
    (llm-provider designator)
    (keyword (make-provider designator))))

(defun %resolve-provider (provider)
  "Return PROVIDER or *default-provider*; restartable when absent."
  (or provider *default-provider*
      (restart-case
          (error 'provider-configuration-error
                 :message "No provider specified and *default-provider* is nil")
        (use-provider (p)
          :report "Supply a provider (instance or keyword like :anthropic)"
          :interactive (lambda ()
                         (format *query-io* "Enter provider keyword (e.g. :anthropic): ")
                         (finish-output *query-io*)
                         (let ((*read-eval* nil))
                           (list (read *query-io*))))
          (%coerce-provider p)))))

(defun %resolve-model (model provider)
  "Return MODEL, the provider default, or *default-model*; restartable when absent."
  (or model
      (and provider (provider-default-model provider))
      *default-model*
      (restart-case
          (error 'provider-configuration-error
                 :message "No model specified and no default model configured")
        (use-model (m)
          :report "Supply a model name"
          :interactive (lambda ()
                         (format *query-io* "Enter model name: ")
                         (finish-output *query-io*)
                         (list (read-line *query-io*)))
          m))))

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
              (:role \"user\" :content \"And if you add 3?\")))

  ;; With observability hooks
  (complete messages
            :hooks my-hooks
            :on-request (lambda (info)
                         (format t \"Sending request to ~A~%\" (getf info :provider)))
            :on-response (lambda (response timing)
                          (format t \"Got response in ~,2Fs~%\" timing)))"
  (:feature completion-api)
  (:purpose "Send completion request with provider resolution, hooks, and error handling")
  (let* ((prov (%resolve-provider provider))
         (mod (%resolve-model model prov))
         (max-tok (or max-tokens *default-max-tokens*))
         (temp (or temperature *default-temperature*))
         (all-hooks (or hooks *global-hooks*))
         (start-time (get-internal-real-time))
         (request-info (list :provider (when prov (provider-type prov))
                            :model mod
                            :message-count (length messages)
                            :has-tools (not (null tools)))))

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
    (loop
      (restart-case
          (return
            (handler-bind
                ((error (lambda (e)
                          (when all-hooks
                            (invoke-hooks all-hooks :on-error prov mod e))
                          (when on-error
                            (funcall on-error e)))))
              ;; INSIDE the loop, so a model changed by USE-MODEL or by
              ;; USE-FALLBACK-PROVIDER is the one the next failure reports. Bound
              ;; outside, a corrected second attempt would fail naming the FIRST
              ;; attempt's model — a lie that reads exactly like the truth.
              ;; Send request and parse response (with performance tracking if enabled)
              (let* ((*requested-model* mod)
                     (response
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

                response)))
        (use-fallback-provider (fallback &optional (fallback-model nil fallback-model-p))
          :report "Re-issue the request with a different provider"
          :interactive (lambda ()
                         (format *query-io* "Enter fallback provider keyword: ")
                         (finish-output *query-io*)
                         (let ((*read-eval* nil))
                           (list (read *query-io*))))
          ;; FALLBACK-MODEL IS WHAT MAKES A CROSS-PROVIDER FAILOVER POSSIBLE AT
          ;; ALL. Without it this restart switches the provider and KEEPS THE
          ;; MODEL, because %RESOLVE-MODEL is (or model ...) and an explicit model
          ;; always wins — so a local model name travels to a cloud endpoint that
          ;; has never heard of it. Measured 2026-08-04 against a live MLX server:
          ;; the switch succeeded and the request then died on the fallback's own
          ;; model-not-found. Every real local->cloud failover is that case;
          ;; "gemma-4-26B-A4B-it-QAT-MLX-4bit" means nothing to anyone else.
          ;;
          ;; THE ONE-ARGUMENT FORM IS UNCHANGED, deliberately. Preferring the new
          ;; provider's own default would be the more "helpful" default and would
          ;; silently break every caller failing over between two endpoints that
          ;; serve the SAME model — a behaviour change no existing test could have
          ;; caught, because the fixture used one model string in three places. A
          ;; caller who wants the model to change now says which.
          (setf prov (%coerce-provider fallback)
                mod (if fallback-model-p
                        fallback-model
                        (%resolve-model model prov))))
        (use-model (new-model)
          :report "Re-issue the request with a different model"
          :interactive (lambda ()
                         (format *query-io* "Enter model name: ")
                         (finish-output *query-io*)
                         (list (read-line *query-io*)))
          ;; ESTABLISHED HERE AND NOT IN HANDLE-HTTP-ERROR, where the 404 is
          ;; actually signalled, because there is nothing to change down there:
          ;; HANDLE-HTTP-ERROR returns :RETRY and the provider method re-issues
          ;; with its OWN lexical model, which no restart body can reach. MOD is
          ;; the variable the next attempt reads, and it lives here.
          ;;
          ;; R-CS-002 in substance rather than in form: the 404 already carried
          ;; RETRY (which repeats the same 404) and USE-FALLBACK-PROVIDER (a
          ;; sledgehammer for a typo) and nothing that could fix the one thing
          ;; actually wrong.
          (setf mod new-model))))))

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
  (let* ((prov (%resolve-provider provider))
         (mod (%resolve-model model prov)))
    (loop
      (restart-case
          (return
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
                  (parse-embedding-response prov raw-response))))
        ;; SAME CONTRACT AS COMPLETE'S, and it has to be. One restart name that takes
        ;; a model here and refuses one there is worse than either behaviour
        ;; alone: a caller writes the two-argument form, it works against
        ;; COMPLETE, and it dies on arity the first time the same recovery code
        ;; covers an embedding. Found by writing the how-to, not by a test.
        (use-fallback-provider (fallback &optional (fallback-model nil fallback-model-p))
          :report "Re-issue the request with a different provider"
          :interactive (lambda ()
                         (format *query-io* "Enter fallback provider keyword: ")
                         (finish-output *query-io*)
                         (let ((*read-eval* nil))
                           (list (read *query-io*))))
          (setf prov (%coerce-provider fallback)
                mod (if fallback-model-p
                        fallback-model
                        (%resolve-model model prov))))
        (use-model (new-model)
          :report "Re-issue the request with a different model"
          :interactive (lambda ()
                         (format *query-io* "Enter model name: ")
                         (finish-output *query-io*)
                         (list (read-line *query-io*)))
          (setf mod new-model))))))

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
Note: when callbacks are supplied, errors during reading propagate to the
caller after ON-ERROR fires; the stream object is only returned on success.

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
  (let* ((prov (%resolve-provider provider))
         (mod (%resolve-model model prov))
         (max-tok (or max-tokens *default-max-tokens*))
         (temp (or temperature *default-temperature*)))

    ;; Validate tools if provided
    (when tools
      (validate-tools tools))

    (loop
      (restart-case
          (return
            ;; Bound inside the loop for the same reason as in COMPLETE: a model
            ;; corrected by USE-MODEL must be the one a second failure names.
            (let* ((*requested-model* mod)
                   (stream (send-streaming-request prov messages
                                                  :model mod
                                                  :max-tokens max-tok
                                                  :temperature temp
                                                  :system system
                                                  :tools tools
                                                  :tool-choice tool-choice
                                                  :stop stop)))

              ;; If callbacks provided, start reading in current thread.
              ;; Use handler-bind (not handler-case) to preserve restart stack from
              ;; read-stream-chunk errors (e.g. stream-interrupted-error restarts).
              (when (or on-chunk on-complete on-error)
                (handler-bind
                    ((error (lambda (e)
                              (when on-error
                                (funcall on-error e)))))
                  (loop for chunk = (read-stream-chunk stream)
                        while chunk
                        do (when on-chunk (funcall on-chunk chunk))
                        finally (when on-complete
                                  (funcall on-complete
                                           (stream-accumulated-content stream)
                                           (first (stream-chunks stream)))))))

              stream))
        ;; SAME CONTRACT AS COMPLETE'S — see the note in EMBEDDING. This one matters
        ;; most of the three: a streaming turn is the path an agent actually
        ;; runs, so a recovery handler written once and reused is the normal
        ;; case rather than the unusual one.
        (use-fallback-provider (fallback &optional (fallback-model nil fallback-model-p))
          :report "Re-issue the request with a different provider"
          :interactive (lambda ()
                         (format *query-io* "Enter fallback provider keyword: ")
                         (finish-output *query-io*)
                         (let ((*read-eval* nil))
                           (list (read *query-io*))))
          (setf prov (%coerce-provider fallback)
                mod (if fallback-model-p
                        fallback-model
                        (%resolve-model model prov))))
        (use-model (new-model)
          :report "Re-issue the request with a different model"
          :interactive (lambda ()
                         (format *query-io* "Enter model name: ")
                         (finish-output *query-io*)
                         (list (read-line *query-io*)))
          (setf mod new-model))))))
