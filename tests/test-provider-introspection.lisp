(require :asdf)
(ql:quickload :fiveam :silent t)
(ql:quickload :alexandria :silent t)
(ql:quickload :serapeum :silent t)
(ql:quickload :dexador :silent t)
(ql:quickload :yason :silent t)
(ql:quickload :bordeaux-threads :silent t)
(ql:quickload :cl-ppcre :silent t)
(ql:quickload :uiop :silent t)

;; Load the library
(load "src/package.lisp")
(load "src/conditions.lisp")
(load "src/types.lisp")
(load "src/config.lisp")
(load "src/protocol.lisp")
(load "src/model-registry.lisp")
(load "src/tools.lisp")
(load "src/providers/anthropic.lisp")
(load "src/providers/openai.lisp")
(load "src/providers/ollama.lisp")
(load "src/providers/openrouter.lisp")
(load "src/providers/openai-compatible.lisp")
(load "src/api.lisp")

(in-package :cl-llm-provider)

;;; Define test suite
(fiveam:def-suite provider-introspection-suite
  :description "Test suite for provider introspection and metadata APIs")

(fiveam:in-suite provider-introspection-suite)

;;;; ============================================================
;;;; Phase 1: Provider Type Tests
;;;; ============================================================

(fiveam:test provider-type-openai
  "provider-type should return :openai for OpenAI provider"
  (let ((provider (make-provider :openai :api-key "test" :model "gpt-4")))
    (fiveam:is (eq :openai (provider-type provider)))))

(fiveam:test provider-type-anthropic
  "provider-type should return :anthropic for Anthropic provider"
  (let ((provider (make-provider :anthropic :api-key "test" :model "claude-3-opus")))
    (fiveam:is (eq :anthropic (provider-type provider)))))

(fiveam:test provider-type-ollama
  "provider-type should return :ollama for Ollama provider"
  (let ((provider (make-provider :ollama :base-url "http://localhost:11434" :model "llama3")))
    (fiveam:is (eq :ollama (provider-type provider)))))

(fiveam:test provider-type-openrouter
  "provider-type should return :openrouter for OpenRouter provider"
  (let ((provider (make-provider :openrouter :api-key "test" :model "openai/gpt-4")))
    (fiveam:is (eq :openrouter (provider-type provider)))))

(fiveam:test provider-type-openai-compatible
  "provider-type should return :openai-compatible for OpenAI-compatible provider"
  (let ((provider (make-provider :openai-compatible
                                 :api-key "test"
                                 :base-url "http://localhost:8000/v1"
                                 :model "local-model")))
    (fiveam:is (eq :openai-compatible (provider-type provider)))))

(fiveam:test provider-type-keyword-usable-in-eql
  "provider-type keywords should be usable in eql dispatch"
  (let ((provider (make-provider :openai :api-key "test" :model "gpt-4")))
    (fiveam:is (eql (provider-type provider) :openai))
    (fiveam:is (not (eql (provider-type provider) :anthropic)))))

;;;; ============================================================
;;;; Phase 1: Provider Name Tests
;;;; ============================================================

(fiveam:test provider-name-openai
  "provider-name should return 'OpenAI' for OpenAI provider"
  (let ((provider (make-provider :openai :api-key "test" :model "gpt-4")))
    (fiveam:is (string= "OpenAI" (provider-name provider)))))

(fiveam:test provider-name-anthropic
  "provider-name should return 'Anthropic' for Anthropic provider"
  (let ((provider (make-provider :anthropic :api-key "test" :model "claude-3-opus")))
    (fiveam:is (string= "Anthropic" (provider-name provider)))))

(fiveam:test provider-name-ollama
  "provider-name should return 'Ollama' for Ollama provider"
  (let ((provider (make-provider :ollama :base-url "http://localhost:11434" :model "llama3")))
    (fiveam:is (string= "Ollama" (provider-name provider)))))

(fiveam:test provider-name-openrouter
  "provider-name should return 'OpenRouter' for OpenRouter provider"
  (let ((provider (make-provider :openrouter :api-key "test" :model "openai/gpt-4")))
    (fiveam:is (string= "OpenRouter" (provider-name provider)))))

(fiveam:test provider-name-openai-compatible
  "provider-name should return 'OpenAI-Compatible' for OpenAI-compatible provider"
  (let ((provider (make-provider :openai-compatible
                                 :api-key "test"
                                 :base-url "http://localhost:8000/v1"
                                 :model "local-model")))
    (fiveam:is (string= "OpenAI-Compatible" (provider-name provider)))))

