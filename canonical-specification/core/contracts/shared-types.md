---
type: contract
name: shared-types
version: 0.1.0
status: draft
---

# Shared Types

[DRAFT] - To be extracted from cl-llm-provider codebase

Common data structures used across multiple features.

> **Status**: Type definitions will be extracted during Pass 2: Contract Extraction.
> This file will contain types referenced by multiple features.

---

<!-- Shared type definitions will be populated during Pass 2: Contract Extraction -->

## Response Types

### JSON Schema: Base Response

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["id", "model"],
  "properties": {
    "id": {"type": "string"},
    "model": {"type": "string"},
    "usage": {
      "type": "object",
      "properties": {
        "prompt_tokens": {"type": "integer"},
        "completion_tokens": {"type": "integer"},
        "total_tokens": {"type": "integer"}
      }
    }
  }
}
```

## Message Types

### JSON Schema: Message

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["role", "content"],
  "properties": {
    "role": {
      "type": "string",
      "enum": ["user", "assistant", "system"]
    },
    "content": {
      "oneOf": [
        {"type": "string"},
        {
          "type": "array",
          "items": {"type": "object"}
        }
      ]
    }
  }
}
```

## Tool Types

### JSON Schema: Tool Definition

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["name", "description", "parameters"],
  "properties": {
    "name": {"type": "string"},
    "description": {"type": "string"},
    "parameters": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "type"],
        "properties": {
          "name": {"type": "string"},
          "type": {"type": "string"},
          "description": {"type": "string"},
          "required": {"type": "boolean"}
        }
      }
    }
  }
}
```

### JSON Schema: Tool Call

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["id", "name", "arguments"],
  "properties": {
    "id": {"type": "string"},
    "name": {"type": "string"},
    "arguments": {"type": "object"}
  }
}
```

## Error Types

### JSON Schema: Error Response

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["type", "message"],
  "properties": {
    "type": {
      "type": "string",
      "enum": ["api_error", "authentication_error", "rate_limit_error", "validation_error"]
    },
    "message": {"type": "string"},
    "status_code": {"type": "integer"},
    "retry_after": {"type": "integer"}
  }
}
```
