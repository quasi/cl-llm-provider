# Building Your First LLM Chat Application

Learn how to build a working chat application that talks to multiple AI providers using `cl-llm-provider`.

## What You'll Build

A command-line chat program that:
- Connects to different AI providers (OpenAI, Anthropic, Google Gemini, local Ollama)
- Maintains conversation history
- Switches between providers on the fly
- Uses function calling to answer questions about the weather

You'll have a working chat bot in under 10 minutes.

## Prerequisites

- Common Lisp installed (SBCL recommended)
- Quicklisp installed
- Internet connection (for cloud providers)

Optional: Ollama installed locally for free, offline testing

## Step 1: Install the Library

```lisp
(ql:quickload :cl-llm-provider)
```

Expected output:
```
To load "cl-llm-provider":
  Load 1 ASDF system:
    cl-llm-provider
; Loading "cl-llm-provider"
...
(:CL-LLM-PROVIDER)
```

The library is now installed.

## Step 2: Get Your First Provider Running

Start with the easiest option—local Ollama (free, no API key needed):

### Install Ollama

Visit https://ollama.ai and download Ollama for your system.

Start the Ollama server:
```bash
ollama serve
```

Pull a model (this downloads a small AI model to your computer):
```bash
ollama pull llama3.2
```

Expected output:
```
pulling manifest
pulling model...
success
```

### Test Ollama Connection

```lisp
;; Create an Ollama provider
(defvar *ollama*
  (cl-llm-provider:make-provider
   :ollama
   :base-url "http://localhost:11434"
   :model "llama3.2"))

;; Send your first message
(defvar *response*
  (cl-llm-provider:complete
   (list (list :role "user"
               :content "Say hello in one word"))
   :provider *ollama*))

;; Get the response text
(cl-llm-provider:response-content *response*)
```

Expected output:
```
"Hello!"
```

**It works!** You just talked to an AI model running on your computer.

## Step 3: Understand the Basics

Every interaction has three parts:

### 1. Create a Provider

The provider knows how to talk to a specific AI service:

```lisp
(cl-llm-provider:make-provider
 :ollama                              ; Which service (ollama, openai, anthropic, etc.)
 :base-url "http://localhost:11434"  ; Where to find it
 :model "llama3.2")                  ; Which AI model to use
```

### 2. Format Your Messages

Messages use a simple format—a list of plists:

```lisp
(list (list :role "user" :content "What is 2+2?"))
```

For a conversation with history:

```lisp
(list
  (list :role "user" :content "My name is Alice")
  (list :role "assistant" :content "Nice to meet you, Alice!")
  (list :role "user" :content "What's my name?"))
```

The AI sees the whole conversation and remembers context.

### 3. Call the AI and Get a Response

```lisp
(cl-llm-provider:complete messages :provider *ollama*)
```

Returns a response object. Extract the text:

```lisp
(cl-llm-provider:response-content response)
```

## Step 4: Add Cloud Providers

Cloud providers need API keys. Create accounts:

- **OpenAI**: https://platform.openai.com/api-keys
- **Anthropic**: https://console.anthropic.com/
- **Google Gemini**: https://aistudio.google.com/apikey

Store keys in environment variables or a `.env` file:

```bash
# .env file
OPENAI_API_KEY=sk-your-key-here
ANTHROPIC_API_KEY=sk-ant-your-key-here
GEMINI_API_KEY=your-gemini-key-here
```

Load environment variables:

```lisp
(defun get-env (key)
  "Get environment variable"
  (uiop:getenv key))
```

Create providers with API keys:

```lisp
;; OpenAI GPT
(defvar *openai*
  (cl-llm-provider:make-provider
   :openai
   :api-key (get-env "OPENAI_API_KEY")
   :model "gpt-4o-mini"))

;; Anthropic Claude
(defvar *claude*
  (cl-llm-provider:make-provider
   :anthropic
   :api-key (get-env "ANTHROPIC_API_KEY")
   :model "claude-3-5-sonnet-20241022"))

;; Google Gemini
(defvar *gemini*
  (cl-llm-provider:make-provider
   :gemini
   :api-key (get-env "GEMINI_API_KEY")
   :model "gemini-2.0-flash-exp"))
```

Test any provider:

```lisp
(cl-llm-provider:response-content
  (cl-llm-provider:complete
   (list (list :role "user" :content "Hello!"))
   :provider *openai*))
```

## Step 5: Build a Chat Loop

