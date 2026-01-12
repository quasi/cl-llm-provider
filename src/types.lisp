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

;;;; Streaming Types

(defclass stream-chunk ()
  ((content :initarg :content
            :initform ""
            :accessor chunk-content
            :documentation "Accumulated content so far.")
   (delta :initarg :delta
          :initform ""
          :reader chunk-delta
          :documentation "New content in this chunk.")
   (finish-reason :initarg :finish-reason
                  :initform nil
                  :reader chunk-finish-reason
                  :documentation "Set when stream completes (:stop, :length, :tool-calls).")
   (index :initarg :index
          :initform 0
          :reader chunk-index
          :documentation "Chunk sequence number.")
   (tool-call-delta :initarg :tool-call-delta
                    :initform nil
                    :reader chunk-tool-call-delta
                    :documentation "Partial tool call data if streaming tool calls.")
   (usage :initarg :usage
          :initform nil
          :reader chunk-usage
          :documentation "Usage info (only set on final chunk for some providers)."))
  (:documentation "A single chunk from a streaming response."))

(defmethod print-object ((chunk stream-chunk) stream)
  (print-unreadable-object (chunk stream :type t)
    (format stream "~D: ~S~@[ [~A]~]"
            (chunk-index chunk)
            (let ((delta (chunk-delta chunk)))
              (if (> (length delta) 20)
                  (concatenate 'string (subseq delta 0 20) "...")
                  delta))
            (chunk-finish-reason chunk))))

(defclass completion-stream ()
  ((provider :initarg :provider
             :reader stream-provider
             :documentation "The provider this stream is from.")
   (model :initarg :model
          :reader stream-model
          :documentation "Model identifier.")
   (state :initarg :state
          :initform :open
          :accessor stream-state
          :documentation "Stream state: :open, :closed, :error")
   (chunks :initarg :chunks
           :initform nil
           :accessor stream-chunks
           :documentation "List of received chunks (for accumulation).")
   (accumulated-content :initarg :accumulated-content
                        :initform ""
                        :accessor stream-accumulated-content
                        :documentation "Full accumulated text content.")
   (http-stream :initarg :http-stream
                :initform nil
                :accessor stream-http-stream
                :documentation "Underlying HTTP stream for reading.")
   (error-condition :initarg :error-condition
                    :initform nil
                    :accessor stream-error-condition
                    :documentation "Error condition if state is :error."))
  (:documentation "Represents an active streaming completion response."))

(defmethod print-object ((stream completion-stream) stream-out)
  (print-unreadable-object (stream stream-out :type t)
    (format stream-out "~A ~A (~D chunks)"
            (stream-model stream)
            (stream-state stream)
            (length (stream-chunks stream)))))

(defun stream-open-p (stream)
  "Return T if STREAM is still open and receiving chunks."
  (eq (stream-state stream) :open))

(defun stream-closed-p (stream)
  "Return T if STREAM is closed (completed or errored)."
  (not (stream-open-p stream)))

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
             :documentation "List of required parameter names.")
   ;; NEW: Safety and categorization
   (safety-level :initarg :safety-level
                 :initform :safe
                 :accessor tool-safety-level
                 :documentation "Safety classification: :safe (no side effects),
                                :moderate (reversible side effects),
                                :dangerous (irreversible/sensitive operations).")
   (categories :initarg :categories
               :initform nil
               :accessor tool-categories
               :documentation "List of category keywords for classification
                              (e.g., :search, :database, :filesystem, :network).")
   ;; NEW: Approval system
   (requires-approval :initarg :requires-approval
                      :initform nil
                      :accessor tool-requires-approval
                      :documentation "Whether tool requires human approval before execution.
                                     NIL = no approval, T/:always = always require,
                                     :if-dangerous = require only if safety-level is :dangerous.")
   ;; NEW: Parameter validation
   (parameter-validators :initarg :parameter-validators
                         :initform nil
                         :accessor tool-parameter-validators
                         :documentation "Alist mapping parameter names to validator functions or specs.
                                        Each validator is either a function (lambda (value) ...)
                                        or a validator spec plist like (:type :integer :min 0 :max 100).")
   ;; NEW: Lifecycle hooks
   (on-start :initarg :on-start
             :initform nil
             :accessor tool-on-start
             :documentation "Function called before tool execution: (lambda (tool-call arguments) ...)")
   (on-complete :initarg :on-complete
                :initform nil
                :accessor tool-on-complete
                :documentation "Function called after successful execution: (lambda (tool-call arguments result) ...)")
   (on-error :initarg :on-error
             :initform nil
             :accessor tool-on-error
             :documentation "Function called on execution failure: (lambda (tool-call arguments condition) ...)")
   ;; NEW: Execution handler
   (handler :initarg :handler
            :initform nil
            :accessor tool-handler
            :documentation "Optional function to execute the tool: (lambda (arguments) ...).
                           Enables automatic tool execution when provided.")
   ;; NEW: Metadata
   (metadata :initarg :metadata
             :initform nil
             :accessor tool-metadata
             :documentation "Plist of additional metadata (version, author, documentation-url, etc.)."))
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
