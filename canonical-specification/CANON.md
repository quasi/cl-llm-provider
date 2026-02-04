---
type: agent-documentation
version: 1.0.0
generated: 2026-01-21
source: canon/
---

# AGENT.md

Agent-oriented documentation for cl-llm-provider. Optimized for LLM parsing and code generation.

## Project Context

| Property | Value |
|----------|-------|
| **Name** | cl-llm-provider |
| **Version** | 0.2.0 |
| **Language** | Common Lisp |
| **Build System** | ASDF |
| **Test Framework** | FiveAM |
| **License** | MIT |

**Description**: Unified Common Lisp interface for multiple LLM provider APIs (Anthropic, OpenAI, Google Gemini, Ollama, OpenRouter).

**Architecture**: Protocol-based design with provider-agnostic message handling, tool calling, streaming, and error recovery.

## Build Commands

```bash
# Load system
sbcl --eval '(asdf:load-system :cl-llm-provider)'

# Via Quicklisp (when available)
sbcl --eval '(ql:quickload :cl-llm-provider)'

# Run all tests
sbcl --eval '(asdf:test-system :cl-llm-provider)'

# Run specific test file
sbcl --noinform --non-interactive --load tests/test-provider-protocols.lisp

# Load and test
sbcl --eval '(progn (asdf:load-system :cl-llm-provider/test) (asdf:test-system :cl-llm-provider))'
```

## File Locations

| Type | Location | Notes |
|------|----------|-------|
| **Package definition** | `src/package.lisp` | Exports |
| **Types** | `src/types.lisp` | Response objects, tool definitions |
| **Conditions** | `src/conditions.lisp` | Error hierarchy |
| **Protocol** | `src/protocol.lisp` | Generic functions |
| **Providers** | `src/providers/*.lisp` | Per-provider implementations |
| **Core API** | `src/api.lisp` | `complete`, `embedding` |
| **Tools** | `src/tools.lisp` + `src/tools/*.lisp` | Tool definitions, validation, execution |
| **Streaming** | `src/streaming.lisp` | SSE parsing, stream management |
| **Config** | `src/config.lisp` | Configuration loading |
| **Model Metadata** | `src/model-registry.lisp` | Model registry, introspection |
| **Observability** | `src/observability.lisp` | Hooks, profiling |
| **Tokenizer** | `src/tokenizer.lisp` | Token counting |
| **Tests** | `tests/*.lisp` | Test suites |
| **Agent Specs** | `docs/agent/*.agent.md` | Formal specifications |
| **Canon** | `canon/` | Behavioral specification |

## Terminology

MUST use these terms consistently. No synonyms.

| Term | Definition |
|------|------------|
| **provider** | Instance of `llm-provider` subclass representing API connection |
| **completion** | Text generation request/response cycle via `complete` |
| **embedding** | Vector representation request/response via `embedding` |
| **message** | Plist with `:role`, `:content`, optional `:tool-calls`, `:tool-call-id` |
| **tool-definition** | Specification of callable function (name, description, parameters, handler) |
| **tool-call** | LLM's request to invoke specific tool with arguments |
| **tool-result** | Response message containing tool execution output |
| **protocol method** | Generic function specialized per provider type |
| **response object** | `completion-response` or `embedding-response` instance |
| **normalization** | Converting provider-specific formats to unified representation |
| **raw-response** | Provider's original HTTP response body (hash-table) |
| **performance-profiling** | Timing collection for encode/API/decode phases |
| **usage** | Token count plist (`:prompt-tokens`, `:completion-tokens`, `:total-tokens`) |
| **finish-reason** | Why generation stopped (`:stop`, `:length`, `:tool-calls`, `:content-filter`) |
| **safety-level** | Tool classification (`:safe`, `:moderate`, `:dangerous`) |
| **message history** | Ordered list of messages forming conversation context |

## Code Conventions

### Package Usage

```lisp
;; Always use package prefix or import explicitly
(cl-llm-provider:complete messages)

;; Or use-package
(use-package :cl-llm-provider)
(complete messages)
```

### Naming Patterns

