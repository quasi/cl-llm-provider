(in-package :cl-llm-provider)

;;;; Google Gemini Provider Implementation

(defmethod provider-default-base-url ((provider gemini-provider))
  "https://generativelanguage.googleapis.com/v1beta/openai/")

(defmethod provider-api-key-env-var ((provider gemini-provider))
  "GEMINI_API_KEY")

;;; Provider Introspection

(defmethod provider-type ((provider gemini-provider))
  :gemini)

(defmethod provider-name ((provider gemini-provider))
  "Google Gemini")

(defmethod provider-capabilities ((provider gemini-provider))
  '(:tools t
    :embeddings t
    :streaming t
    :vision t
    :function-calling t))

(defmethod model-metadata ((provider gemini-provider) model-name)
  (get-model-metadata *gemini-model-registry* model-name))
