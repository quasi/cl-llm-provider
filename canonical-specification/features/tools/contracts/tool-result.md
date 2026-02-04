---
type: contract
name: tool-result
version: 0.1.0
status: draft
feature: tools
---

# Tool Result Contract

This contract defines how tool execution results are represented and sent back to the LLM.

## Overview

After executing a tool, the result must be formatted as a message and included in the next completion request so the LLM can use the information to continue the conversation.

## Function: `make-tool-result`

Create a tool result message to send back to the LLM.

### Signature

```lisp
(make-tool-result tool-call-id result &key is-error) → message-plist
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `tool-call-id` | string | The ID from the original tool call |
| `result` | any | The result of executing the tool |
| `is-error` | boolean | `t` if result represents an error (default: `nil`) |

### Return Value

Returns a message plist suitable for inclusion in the messages list of the next `complete` call.

**Format**:
```lisp
(:role "tool"
 :tool_call_id "call_abc123"
 :content "result string"
 :is_error nil)
```

### Tool Result Message Schema

```json-schema
{
  "type": "object",
  "properties": {
    "role": {
      "type": "string",
      "const": "tool",
      "description": "Always 'tool' for tool results"
    },
    "tool_call_id": {
      "type": "string",
      "description": "ID of the tool call this result corresponds to"
    },
    "content": {
      "type": "string",
      "description": "String representation of the result"
    },
    "is_error": {
      "type": "boolean",
      "description": "Whether this result represents an error"
    }
  },
  "required": ["role", "tool_call_id", "content"]
}
```

## Usage Example

### Successful Execution

```lisp
(let* ((tools (list (define-tool "get_weather" ...)))
       (response (complete messages :tools tools))
       (calls (tool-calls response)))
  (when calls
    ;; Execute the tool
    (let* ((call (first calls))
           (result (execute-weather-lookup (tool-call-arguments call))))
      ;; Create result message
      (let ((result-msg (make-tool-result (tool-call-id call)
                                         result)))
        ;; Continue conversation with result
        (complete (append messages
                         (list (:role "assistant" :tool_calls calls)
                               result-msg))
                 :tools tools)))))
```

### Error Handling

```lisp
(let ((result-msg
        (handler-case
            (let ((result (execute-tool call)))
              (make-tool-result (tool-call-id call) result))
          (error (e)
            (make-tool-result (tool-call-id call)
                            (format nil "Error: ~A" e)
                            :is-error t)))))
  ...)
```

## Result Formatting

### Result Type Conversion

| Result Type | Conversion |
|-------------|------------|
| String | Use as-is |
| Number | Convert to string via `princ-to-string` |
| Boolean | `"true"` or `"false"` |
| List/Vector | JSON-encode via `yason:encode` |
| Hash Table | JSON-encode via `yason:encode` |
| Object | Convert to plist, then JSON-encode |
| Error | Error message string with `:is-error t` |

### Example Transformations

```lisp
;; String result
(make-tool-result "call_1" "Sunny, 72°F")
;; → (:role "tool" :tool_call_id "call_1" :content "Sunny, 72°F")

;; Structured result
(make-tool-result "call_2" '(:temp 72 :condition "sunny"))
;; → (:role "tool" :tool_call_id "call_2"
;;     :content "{\"temp\":72,\"condition\":\"sunny\"}")

;; Error result
(make-tool-result "call_3" "API key invalid" :is-error t)
;; → (:role "tool" :tool_call_id "call_3"
;;     :content "API key invalid" :is_error t)
```

## Multi-Turn Conversation Flow

```
1. User: "What's the weather in Paris?"
2. Assistant: [tool_call: get_weather(location="Paris")]
3. Tool: [result: "Sunny, 20°C"]  ← Tool result message
4. Assistant: "The weather in Paris is sunny with a temperature of 20°C."
```

**Message Sequence**:
```lisp
'((:role "user" :content "What's the weather in Paris?")
  (:role "assistant" :tool_calls [...])  ; Added automatically
  (:role "tool" :tool_call_id "call_1" :content "Sunny, 20°C")  ; make-tool-result
  (:role "assistant" :content "The weather in Paris is..."))  ; Next completion
```

## Provider-Specific Formats

### OpenAI Tool Result

Sent as a message with role "tool":
```json
{
  "role": "tool",
  "tool_call_id": "call_abc123",
  "content": "result string"
}
```

### Anthropic Tool Result

Sent within the user message as a tool_result content block:
```json
{
  "role": "user",
  "content": [{
    "type": "tool_result",
    "tool_use_id": "toolu_xyz789",
    "content": "result string",
    "is_error": false
  }]
}
```

Both formats are handled transparently by the provider implementation.

## Invariants

1. **ID matching**: `tool_call_id` MUST match an ID from a previous tool call in the conversation
2. **String content**: Result content MUST be a string (convert if necessary)
3. **Role value**: Role MUST always be "tool"
4. **Sequential ordering**: Tool result messages MUST follow the assistant message containing the tool call
5. **Completeness**: Every tool call MUST have a corresponding tool result before the next completion

## Error Conditions

| Condition | When | Recovery |
|-----------|------|----------|
| `mismatched-tool-call-id` | ID doesn't match any tool call | Check conversation history |
| `missing-tool-result` | Tool called but no result provided | Add result or error message |
| `non-string-content` | Result not converted to string | Apply type conversion |

## Related Contracts

- [tool-call.md](./tool-call.md) - Tool invocation by LLM
- [tool-definition.md](./tool-definition.md) - Defining tools
- [hooks-api.md](../../observability/contracts/hooks-api.md) - Tool execution hooks

## Implementation Notes

- Result formatting is provider-agnostic at the API level
- Providers handle the translation to their specific wire format
- Large results (>100KB) should be summarized before sending back to the LLM
- Error results allow the LLM to handle failures gracefully