| Pattern | Usage | Example |
|---------|-------|---------|
| `make-*` | Constructor functions | `make-provider`, `make-tool-result` |
| `*name*` | Special variables | `*default-provider*`, `*performance-profiling*` |
| `+name+` | Constants | `+default-config-file-path+` |
| `define-*` | Definition macros | `define-tool` |
| `with-*` | Context macros | `with-provider`, `with-performance-timing` |
| `provider-*` | Provider accessors/methods | `provider-type`, `provider-supports-p` |
| `response-*` | Response accessors | `response-content`, `response-tool-calls` |
| `tool-*` | Tool-related functions | `tool-name`, `tool-calls` |
| `*-error` | Condition names | `provider-api-error`, `tool-schema-error` |
| `error-*` | Condition accessors | `error-message`, `error-status-code` |

### Error Handling

```lisp
;; All library conditions inherit from llm-provider-error
(handler-case (complete messages)
  (provider-api-error (e)
    (format t "API error: ~A~%" (error-message e)))
  (provider-rate-limit-error (e)
    (format t "Rate limited, retry after ~A~%" (error-retry-after e)))
  (llm-provider-error (e)
    (format t "Library error: ~A~%" e)))
```

### Message Construction

```lisp
;; Messages are plists
(list :role "user" :content "Hello")

;; Multi-turn conversation
(list
  (list :role "system" :content "You are helpful.")
  (list :role "user" :content "What is Lisp?")
  (list :role "assistant" :content "Lisp is...")
  (list :role "user" :content "Tell me more."))

;; Tool result message
(list :role "tool"
      :tool-call-id "call_abc123"
      :content "{\"result\": \"success\"}")
```

### Tool Definition

```lisp
;; Basic tool
(define-tool "get_weather"
  "Get current weather for a location"
  '((:name "city" :type :string :description "City name")))

;; Tool with handler
(define-tool "add_numbers"
  "Add two numbers"
  '((:name "a" :type :number)
    (:name "b" :type :number))
  :handler (lambda (args)
             (+ (getf args :a)
                (getf args :b))))
```

## Architecture Rules

### RULE-001: Provider Protocol Implementation

**Rule**: Every `llm-provider` subclass MUST implement ALL required protocol methods.

**Required methods**:
- `send-completion-request`
- `parse-completion-response`
- `send-embedding-request`
- `parse-embedding-response`

**Applies to**: New provider implementations

**Violation**: Runtime error when calling unimplemented method

**Agent action**: Flag missing methods. Auto-fix FORBIDDEN (requires provider-specific logic).

---

### RULE-002: Message Role Validity

**Rule**: Message `:role` MUST be one of `"user"`, `"assistant"`, `"system"`, or `"tool"`.

**Applies to**: All message plists

**Violation**: API error (400 Bad Request)

**Agent action**: Flag invalid roles. Auto-fix allowed (convert keyword to string if applicable).

---

### RULE-003: Tool Name Format

**Rule**: Tool names MUST match pattern `^[a-zA-Z0-9_-]+$` (alphanumeric, underscore, hyphen).

**Applies to**: All `tool-definition` names

**Violation**: Schema validation error or API rejection

**Agent action**: Flag invalid names. Auto-fix FORBIDDEN (semantic decision).

---

### RULE-004: No Mutation of Response Objects

**Rule**: Agent MUST NOT modify slots of `completion-response` or `embedding-response` instances after creation.

**Applies to**: All code receiving response objects

**Rationale**: Responses are immutable snapshots. Mutation breaks debugging and caching.

**Violation**: Unpredictable behavior, broken raw response preservation

**Agent action**: Flag any `setf` on response slots. Auto-fix FORBIDDEN.

---

### RULE-005: API Key Security

**Rule**: API keys MUST NOT appear in:
- Source code literals (except test fixtures marked clearly)
- Log output
- Error messages
- Version control commits

**Applies to**: All code handling API keys

**Violation**: Security vulnerability

**Agent action**: RED FLAG. Human review required.

---

### RULE-006: Message History Ordering

**Rule**: Messages MUST be ordered chronologically (oldest first).

**Applies to**: All message lists passed to `complete`

**Violation**: Nonsensical conversation context or API error

**Agent action**: Flag if detected. Auto-fix FORBIDDEN (semantic decision).

---

### RULE-007: Tool Call ID Correlation

**Rule**: `make-tool-result` MUST use exact `:id` from corresponding `tool-call` object.

