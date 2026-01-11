(in-package :cl-llm-provider)

;; ABOUTME: Model metadata registries for OpenAI and Anthropic models.
;; Provides context windows, output limits, pricing, and capability information.

;;; ============================================================
;;; Model Registry Infrastructure
;;; ============================================================

(defvar *openai-model-registry* (make-hash-table :test 'equal)
  "Registry of OpenAI model metadata.
Keys are model name strings, values are plists with:
  :context-window - max input tokens
  :max-output-tokens - max completion tokens
  :supports-tools - boolean
  :supports-vision - boolean
  :input-cost-per-1m-tokens - USD per 1M input tokens
  :output-cost-per-1m-tokens - USD per 1M output tokens")

(defvar *anthropic-model-registry* (make-hash-table :test 'equal)
  "Registry of Anthropic model metadata.
Keys are model name strings, values are plists with same schema as *openai-model-registry*.")

(defun register-model-metadata (registry model-name metadata)
  "Register METADATA for MODEL-NAME in REGISTRY.
METADATA should be a plist with keys like :context-window, :max-output-tokens, etc."
  (setf (gethash model-name registry) metadata))

(defun get-model-metadata (registry model-name)
  "Get metadata for MODEL-NAME from REGISTRY, or NIL if unknown."
  (gethash model-name registry))

;;; ============================================================
;;; OpenAI Models
;;; ============================================================

;; GPT-4o family
(register-model-metadata *openai-model-registry* "gpt-4o"
  '(:context-window 128000
    :max-output-tokens 16384
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 2.50
    :output-cost-per-1m-tokens 10.00))

(register-model-metadata *openai-model-registry* "gpt-4o-2024-11-20"
  '(:context-window 128000
    :max-output-tokens 16384
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 2.50
    :output-cost-per-1m-tokens 10.00))

(register-model-metadata *openai-model-registry* "gpt-4o-mini"
  '(:context-window 128000
    :max-output-tokens 16384
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 0.15
    :output-cost-per-1m-tokens 0.60))

(register-model-metadata *openai-model-registry* "gpt-4o-mini-2024-07-18"
  '(:context-window 128000
    :max-output-tokens 16384
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 0.15
    :output-cost-per-1m-tokens 0.60))

;; GPT-4 Turbo
(register-model-metadata *openai-model-registry* "gpt-4-turbo"
  '(:context-window 128000
    :max-output-tokens 4096
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 10.00
    :output-cost-per-1m-tokens 30.00))

(register-model-metadata *openai-model-registry* "gpt-4-turbo-2024-04-09"
  '(:context-window 128000
    :max-output-tokens 4096
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 10.00
    :output-cost-per-1m-tokens 30.00))

;; GPT-4 (original)
(register-model-metadata *openai-model-registry* "gpt-4"
  '(:context-window 8192
    :max-output-tokens 8192
    :supports-tools t
    :supports-vision nil
    :input-cost-per-1m-tokens 30.00
    :output-cost-per-1m-tokens 60.00))

(register-model-metadata *openai-model-registry* "gpt-4-32k"
  '(:context-window 32768
    :max-output-tokens 32768
    :supports-tools t
    :supports-vision nil
    :input-cost-per-1m-tokens 60.00
    :output-cost-per-1m-tokens 120.00))

;; GPT-3.5 Turbo
(register-model-metadata *openai-model-registry* "gpt-3.5-turbo"
  '(:context-window 16385
    :max-output-tokens 4096
    :supports-tools t
    :supports-vision nil
    :input-cost-per-1m-tokens 0.50
    :output-cost-per-1m-tokens 1.50))

(register-model-metadata *openai-model-registry* "gpt-3.5-turbo-0125"
  '(:context-window 16385
    :max-output-tokens 4096
    :supports-tools t
    :supports-vision nil
    :input-cost-per-1m-tokens 0.50
    :output-cost-per-1m-tokens 1.50))

;; o1 reasoning models
(register-model-metadata *openai-model-registry* "o1"
  '(:context-window 200000
    :max-output-tokens 100000
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 15.00
    :output-cost-per-1m-tokens 60.00))

(register-model-metadata *openai-model-registry* "o1-mini"
  '(:context-window 128000
    :max-output-tokens 65536
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 3.00
    :output-cost-per-1m-tokens 12.00))

(register-model-metadata *openai-model-registry* "o1-preview"
  '(:context-window 128000
    :max-output-tokens 32768
    :supports-tools nil
    :supports-vision nil
    :input-cost-per-1m-tokens 15.00
    :output-cost-per-1m-tokens 60.00))

;;; ============================================================
;;; Anthropic Models
;;; ============================================================

;; Claude 4 family
(register-model-metadata *anthropic-model-registry* "claude-opus-4-20250514"
  '(:context-window 200000
    :max-output-tokens 32000
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 15.00
    :output-cost-per-1m-tokens 75.00))

(register-model-metadata *anthropic-model-registry* "claude-sonnet-4-20250514"
  '(:context-window 200000
    :max-output-tokens 16000
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 3.00
    :output-cost-per-1m-tokens 15.00))

;; Claude 3.5 family
(register-model-metadata *anthropic-model-registry* "claude-3-5-sonnet-20241022"
  '(:context-window 200000
    :max-output-tokens 8192
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 3.00
    :output-cost-per-1m-tokens 15.00))

(register-model-metadata *anthropic-model-registry* "claude-3-5-sonnet-latest"
  '(:context-window 200000
    :max-output-tokens 8192
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 3.00
    :output-cost-per-1m-tokens 15.00))

(register-model-metadata *anthropic-model-registry* "claude-3-5-haiku-20241022"
  '(:context-window 200000
    :max-output-tokens 8192
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 0.80
    :output-cost-per-1m-tokens 4.00))

(register-model-metadata *anthropic-model-registry* "claude-3-5-haiku-latest"
  '(:context-window 200000
    :max-output-tokens 8192
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 0.80
    :output-cost-per-1m-tokens 4.00))

;; Claude 3 family
(register-model-metadata *anthropic-model-registry* "claude-3-opus-20240229"
  '(:context-window 200000
    :max-output-tokens 4096
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 15.00
    :output-cost-per-1m-tokens 75.00))

(register-model-metadata *anthropic-model-registry* "claude-3-sonnet-20240229"
  '(:context-window 200000
    :max-output-tokens 4096
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 3.00
    :output-cost-per-1m-tokens 15.00))

(register-model-metadata *anthropic-model-registry* "claude-3-haiku-20240307"
  '(:context-window 200000
    :max-output-tokens 4096
    :supports-tools t
    :supports-vision t
    :input-cost-per-1m-tokens 0.25
    :output-cost-per-1m-tokens 1.25))
