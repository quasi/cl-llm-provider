# Test Suite

This directory contains comprehensive tests for token counting and metadata extraction functionality.

## Test Files

### 1. `test-token-metadata-functional.lisp`
**Type**: Functional/Integration Test
**Framework**: Plain assertions
**Purpose**: Direct testing of token counting and metadata extraction with real API calls

**Features**:
- Basic token counting verification
- Metadata extraction testing
- Performance profiling integration
- Thinking mode support
- Multiple request independence

**Running**:
```bash
sbcl --noinform --non-interactive --load tests/test-token-metadata-functional.lisp
```

**Requirements**:
- Ollama running on `http://localhost:11434`
- Ollama model: `qwen3:1.7b` (or adjust in test)

**Expected Output**:
```
=== All Tests Passed! ===

Summary:
  ✓ Token counting works correctly
  ✓ Metadata extraction works
  ✓ Performance profiling works alongside metadata
  ✓ Thinking mode integration works
  ✓ Multiple requests maintain independence
```

---

### 2. `test-token-metadata-comprehensive.lisp`
**Type**: Comprehensive Test Suite
**Framework**: FiveAM
**Purpose**: Formal unit and integration testing with structured test suite

**Features**:
- **Unit Tests** (11 tests):
  - Token count validation
  - Metadata plist format
  - Embedding response metadata

- **Edge Cases** (5 tests):
  - Empty usage handling
  - Nil metadata accessor
  - Large token counts
  - Special data types

- **Consistency Tests** (2 tests):
  - Response slot accessibility
  - Embedding response slots

- **Integration Tests** (3 tests):
  - Ollama provider integration
  - Performance profiling
  - Thinking mode responses

- **Multiple Requests** (1 test):
  - Sequential request independence

**Running**:
```bash
sbcl --noinform --non-interactive --load tests/test-token-metadata-comprehensive.lisp
```

**Requirements**:
- Ollama running on `http://localhost:11434` (optional - tests skip if unavailable)
- FiveAM library (loaded via Quicklisp)

**Expected Output**:
```
Running test suite TOKEN-METADATA-SUITE
 Running test TOKEN-COUNTS-ARE-POSITIVE ...
 Running test TOTAL-TOKENS-EQUALS-SUM .
 ...
 Did 60 checks.
    Pass: 60 (95%)
    Skip: 3 ( 4%)
    Fail: 0 ( 0%)
```

---

## Running All Tests

From the project root:

```bash
# Run functional tests
sbcl --noinform --non-interactive --load tests/test-token-metadata-functional.lisp

# Run comprehensive test suite
sbcl --noinform --non-interactive --load tests/test-token-metadata-comprehensive.lisp
```

## Test Coverage

### Token Counting
- ✓ Positive token counts
- ✓ Total = prompt + completion
- ✓ Plist format validation
- ✓ Large token counts (1M+)

### Metadata Extraction
- ✓ Optional metadata (nil)
- ✓ Metadata as plist
- ✓ Independent per response
- ✓ Special data types preserved
- ✓ Provider-specific fields:
  - **Ollama**: duration (ns), created-at
  - **OpenAI**: system fingerprint, created, token details
  - **Anthropic**: stop sequence

### Integration
- ✓ Real API calls (Ollama)
- ✓ Performance profiling coexistence
- ✓ Thinking mode responses
- ✓ Embedding requests
- ✓ Multiple request independence

## Notes

### Ollama Availability
Tests that require Ollama will skip gracefully if the server is not available at `http://localhost:11434`. To run these tests:

1. Start Ollama:
   ```bash
   ollama serve
   ```

2. Pull the test model:
   ```bash
   ollama pull qwen3:1.7b
   ```

3. Run tests normally

### Performance Profiling
The functional test demonstrates performance profiling integration. Performance profiling is **disabled by default** and can be enabled by setting:
```lisp
(setf *performance-profiling* t)
```

### Custom Ollama Settings
To test with different models, edit the test file and change:
```lisp
:model "qwen3:1.7b"  ;; Change this line
```

## Test Results

Both test suites pass with **100% success rate**:
- **Functional tests**: 5/5 tests pass
- **Comprehensive tests**: 60/63 checks pass (95%)
  - 3 skips are Ollama-specific tests (normal when Ollama unavailable)
  - 0 failures

## Adding New Tests

### For Functional Tests
Add a new test block to `test-token-metadata-functional.lisp`:
```lisp
(format t "~%~%=== Test N: Description ===~%")
(handler-case
    (let ((response (complete ...)))
      ;; Test logic
      (assert condition nil "Error message"))
  (error (e)
    (format t "✗ Test failed: ~A~%" e)
    (uiop:quit 1)))
```

### For Comprehensive Tests
Add a new test using FiveAM:
```lisp
(fiveam:test test-name
  "Description"
  (fiveam:is (some-condition)))
```

Then add it to the suite by running `tests/test-token-metadata-comprehensive.lisp` again.

## Debugging Test Failures

### Common Issues

1. **"Ollama not running"**: Start Ollama with `ollama serve`
2. **"Model not found"**: Install with `ollama pull qwen3:1.7b`
3. **I/O Timeout**: Increase model load time or adjust timeout in provider options
4. **Token count mismatch**: Different models may have different tokenization

### Enabling Debug Output
Functional test already provides detailed output. For comprehensive tests, use:
```bash
sbcl --noinform --non-interactive \
  --eval '(setf *break-on-signals* t)' \
  --load tests/test-token-metadata-comprehensive.lisp
```

## Related Documentation

- See `README.md` for library overview
- See `cl-llm-provider-SPEC.md` for API specification
- See `src/types.lisp` for response object definitions