**Applies to**: Tool result message creation

**Violation**: API error (400) or tool result silently ignored

**Agent action**: Flag ID mismatches when detectable. Auto-fix FORBIDDEN.

---

### RULE-008: Provider Configuration Before Use

**Rule**: Provider instance MUST have valid configuration (API key for cloud providers, base-url for all) before `complete` or `embedding` call.

**Applies to**: All API calls

**Violation**: `provider-configuration-error` signaled

**Agent action**: Flag missing configuration at provider creation. Auto-fix FORBIDDEN.

---

### RULE-009: Performance Stats Immutability

**Rule**: When `*performance-profiling*` enabled, agent MUST NOT modify `*performance-stats*` outside `with-performance-timing` macro.

**Applies to**: All code in profiling context

**Violation**: Corrupted timing measurements

**Agent action**: Flag direct modifications. Auto-fix FORBIDDEN.

---

### RULE-010: Condition Hierarchy Preservation

**Rule**: All library conditions MUST inherit from `llm-provider-error`.

**Applies to**: New condition definitions

**Violation**: Breaks user error handling assumptions

**Agent action**: Flag violations. Auto-fix allowed (add parent class).

---

### RULE-011: Tool Parameter Type Consistency

**Rule**: Tool parameter `:type` MUST be one of `:string`, `:integer`, `:number`, `:boolean`, `:array`, `:object`.

**Applies to**: `define-tool` parameter specifications

**Violation**: Schema validation error or API rejection

**Agent action**: Flag invalid types. Auto-fix FORBIDDEN (semantic decision).

---

### RULE-012: No Side Effects in Protocol Methods

**Rule**: Protocol methods SHOULD NOT have observable side effects beyond:
- HTTP requests
- Performance profiling updates
- Condition signaling

**Applies to**: `send-completion-request`, `parse-*-response`, `translate-tool-to-provider`

**Violation**: Breaks restart mechanism, unpredictable retry behavior

**Agent action**: Yellow flag. Human review for global state modifications.

---

### RULE-013: Message Content Non-Empty

**Rule**: User and assistant messages MUST have non-empty `:content` string OR `:tool-calls` (assistant only).

**Applies to**: All messages in conversation history

**Violation**: API error (400 Bad Request)

**Agent action**: Flag empty content. Auto-fix FORBIDDEN.

---

### RULE-014: Tool Handler Signature

**Rule**: Tool `:handler` function MUST accept single plist argument (tool arguments) and return serializable value.

**Applies to**: `define-tool` `:handler` option

**Violation**: Execution framework error or unserializable result

**Agent action**: Flag signature mismatches when detectable. Auto-fix FORBIDDEN.

---

### RULE-015: Finish Reason Normalization

**Rule**: `parse-completion-response` MUST normalize finish reason to one of `:stop`, `:length`, `:tool-calls`, `:content-filter`, or provider-specific keyword.

**Applies to**: All provider implementations

**Violation**: User code cannot reliably detect completion status

**Agent action**: Flag missing normalization. Auto-fix allowed (add mapping).

## Invariants

These properties MUST always hold. Mechanically checkable.

### INV-001: Response Raw Preservation

**Statement**: Every response preserves the original provider response.

**Formal**: `∀ response: (response-raw response)` returns original provider response

**Check**: `(hash-table-p (response-raw completion-response-instance))`

**Rationale**: Enables debugging and access to provider-specific features.

---

### INV-002: Usage Token Non-Negative

**Statement**: All token counts in usage are non-negative integers.

**Formal**: `∀ response: (response-usage response)` contains non-negative integers

**Check**:
```lisp
(let ((usage (response-usage response)))
  (and (>= (getf usage :prompt-tokens) 0)
       (>= (getf usage :completion-tokens) 0)
       (>= (getf usage :total-tokens) 0)))
```

**Rationale**: Token counts are cumulative, never negative.

---

### INV-003: Tool Call ID Uniqueness

**Statement**: Tool call IDs are unique within a response.

**Formal**: `∀ response: (response-tool-calls response)` has unique `:id` values

**Check**:
```lisp
(let ((ids (mapcar #'tool-call-id (response-tool-calls response))))
  (= (length ids) (length (remove-duplicates ids :test #'string=))))
```

