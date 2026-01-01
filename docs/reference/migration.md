# Reference: Upgrading Existing Code

Guide for upgrading from older versions or other libraries.

---

## Version 1.x → Current

### API Changes

**Old**:
```lisp
(llm:complete messages :provider "anthropic")
```

**New**:
```lisp
(complete messages :provider (make-provider :anthropic))
```

Provider is now an object, not a string.

### Tool Calling Changes

**Old**:
```lisp
(llm:define-tool name description params handler)
```

**New**:
```lisp
(define-tool name description params
  :handler handler
  :safety-level :safe
  :categories '(:search))
```

Tools now support safety levels and categories.

### Response Object Changes

**Old**:
```lisp
(llm:response-text response)
(llm:response-tokens response)
```

**New**:
```lisp
(response-content response)
(response-token-count response)
```

All response accessors renamed for consistency.

---

## From Python Libraries

If you're migrating from Python:

### Python LiteLLM

**Python**:
```python
import litellm
response = litellm.completion(
  model="claude-3-sonnet",
  messages=[{"role": "user", "content": "Hello"}]
)
```

**Lisp (cl-llm-provider)**:
```lisp
(complete '((:role "user" :content "Hello"))
         :provider (make-provider :anthropic)
         :model "claude-3-sonnet-20240229")
```

**Key differences**:
- Model specified in `make-provider`, not globally
- Messages use keyword lists (plists), not dicts
- Responses are objects with accessors, not dicts

### Python OpenAI Library

**Python**:
```python
from openai import OpenAI
client = OpenAI()
response = client.chat.completions.create(
  model="gpt-4",
  messages=[{"role": "user", "content": "Hello"}]
)
print(response.choices[0].message.content)
```

**Lisp**:
```lisp
(let ((response (complete '((:role "user" :content "Hello"))
                         :provider (make-provider :openai)
                         :model "gpt-4")))
  (format t "~A~%" (response-content response)))
```

### Python Anthropic Library

**Python**:
```python
import anthropic
client = anthropic.Anthropic()
message = client.messages.create(
  model="claude-3-sonnet-20240229",
  messages=[{"role": "user", "content": "Hello"}]
)
print(message.content[0].text)
```

**Lisp**:
```lisp
(let ((response (complete '((:role "user" :content "Hello"))
                         :provider (make-provider :anthropic))))
  (format t "~A~%" (response-content response)))
```

---

## From Raw API Calls

If you're currently making raw API calls:

### Before: Raw HTTP

```lisp
(defun my-completion (prompt)
  (let* ((request (list
          :model "gpt-4"
          :messages (list
            (list :role "user" :content prompt))))
         (response (dexador:post
                   "https://api.openai.com/v1/chat/completions"
                   :headers (list
                     (cons "Authorization"
                          (format nil "Bearer ~A" (getenv "OPENAI_API_KEY"))))
                   :content (yason:encode-to-string request))))
    (let* ((parsed (yason:parse response))
           (content (getf (getf (first (getf parsed :choices)) :message)
                         :content)))
      content)))
```

### After: Using cl-llm-provider

```lisp
(defun my-completion (prompt)
  (response-content (complete (list (list :role "user" :content prompt))
                             :provider (make-provider :openai))))
```

**Benefits**:
- No HTTP details
- No API key management
- No JSON parsing
- Works with any provider
- Automatic error handling
- Token counting included

---

## Feature Migration

### Tool Calling

**Old way** (if you had it):
```lisp
;; Manually format tools, send, parse, handle
```

**New way**:
```lisp
(define-tool "search"
  "Search the web"
  '((:name "query" :type :string))
  :required '("query")
  :handler (lambda (args) ...))

(let ((response (complete messages :tools (list (get-tool "search")))))
  (when (response-tool-calls response)
    (dolist (call (response-tool-calls response))
      (execute-tool (getf call :name) (getf call :arguments)))))
```

### Token Counting

**Old way**:
```lisp
;; Approximate based on word count
(/ (length (split-string message " ")) 1.3)
```

