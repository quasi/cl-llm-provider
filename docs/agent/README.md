# Agent-Oriented Documentation

Formal specifications for LLM agents and automated code assistants.

This directory contains machine-optimized documentation intended for:
- LLM-based code agents and assistants
- Automated reasoning systems
- Formal verification and testing
- Integration with Claude Code and similar tools

## Documents

**Entry Point**: [../../AGENT.md](../../AGENT.md) - Start here for workflows and quick reference

### Core Library

| Document | Purpose |
|----------|---------|
| **[core-SPEC.agent.md](core-SPEC.agent.md)** | Normative specification with 15 rules, 7 invariants, 5 anti-patterns, and verification checklist |
| **[core-PATTERNS.agent.md](core-PATTERNS.agent.md)** | 14 complete, runnable code patterns covering all major workflows |
| **[core-API-SPEC.agent.md](core-API-SPEC.agent.md)** | Formal method signatures, type specs, preconditions/postconditions, provider details, and state machines |

### Metadata & Introspection

| Document | Purpose |
|----------|---------|
| **[metadata-API-SPEC.agent.md](metadata-API-SPEC.agent.md)** | 10 normative rules, 5 invariants, 10 complete patterns for metadata/introspection API |

### Streaming & Observability

| Document | Purpose |
|----------|---------|
| **[streaming-observability-PATTERNS.agent.md](streaming-observability-PATTERNS.agent.md)** | Complete patterns for streaming responses and observability hooks |
| **[streaming-observability-API-SPEC.agent.md](streaming-observability-API-SPEC.agent.md)** | Formal API specification for streaming and observability |

## For Human Readers

If you're a human developer, see the **[Human-Oriented Documentation](../quickstart.md)** instead:

- **[Quick Start](../quickstart.md)** - Get running in 5 minutes
- **[Tutorials](../tutorials/)** - Progressive learning
- **[How-To Guides](../how-to/)** - Task-oriented
- **[Explanation](../explanation/)** - Conceptual understanding
- **[Reference](../reference/)** - API and migration

---

**See Also**: [Complete Documentation Index](../quickstart.md)