Now build a real chat application:

```lisp
(defvar *messages* nil "Conversation history")

(defun chat (user-input provider)
  "Send message and return AI response"
  ;; Add user message to history
  (push (list :role "user" :content user-input)
        *messages*)

  ;; Reverse messages (oldest first)
  (let* ((history (reverse *messages*))
         (response (cl-llm-provider:complete
                    history
                    :provider provider
                    :max-tokens 500)))

    ;; Add AI response to history
    (push (list :role "assistant"
                :content (cl-llm-provider:response-content response))
          *messages*)

    ;; Return response text
    (cl-llm-provider:response-content response)))
```

Use it:

```lisp
(chat "My favorite color is blue" *ollama*)
=> "That's nice! Blue is a popular favorite..."

(chat "What's my favorite color?" *ollama*)
=> "Your favorite color is blue."
```

The AI remembers the conversation!

## Step 6: Add Function Calling

Teach the AI to check the weather by calling your functions.

Define a tool:

```lisp
(defun check-weather (location)
  "Pretend to check weather (replace with real API later)"
  (format nil "Weather in ~A: Sunny, 72°F" location))

(defvar *weather-tool*
  (cl-llm-provider:define-tool
   "check_weather"
   "Get current weather for a location"
   '((:name "location"
      :type :string
      :description "City name"))
   :required '("location")
   :handler (lambda (args)
              ;; args is a plist like (:location "Paris")
              (check-weather (getf args :location)))))
```

Call the AI with tools:

```lisp
(defvar *response-with-tools*
  (cl-llm-provider:complete
   (list (list :role "user"
               :content "What's the weather in Tokyo?"))
   :provider *ollama*
   :tools (list *weather-tool*)))
```

Check if the AI wants to use a tool:

```lisp
(cl-llm-provider:response-tool-calls *response-with-tools*)
```

If tool calls exist, execute them:

```lisp
(let ((tool-calls (cl-llm-provider:response-tool-calls *response-with-tools*)))
  (dolist (call tool-calls)
    (let* ((tool-name (cl-llm-provider:tool-call-name call))
           ;; tool-call-arguments is already a keyword plist, e.g. (:location "Tokyo")
           (args-plist (cl-llm-provider:tool-call-arguments call))
           (tool-id (cl-llm-provider:tool-call-id call)))
      (declare (ignore tool-id))

      ;; Execute the tool
      (format t "Calling ~A with ~S~%" tool-name args-plist)
      (funcall (cl-llm-provider:tool-handler *weather-tool*)
               args-plist))))
```

See the complete example in `example-chat.lisp` for a full tool-calling implementation.

## Step 7: Add Streaming Responses

Stream responses word-by-word as the AI generates them:

```lisp
(cl-llm-provider:complete-stream
 (list (list :role "user"
             :content "Write a haiku about programming"))
 :provider *ollama*
 :on-chunk (lambda (chunk)
             ;; Print each word as it arrives
             (let ((text (cl-llm-provider:chunk-delta chunk)))
               (format t "~A" text)
               (force-output)))
 :on-complete (lambda (full-text final-chunk)
                (format t "~%Done!~%"))
 :on-error (lambda (error)
             (format t "Error: ~A~%" error)))
```

Output appears word by word:
```
Code flows like water
Bugs dance in the moonlight
Compile and rejoice
Done!
```

## Step 8: Track Token Usage

Monitor how much each request costs:

```lisp
(let* ((response (cl-llm-provider:complete
                  (list (list :role "user"
                              :content "Hello"))
                  :provider *ollama*))
       (usage (cl-llm-provider:response-usage response)))

  (format t "Input tokens: ~D~%"
          (getf usage :prompt-tokens))
  (format t "Output tokens: ~D~%"
          (getf usage :completion-tokens))
  (format t "Total tokens: ~D~%"
          (getf usage :total-tokens)))
```

Output:
```
Input tokens: 8
Output tokens: 5
Total tokens: 13
```

Tokens roughly equal words × 1.3. Cloud providers charge per token.

## Complete Working Example

Two files are included:

### `example-chat.lisp`
Complete, runnable chat application with:
- Multi-provider support (Ollama, OpenAI, Claude, Gemini)
- Conversation history
- Tool/function calling
- Streaming support
- Token tracking
- Command system

Load and run:
```lisp
(load "example-chat.lisp")
(example-chat:start-chat)
```