**New way**:
```lisp
;; Accurate token counting
(token-count messages)
```

### Error Handling

**Old way**:
```lisp
(handler-case
  (dexador:post ...)
  (dexador-timeout-error (e) ...)
  (dexador-error (e) ...))
```

**New way**:
```lisp
(handler-case
  (complete messages)
  (rate-limit-error (e) ...)
  (timeout-error (e) ...)
  (network-error (e) ...)
  (authentication-error (e) ...))
```

### Provider Switching

**Old way**:
```lisp
;; Different code for each provider
(if (eq provider :openai)
  (call-openai-api ...)
  (call-anthropic-api ...))
```

**New way**:
```lisp
;; Same code for all providers
(complete messages :provider (make-provider provider))
```

---

## Testing Migration

### Before

```lisp
;; Mock HTTP calls
(let ((responses (list
        (cons "https://api.openai.com/..." "{...}"))))
  ;; Test code...
  )
```

### After

```lisp
;; Use mock providers
(let ((provider (make-mock-provider :openai)))
  (let ((response (complete messages :provider provider)))
    ;; Test code...
    ))
```

---

## Backward Compatibility

Old code will break. Here's how to fix common issues:

### Error 1: Unknown Provider Type

**Error**:
```
Unknown provider: "anthropic"
```

**Fix**: Use `make-provider` instead of string
```lisp
;; Old
(complete messages :provider "anthropic")

;; New
(complete messages :provider (make-provider :anthropic))
```

### Error 2: Response Accessor Not Found

**Error**:
```
Undefined function: RESPONSE-TEXT
```

**Fix**: Use new accessor names
```lisp
;; Old
(response-text response)

;; New
(response-content response)
```

### Error 3: Tool Handler Signature

**Error**:
```
Tool handler expects different argument format
```

**Fix**: Tool handlers now receive arguments as plists
```lisp
;; Old
(define-tool "search" ... (lambda (query limit) ...))

;; New
(define-tool "search" ... (lambda (args)
  (let ((query (getf args :query))
        (limit (getf args :limit)))
    ...)))
```

---

## Common Patterns

### Request Wrapper

If you had a wrapper function:

**Old**:
```lisp
(defun my-complete (message)
  ;; Custom logic
  (call-openai-api message))
```

**New**:
```lisp
(defun my-complete (message)
  ;; Custom logic
  (complete (list (list :role "user" :content message))))
```

### Error Retry

**Old**:
```lisp
(defun retry-complete (messages &key retries)
  (loop
    (handler-case
      (return (call-api messages))
      (api-timeout-error (e)
        (if (> retries 0)
          (progn
            (decf retries)
            (sleep 1))
          (error e))))))
```

**New**:
```lisp
(defun retry-complete (messages &key (max-retries 3))
  (loop
    (handler-case
      (return (complete messages))
      ((or timeout-error network-error) (e)
        (if (< retry-count max-retries)
          (progn
            (incf retry-count)
            (sleep (expt 2 retry-count)))
          (error e))))))
```

### Provider Configuration

**Old**:
```lisp
(defvar *api-provider* "openai")
(defvar *api-key* (getenv "OPENAI_API_KEY"))

(defun make-request (messages)
  (dexador:post (make-url *api-provider*)
               :headers (list (cons "Authorization" *api-key*))
               ...))
```

**New**:
```lisp
(defvar *provider* (make-provider :openai))

(defun make-request (messages)
  (complete messages :provider *provider*))
```

---

## Checklist for Upgrading

- [ ] Replace provider strings with `(make-provider :keyword)`
- [ ] Update response accessor names
- [ ] Update tool handler signatures to receive `args` plist
- [ ] Replace raw HTTP calls with `complete`
- [ ] Replace error types with standard cl-llm-provider errors
- [ ] Test with new provider instances
- [ ] Update token counting to use `token-count`
- [ ] Add proper error handling with `handler-case`
- [ ] Run full test suite

---

**See Also**:
- [Quick Start](../quickstart.md)
- [Reference: Complete API](api.md)
- [How-To: Error Handling](../how-to/error-handling.md)
