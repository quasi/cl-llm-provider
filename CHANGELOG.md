# Changelog

Notable changes to cl-llm-provider. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This file starts at 2026-08-04. Anything earlier is in `git log` — the library was
pre-release and untagged, and reconstructing 100 commits after the fact would
produce a document nobody could trust.

## [Unreleased]

### Added

- **`use-model` restart** on `complete`, `embedding` and `complete-stream`.
  Re-issues against the *same* provider with a different model name. A
  `provider-model-not-found-error` previously offered only `retry`, which repeats
  the same 404, and `use-fallback-provider`, which is a sledgehammer for a typo.
- **Optional model argument on `use-fallback-provider`**:
  `(fallback &optional model)`. This is what makes cross-provider failover
  possible at all. The one-argument form is unchanged and still keeps the
  caller's model, which is correct for two endpoints serving the same one.
- **`:fallback-providers` entries may name a model** —
  `(provider . model)` or `(provider model)`. A bare provider keeps the previous
  meaning.
- **`*requested-model*`**, the in-flight model, exported. Bound by `complete`,
  `embedding` and `complete-stream` inside their retry loops so a 404 can name
  the model it could not find.
- **`:requested-model` keyword on `handle-http-error`**, for callers that know
  the model and would rather pass it than rely on the dynamic binding.
- **`docs/how-to/local-models-and-failover.md`** — running against a local
  OpenAI-compatible endpoint (MLX, vLLM, LM Studio, llama.cpp) and failing over
  to a hosted provider. Every command and output measured against a real MLX
  server on a LAN host and OpenRouter.

### Fixed

- **Cross-provider failover could not change the model.** `use-fallback-provider`
  re-resolved `(%resolve-model model prov)` where `model` was the caller's
  original argument, and `%resolve-model` is `(or model ...)`, so an explicit
  model always won and travelled to an endpoint that had never heard of it. The
  restart appeared to work — the handler ran, the provider switched — and the
  request then died on the fallback's own 404.
- **The failover contract differed by entry point.** `embedding` and
  `complete-stream` had a same-named restart that refused the second argument,
  and no `use-model` at all. A caller who wrote the two-argument form against
  `complete` and reused the handler for a streaming turn died on arity, at the
  moment its provider was already down.
- **The two restarts undid each other.** A model corrected by `use-model` was
  silently reverted by any later one-argument `use-fallback-provider`, which
  recomputed from the caller's original argument. The broken name then went to
  the fallback. Both restarts now write the same variable.
- **An explicit `NIL` fallback model reached the wire as `"model": null`** —
  the shape `(invoke-restart r fb (getf config :model))` produces when the config
  names no model. `NIL` now means "let the new provider decide", as everywhere
  else.
- **`Model not found: NIL`.** `classify-api-error` read the requested model from
  a nested `error.model` field almost no server sends, and `handle-http-error`
  was never told what the caller had asked for.
- **`with-auto-recovery`'s `:fallback-providers` could not change the model, and
  did nothing at all for a body passing `:provider` explicitly.** It swapped
  `*default-provider*` and re-ran the body — a second, weaker implementation of
  the restart. It now invokes `use-fallback-provider`, which is live at that
  point.
- **Documentation examples that could not work**: `handler-case` bodies calling
  `invoke-restart` (`handler-case` unwinds before its body runs, so the restart
  is already gone), and a `See also` pointing at a document that covers no
  restarts.

### Changed

- **The telos shim is gone; annotations now live in `cl-llm-provider.intent`.**
  `src/telos-shim.lisp` defined a stand-in `telos` package whenever the real
  telos was absent. Whether it activated was ambient state, evaluated separately
  at compile time and at load time, and the shim's macros expanded to shim-only
  specials while the real telos's expand to `register-feature`/`make-intent`.
  A fasl was therefore valid **only** in an image whose telos-presence matched
  the one that compiled it: 2 of 4 compile/load orderings died with
  `TELOS::*FEATURE-NAMES* is unbound` or `TELOS::MAKE-INTENT is undefined`.
  Because ASDF's cache is shared across projects, building this library in one
  repo could break an unrelated repo. `src/intent.lisp` replaces it with macros
  that expand only to calls on functions in their own package, so load order
  cannot matter. Regression test: `tests/test-load-order.sh`.

  **Migration.** `cl-llm-provider` no longer occupies or requires the `telos`
  package, so `(telos:get-intent 'cl-llm-provider:complete)` now returns `NIL`
  rather than an intent — it fails silently, which is the one thing worth
  checking for. Either query `cl-llm-provider.intent:get-intent` instead, or
  load the new **`cl-llm-provider/telos`** system, which declares a real
  dependency on telos and republishes every annotation into it — features,
  their members, their decisions, and classes filed as classes.

- **`with-auto-recovery` no longer re-executes the body on the fallback path.**
  It re-issues only the failing request, so side effects performed earlier in the
  body are no longer repeated. Retries still re-execute the body.
- **`use-fallback-provider`'s `:report` string** now mentions the optional model.
  A `restart-case` lambda list cannot be read back and
  `available-recovery-options` returns only `:name` and `:report`, so the report
  was the sole channel by which an agent could discover the argument.
