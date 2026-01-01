# Explanation: Understanding Providers

What each provider offers and how to choose.

---

## Provider Comparison

| Provider | Best For | Cost | Speed | Local | Notes |
|----------|----------|------|-------|-------|-------|
| **Anthropic** (Claude) | Writing, reasoning, long context | $3-15/M tokens | Medium | No | Best reasoning, long context window |
| **OpenAI** (GPT-4, 3.5) | General purpose | $0.03-30/M tokens | Fast | No | Most popular, wide model variety |
| **Ollama** | Local, private, offline | Free | Variable | Yes | Run locally, no API key needed |
| **OpenRouter** | Multi-provider, cheap | Variable | Variable | No | Routes to cheapest provider |
| **Groq** | Speed-optimized | $0.005/M tokens | Very fast | No | Specialized for speed |

## Anthropic (Claude)

**Best for**: Writing, analysis, reasoning, long documents

**Models**:
- `claude-3-opus-20250219` - Best reasoning, larger context
- `claude-3-sonnet-20240229` - Balanced, good for most tasks
- `claude-3-haiku-20240307` - Fast and cheap

**Features**:
- ✅ Tool calling (native)
- ❌ Embeddings (not supported)
- ✅ Token counting (accurate)
- ✅ Large context window (100K-200K tokens)

**Setup**:
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

```lisp
(complete messages :provider (make-provider :anthropic))
```

**Cost estimate**: $3/M tokens (Claude 3 Sonnet)

## OpenAI (GPT-4, GPT-3.5)

**Best for**: General purpose, fast responses, embeddings

**Models**:
- `gpt-4` - Most capable
- `gpt-4-turbo` - Larger context, faster
- `gpt-3.5-turbo` - Cheap and fast
- `o1` - Reasoning (slow, expensive)

**Features**:
- ✅ Tool calling (function calling)
- ✅ Embeddings
- ✅ Token counting (accurate)
- ✅ Fine-tuning support

**Setup**:
```bash
export OPENAI_API_KEY="sk-..."
```

```lisp
(complete messages :provider (make-provider :openai))
```

**Cost estimate**: $0.03-30/M tokens (varies by model)

## Ollama (Local)

**Best for**: Private, offline, testing, development

**Models** (run locally):
- `mistral` - Balanced, good quality
- `llama2` - Popular, good reasoning
- `neural-chat` - Optimized for conversation
- Custom models

**Features**:
- ✅ Completely local (no API calls)
- ✅ Free (runs on your machine)
- ✅ OpenAI-compatible API
- ❌ Limited reasoning capability
- ✅ Good for testing/development

**Setup**:

```bash
# Install Ollama from https://ollama.ai
# Start Ollama
ollama serve

# In another terminal, pull a model
ollama pull mistral
```

```lisp
(complete messages :provider (make-provider :ollama :model "mistral"))
```

**Cost**: Free (runs on your hardware)

## OpenRouter

**Best for**: Trying multiple models, cost optimization, avoiding vendor lock-in

**Why use it**:
- Single API for 100+ models
- Automatic routing to cheapest provider
- Try Claude, GPT-4, Llama, Mistral, etc. with one API key

**Setup**:
```bash
export OPENROUTER_API_KEY="sk-..."
```

```lisp
(complete messages :provider (make-provider :openrouter))
```

## OpenAI-Compatible APIs

**Best for**: Self-hosted models, providers that mimic OpenAI

**Includes**:
- **Groq** - Specialized for speed
- **vLLM** - Self-hosted inference
- **LM Studio** - Local GUI interface
- **Text Generation WebUI** - Self-hosted UI
- Any OpenAI-compatible implementation

**Setup**:
```lisp
;; Groq
(complete messages :provider (make-provider :openai-compatible
                                           :base-url "https://api.groq.com/openai/v1"
                                           :api-key "gsk-..."))

;; Self-hosted
(complete messages :provider (make-provider :openai-compatible
                                           :base-url "http://localhost:8000/v1"
                                           :api-key "anything"))
```

## Choosing a Provider

### Quick Decision Tree

