(in-package :cl-llm-provider)

;;;; Feature Hierarchy
;;;;
;;;; Defines the telos feature tree for cl-llm-provider.
;;;; Features organize code by purpose and provide queryable intent.

(deffeature llm-provider
  :purpose "Unified provider-agnostic interface to LLM APIs"
  :goals ((:provider-agnostic "Same API regardless of underlying LLM provider")
          (:agent-friendly "Programmatic recovery from all error conditions")
          (:observable "Full visibility into request/response lifecycle"))
  :constraints ((:http-only "Communication via HTTP/HTTPS only")
                (:sync-default "Synchronous by default, streaming opt-in"))
  :failure-modes ((:provider-down "Remote API unavailable")
                  (:auth-expired "API key invalid or expired")
                  (:rate-limited "Request rate exceeded provider limits")))

(deffeature provider-protocol
  :purpose "Generic function protocol enabling provider extensibility"
  :belongs-to llm-provider
  :goals ((:extensible "New providers added by subclassing + method specialization")
          (:uniform "All providers expose same generic interface"))
  :constraints ((:clos-based "Protocol defined via CLOS generic functions")))

(deffeature http-transport
  :purpose "HTTP communication, error classification, and retry infrastructure"
  :belongs-to llm-provider
  :goals ((:reliable "Classify and handle all HTTP error categories")
          (:recoverable "Every HTTP error offers programmatic restarts"))
  :failure-modes ((:network-unreachable "Cannot connect to provider")
                  (:timeout "Request or response exceeds time limit")
                  (:json-parse-fail "Response body is not valid JSON")))

(deffeature completion-api
  :purpose "High-level API for completions, embeddings, and streaming"
  :belongs-to llm-provider
  :goals ((:simple "Single function call for common operations")
          (:configurable "Defaults cascade: explicit > provider > global"))
  :constraints ((:provider-required "A provider must be available")
                (:model-required "A model must be specified or defaulted")))

(deffeature streaming-api
  :purpose "Streaming protocol, SSE parsing, and chunk accumulation"
  :belongs-to llm-provider
  :goals ((:incremental "Content delivered as it generates")
          (:accumulative "Full content available after stream completes"))
  :failure-modes ((:stream-interrupted "Connection drops mid-stream")
                  (:parse-failure "Malformed SSE chunk received")))

(deffeature tool-calling
  :purpose "Tool definition, validation, translation, and execution"
  :belongs-to llm-provider
  :goals ((:safe "Tools classified by safety level with approval gates")
          (:validated "Parameters validated before execution"))
  :failure-modes ((:schema-invalid "Tool definition malformed")
                  (:handler-missing "Tool has no execution handler")
                  (:execution-error "Handler raises during execution")))

(deffeature configuration
  :purpose "Configuration management, defaults, and thread safety"
  :belongs-to llm-provider
  :goals ((:thread-safe "Global defaults protected by lock")
          (:layered "Per-thread overrides via dynamic binding"))
  :constraints ((:opt-in-config "Config file never loaded automatically")))

(deffeature observability
  :purpose "Hook system for logging, tracing, and monitoring"
  :belongs-to llm-provider
  :goals ((:non-intrusive "Hook errors never propagate to caller")
          (:composable "Multiple hooks stack independently")))

(deffeature error-recovery
  :purpose "Restart infrastructure for programmatic agent recovery"
  :belongs-to llm-provider
  :goals ((:every-error-recoverable "Every error point offers at least one restart")
          (:agent-inspectable "Agents can list available restarts programmatically"))
  :constraints ((:handler-bind-safe "Restarts visible through handler-bind, not destroyed by handler-case")))
