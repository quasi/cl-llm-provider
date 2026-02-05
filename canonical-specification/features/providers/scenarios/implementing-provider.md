---
type: scenario
name: implementing-provider
version: 0.1.0
feature: providers
covers:
  - provider-protocol
tags:
  - happy-path
  - extensibility
---

# Provider Protocol - Implementing a New Provider

## Context

Developer wants to add support for a new LLM provider by implementing the provider protocol. The protocol requires specific generic functions to be implemented.

## Scenario 1: Minimal provider implementation

### Setup

```lisp
;; Define new provider class
(defclass minimal-provider (llm-provider)
  ((api-key :initarg :api-key :accessor provider-api-key)
   (base-url :initarg :base-url :accessor provider-base-url)))
```

### Steps

#### 1. Implement provider-type

**Action**: Define provider type identifier
```lisp
(defmethod provider-type ((provider minimal-provider))
  :minimal)
```

**Expected**:
- Returns keyword identifying provider
- Consistent across all instances

**Verification**: `(provider-type (make-instance 'minimal-provider))` → `:minimal`

#### 2. Implement provider-name

**Action**: Define human-readable name
```lisp
(defmethod provider-name ((provider minimal-provider))
  "Minimal Provider")
```

**Expected**:
- Returns string suitable for display
- Descriptive name

**Verification**: `(provider-name (make-instance 'minimal-provider))` → `"Minimal Provider"`

#### 3. Implement provider-capabilities

**Action**: Declare supported features
```lisp
(defmethod provider-capabilities ((provider minimal-provider))
  '(:tools nil
    :embeddings nil
    :streaming t
    :vision nil))
```

**Expected**:
- Returns plist of capabilities
- Boolean values for each capability
- Supports streaming only

**Verification**: `(getf (provider-capabilities provider) :streaming)` → `t`

#### 4. Implement send-completion-request

**Action**: Define HTTP request method
```lisp
(defmethod send-completion-request ((provider minimal-provider) messages
                                   &key model max-tokens temperature
                                        system tools tool-choice stop)
  (let ((request-body (make-hash-table :test 'equal)))
    (setf (gethash "messages" request-body) messages)
    (when model (setf (gethash "model" request-body) model))
    (when max-tokens (setf (gethash "max_tokens" request-body) max-tokens))
    ;; Make HTTP POST to provider API
    (http-request (concatenate 'string
                              (provider-base-url provider)
                              "/chat/completions")
                 :method :post
                 :headers `(("Authorization" . ,(format nil "Bearer ~A"
                                                       (provider-api-key provider)))
                          ("Content-Type" . "application/json"))
                 :json request-body)))
```

**Expected**:
- Sends HTTP POST to provider endpoint
- Returns raw response hash-table
- Handles authentication

#### 5. Implement parse-completion-response

**Action**: Parse provider response format
```lisp
(defmethod parse-completion-response ((provider minimal-provider) raw-response
                                     &key performance)
  (let ((id (gethash "id" raw-response))
        (model (gethash "model" raw-response))
        (choices (gethash "choices" raw-response))
        (usage (gethash "usage" raw-response)))
    (let ((first-choice (elt choices 0)))
      (make-instance 'completion-response
                    :id id
                    :model model
                    :content (gethash "content" (gethash "message" first-choice))
                    :finish-reason (intern (string-upcase
                                           (gethash "finish_reason" first-choice))
                                          :keyword)
                    :usage (list :prompt-tokens (gethash "prompt_tokens" usage)
                               :completion-tokens (gethash "completion_tokens" usage)
                               :total-tokens (gethash "total_tokens" usage))
                    :raw raw-response
                    :performance performance))))
```

**Expected**:
- Extracts fields from provider-specific format
- Returns normalized `completion-response` object
- Preserves raw response

### Verification

```
ASSERT (provider-type provider) == :minimal
ASSERT (provider-capabilities provider) contains :streaming
ASSERT (send-completion-request provider messages) returns hash-table
ASSERT (parse-completion-response provider response) returns completion-response
```

## Scenario 2: Use new provider with complete API

### Setup

```lisp
(setf *provider* (make-instance 'minimal-provider
                               :api-key "test-key"
                               :base-url "https://api.minimal.com"))
