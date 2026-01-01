---
type: specification
version: 1.0.0
applies-to: [cl-llm-provider]
library-type: common-lisp
audience: llm-agents
---

# cl-llm-provider Agent Specification

Unified Common Lisp interface for LLM provider APIs. Protocol-based design with provider-agnostic message handling, tool calling, and error recovery.

## Scope & Applicability

**Applies to**: All code modifications, extensions, and integrations with cl-llm-provider

**Coverage**:
- Provider implementations (Anthropic, OpenAI, Ollama, OpenRouter, OpenAI-compatible)
- Protocol generic functions (`send-completion-request`, `parse-completion-response`, etc.)
- Tool definitions and tool calling workflows
- Message normalization and conversation management
- Error handling and condition system
- Configuration and API key management
- Performance profiling infrastructure

**Does NOT cover**:
- Application-level tool execution logic (user responsibility)
- Conversation memory/history persistence (user responsibility)
- Streaming responses (deferred to v2+)
- Audio/video/image processing (deferred to v2+)
- Cost tracking or rate limiting (deferred to v2+)

## Terminology

Define once, use consistently:

- **provider**: Instance of `llm-provider` subclass representing API connection to LLM service
- **completion**: Text generation request/response cycle via `complete` function
- **embedding**: Vector representation request/response cycle via `embedding` function
- **message**: Plist representing single conversation turn (`:role`, `:content`, optional `:tool-calls`, `:tool-call-id`)
- **tool-definition**: Specification of callable function (name, description, parameters, optional handler)
- **tool-call**: LLM's request to invoke specific tool with arguments
- **tool-result**: Response message containing tool execution output
- **protocol method**: Generic function specialized per provider type
- **response object**: `completion-response` or `embedding-response` instance
- **normalization**: Converting provider-specific formats to unified representation
- **raw-response**: Provider's original HTTP response body (hash-table)
- **performance-profiling**: Timing collection for encode/API/decode phases
- **metadata**: Provider-specific response data (timing, fingerprints, stop sequences)
- **usage**: Token count plist (`:prompt-tokens`, `:completion-tokens`, `:total-tokens`)
- **finish-reason**: Why generation stopped (`:stop`, `:length`, `:tool-calls`, `:content-filter`)
- **safety-level**: Tool classification (`:safe`, `:moderate`, `:dangerous`)
- **message history**: Ordered list of messages forming conversation context

## Normative Rules

### RULE-001: Provider Protocol Implementation

**Rule**: Every `llm-provider` subclass MUST implement ALL required protocol methods.

**Applies to**: New provider implementations

**Required methods**:
```lisp
send-completion-request
parse-completion-response
send-embedding-request
parse-embedding-response
```

**Rationale**: Ensures consistent behavior across all providers.

**Violation consequence**: Runtime error when calling unimplemented protocol method.

**Agent action**: Flag missing methods. Auto-fix forbidden (requires provider-specific logic).

---

### RULE-002: Message Role Validity

**Rule**: Message `:role` MUST be one of `"user"`, `"assistant"`, `"system"`, or `"tool"`.

**Applies to**: All message plists passed to `complete`

**Rationale**: Provider APIs reject invalid roles.

**Violation consequence**: API error (400 Bad Request).

**Agent action**: Flag invalid roles. Auto-fix allowed (convert keyword to string if applicable).

---

### RULE-003: Tool Name Format

**Rule**: Tool names MUST match pattern `^[a-zA-Z0-9_-]+$` (alphanumeric, underscore, hyphen).

**Applies to**: All `tool-definition` names

**Rationale**: Provider APIs have naming restrictions. OpenAI rejects invalid patterns.

**Violation consequence**: Tool schema validation error or API rejection.

**Agent action**: Flag invalid names. Auto-fix forbidden (semantic decision).

---

### RULE-004: No Mutation of Response Objects

**Rule**: Agent MUST NOT modify slots of `completion-response` or `embedding-response` instances after creation.

**Applies to**: All code receiving response objects

**Rationale**: Responses are immutable snapshots. Mutation breaks debugging and caching assumptions.

**Violation consequence**: Unpredictable behavior, broken raw response preservation.

