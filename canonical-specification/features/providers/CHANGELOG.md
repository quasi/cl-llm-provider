# Providers Feature Changelog

All notable changes to the providers feature will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2025-01-22

### Fixed

- **Anthropic Provider**: Added array items schema handling to `translate-tool-to-provider`
  - Matches fix applied to default implementation in protocol.lisp
  - Array parameters now properly include `items` property in JSON schema
  - Defaults to `{"type": "string"}` when `:items` not specified
  - See `features/tools/decisions/DR-001-array-items-schema.md`

## [0.2.0] - 2026-01-16

### Added

- **Google Gemini Provider**: Complete implementation with OpenAI-compatible endpoint
  - Text completion support (gemini-3-flash-preview, gemini-3-pro-preview)
  - Vision analysis support (JPEG, PNG, WebP, GIF)
  - Function calling/tools support
  - Streaming response support
  - Embeddings support (gemini-embedding-001, 768 dimensions)
  - Model metadata with accurate pricing and context windows
  - Full test coverage (44 assertions, 100% pass rate)
  - Comprehensive documentation (how-to guide)

- **Canon Artifacts**:
  - `GEMINI-PROVIDER-SPECIFICATION.md` - Complete specification
  - `contracts/gemini-api.md` - API contract
  - `scenarios/gemini-provider-usage.md` - 14 usage scenarios
  - `decisions/gemini-implementation-strategy.md` - Implementation strategy

### Changed

- Updated README.md to include Gemini in supported providers
- Enhanced provider capabilities matrix with Vision column
- Updated provider comparison table

### Implementation Details

- **Lines of Code**: 264 lines (src/providers/gemini.lisp)
- **Code Reuse**: >80% via OpenAI-compatible patterns
- **Test Coverage**: 13 test cases, 44 assertions, 100% pass rate
- **Zero Breaking Changes**: Fully backward compatible

### Architecture Decision

Used OpenAI-compatible endpoint (`/v1beta/openai/`) for maximum code reuse:
- Composition over inheritance
- Shared request/response helpers
- Only provider-specific metadata overridden
- See `decisions/gemini-implementation-strategy.md` for rationale

## [0.1.0] - 2026-01-16

### Initial

- Canon structure established
- Provider protocol contract defined
- Foundation for multi-provider support documented