**Rationale**: ID correlation requires uniqueness per response.

---

### INV-004: Message Role Consistency

**Statement**: Message roles are from a closed set.

**Formal**: `∀ message: (member (getf message :role) '("user" "assistant" "system" "tool") :test #'string=)`

**Check**: Direct member test

**Rationale**: Limited role vocabulary defined by protocol.

---

### INV-005: Provider Type Determinism

**Statement**: Same provider class always returns same default URL.

**Formal**: `∀ provider: (provider-default-base-url provider)` deterministic for type

**Check**: Same provider class instance always returns same default URL

**Rationale**: Enables URL inference from provider type.

---

### INV-006: Performance Stats Keys

**Statement**: When profiling enabled, stats contain exactly the three timing keys.

**Formal**: When `*performance-profiling*` enabled, stats plist contains exactly `:encode-time`, `:api-time`, `:decode-time`

**Check**:
```lisp
(when *performance-profiling*
  (let ((perf (response-performance response)))
    (and (member :encode-time perf)
         (member :api-time perf)
         (member :decode-time perf))))
```

**Rationale**: Defined profiling phases ensure consistent measurement structure.

---

### INV-007: Tool Definition Immutability

**Statement**: Tool definitions should not change after registration.

**Formal**: Once tool added to registry, slots SHOULD NOT change

**Check**: Compare tool snapshots before/after registration

**Rationale**: Prevents mid-conversation schema changes that could confuse LLM.

---

### INV-STREAM-001: Accumulated Content Consistency

**Statement**: Accumulated content equals concatenation of all chunk deltas.

**Formal**:
```lisp
(string= (stream-accumulated-content stream)
         (apply #'concatenate 'string
                (mapcar #'chunk-delta (stream-chunks stream))))
```

**Source**: `docs/agent/streaming-observability-API-SPEC.agent.md`

---

### INV-STREAM-002: Chunk Index Ordering

**Statement**: Chunk indices are sequential starting from 0.

**Formal**:
```lisp
(= (length (stream-chunks stream))
   (loop for i from 0
         for chunk in (stream-chunks stream)
         always (= (chunk-index chunk) i)))
```

**Source**: `docs/agent/streaming-observability-API-SPEC.agent.md`

## API Patterns

### Basic Completion

```lisp
(use-package :cl-llm-provider)

;; Simplest form (uses *default-provider*)
(let ((response (complete '((:role "user" :content "What is Lisp?")))))
  (response-content response))

;; With provider
(let ((provider (make-provider :anthropic :model "claude-3-5-sonnet-20241022")))
  (complete '((:role "user" :content "Hello")) :provider provider))

;; With options
(complete messages
          :provider provider
          :max-tokens 1000
          :temperature 0.7
          :system "You are helpful.")
```

### Multi-Turn Conversation

```lisp
(let ((messages (list (list :role "user" :content "What is 2+2?"))))
  ;; First completion
  (let ((response (complete messages)))
    ;; Add assistant response to history
    (push (response-message response) messages)
    ;; Add next user message
    (push (list :role "user" :content "Add 3 to that?") messages)
    ;; Continue conversation (messages in chronological order)
    (complete (reverse messages))))
```

### Tool Calling

```lisp
;; Define tools
(let* ((weather-tool (define-tool "get_weather"
                       "Get current weather"
                       '((:name "city" :type :string))))
       (tools (list weather-tool)))

  ;; Request with tools
  (let ((response (complete '((:role "user" :content "Weather in Paris?"))
                            :tools tools)))

    ;; Check for tool calls
    (when (response-tool-calls response)
      (let ((tool-results
              (loop for call in (response-tool-calls response)
                    collect (make-tool-result
                             call
                             "{\"temperature\": 20, \"condition\": \"sunny\"}"))))

        ;; Continue with tool results
        (complete (append (list (response-message response))
                          tool-results))))))
```

### Streaming

```lisp
(let ((stream (complete-stream '((:role "user" :content "Tell me a story")))))
  (loop for chunk = (read-stream-chunk stream)
        while chunk
        do (format t "~A" (chunk-delta chunk))
        finally (format t "~%Finish reason: ~A~%" (chunk-finish-reason chunk))))
```

### Provider Introspection

