# Provider Protocol and Request/Response Handling Test Suites

This directory contains comprehensive test suites for the provider protocol, request/response handling, and integration flows.

## Test Files

### 1. `test-provider-protocols.lisp`
**Type**: Protocol Compliance Test Suite
**Framework**: FiveAM
**Purpose**: Tests provider protocol contracts, generic functions, and type hierarchies

**Coverage** (77 checks, 100% pass rate):
- **Provider Initialization** (4 tests)
  - Anthropic, OpenAI, Ollama, OpenAI-Compatible provider creation

- **Message Normalization** (3 tests)
  - Plist format validation
  - Message list conversion
  - Plist-to-hash conversion

- **Tool Definition** (3 tests)
  - Tool creation with name, description, parameters
  - Required parameters tracking
  - Tool definition validation

- **Tool Calls** (1 test)
  - Tool call creation with ID, name, and arguments

- **Response Objects** (5 tests)
  - Completion response creation
  - Completion response with tool calls
  - Finish reason support (:stop, :length, :tool-calls, :content-filter)
  - Embedding response creation

- **Request Building** (2 tests)
  - Minimal completion requests
  - System message handling

- **Response Parsing** (3 tests)
  - Generic function existence verification
  - Tool call parsing
  - Embedding response parsing

- **Error Handling** (9 tests)
  - Error type hierarchy
  - Provider API error creation
  - Rate limit error with retry-after
  - Authentication error
  - Configuration error
  - Tool schema error
  - Error extraction from various response formats

- **Configuration** (3 tests)
  - Default model resolution
  - Default temperature handling
  - Default max tokens

- **Provider-Specific Behavior** (3 tests)
  - Anthropic max_tokens requirement
  - Ollama thinking support
  - OpenAI tool choice support

- **Protocol Compliance** (3 tests)
  - Generic function existence verification
  - send-completion-request, parse-completion-response
  - send-embedding-request

- **Message Flow** (5 tests)
  - User, assistant, system message formats
  - Conversation continuation
  - Response message reuse

**Running**:
```bash
sbcl --noinform --non-interactive --load tests/test-provider-protocols.lisp
```

---

### 2. `test-request-response-handling.lisp`
**Type**: Request/Response Handling Test Suite
**Framework**: FiveAM
**Purpose**: Tests message normalization, request encoding, response parsing, and data structures

**Coverage** (97 checks, 100% pass rate):
- **Message Normalization** (5 tests)
  - Keyword to string key conversion
  - String key preservation
  - Multiple message handling
  - Nil value handling
  - Message order preservation

- **System Message Handling** (3 tests)
  - System message as parameter
  - Conversion to message plist
  - Single system message enforcement

- **Tool Definition to Schema Translation** (5 tests)
  - OpenAI format translation
  - Enum constraints
  - Required parameters
  - Nested object parameters
  - Array type parameters

- **Request Parameters** (6 tests)
  - Temperature valid range (0-2)
  - Invalid temperature bounds
  - Max tokens positive integer
  - Stop sequences as string list
  - Top-p sampling parameter
  - Valid parameter ranges

- **Tool Call Extraction** (4 tests)
  - Tool call with unique ID
  - Tool call with name
  - Arguments as plist
  - Arguments parsing from JSON

- **Response Content** (3 tests)
  - Completion response content as string
  - Nil content when tool calls present
  - Message structure with role and content

- **Token Usage** (5 tests)
  - Usage has prompt tokens
  - Usage has completion tokens
  - Usage has total tokens
  - Total equals prompt + completion
  - Zero tokens validity

- **Provider Metadata** (5 tests)
  - Optional metadata field
  - OpenAI system fingerprint
  - OpenAI created timestamp
  - Anthropic stop sequence
  - Ollama timing fields

- **Finish Reasons** (4 tests)
  - :stop finish reason
  - :length finish reason
  - :tool-calls finish reason
  - :content-filter finish reason

- **Raw Response Preservation** (2 tests)
  - Raw response storage
  - Original response preservation

- **Embedding Response** (3 tests)
  - Contains vector list
  - Float list vectors
  - Consistent vector dimensions

- **Multiple Responses** (2 tests)
  - Response independence
  - Unique response IDs

- **Performance Profiling** (3 tests)
  - Performance timing structure
  - Positive timing values
  - Disabled by default

**Running**:
```bash
sbcl --noinform --non-interactive --load tests/test-request-response-handling.lisp
```

---

### 3. `test-integration-full-flow.lisp`
**Type**: End-to-End Integration Test Suite
**Framework**: FiveAM
**Purpose**: Tests complete provider flows and real-world scenarios

