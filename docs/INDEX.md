# Documentation Index

Complete index of all cl-llm-provider documentation.

## Quick Navigation

**New to cl-llm-provider?**
→ Start with [Quick Start](quickstart.md)

**Want to learn progressively?**
→ Follow the [Tutorials](tutorials/)

**Have a specific problem to solve?**
→ See [How-To Guides](how-to/)

**Want to understand how it works?**
→ Read [Explanation](explanation/)

**Looking up API details?**
→ Check the [Reference](reference/)

---

## Complete Documentation Map

### Entry Points

| Document | Purpose | Time |
|----------|---------|------|
| [Quickstart](quickstart.md) | Get running in 5 minutes | 5 min |
| [Tutorial: Basics](tutorials/01-basics.md) | Learn how to send messages and build conversations | 15 min |
| [Tutorial: Tool Calling](tutorials/02-tool-calling.md) | Learn to define tools and let LLMs use them | 20 min |
| [Tutorial: Advanced](tutorials/03-advanced.md) | Token counting, profiling, embeddings, error handling | 20 min |

### How-To Guides (Task-Oriented)

| Document | Purpose |
|----------|---------|
| [Using Gemini Provider](how-to/using-gemini.md) | Setup, vision, models, patterns for Google Gemini |
| [Tools: Advanced Features](how-to/tools.md) | Safety levels, validators, categories, approvals |
| [Add a New Provider](how-to/add-provider.md) | Implement support for a new LLM provider |
| [Error Handling](how-to/error-handling.md) | Rate limits, retries, circuit breakers, graceful degradation |
| [Local Models and Failover](how-to/local-models-and-failover.md) | Local OpenAI-compatible endpoints, failing over to a hosted provider |
| [Streaming](how-to/streaming.md) | Real-time streaming responses, callbacks, state management |
| [Observability](how-to/observability.md) | Logging, metrics, request/response hooks |
| [Testing](how-to/testing.md) | Unit tests, integration tests, mocking, performance tests |

### Explanation (Conceptual)

| Document | Purpose |
|----------|---------|
| [Architecture](explanation/architecture.md) | How the protocol works, provider dispatch, message normalization |
| [Providers](explanation/providers.md) | Comparison of each provider, costs, features, choosing |

### Reference (Lookup)

| Document | Purpose |
|----------|---------|
| [Complete API](reference/api.md) | All functions, parameters, response objects, error types |
| [Migration Guide](reference/migration.md) | Upgrading from old versions or other libraries |

### Examples

| Document | Purpose |
|----------|---------|
| [Chat with Tools](examples/CHAT_WITH_TOOLS.md) | Complete interactive chat session with enhanced tools |

### Agent-Oriented Specs

For LLM agents and automated code assistants.

| Document | Purpose |
|----------|---------|
| [Agent: Specification](agent/SPEC.agent.md) | Normative rules, invariants, verification checklist |
| [Agent: Patterns](agent/PATTERNS.agent.md) | 14 complete, runnable patterns for all workflows |
| [Agent: API Spec](agent/API-SPEC.agent.md) | Formal method signatures, types, preconditions, state machines |

See [agent/README.md](agent/README.md) for agent documentation index.

---

## Learning Paths

### Path 1: Absolute Beginner (30 minutes)

1. [Quickstart](quickstart.md) (5 min) - Get something working
2. [Tutorial: Basics](tutorials/01-basics.md) (15 min) - Understand messages and conversations
3. [Reference: API](reference/api.md) (10 min) - Look up what you need

**Result**: You can send messages to any LLM provider.

### Path 2: Building with Tools (90 minutes)

1. [Tutorial: Basics](tutorials/01-basics.md) (15 min)
2. [Tutorial: Tool Calling](tutorials/02-tool-calling.md) (20 min) - Define and use tools
3. [How-To: Advanced Tools](how-to/tools.md) (30 min) - Safety, validation, approval
4. [How-To: Error Handling](how-to/error-handling.md) (20 min) - Robust applications
5. [How-To: Testing](how-to/testing.md) (10 min) - Test your code

**Result**: You can build tool-using agents.

### Path 3: Architecture & Customization (2 hours)

1. [Explanation: Architecture](explanation/architecture.md) (20 min) - How it works
2. [Explanation: Providers](explanation/providers.md) (15 min) - Provider comparison
3. [Tutorial: Advanced](tutorials/03-advanced.md) (20 min) - Profiling, embeddings
4. [How-To: Add Provider](how-to/add-provider.md) (40 min) - Custom providers
5. [Reference: API](reference/api.md) (25 min) - Complete details

