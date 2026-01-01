# Tutorial: Basic Completions and Conversations

Learn to send messages, build conversations, and control response behavior.

**What you'll learn**:
- How to send a simple completion request
- Build multi-turn conversations
- Use system messages for context
- Control response parameters

**Prerequisites**: [Quickstart](../quickstart.md) complete and API key set.

---

## Understanding Messages

In cl-llm-provider, conversations are lists of **messages**. Each message is a property list (plist) with `:role` and `:content`:

```lisp
'((:role "user" :content "What is Lisp?"))
```

Roles are:
- **`"user"`** - Messages from the person/application
- **`"assistant"`** - Messages from the LLM
- **`"system"`** (optional) - Instructions for the LLM

## Single Turn: One Question, One Answer

The simplest completion:

```lisp
(use-package :cl-llm-provider)

(let ((response (complete '((:role "user" :content "What is 2+2?")))))
  (format t "~A~%" (response-content response)))
```

This returns a `completion-response` object. Access its fields:

```lisp
(let ((response (complete '((:role "user" :content "What is Lisp?")))))
  ;; Get the text content
  (format t "Content: ~A~%" (response-content response))

  ;; Get full message (with role)
  (format t "Message: ~A~%" (response-message response))

  ;; Get response metadata
  (format t "Model: ~A~%" (response-model response))
  (format t "Stop reason: ~A~%" (response-finish-reason response)))
```

## Multi-Turn: Building Conversations

To build context across multiple turns, pass a growing list of messages:

```lisp
(let* (;; Turn 1: ask a question
       (turn-1 (complete '((:role "user" :content "What is 2+2?"))))

       ;; Turn 2: add the response and ask a follow-up
       (turn-2 (complete (list '(:role "user" :content "What is 2+2?")
                               (response-message turn-1)
                               '(:role "user" :content "Add 3 to that number"))))

       ;; Turn 3: continue the conversation
       (turn-3 (complete (list '(:role "user" :content "What is 2+2?")
                               (response-message turn-1)
                               '(:role "user" :content "Add 3 to that number")
                               (response-message turn-2)
                               '(:role "user" :content "Multiply by 2")))))

  (format t "Turn 1: ~A~%" (response-content turn-1))
  (format t "Turn 2: ~A~%" (response-content turn-2))
  (format t "Turn 3: ~A~%" (response-content turn-3)))
```

**Key principle**: Always pass the **full conversation history** (not just the last exchange) so the LLM understands context.

## System Messages: Giving Instructions

Use system messages to set behavior, tone, or expertise:

```lisp
;; Tell Claude to act as a translator
(complete '((:role "user" :content "Translate to French: Hello world"))
         :system "You are a professional translator. Respond with only the translation.")

;; Tell Claude to be a mathematician
(complete '((:role "user" :content "Solve: x^2 - 5x + 6 = 0"))
         :system "You are a mathematician. Show your work step by step.")

;; Tell Claude to be concise
(complete '((:role "user" :content "What is the history of the internet?"))
         :system "Be concise. Answer in 1-2 sentences.")
```

System messages work across all providers. The library normalizes them to each provider's format.

## Controlling Response Parameters

Adjust model behavior with optional parameters:

```lisp
(complete messages
  ;; Temperature: 0 = deterministic, 1 = creative
  :temperature 0.5

  ;; Max tokens: limit response length
  :max-tokens 100

  ;; Stop sequences: stop generation at these strings
  :stop '("END" "---")

  ;; System message: model instructions
  :system "You are a helpful assistant"

  ;; Model override: use a different model
  :model "claude-3-sonnet-20240229"

  ;; Provider override: use a different provider
  :provider (make-provider :openai :model "gpt-4"))
```

### Parameter Guide

| Parameter | Range | Default | Use Case |
|-----------|-------|---------|----------|
| `:temperature` | 0.0–1.0 | 1.0 | Lower = predictable, Higher = creative |
| `:max-tokens` | 1–4096+ | Provider default | Limit response length for cost savings |
| `:stop` | List of strings | `nil` | Stop generation at keywords |
| `:system` | String | `nil` | Set model behavior/role |
| `:model` | String | Provider default | Override default model |

### Temperature Examples

```lisp
;; Deterministic (facts, calculations)
(complete messages :temperature 0.1)

;; Balanced (most use cases)
(complete messages :temperature 0.7)

;; Creative (brainstorming, writing)
(complete messages :temperature 1.0)
```

## Building a Chat Loop

Here's a complete chat program that reads user input and maintains conversation:

```lisp
(use-package :cl-llm-provider)

(defun chat-loop (&optional system-message)
  "Interactive chat. Type 'quit' to exit."
  (let ((messages '()))
    (loop
      (format t "You: ")
      (finish-output)
      (let ((user-input (read-line)))
        (when (string= user-input "quit")
          (return))

        ;; Add user message
        (push (list :role "user" :content user-input) messages)

        ;; Get response
        (let ((response (complete (reverse messages)
                                 :system system-message)))
          ;; Add assistant message
          (push (response-message response) messages)

          ;; Display response
          (format t "Assistant: ~A~%~%" (response-content response)))))))

;; Start a chat with custom instructions
(chat-loop "You are a helpful programming assistant. Be concise.")
```

## Checking Response Metadata

Every response includes metadata about the completion:

```lisp
(let ((response (complete '((:role "user" :content "What is Lisp?")))))
  ;; Content
  (format t "Text: ~A~%" (response-content response))

  ;; Model and provider info
  (format t "Model: ~A~%" (response-model response))
  (format t "Provider: ~A~%" (response-provider response))

  ;; Stop reason: :stop (normal), :length (max-tokens hit), etc.
  (format t "Stop reason: ~A~%" (response-finish-reason response))

  ;; Token usage
  (format t "Tokens used: ~A~%" (response-token-count response)))
```

## Common Patterns

### Asking for Specific Formats

```lisp
;; Get JSON response
(complete '((:role "user"
             :content "Return this as JSON: {name: 'Alice', age: 30}"))
         :system "Always respond with valid JSON only.")

;; Get structured output
(complete '((:role "user"
             :content "List 3 reasons why Lisp is great"))
         :system "Format as numbered list. Be concise.")
```

### Error Handling (Basic)

```lisp
(handler-case
  (let ((response (complete messages)))
    (format t "~A~%" (response-content response)))
  (error (e)
    (format t "Error: ~A~%" e)))
```

See [How-To: Error Handling](../how-to/error-handling.md) for advanced error recovery.

## Checkpoint: What You Can Now Do

- ✅ Send single-turn completions
- ✅ Build multi-turn conversations with full history
- ✅ Use system messages for behavior control
- ✅ Adjust temperature, tokens, and stop sequences
- ✅ Read response metadata

## Next Steps

- **Learn tool calling**: [Tutorial: Tool Calling](02-tool-calling.md)
- **Explore advanced features**: [Tutorial: Advanced Features](03-advanced.md)
- **See patterns**: [Explanation: How the Protocol Works](../explanation/architecture.md)

---

**Prev**: [Quickstart](../quickstart.md) | **Next**: [Tool Calling](02-tool-calling.md)
