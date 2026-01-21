# Adding New Providers

This guide explains how to implement support for a new LLM provider in cl-llm-provider.

## Overview

Each provider implementation consists of:

1. **Provider Class** - Subclass of `llm-provider`
2. **Required Methods** - Implement the protocol contract
3. **Optional Methods** - Override defaults for special behavior
4. **Tests** - Verify correct behavior

## Step-by-Step Implementation

### 1. Create the Provider Class

Create a new file `src/providers/my-provider.lisp`:

```lisp
(in-package :cl-llm-provider)

(defclass my-provider (llm-provider)
  ()
  (:documentation "Integration with MyLLM service"))
```

### 2. Implement Required Methods

#### 2.1 Completion Request Method

```lisp
(defmethod send-completion-request
    ((provider my-provider) messages
     &key model max-tokens temperature system tools tool-choice stop)
  "Send completion request to MyLLM API"

  ;; Resolve defaults
  (let* ((model (or model (provider-default-model provider)))
         (base-url (provider-default-base-url provider))
         (api-key (provider-api-key provider)))

    ;; Validate required parameters
    (unless api-key
      (error 'provider-configuration-error
             :message "MyLLM requires API key"
             :provider provider))
    (unless model
      (error 'provider-configuration-error
             :message "MyLLM requires model specification"
             :provider provider))

    ;; Build request body
    (let ((request-body (make-hash-table :test 'equal)))
      ;; Add messages
      (setf (gethash "messages" request-body)
            (mapcar (lambda (msg)
                      (plist-to-hash msg))
                    messages))

      ;; Add model
      (setf (gethash "model" request-body) model)

      ;; Add optional parameters
      (when max-tokens
        (setf (gethash "max_tokens" request-body) max-tokens))
      (when temperature
        (setf (gethash "temperature" request-body) temperature))
      (when stop
        (setf (gethash "stop" request-body) stop))

      ;; Add system message if provided
      (when system
        (setf (gethash "system" request-body) system))

      ;; Translate tools if provided
      (when tools
        (setf (gethash "tools" request-body)
              (mapcar (lambda (tool)
                        (translate-tool-to-provider provider tool))
                      tools)))

      ;; Add tool choice if specified
      (when tool-choice
        ;; MyLLM tool choice format (if different from OpenAI)
        (etypecase tool-choice
          (keyword (setf (gethash "tool_choice" request-body)
                        (string-downcase (symbol-name tool-choice))))
          (string (setf (gethash "tool_choice" request-body)
                       (make-hash-table :test 'equal)))))

      ;; Make HTTP request
      (handler-case
          (let ((response (dex:post
                          (format nil "~A/v1/chat/completions" base-url)
                          :headers `(("Authorization" . ,(format nil "Bearer ~A" api-key))
                                    ("Content-Type" . "application/json"))
                          :content (yason:encode-to-string request-body))))
            ;; Parse response JSON
            (yason:parse response :object-as :hash-table))

        ;; Handle HTTP errors
        (dex:http-request-failed (e)
          (handle-http-error provider e))))))
```

#### 2.2 Response Parsing Method

```lisp
(defmethod parse-completion-response
    ((provider my-provider) raw-response &key performance)
  "Parse MyLLM response into normalized completion-response"

  (let* (;; Extract top-level fields
         (id (gethash "id" raw-response))
         (model (gethash "model" raw-response))

         ;; Extract choice (MyLLM uses "choices" array)
         (choice (aref (gethash "choices" raw-response) 0))
         (message (gethash "message" choice))
         (content (gethash "content" message))
         (finish-reason (string-to-keyword
                        (gethash "finish_reason" choice)))

         ;; Extract tool calls if present
         (tool-calls (when (gethash "tool_calls" message)
                       (parse-tool-calls provider raw-response)))

         ;; Extract usage
         (usage-obj (gethash "usage" raw-response))
         (usage (list :prompt-tokens (gethash "prompt_tokens" usage-obj)
                     :completion-tokens (gethash "completion_tokens" usage-obj)
                     :total-tokens (gethash "total_tokens" usage-obj)))

         ;; Extract metadata
         (metadata (extract-metadata provider raw-response)))

    ;; Create response object
    (make-instance 'completion-response
                  :id id
                  :model model
                  :content content
                  :message (hash-table-plist message)
                  :tool-calls tool-calls
                  :finish-reason finish-reason
                  :usage usage
                  :raw raw-response
                  :performance performance
                  :metadata metadata)))

;; Helper to extract provider-specific metadata
(defun extract-metadata (provider raw-response)
  (let ((metadata nil))
    ;; MyLLM-specific metadata fields
    (when-let ((created (gethash "created" raw-response)))
      (setf (getf metadata :created) created))
    (when-let ((system-fp (gethash "system_fingerprint" raw-response)))
      (setf (getf metadata :system-fingerprint) system-fp))
    metadata))
```

#### 2.3 Tool Translation Method (if different from default)

```lisp
(defmethod translate-tool-to-provider
    ((provider my-provider) tool-definition)
  "Translate tool to MyLLM format (if different from OpenAI)"

  ;; MyLLM uses OpenAI format, so use default
  (call-next-method))