(setf *messages* '((:role "user" :content "Hello")))
```

### Steps

#### 1. Call complete with new provider

**Action**: Use high-level API
```lisp
(setf *response* (complete *messages*
                           :provider *provider*
                           :model "minimal-model-1"))
```

**Expected**:
- `complete` function works with new provider
- Calls `send-completion-request` and `parse-completion-response`
- Returns normalized response

#### 2. Verify response structure

**Action**: Check response fields
```lisp
(list :id (response-id *response*)
      :model (response-model *response*)
      :content (response-content *response*)
      :finish-reason (response-finish-reason *response*))
```

**Expected**:
- All standard response fields present
- Provider-agnostic structure
- Works like any other provider

### Verification

```
ASSERT (response-id *response*) != nil
ASSERT (response-finish-reason *response*) in (:stop :length :tool-calls)
ASSERT (response-usage *response*) contains token counts
```

## Scenario 3: Add streaming support

### Setup

```lisp
;; Already have minimal-provider class
```

### Steps

#### 1. Implement send-streaming-request

**Action**: Add streaming method
```lisp
(defmethod send-streaming-request ((provider minimal-provider) messages
                                  &key model max-tokens temperature
                                       system tools tool-choice stop)
  (let ((request-body (make-hash-table :test 'equal)))
    (setf (gethash "messages" request-body) messages)
    (setf (gethash "stream" request-body) t)
    (when model (setf (gethash "model" request-body) model))
    ;; Return HTTP stream
    (http-stream-request (concatenate 'string
                                     (provider-base-url provider)
                                     "/chat/completions")
                        :method :post
                        :headers (auth-headers provider)
                        :json request-body)))
```

**Expected**:
- Sets `stream: true` in request
- Returns HTTP stream object

#### 2. Implement parse-stream-chunk

**Action**: Parse SSE events
```lisp
(defmethod parse-stream-chunk ((provider minimal-provider) data index)
  (cond
    ((string= data "[DONE]") :done)
    ((string= data "") nil)
    (t (let* ((json (yason:parse data))
              (delta (gethash "delta" (elt (gethash "choices" json) 0)))
              (content (gethash "content" delta)))
         (make-instance 'stream-chunk
                       :delta (or content "")
                       :index index
                       :finish-reason nil)))))
```

**Expected**:
- Parses SSE data into stream-chunk
- Returns `:done` when complete
- Returns `nil` for empty events

#### 3. Use streaming

**Action**: Call complete-stream
```lisp
(setf *stream* (complete-stream *messages*
                                :provider *provider*
                                :model "minimal-model-1"))

(loop for chunk = (read-stream-chunk *stream*)
      until (eq chunk :done)
      collect (stream-chunk-delta chunk))
```

**Expected**:
- Stream created successfully
- Chunks arrive incrementally
- Final chunk signals done

### Verification

```
ASSERT stream created
ASSERT chunks have sequential indices
ASSERT final chunk returns :done
```

## Scenario 4: Add tool support

### Setup

```lisp
;; Update capabilities
(defmethod provider-capabilities ((provider minimal-provider))
  '(:tools t
    :embeddings nil
    :streaming t
    :vision nil))
```

### Steps

#### 1. Implement translate-tool-to-provider

**Action**: Convert tool definition to provider format
```lisp
(defmethod translate-tool-to-provider ((provider minimal-provider) tool-def)
  (let ((schema (make-hash-table :test 'equal)))
    (setf (gethash "name" schema) (tool-name tool-def))
    (setf (gethash "description" schema) (tool-description tool-def))
    (setf (gethash "parameters" schema)
          (parameters-to-json-schema (tool-parameters tool-def)))
    schema))
```

**Expected**:
- Converts tool to provider-specific format
- Returns hash-table with tool schema

#### 2. Implement parse-tool-calls

**Action**: Extract tool calls from response
```lisp
(defmethod parse-tool-calls ((provider minimal-provider) raw-response)
  (let ((tool-calls (gethash "tool_calls"
                            (gethash "message"
                                    (elt (gethash "choices" raw-response) 0)))))
    (when tool-calls
      (map 'list
           (lambda (tc)
             (make-instance 'tool-call
                           :id (gethash "id" tc)
                           :name (gethash "name" (gethash "function" tc))
                           :arguments (yason:parse (gethash "arguments"
                                                           (gethash "function" tc)))))
           tool-calls))))
```

**Expected**:
- Extracts tool calls from provider response
- Returns list of tool-call objects
- Returns `nil` if no tool calls

### Verification

```
ASSERT tools translated to provider format
ASSERT tool calls parsed correctly
ASSERT (complete messages :tools tools :provider provider) works
```

## Scenario 5: Error handling

### Setup

```lisp
;; minimal-provider already defined
```

### Steps

#### 1. Handle HTTP errors

**Action**: Add error handling to send-completion-request
```lisp
(defmethod send-completion-request ((provider minimal-provider) messages &key &allow-other-keys)
  (handler-case
      (progn
        ;; ... make HTTP request ...
        )
    (http-error (e)
      (let ((status (http-error-status e)))
        (cond
          ((= status 401)
           (error 'provider-authentication-error
                  :provider provider
                  :message "Invalid API key"))
          ((= status 429)
           (error 'provider-rate-limit-error
                  :provider provider
                  :retry-after (http-error-retry-after e)))
          (t
           (error 'provider-api-error
                  :provider provider
                  :status status
                  :message (http-error-message e))))))))
```

**Expected**:
- HTTP 401 → `provider-authentication-error`
- HTTP 429 → `provider-rate-limit-error`
- Other errors → `provider-api-error`

#### 2. Test error conditions

**Action**: Trigger various errors
```lisp
;; Invalid API key
(handler-case
    (complete messages :provider (make-instance 'minimal-provider
                                               :api-key "invalid"))
  (provider-authentication-error (e) :auth-error))

;; Rate limit
(handler-case
    (loop repeat 100 do (complete messages :provider provider))
  (provider-rate-limit-error (e)
    (format t "Rate limited, retry after ~A seconds~%"
            (provider-error-retry-after e))))
```

**Expected**:
- Errors signaled correctly
- Error types match conditions
- Retry information available

### Verification

```
ASSERT authentication errors signaled for 401
ASSERT rate limit errors signaled for 429
ASSERT errors include provider and message
```

## Performance Criteria

- Provider instantiation: < 1ms
- Method dispatch overhead: < 1μs per call
- Response parsing: < 10ms for typical response
- Error handling: no performance degradation

## Integration Criteria

- Works with `complete` and `complete-stream`
- Supports all standard parameters
- Error conditions propagate correctly
- Provider config summary excludes sensitive data
