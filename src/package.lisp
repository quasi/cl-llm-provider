(in-package :cl-user)

(defpackage :cl-llm-provider
  (:use :cl)
  (:import-from :alexandria
                :if-let
                :when-let
                :with-gensyms
                :hash-table-plist
                :plist-hash-table
                :ensure-list)
  (:import-from :serapeum
                :~>
                :dict
                :@)
  (:export
   ;; Provider creation
   #:make-provider

   ;; Core API functions
   #:complete
   #:embedding

   ;; Tool calling
   #:define-tool
   #:tool-calls
   #:make-tool-result

   ;; Configuration
   #:load-configuration
   #:configure-defaults
   #:*default-provider*
   #:*default-model*
   #:*default-max-tokens*
   #:*default-temperature*

   ;; Performance profiling
   #:*performance-profiling*
   #:make-performance-stats
   #:get-performance-stats
   #:get-monotonic-time
   #:with-performance-timing
   #:format-performance-time
   #:format-performance-stats

   ;; Convenience macros
   #:with-provider
   #:with-model

   ;; Provider classes
   #:llm-provider
   #:anthropic-provider
   #:openai-provider
   #:ollama-provider
   #:openrouter-provider
   #:openai-compatible-provider

   ;; Provider accessors
   #:provider-api-key
   #:provider-base-url
   #:provider-default-model
   #:provider-options

   ;; Response types
   #:completion-response
   #:response-id
   #:response-model
   #:response-content
   #:response-message
   #:response-tool-calls
   #:response-finish-reason
   #:response-usage
   #:response-raw
   #:response-performance
   #:response-metadata

   #:embedding-response
   #:response-embeddings

   ;; Tool types
   #:tool-definition
   #:tool-name
   #:tool-description
   #:tool-parameters
   #:tool-required-params
   ;; Enhanced tool accessors
   #:tool-safety-level
   #:tool-categories
   #:tool-requires-approval
   #:tool-parameter-validators
   #:tool-on-start
   #:tool-on-complete
   #:tool-on-error
   #:tool-handler
   #:tool-metadata

   #:tool-call
   #:tool-call-id
   #:tool-call-name
   #:tool-call-arguments

   ;; Conditions
   #:llm-provider-error
   #:error-provider
   #:error-message

   #:provider-configuration-error
   #:error-missing-key

   #:provider-api-error
   #:error-status-code
   #:error-body

   #:provider-rate-limit-error
   #:error-retry-after

   #:provider-authentication-error

   #:tool-schema-error
   #:error-tool
   #:error-reason

   ;; Enhanced tool conditions
   #:tool-validation-error
   #:error-parameter
   #:error-value
   #:error-validator

   #:tool-approval-error
   #:tool-approval-required
   #:error-tool-call

   #:tool-safety-violation
   #:error-required-level
   #:error-actual-level

   ;; Protocol (for extensibility)
   #:send-completion-request
   #:parse-completion-response
   #:send-embedding-request
   #:parse-embedding-response
   #:provider-default-base-url
   #:provider-api-key-env-var
   #:translate-tool-to-provider
   #:parse-tool-calls

   ;; Enhanced tools module (re-exported from cl-llm-provider.tools)
   ;; See cl-llm-provider.tools package for additional exports

   ;; Tool validation
   #:validate-tools
   #:validate-tool-definition))
