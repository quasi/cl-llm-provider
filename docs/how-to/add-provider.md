# How-To: Add a New Provider

Integrate a new LLM provider into cl-llm-provider.

**Prerequisites**: Understand the [protocol architecture](../explanation/architecture.md).

---

## Overview

Each provider implementation requires:
1. **Provider class** - Subclass of `llm-provider`
2. **Protocol methods** - Implement the required generic functions
3. **HTTP integration** - Format requests and parse responses
4. **Tests** - Verify correct behavior

## Step 1: Create the Provider Class

Create a new file `src/providers/my-provider.lisp`:

```lisp
(in-package :cl-llm-provider)

(defclass my-provider (llm-provider)
  ()
  (:documentation "Integration with MyLLM service"))
```

Add to `src/providers.lisp` to export:

```lisp
(defun make-provider (provider-type &rest args)
  "Create a provider instance."
  (case provider-type
    (:my-provider (apply #'make-instance 'my-provider args))
    ...))
```

## Step 2: Implement Required Methods

Every provider must implement these generic functions:

### 2.1 Completion Request

```lisp
(defmethod send-completion-request
    ((provider my-provider)
     messages
     &key
     model
     max-tokens
     temperature
     system
     tools
     tool-choice
     stop)
  "Send completion request to MyLLM API"

  ;; Resolve defaults
  (let* ((model (or model (provider-default-model provider)))
         (api-key (provider-api-key provider))
         (base-url (provider-base-url provider)))

    ;; Validate configuration
    (unless api-key
      (error 'authentication-error
             :message "MyLLM requires MYPROVIDER_API_KEY"))
    (unless model
      (error 'provider-configuration-error
             :message "MyLLM requires model specification"))

    ;; Normalize messages to provider format
    (let* ((normalized-messages (normalize-messages-for-my-provider messages))

           ;; Format the request
           (request-body (format-completion-request-my-provider
                         :messages normalized-messages
                         :model model
                         :max-tokens max-tokens
                         :temperature temperature
                         :system system
                         :tools tools
                         :tool-choice tool-choice
                         :stop stop))

           ;; Make HTTP request
           (response (dexador:post
                     (format nil "~A/v1/completions" base-url)
                     :headers (list (cons "Authorization" (format nil "Bearer ~A" api-key))
                                   (cons "Content-Type" "application/json"))
                     :content (yason:encode-to-string request-body))))

      ;; Parse response
      (parse-completion-response-my-provider response))))
```

### 2.2 Embedding Request

```lisp
(defmethod send-embedding-request
    ((provider my-provider)
     texts
     &key model)
  "Send embedding request to MyLLM API"

  (let* ((model (or model (provider-default-model provider)))
         (api-key (provider-api-key provider))
         (base-url (provider-base-url provider)))

    ;; Normalize input (single string or list)
    (let ((text-list (if (listp texts) texts (list texts))))

      ;; Format request
      (let ((request-body (list
             :input text-list
             :model model)))

        ;; Make request
        (let ((response (dexador:post
                        (format nil "~A/v1/embeddings" base-url)
                        :headers (list (cons "Authorization" (format nil "Bearer ~A" api-key))
                                      (cons "Content-Type" "application/json"))
                        :content (yason:encode-to-string request-body))))

          ;; Parse response
          (parse-embedding-response-my-provider response))))))
```

## Step 3: Message Normalization

Convert between cl-llm-provider format and provider format:

```lisp
(defun normalize-messages-for-my-provider (messages)
  "Convert messages to MyLLM format."
  (mapcar (lambda (msg)
           (list
            :role (string-downcase (getf msg :role))
            :content (getf msg :content)))
         messages))

(defun denormalize-message-from-my-provider (response-msg)
  "Convert MyLLM response to cl-llm-provider format."
  (list
   :role (string-upcase (getf response-msg :role))
   :content (getf response-msg :content)))
```

## Step 4: Tool Definition Conversion

Convert tool definitions to provider format:

```lisp
(defun convert-tools-to-my-provider (tools)
  "Convert tools to MyLLM function calling format."
  (mapcar (lambda (tool)
           (list
            :name (tool-name tool)
            :description (tool-description tool)
            :parameters (format-parameters-for-my-provider
                        (tool-parameters tool))
            :required (tool-required-parameters tool)))
         tools))

(defun format-parameters-for-my-provider (parameters)
  "Convert parameter definitions to MyLLM schema."
  ;; MyLLM uses JSON Schema for parameters
  (list
   :type "object"
   :properties (let ((props (make-hash-table)))
                 (dolist (param parameters props)
                   (setf (gethash (getf param :name) props)
                        (list
                         :type (getf param :type)
                         :description (getf param :description "")))))
   :required (mapcar #'tool-name tools)))
```

## Step 5: Response Parsing

Parse provider responses into `completion-response` objects:

