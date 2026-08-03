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
                  (:json-parse-fail "Response body is not valid JSON")
                  (:model-not-found-names-nothing
                   "A 404 for an unknown model reports \"Model not found: NIL\".
CLASSIFY-API-ERROR reads :requested-model from a nested (error.model) field that
almost no server sends, and HANDLE-HTTP-ERROR was never told which model the
caller asked for. Measured 2026-08-04 against a live MLX server. An operator is
told that something was not found and not what — the least useful true sentence
available, and it cost one wrong diagnosis in the session that fixed it."
                   :mitigation "HANDLE-HTTP-ERROR takes :REQUESTED-MODEL, and falls
back to *REQUESTED-MODEL*, which COMPLETE binds inside its retry loop. The BODY
still wins when it names a model: the server is the authority on what it refused,
and a caller-supplied value overwriting that would replace a fact with an
assumption. Guarded by a test asserting the name appears in the printed REPORT,
not merely in the slot — the report is what reaches a spool file."
                   :violates :reliable)))

(deffeature completion-api
  :purpose "High-level API for completions, embeddings, and streaming"
  :belongs-to llm-provider
  :goals ((:simple "Single function call for common operations")
          (:configurable "Defaults cascade: explicit > provider > global")
          (:failover-can-cross-providers
           "Recovering from a dead provider means reaching a DIFFERENT one, which
in practice always means a different model too. Switching provider without being
able to switch model is not failover; it is a switch that cannot succeed."))
  :constraints ((:provider-required "A provider must be available")
                (:model-required "A model must be specified or defaulted"))
  :failure-modes ((:fallback-carries-the-dead-providers-model
                   "USE-FALLBACK-PROVIDER switches the provider and KEEPS the
model. Its body re-resolved (%RESOLVE-MODEL model prov) where MODEL is the
caller's original argument, and %RESOLVE-MODEL is (or model ...) — so an explicit
model always won and travelled to an endpoint that had never heard of it. The
restart appeared to work: the handler ran, the switch happened, and the request
then died on the fallback's own 404. Measured 2026-08-04 against a live MLX server
and OpenRouter."
                   :mitigation "USE-FALLBACK-PROVIDER takes an optional model. The
ONE-ARGUMENT FORM IS UNCHANGED — preferring the new provider's default would be
the more helpful default and would silently break callers failing over between
two endpoints serving the same model."
                   :violates :failover-can-cross-providers)
                  (:one-model-string-in-three-places
                   "The pre-existing test built both providers with :model \"m\"
and passed :model \"m\", so 'the model travelled' and 'the model was replaced'
were the same green, and the defect above survived every run. The first draft of
its replacement control repeated the mistake."
                   :mitigation "The fixtures give each provider a DIFFERENT model
name and record what each was handed; the cross-provider fixture REFUSES anything
but its own, so a restart that carried the wrong model cannot pass by accident."
                   :violates :failover-can-cross-providers)
                  (:no-way-to-correct-a-model-name
                   "PROVIDER-MODEL-NOT-FOUND-ERROR offered RETRY, which repeats the
same 404, and USE-FALLBACK-PROVIDER, which is a sledgehammer for a typo — and
nothing that could fix the one thing actually wrong."
                   :mitigation "A USE-MODEL restart on COMPLETE's retry loop."
                   :violates :recoverable))
  :decisions ((:id :use-model-lives-in-complete-not-in-handle-http-error
               :chose "The USE-MODEL restart is established in COMPLETE's retry
loop, beside USE-FALLBACK-PROVIDER"
               :over ("Establishing it in HANDLE-HTTP-ERROR, where the 404 is
actually signalled and where RETRY already lives")
               :because "There is nothing to change down there. HANDLE-HTTP-ERROR
returns :RETRY and the provider method re-issues with its OWN lexical model, which
no restart body can reach. MOD, in COMPLETE, is the variable the next attempt
actually reads."
               :decided-by "agent, 2026-08-04")
              (:id :in-flight-model-travels-on-a-dynamic-variable
               :chose "*REQUESTED-MODEL*, bound by COMPLETE inside its retry loop"
               :over ("Threading :REQUESTED-MODEL through PROVIDER-HTTP-POST and
every SEND-COMPLETION-REQUEST method — nine call sites across five provider files"
                      "Widening CLASSIFY-API-ERROR, a public generic that callers
specialize, which would break every specialization to save one LIST*")
               :because "Attaching context to a condition without changing a
signature and without re-signalling is exactly what a dynamic binding is for. Bound
INSIDE the loop, not outside, so a model corrected by USE-MODEL is the one a second
failure names — bound outside, the second failure would report the first attempt's
model and read exactly like the truth."
               :decided-by "agent, 2026-08-04")))

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
          (:validated "Parameters validated before execution")
          (:stable-safety-contract
           "Safety levels are exactly :safe, :moderate, and :dangerous; only :safe denotes read-only behavior")
          (:fail-closed-classification
           "Consumers treat every non-:safe value, including an unrecognized value, as effectful"))
  :failure-modes ((:safety-underclassification
                   "A non-:safe or unrecognized safety level is treated as read-only, bypassing effect metering or approval")
                  (:schema-invalid "Tool definition malformed")
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
