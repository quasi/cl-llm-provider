(in-package :cl-llm-provider)

;;;; Provider Classes

(defclass llm-provider ()
  ((api-key :initarg :api-key
            :initform nil
            :reader provider-api-key
            :documentation "API key for authentication.")
   (base-url :initarg :base-url
             :initform nil
             :reader provider-base-url
             :documentation "Base URL for API requests.")
   (default-model :initarg :model
                  :initform nil
                  :accessor provider-default-model
                  :documentation "Default model identifier for this provider.")
   (options :initarg :options
            :initform nil
            :reader provider-options
            :documentation "Provider-specific options (plist)."))
  (:documentation "Base class for all LLM provider implementations."))

(defmethod print-object ((provider llm-provider) stream)
  (print-unreadable-object (provider stream :type t :identity t)
    (format stream "~@[model: ~A~]" (provider-default-model provider))))

(defclass anthropic-provider (llm-provider)
  ()
  (:documentation "Anthropic API provider (Claude models)."))

(defclass openai-provider (llm-provider)
  ()
  (:documentation "OpenAI API provider (GPT models)."))

(defclass ollama-provider (llm-provider)
  ()
  (:documentation "Ollama local model provider."))

(defclass openrouter-provider (llm-provider)
  ()
  (:documentation "OpenRouter multi-provider gateway."))

(defclass openai-compatible-provider (openai-provider)
  ()
  (:documentation "OpenAI-compatible API provider (e.g., Groq, Together, vLLM)."))

;;;; Response Types

(defclass completion-response ()
  ((id :initarg :id
       :reader response-id
       :documentation "Unique response identifier.")
   (model :initarg :model
          :reader response-model
          :documentation "Model that generated the response.")
   (content :initarg :content
            :initform nil
            :reader response-content
            :documentation "Text content of the response (nil if tool call).")
   (message :initarg :message
            :reader response-message
            :documentation "Full message plist for conversation continuation.")
   (tool-calls :initarg :tool-calls
               :initform nil
               :reader response-tool-calls
               :documentation "List of tool-call objects if model requested tool use.")
   (finish-reason :initarg :finish-reason
                  :reader response-finish-reason
                  :documentation "Why generation stopped (:stop, :length, :tool-calls).")
   (usage :initarg :usage
          :reader response-usage
          :documentation "Token usage plist (:prompt-tokens N :completion-tokens M :total-tokens T).")
   (raw :initarg :raw
        :reader response-raw
        :documentation "Original provider response for debugging/advanced use.")
   (performance :initarg :performance
                :initform nil
                :reader response-performance
                :documentation "Performance timing plist (:encode-time N :api-time M :decode-time K) when *performance-profiling* is enabled.")
   (metadata :initarg :metadata
             :initform nil
             :reader response-metadata
             :documentation "Provider-specific metadata plist (timing, fingerprints, etc)."))
  (:documentation "Normalized completion response from any provider."))

(defmethod print-object ((response completion-response) stream)
  (print-unreadable-object (response stream :type t)
    (format stream "~A ~:[tools~;~:*~S~]"
            (response-model response)
            (let ((content (response-content response)))
              (when content
                (subseq content 0 (min 40 (length content))))))))

(defclass embedding-response ()
  ((embeddings :initarg :embeddings
               :reader response-embeddings
               :documentation "List of vectors (each vector is a list of floats).")
   (model :initarg :model
          :reader response-model
          :documentation "Model used for embeddings.")
   (usage :initarg :usage
          :reader response-usage
          :documentation "Token usage plist.")
   (raw :initarg :raw
        :reader response-raw
        :documentation "Original provider response.")
   (performance :initarg :performance
                :initform nil
                :reader response-performance
                :documentation "Performance timing plist (:encode-time N :api-time M :decode-time K) when *performance-profiling* is enabled.")
   (metadata :initarg :metadata
             :initform nil
             :reader response-metadata
             :documentation "Provider-specific metadata plist (timing, fingerprints, etc)."))
  (:documentation "Normalized embedding response from any provider."))

(defmethod print-object ((response embedding-response) stream)
  (print-unreadable-object (response stream :type t)
    (format stream "~A: ~D vectors"
            (response-model response)
            (length (response-embeddings response)))))

;;;; Tool Types

(defclass tool-definition ()
  ((name :initarg :name
         :reader tool-name
         :documentation "Tool/function name.")
   (description :initarg :description
                :reader tool-description
                :documentation "What the tool does (used by LLM).")
   (parameters :initarg :parameters
               :reader tool-parameters
               :documentation "Parameter specifications as plists.")
   (required :initarg :required
             :initform nil
             :reader tool-required-params
             :documentation "List of required parameter names."))
  (:documentation "Represents a tool that can be called by the LLM."))

(defmethod print-object ((tool tool-definition) stream)
  (print-unreadable-object (tool stream :type t)
    (format stream "~A" (tool-name tool))))

(defclass tool-call ()
  ((id :initarg :id
       :reader tool-call-id
       :documentation "Unique identifier for this call (needed for result correlation).")
   (name :initarg :name
         :reader tool-call-name
         :documentation "Name of the tool to call.")
   (arguments :initarg :arguments
              :reader tool-call-arguments
              :documentation "Plist of arguments (already parsed from JSON)."))
  (:documentation "Represents a tool invocation requested by the LLM."))

(defmethod print-object ((call tool-call) stream)
  (print-unreadable-object (call stream :type t)
    (format stream "~A(~{~A~^, ~})"
            (tool-call-name call)
            (loop for (key value) on (tool-call-arguments call) by #'cddr
                  collect (format nil "~A=~S" key value)))))
