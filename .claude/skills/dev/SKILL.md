---
name: cl-llm-provider-dev
description: Development workflow for the cl-llm-provider LLM abstraction library
version: 1.0.0
author: quasiLabs
type: dev
---

# cl-llm-provider Dev Skill

## What is cl-llm-provider

A unified Common Lisp interface for multiple LLM providers (Claude, GPT, Gemini, Ollama, OpenRouter). Protocol-based design with provider-agnostic messages, tool calling, streaming, observability, and error recovery via the condition/restart system.

## Quick Reference

```lisp
;; Load the system
(ql:quickload :cl-llm-provider)

;; Verify a symbol
(mcp__lisp__describe-symbol "complete" "cl-llm-provider")
```

```bash
# Run tests
sbcl --noinform --non-interactive --load tests/test-tools-support.lisp
sbcl --noinform --non-interactive --load tests/test-provider-protocols.lisp
```

## Package Structure

| Package | Purpose |
|---------|---------|
| `:cl-llm-provider` | Main — complete/embedding/make-provider, config, conditions/restarts, metadata |
| `:cl-llm-provider.tools` | Tools — validators, registry, approval, hooks, execution |
| `:cl-llm-provider/test` | Test suite |

**Naming**: Predicates `-p`, constructors `make-*`, converters `*-to-*` or `normalize-*`.

## Architecture

| Subsystem | Key Files |
|-----------|-----------|
| Protocol | `src/protocol.lisp` — 4 required methods per provider |
| Providers | `src/providers/{anthropic,openai,ollama,openrouter,openai-compatible}.lisp` |
| Tools | `src/tools.lisp` — definition, validation, execution |
| Errors | `src/conditions.lisp`, `src/recovery.lisp` — condition/restart based |
| Config | `src/config.lisp` |
| Metadata | `src/model-registry.lisp` |
| Observability | `src/observability.lisp` — hooks and streaming |

## Critical Rules (R001-R005)

- **R001**: Every `llm-provider` subclass MUST implement ALL 4 protocol methods
- **R002**: Message `:role` MUST be one of `"user"`, `"assistant"`, `"system"`, `"tool"`
- **R003**: Tool names MUST match `^[a-zA-Z0-9_-]+$`
- **R004**: Messages MUST be chronologically ordered (oldest first)
- **R005**: Every tool-call message MUST have matching tool-result in next turn

Full 15 rules, 7 invariants: `.claude/skills/integration/references/core-spec.md`

## Invariants (Never Violate)

- INV-001: Provider instance immutable after creation
- INV-002: Messages chronologically ordered
- INV-003: Tool-call / tool-result pairing maintained
- INV-004: Response objects contain valid usage data
- INV-005: API keys never logged or exposed
- INV-006: Errors signaled as conditions (not returned)
- INV-007: Thread-safe concurrent requests

## Anti-Patterns (Forbidden)

- Return error indicators instead of signaling conditions
- Mutate provider instances after creation
- Assume capabilities without checking
- Ignore `finish-reason` when processing responses
- Expose API keys in logs or error messages

## Common Workflows

**Adding a provider**: Implement 4 protocol methods. Read PATTERN-001 in integration references.
**Tool calling**: Follow OpenAI parameter schema format. Verify name regex. Read PATTERN-003.
**Error recovery**: Use condition/restart system. Follow INV-006. Read PATTERN-004.

## Testing Strategy

1. Unit tests — message normalization, token counting
2. Provider tests — protocol implementation, request/response parsing
3. Integration tests — multi-turn conversations, tool calling
4. Error recovery tests — condition signaling, restart handling

## Code Review Checklist

- [ ] All 15 normative rules satisfied
- [ ] All 7 invariants hold
- [ ] No anti-patterns introduced
- [ ] Tests pass
- [ ] No API keys in code or test output

## Canon Specification

Full formal specification: `canonical-specification/`

## References

Detailed specs and patterns in `.claude/skills/integration/references/`:
- `core-spec.md` — 15 rules, 7 invariants, 5 anti-patterns
- `core-api-spec.md` — protocol contracts, method signatures
- `core-patterns.md` — 14 runnable code patterns
- `metadata-api-spec.md` — provider introspection API
- `streaming-api-spec.md` — streaming/observability API
- `streaming-patterns.md` — streaming patterns

## Consumers

- **ghost** and **agent-q** depend on this library
- Verify downstream projects after changes