**Agent action**: Flag any `setf` on response slots. Auto-fix forbidden.

---

### RULE-005: API Key Security

**Rule**: API keys MUST NOT appear in:
- Source code literals (except test fixtures marked clearly)
- Log output
- Error messages
- Version control commits

**Applies to**: All code handling API keys

**Rationale**: Security best practice. Prevents credential leakage.

**Violation consequence**: Security vulnerability.

**Agent action**: Red flag. Human review required.

---

### RULE-006: Message History Ordering

**Rule**: Messages MUST be ordered chronologically (oldest first).

**Applies to**: All message lists passed to `complete`

**Rationale**: Conversation context must flow in temporal order. Providers reject misordered messages.

**Violation consequence**: Nonsensical conversation context or API error.

**Agent action**: Flag if detected. Auto-fix forbidden (semantic decision).

---

### RULE-007: Tool Call ID Correlation

**Rule**: `make-tool-result` MUST use exact `:id` from corresponding `tool-call` object.

**Applies to**: Tool result message creation

**Rationale**: Providers correlate results to calls via ID. Mismatch causes API error or ignored results.

**Violation consequence**: API error (400) or tool result silently ignored.

**Agent action**: Flag ID mismatches when detectable. Auto-fix forbidden.

---

### RULE-008: Provider Configuration Before Use

**Rule**: Provider instance MUST have valid configuration (API key for cloud providers, base-url for all) before `complete` or `embedding` call.

**Applies to**: All API calls

**Rationale**: Prevents runtime configuration errors.

**Violation consequence**: `provider-configuration-error` signaled.

**Agent action**: Flag missing configuration at provider creation. Auto-fix forbidden.

---

### RULE-009: Performance Stats Immutability

**Rule**: When `*performance-profiling*` is enabled, agent MUST NOT modify `*performance-stats*` outside `with-performance-timing` macro.

**Applies to**: All code in profiling context

**Rationale**: Performance data integrity.

**Violation consequence**: Corrupted timing measurements.

**Agent action**: Flag direct modifications. Auto-fix forbidden.

---

### RULE-010: Condition Hierarchy Preservation

**Rule**: All library conditions MUST inherit from `llm-provider-error`.

**Applies to**: New condition definitions

**Rationale**: Allows user code to catch all library errors with single handler.

**Violation consequence**: Breaks user error handling assumptions.

**Agent action**: Flag violations. Auto-fix allowed (add parent class).

---

### RULE-011: Tool Parameter Type Consistency

**Rule**: Tool parameter `:type` MUST be one of `:string`, `:integer`, `:number`, `:boolean`, `:array`, `:object`.

**Applies to**: `define-tool` parameter specifications

**Rationale**: Maps to JSON Schema types. Providers reject unknown types.

**Violation consequence**: Schema validation error or API rejection.

**Agent action**: Flag invalid types. Auto-fix forbidden (semantic decision).

---

### RULE-012: No Side Effects in Protocol Methods

**Rule**: Protocol methods SHOULD NOT have observable side effects beyond:
- HTTP requests
- Performance profiling updates
- Condition signaling

**Applies to**: `send-completion-request`, `parse-*-response`, `translate-tool-to-provider`

**Rationale**: Enables retry, testing, memoization.

**Violation consequence**: Breaks restart mechanism, unpredictable retry behavior.

**Agent action**: Yellow flag. Human review for global state modifications.

---

### RULE-013: Message Content Non-Empty

**Rule**: User and assistant messages MUST have non-empty `:content` string OR `:tool-calls` (assistant only).

**Applies to**: All messages in conversation history

**Rationale**: Empty content causes API errors. Providers require substance.

**Violation consequence**: API error (400 Bad Request).

**Agent action**: Flag empty content. Auto-fix forbidden.

---

### RULE-014: Tool Handler Signature

**Rule**: Tool `:handler` function MUST accept single plist argument (tool arguments) and return serializable value.

**Applies to**: `define-tool` `:handler` option

**Rationale**: Consistent execution interface. Return value becomes tool result content.

**Violation consequence**: Execution framework error or unserializable result.

