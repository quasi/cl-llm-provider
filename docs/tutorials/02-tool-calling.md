# Tutorial: Tool Calling

Learn to define tools, let LLMs call them, and build tool-using agents.

**What you'll learn**:
- Define tools that LLMs can call
- Handle tool calls from responses
- Build a tool-using agent
- Handle tool errors safely

**Prerequisites**: [Tutorial: Basic Completions](01-basics.md) complete.

---

## What Are Tools?

Tools let LLMs call functions you define. Instead of just generating text, the LLM can ask your code to:

- Look something up (search, database queries)
- Take an action (send email, create file)
- Compute something (math, formatting)

The LLM decides when to use tools. You decide what tools do.

## Defining Your First Tool

Use `define-tool` to create a callable function:

```lisp
(use-package :cl-llm-provider)

;; Define a simple tool
(define-tool "get_weather"
  "Get the current weather for a city"
  '((:name "city" :type :string))
  :required '("city")
  :handler (lambda (args)
             (let ((city (getf args :city)))
               (format nil "Weather in ~A: Sunny, 72°F" city))))
```

Parts:
- **Name**: How the LLM calls it (string)
- **Description**: Tells the LLM what it does (string)
- **Parameters**: What inputs it takes (list of plists)
- **Handler**: Lisp function that executes the tool

## Tool Parameters

Parameters describe what inputs the tool accepts:

```lisp
(define-tool "search_web"
  "Search the internet"
  '((:name "query" :type :string)
    (:name "limit" :type :integer))
  :required '("query")        ; Only "query" is required
  :handler (lambda (args)
             (let ((query (getf args :query))
                   (limit (getf args :limit 10)))  ; Default to 10
               (format nil "Found ~A results for ~A" limit query))))
```

**Parameter Types**:
- `:string` - Text
- `:integer` - Whole numbers
- `:number` - Decimals
- `:boolean` - True/false

## Calling Tools from Completions

Tell the LLM about your tools and it will decide to use them:

```lisp
;; Define tools
(define-tool "get_weather"
  "Get the current weather for a city"
  '((:name "city" :type :string))
  :required '("city")
  :handler (lambda (args)
             (format nil "Weather in ~A: Sunny, 72°F" (getf args :city))))

;; Ask the LLM to use a tool
(let ((response (complete '((:role "user" :content "What's the weather in Paris?"))
                         :tools (list (get-tool "get_weather")))))

  ;; Check if LLM requested tool calls
  (if (response-tool-calls response)
    (format t "Tool calls: ~A~%" (response-tool-calls response))
    (format t "Response: ~A~%" (response-content response))))
```

## Handling Tool Calls

When an LLM requests tools, you execute them and send results back:

```lisp
(defun handle-tool-call (tool-call)
  "Execute a tool call and return the result."
  (let* ((tool-name (getf tool-call :name))
         (tool-args (getf tool-call :arguments))
         (tool (get-tool tool-name)))
    ;; Execute the tool
    (funcall (tool-handler tool) tool-args)))

(defun chat-with-tools (messages &optional tools)
  "Chat with tool support. Keep calling tools until LLM stops."
  (let ((current-messages messages))
    (loop
      ;; Get response (with tools available)
      (let ((response (complete current-messages :tools tools)))

        ;; If no tool calls, we're done
        (unless (response-tool-calls response)
          (return (response-content response)))

        ;; Add assistant message to history
        (push (response-message response) current-messages)

        ;; Handle each tool call
        (dolist (tool-call (response-tool-calls response))
          (let* ((result (handle-tool-call tool-call)))
            ;; Add tool result to history
            (push (list :role "user"
                       :content (format nil "Tool result: ~A" result))
                 current-messages)))))))

;; Use it
(let ((tools (list (get-tool "get_weather"))))
  (chat-with-tools '((:role "user" :content "What's the weather in Paris?"))
                  tools))
```

## Complete Tool-Using Agent

Here's a practical agent that searches the web and summarizes:

