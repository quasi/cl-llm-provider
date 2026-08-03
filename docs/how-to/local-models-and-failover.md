# Local models, and failing over to the cloud when they are not there

Run against a model on your own machine or LAN, and fall back to a hosted
provider only when the local one is unreachable. Cheap and private by default,
still answering when the box is off.

Every command and every output on this page was measured on 2026-08-04 against an
MLX server on a LAN host and OpenRouter.

## Talking to a local server

Anything exposing an OpenAI-shaped `/v1` is the `:openai-compatible` provider —
MLX, vLLM, LM Studio, llama.cpp's server, Groq, Together. The only required
argument is the base URL; there is no default, deliberately, because guessing
`localhost` would silently pick the wrong box.

```lisp
(defparameter *local*
  (make-provider :openai-compatible
                 :base-url "http://surya.local:8888/v1"
                 :model    "gemma-4-26B-A4B-it-QAT-MLX-4bit"
                 :api-key  "not-needed"))   ; most local servers ignore it

(response-content (complete '((:role "user" :content "Reply with exactly: LOCAL-OK"))
                            :provider *local*))
;; => "LOCAL-OK"
```

`:api-key` is passed because `make-provider` asks the environment for one when a
provider declares an env var; `:openai-compatible` declares none, so any
non-`nil` value satisfies it. (`:ollama` needs no key at all.)

To find out what a server actually serves, ask it — the model id you pass must
match one of these exactly:

```console
$ curl -s http://surya.local:8888/v1/models | python3 -m json.tool
{"data": [{"id": "gemma-4-26B-A4B-it-QAT-MLX-4bit", ...}, ...]}
```

## Local first, cloud second

The affordance is the `use-fallback-provider` restart, established by `complete`,
`complete-stream` and `embedding`. A handler that finds it decides; nothing
switches on its own, and nothing spends your money without being asked.

```lisp
(defparameter *cloud* (make-provider :openrouter :model "openai/gpt-oss-120b"))

(defun ask (messages)
  (handler-bind
      ((provider-network-error
         (lambda (c)
           (let ((r (find-restart 'use-fallback-provider c)))
             (when r
               (format *error-output* "~&local endpoint is down; using OpenRouter~%")
               ;; BOTH ARGUMENTS. See below.
               (invoke-restart r *cloud* "openai/gpt-oss-120b"))))))
    (complete messages
              :provider *local*
              :model "gemma-4-26B-A4B-it-QAT-MLX-4bit"
              :max-tokens 400)))
```

Measured, with the local server up and then with it stopped:

```
local UP  : switched=NIL  served-by=surya.local  answer="OK"
local DOWN: switched=T    served-by=openrouter   answer="OK"
```

### Pass the model. This is the whole trap.

`use-fallback-provider` takes `(fallback &optional fallback-model)`. Omit the
model and the caller's original is kept and re-resolved against the new provider
— correct only when both endpoints serve the *same* model, which is the mirror
case (a local copy of a cloud model, two regions of one service).

Across *different services* it sends a name the fallback has never heard of:

```lisp
;; WRONG for a local -> cloud switch
(invoke-restart r *cloud*)
;; the switch succeeds, and then:
;;   Model not found: gemma-4-26B-A4B-it-QAT-MLX-4bit
```

The failure is nasty because the restart *appears* to work: your handler runs,
the provider changes, and the request dies one layer further down looking like a
cloud problem. Name the model and it goes away.

### `use-model`, when only the name is wrong

If the provider is fine and the model name is not — a typo, a model retired
upstream, a local server that has not pulled it yet — switching provider is a
sledgehammer and `retry` just repeats the same 404:

```lisp
(handler-bind
    ((provider-model-not-found-error
       (lambda (c)
         (let ((r (find-restart 'use-model c)))
           (when r (invoke-restart r "gemma-4-26B-A4B-it-QAT-MLX-4bit"))))))
  (complete messages :provider *local* :model "gemma-4-26b"))   ; wrong case
```

The condition names what it could not find, so a handler can decide from the
report alone:

```
Model not found: gemma-4-26b
```

Corrections stick. If a handler fixes the name with `use-model` and the endpoint
then dies, a later one-argument `use-fallback-provider` carries the *corrected*
name to the fallback, not the one you started with.

### `with-auto-recovery`, when you also want retries

If you want backoff and retries before the switch, the macro does the same thing
declaratively. Name the model in the entry, for the same reason as above:

```lisp
(with-auto-recovery (:max-retries 3
                     :fallback-providers (list (cons *cloud* "openai/gpt-oss-120b")))
  (complete messages :provider *local* :model "gemma-4-26B-A4B-it-QAT-MLX-4bit"))
```

A bare entry — `(list *cloud*)` — keeps the caller's model, which is right only
for the mirror case. The macro invokes the same restart, so the two forms mean
exactly what they mean above.

Retries re-execute the whole body; the fallback switch does not — it re-issues
just the failing request, so side effects earlier in the body are not repeated.

## Choosing what to fail over on

`provider-network-error` means *the server is not there* — connection refused,
DNS failure, timeout. That is the local-server-is-off case and the one worth
switching on.

Handling `provider-api-error` broadly instead will also fail over on a 400 you
sent, on a content filter, and on a context-length error — none of which the
cloud will answer any better, and all of which will now cost money to be told
so twice. `transient-error-p` is the ready-made predicate if you want a wider
net than network errors but narrower than everything.

## Two things that will bite you

**A reasoning model returns nothing on a small `max-tokens`.** Budgets tuned for
a local model can make a cloud fallback come back empty, which reads as a
provider bug and is not one. Measured on `openai/gpt-oss-120b`:

| `max-tokens` | completion tokens | content |
|---|---|---|
| 32 | 32 | `NIL` |
| 400 | — | `"OK"` |

Every token went to reasoning and none to output. If your fallback is a
reasoning model, give it room.

**A local model is not a drop-in for a frontier one.** Failover keeps you
answering; it does not keep you equally good. If some work genuinely needs the
bigger model, say so — send that work to the cloud directly rather than
discovering the difference in your output quality.

## See also

- [Error handling](error-handling.md) — the full condition hierarchy and every restart
- [Adding a provider](add-provider.md) — when OpenAI-shaped is not shaped enough