**Agent action**: Flag signature mismatches when detectable. Auto-fix forbidden.

---

### RULE-015: Finish Reason Normalization

**Rule**: `parse-completion-response` MUST normalize finish reason to one of `:stop`, `:length`, `:tool-calls`, `:content-filter`, or provider-specific keyword.

**Applies to**: All provider implementations

**Rationale**: Enables provider-agnostic completion status checking.

**Violation consequence**: User code cannot reliably detect completion status.

**Agent action**: Flag missing normalization. Auto-fix allowed (add mapping).

## Invariants

### INV-001: Response Raw Preservation
`∀ response: (response-raw response)` returns original provider response
**Check**: `(hash-table-p (response-raw completion-response-instance))`
**Rationale**: Debugging, provider-specific feature access

---

### INV-002: Usage Token Non-Negative
`∀ response: (response-usage response)` contains non-negative integers
**Check**:
```lisp
(let ((usage (response-usage response)))
  (and (>= (getf usage :prompt-tokens) 0)
       (>= (getf usage :completion-tokens) 0)
       (>= (getf usage :total-tokens) 0)))
```
**Rationale**: Token counts are cumulative, never negative

---

### INV-003: Tool Call ID Uniqueness
`∀ response: (response-tool-calls response)` has unique `:id` values
**Check**:
```lisp
(let ((ids (mapcar #'tool-call-id (response-tool-calls response))))
  (= (length ids) (length (remove-duplicates ids :test #'string=))))
```
**Rationale**: ID correlation requires uniqueness per response

---

### INV-004: Message Role Consistency
`∀ message: (member (getf message :role) '("user" "assistant" "system" "tool") :test #'string=)`
**Check**: Direct member test
**Rationale**: Limited role vocabulary defined by protocol

---

### INV-005: Provider Type Determines Default URL
`∀ provider: (provider-default-base-url provider)` deterministic for type
**Check**: Same provider class always returns same default URL
**Rationale**: Enables URL inference from provider type

---

### INV-006: Performance Stats Keys
When `*performance-profiling*` enabled, stats plist contains exactly `:encode-time`, `:api-time`, `:decode-time`
**Check**:
```lisp
(when *performance-profiling*
  (let ((perf (response-performance response)))
    (and (member :encode-time perf)
         (member :api-time perf)
         (member :decode-time perf))))
```
**Rationale**: Defined profiling phases

---

### INV-007: Tool Definition Immutability After Registration
Once tool added to registry, slots SHOULD NOT change
**Check**: Compare tool snapshots before/after registration
**Rationale**: Prevents mid-conversation schema changes

## Anti-Patterns

### ANTI-001: Manual Message History Concatenation

**Description**: Building conversation by string concatenation instead of message list.

**Symptoms**:
```lisp
;; WRONG
(complete (list (list :role "user"
                      :content (format nil "~A~%~A" prev-msg new-msg))))
```

**Why harmful**: Loses turn structure, breaks tool calling, prevents proper context management.

**Remediation**: Maintain message list:
```lisp
;; RIGHT
(setf messages (append messages
                       (list (list :role "user" :content new-msg))))
(complete messages)
```

**Agent action**: Red flag. Suggest message list pattern.

---

### ANTI-002: Ignoring Finish Reason

**Description**: Not checking `response-finish-reason` before assuming completion.

**Symptoms**:
```lisp
;; WRONG - assumes content exists
(let ((text (response-content response)))
  (process text))  ; fails when finish-reason is :tool-calls
```

**Why harmful**: Tool calls return nil content. Length limit truncates mid-sentence.

**Remediation**:
```lisp
;; RIGHT
(case (response-finish-reason response)
  (:stop (process (response-content response)))
  (:tool-calls (handle-tool-calls (response-tool-calls response)))
  (:length (warn "Truncated response")))
```

**Agent action**: Yellow flag. Suggest finish-reason check.

---

### ANTI-003: Hardcoded Provider Logic

**Description**: Conditional logic based on provider type in user code.

**Symptoms**:
```lisp
;; WRONG
(if (typep provider 'anthropic-provider)
    (format-anthropic-way ...)
    (format-openai-way ...))
```

