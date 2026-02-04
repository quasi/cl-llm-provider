---
type: contract
name: tool-approval
version: 0.1.0
status: draft
feature: tools
---

# Tool Approval Contract

This contract defines the approval system for tool execution, enabling human-in-the-loop confirmation for sensitive operations.

## Overview

Tool approval provides a callback-based system for requiring human approval before executing tools. This is essential for dangerous operations (file deletion, database writes, external API calls) where automated execution could cause harm.

## Approval Requirements

### Function: `needs-approval-p`

Check if a tool requires approval.

```lisp
(needs-approval-p tool-definition) → boolean
```

Returns `t` if approval is required based on the tool's `:requires-approval` setting.

### Approval Trigger Logic

| `requires-approval` Value | Condition |
|---------------------------|-----------|
| `nil` | Never requires approval |
| `t` | Always requires approval |
| `:always` | Always requires approval |
| `:if-dangerous` | Requires approval if `:safety-level` is `:dangerous` |

**Examples**:
```lisp
;; Never needs approval
(needs-approval-p (define-tool "search" ... :requires-approval nil))
;; → NIL

;; Always needs approval
(needs-approval-p (define-tool "delete_file" ... :requires-approval t))
;; → T

;; Conditional approval
(needs-approval-p (define-tool "write_file" ...
                    :safety-level :dangerous
                    :requires-approval :if-dangerous))
;; → T (dangerous + :if-dangerous)

(needs-approval-p (define-tool "read_file" ...
                    :safety-level :safe
                    :requires-approval :if-dangerous))
;; → NIL (safe, so no approval needed)
```

## Approval Protocol

### Generic Function: `request-tool-approval`

Request approval for tool execution.

```lisp
(request-tool-approval tool-definition tool-call arguments
                       &key callback)
→ (values decision arguments reason)
```

**Parameters**:
- `tool-definition`: The tool being executed
- `tool-call`: Tool call object from the LLM
- `arguments`: Parsed arguments plist
- `callback`: Approval callback function (uses registry default if not provided)

**Return Values**:
1. `decision`: `:approved`, `:rejected`, or `:edited`
2. `arguments`: Original or edited arguments plist
3. `reason`: Optional reason string (for rejection)

**Error Conditions**:
- `tool-approval-required`: No callback available
- `tool-approval-error`: Tool was rejected

## Approval Callback

### Callback Signature

```lisp
(lambda (tool-definition tool-call arguments) → result)
```

**Parameters**:
- `tool-definition`: Tool being executed
- `tool-call`: Tool call object
- `arguments`: Parsed arguments plist

**Return Format Options**:

| Return Value | Interpretation |
|--------------|----------------|
| `t` | Approved with original arguments |
| `:approved` | Approved with original arguments |
| `nil` | Rejected without reason |
| `:rejected` | Rejected without reason |
| `(list :approved)` | Approved with original arguments |
| `(list :rejected reason)` | Rejected with reason string |
| `(list :edited new-args)` | Approved with modified arguments |
| `(list :approved new-args)` | Approved with modified arguments |

### Approval Result Schema

```json-schema
{
  "type": "object",
  "properties": {
    "decision": {
      "type": "string",
      "enum": ["approved", "rejected", "edited"],
      "description": "Approval decision"
    },
    "arguments": {
      "type": "object",
      "description": "Original or edited arguments (plist)"
    },
    "reason": {
      "type": "string",
      "description": "Rejection reason (optional)"
    }
  },
  "required": ["decision", "arguments"]
}
```

## Usage Examples

### Simple Approval Callback

```lisp
(defun simple-approval-callback (tool call args)
  "Ask user for yes/no confirmation."
  (format t "~%Approve call to ~A with args ~A? (y/n): "
          (tool-name tool) args)
  (force-output)
  (char= (read-char) #\y))

;; Use with registry
(make-tool-registry
  :name "approved-tools"
  :approval-callback #'simple-approval-callback)

;; Or use directly
(request-tool-approval tool call args
                       :callback #'simple-approval-callback)
```

### Advanced Approval with Editing