```lisp
;; Check capabilities before use
(let ((provider (make-provider :anthropic)))
  (when (provider-supports-p provider :tools)
    (complete messages :tools my-tools :provider provider)))

;; Get model metadata
(let* ((provider (make-provider :openai))
       (meta (model-metadata provider "gpt-4o")))
  (format t "Context: ~D tokens~%" (getf meta :context-window))
  (format t "Cost: $~,2F per 1M input~%" (getf meta :input-cost-per-1m-tokens)))

;; Provider summary
(provider-config-summary provider)
```

### Error Handling

```lisp
(handler-case
    (complete messages)

  (provider-rate-limit-error (e)
    (format t "Rate limited, retry after ~A seconds~%" (error-retry-after e))
    (sleep (error-retry-after e))
    (complete messages)) ; Retry

  (provider-authentication-error (e)
    (format t "Auth failed: ~A~%" (error-message e))
    nil)

  (provider-api-error (e)
    (format t "API error ~A: ~A~%" (error-status-code e) (error-body e))
    nil))
```

### Observability Hooks

```lisp
;; Global hooks for all requests
(setf *global-hooks*
      (make-logging-hooks :log-level :debug))

;; Per-request hooks
(complete messages
          :hooks (make-hooks
                  :on-request (lambda (provider req)
                                (format t "Sending to ~A~%" (provider-name provider)))
                  :on-response (lambda (provider resp)
                                 (format t "Received ~A tokens~%"
                                         (getf (response-usage resp) :total-tokens)))
                  :on-error (lambda (provider err)
                              (format t "Error: ~A~%" err))))
```

## Dependencies

| Library | Purpose | Required |
|---------|---------|----------|
| **alexandria** | General utilities | Yes |
| **serapeum** | Additional utilities | Yes |
| **dexador** | HTTP client | Yes |
| **yason** | JSON parsing | Yes |
| **bordeaux-threads** | Thread safety | Yes |
| **cl-ppcre** | Regular expressions | Yes |
| **uiop** | OS interface | Yes |
| **fiveam** | Testing | Test only |

## Testing Strategy

**Test count**: 423 tests, 100% passing

**Test files**:
- `test-provider-protocols.lisp` - Protocol implementation
- `test-token-metadata-comprehensive.lisp` - Token counting, metadata
- `test-tools-support.lisp` - Tool definitions, validation
- `test-tools-enhanced.lisp` - Advanced tool features
- `test-tools-integration.lisp` - Tool calling workflows
- `test-streaming.lisp` - Streaming responses
- `test-observability.lisp` - Hooks, profiling
- `test-provider-introspection.lisp` - Capabilities, metadata
- `test-gemini-provider.lisp` - Gemini-specific tests

**Run pattern**:
```bash
sbcl --noinform --non-interactive --load tests/test-{name}.lisp
```

## Verification Checklist

When making changes:

```
[ ] All protocol methods implemented for new providers (RULE-001)
[ ] All tool names match ^[a-zA-Z0-9_-]+$ (RULE-003)
[ ] No API keys in source code or logs (RULE-005)
[ ] Messages chronologically ordered (RULE-006)
[ ] Tool call IDs preserved in results (RULE-007, INV-003)
[ ] Response objects never mutated after creation (RULE-004)
[ ] All conditions inherit from llm-provider-error (RULE-010)
[ ] Tool parameter types valid (RULE-011)
[ ] Finish reasons normalized to standard keywords (RULE-015)
[ ] Usage token counts non-negative (INV-002)
[ ] Performance stats structure preserved (INV-006)
[ ] Message roles valid (INV-004)
[ ] All tests pass
[ ] New features have tests
[ ] Documentation updated
```

## Additional Resources

| Resource | Purpose |
|----------|---------|
| **canon/** | Behavioral specification (contracts, scenarios, properties) |
| **docs/agent/core-SPEC.agent.md** | Detailed agent specification |
| **docs/agent/core-API-SPEC.agent.md** | API formal specification |
| **docs/agent/metadata-API-SPEC.agent.md** | Metadata/introspection specification |
| **docs/agent/streaming-observability-API-SPEC.agent.md** | Streaming specification |
| **README.md** | Human-oriented overview |
| **docs/** | Human-oriented documentation |

---

*Generated from Canon specification on 2026-01-21*