**Need to run locally?**
→ **Ollama**

**Need embeddings?**
→ **OpenAI** or **OpenRouter**

**Best reasoning/writing?**
→ **Anthropic** (Claude)

**Want to try many models?**
→ **OpenRouter**

**Need maximum speed?**
→ **Groq** (via OpenAI-compatible)

**Cost-conscious?**
→ **OpenRouter** (automatic optimization)

### By Use Case

**Customer-facing application**:
- Primary: **OpenAI GPT-4** (reliable, fast)
- Fallback: **Anthropic Claude 3 Sonnet** (good reasoning)

**Internal tooling**:
- **Ollama** (free, private, offline)
- Fallback to **OpenRouter** for complex tasks

**Prototyping**:
- **Ollama** locally
- Or **OpenRouter** to try multiple models quickly

**Research/Analysis**:
- **Anthropic Claude** (best reasoning)
- Or **OpenAI o1** (reasoning model)

**Writing/Creative**:
- **Anthropic Claude** (best writing quality)

**High-volume processing**:
- **Groq** (fastest)
- Or **OpenRouter** with cost optimization

## Provider Costs at a Glance

**For 1M tokens of API usage**:

| Provider | Cost | Speed | Best For |
|----------|------|-------|----------|
| Ollama | $0 | Varies | Local/offline |
| OpenRouter (cheapest) | $0.15 | Medium | Cost optimization |
| OpenRouter (Claude) | $3 | Medium | Reasoning |
| OpenAI GPT-3.5 | $0.50 | Fast | General |
| OpenAI GPT-4 | $30 | Medium | Capability |
| Groq | $0.005 | Fast | Speed |
| Anthropic Claude 3 Haiku | $0.25 | Medium | Budget |
| Anthropic Claude 3 Sonnet | $3 | Medium | Balanced |

## Multi-Provider Strategy

Use different providers for different tasks:

```lisp
(defun complete-optimized (messages &key task)
  "Choose provider based on task."
  (case task
    ;; Fast responses: use Groq
    (:fast (complete messages :provider (make-provider :openai-compatible
                                                      :base-url "https://api.groq.com/openai/v1")))

    ;; Writing/reasoning: use Claude
    (:writing (complete messages :provider (make-provider :anthropic)))

    ;; Budget: use OpenAI GPT-3.5
    (:budget (complete messages :provider (make-provider :openai
                                                        :model "gpt-3.5-turbo")))

    ;; Default: try OpenAI, fall back to Claude
    (t (handler-case
         (complete messages :provider (make-provider :openai))
         (error (e)
           (complete messages :provider (make-provider :anthropic)))))))
```

## Testing Provider Integration

Before deploying, test with:

1. **Development**: Ollama (free, offline)
2. **Staging**: OpenRouter (cheap, multi-model)
3. **Production**: Primary provider + fallback

```lisp
(defvar *provider-config*
  (list
   :development (make-provider :ollama :model "mistral")
   :staging (make-provider :openrouter)
   :production (make-provider :anthropic)))

(defun get-provider-for-environment ()
  (getf *provider-config* (or (getenv "APP_ENV") :development)))
```

## Provider Features Supported by cl-llm-provider

| Feature | Anthropic | OpenAI | Ollama | OpenRouter |
|---------|-----------|--------|--------|-----------|
| Completions | ✅ | ✅ | ✅ | ✅ |
| Tool calling | ✅ Native | ✅ Function | ✅ OpenAI format | ✅ |
| Embeddings | ❌ | ✅ | ✅ | ✅ |
| Token counting | ✅ | ✅ | ⚠️ Approximate | Varies |
| System messages | ✅ | ✅ | ✅ | ✅ |
| Temperature | ✅ | ✅ | ✅ | ✅ |
| Max tokens | ✅ | ✅ | ✅ | ✅ |
| Stop sequences | ✅ | ✅ | ✅ | ✅ |

---

**See Also**:
- [Tutorial: Basic Completions](../tutorials/01-basics.md)
- [Quickstart](../quickstart.md)
- [Explanation: How It Works](architecture.md)
