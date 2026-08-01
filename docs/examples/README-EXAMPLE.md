# Example Chat Application Files

This directory contains a complete, beginner-friendly tutorial and working example for building chat applications with `cl-llm-provider`.

## Files

1. **example-chat.md** (545 lines) - Complete beginner tutorial
   - Step-by-step guide from installation to deployment
   - Progressive learning path with working examples
   - Covers all major features: providers, streaming, tools, error handling

2. **example-chat.lisp** (460 lines) - Standalone, runnable chat application
   - Multi-provider support (Ollama, OpenAI, Claude, Gemini)
   - Function calling (tools) demonstration
   - Streaming responses
   - Interactive command system
   - Complete implementation ready to use

3. **example-chat-tests.lisp** (290 lines) - FiveAM test suite
   - Comprehensive test coverage
   - Tests for providers, completion, history, tools, streaming
   - Includes error handling tests
   - Ready to run

## Quick Start

### Load and Run the Chat

```lisp
;; Install dependencies
(ql:quickload :cl-llm-provider)
(ql:quickload :str)

;; Load the application
(load "example-chat.lisp")

;; Start chatting!
(example-chat:start-chat)
```

### Run the Tests

```lisp
;; Load everything
(ql:quickload :fiveam)
(ql:quickload :cl-llm-provider)
(ql:quickload :str)
(load "example-chat.lisp")
(load "example-chat-tests.lisp")

;; Run all tests
(example-chat-tests:run-tests)

;; Or use FiveAM directly
(5am:run! 'example-chat-tests:all-tests)
```

## Prerequisites

### For Ollama (Recommended for First-Time Users)

1. Install Ollama: https://ollama.ai
2. Start the server:
   ```bash
   ollama serve
   ```
3. Pull a model:
   ```bash
   ollama pull llama3.2
   ```

### For Cloud Providers (Optional)

Set environment variables:

```bash
export OPENAI_API_KEY=sk-your-key-here
export ANTHROPIC_API_KEY=sk-ant-your-key-here
export GEMINI_API_KEY=your-key-here
```

Or create a `.env` file (see `.env.template`).

## Features Demonstrated

### In example-chat.lisp:

- [x] Multi-provider support with hot-swapping
- [x] Conversation history management
- [x] Function calling (weather and time tools)
- [x] Streaming responses
- [x] Token usage tracking
- [x] Interactive command system
- [x] Error handling
- [x] Observability hooks

### In example-chat-tests.lisp:

- [x] Provider creation tests
- [x] Basic completion tests
- [x] Conversation history tests
- [x] Tool definition tests
- [x] Tool calling tests
- [x] Streaming tests
- [x] Error handling tests
- [x] Provider switching tests

## Usage Examples

### Simple Chat

```lisp
(example-chat:chat "What is the capital of France?")
=> "The capital of France is Paris."
```

### With Streaming

```lisp
(example-chat:chat-stream "Tell me a short story")
;; Output appears word-by-word as generated
```

### Switch Providers

```lisp
(example-chat:switch-provider :openai)
(example-chat:chat "Hello!")  ; Uses OpenAI

(example-chat:switch-provider :claude)
(example-chat:chat "Hello!")  ; Uses Claude
```

### Clear History

```lisp
(example-chat:clear-messages)
```

## Tutorial Path

Read `example-chat.md` for the full tutorial. It guides you through:

1. Installing the library
2. Setting up your first provider (Ollama)
3. Understanding the basics (providers, messages, responses)
4. Adding cloud providers (OpenAI, Claude, Gemini)
5. Building a chat loop
6. Adding function calling (tools)
7. Implementing streaming
8. Tracking token usage
9. Advanced topics and deployment

## File Independence

All three files are standalone:

- `example-chat.md` can be read independently as a tutorial
- `example-chat.lisp` runs without any other files (just needs the library)
- `example-chat-tests.lisp` only depends on `example-chat.lisp`

No additional project structure needed - just load and run!

## Verified Working

Both code files load successfully, given the prerequisites from Quick Start above
(`cl-llm-provider` and `str` quickloaded first — `example-chat.lisp` needs both
before it can be `load`ed):

```bash
$ sbcl --non-interactive \
    --eval '(ql:quickload :cl-llm-provider)' \
    --eval '(ql:quickload :str)' \
    --load example-chat.lisp
...
; example-chat.lisp loaded, no errors

$ sbcl --non-interactive \
    --eval '(ql:quickload :cl-llm-provider)' \
    --eval '(ql:quickload :str)' \
    --eval '(ql:quickload :fiveam)' \
    --load example-chat.lisp \
    --load example-chat-tests.lisp \
    --eval '(example-chat-tests:run-tests)'
...
; both files loaded, test suite runs (needs a local Ollama model pulled
; for the completion/streaming tests to pass rather than skip)
```

## Submit to Library Examples

These files are ready to be submitted to the `cl-llm-provider` library examples directory. They provide:

1. **Complete documentation** - Beginners can learn from scratch
2. **Working code** - Copy-paste examples that run immediately
3. **Test coverage** - Verify everything works
4. **Progressive complexity** - From "hello world" to advanced features

## Questions?

- Read the tutorial: `example-chat.md`
- Run the example: `(load "example-chat.lisp") (example-chat:start-chat)`
- Check the tests: `(load "example-chat-tests.lisp") (example-chat-tests:run-tests)`

Everything you need is included!
