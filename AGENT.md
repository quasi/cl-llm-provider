# Agent Instructions for cl-llm-provider

**Entry point for LLM agents working with cl-llm-provider.**

## System Overview

`cl-llm-provider` is a unified Common Lisp interface for multiple LLM providers (Claude, GPT, Gemini, Ollama, OpenRouter). Protocol-based design with provider-agnostic messages, tool calling, and error recovery.

**Architecture**: Protocol-based system where each provider implements 4 required protocol methods. Messages and tools normalized to unified format, converted to provider-specific formats at request time.

## Quick Orientation

| When You Need To... | Go Here |
|---------------------|---------|
| Understand rules, invariants, constraints | [Core Specification](docs/agent/core-SPEC.agent.md) |
| See working code patterns | [Core Patterns](docs/agent/core-PATTERNS.agent.md) |
| Look up function signatures | [Core API Specification](docs/agent/core-API-SPEC.agent.md) |
| Work with metadata/introspection API | [Metadata API Specification](docs/agent/metadata-API-SPEC.agent.md) |
| Implement streaming or observability | [Streaming/Observability Patterns](docs/agent/streaming-observability-PATTERNS.agent.md), [API Spec](docs/agent/streaming-observability-API-SPEC.agent.md) |

## Critical Rules (Read First)

Before modifying code, internalize these:

### RULE-001: Protocol Implementation
Every `llm-provider` subclass MUST implement ALL 4 protocol methods:
- `send-completion-request`
- `parse-completion-response`
- `send-embedding-request`
- `parse-embedding-response`

### RULE-002: Message Role Validity
Message `:role` MUST ∈ `{"user", "assistant", "system", "tool"}`

### RULE-003: Tool Name Format
Tool names MUST match `^[a-zA-Z0-9_-]+$`

### RULE-004: Message History Ordering
Messages MUST be chronologically ordered (oldest first).

### RULE-005: Tool-Result Pairing
Every tool-call message MUST have matching tool-result in next turn.

**See** [core-SPEC.agent.md](docs/agent/core-SPEC.agent.md) for all 15 rules and 7 invariants.

## Common Workflows

### Adding a New Provider

