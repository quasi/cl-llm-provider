---
type: scenario
name: tool-approval-workflow
version: 0.1.0
feature: tools
covers:
  - tool-approval
tags:
  - happy-path
  - human-in-loop
  - safety
---

# Tool Approval - Human-in-the-Loop Workflow

## Context

Certain tools require explicit human approval before execution for safety and compliance. The approval system presents tool calls to users and waits for confirmation.

## Scenario 1: Manual approval for sensitive tool

### Setup

```lisp
(setf *provider* (make-provider :openai))
(setf *tool* (define-tool "delete_file"
                          "Delete a file from the filesystem"
                          '((:name "path" :type :string :required t))
                          :requires-approval t))
(setf *messages* '((:role "user" :content "Delete the old log file at /tmp/old.log")))
```

### Steps

#### 1. LLM requests tool call

**Action**: Complete with tool requiring approval
```lisp
(setf *response* (complete *messages*
                           :provider *provider*
                           :tools (list *tool*)))
(setf *tool-call* (first (response-tool-calls *response*)))
```

**Expected**:
- Tool call returned
- Tool name is "delete_file"
- Arguments contain path

#### 2. Request approval

**Action**: Present to user for approval
```lisp
(setf *approval* (request-tool-approval *tool* *tool-call*
                                        (tool-call-arguments *tool-call*)
                                        :callback (lambda (approved)
                                                   (format t "User ~A~%"
                                                          (if approved "approved" "denied")))))
```

**Expected**:
- Displays tool name, description, and arguments
- Waits for user input (approve/deny)
- Callback invoked with result

#### 3. Handle approval

**Action**: Process approved tool
```lisp
(if *approval*
    (progn
      (format t "Executing: delete ~A~%" (getf (tool-call-arguments *tool-call*) :path))
      (make-tool-result (tool-call-id *tool-call*) "File deleted successfully"))
    (make-tool-result (tool-call-id *tool-call*)
                      "User denied tool execution"
                      :is-error t))
```

**Expected**:
- If approved: tool executes, returns success
- If denied: returns error result

### Verification

```
ASSERT approval request displays tool details
ASSERT callback invoked with boolean
ASSERT denied execution returns error result
```

## Scenario 2: Auto-approval for safe tools

### Setup

```lisp
(setf *safe-tool* (define-tool "get_weather"
                               "Get current weather"
                               '((:name "location" :type :string))
                               :requires-approval nil))
```

### Steps

#### 1. Check approval requirement

**Action**: Verify tool doesn't require approval
```lisp
(tool-requires-approval *safe-tool*)
```

**Expected**:
- Returns `nil`
- Tool can execute without prompting user

#### 2. Execute directly

**Action**: Execute without approval step
```lisp
(execute-tool-call *safe-tool* '(:location "Paris"))
```

**Expected**:
- Executes immediately
- No approval prompt shown

### Verification

```
ASSERT (tool-requires-approval *safe-tool*) == nil
ASSERT tool executes without blocking
```

## Scenario 3: Batch approval for multiple tools

### Setup

```lisp
(setf *tool-calls* (list
                    (make-instance 'tool-call :id "call_1"
                                   :name "delete_file"
                                   :arguments '(:path "/tmp/file1.log"))
                    (make-instance 'tool-call :id "call_2"
                                   :name "delete_file"
                                   :arguments '(:path "/tmp/file2.log"))))
```

### Steps

#### 1. Request batch approval

**Action**: Present multiple tool calls for approval
```lisp
(setf *approvals* (request-batch-approval *tool-calls*))
```

**Expected**:
- Displays all tool calls
- User can approve/deny individually or all at once
- Returns list of approval decisions

#### 2. Process batch results

**Action**: Execute approved tools only
```lisp
(loop for call in *tool-calls*
      for approved in *approvals*
      collect (if approved
                  (execute-and-make-result call)
                  (make-tool-result (tool-call-id call)
                                    "Denied by user"
                                    :is-error t)))
```

**Expected**:
- Approved tools execute
- Denied tools return error results
- Results maintain call order

### Verification

```
ASSERT (length *approvals*) == (length *tool-calls*)
ASSERT each approval is boolean
```

## Scenario 4: Approval with timeout

### Setup

```lisp
(setf *tool-call* (make-instance 'tool-call
                                 :id "call_timeout"
                                 :name "sensitive_operation"
                                 :arguments nil))
```

### Steps

#### 1. Request approval with timeout

**Action**: Request with 5 second timeout
```lisp
(handler-case
    (request-tool-approval *tool* *tool-call*
                          (tool-call-arguments *tool-call*)
                          :timeout 5)
  (approval-timeout (e)
    (format t "Approval timed out~%")
    nil))
```

**Expected**:
- If user responds within 5s: returns approval decision
- If timeout: signals `approval-timeout` condition
- Default action: deny (fail-safe)

### Verification

```
ASSERT timeout triggers condition
ASSERT default action is deny
```

## Scenario 5: Custom approval UI

### Setup

```lisp
(defun custom-approval-ui (tool-name description arguments)
  "Custom approval interface"
  (format t "~%=== TOOL APPROVAL REQUIRED ===~%")
  (format t "Tool: ~A~%" tool-name)
  (format t "Description: ~A~%" description)
  (format t "Arguments: ~A~%" arguments)
  (format t "Approve? (y/n): ")
  (force-output)
  (char= (read-char) #\y))
```

### Steps

#### 1. Register custom UI

**Action**: Set custom approval handler
```lisp
(setf *approval-handler* #'custom-approval-ui)
```

#### 2. Request approval using custom UI

**Action**: Approval uses custom function
```lisp
(setf *approved* (funcall *approval-handler*
                         (tool-name *tool*)
                         (tool-description *tool*)
                         (tool-call-arguments *tool-call*)))
```

**Expected**:
- Custom UI displayed
- Returns boolean based on user input
- Integrates with existing approval workflow

### Verification

```
ASSERT custom UI is called
ASSERT returns boolean
ASSERT integrates with tool execution flow
```

## Scenario 6: Approval audit logging

### Setup

```lisp
(defvar *approval-log* nil)

(defun log-approval (tool-name arguments approved)
  (push (list :timestamp (get-universal-time)
              :tool tool-name
              :arguments arguments
              :approved approved)
        *approval-log*))
```

### Steps

#### 1. Request approval with logging

**Action**: Wrap approval with logging
```lisp
(let ((approved (request-tool-approval *tool* *tool-call*
                                       (tool-call-arguments *tool-call*))))
  (log-approval (tool-name *tool*)
                (tool-call-arguments *tool-call*)
                approved)
  approved)
```

**Expected**:
- Approval decision logged
- Log contains timestamp, tool, arguments, decision

#### 2. Verify audit trail

**Action**: Check log entries
```lisp
(first *approval-log*)
```

**Expected**:
- Contains complete approval record
- Timestamp present
- Decision recorded

### Verification

```
ASSERT *approval-log* not empty
ASSERT log entry contains required fields
ASSERT multiple approvals create separate entries
```

## Performance Criteria

- Approval UI display: < 100ms
- Approval decision capture: synchronous user input
- Batch approval: O(n) where n = number of tools
- Audit logging overhead: < 5ms per approval
- Timeout accuracy: ±100ms

## Safety Invariants

- **Default deny**: Timeout or error = denial, never auto-approve
- **Explicit approval**: User must actively confirm, not passive
- **Audit trail**: All approval decisions must be logged
- **No bypass**: Tools marked `requires-approval` cannot execute without approval