**Coverage** (65 checks, 100% pass rate):
- **Provider Initialization** (4 tests)
  - Anthropic full initialization
  - OpenAI full initialization
  - Ollama local initialization
  - OpenAI-compatible initialization

- **Message Construction Flow** (4 tests)
  - User message construction
  - Multi-turn conversation
  - System prompt construction
  - Messages with tool calling

- **Response Validation Flow** (3 tests)
  - Basic completion response creation
  - Response with metadata
  - Response with performance profiling

- **Response with Tool Calls** (1 test)
  - Tool call response without text content
  - Proper finish reason

- **Error Handling Flow** (5 tests)
  - Missing API key handling
  - Invalid provider type handling
  - Provider API error creation
  - Rate limit error with retry info
  - Graceful error handling

- **Tool Definition and Validation** (3 tests)
  - Create and validate tool
  - Parameter validation
  - Multiple parameters

- **Token Counting Flow** (2 tests)
  - Token usage tracking in response
  - Token count mathematical relationship

- **Conversation Continuation** (2 tests)
  - Continue after response
  - Continue with tool response

- **Embedding Flow** (2 tests)
  - Embedding response creation
  - Embedding vector properties

- **Multi-Provider Compatibility** (2 tests)
  - Response works across providers
  - Different provider instances are independent

- **Configuration and Defaults** (4 tests)
  - Default temperature resolution
  - Default model configuration
  - Default max tokens
  - Override defaults with instance settings

- **Provider-Specific Tests** (3 tests)
  - Ollama availability check
  - Ollama provider creation
  - Anthropic max_tokens requirement
  - Anthropic provider creation
  - OpenAI provider creation
  - OpenAI tool calling support

- **Response Independence** (1 test)
  - Multiple responses don't share state

- **Performance Profiling** (3 tests)
  - Profiling disabled by default
  - Profiling can be enabled
  - Response with profiling data

**Running**:
```bash
sbcl --noinform --non-interactive --load tests/test-integration-full-flow.lisp
```

---

## Test Statistics

### Overall Results
- **Total Tests**: 3 comprehensive test suites
- **Total Checks**: 77 + 97 + 65 = **239 checks**
- **Pass Rate**: **100% (239/239 passing)**
- **Failed**: 0
- **Skipped**: 0

### Coverage Areas
✓ Provider protocol contracts
✓ Request/response normalization
✓ Error handling and recovery
✓ Tool definition and parsing
✓ Message formatting and conversion
✓ Provider-specific behaviors
✓ Configuration and defaults
✓ Performance profiling
✓ Multi-provider compatibility
✓ Edge cases and special values
✓ Full end-to-end workflows

---

## Running All Tests

From project root:

```bash
# Run provider protocol tests
sbcl --noinform --non-interactive --load tests/test-provider-protocols.lisp

# Run request/response handling tests
sbcl --noinform --non-interactive --load tests/test-request-response-handling.lisp

# Run integration full flow tests
sbcl --noinform --non-interactive --load tests/test-integration-full-flow.lisp
```

## Test Philosophy

These test suites follow FiveAM testing best practices:

1. **Comprehensive Coverage**: Each test is focused on a single aspect of functionality
2. **Clear Names**: Test names describe what is being tested and the expected behavior
3. **Isolated Tests**: Tests don't depend on other tests or external state
4. **Multiple Levels**: Unit tests validate individual components, integration tests validate workflows
5. **Error Scenarios**: Tests include error conditions and edge cases
6. **Real Structures**: Tests use actual response and request objects from the library

## Key Test Patterns

### Protocol Compliance
Tests verify that required generic functions exist and are callable:
```lisp
(fiveam:is (fboundp 'send-completion-request))
```

### Type Validation
Tests verify object types and structures:
```lisp
(fiveam:is (typep response 'completion-response))
(fiveam:is (hash-table-p hash))
```

### Data Structure Validation
Tests verify content and relationships:
```lisp
(fiveam:is (= (getf usage :total-tokens)
              (+ (getf usage :prompt-tokens)
                 (getf usage :completion-tokens))))
```

### Error Handling
Tests verify error conditions are handled:
```lisp
(fiveam:is (subtypep 'provider-rate-limit-error 'provider-api-error))
```

## Maintenance Notes

- Tests are designed to be implementation-agnostic (don't rely on specific provider internals)
- Mock tests can be added without modifying existing tests
- Tests use only the public API surface
- No external API keys or network calls required (unless explicitly testing with mocks)

## Related Documentation

- See `/tests/README.md` for token counting and metadata extraction tests
- See `/src/protocol.lisp` for provider protocol definitions
- See `/src/types.lisp` for response object definitions
- See `/src/conditions.lisp` for error type definitions
