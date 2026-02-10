(in-package :cl-llm-provider)

;;;; Configuration and Global Defaults

(defvar *default-provider* nil
  "Default provider used when :provider argument is omitted from API calls.
Thread safety: set at startup via CONFIGURE-DEFAULTS, or use WITH-PROVIDER
for per-thread overrides.")

(defvar *default-model* nil
  "Default model used when :model argument is omitted and provider has no default.
Thread safety: set at startup via CONFIGURE-DEFAULTS, or use WITH-MODEL
for per-thread overrides.")

(defvar *default-max-tokens* 4096
  "Default max-tokens when not specified.
Thread safety: set at startup via CONFIGURE-DEFAULTS, or pass :max-tokens
explicitly for per-thread overrides.")

(defvar *default-temperature* 1.0
  "Default temperature when not specified.
Thread safety: set at startup via CONFIGURE-DEFAULTS, or pass :temperature
explicitly for per-thread overrides.")

(defvar *config-lock* (bt:make-lock "cl-llm-provider-config")
  "Lock for thread-safe mutation of global configuration defaults.")

;;;; Configuration File Path

(defconstant +default-config-file-path+
  (merge-pathnames "cl-llm-provider/config.lisp"
                   (uiop:xdg-config-home))
  "Default path for configuration file.

   This is a SUGGESTED path only - the library never loads this automatically.
   Users can pass any path to load-configuration-from-file, or set API keys
   directly via make-provider or environment variables.")

;;;; Configuration Loading (Opt-In Only)

(defun load-configuration-from-file (&key (path +default-config-file-path+) verbose)
  "Load configuration from a Lisp file (OPT-IN ONLY - never called automatically).

   PATH - Path to configuration file (default: +default-config-file-path+)
   VERBOSE - If true, print loading progress (default: NIL)

   IMPORTANT: This function is NEVER called automatically by the library.
   Configuration is purely opt-in. You can configure the library via:

   1. Explicit arguments:
      (make-provider :anthropic :api-key \"sk-ant-...\")

   2. Environment variables:
      export ANTHROPIC_API_KEY=\"sk-ant-...\"

   3. This function (loads a Lisp file that can set env vars or special vars):
      (load-configuration-from-file :path \"~/.config/cl-llm-provider/config.lisp\")

   The configuration file should set environment variables:
     (setf (uiop:getenv \"ANTHROPIC_API_KEY\") \"sk-ant-...\")
     (setf (uiop:getenv \"OPENAI_API_KEY\") \"sk-...\")

   Or directly set the special variables:
     (setf cl-llm-provider:*default-provider* :anthropic)
     (setf cl-llm-provider:*default-model* \"claude-3-sonnet-20240229\")

   Returns plist of loaded configuration values.

   Examples:
     (load-configuration-from-file)                    ; Uses +default-config-file-path+
     (load-configuration-from-file :path #p\"~/my-config.lisp\")
     (load-configuration-from-file :verbose t)"
  (let* ((config-path path)
         (resolved-path (probe-file config-path)))

    (when verbose
      (format t "~&━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%")
      (format t "Loading cl-llm-provider configuration~%")
      (format t "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%")
      (format t "Config file: ~A~%" config-path))

    (cond
      (resolved-path
       (when verbose
         (format t "Status: ✓ Found~%")
         (format t "~%Loading Lisp configuration file...~%"))
       (load resolved-path :verbose nil)
       (when verbose
         (format t "✓ Configuration loaded successfully~%")))

      (t
       (when verbose
         (format t "Status: ✗ Not found~%")
         (format t "~%~%To create configuration file:~%")
         (format t "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%")
         (format t "1. Create directory:~%")
         (format t "   mkdir -p ~~/.config/cl-llm-provider~%")
         (format t "~%2. Create config file at:~%")
         (format t "   ~A~%" +default-config-file-path+)
         (format t "~%3. Add your API keys:~%")
         (format t "   ;;; cl-llm-provider configuration~%")
         (format t "   (setf (uiop:getenv \"ANTHROPIC_API_KEY\") \"sk-ant-...\")~%")
         (format t "   (setf (uiop:getenv \"OPENAI_API_KEY\") \"sk-...\")~%")
         (format t "~%4. Optionally set defaults:~%")
         (format t "   (setf cl-llm-provider:*default-model* \"claude-3-sonnet-20240229\")~%")
         (format t "~%5. Load it manually:~%")
         (format t "   (load-configuration-from-file)~%")
         (format t "~%See config.lisp.example in the repository for more options.~%"))))

    ;; Show what was loaded
    (when (and verbose resolved-path)
      (let ((loaded-keys '()))
        (when (uiop:getenv "ANTHROPIC_API_KEY")
          (push "ANTHROPIC_API_KEY" loaded-keys))
        (when (uiop:getenv "OPENAI_API_KEY")
          (push "OPENAI_API_KEY" loaded-keys))
        (when (uiop:getenv "OPENROUTER_API_KEY")
          (push "OPENROUTER_API_KEY" loaded-keys))
        (when (uiop:getenv "OLLAMA_BASE_URL")
          (push "OLLAMA_BASE_URL" loaded-keys))

        (format t "~%Environment variables set:~%")
        (if loaded-keys
            (dolist (key (nreverse loaded-keys))
              (format t "  ✓ ~A~%" key))
            (format t "  (none)~%"))

        (format t "~%Global defaults:~%")
        (format t "  *default-provider*: ~A~%"
                (if *default-provider*
                    (type-of *default-provider*)
                    "NIL"))
        (format t "  *default-model*: ~A~%" (or *default-model* "NIL"))
        (format t "  *default-max-tokens*: ~A~%" *default-max-tokens*)
        (format t "  *default-temperature*: ~A~%" *default-temperature*)
        (format t "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%"))))

  ;; Return loaded configuration as plist
  (list :anthropic-api-key (uiop:getenv "ANTHROPIC_API_KEY")
        :openai-api-key (uiop:getenv "OPENAI_API_KEY")
        :openrouter-api-key (uiop:getenv "OPENROUTER_API_KEY")
        :ollama-base-url (uiop:getenv "OLLAMA_BASE_URL")
        :default-provider *default-provider*
        :default-model *default-model*
        :default-max-tokens *default-max-tokens*
        :default-temperature *default-temperature*))


(defun configure-defaults (&key provider model max-tokens temperature)
  "Set global defaults for LLM operations.

PROVIDER - Default provider (provider instance or keyword to create one automatically)
MODEL - Default model identifier
MAX-TOKENS - Default max tokens
TEMPERATURE - Default temperature

Thread safety: Mutations are serialized with *CONFIG-LOCK*.
For per-thread overrides, use WITH-PROVIDER, WITH-MODEL, or explicit keyword arguments.

Example:
  (configure-defaults :provider (make-provider :anthropic)
                      :model \"claude-3-sonnet-20240229\"
                      :max-tokens 2048)

  (configure-defaults :provider :anthropic
                      :model \"claude-3-sonnet-20240229\")"
  (bt:with-lock-held (*config-lock*)
    (when provider
      (setf *default-provider*
            (etypecase provider
              (llm-provider provider)
              (keyword (make-provider provider)))))
    (when model
      (setf *default-model* model))
    (when max-tokens
      (setf *default-max-tokens* max-tokens))
    (when temperature
      (setf *default-temperature* temperature)))
  nil)

;;;; Convenience Macros

(defmacro with-provider ((provider-form) &body body)
  "Execute BODY with a specific provider as the default.

Example:
  (with-provider ((make-provider :ollama :model \"llama3\"))
    (complete '((:role \"user\" :content \"Hello\")))
    (complete '((:role \"user\" :content \"Goodbye\"))))"
  `(let ((*default-provider* ,provider-form))
     ,@body))

(defmacro with-model ((model-name) &body body)
  "Execute BODY with a specific model as the default.

Example:
  (with-model (\"claude-3-opus-20240229\")
    (complete '((:role \"user\" :content \"Complex reasoning task...\"))))"
  `(let ((*default-model* ,model-name))
     ,@body))

;;;; Internal Helpers

(defun get-env-or-error (var-name &optional (error-message "Environment variable not set"))
  "Get environment variable VAR-NAME or signal error."
  (or (uiop:getenv var-name)
      (restart-case
          (error 'provider-configuration-error
                 :missing-key var-name
                 :message error-message)
        (use-value (value)
          :report "Provide a value to use instead"
          :interactive (lambda ()
                         (format t "Enter value for ~A: " var-name)
                         (list (read-line)))
          value)
        (use-environment (env-var)
          :report "Try a different environment variable"
          :interactive (lambda ()
                         (format t "Enter environment variable name: ")
                         (list (read-line)))
          (or (uiop:getenv env-var)
              (error 'provider-configuration-error
                     :missing-key env-var
                     :message (format nil "Environment variable ~A not set" env-var)))))))
