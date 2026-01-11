(in-package :cl-llm-provider)

;;;; OpenAI-Compatible Provider Implementation
;;;;
;;;; This provider is for any service that implements OpenAI's API format,
;;;; such as Groq, Together AI, local vLLM, etc.
;;;;
;;;; Since it inherits from openai-provider, all the request/response
;;;; handling is already implemented. This file just provides documentation
;;;; and could add provider-specific customizations if needed.

;; No default base URL - must be specified when creating the provider
(defmethod provider-default-base-url ((provider openai-compatible-provider))
  nil)

;; No standard environment variable - varies by provider
(defmethod provider-api-key-env-var ((provider openai-compatible-provider))
  nil)

;;; Provider Introspection

(defmethod provider-type ((provider openai-compatible-provider))
  :openai-compatible)

(defmethod provider-name ((provider openai-compatible-provider))
  "OpenAI-Compatible")

(defmethod provider-capabilities ((provider openai-compatible-provider))
  '(:tools t
    :embeddings t  ; Most OpenAI-compatible APIs support embeddings
    :streaming t
    :vision nil  ; Conservative default, varies by provider
    :function-calling t))

;; All other methods are inherited from openai-provider:
;; - send-completion-request
;; - parse-completion-response
;; - send-embedding-request
;; - parse-embedding-response
;; - translate-tool-to-provider
;; - parse-tool-calls

;;;; Usage Examples
;;;;
;;;; ;; Groq
;;;; (make-provider :openai-compatible
;;;;                :api-key (uiop:getenv "GROQ_API_KEY")
;;;;                :base-url "https://api.groq.com/openai/v1"
;;;;                :model "mixtral-8x7b-32768")
;;;;
;;;; ;; Together AI
;;;; (make-provider :openai-compatible
;;;;                :api-key (uiop:getenv "TOGETHER_API_KEY")
;;;;                :base-url "https://api.together.xyz/v1"
;;;;                :model "meta-llama/Llama-3-70b-chat-hf")
;;;;
;;;; ;; Local vLLM
;;;; (make-provider :openai-compatible
;;;;                :base-url "http://localhost:8000/v1"
;;;;                :model "your-local-model")