**Result**: You understand the design and can extend it.

### Path 4: Migration (30 minutes)

1. [Reference: Migration Guide](reference/migration.md) (30 min) - Upgrade existing code

**Result**: Your existing code works with the new version.

---

## By Topic

### Completions
- [Tutorial: Basics](tutorials/01-basics.md)
- [Reference: API - `complete`](reference/api.md#complete)

### Messages & Conversations
- [Tutorial: Basics](tutorials/01-basics.md) - Building multi-turn conversations
- [Reference: API - Message Building](reference/api.md#message-building)

### Tool Calling
- [Tutorial: Tool Calling](tutorials/02-tool-calling.md)
- [How-To: Advanced Tools](how-to/tools.md)
- [How-To: Testing](how-to/testing.md) - Test tools
- [Reference: API - Tool Functions](reference/api.md#tool-functions)

### Embeddings
- [Tutorial: Advanced](tutorials/03-advanced.md) - Embeddings section
- [Reference: API - `embedding`](reference/api.md#embedding)

### Token Counting
- [Tutorial: Advanced](tutorials/03-advanced.md) - Token counting section
- [Reference: API - `token-count`](reference/api.md#token-count)

### Performance Profiling
- [Tutorial: Advanced](tutorials/03-advanced.md) - Performance profiling section
- [Reference: API - Profiling](reference/api.md#profiling)

### Error Handling
- [How-To: Error Handling](how-to/error-handling.md)
- [Reference: API - Error Types](reference/api.md#error-types)

### Providers
- [How-To: Using Gemini](how-to/using-gemini.md) - Google Gemini setup and patterns
- [Explanation: Providers](explanation/providers.md) - Compare providers
- [How-To: Add Provider](how-to/add-provider.md) - Implement new provider
- [Reference: API - Provider Functions](reference/api.md#provider-functions)

### Configuration
- [Reference: API - Configuration](reference/api.md#configuration)

### Testing
- [How-To: Testing](how-to/testing.md)

---

## Troubleshooting

**"I don't know where to start"**
→ Go to [Quickstart](quickstart.md)

**"I want to learn systematically"**
→ Follow [Tutorials](tutorials/) in order

**"I know what I want to do but not how"**
→ Check [How-To Guides](how-to/)

**"I want to understand the design"**
→ Read [Explanation](explanation/)

**"I'm looking up a specific API"**
→ Use [Reference](reference/)

**"I'm upgrading from an old version"**
→ See [Migration Guide](reference/migration.md)

**"I'm an LLM agent reading this"**
→ Go to [Agent Specs](agent/)

---

## File Structure

```
docs/
├── INDEX.md                     # This file
├── quickstart.md                # 5-minute getting started
│
├── tutorials/                   # Progressive learning
│   ├── 01-basics.md            # Basic completions and conversations
│   ├── 02-tool-calling.md      # Tool definition and usage
│   └── 03-advanced.md          # Advanced features
│
├── how-to/                      # Task-oriented guides
│   ├── using-gemini.md         # Google Gemini provider guide
│   ├── tools.md                # Advanced tool features
│   ├── add-provider.md         # Implement new provider
│   ├── configuration.md        # Providers, defaults, environment
│   ├── error-handling.md       # Error patterns
│   ├── local-models-and-failover.md  # Local endpoints and failover
│   ├── streaming.md            # Streaming responses
│   ├── observability.md        # Logging and metrics
│   └── testing.md              # Testing guide
│
├── explanation/                 # Conceptual understanding
│   ├── architecture.md         # How the system works
│   └── providers.md            # Provider comparison
│
├── reference/                   # API documentation
│   ├── api.md                 # Complete API reference
│   └── migration.md           # Upgrading existing code
│
├── examples/                    # Complete examples
│   └── CHAT_WITH_TOOLS.md     # Interactive chat example
│
└── agent/                       # Machine-optimized specs
    ├── README.md              # Agent docs index
    ├── SPEC.agent.md          # Formal specification
    ├── PATTERNS.agent.md      # Runnable patterns
    └── API-SPEC.agent.md      # Formal API spec
```

---

**Quick Links**:
- [Quickstart](quickstart.md) - Start here
- [Tutorials](tutorials/) - Learn step-by-step
- [How-To](how-to/) - Solve specific problems
- [Reference](reference/api.md) - Look up APIs