(fiveam:test provider-name-is-string
  "provider-name should always return a string"
  (dolist (type '(:openai :anthropic :ollama :openrouter))
    (let ((provider (make-provider type :api-key "test" :model "test-model")))
      (fiveam:is (stringp (provider-name provider))))))

;;;; ============================================================
;;;; Phase 1: Provider Capabilities Tests
;;;; ============================================================

(fiveam:test provider-capabilities-openai
  "OpenAI should support all major capabilities"
  (let* ((provider (make-provider :openai :api-key "test" :model "gpt-4"))
         (caps (provider-capabilities provider)))
    (fiveam:is (getf caps :tools))
    (fiveam:is (getf caps :embeddings))
    (fiveam:is (getf caps :streaming))
    (fiveam:is (getf caps :vision))
    (fiveam:is (getf caps :function-calling))))

(fiveam:test provider-capabilities-anthropic
  "Anthropic should support tools but not embeddings"
  (let* ((provider (make-provider :anthropic :api-key "test" :model "claude-3-opus"))
         (caps (provider-capabilities provider)))
    (fiveam:is (getf caps :tools))
    (fiveam:is (null (getf caps :embeddings)))
    (fiveam:is (getf caps :streaming))
    (fiveam:is (getf caps :vision))))

(fiveam:test provider-capabilities-ollama
  "Ollama should support embeddings but not vision by default"
  (let* ((provider (make-provider :ollama :base-url "http://localhost:11434" :model "llama3"))
         (caps (provider-capabilities provider)))
    (fiveam:is (getf caps :tools))
    (fiveam:is (getf caps :embeddings))
    (fiveam:is (getf caps :streaming))
    (fiveam:is (null (getf caps :vision)))))

(fiveam:test provider-capabilities-openrouter
  "OpenRouter should not support embeddings"
  (let* ((provider (make-provider :openrouter :api-key "test" :model "openai/gpt-4"))
         (caps (provider-capabilities provider)))
    (fiveam:is (getf caps :tools))
    (fiveam:is (null (getf caps :embeddings)))
    (fiveam:is (getf caps :streaming))))

(fiveam:test provider-capabilities-returns-plist
  "provider-capabilities should return a plist"
  (let* ((provider (make-provider :openai :api-key "test" :model "gpt-4"))
         (caps (provider-capabilities provider)))
    (fiveam:is (listp caps))
    (fiveam:is (keywordp (first caps)))))

;;;; ============================================================
;;;; Phase 1: provider-supports-p Tests
;;;; ============================================================

(fiveam:test provider-supports-p-openai-tools
  "OpenAI should support tools"
  (let ((provider (make-provider :openai :api-key "test" :model "gpt-4")))
    (fiveam:is-true (provider-supports-p provider :tools))))

(fiveam:test provider-supports-p-anthropic-embeddings
  "Anthropic should not support embeddings"
  (let ((provider (make-provider :anthropic :api-key "test" :model "claude-3")))
    (fiveam:is-false (provider-supports-p provider :embeddings))))

(fiveam:test provider-supports-p-returns-boolean
  "provider-supports-p should return boolean-like values"
  (let ((provider (make-provider :openai :api-key "test" :model "gpt-4")))
    ;; T or NIL
    (let ((result (provider-supports-p provider :tools)))
      (fiveam:is (or (eq result t) (null result))))))

(fiveam:test provider-supports-p-unknown-capability
  "Unknown capability should return NIL"
  (let ((provider (make-provider :openai :api-key "test" :model "gpt-4")))
    (fiveam:is (null (provider-supports-p provider :unknown-capability)))))

;;;; ============================================================
;;;; Phase 1: provider-config-summary Tests
;;;; ============================================================

(fiveam:test provider-config-summary-has-type
  "Config summary should include :type"
  (let* ((provider (make-provider :openai :api-key "test" :model "gpt-4"))
         (summary (provider-config-summary provider)))
    (fiveam:is (eq :openai (getf summary :type)))))

(fiveam:test provider-config-summary-has-name
  "Config summary should include :name"
  (let* ((provider (make-provider :openai :api-key "test" :model "gpt-4"))
         (summary (provider-config-summary provider)))
    (fiveam:is (string= "OpenAI" (getf summary :name)))))

(fiveam:test provider-config-summary-has-model
  "Config summary should include :model"
  (let* ((provider (make-provider :openai :api-key "test" :model "gpt-4"))
         (summary (provider-config-summary provider)))
    (fiveam:is (string= "gpt-4" (getf summary :model)))))

(fiveam:test provider-config-summary-has-base-url
  "Config summary should include :base-url"
  (let* ((provider (make-provider :openai :api-key "test" :model "gpt-4"))
         (summary (provider-config-summary provider)))
    (fiveam:is (getf summary :base-url))))

(fiveam:test provider-config-summary-has-capabilities
  "Config summary should include :capabilities"
  (let* ((provider (make-provider :openai :api-key "test" :model "gpt-4"))
         (summary (provider-config-summary provider)))
    (fiveam:is (listp (getf summary :capabilities)))))

(fiveam:test provider-config-summary-no-api-key
  "Config summary should NOT include API key"
  (let* ((provider (make-provider :openai :api-key "secret-key" :model "gpt-4"))
         (summary (provider-config-summary provider)))
    (fiveam:is (null (getf summary :api-key)))
    ;; Also verify the api-key is not in any nested structure
    (fiveam:is (not (search "secret-key" (format nil "~S" summary))))))

;;;; ============================================================
;;;; Phase 2: Model Metadata Tests
;;;; ============================================================

(fiveam:test model-metadata-openai-gpt4o
  "model-metadata should return metadata for gpt-4o"
  (let* ((provider (make-provider :openai :api-key "test" :model "gpt-4o"))
         (meta (model-metadata provider "gpt-4o")))
    (fiveam:is-true meta)
    (fiveam:is (= 128000 (getf meta :context-window)))
    (fiveam:is-true (getf meta :supports-tools))
    (fiveam:is-true (getf meta :supports-vision))
    (fiveam:is (numberp (getf meta :input-cost-per-1m-tokens)))))

(fiveam:test model-metadata-openai-gpt4o-mini
  "model-metadata should return metadata for gpt-4o-mini"
  (let* ((provider (make-provider :openai :api-key "test" :model "gpt-4o-mini"))
         (meta (model-metadata provider "gpt-4o-mini")))
    (fiveam:is-true meta)
    (fiveam:is (= 128000 (getf meta :context-window)))
    (fiveam:is (< (getf meta :input-cost-per-1m-tokens) 1.0))))

(fiveam:test model-metadata-anthropic-claude-3-5-sonnet
  "model-metadata should return metadata for claude-3-5-sonnet"
  (let* ((provider (make-provider :anthropic :api-key "test" :model "claude-3-5-sonnet-20241022"))
         (meta (model-metadata provider "claude-3-5-sonnet-20241022")))
    (fiveam:is-true meta)
    (fiveam:is (= 200000 (getf meta :context-window)))
    (fiveam:is-true (getf meta :supports-vision))))

(fiveam:test model-metadata-unknown-model
  "model-metadata should return NIL for unknown models"
  (let* ((provider (make-provider :openai :api-key "test" :model "unknown-model"))
         (meta (model-metadata provider "nonexistent-model")))
    (fiveam:is (null meta))))

(fiveam:test model-metadata-ollama-returns-nil
  "model-metadata should return NIL for Ollama (no registry)"
  (let* ((provider (make-provider :ollama :base-url "http://localhost:11434" :model "llama3"))
         (meta (model-metadata provider "llama3")))
    (fiveam:is (null meta))))

(fiveam:test register-model-metadata-custom
  "register-model-metadata should allow custom model registration"
  (let ((test-registry (make-hash-table :test 'equal)))
    (register-model-metadata test-registry "custom-model"
                             '(:context-window 10000 :supports-tools nil))
    (let ((meta (get-model-metadata test-registry "custom-model")))
      (fiveam:is-true meta)
      (fiveam:is (= 10000 (getf meta :context-window))))))

;;;; ============================================================
;;;; Integration Tests
;;;; ============================================================

(fiveam:test provider-introspection-format-display
  "Provider introspection should enable display formatting"
  (let* ((provider (make-provider :openai :api-key "test" :model "gpt-4o-mini"))
         (display-string (format nil "Using ~A ~A"
                                 (provider-name provider)
                                 (provider-default-model provider))))
    (fiveam:is (string= "Using OpenAI gpt-4o-mini" display-string))))

(fiveam:test provider-introspection-eql-dispatch
  "provider-type should work in eql-specializer dispatch"
  (let ((provider (make-provider :openai :api-key "test" :model "gpt-4")))
    (fiveam:is (case (provider-type provider)
                 (:openai t)
                 (:anthropic nil)
                 (t nil)))))

(fiveam:test provider-config-serializable
  "provider-config-summary should produce serializable data"
  (let* ((provider (make-provider :openai :api-key "secret" :model "gpt-4"))
         (summary (provider-config-summary provider)))
    ;; Should be able to write to string (for JSON serialization)
    (fiveam:is (stringp (format nil "~S" summary)))))

;;;; ============================================================
;;;; Generic Function Existence Tests
;;;; ============================================================

(fiveam:test generic-function-provider-type-exists
  "provider-type generic function should exist"
  (fiveam:is (fboundp 'provider-type)))

(fiveam:test generic-function-provider-name-exists
  "provider-name generic function should exist"
  (fiveam:is (fboundp 'provider-name)))

(fiveam:test generic-function-provider-capabilities-exists
  "provider-capabilities generic function should exist"
  (fiveam:is (fboundp 'provider-capabilities)))

(fiveam:test generic-function-model-metadata-exists
  "model-metadata generic function should exist"
  (fiveam:is (fboundp 'model-metadata)))

(fiveam:test function-provider-supports-p-exists
  "provider-supports-p function should exist"
  (fiveam:is (fboundp 'provider-supports-p)))

(fiveam:test generic-function-provider-config-summary-exists
  "provider-config-summary generic function should exist"
  (fiveam:is (fboundp 'provider-config-summary)))

;;;; Run Tests

(format t "~%~%=== Running Provider Introspection Test Suite ===~%~%")
(fiveam:run! 'provider-introspection-suite)