```

#### 2.4 Tool Call Parsing Method (if different from default)

```lisp
(defmethod parse-tool-calls
    ((provider my-provider) raw-response)
  "Parse tool calls from MyLLM response"

  ;; If MyLLM follows OpenAI format, use default
  (call-next-method))
```

### 3. Implement Optional Methods

#### 3.1 Default Base URL

```lisp
(defmethod provider-default-base-url
    ((provider my-provider))
  "https://api.myservice.com")
```

#### 3.2 API Key Environment Variable

```lisp
(defmethod provider-api-key-env-var
    ((provider my-provider))
  "MYSERVICE_API_KEY")
```

#### 3.3 Embedding Support (if available)

```lisp
(defmethod send-embedding-request
    ((provider my-provider) input &key model dimensions)
  "Send embedding request to MyLLM"

  (let* ((api-key (provider-api-key provider))
         (request-body (make-hash-table :test 'equal)))

    ;; Build embedding request
    (setf (gethash "input" request-body)
          (if (stringp input) input input))
    (when model
      (setf (gethash "model" request-body) model))
    (when dimensions
      (setf (gethash "dimensions" request-body) dimensions))

    ;; Make HTTP request
    (handler-case
        (let ((response (dex:post
                        (format nil "~A/v1/embeddings"
                               (provider-default-base-url provider))
                        :headers `(("Authorization" . ,(format nil "Bearer ~A" api-key))
                                  ("Content-Type" . "application/json"))
                        :content (yason:encode-to-string request-body))))
          (yason:parse response :object-as :hash-table))

      (dex:http-request-failed (e)
        (handle-http-error provider e)))))

(defmethod parse-embedding-response
    ((provider my-provider) raw-response &key performance)
  "Parse MyLLM embedding response"

  (let ((embeddings (mapcar (lambda (item)
                              (coerce (gethash "embedding" item) 'list))
                           (gethash "data" raw-response)))
        (usage (let ((u (gethash "usage" raw-response)))
                (list :prompt-tokens (gethash "prompt_tokens" u)
                     :total-tokens (gethash "total_tokens" u)))))

    (make-instance 'embedding-response
                  :embeddings embeddings
                  :model (gethash "model" raw-response)
                  :usage usage
                  :raw raw-response
                  :performance performance
                  :metadata nil)))
```

### 4. Export Provider in Package

Add to `src/package.lisp`:

```lisp
(defclass my-provider)
```

Add to the `make-provider` function in `src/api.lisp`:

```lisp
(defmethod make-provider ((type (eql :myservice)) &key &allow-other-keys)
  (apply #'make-provider-instance 'my-provider arguments))
```

### 5. Write Tests

Create `tests/test-my-provider.lisp`:

```lisp
(require :asdf)
(ql:quickload :fiveam :silent t)

(load "src/package.lisp")
(load "src/conditions.lisp")
(load "src/types.lisp")
(load "src/protocol.lisp")
(load "src/api.lisp")
(load "src/tools.lisp")
(load "src/config.lisp")
(load "src/providers/my-provider.lisp")

(in-package :cl-llm-provider)

(fiveam:def-suite my-provider-suite)
(fiveam:in-suite my-provider-suite)

;;; Test provider creation
(fiveam:test create-my-provider
  "Create MyLLM provider"
  (let ((provider (make-provider :myservice
                                :api-key "test-key"
                                :model "my-model")))
    (fiveam:is (typep provider 'my-provider))
    (fiveam:is (string= (provider-api-key provider) "test-key"))))

;;; Test default URL
(fiveam:test my-provider-default-url
  "MyLLM should have correct default URL"
  (let ((provider (make-provider :myservice :api-key "test" :model "test")))
    (fiveam:is (string= (provider-default-base-url provider)
                       "https://api.myservice.com"))))

;;; Test tool support
(fiveam:test my-provider-tool-translation
  "Tools should translate correctly"
  (let ((provider (make-provider :myservice :api-key "test" :model "test"))
        (tool (make-instance 'tool-definition
                            :name "my_tool"
                            :description "Test tool"
                            :parameters nil)))
    ;; Verify tool translates without error
    (fiveam:is (translate-tool-to-provider provider tool))))

;;; More tests...

(format t "~%=== Running MyLLM Provider Tests ===~%~%")
(fiveam:run! 'my-provider-suite)
```

## Helper Functions

The library provides utility functions to help with implementation:

### Message/Hash Conversion

```lisp
;; Convert plist message to hash table
(plist-to-hash '(:role "user" :content "Hello"))
; => #<HASH-TABLE ...>

;; Convert hash table to plist
(hash-table-plist hash-table)
; => (:role "user" :content "Hello")
```

### String/Keyword Conversion

```lisp
(string-to-keyword "stop")      ; => :STOP
(keyword-to-string :stop)       ; => "stop"
```

### Error Handling

```lisp
;; Wrap HTTP errors into provider errors
(defun handle-http-error (provider error)
  (let ((status (dex:response-status error))
        (body (dex:response-body error)))
    (cond
      ((= status 401)
       (error 'provider-authentication-error
              :message "Invalid API key"
              :provider provider
              :status-code 401))
      ((= status 429)
       (error 'provider-rate-limit-error
              :message "Rate limited"
              :provider provider
              :status-code 429
              :retry-after 60))
      (t
       (error 'provider-api-error
              :message (extract-error-message body)
              :provider provider
              :status-code status
              :body body)))))
```

## Testing Checklist

When implementing a new provider, test:

- [ ] Provider creation and initialization
- [ ] Default URL and env var lookup
- [ ] Simple completion request
- [ ] Multi-turn conversations
- [ ] System message handling
- [ ] Max tokens parameter
- [ ] Temperature parameter
- [ ] Tool definition translation
- [ ] Tool call extraction
- [ ] Error handling (auth, rate limit, API error)
- [ ] Token usage tracking
- [ ] Metadata extraction (if applicable)
- [ ] Embedding support (if available)

## Provider-Specific Considerations

### Authentication

Most providers use bearer token authentication:
```
Authorization: Bearer <API_KEY>
```

But some might use different schemes:
- API key in header: `X-API-Key: <key>`
- API key in URL: `?api_key=<key>`
- Username/password: `Authorization: Basic <base64>`

Adjust `send-completion-request` headers accordingly.

### Response Format

Providers might use different field names:
- Token counts: `tokens`, `usage`, `token_usage`
- Finish reason: `stop_reason`, `finish_reason`, `reason`
- Content field: `text`, `content`, `message.content`

Extract and normalize in `parse-completion-response`.

### Error Formats

Different error response formats:
```json
// Format 1
{"error": {"message": "...", "code": "..."}}

// Format 2
{"errors": [{"message": "..."}]}

// Format 3
{"detail": "error description"}

// Format 4
{"error_description": "..."}
```

Handle in `extract-error-message` if needed.

### Special Features

If the provider has unique features:
- Create optional metadata fields for them
- Document in provider's docstring
- Add examples to `docs/examples/`

## Example: Groq Provider

Groq is OpenAI-compatible, so it's simple:

```lisp
(defclass groq-provider (openai-compatible-provider)
  ()
  (:documentation "Groq API (OpenAI-compatible)"))

(defmethod provider-default-base-url
    ((provider groq-provider))
  "https://api.groq.com/openai/v1")

(defmethod provider-api-key-env-var
    ((provider groq-provider))
  "GROQ_API_KEY")
```

That's it! Since Groq is OpenAI-compatible, it inherits all functionality.

## Example: Custom Local Service

For a custom local service:

```lisp
(defclass custom-local-provider (llm-provider)
  ()
  (:documentation "Custom local LLM service"))

(defmethod provider-default-base-url
    ((provider custom-local-provider))
  "http://localhost:8000")

(defmethod send-completion-request
    ((provider custom-local-provider) messages
     &key model max-tokens temperature system tools tool-choice stop)
  ;; Simplified implementation for local service
  (let ((response (dex:post
                  (format nil "~A/chat" (provider-default-base-url provider))
                  :content (yason:encode-to-string
                           (make-hash-table :test 'equal
                                          :initial-contents
                                          `(("messages" . ,messages)
                                            ("model" . ,model)))))))
    (yason:parse response :object-as :hash-table)))

;; Simple response parsing
(defmethod parse-completion-response
    ((provider custom-local-provider) raw-response &key performance)
  (make-instance 'completion-response
                :id "local-response"
                :model (gethash "model" raw-response)
                :content (gethash "content" raw-response)
                :message (list :role "assistant" :content (gethash "content" raw-response))
                :finish-reason :stop
                :usage (list :prompt-tokens 0 :completion-tokens 0 :total-tokens 0)
                :raw raw-response
                :performance performance
                :metadata nil))
```

## Debugging Implementation Issues

### Request/Response Logging

Add logging to see actual API communication:

```lisp
(defmethod send-completion-request
    ((provider my-provider) messages &key &allow-other-keys)
  (let ((request-body ...))
    ;; Log request
    (format t "~&Request: ~A~%" (yason:encode-to-string request-body))

    (let ((response ...))
      ;; Log response
      (format t "~&Response: ~A~%" (yason:encode-to-string response))
      response)))
```

### Test with Real API

Use a small test API call to verify basic functionality:

```lisp
(let ((provider (make-provider :myservice :api-key "..." :model "...")))
  (complete '((:role "user" :content "Hello")) :provider provider))
```

### Check HTTP Headers

Verify headers match provider requirements:

```lisp
(dex:post url
  :headers `(("Authorization" . ,(format nil "Bearer ~A" key))
            ("Content-Type" . "application/json"))
  ...)
```

## Documentation

Document your provider implementation:

1. Add entry to main README.md
2. Add example usage in docs/examples/
3. Document any special parameters or metadata fields
4. Note any limitations or special behaviors

## See Also

- `src/providers/openai.lisp` - Reference implementation
- `src/providers/anthropic.lisp` - Different request/response format example
- `docs/PROTOCOL.md` - Protocol specification
- `docs/FEATURES.md` - Feature documentation
