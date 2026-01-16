# Core Invariants

**Status**: Extracted from docs/agent/core-SPEC.agent.md
**Confidence**: High (formal specification with verification code)
**Last Updated**: 2026-01-16

Invariants are properties that MUST always hold. They are mechanically checkable and represent absolute requirements of the system.

---

## Response Invariants

### INV-001: Response Raw Preservation

**Statement**: Every response preserves the original provider response.

**Formal**:
```
∀ response: (response-raw response) returns original provider response
```

**Check**:
```lisp
(hash-table-p (response-raw completion-response-instance))
```

**Rationale**: Enables debugging and access to provider-specific features not normalized into standard slots.

---

### INV-002: Usage Token Non-Negative

**Statement**: All token counts in usage are non-negative integers.

**Formal**:
```
∀ response: (response-usage response) contains non-negative integers
```

**Check**:
```lisp
(let ((usage (response-usage response)))
  (and (>= (getf usage :prompt-tokens) 0)
       (>= (getf usage :completion-tokens) 0)
       (>= (getf usage :total-tokens) 0)))
```

**Rationale**: Token counts are cumulative, never negative.

---

## Tool Call Invariants

### INV-003: Tool Call ID Uniqueness

**Statement**: Tool call IDs are unique within a response.

**Formal**:
```
∀ response: (response-tool-calls response) has unique :id values
```

**Check**:
```lisp
(let ((ids (mapcar #'tool-call-id (response-tool-calls response))))
  (= (length ids) (length (remove-duplicates ids :test #'string=))))
```

**Rationale**: ID correlation requires uniqueness per response for matching results to calls.

---

## Message Invariants

### INV-004: Message Role Consistency

**Statement**: Message roles are from a closed set.

**Formal**:
```
∀ message: (member (getf message :role) '("user" "assistant" "system" "tool") :test #'string=)
```

**Check**: Direct member test.

**Rationale**: Limited role vocabulary defined by protocol; providers reject invalid roles.

---

## Provider Invariants

### INV-005: Provider Type Determinism

**Statement**: Same provider class always returns same default URL.

**Formal**:
```
∀ provider: (provider-default-base-url provider) deterministic for type
```

**Check**: Same provider class instance always returns same default URL.

**Rationale**: Enables URL inference from provider type.

---

## Performance Invariants

### INV-006: Performance Stats Keys

**Statement**: When profiling enabled, stats contain exactly the three timing keys.

**Formal**:
```
When *performance-profiling* enabled:
  stats plist contains exactly :encode-time, :api-time, :decode-time
```

**Check**:
```lisp
(when *performance-profiling*
  (let ((perf (response-performance response)))
    (and (member :encode-time perf)
         (member :api-time perf)
         (member :decode-time perf))))
```

**Rationale**: Defined profiling phases ensure consistent measurement structure.

---

## Tool Definition Invariants

### INV-007: Tool Definition Immutability

**Statement**: Tool definitions should not change after registration.

**Formal**:
```
Once tool added to registry, slots SHOULD NOT change
```

**Check**: Compare tool snapshots before/after registration.

**Rationale**: Prevents mid-conversation schema changes that could confuse the LLM.

---

## Streaming Invariants

### INV-STREAM-001: Accumulated Content Consistency

**Statement**: Accumulated content equals concatenation of all chunk deltas.

**Formal**:
```lisp
(string= (stream-accumulated-content stream)
         (apply #'concatenate 'string
                (mapcar #'chunk-delta (stream-chunks stream))))
```

**Source**: docs/agent/streaming-observability-API-SPEC.agent.md

---

### INV-STREAM-002: Chunk Index Ordering

**Statement**: Chunk indices are sequential starting from 0.

**Formal**:
```lisp
(= (length (stream-chunks stream))
   (loop for i from 0
         for chunk in (stream-chunks stream)
         always (= (chunk-index chunk) i)))
```

**Source**: docs/agent/streaming-observability-API-SPEC.agent.md

---

## Verification Checklist

From docs/agent/core-SPEC.agent.md Machine Checklist:

```
[ ] All protocol methods implemented for new providers (INV via RULE-001)
[ ] All tool names match ^[a-zA-Z0-9_-]+$ (RULE-003)
[ ] No API keys in source code or logs (RULE-005)
[ ] Messages chronologically ordered (RULE-006)
[ ] Tool call IDs preserved in results (RULE-007, INV-003)
[ ] Response objects never mutated after creation (RULE-004)
[ ] All conditions inherit from llm-provider-error (RULE-010)
[ ] Tool parameter types valid (RULE-011)
[ ] Finish reasons normalized to standard keywords (RULE-015)
[ ] Usage token counts non-negative (INV-002)
[ ] Performance stats structure preserved (INV-006)
[ ] Message roles valid (INV-004)
```

---

## Cross-Reference

| Invariant | Related Rules | Affected Artifacts |
|-----------|--------------|-------------------|
| INV-001 | - | completion-response, embedding-response |
| INV-002 | - | response-usage |
| INV-003 | RULE-007 | tool-call, make-tool-result |
| INV-004 | RULE-002 | message handling |
| INV-005 | - | provider-default-base-url |
| INV-006 | RULE-009 | performance profiling |
| INV-007 | - | tool registry |
