(in-package :cl-user)

(defpackage :cl-llm-provider
  (:use :cl :telos)
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

   ;; Streaming API
   #:complete-stream
   #:read-stream-chunk
   #:stream-chunk
   #:chunk-content
   #:chunk-delta
   #:chunk-finish-reason
   #:chunk-index
   #:chunk-usage
   #:chunk-tool-call-delta
   #:completion-stream
   #:stream-open-p
   #:stream-closed-p
   #:stream-accumulated-content
   #:stream-state
   #:stream-tool-calls

   ;; Tool calling
   #:define-tool
   #:tool-calls
   #:make-tool-result

   ;; Configuration
   #:+default-config-file-path+
   #:default-config-file-path
   #:load-configuration-from-file
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
   #:gemini-provider

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
   #:tool-registration-error
   #:error-tool-name

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

   ;; Agent-oriented conditions (Phase 3)
   #:provider-model-not-found-error
   #:error-requested-model
   #:error-available-models

   #:provider-context-length-error
   #:error-token-count
   #:error-max-tokens
   #:error-context-model

   #:provider-content-filter-error
   #:error-filter-reason

   #:provider-overloaded-error
   ;; error-retry-after is shared with provider-rate-limit-error (already exported above)

   #:provider-invalid-response-error
   #:error-expected-format
   #:error-actual-value

   #:provider-network-error
   #:error-original-condition
   #:error-url
   #:error-operation

   #:provider-timeout-error
   #:error-timeout-seconds
   #:error-timeout-phase

   #:provider-json-parse-error
   #:error-raw-body
   #:error-parse-condition

   #:provider-unsupported-operation
   #:error-unsupported-operation
   #:error-unsupported-provider-type

   #:llm-stream-error
   #:stream-error-condition  ; slot accessor on completion-stream (distinct from llm-stream-error condition)
   #:error-stream-object
   #:error-stream-phase

   #:stream-interrupted-error
   #:error-chunks-received
   #:error-accumulated-content

   #:stream-parse-error
   #:error-raw-chunk
   #:error-chunk-parse-condition

   #:tool-execution-error
   #:error-arguments
   #:error-execution-cause

   #:tool-not-found-error
   #:error-missing-tool-name
   #:error-available-tools

   #:tool-handler-missing-error

   #:llm-provider-warning
   #:warning-provider
   #:warning-message

   #:provider-deprecation-warning
   #:warning-deprecated-feature
   #:warning-replacement

   ;; Error classification
   #:classify-api-error

   ;; Agent recovery helpers
   #:available-recovery-options
   #:transient-error-p
   #:provider-retry-after
   #:default-backoff
   #:retry-wait-time
   #:make-retry-handler
   #:with-auto-recovery

   ;; Restart names (for handler-bind + invoke-restart by agents)
   ;; From api.lisp:
   #:use-provider
   #:use-model
   ;; From protocol.lisp (handle-http-error):
   #:retry
   #:wait-and-retry
   #:use-fallback-provider
   ;; From streaming.lisp:
   #:return-partial-content
   #:abort-stream
   ;; Note: CL:USE-VALUE is already accessible from CL package.
   ;; Tool validation restarts (skip-validation, skip-invalid-tool) and
   ;; tool execution restarts (use-handler, use-error-result,
   ;; retry-execution, skip-tool) are in cl-llm-provider.tools package.

   ;; Protocol (for extensibility)
   #:send-completion-request
   #:parse-completion-response
   #:send-embedding-request
   #:parse-embedding-response
   #:provider-default-base-url
   #:provider-api-key-env-var
   #:translate-tool-to-provider
   #:translate-message-to-provider
   #:provider-http-post
   #:parse-tool-calls

   ;; Provider introspection
   #:provider-type
   #:provider-name
   #:provider-capabilities
   #:provider-supports-p
   #:provider-config-summary

   ;; Model metadata
   #:model-metadata
   #:*openai-model-registry*
   #:*anthropic-model-registry*
   #:*gemini-model-registry*
   #:register-model-metadata
   #:get-model-metadata

   ;; Token counting
   #:count-tokens
   #:count-tokens-with-system
   #:estimate-cost
   #:format-cost

   ;; Observability
   #:make-hooks
   #:add-hook
   #:remove-hook
   #:*global-hooks*
   #:make-logging-hooks

   ;; Enhanced tools module (re-exported from cl-llm-provider.tools)
   ;; See cl-llm-provider.tools package for additional exports

   ;; Tool validation
   #:validate-tools
   #:validate-tool-definition))