```lisp
(use-package :cl-llm-provider)

;; Define tools
(define-tool "search_web"
  "Search the internet for information"
  '((:name "query" :type :string)
    (:name "num_results" :type :integer))
  :required '("query")
  :handler (lambda (args)
             ;; In reality, call a real search API
             (format nil "Results for '~A': Wikipedia, News, Blog posts"
                     (getf args :query))))

(define-tool "summarize_text"
  "Summarize a long text"
  '((:name "text" :type :string))
  :required '("text")
  :handler (lambda (args)
             ;; In reality, use an NLP library or LLM
             (let ((text (getf args :text)))
               (format nil "Summary: ~A [shortened]" (subseq text 0 30)))))

;; Agent loop
(defun research-agent (topic)
  "Research a topic and provide a summary."
  (let* ((tools (list (get-tool "search_web")
                     (get-tool "summarize_text")))
         (messages (list (list :role "user"
                              :content (format nil "Research this topic and provide a summary: ~A" topic)))))

    (format t "Researching: ~A~%~%" topic)

    (loop
      ;; Get response
      (let ((response (complete messages :tools tools)))
        (format t "Agent: ~A~%~%" (response-content response))

        ;; If no more tool calls, we're done
        (unless (response-tool-calls response)
          (return (response-content response)))

        ;; Add assistant message
        (push (response-message response) messages)

        ;; Execute tools
        (dolist (tool-call (response-tool-calls response))
          (let* ((tool-name (getf tool-call :name))
                 (tool-args (getf tool-call :arguments))
                 (tool (get-tool tool-name))
                 (result (funcall (tool-handler tool) tool-args)))
            (format t "Tool ~A returned: ~A~%~%" tool-name result)

            ;; Add tool result
            (push (list :role "user" :content (format nil "Tool result: ~A" result))
                 messages)))))))

;; Run it
(research-agent "The history of Lisp")
```

## Tool Safety and Categories (Optional)

Mark tools with safety levels and categories for advanced use:

```lisp
;; Read-only tool
(define-tool "get_weather"
  "Get weather"
  '((:name "city" :type :string))
  :required '("city")
  :safety-level :safe
  :categories '(:search :external-api)
  :handler (lambda (args) ...))

;; Dangerous tool - requires approval
(define-tool "delete_file"
  "Delete a file"
  '((:name "path" :type :string))
  :required '("path")
  :safety-level :dangerous
  :categories '(:filesystem :destructive)
  :requires-approval :always
  :handler (lambda (args) ...))
```

See [How-To: Advanced Tools](../how-to/tools.md) for full details.

## Debugging Tool Calls

If tool calls aren't working:

```lisp
;; Check if a tool is registered
(get-tool "get_weather")  ; Returns the tool or NIL

;; Check what tools you have
(list-tools)

;; See tool details
(let ((tool (get-tool "get_weather")))
  (format t "Name: ~A~%" (tool-name tool))
  (format t "Description: ~A~%" (tool-description tool))
  (format t "Parameters: ~A~%" (tool-parameters tool)))

;; Check if response has tool calls
(let ((response (complete messages :tools tools)))
  (format t "Tool calls: ~A~%" (response-tool-calls response)))
```

## Common Patterns

### Chaining Tools

```lisp
;; First tool returns data, second tool processes it
(loop
  (let ((response (complete messages :tools tools)))
    ;; If assistant wants to use tools
    (if (response-tool-calls response)
      (progn
        ;; Execute tools and continue
        ...)
      ;; Otherwise, return final answer
      (return (response-content response)))))
```

### Error Handling in Tools

```lisp
(define-tool "fetch_url"
  "Fetch a web page"
  '((:name "url" :type :string))
  :required '("url")
  :handler (lambda (args)
             (handler-case
               (fetch-page (getf args :url))
               (network-error (e)
                 (format nil "Network error: ~A" e))
               (error (e)
                 (format nil "Error: ~A" e)))))
```

## Checkpoint: What You Can Now Do

- ✅ Define tools with parameters
- ✅ Let LLMs call your tools
- ✅ Build tool-using agents
- ✅ Handle tool errors
- ✅ Chain multiple tools together

## Next Steps

- **Advanced tool features**: [How-To: Advanced Tools](../how-to/tools.md)
- **Error handling patterns**: [How-To: Error Handling](../how-to/error-handling.md)
- **Advanced features**: [Tutorial: Advanced Features](03-advanced.md)

---

**Prev**: [Basic Completions](01-basics.md) | **Next**: [Advanced Features](03-advanced.md)