**Why harmful**: Defeats provider abstraction. Breaks when adding providers.

**Remediation**: Use protocol methods or provider-agnostic response accessors.

**Agent action**: Red flag. Suggest protocol-based design.

---

### ANTI-004: Discarding Tool Call IDs

**Description**: Not preserving `:id` from `tool-call` when creating result.

**Symptoms**:
```lisp
;; WRONG
(make-tool-result "fake-id-123" result)
```

**Why harmful**: Breaks tool call correlation. API rejects or ignores result.

**Remediation**:
```lisp
;; RIGHT
(make-tool-result (tool-call-id call) result)
```

**Agent action**: Red flag when hardcoded ID detected.

---

### ANTI-005: Synchronous Retry Without Backoff

**Description**: Tight retry loop on rate limit without delay.

**Symptoms**:
```lisp
;; WRONG
(loop repeat 10 do (ignore-errors (complete messages)))
```

**Why harmful**: Amplifies rate limiting, wastes quota, extends lock contention.

**Remediation**: Use restarts with backoff or invoke `wait-and-retry` restart.

**Agent action**: Red flag. Suggest exponential backoff or restart mechanism.

## Allowed Transformations

| Transform | Scope | Conditions |
|-----------|-------|------------|
| Add provider subclass | New file in `src/providers/` | Must implement all protocol methods |
| Add tool parameter | `tool-definition` parameters list | Must include `:name`, `:type`, `:description` |
| Add condition subclass | `src/conditions.lisp` | Must inherit from `llm-provider-error` or descendant |
| Normalize message format | Protocol methods | Preserve semantic content, convert to canonical form |
| Add metadata field | Response `:metadata` plist | Provider-specific data only, document in docstring |
| Add performance metric | Performance plist | Must use `with-performance-timing` macro |
| Add tool hook | `define-tool` | Must match hook signature (`:on-start`, `:on-complete`, `:on-error`) |
| Add tool category | Tool `:categories` list | Keyword symbol, document in tool registry |

## Forbidden Transformations

| Transform | Reason |
|-----------|--------|
| Modify protocol generic function signatures | Breaks all provider implementations |
| Remove slots from response classes | Breaks user code accessing standard fields |
| Change message role vocabulary | Incompatible with provider APIs |
| Mutate response object after creation | Violates immutability contract |
| Remove condition types | Breaks user error handlers |
| Change tool parameter `:type` keywords | Breaks provider schema translation |
| Add required protocol methods | Breaks existing provider implementations |
| Change `*performance-stats*` structure | Breaks profiling analysis code |
| Modify finish-reason normalization mapping | Breaks user completion status checks |

## Ambiguity Resolution

Precedence (highest first):

1. **Invariants** - Always true, mechanically checkable
2. **Normative Rules (MUST)** - Absolute requirements
3. **Provider API Constraints** - External system requirements (OpenAI spec, Anthropic spec, etc.)
4. **Normative Rules (SHOULD)** - Strong recommendations
5. **Anti-Pattern Avoidance** - Proven problematic structures
6. **Existing Protocol Contracts** - Established generic function behavior
7. **Common Lisp Idioms** - Language-level best practices
8. **Performance** - Efficiency when semantics preserved

**Ambiguity remains after precedence**: Agent MUST defer to human input.

## Machine Checklist

```
[ ] All protocol methods implemented for new providers
[ ] All tool names match ^[a-zA-Z0-9_-]+$
[ ] No API keys in source code or logs
[ ] Messages chronologically ordered
[ ] Tool call IDs preserved in results
[ ] Response objects never mutated after creation
[ ] All conditions inherit from llm-provider-error
[ ] Tool parameter types valid (:string, :integer, :number, :boolean, :array, :object)
[ ] Finish reasons normalized to standard keywords
[ ] Usage token counts non-negative
[ ] Performance stats structure preserved when profiling enabled
[ ] Message roles valid ("user", "assistant", "system", "tool")
```

## Integration with Other Documents

- **PATTERNS.agent.md**: Exemplar code patterns demonstrating these rules
- **API-SPEC.agent.md**: Detailed protocol specifications and type contracts