1. **Read**: [PATTERN-001: New Provider Implementation](docs/agent/core-PATTERNS.agent.md#pattern-001-new-provider-implementation)
2. **Implement**: All 4 protocol methods
3. **Test**: Provider tests + integration tests
4. **Document**: Update provider table in README.md

### Implementing Tool Calling

1. **Read**: [PATTERN-003: Tool Definition](docs/agent/core-PATTERNS.agent.md#pattern-003-tool-definition)
2. **Follow**: OpenAI parameter schema format
3. **Verify**: Tool name matches `^[a-zA-Z0-9_-]+$`
4. **Test**: With multiple providers

### Adding Error Recovery

1. **Read**: [PATTERN-004: Error Handling with Restarts](docs/agent/core-PATTERNS.agent.md#pattern-004-error-handling-with-restarts)
2. **Use**: Condition system with restarts
3. **Follow**: INV-006 (always signal conditions, never return error indicators)
4. **Test**: Retry, skip, and manual-retry restarts

## Architecture Entry Points

| Subsystem | Key Files | Patterns |
|-----------|-----------|----------|
| **Protocol** | `src/protocol.lisp` | PATTERN-001 |
| **Providers** | `src/providers/{anthropic,openai,ollama,openrouter,openai-compatible}.lisp` | PATTERN-001, PATTERN-002 |
| **Tools** | `src/tools.lisp` | PATTERN-003, PATTERN-004, PATTERN-005 |
| **Error Handling** | `src/conditions.lisp`, `src/recovery.lisp` | PATTERN-004 |
| **Config** | `src/config.lisp` | PATTERN-008 |
| **Metadata** | `src/model-registry.lisp` | [Metadata API Spec](docs/agent/metadata-API-SPEC.agent.md) |
| **Observability** | `src/observability.lisp` | [Streaming/Observability Patterns](docs/agent/streaming-observability-PATTERNS.agent.md) |

## Invariants (Never Violate)

These conditions MUST hold at all times:

- **INV-001**: Provider instance immutable after creation
- **INV-002**: Messages chronologically ordered
- **INV-003**: Tool-call → tool-result pairing maintained
- **INV-004**: Response objects contain valid usage data
- **INV-005**: API keys never logged or exposed
- **INV-006**: Errors signaled as conditions (not returned)
- **INV-007**: Thread-safe concurrent requests

**See** [core-SPEC.agent.md](docs/agent/core-SPEC.agent.md) for complete invariant specifications and verification checks.

## Anti-Patterns (Forbidden)

- **ANTI-001**: Returning error indicators instead of signaling conditions
- **ANTI-002**: Mutating provider instances after creation
- **ANTI-003**: Assuming provider capabilities without checking
- **ANTI-004**: Ignoring `finish-reason` when processing responses
- **ANTI-005**: Exposing API keys in logs or error messages

**See** [core-SPEC.agent.md](docs/agent/core-SPEC.agent.md) for remediation strategies.

## Testing Strategy

**Test hierarchy** (confidence pyramid):
1. **Unit tests** - Individual functions, message normalization, token counting
2. **Provider tests** - Protocol implementation, request/response parsing
3. **Integration tests** - Multi-turn conversations, tool calling workflows
4. **Error recovery tests** - Condition signaling, restart handling

**Run tests**:
```bash
sbcl --noinform --non-interactive --load tests/test-tools-support.lisp
sbcl --noinform --non-interactive --load tests/test-provider-protocols.lisp
sbcl --noinform --non-interactive --load tests/test-token-metadata-comprehensive.lisp
```

**Current status**: 452 tests, 100% passing

## Package Structure

```lisp
:cl-llm-provider          ; Main package - complete/embedding/make-provider, configuration,
                          ; conditions/restarts, metadata/introspection
:cl-llm-provider.tools    ; Enhanced tool functionality - validators, registry, approval,
                          ; hooks, execution (register-tool, execute-tool, etc.)
:cl-llm-provider/test     ; Test suite
```

**Key exports**:
- Core API: `complete`, `embedding`, `complete-stream`, `make-provider`
- Tools: `define-tool`, `tool-calls`, `make-tool-result`
- Enhanced tools: `register-tool`, `execute-tool`, `validate-tool-arguments` (from :cl-llm-provider.tools)
- Configuration: `*default-provider*`, `load-configuration-from-file`, `configure-defaults`
- Conditions: All error/warning types exported from :cl-llm-provider
- Metadata: `model-metadata`, `provider-capabilities`, `provider-supports-p`
- Observability: `make-hooks`, `add-hook`, `*global-hooks*`

**Naming convention**: Predicates end in `-p`, constructors use `make-*`, converters use `*-to-*` or `normalize-*`.

## Code Review Checklist

Before committing code:

```
[ ] All 15 normative rules satisfied (run /cobra-lisp-reviewer)
[ ] All 7 invariants hold
[ ] Zero anti-patterns introduced
[ ] Tests pass (423/423)
[ ] No API keys in code or test output
[ ] Documentation updated (human + agent)
[ ] Code examples verified with mcp__lisp__evaluate-lisp
```

## Essential Verification Commands

```lisp
;; Check if function exists before documenting
(mcp__lisp__describe-symbol "complete" "cl-llm-provider")

;; Verify code example compiles
(mcp__lisp__compile-form "(complete '((:role \"user\" :content \"test\")))")

;; Execute and verify output
(mcp__lisp__evaluate-lisp "(list :test t)")

;; Find all uses of a function
(mcp__lisp__who-calls "normalize-messages")
```

## Documentation Maintenance

When updating agent documentation:

1. **Verify all facts**: Use Grep/Glob/Read to confirm function names, signatures, file paths
2. **Execute code examples**: Use mcp__lisp tools to verify every example runs
3. **Check links**: Ensure all markdown links resolve (see Navigation Audit below)
4. **Run nitpicker**: `/nitpicker <doc-path> --tier execute` after changes

## Navigation Audit

**Critical**: Verify all documentation links resolve.

```bash
# Check project links
grep -r '\[.*\](.*\.md)' README.md docs/agent/README.md
# Then use Glob to verify each path exists
```

**Current known links**:
- README.md → docs/agent/README.md ✓
- README.md → docs/agent/{core-SPEC,core-PATTERNS,core-API-SPEC}.agent.md (needs fixing)
- docs/agent/README.md → docs/agent/{core-SPEC,core-PATTERNS,core-API-SPEC}.agent.md (needs fixing)

## Upstream/Downstream Dependencies

**Upstream**: None (self-contained library)

**Downstream**:
- `ghost` project uses cl-llm-provider for LLM interactions
- After changing cl-llm-provider, verify ghost still works

**Before declaring work complete**: Run ghost's tests or notify maintainer.

## Development Workflow

1. **Read**: Relevant patterns in [core-PATTERNS.agent.md](docs/agent/core-PATTERNS.agent.md)
2. **Write tests**: TDD - write failing test first
3. **Implement**: Minimal code to pass test
4. **Verify**: Run test suite
5. **Review**: `/cobra-lisp-reviewer` on modified files
6. **Stage**: `git add <specific-files>` (never `git add -A`)
7. **Commit**: Clear message describing change
8. **Check downstream**: Verify ghost project unaffected

## When Stuck

1. **Search for similar code**: `grep -r 'pattern' .`
2. **Check existing patterns**: Read 2-3 similar files
3. **Use REPL**: `mcp__lisp__evaluate-lisp` for interactive exploration
4. **Read tests**: `tests/` directory has working examples
5. **Ask Baba**: "I tried X, Y, Z. Expected A, got B. Why?"

## Human-Oriented Documentation

For architectural understanding and design rationale, see:
- [Quick Start](docs/quickstart.md) - Get running in 5 minutes
- [Architecture Explanation](docs/explanation/architecture.md) - How the system works
- [Provider Guide](docs/explanation/providers.md) - Understanding each provider

---

**Summary**: This is a protocol-based LLM provider abstraction layer. Read [core-SPEC.agent.md](docs/agent/core-SPEC.agent.md) for rules, [core-PATTERNS.agent.md](docs/agent/core-PATTERNS.agent.md) for working code, [core-API-SPEC.agent.md](docs/agent/core-API-SPEC.agent.md) for signatures. Follow the workflows above. Test everything. Ask when uncertain.
