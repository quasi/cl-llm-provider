# cl-llm-provider Canon

Unified Common Lisp interface for multiple LLM provider APIs (Anthropic, OpenAI, Ollama, OpenRouter)

## What is This?

This is a **Canon** - a complete, authoritative specification of the cl-llm-provider system.
The Canon defines what the system does (behavior), not how it does it (implementation).

This Canon was **extracted from the existing implementation** as the authoritative specification.
The implementation already exists and this Canon documents its behavior for:
- Verification of conformance
- Future evolution and refactoring
- Alternative implementations
- Documentation generation

## Structure

```
cl-llm-provider-canon/
├── canon.yaml          # Manifest: metadata, features list
├── core/               # Shared definitions
│   ├── foundation/     # Vocabulary, ontology, invariants
│   ├── contracts/      # Shared data types
│   └── context/        # Cross-cutting decisions
├── features/           # Feature-specific specifications
│   ├── core-api/       # Main user-facing API (complete, embedding)
│   ├── providers/      # Provider implementations (Anthropic, OpenAI, etc.)
│   ├── tools/          # Tool definition and execution system
│   ├── streaming/      # Streaming completion support
│   └── model-metadata/ # Model registry and metadata system
└── verification/       # Integration and system tests
```

## Features

### core-api
Main user-facing API providing `complete` and `embedding` functions with provider abstraction.

### providers
Multi-provider support for Anthropic, OpenAI, Ollama, OpenRouter, and OpenAI-compatible APIs.

### tools
Tool definition, validation, approval workflows, and execution with safety levels and lifecycle hooks.

### streaming
Streaming completion responses with chunk-by-chunk reading support.

### model-metadata
Model registry, capability introspection, token counting, and cost estimation.

## Using the Canon

- **Verify Implementation**: Use `canon-verify` skill to ensure implementation conforms
- **Evolve Specification**: Use `canon-evolve` skill for changes
- **Generate Documentation**: Use `canon-document` skill for human-oriented docs

## Initiation Status

This Canon was initialized from an existing codebase using multi-pass extraction:

- **Pass 1 (Structural)**: In progress
- **Pass 2 (Contracts)**: Pending
- **Pass 3 (Behaviors)**: Pending
- **Pass 4 (Properties)**: Pending

All extracted artifacts are marked `[DRAFT]` and require human review.
See `.canon-initiation/observations.yaml` for items needing decisions.

---

*This Canon was bootstrapped on 2026-01-16 from the cl-llm-provider implementation.*