```lisp
(defun parse-completion-response-my-provider (http-response)
  "Parse MyLLM API response."
  (let* ((body (yason:parse http-response))
         (message (getf body :message))
         (content (getf message :content))
         (tool-calls (parse-tool-calls-my-provider (getf body :tool_calls)))
         (usage (getf body :usage)))

    ;; Create response object
    (make-instance 'completion-response
                  :id (getf body :id)
                  :model (getf body :model)
                  :content content
                  :message (denormalize-message-from-my-provider message)
                  :tool-calls tool-calls
                  :token-count (getf usage :total_tokens)
                  :finish-reason (parse-finish-reason (getf body :finish_reason))
                  :provider 'my-provider
                  :metadata body)))

(defun parse-tool-calls-my-provider (tool-calls-data)
  "Extract tool calls from response."
  (mapcar (lambda (call)
           (list
            :name (getf call :function :name)
            :arguments (yason:parse (getf call :function :arguments))))
         tool-calls-data))

(defun parse-finish-reason (reason-string)
  "Convert provider finish reason to standard keyword."
  (cond
    ((string= reason-string "stop") :stop)
    ((string= reason-string "length") :length)
    ((string= reason-string "tool_calls") :tool-calls)
    (t :unknown)))
```

## Step 6: Error Handling

Handle provider-specific errors:

```lisp
(defun handle-my-provider-error (http-status body)
  "Convert HTTP errors to cl-llm-provider error types."
  (let ((error-code (getf body :error :code)))
    (cond
      ;; Rate limiting
      ((= http-status 429)
       (error 'rate-limit-error
              :message "Rate limited by MyLLM API"))

      ;; Authentication
      ((or (= http-status 401) (string= error-code "invalid_api_key"))
       (error 'authentication-error
              :message "Invalid API key for MyLLM"))

      ;; Model not found
      ((string= error-code "model_not_found")
       (error 'provider-error
              :message (format nil "Model not found: ~A" (getf body :model))))

      ;; Server errors
      ((>= http-status 500)
       (error 'network-error
              :message "MyLLM server error"))

      ;; Default
      (t (error 'provider-error
                :message (getf body :error :message))))))
```

## Step 7: Tests

Create comprehensive tests in `tests/test-my-provider.lisp`:

```lisp
(in-package :cl-llm-provider-tests)

(def-suite my-provider-tests :description "MyLLM provider tests")
(in-suite my-provider-tests)

;; Test initialization
(test my-provider-creation
  "Test creating a MyLLM provider"
  (let ((provider (make-provider :my-provider :api-key "test-key")))
    (is (typep provider 'my-provider))
    (is (string= (provider-api-key provider) "test-key"))))

;; Test message normalization
(test message-normalization
  "Test message format conversion"
  (let* ((messages '((:role "user" :content "Hello")))
         (normalized (normalize-messages-for-my-provider messages)))
    (is (string= (getf (first normalized) :role) "user"))
    (is (string= (getf (first normalized) :content) "Hello"))))

;; Test tool conversion
(test tool-conversion
  "Test tool definition conversion"
  (let* ((tools (list (get-tool "search")))
         (converted (convert-tools-to-my-provider tools)))
    (is (= (length converted) 1))
    (is (string= (getf (first converted) :name) "search"))))

;; Test error handling
(test error-handling
  "Test error handling"
  (signals authentication-error
    (handle-my-provider-error 401 (list :error (list :code "invalid_api_key")))))
```

Run tests:

```bash
sbcl --noinform --non-interactive \
  --eval '(asdf:test-system :cl-llm-provider)'
```

## Step 8: Update Exports

Add your provider to the main package:

In `src/package.lisp`:
```lisp
(defpackage :cl-llm-provider
  (:export
   ...
   #:my-provider
   ...))
```

## Complete Minimal Example

Here's a minimal but complete provider for a hypothetical service:

```lisp
(in-package :cl-llm-provider)

(defclass minillm-provider (llm-provider)
  ()
  (:documentation "Integration with MiniLLM service"))

(defmethod send-completion-request
    ((provider minillm-provider)
     messages
     &key model max-tokens temperature system tools tool-choice stop)

  (let* ((api-key (provider-api-key provider))
         (request-body (list
          :messages messages
          :model (or model "mini")
          :max-tokens (or max-tokens 256)
          :temperature (or temperature 0.7))))

    (let ((response (dexador:post
                    "https://api.minillm.io/v1/completions"
                    :headers (list (cons "Authorization" (format nil "Bearer ~A" api-key)))
                    :content (yason:encode-to-string request-body))))

      (let* ((body (yason:parse response))
             (message (getf body :message)))
        (make-instance 'completion-response
                      :content (getf message :content)
                      :message message
                      :model (or model "mini")
                      :provider 'minillm-provider)))))
```

## Verification Checklist

Before submitting:

- ✅ All required generic functions implemented
- ✅ Message normalization working correctly
- ✅ Tool definitions converted properly
- ✅ Responses parsed into correct objects
- ✅ Error handling implemented
- ✅ Tests passing
- ✅ Documentation updated

---

**See Also**:
- [Explanation: Protocol Architecture](../explanation/architecture.md)
- [Reference: API Specification](../reference/api.md)
