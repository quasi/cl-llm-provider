---
type: scenario
name: tool-registry-management
version: 0.1.0
feature: tools
covers:
  - tool-registry
tags:
  - happy-path
  - registry
---

# Tool Registry - Management and Lookup

## Context

Application needs to register, lookup, and manage tool definitions in a central registry for reuse across completion requests.

## Scenario 1: Register and lookup tool

### Setup

```lisp
(setf *registry* (make-tool-registry))
(setf *tool* (define-tool "calculator"
                          "Perform calculations"
                          '((:name "expression" :type :string :required t))))
```

### Steps

#### 1. Register tool

**Action**: Add tool to registry
```lisp
(register-tool *registry* *tool*)
```

**Expected**:
- Tool stored in registry
- No error raised
- Can be retrieved later

#### 2. Lookup tool by name

**Action**: Retrieve registered tool
```lisp
(setf *found* (lookup-tool *registry* "calculator"))
```

**Expected**:
- Returns tool definition object
- Tool is `eq` or `equal` to original
- Has same name and description

#### 3. Verify tool contents

**Action**: Check tool properties
```lisp
(list :name (tool-name *found*)
      :description (tool-description *found*)
      :parameters (tool-parameters *found*))
```

**Expected**:
- Name = "calculator"
- Description matches original
- Parameters list matches definition

### Verification

```
ASSERT (lookup-tool *registry* "calculator") != nil
ASSERT (tool-name *found*) == "calculator"
ASSERT (length (tool-parameters *found*)) == 1
```

## Scenario 2: Replace existing tool

### Setup

```lisp
(setf *registry* (make-tool-registry))
(setf *tool-v1* (define-tool "weather" "Get weather" '((:name "city" :type :string))))
(setf *tool-v2* (define-tool "weather" "Get detailed weather"
                             '((:name "city" :type :string)
                               (:name "units" :type :string))))
```

### Steps

#### 1. Register initial version

**Action**: Register v1
```lisp
(register-tool *registry* *tool-v1*)
```

#### 2. Attempt replace without flag

**Action**: Try to re-register without `:replace`
```lisp
(handler-case
    (register-tool *registry* *tool-v2*)
  (tool-already-registered (e) :error))
```

**Expected**:
- Signals `tool-already-registered` condition
- Original tool unchanged
- Returns `:error`

#### 3. Replace with flag

**Action**: Register with `:replace t`
```lisp
(register-tool *registry* *tool-v2* :replace t)
(setf *current* (lookup-tool *registry* "weather"))
```

**Expected**:
- No error
- Lookup returns v2 (updated version)
- Has 2 parameters instead of 1

### Verification

```
ASSERT (length (tool-parameters *current*)) == 2
ASSERT (tool-description *current*) == "Get detailed weather"
```

## Scenario 3: List all registered tools

### Setup

```lisp
(setf *registry* (make-tool-registry))
(register-tool *registry* (define-tool "tool1" "First tool" nil))
(register-tool *registry* (define-tool "tool2" "Second tool" nil))
(register-tool *registry* (define-tool "tool3" "Third tool" nil))
```

### Steps

#### 1. Get all tools

**Action**: List registry contents
```lisp
(setf *all-tools* (list-tools *registry*))
```

**Expected**:
- Returns list of 3 tool definitions
- All registered tools present
- Order may vary

#### 2. Get tool names

**Action**: Extract names
```lisp
(mapcar #'tool-name *all-tools*)
```

**Expected**:
- Returns list of strings
- Contains "tool1", "tool2", "tool3"

### Verification

```
ASSERT (length *all-tools*) == 3
ASSERT tool names include "tool1", "tool2", "tool3"
```

## Scenario 4: Lookup non-existent tool

### Setup

```lisp
(setf *registry* (make-tool-registry))
```

### Steps

#### 1. Lookup missing tool

**Action**: Attempt to find unregistered tool
```lisp
(lookup-tool *registry* "nonexistent")
```

**Expected**:
- Returns `nil`
- No error raised
- Registry unchanged

### Verification

```
ASSERT (lookup-tool *registry* "nonexistent") == nil
ASSERT (length (list-tools *registry*)) == 0
```

## Scenario 5: Remove tool from registry

### Setup

```lisp
(setf *registry* (make-tool-registry))
(register-tool *registry* (define-tool "temporary" "Temp tool" nil))
```

### Steps

#### 1. Verify tool exists

**Action**: Confirm tool is registered
```lisp
(lookup-tool *registry* "temporary")
```

**Expected**: Returns tool definition

#### 2. Remove tool

**Action**: Unregister tool
```lisp
(unregister-tool *registry* "temporary")
```

**Expected**:
- Tool removed from registry
- No error

#### 3. Verify removal

**Action**: Try to lookup removed tool
```lisp
(lookup-tool *registry* "temporary")
```

**Expected**:
- Returns `nil`
- Tool no longer in registry

### Verification

```
ASSERT (lookup-tool *registry* "temporary") == nil
ASSERT (length (list-tools *registry*)) == 0
```

## Performance Criteria

- Register tool: O(1) hash table insert, < 1ms
- Lookup tool: O(1) hash table access, < 1μs
- List tools: O(n) where n = number of tools, < 1ms for typical registries
- No memory leaks on repeated register/unregister
