# Provider Configuration

This guide explains how to configure API keys and base URLs for different providers in `cl-llm-provider`.

## Configuration Priority

Configuration values are resolved in this order (highest to lowest priority):

1. **Explicit arguments** to `make-provider` - highest priority
2. **Environment variables** - checked automatically when creating providers
3. **Configuration file** - opt-in only via `load-configuration-from-file`

## Quick Start

### Using Environment Variables (Recommended)

Set environment variables for the providers you use:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export GEMINI_API_KEY="your-gemini-key"
export OPENROUTER_API_KEY="sk-or-..."
export OLLAMA_BASE_URL="http://localhost:11434"
```

Then create providers without explicitly passing credentials:

```lisp
;; Reads ANTHROPIC_API_KEY from environment automatically
(make-provider :anthropic :model "claude-3-5-sonnet-20241022")

;; Reads OPENAI_API_KEY from environment
(make-provider :openai :model "gpt-4")

;; Ollama doesn't require an API key
(make-provider :ollama :model "llama3")
```

### Using Explicit Arguments

You can also pass credentials directly:

```lisp
(make-provider :openai
               :api-key "sk-..."
               :base-url "https://api.openai.com/v1"
               :model "gpt-4")
```

### Using a Configuration File

For more complex setups, create `~/.config/cl-llm-provider/config.lisp`:

```lisp
;; Set environment variables
(setenv "ANTHROPIC_API_KEY" "sk-ant-...")
(setenv "OPENAI_API_KEY" "sk-...")

;; Or configure defaults
(configure-defaults
  :default-provider :anthropic
  :default-model "claude-3-5-sonnet-20241022"
  :default-temperature 0.7)

;; Run arbitrary Lisp code during initialization
(push :my-custom-feature *features*)
```

Then explicitly load it in your code:

```lisp
(load-configuration-from-file :path "~/.config/cl-llm-provider/config.lisp"
                               :verbose t)
```

See `config.lisp.example` in the project root for a complete template.

## Provider-Specific Configuration

### Anthropic

| Setting | Value |
|---------|-------|
| **Environment Variable** | `ANTHROPIC_API_KEY` |
| **Default Base URL** | `https://api.anthropic.com/v1` |
| **API Key Required** | Yes |

```lisp
(make-provider :anthropic :model "claude-3-5-sonnet-20241022")
```

### OpenAI

| Setting | Value |
|---------|-------|
| **Environment Variable** | `OPENAI_API_KEY` |
| **Default Base URL** | `https://api.openai.com/v1` |
| **API Key Required** | Yes |

```lisp
(make-provider :openai :model "gpt-4")
```

### Gemini

| Setting | Value |
|---------|-------|
| **Environment Variable** | `GEMINI_API_KEY` |
| **Default Base URL** | `https://generativelanguage.googleapis.com/v1beta/openai/` |
| **API Key Required** | Yes |

```lisp
(make-provider :gemini :model "gemini-2.0-flash")
```

### OpenRouter

| Setting | Value |
|---------|-------|
| **Environment Variable** | `OPENROUTER_API_KEY` |
| **Default Base URL** | `https://openrouter.ai/api/v1` |
| **API Key Required** | Yes |

```lisp
(make-provider :openrouter :model "openai/gpt-4")
```

### Ollama

| Setting | Value |
|---------|-------|
| **Environment Variable** | None (API key not needed) |
| **Default Base URL** | `http://localhost:11434` |
| **Environment Override** | `OLLAMA_BASE_URL` |
| **API Key Required** | No |

```lisp
;; Uses default localhost
(make-provider :ollama :model "llama3")

;; Or specify a remote Ollama server
(make-provider :ollama
               :base-url "http://remote-host:11434"
               :model "llama3")
```

### OpenAI-Compatible

For custom OpenAI-compatible endpoints, you must provide both API key and base URL explicitly:

```lisp
(make-provider :openai-compatible
               :api-key "your-api-key"
               :base-url "https://your-endpoint.com/v1"
               :model "your-model")
```

## How Configuration Resolution Works

When you call `make-provider`, the system:

1. Creates a provider instance with any explicit arguments you provide
2. **For base URL**: If not provided, calls `provider-default-base-url`
3. **For API key**: If not provided and not Ollama:
   - Calls `provider-api-key-env-var` to get the environment variable name
   - Calls `get-env-or-error` to fetch from the environment
   - Signals `provider-configuration-error` if the key is missing

Example flow for `:anthropic`:

```
(make-provider :anthropic :model "claude-3-5-sonnet-20241022")
  → base-url = nil
    → Calls provider-default-base-url
    → Sets base-url = "https://api.anthropic.com/v1"
  → api-key = nil
    → Calls provider-api-key-env-var
    → Gets "ANTHROPIC_API_KEY"
    → Fetches from environment
    → If missing, signals error
```

## Error Handling

If a required configuration value is missing, you'll see:

```
provider-configuration-error: Missing API key for :anthropic
  Environment variable: ANTHROPIC_API_KEY
```

You can handle this with restart cases:

```lisp
;; Supply a value directly
(invoke-restart 'use-value "sk-ant-...")

;; Or try a different environment variable
(invoke-restart 'use-environment "ALT_ANTHROPIC_KEY")
```

## Inspecting Provider Configuration

You can query a provider's configuration without exposing sensitive data:

```lisp
(let ((provider (make-provider :anthropic :model "claude-3-5-sonnet-20241022")))
  ;; Get a summary (omits API key)
  (provider-config-summary provider)

  ;; Get provider type
  (provider-type provider)  ; => :anthropic

  ;; Get capabilities
  (provider-capabilities provider))
```

## Best Practices

1. **Use environment variables in production** - Never hardcode API keys in source code
2. **Load config files explicitly** - Avoid auto-loading to maintain control
3. **Use different API keys per environment** - Separate development, staging, and production keys
4. **Test configuration early** - Verify API keys work before running long-running tasks
5. **Use explicit base URLs for custom endpoints** - Don't rely on defaults for non-standard deployments

## Related Resources

- [Quickstart Guide](../quickstart.md) - Get started with your first request
- [Error Handling Guide](./error-handling.md) - Handle configuration and API errors
- [Provider-Specific Guides](./using-gemini.md) - Provider implementation details