```lisp
(defun advanced-approval-callback (tool call args)
  "Allow user to approve, reject, or edit arguments."
  (format t "~%Tool: ~A~%" (tool-name tool))
  (format t "Args: ~A~%" args)
  (format t "Options: [a]pprove, [r]eject, [e]dit: ")
  (force-output)
  (case (read-char)
    (#\a :approved)
    (#\r (list :rejected "User declined"))
    (#\e (list :edited (read-edited-args args)))
    (t :rejected)))
```

### Conditional Approval Based on Arguments

```lisp
(defun smart-approval-callback (tool call args)
  "Auto-approve safe paths, require confirmation for others."
  (let ((path (getf args :path)))
    (if (and (stringp path)
             (or (starts-with path "/tmp/")
                 (starts-with path "/var/tmp/")))
        :approved  ; Auto-approve temp files
        (progn
          (format t "Confirm deletion of ~A? (y/n): " path)
          (force-output)
          (if (char= (read-char) #\y)
              :approved
              (list :rejected "User declined non-temp file deletion"))))))
```

### Logging Approval Decisions

```lisp
(defun logged-approval-callback (tool call args)
  "Approve and log the decision."
  (log:info "Approval requested for ~A" (tool-name tool))
  (let ((decision (simple-yes-no-prompt)))
    (log:info "Decision: ~A" decision)
    decision))
```

## Integration with Tool Registry

### Registry-Level Default

```lisp
(defvar *approved-registry*
  (make-tool-registry
    :name "approved-tools"
    :approval-callback #'my-approval-callback))

;; All tools in this registry will use the default callback
(register-tool *approved-registry*
  (define-tool "delete_file" ...
    :requires-approval :always))
```

### Tool-Level Override

```lisp
;; Tool-specific approval (not yet implemented, but planned)
(define-tool "special_delete" ...
  :requires-approval :always
  :approval-callback #'special-approval-callback)
```

## Approval Workflow

```
1. Tool call received from LLM
2. Parse arguments
3. Validate arguments (see tool-validation.md)
4. Check needs-approval-p
   ├─ NO → Execute directly
   └─ YES ↓
5. request-tool-approval
   ├─ Callback returns :approved → Execute with original args
   ├─ Callback returns :edited → Execute with modified args
   └─ Callback returns :rejected → Signal tool-approval-error
```

## Error Handling

### Condition: `tool-approval-required`

Signaled when approval is needed but no callback is configured.

**Slots**:
- `tool` - tool-definition requiring approval
- `tool-call` - the tool call object

**Restart**: `:provide-approval` - Provide approval callback

### Condition: `tool-approval-error`

Signaled when a tool is rejected.

**Slots**:
- `tool` - tool-definition that was rejected
- `tool-call` - the tool call object
- `reason` - rejection reason string

**Restart**: `:retry-approval` - Ask for approval again

## Invariants

1. **Approval before execution**: Tools requiring approval MUST NOT execute without approval
2. **Validation first**: Arguments MUST be validated before requesting approval
3. **Callback availability**: If `:requires-approval` is not `nil`, a callback MUST be available
4. **Decision finality**: Once approved or rejected, the decision is final (no silent retries)
5. **Argument immutability**: Original arguments MUST NOT be modified; edited arguments are a new plist

## Best Practices

1. **Clear prompts**: Approval prompts should clearly explain what will happen
2. **Argument visibility**: Show full arguments to user for informed decision
3. **Timeout handling**: Implement timeouts for approval requests to avoid hanging
4. **Audit trail**: Log all approval decisions for security audit
5. **Escape hatch**: Provide way to abort/cancel during approval
6. **Editing validation**: Re-validate arguments after editing

## Related Contracts

- [tool-definition.md](./tool-definition.md) - Defining tools with approval requirements
- [tool-validation.md](./tool-validation.md) - Argument validation before approval
- [tool-execution.md](./tool-execution.md) - Tool execution after approval

## Implementation Notes

- Approval callbacks are synchronous (blocking)
- For async approval (e.g., Slack notification), use a polling mechanism
- Approval happens after validation to avoid approving invalid calls
- The `:edited` decision allows for argument sanitization/correction
- Registry-level callbacks provide default, but tool-level overrides are planned
