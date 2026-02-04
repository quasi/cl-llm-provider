---
type: scenario
name: multi-turn-conversation
version: 0.1.0
status: draft
feature: core-api
covers:
  - complete
test_evidence: tests/test-integration-full-flow.lisp:76-80
---

# Multi-Turn Conversation

[DRAFT] - Extracted from test suite

## Overview

Users can maintain multi-turn conversations by accumulating messages and responses, allowing the LLM to maintain context across multiple exchanges.

## Scenario: Continue Conversation with Message History

### Given

- An initial message from the user
- A previous completion response from the LLM
- A follow-up message from the user

### When

1. User sends first message: "What is 2+2?"
2. System receives response with content "4"
3. User appends response message to conversation history
4. User adds follow-up message: "Add 3 to that"
5. User sends complete message history to `complete` function

### Then

- The LLM receives full conversation context (user → assistant → user)
- Response accounts for previous exchanges
- Message history maintains correct role alternation

## Implementation

```lisp
;; Initial conversation
(let ((messages (list (list :role "user" :content "What is 2+2?"))))

  ;; Get first response
  (let ((response (complete messages)))

    ;; Append assistant's response to history
    (push (response-message response) messages)

    ;; Add follow-up question
    (push (list :role "user" :content "Add 3 to that") messages)

    ;; Continue conversation with full history
    (complete (reverse messages))))
```

## Acceptance Criteria

✅ Message history accumulates correctly
✅ Role alternation is preserved (user → assistant → user)
✅ Response message format is suitable for conversation continuation
✅ LLM maintains context from previous exchanges

## Error Conditions

None expected in happy path.

## Test Evidence

**Source**: `tests/test-integration-full-flow.lisp:76-80`

```lisp
(fiveam:test construct-conversation-sequence
  "Construct multi-turn conversation"
  (let ((messages '((:role "user" :content "Hello")
                   (:role "assistant" :content "Hi there!")
                   (:role "user" :content "How are you?"))))
    (fiveam:is (= (length messages) 3))
    (fiveam:is (string= (getf (first messages) :role) "user"))
    (fiveam:is (string= (getf (second messages) :role) "assistant"))))
```

## Related Scenarios

- [Complete Basic Request](./complete-basic-request.md) - Single-turn completion
- [Tool-Enabled Conversation](../tools/scenarios/tool-enabled-conversation.md) - With tool calling

## Invariants

- **INV-CONV-01**: Message list must alternate roles (or have system message first)
- **INV-CONV-02**: Each message must have `:role` and `:content` keys
- **INV-CONV-03**: Response message format is identical to input message format