### `example-chat-tests.lisp`
Test suite using FiveAM that verifies:
- Provider creation
- Basic completion
- Conversation memory
- Tool calling
- Streaming
- Error handling

Run tests:
```lisp
(load "example-chat-tests.lisp")
(5am:run! 'example-chat-tests:all-tests)
```

## What You Learned

You can now:

✓ Connect to multiple AI providers
✓ Send messages and get responses
✓ Maintain conversation history
✓ Use function calling (tools)
✓ Stream responses in real-time
✓ Track token usage
✓ Switch between providers

## Common Issues

### "Connection refused" with Ollama

**Cause**: Ollama server isn't running.

**Fix**:
```bash
ollama serve
```

Keep this terminal window open while using Ollama.

### "Invalid API key"

**Cause**: API key is wrong or not loaded.

**Fix**: Verify your key:
```lisp
(uiop:getenv "OPENAI_API_KEY")  ; Should return your key, not NIL
```

Load `.env` file or set environment variables before starting Lisp.

### "Model not found"

**Cause**: Model doesn't exist for that provider.

**Fix**: Check provider documentation for valid model names:
- OpenAI: "gpt-4o-mini", "gpt-4o"
- Anthropic: "claude-3-5-sonnet-20241022"
- Gemini: "gemini-2.0-flash-exp"
- Ollama: Pull model first with `ollama pull <model-name>`

### Empty response

**Cause**: Token limit too low or provider error.

**Fix**: Increase `:max-tokens`:
```lisp
(cl-llm-provider:complete
 messages
 :provider *ollama*
 :max-tokens 1000)  ; Increase from default
```

## Going Further

Now that you have the basics:

### Add More Tools

```lisp
;; Calculator tool
;; WARNING: (eval (read-from-string ...)) executes arbitrary Lisp code.
;; args here comes from the LLM, which in turn may be echoing untrusted
;; user input — never eval it directly. Parse the expression yourself with
;; a real arithmetic parser, or shell out to a sandboxed calculator instead.
(cl-llm-provider:define-tool
 "calculate"
 "Perform math operations"
 '((:name "expression"
    :type :string
    :description "Math expression like '2+2'"))
 :required '("expression")
 :handler (lambda (args)
            (safe-evaluate-arithmetic (getf args :expression))))

;; Web search tool (use Dexador to fetch real data)
(cl-llm-provider:define-tool
 "search_web"
 "Search the web for information"
 '((:name "query"
    :type :string
    :description "Search query"))
 :required '("query")
 :handler (lambda (args)
            ;; Integrate with search API
            (fetch-search-results (getf args :query))))
```

### Build a Web Interface

Use Hunchentoot to create a web UI:

```lisp
(hunchentoot:define-easy-handler (chat-endpoint :uri "/chat") (message)
  (setf (hunchentoot:content-type*) "application/json")
  (let ((response (chat message *ollama*)))
    (json:encode-json-to-string
     `((:response . ,response)))))
```

### Save Conversations to Disk

```lisp
(defun save-conversation (filename messages)
  "Save messages to file"
  (with-open-file (stream filename
                          :direction :output
                          :if-exists :supersede)
    (prin1 messages stream)))

(defun load-conversation (filename)
  "Load messages from file"
  (with-open-file (stream filename)
    (read stream)))
```

### Try Different Models

Each provider offers models with different capabilities:

**Fast and cheap**: Good for simple tasks
- OpenAI: "gpt-4o-mini"
- Anthropic: "claude-3-5-haiku-20241022"
- Gemini: "gemini-2.0-flash-exp"

**Powerful**: Best quality, slower, more expensive
- OpenAI: "gpt-4o"
- Anthropic: "claude-3-5-sonnet-20241022"
- Gemini: "gemini-2.0-pro-exp"

**Local**: Free, private, offline
- Ollama: "llama3.2", "mistral", "qwen3:1.7b"

## Resources

- **Library Documentation**: [docs/INDEX.md](../INDEX.md)
- **Provider Docs**:
  - OpenAI: https://platform.openai.com/docs
  - Anthropic: https://docs.anthropic.com
  - Gemini: https://ai.google.dev/docs
  - Ollama: https://ollama.ai/library

## Next Steps

1. Modify `example-chat.lisp` to add your own tools
2. Build a specialized bot (code reviewer, translator, tutor)
3. Connect to real APIs (weather, news, databases)
4. Deploy as a web service or Slack bot

You have everything you need to build production LLM applications in Common Lisp.
