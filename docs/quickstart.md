# Quickstart: Your First LLM Completion

Get a working LLM completion in 5 minutes. No configuration needed.

## Prerequisites

- SBCL (any recent version)
- An API key from Anthropic, OpenAI, or Ollama (we default to Anthropic)
- 5 minutes

## Step 1: Install

```bash
# Clone the repository
git clone https://github.com/quasi/cl-llm-provider.git
cd cl-llm-provider

# Or via Quicklisp (when available)
sbcl --eval '(ql:quickload :cl-llm-provider)'
```

## Step 2: Set Your API Key

```bash
# For Anthropic (Claude) - the default
export ANTHROPIC_API_KEY="sk-ant-..."

# Or for OpenAI (GPT-4, etc.)
export OPENAI_API_KEY="sk-..."

# Or for local Ollama (no key needed)
export OLLAMA_BASE_URL="http://localhost:11434"
```

## Step 3: Run Your First Completion

Create a file called `first-completion.lisp`:

```lisp
(asdf:load-system :cl-llm-provider)
(use-package :cl-llm-provider)

;; Ask Claude a question
(let ((response (complete '((:role "user" :content "What is 2+2?")))))
  (format t "Answer: ~A~%" (response-content response)))
```

Run it:

```bash
sbcl --noinform --non-interactive --load first-completion.lisp
```

Expected output:

```
Answer: 2+2 equals 4.
```

**That's it!** You have working LLM completions. Your code is provider-agnostic—change the API key and it switches providers automatically.

## Step 4: Try Something Slightly More Complex

Build a two-turn conversation:

```lisp
(asdf:load-system :cl-llm-provider)
(use-package :cl-llm-provider)

;; First turn: ask a question
(let* ((turn-1 (complete '((:role "user" :content "What is the capital of France?"))))
       ;; Second turn: follow up
       (turn-2 (complete (list '(:role "user" :content "What is the capital of France?")
                               (response-message turn-1)
                               '(:role "user" :content "What's its population?")))))
  (format t "Final answer: ~A~%" (response-content turn-2)))
```

Run it the same way:

```bash
sbcl --noinform --non-interactive --load two-turn.lisp
```

## Common Variations

**Switch providers without changing code:**

```lisp
;; Use OpenAI instead
(complete messages :provider (make-provider :openai :model "gpt-4"))

;; Use Ollama instead
(complete messages :provider (make-provider :ollama :model "mistral"))
```

**Control response behavior:**

```lisp
(complete messages
  :max-tokens 100        ; Limit response length
  :temperature 0.7       ; 0 = deterministic, 1 = creative
  :stop '("END")         ; Stop generation at keyword
  :system "You are a helpful assistant.")
```

## Next Steps

- **Learn the basics**: [Tutorial: Basic Completions](tutorials/01-basics.md)
- **Master tool calling**: [Tutorial: Tool Calling](tutorials/02-tool-calling.md)
- **Explore advanced features**: [Tutorial: Advanced Features](tutorials/03-advanced.md)
- **See a complete example**: [Chat with Tools Example](examples/CHAT_WITH_TOOLS.md)

## Troubleshooting

**Error: `API key not found`**

Make sure your environment variable is set:

```bash
export ANTHROPIC_API_KEY="your-key-here"
echo $ANTHROPIC_API_KEY  # Verify it's set
```

**Error: `Connection refused`**

If using Ollama, make sure it's running:

```bash
# macOS
brew services start ollama

# Linux
ollama serve
```

**Error: `Unknown provider`**

Check that you're using a valid provider symbol: `:anthropic`, `:openai`, `:ollama`, `:openrouter`, etc.

## What You Can Do Now

- ✅ Send messages to any LLM provider
- ✅ Build multi-turn conversations
- ✅ Control response temperature, token limits, and stopping
- ✅ Switch providers without rewriting code

To use tool calling, embeddings, error handling, and advanced features, continue with the tutorials.

---

**Next**: [Tutorial: Basic Completions](tutorials/01-basics.md)
