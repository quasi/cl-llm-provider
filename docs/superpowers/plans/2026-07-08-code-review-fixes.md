# Code Review Fixes: Robustness Release Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every verified error- and warning-severity finding from the 2026-07-08 code review so the multi-turn tool loop works end-to-end on all providers and the library is fit for open-source release.

**Architecture:** The core defect is asymmetry: responses are parsed into recursive keyword plists but serialized shallowly, so the tool loop cannot round-trip. We make `plist-to-hash` a true inverse of `%json-hash-to-keyword-plist`, add a `translate-message-to-provider` generic for per-provider message wire formats, consolidate six duplicated HTTP blocks into one `provider-http-post` with a working retry-restart contract, and harden parsers, restarts, and interactive readers.

**Tech Stack:** SBCL, FiveAM + cl-test-hardening harness, dexador, yason. All new tests are offline (synthetic JSON/SSE) — no network.

## Global Constraints

- TDD: every behavioral change gets a failing test first (`~/.claude/workflows/common-lisp.md` hard rule).
- Run a file's tests with: `sbcl --noinform --non-interactive --load tests/<file>.lisp` (exit 0 + FiveAM "Did N checks. Pass: N").
- Validate syntax with `mcp__lisp__validate-syntax` before saving any `.lisp` file.
- `git add <specific files>` only — never `-A` or `.`.
- cobra-lisp-reviewer review before each commit (CL workflow hard rule); at minimum every 3 tasks per `/execute` convention.
- Dev-skill invariants hold: INV-003 (tool-call/tool-result pairing), INV-005 (no API keys in logs), INV-006 (errors are conditions), R005 (tool-call message → matching tool-result next turn).
- New exported symbols go into `src/package.lisp` export list AND the test harness needs no change (it loads source files directly).
- Verified-refuted finding — do NOT "fix": the streaming socket "leak" (`stream-closed-p` at `src/types.lisp:181` returns T for `:error` state, so cleanup in streaming.lisp does close the HTTP stream).

## Decision Required From Baba (before Task 17)

The `.asd` hard-depends on `:telos` (not in Quicklisp) — nobody outside this machine can load the library. Two options:

- **Option A (plan default): vendor a telos shim.** A ~100-line `src/telos-shim.lisp` defines a functional `:telos` package (`defun/i`, `define-condition/i`, `defintent`, `deffeature` recording into simple registries; `get-intent`/`list-features` work — the existing Section-6 telos tests require this) only when real telos is absent. Real telos, when loaded first, wins. Zero behavior change, unblocks release.
- **Option B: publish telos** (Ultralisp/Quicklisp) and keep the hard dependency. Cleaner long-term, but couples this library's release to telos's release-readiness.

Task 17 implements Option A; skip it if Baba picks B.

---

### Task 1: Make plist-to-hash recursively JSON-serializable

The single highest-impact fix. `plist-to-hash` (src/protocol.lisp:347) converts only top-level keys; nested keyword plists (e.g. `:tool-calls` in a response message) get yason-encoded as JSON arrays instead of objects, breaking every tool-loop continuation request.

**Files:**
- Modify: `src/protocol.lisp:347-362`
- Test: `tests/test-request-response-handling.lisp`

**Interfaces:**
- Produces: `plist-to-hash (plist &key test)` — unchanged signature, now deep. New internal helpers `%json-plist-p (value)` and `%lisp-to-json-value (value)` in `src/protocol.lisp`.
- Contract: `(%json-hash-to-keyword-plist (yason:parse (yason-encode-string (plist-to-hash p))))` is structurally equivalent to `p` for any keyword plist whose values are strings, numbers, booleans, nil, nested keyword plists, or lists of these.

- [ ] **Step 1: Write the failing test**

Add to `tests/test-request-response-handling.lisp` (inside its existing `in-suite`; use `cl-llm-provider::` for internals):

```lisp
(fiveam:test plist-to-hash-recursive-round-trip
  "Nested tool-call plists must encode as JSON objects, not arrays (round trip)."
  (let* ((msg '(:role "assistant"
                :content nil
                :tool-calls ((:id "call_1"
                              :type "function"
                              :function (:name "get_weather"
                                         :arguments "{\"location\":\"Paris\"}")))))
         (json (with-output-to-string (s)
                 (yason:encode (cl-llm-provider::plist-to-hash msg) s)))
         (back (cl-llm-provider::%json-hash-to-keyword-plist (yason:parse json))))
    (fiveam:is (string= "assistant" (getf back :role)))
    (let* ((tc (first (getf back :tool-calls)))
           (fn (getf tc :function)))
      (fiveam:is (string= "call_1" (getf tc :id)))
      (fiveam:is (string= "get_weather" (getf fn :name)))
      (fiveam:is (string= "{\"location\":\"Paris\"}" (getf fn :arguments))))))

(fiveam:test plist-to-hash-nested-content-blocks
  "A list of content-block plists becomes a JSON array of objects."
  (let* ((msg '(:role "assistant"
                :content ((:type "text" :text "Checking...")
                          (:type "tool-use" :id "toolu_1" :name "f" :input (:x 1)))))
         (hash (cl-llm-provider::plist-to-hash msg))
         (content (gethash "content" hash)))
    (fiveam:is (vectorp content))
    (fiveam:is (hash-table-p (elt content 0)))
    (fiveam:is (string= "text" (gethash "type" (elt content 0))))
    (fiveam:is (hash-table-p (gethash "input" (elt content 1))))))
```

- [ ] **Step 2: Run to verify failure**

Run: `sbcl --noinform --non-interactive --load tests/test-request-response-handling.lisp`
Expected: the two new tests FAIL (`getf` on a list-encoded tool-call returns NIL / content elt is a cons, not hash).

- [ ] **Step 3: Implement**

In `src/protocol.lisp`, immediately above `plist-to-hash`:

```lisp
(defun %json-plist-p (value)
  "True if VALUE is a keyword plist: a cons whose first element is a keyword."
  (and (consp value) (keywordp (first value))))

(defun %lisp-to-json-value (value)
  "Recursively convert a Lisp VALUE into yason-encodable data.
Keyword plists become hash-tables, other lists become vectors (JSON arrays),
atoms (strings, numbers, T, NIL) pass through.
Inverse of %json-hash-to-keyword-plist (types.lisp)."
  (cond
    ((%json-plist-p value) (plist-to-hash value))
    ((consp value) (map 'vector #'%lisp-to-json-value value))
    (t value)))
```

In `plist-to-hash`, change the loop body's setf to convert values, and fix the dangling docstring fragment:

```lisp
  "Convert a plist to a hash table with string keys, recursively.
Keywords like :role become \"role\", :tool-call-id becomes \"tool_call_id\";
string keys are preserved as-is. Values that are keyword plists become nested
hash-tables; other lists become vectors. Inverse of %json-hash-to-keyword-plist."
  ...
          do (setf (gethash string-key hash) (%lisp-to-json-value value))
```

- [ ] **Step 4: Run tests to verify pass**

Run: `sbcl --noinform --non-interactive --load tests/test-request-response-handling.lisp`
Also run: `sbcl --noinform --non-interactive --load tests/test-properties.lisp` (existing plist-to-hash property tests must still pass — values in those tests are atoms, unaffected).

- [ ] **Step 5: Commit**

```bash
git add src/protocol.lisp tests/test-request-response-handling.lisp
git commit -m "fix: make plist-to-hash recursive, true inverse of %json-hash-to-keyword-plist"
```

---

### Task 2: Normalize Anthropic response message + parser nil guards

`src/providers/anthropic.lisp:195-198` stores raw `tool-call` CLOS objects in the `:message` plist (yason cannot encode them) and drops text content when tool calls are present. Also: `(gethash "type" first-block)` crashes on empty content (line 176) and `(intern (string-upcase finish-reason))` crashes on missing `stop_reason` (line 206).

**Files:**
- Modify: `src/providers/anthropic.lisp:171-222`
- Test: `tests/test-request-response-handling.lisp`

**Interfaces:**
- Produces: Anthropic `response-message` is now `(:role "assistant" :content <list of content-block keyword plists>)` — the raw content blocks preserved, so echoing back to the API reconstructs `tool_use` blocks exactly. Text content is the concatenation of all `text` blocks.

- [ ] **Step 1: Write the failing tests**

```lisp
(fiveam:test anthropic-parse-tool-use-message-is-plist
  "Anthropic :message slot must be a pure keyword plist mirroring content blocks."
  (let* ((provider (make-instance 'cl-llm-provider::anthropic-provider))
         (raw (yason:parse "{\"id\":\"msg_1\",\"model\":\"claude-x\",
\"stop_reason\":\"tool_use\",
\"content\":[{\"type\":\"text\",\"text\":\"Let me check.\"},
             {\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"get_weather\",
              \"input\":{\"location\":\"Pune\"}}],
\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}"))
         (resp (cl-llm-provider:parse-completion-response provider raw))
         (msg (cl-llm-provider:response-message resp)))
    ;; message is encodable: no CLOS objects inside
    (fiveam:finishes
      (with-output-to-string (s)
        (yason:encode (cl-llm-provider::plist-to-hash msg) s)))
    (fiveam:is (string= "assistant" (getf msg :role)))
    (let ((blocks (getf msg :content)))
      (fiveam:is (= 2 (length blocks)))
      ;; %json-hash-to-keyword-plist maps _ to - in KEYS only; the "type"
      ;; VALUE string "tool_use" passes through unchanged.
      (fiveam:is (string= "tool_use" (getf (second blocks) :type)))
      (fiveam:is (string= "toolu_1" (getf (second blocks) :id))))
    ;; text is kept even when tool calls are present
    (fiveam:is (string= "Let me check." (cl-llm-provider:response-content resp)))
    (fiveam:is (= 1 (length (cl-llm-provider:response-tool-calls resp))))))

(fiveam:test anthropic-parse-empty-content-no-crash
  (let* ((provider (make-instance 'cl-llm-provider::anthropic-provider))
         (raw (yason:parse "{\"id\":\"msg_2\",\"model\":\"claude-x\",\"content\":[]}")))
    (fiveam:finishes (cl-llm-provider:parse-completion-response provider raw))
    (let ((resp (cl-llm-provider:parse-completion-response provider raw)))
      (fiveam:is (null (cl-llm-provider:response-finish-reason resp))))))
```

- [ ] **Step 2: Run to verify failure**

Run: `sbcl --noinform --non-interactive --load tests/test-request-response-handling.lisp`
Expected: first test FAILS (yason:encode errors on tool-call object / content missing); second SIGNALS (gethash on NIL).

- [ ] **Step 3: Implement**

Rewrite `parse-completion-response` for anthropic (src/providers/anthropic.lisp:171-222):

```lisp
(defmethod parse-completion-response ((provider anthropic-provider) raw-response
                                      &key performance)
  (let* ((content-blocks (gethash "content" raw-response))
         (text-content
           (let ((texts (loop for block in (coerce (or content-blocks #()) 'list)
                              when (string= (gethash "type" block) "text")
                              collect (gethash "text" block))))
             (when texts
               (format nil "~{~A~}" texts))))
         (finish-reason (gethash "stop_reason" raw-response))
         (usage (gethash "usage" raw-response))
         (tool-calls
           (loop for block in (coerce (or content-blocks #()) 'list)
                 when (string= (gethash "type" block) "tool_use")
                 collect (make-instance 'tool-call
                                        :id (gethash "id" block)
                                        :name (gethash "name" block)
                                        :arguments (gethash "input" block)))))
    (make-instance 'completion-response
                   :id (gethash "id" raw-response)
                   :model (gethash "model" raw-response)
                   :content text-content
                   ;; Message mirrors the raw content blocks so it can be echoed
                   ;; back to the API for conversation continuation (tool loops).
                   :message (list :role "assistant"
                                  :content (%json-hash-to-keyword-plist content-blocks))
                   :tool-calls tool-calls
                   :finish-reason (when finish-reason
                                    (intern (string-upcase finish-reason) :keyword))
                   :usage (when usage
                            (let ((in (or (gethash "input_tokens" usage) 0))
                                  (out (or (gethash "output_tokens" usage) 0)))
                              (list :prompt-tokens in
                                    :completion-tokens out
                                    :total-tokens (+ in out))))
                   :raw raw-response
                   :performance performance
                   :metadata (let ((metadata nil))
                               (setf (getf metadata :provider-type) (provider-type provider))
                               (setf (getf metadata :provider-name) (provider-name provider))
                               (when-let ((stop-seq (gethash "stop_sequence" raw-response)))
                                 (setf (getf metadata :stop-sequence) stop-seq))
                               metadata))))
```

(The old `first-block`/`content-type` locals disappear; text is collected from ALL text blocks.)

- [ ] **Step 4: Run tests, verify pass** (same command)

- [ ] **Step 5: Commit**

```bash
git add src/providers/anthropic.lisp tests/test-request-response-handling.lisp
git commit -m "fix: Anthropic response message is a pure plist; keep text alongside tool calls; nil guards"
```

---

### Task 3: Nil guards in OpenAI-format parsers (openai, gemini, openrouter, ollama)

All four crash on absent `finish_reason` (`string-upcase` of NIL) and on empty `choices` / missing `message` (`gethash` on NIL): `openai.lisp:105,119`, `gemini.lisp:110,124`, `openrouter.lisp:107,121`, `ollama.lisp:114,145`.

**Files:**
- Modify: `src/providers/openai.lisp`, `src/providers/gemini.lisp`, `src/providers/openrouter.lisp`, `src/providers/ollama.lisp`
- Test: `tests/test-request-response-handling.lisp`

- [ ] **Step 1: Write the failing test**

```lisp
(fiveam:test openai-format-parsers-tolerate-sparse-responses
  "Empty choices / missing finish_reason must not crash any OpenAI-format parser."
  (dolist (class '(cl-llm-provider::openai-provider
                   cl-llm-provider::gemini-provider
                   cl-llm-provider::openrouter-provider))
    (let ((provider (make-instance class)))
      (fiveam:finishes
        (cl-llm-provider:parse-completion-response
         provider (yason:parse "{\"id\":\"x\",\"model\":\"m\",\"choices\":[]}")))
      (let ((resp (cl-llm-provider:parse-completion-response
                   provider
                   (yason:parse "{\"id\":\"x\",\"model\":\"m\",
\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"hi\"}}]}"))))
        (fiveam:is (null (cl-llm-provider:response-finish-reason resp)))
        (fiveam:is (string= "hi" (cl-llm-provider:response-content resp)))))))

(fiveam:test ollama-parser-tolerates-missing-message
  (let ((provider (make-instance 'cl-llm-provider::ollama-provider)))
    (fiveam:finishes
      (cl-llm-provider:parse-completion-response
       provider (yason:parse "{\"model\":\"m\",\"done\":true}")))))
```

- [ ] **Step 2: Run to verify failure** — expected: type errors (gethash on NIL / string-upcase NIL).

- [ ] **Step 3: Implement** — the same three edits in openai.lisp, gemini.lisp, openrouter.lisp `parse-completion-response`:

```lisp
         ;; guard: first-choice may be NIL (empty choices)
         (message (when first-choice (gethash "message" first-choice)))
         (content (when message (gethash "content" message)))
         (finish-reason (when first-choice (gethash "finish_reason" first-choice)))
         ...
         (tool-calls-raw (when message (gethash "tool_calls" message)))
```
and
```lisp
                   :finish-reason (when finish-reason
                                    (intern (string-upcase finish-reason) :keyword))
```

In ollama.lisp `parse-completion-response`:
```lisp
  (let* ((message (gethash "message" raw-response))
         (content (when message (gethash "content" message)))
         (thinking (when message (gethash "thinking" message)))
         (role (or (when message (gethash "role" message)) "assistant"))
```
(`finish-reason` there already defaults via `(or ... "stop")` — leave it.)

- [ ] **Step 4: Run tests, verify pass**

- [ ] **Step 5: Commit**

```bash
git add src/providers/openai.lisp src/providers/gemini.lisp src/providers/openrouter.lisp src/providers/ollama.lisp tests/test-request-response-handling.lisp
git commit -m "fix: response parsers tolerate empty choices and missing finish_reason"
```

---

### Task 4: translate-message-to-provider generic — tool results reach Anthropic

`make-tool-result` (src/tools.lisp:121) emits an OpenAI-shaped message with a spurious `"is_error":null`; Anthropic requires tool results as `tool_result` content blocks in a user message, and requires strictly alternating roles (multiple tool results must coalesce into ONE user message).

**Files:**
- Modify: `src/protocol.lisp` (new generic + default method), `src/tools.lisp:102-124`, `src/providers/anthropic.lisp` (new `%anthropic-wire-messages`, use in both send methods), `src/providers/openai.lisp:41-47,238-242`, `src/providers/gemini.lisp:45-51,238-242`, `src/providers/openrouter.lisp:44-48`, `src/providers/ollama.lisp:45-49`, `src/package.lisp` (export `translate-message-to-provider`)
- Test: `tests/test-tools-integration.lisp`

**Interfaces:**
- Produces: `(translate-message-to-provider provider message-plist)` → hash-table in the provider's wire format. Default method = OpenAI format with `:is-error` stripped. `make-tool-result` omits `:is-error` unless true.
- Consumes: recursive `plist-to-hash` (Task 1), Anthropic content-block messages (Task 2).

- [ ] **Step 1: Write the failing tests**

Add to `tests/test-tools-integration.lisp`:

```lisp
(fiveam:test make-tool-result-omits-nil-is-error
  (let ((msg (make-tool-result "call_1" "42")))
    (fiveam:is (null (member :is-error msg))))
  (let ((msg (make-tool-result "call_1" "boom" :is-error t)))
    (fiveam:is (eq t (getf msg :is-error)))))

(fiveam:test default-translation-strips-is-error
  (let* ((provider (make-instance 'cl-llm-provider::openai-provider))
         (hash (cl-llm-provider:translate-message-to-provider
                provider (make-tool-result "call_1" "boom" :is-error t))))
    (fiveam:is (string= "tool" (gethash "role" hash)))
    (fiveam:is (string= "call_1" (gethash "tool_call_id" hash)))
    (fiveam:is (null (nth-value 1 (gethash "is_error" hash))))))

(fiveam:test anthropic-tool-result-becomes-user-content-block
  (let* ((provider (make-instance 'cl-llm-provider::anthropic-provider))
         (hash (cl-llm-provider:translate-message-to-provider
                provider (make-tool-result "toolu_1" "22 celsius"))))
    (fiveam:is (string= "user" (gethash "role" hash)))
    (let ((block (elt (gethash "content" hash) 0)))
      (fiveam:is (string= "tool_result" (gethash "type" block)))
      (fiveam:is (string= "toolu_1" (gethash "tool_use_id" block)))
      (fiveam:is (string= "22 celsius" (gethash "content" block))))))

(fiveam:test anthropic-coalesces-consecutive-tool-results
  "Two tool results must merge into ONE user message (alternating-roles rule)."
  (let* ((provider (make-instance 'cl-llm-provider::anthropic-provider))
         (messages (list '(:role "user" :content "weather in Pune and Paris?")
                         '(:role "assistant"
                           :content ((:type "tool_use" :id "t1" :name "w" :input (:city "Pune"))
                                     (:type "tool_use" :id "t2" :name "w" :input (:city "Paris"))))
                         (make-tool-result "t1" "30C")
                         (make-tool-result "t2" "18C")))
         (wire (cl-llm-provider::%anthropic-wire-messages provider messages)))
    (fiveam:is (= 3 (length wire)))
    (let ((last-msg (elt wire 2)))
      (fiveam:is (string= "user" (gethash "role" last-msg)))
      (fiveam:is (= 2 (length (gethash "content" last-msg)))))))

(fiveam:test anthropic-merges-tool-result-with-following-user-text
  "Tool result followed by plain user text must merge into ONE user turn
(alternating-roles rule holds for ALL consecutive user-role messages)."
  (let* ((provider (make-instance 'cl-llm-provider::anthropic-provider))
         (messages (list '(:role "user" :content "weather?")
                         '(:role "assistant"
                           :content ((:type "tool_use" :id "t1" :name "w" :input (:city "Pune"))))
                         (make-tool-result "t1" "30C")
                         '(:role "user" :content "thanks — and tomorrow?")))
         (wire (cl-llm-provider::%anthropic-wire-messages provider messages)))
    (fiveam:is (= 3 (length wire)))
    (let* ((last-msg (elt wire 2))
           (blocks (coerce (gethash "content" last-msg) 'list)))
      (fiveam:is (string= "user" (gethash "role" last-msg)))
      (fiveam:is (= 2 (length blocks)))
      (fiveam:is (string= "tool_result" (gethash "type" (first blocks))))
      (fiveam:is (string= "text" (gethash "type" (second blocks)))))))
```

- [ ] **Step 2: Run to verify failure** — `translate-message-to-provider` / `%anthropic-wire-messages` undefined.

- [ ] **Step 3: Implement**

`src/tools.lisp` — `make-tool-result` body:

```lisp
  (let ((msg (list :role "tool"
                   :tool-call-id tool-call-id
                   :content result)))
    (if is-error
        (append msg (list :is-error t))
        msg))
```

`src/protocol.lisp` — after `translate-tool-to-provider`:

```lisp
(defgeneric translate-message-to-provider (provider message)
  (:documentation "Translate a canonical message plist into PROVIDER's wire format.

MESSAGE - keyword plist as produced by response-message, make-tool-result,
or user code (:role \"user\"/\"assistant\"/\"system\"/\"tool\", :content ...).

Returns a hash-table ready for yason encoding.
The default method implements the OpenAI chat format."))

(defmethod translate-message-to-provider ((provider llm-provider) message)
  "OpenAI format. Strips the library-internal :is-error key from tool messages."
  (let ((msg (copy-list message)))
    (remf msg :is-error)
    (plist-to-hash msg)))
```

`src/providers/anthropic.lisp` — method + coalescing helper:

```lisp
(defun %tool-result-block (message)
  "Build an Anthropic tool_result content-block plist from a role=\"tool\" MESSAGE."
  (let ((block (list :type "tool_result"
                     :tool-use-id (getf message :tool-call-id)
                     :content (getf message :content))))
    (if (getf message :is-error)
        (append block (list :is-error t))
        block)))

(defmethod translate-message-to-provider ((provider anthropic-provider) message)
  "Anthropic format: tool results are tool_result content blocks in a user message."
  (if (equal (getf message :role) "tool")
      (plist-to-hash (list :role "user"
                           :content (list (%tool-result-block message))))
      (call-next-method)))

(defun %user-content-blocks (msg-hash)
  "Return MSG-HASH's content as a list of content-block hash-tables,
promoting plain string content to a text block."
  (let ((content (gethash "content" msg-hash)))
    (etypecase content
      (string (list (plist-to-hash (list :type "text" :text content))))
      (list content)
      (vector (coerce content 'list)))))

(defun %merge-consecutive-user-turns (wire-list)
  "Merge adjacent role=\"user\" wire messages into one message with combined
content blocks — the Messages API requires strictly alternating turns."
  (let ((merged '()))
    (dolist (msg wire-list (nreverse merged))
      (let ((prev (first merged)))
        (if (and prev
                 (equal (gethash "role" prev) "user")
                 (equal (gethash "role" msg) "user"))
            (setf (gethash "content" prev)
                  (append (%user-content-blocks prev)
                          (%user-content-blocks msg)))
            (push msg merged))))))

(defun %anthropic-wire-messages (provider messages)
  "Translate MESSAGES to Anthropic wire format (vector of hash-tables).
Consecutive role=\"tool\" messages coalesce into a single user message, and
ANY adjacent user turns (e.g. tool results followed by user text) merge —
the Messages API requires strictly alternating user/assistant turns."
  (let ((wire '())
        (pending-results '()))
    (flet ((flush-results ()
             (when pending-results
               (push (plist-to-hash (list :role "user"
                                          :content (nreverse pending-results)))
                     wire)
               (setf pending-results nil))))
      (dolist (msg messages)
        (if (equal (getf msg :role) "tool")
            (push (%tool-result-block msg) pending-results)
            (progn
              (flush-results)
              (push (translate-message-to-provider provider msg) wire))))
      (flush-results))
    (coerce (%merge-consecutive-user-turns (nreverse wire)) 'vector)))
```

Wire it in — anthropic.lisp `send-completion-request` (line 118-119) and `send-streaming-request` (line 253-254):

```lisp
        (setf (gethash "messages" body)
              (%anthropic-wire-messages provider messages))
```

The other four providers replace every `(mapcar #'plist-to-hash messages)` / `(map 'vector #'plist-to-hash all-messages)` in send-completion-request and send-streaming-request:

```lisp
        ;; openai.lisp:41-47 (same pattern in gemini.lisp, openrouter.lisp, ollama.lisp)
        (setf (gethash "messages" body)
              (let ((all (if system
                             (cons (list :role "system" :content system) messages)
                             messages)))
                (map 'vector (lambda (m) (translate-message-to-provider provider m))
                     all)))
```

(Note this also fixes the OpenAI/Gemini/OpenRouter non-streaming paths that previously produced a LIST for `"messages"` while wrapping system messages inconsistently — now uniformly a vector.)

Add `#:translate-message-to-provider` to the exports in `src/package.lisp` (near `#:translate-tool-to-provider` if present, else in the protocol section).

- [ ] **Step 4: Run tests** — `tests/test-tools-integration.lisp` AND `tests/test-request-response-handling.lisp` AND `tests/test-provider-protocols.lisp`.

- [ ] **Step 5: Full round-trip integration test** (the headline feature, per provider format):

```lisp
(fiveam:test tool-loop-round-trip-openai-format
  "response-message + make-tool-result must survive re-serialization to valid JSON."
  (let* ((provider (make-instance 'cl-llm-provider::openai-provider))
         (raw (yason:parse "{\"id\":\"c1\",\"model\":\"gpt-x\",
\"choices\":[{\"finish_reason\":\"tool_calls\",
 \"message\":{\"role\":\"assistant\",\"content\":null,
  \"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",
   \"function\":{\"name\":\"add\",\"arguments\":\"{\\\"a\\\":2,\\\"b\\\":3}\"}}]}}]}"))
         (resp (cl-llm-provider:parse-completion-response provider raw))
         (continuation (list '(:role "user" :content "add 2 and 3")
                             (cl-llm-provider:response-message resp)
                             (make-tool-result "call_1" "5")))
         (wire (map 'list (lambda (m)
                            (cl-llm-provider:translate-message-to-provider provider m))
                    continuation))
         (json (with-output-to-string (s) (yason:encode (coerce wire 'vector) s)))
         (parsed (yason:parse json)))
    ;; assistant message's tool_calls must be JSON objects with function.name
    (let* ((assistant (elt parsed 1))
           (tc (elt (gethash "tool_calls" assistant) 0)))
      (fiveam:is (hash-table-p tc))
      (fiveam:is (string= "add" (gethash "name" (gethash "function" tc))))
      (fiveam:is (string= "call_1" (gethash "id" tc))))
    (let ((tool-msg (elt parsed 2)))
      (fiveam:is (string= "tool" (gethash "role" tool-msg)))
      (fiveam:is (string= "call_1" (gethash "tool_call_id" tool-msg))))))
```

Run, verify pass.

- [ ] **Step 6: Commit**

```bash
git add src/protocol.lisp src/tools.lisp src/providers/anthropic.lisp src/providers/openai.lisp src/providers/gemini.lisp src/providers/openrouter.lisp src/providers/ollama.lisp src/package.lisp tests/test-tools-integration.lisp
git commit -m "feat: translate-message-to-provider generic; tool loop round-trips on all providers"
```

**>>> Checkpoint: dispatch cobra-lisp-reviewer over Tasks 1-4 diff before continuing. <<<**

---

### Task 5: Working retry restarts + consolidated HTTP path + read timeouts

Three intertwined bugs: (a) `wait-and-retry`/`retry` restarts in `handle-http-error` (src/protocol.lisp:509-548) sleep-then-return-NIL — the provider then parses NIL as a response; (b) `make-retry-handler` (src/recovery.lisp:130-146) sleeps AND invokes `wait-and-retry` which sleeps again; (c) only Ollama sets `:read-timeout` — remote providers hang forever on stalled connections. Also `parse-retry-after` can hand a string to `sleep`. The fix consolidates the six copy-pasted dex:post blocks into one `provider-http-post` that loops while restarts return `:retry`.

**Files:**
- Modify: `src/protocol.lisp` (handle-http-error, parse-retry-after, new provider-http-post), `src/recovery.lisp:130-146`, `src/providers/{anthropic,openai,gemini,openrouter,ollama}.lisp` (replace non-streaming dex:post blocks; add read-timeout to streaming posts), `src/package.lisp` (export `#:provider-http-post`)
- Test: `tests/test-conditions-restarts.lisp` (new tests AND two existing tests updated — see Step 3a)

**Interfaces:**
- Produces: `provider-http-post (provider url headers content &key (operation :completion))` → parsed JSON hash on 2xx; re-issues the request whenever `handle-http-error` returns `:retry`. New contract on `handle-http-error`: every restart returns `:retry`; if nothing handles the condition, it signals and never returns. `use-fallback-provider` is REMOVED from handle-http-error (it never worked at this level) — Task 6 reintroduces it at the `complete` level where it can work. Read timeout comes from provider option `:timeout` (seconds, default 120).

- [ ] **Step 1: Write the failing tests**

Add to `tests/test-conditions-restarts.lisp`:

```lisp
(fiveam:test handle-http-error-retry-returns-directive
  (let ((provider (make-instance 'cl-llm-provider::openai-provider)))
    (handler-bind ((cl-llm-provider:provider-rate-limit-error
                     (lambda (c)
                       (declare (ignore c))
                       (invoke-restart 'cl-llm-provider:retry))))
      (fiveam:is (eq :retry
                     (cl-llm-provider::handle-http-error 429 "slow down" provider))))))

(fiveam:test handle-http-error-generic-retry-returns-directive
  (let ((provider (make-instance 'cl-llm-provider::openai-provider)))
    (handler-bind ((cl-llm-provider:provider-api-error
                     (lambda (c)
                       (declare (ignore c))
                       (invoke-restart 'cl-llm-provider:retry))))
      (fiveam:is (eq :retry
                     (cl-llm-provider::handle-http-error 500 "boom" provider))))))

(fiveam:test parse-retry-after-normalizes-strings
  (let ((ht (make-hash-table :test 'equal)))
    (setf (gethash "retry_after" ht) "30")
    (fiveam:is (= 30 (cl-llm-provider::parse-retry-after ht)))
    (setf (gethash "retry_after" ht) 15)
    (fiveam:is (= 15 (cl-llm-provider::parse-retry-after ht)))
    (setf (gethash "retry_after" ht) '(:junk))
    (fiveam:is (null (cl-llm-provider::parse-retry-after ht)))))

(fiveam:test make-retry-handler-invokes-retry-without-restart-sleep
  "Handler must invoke the RETRY restart (no second sleep inside wait-and-retry)."
  (let ((handler (cl-llm-provider:make-retry-handler
                  :max-retries 1
                  :backoff-fn (lambda (n) (declare (ignore n)) 0)))
        (invoked nil))
    (restart-case
        (progn
          (funcall handler (make-condition 'cl-llm-provider:provider-network-error
                                           :message "test"))
          nil)
      (cl-llm-provider:retry () (setf invoked t)))
    (fiveam:is (eq t invoked))))
```

- [ ] **Step 2: Run to verify failure** — restarts currently return NIL (sleep value), not `:retry`.

- [ ] **Step 3: Implement handle-http-error + parse-retry-after** (src/protocol.lisp):

```lisp
(defun/i handle-http-error (status-code body provider)
  "Signal appropriate condition for HTTP error.

STATUS-CODE - HTTP status code (integer)
BODY - Response body (string or hash-table)
PROVIDER - Provider instance

Contract: if a handler invokes any restart established here, HANDLE-HTTP-ERROR
returns :RETRY and the caller (PROVIDER-HTTP-POST) re-issues the request.
If no handler intervenes, the condition propagates and this never returns."
  (:feature http-transport)
  (:purpose "Classify HTTP errors and signal typed conditions with restarts")
  (let ((error-message (extract-error-message body)))
    (case status-code
      (401 (restart-case
               (error 'provider-authentication-error
                      :provider provider
                      :status-code status-code
                      :body body
                      :message error-message)
             (use-value (new-api-key)
               :report "Provide a new API key and retry"
               :interactive (lambda ()
                              (format *query-io* "Enter new API key: ")
                              (finish-output *query-io*)
                              (list (read-line *query-io*)))
               (setf (provider-api-key provider) new-api-key)
               :retry)))

      (429 (let ((retry-after (parse-retry-after body)))
             (restart-case
                 (error 'provider-rate-limit-error
                        :provider provider
                        :status-code status-code
                        :body body
                        :message error-message
                        :retry-after retry-after)
               (wait-and-retry ()
                 :report (lambda (s)
                           (format s "Wait ~@[~A seconds ~]and retry" retry-after))
                 (when retry-after (sleep retry-after))
                 :retry)
               (retry ()
                 :report "Retry immediately"
                 :retry))))

      (otherwise
       (multiple-value-bind (condition-type extra-initargs)
           (classify-api-error provider status-code body error-message)
         (restart-case
             (apply #'error condition-type
                    :provider provider
                    :status-code status-code
                    :body body
                    :message error-message
                    extra-initargs)
           (retry ()
             :report "Retry the request"
             :retry)))))))
```

`parse-retry-after` — normalize types, drop the dead handler-case:

```lisp
  (flet ((normalize (value)
           (typecase value
             (real value)
             (string (parse-integer value :junk-allowed t))
             (t nil)))
         (extract-from-hash (ht)
           (or (gethash "retry_after" ht)
               (gethash "retry-after" ht)
               (gethash "Retry-After" ht)
               (let ((err (gethash "error" ht)))
                 (when (hash-table-p err)
                   (or (gethash "retry_after" err)
                       (gethash "retry-after" err)))))))
    (cond
      ((hash-table-p body) (normalize (extract-from-hash body)))
      ((stringp body) (normalize body))
      (t nil)))
```

New `provider-http-post` (src/protocol.lisp, after handle-http-error):

```lisp
(defun/i provider-http-post (provider url headers content &key (operation :completion))
  "POST CONTENT to URL for PROVIDER with typed error handling and working retries.

Returns the parsed JSON response body (hash-table) on 2xx.
On HTTP errors delegates to HANDLE-HTTP-ERROR; whenever a retry restart is
invoked by a handler, the request is re-issued from scratch.
Honors provider option :timeout (read timeout in seconds, default 120)."
  (:feature http-transport)
  (:purpose "Single shared HTTP POST path with retry loop for all providers")
  (let ((read-timeout (getf (provider-options provider) :timeout 120)))
    (loop
      (multiple-value-bind (response-body status-code)
          (handler-case
              (dex:post url
                        :headers headers
                        :content content
                        :force-string t
                        :read-timeout read-timeout)
            (dex:http-request-failed (e)
              (values (dex:response-body e) (dex:response-status e)))
            (error (e)
              (error 'provider-network-error
                     :provider provider
                     :url url
                     :operation operation
                     :original-error e
                     :message (format nil "Network error: ~A" e))))
        (if (and (>= status-code 200) (< status-code 300))
            (return (yason:parse response-body))
            (let ((directive (handle-http-error
                              status-code
                              (handler-case (yason:parse response-body)
                                (error () response-body))
                              provider)))
              (unless (eq directive :retry)
                ;; Defensive: unknown directive — do not loop forever.
                (return directive))))))))
```

`make-retry-handler` (src/recovery.lisp) — prefer the non-sleeping `retry` restart (the handler already slept), and document freshness:

```lisp
        ;; Prefer the plain RETRY restart: this handler already slept above,
        ;; and WAIT-AND-RETRY would sleep the provider hint a second time.
        (let ((restart (or (find-restart 'retry condition)
                           (find-restart 'wait-and-retry condition))))
          (when restart
            (invoke-restart restart)))
```
Docstring addition: `"Create a FRESH handler per request: the attempt counter is closed over and never resets."`

Replace the non-streaming `multiple-value-bind ((response-body status-code) ... handler-case dex:post ...)` block in each of the five providers' `send-completion-request` and `send-embedding-request` with:

```lisp
    ;; e.g. openai.lisp send-completion-request tail:
    (with-performance-timing (:api-time)
      (provider-http-post provider url headers encoded-body :operation :completion))
```
(embedding requests pass `:operation :embedding`; ollama drops its bespoke `:read-timeout` since provider-http-post reads the same `:timeout` option). In the four streaming `send-streaming-request` methods add `:read-timeout (getf (provider-options provider) :timeout 120)` to the `dex:post ... :want-stream t` calls.

Update `provider-rate-limit-error`'s `:report` in src/conditions.lisp:93-96 — the restart list now reads:

```lisp
             (format s "Available restarts:~%")
             (format s "  • WAIT-AND-RETRY - Wait per retry-after hint, then retry~%")
             (format s "  • RETRY - Retry immediately~%")
```

Remove `#:use-fallback-provider` from package exports ONLY if Task 6 is skipped — Task 6 re-establishes it at the API level, so leave the export in place. Add `#:provider-http-post` to the exports in `src/package.lisp` (near `#:handle-http-error` in the protocol section) — it is the extension point custom providers build on.

- [ ] **Step 3a: Update the two existing tests that assert the removed restart**

`tests/test-conditions-restarts.lisp` asserts `use-fallback-provider` membership in `restart-handle-http-error-429` (line ~475) and `restart-handle-http-error-generic` (line ~500). Since that restart moves to the API level (Task 6), DELETE these two assertions:

```lisp
    (fiveam:is (member 'use-fallback-provider restarts-found))
```
and in each, add in its place:

```lisp
    ;; use-fallback-provider now lives at the COMPLETE/EMBEDDING/COMPLETE-STREAM
    ;; level (see use-fallback-provider-reissues-request), where the whole
    ;; request can actually be re-issued against the new provider.
```

- [ ] **Step 4: Run tests** — `tests/test-conditions-restarts.lisp`, `tests/test-provider-protocols.lisp`, `tests/test-request-response-handling.lisp` all pass.

- [ ] **Step 5: Commit**

```bash
git add src/protocol.lisp src/recovery.lisp src/conditions.lisp src/package.lisp src/providers/anthropic.lisp src/providers/openai.lisp src/providers/gemini.lisp src/providers/openrouter.lisp src/providers/ollama.lisp tests/test-conditions-restarts.lisp
git commit -m "fix: retry restarts actually retry via provider-http-post loop; read timeouts everywhere"
```

---

### Task 6: api.lisp — resolve helpers, working use-fallback-provider, safe interactive readers

The provider/model resolution boilerplate is triplicated (api.lisp:135-157, 243-265, 330-352) and its `:interactive` lambdas call `(eval (read))`. `use-fallback-provider` must live here — the only level where the whole request can be re-issued against a new provider.

**Files:**
- Modify: `src/api.lisp`
- Test: `tests/test-conditions-restarts.lisp`

**Interfaces:**
- Produces: internal `%resolve-provider (provider)` and `%resolve-model (model provider)`; `complete`, `embedding`, `complete-stream` each wrap their request in a `use-fallback-provider` restart loop. `use-provider`/`use-fallback-provider` restarts accept a provider instance OR a keyword (goes through `make-provider`) — no `eval` anywhere.

- [ ] **Step 1: Write the failing tests**

```lisp
(fiveam:test use-provider-restart-accepts-keyword
  (let ((cl-llm-provider::*default-provider* nil))
    (handler-bind ((cl-llm-provider:provider-configuration-error
                     (lambda (c)
                       (declare (ignore c))
                       (invoke-restart 'cl-llm-provider:use-provider :ollama))))
      (let ((p (cl-llm-provider::%resolve-provider nil)))
        (fiveam:is (typep p 'cl-llm-provider::ollama-provider))))))
```

Test-double provider classes at TOP LEVEL of the test file (defined once at load;
no method cleanup needed — class-specialized, not eql-specialized). Both inherit
`openai-provider` so `parse-completion-response` uses the OpenAI parser:

```lisp
(defclass failing-test-provider (cl-llm-provider::openai-provider) ())
(defclass working-test-provider (cl-llm-provider::openai-provider) ())

(defvar *fallback-test-calls* '())

(defmethod cl-llm-provider:send-completion-request
    ((p failing-test-provider) messages &key &allow-other-keys)
  (declare (ignore messages))
  (push :failing *fallback-test-calls*)
  (error 'cl-llm-provider:provider-api-error :provider p :message "down"))

(defmethod cl-llm-provider:send-completion-request
    ((p working-test-provider) messages &key &allow-other-keys)
  (declare (ignore messages))
  (push :working *fallback-test-calls*)
  (yason:parse "{\"id\":\"r1\",\"model\":\"m\",
\"choices\":[{\"finish_reason\":\"stop\",
 \"message\":{\"role\":\"assistant\",\"content\":\"ok\"}}]}"))
```

```lisp
(fiveam:test use-fallback-provider-reissues-request
  "After USE-FALLBACK-PROVIDER, complete must re-issue against the new provider."
  (setf *fallback-test-calls* '())
  (let ((failing (make-instance 'failing-test-provider :model "m"))
        (working (make-instance 'working-test-provider :model "m")))
    (handler-bind ((cl-llm-provider:provider-api-error
                     (lambda (c)
                       (declare (ignore c))
                       (invoke-restart 'cl-llm-provider:use-fallback-provider working))))
      (let ((resp (cl-llm-provider:complete '((:role "user" :content "hi"))
                                            :provider failing :model "m")))
        (fiveam:is (string= "ok" (cl-llm-provider:response-content resp)))
        (fiveam:is (equal '(:working :failing) *fallback-test-calls*))))))
```

- [ ] **Step 2: Run to verify failure** — `%resolve-provider` undefined; no `use-fallback-provider` restart active in `complete`.

- [ ] **Step 3: Implement** (src/api.lisp, before `complete`):

```lisp
(defun %coerce-provider (designator)
  "Accept a provider instance or a keyword designator (via MAKE-PROVIDER)."
  (etypecase designator
    (llm-provider designator)
    (keyword (make-provider designator))))

(defun %resolve-provider (provider)
  "Return PROVIDER or *default-provider*; signal with a USE-PROVIDER restart when absent."
  (or provider *default-provider*
      (restart-case
          (error 'provider-configuration-error
                 :message "No provider specified and *default-provider* is nil")
        (use-provider (p)
          :report "Supply a provider (instance or keyword like :anthropic)"
          :interactive (lambda ()
                         (format *query-io* "Enter provider keyword (e.g. :anthropic): ")
                         (finish-output *query-io*)
                         (let ((*read-eval* nil))
                           (list (read *query-io*))))
          (%coerce-provider p)))))

(defun %resolve-model (model provider)
  "Return MODEL, the provider default, or *default-model*; restartable when all NIL."
  (or model
      (and provider (provider-default-model provider))
      *default-model*
      (restart-case
          (error 'provider-configuration-error
                 :message "No model specified and no default model configured")
        (use-model (m)
          :report "Supply a model name"
          :interactive (lambda ()
                         (format *query-io* "Enter model name: ")
                         (finish-output *query-io*)
                         (list (read-line *query-io*)))
          m))))
```

In `complete`: replace the two `unless prov/mod restart-case` blocks with

```lisp
  (let* ((prov (%resolve-provider provider))
         (mod (%resolve-model model prov))
         ...)   ; request-info now built AFTER resolution — prov is never NIL here
```

and wrap the existing handler-bind + request/parse/hooks body in the fallback loop:

```lisp
    (loop
      (restart-case
          (return
            <existing handler-bind ... response body, unchanged, using prov/mod>)
        (use-fallback-provider (fallback)
          :report "Re-issue the request with a different provider"
          :interactive (lambda ()
                         (format *query-io* "Enter fallback provider keyword: ")
                         (finish-output *query-io*)
                         (let ((*read-eval* nil))
                           (list (read *query-io*))))
          (setf prov (%coerce-provider fallback)))))
```

Apply the same two changes to `embedding` and `complete-stream` (delete their duplicated `unless` blocks; wrap their request forms in the same restart loop).

Also in `complete-stream`'s docstring add: `"Note: when callbacks are supplied, errors during reading propagate to the caller after ON-ERROR fires; the stream object is only returned on success."` And fix the unbalanced paren in `complete`'s multi-turn docstring example (line ~111: add the missing `))`).

- [ ] **Step 4: Run tests** — `tests/test-conditions-restarts.lisp` plus full `tests/test-observability.lisp` (hook paths in complete changed structurally).

- [ ] **Step 5: Commit**

```bash
git add src/api.lisp tests/test-conditions-restarts.lisp
git commit -m "feat: working use-fallback-provider at API level; dedup resolution; no eval in restarts"
```

---

### Task 7: with-auto-recovery macro hygiene

`src/recovery.lisp:198` uses a literal `auto-recovery` block name and `retry-point` tag — user code containing `(return-from auto-recovery ...)` silently returns from the macro's block instead of its own.

**Files:**
- Modify: `src/recovery.lisp:191-222`
- Test: `tests/test-conditions-restarts.lisp`

- [ ] **Step 1: Failing test**

```lisp
(fiveam:test with-auto-recovery-does-not-capture-block-names
  (fiveam:is (eq :escaped
                 (block auto-recovery
                   (cl-llm-provider:with-auto-recovery ()
                     (return-from auto-recovery :escaped))
                   :not-escaped))))
```

- [ ] **Step 2: Run to verify failure** — returns `:not-escaped` (inner block swallowed the return).

- [ ] **Step 3: Implement** — gensym block and tag; make the fallbacks copy unconditional:

```lisp
  (with-gensyms (retry-count max-r bb fallbacks on-retry-fn condition wait
                 recovery-block retry-point)
    `(let ((,retry-count 0)
           (,max-r ,max-retries)
           (,bb ,backoff-base)
           (,fallbacks (copy-list ,fallback-providers))
           (,on-retry-fn ,on-retry)
           (*default-provider* *default-provider*))
       (block ,recovery-block
         (tagbody
           ,retry-point
           (handler-bind
               ((llm-provider-error
                  (lambda (,condition)
                    (when (transient-error-p ,condition)
                      (cond
                        ((< ,retry-count ,max-r)
                         (incf ,retry-count)
                         (when ,on-retry-fn
                           (funcall ,on-retry-fn ,condition ,retry-count))
                         (let ((,wait (retry-wait-time ,condition ,retry-count ,bb)))
                           (when (> ,wait 0)
                             (sleep ,wait)))
                         (go ,retry-point))
                        (,fallbacks
                         (setf *default-provider* (pop ,fallbacks))
                         (setf ,retry-count 0)
                         (when ,on-retry-fn
                           (funcall ,on-retry-fn ,condition 0))
                         (go ,retry-point)))))))
             (return-from ,recovery-block (progn ,@body))))))))
```

- [ ] **Step 4: Run tests** — including existing recovery tests in test-conditions-restarts.lisp.

- [ ] **Step 5: Commit**

```bash
git add src/recovery.lisp tests/test-conditions-restarts.lisp
git commit -m "fix: gensym block/tag names in with-auto-recovery (hygiene)"
```

**>>> Checkpoint: cobra-lisp-reviewer over Tasks 5-7. <<<**

---

### Task 8: Config path — defconstant → lazily computed function

`(defconstant +default-config-file-path+ (merge-pathnames ...))` (src/config.lisp:30) signals `DEFCONSTANT-UNEQL` on every reload under SBCL and bakes the build machine's XDG path into images.

**Files:**
- Modify: `src/config.lisp:28-37`, `src/package.lisp` (add `#:default-config-file-path` next to `#:+default-config-file-path+` at line 45)
- Test: `tests/test-provider-protocols.lisp`

- [ ] **Step 1: Failing test**

```lisp
(fiveam:test config-path-reload-safe
  "config.lisp must be loadable twice (no DEFCONSTANT-UNEQL) and path computed lazily."
  (fiveam:is (pathnamep (cl-llm-provider:default-config-file-path)))
  (fiveam:finishes (load "src/config.lisp"))
  (fiveam:finishes (load "src/config.lisp")))
```

- [ ] **Step 2: Run to verify failure** — `default-config-file-path` undefined (and second load would signal on a fresh SBCL when values differ).

- [ ] **Step 3: Implement**

```lisp
(defun default-config-file-path ()
  "Return the default configuration file path, computed at call time from the
current XDG-CONFIG-HOME. This is a SUGGESTED path only — the library never
loads it automatically."
  (merge-pathnames "cl-llm-provider/config.lisp" (uiop:xdg-config-home)))

(define-symbol-macro +default-config-file-path+ (default-config-file-path))
```

`load-configuration-from-file`'s default argument keeps working (the symbol-macro evaluates lazily). Export `#:default-config-file-path`.

- [ ] **Step 4: Run tests, verify pass.**

- [ ] **Step 5: Commit**

```bash
git add src/config.lisp src/package.lisp tests/test-provider-protocols.lisp
git commit -m "fix: compute config path lazily; no defconstant on pathname (reload-safe)"
```

---

### Task 9: Interactive input hardening in tools subsystem

`(eval (read))` in restart `:interactive` lambdas (src/tools/execution.lisp:99, 184, 248) is a live REPL inside error recovery; `(read stream)` in the approval callback (src/tools/approval.lisp:170) honors `#.`; `(char input 0)` (approval.lisp:158) crashes on empty input — in the approval path for DANGEROUS tools.

**Files:**
- Modify: `src/tools/execution.lisp`, `src/tools/approval.lisp:138-174`, `src/tools/package.lisp` (export approval-callback constructors)
- Test: `tests/test-tools-enhanced.lisp`

- [ ] **Step 0: Export the approval-callback constructors**

`src/tools/package.lisp` currently exports only `needs-approval-p`, `request-tool-approval`, `normalize-approval-result` from approval.lisp — the documented callback constructors are trapped inside the package (the tests below, and any user of the approval system, need them). Add to the `;; Approval` export section:

```lisp
   #:make-auto-approve-callback
   #:make-auto-reject-callback
   #:make-safety-based-callback
   #:make-interactive-approval-callback
```

- [ ] **Step 1: Failing tests**

```lisp
(fiveam:test interactive-approval-rejects-empty-input
  (let* ((tool (cl-llm-provider:define-tool "t" "test tool" '()))
         (call (make-instance 'cl-llm-provider:tool-call
                              :id "c1" :name "t" :arguments nil))
         (input (make-string-input-stream (format nil "~%")))
         (output (make-string-output-stream))
         (io (make-two-way-stream input output))
         (callback (cl-llm-provider.tools:make-interactive-approval-callback
                    :stream io)))
    (fiveam:is (eq :rejected (funcall callback tool call nil)))))

(fiveam:test interactive-approval-edit-does-not-read-eval
  (let* ((tool (cl-llm-provider:define-tool "t" "test tool" '()))
         (call (make-instance 'cl-llm-provider:tool-call
                              :id "c1" :name "t" :arguments nil))
         (input (make-string-input-stream
                 (format nil "E~%#.(error \"pwned\")~%")))
         (output (make-string-output-stream))
         (io (make-two-way-stream input output))
         (callback (cl-llm-provider.tools:make-interactive-approval-callback
                    :stream io)))
    (fiveam:signals reader-error (funcall callback tool call nil))))
```

- [ ] **Step 2: Run to verify failure** — empty input signals an index error; `#.` evaluates (test sees "pwned" error, not reader-error).

- [ ] **Step 3: Implement**

approval.lisp `make-interactive-approval-callback` dispatch:

```lisp
    (let ((input (read-line stream)))
      (cond
        ((zerop (length input))
         (format stream "Empty input. Rejecting.~%")
         :rejected)
        ((member (char-upcase (char input 0)) '(#\A #\Y))
         :approved)
        ((member (char-upcase (char input 0)) '(#\R #\N))
         (format stream "Reason (optional): ")
         (finish-output stream)
         (let ((reason (read-line stream)))
           (if (string= reason "")
               :rejected
               (list :rejected reason))))
        ((char-equal (char input 0) #\E)
         (format stream "Enter new arguments plist: ")
         (finish-output stream)
         (let ((new-args (let ((*read-eval* nil))
                           (read stream))))
           (list :edited new-args)))
        (t
         (format stream "Invalid input. Rejecting.~%")
         :rejected)))
```

execution.lisp — the three `:interactive` lambdas. Handler-supplying restarts (lines 99, 248) use `coerce` (standard CL: coerces a lambda expression to a function without `eval`):

```lisp
          :interactive (lambda ()
                         (format *query-io* "Enter handler lambda: ")
                         (finish-output *query-io*)
                         (list (coerce (let ((*read-eval* nil))
                                         (read *query-io*))
                                       'function)))
```

Value-supplying restart (line 184):

```lisp
          :interactive (lambda ()
                         (format *query-io* "Enter result value (literal): ")
                         (finish-output *query-io*)
                         (let ((*read-eval* nil))
                           (list (read *query-io*))))
```

- [ ] **Step 4: Run tests** — `tests/test-tools-enhanced.lisp`.

- [ ] **Step 5: Commit**

```bash
git add src/tools/approval.lisp src/tools/execution.lisp src/tools/package.lisp tests/test-tools-enhanced.lisp
git commit -m "fix: no eval/read-eval in interactive restarts; approval survives empty input; export approval callbacks"
```

---

### Task 10: Condition report provider naming

`provider-api-error`'s report (src/conditions.lisp:53-59) compares symbols with `EQUAL` against a stale hardcoded list — `gemini-provider` missing, custom providers print "Provider". Use the `provider-name` generic.

**Files:**
- Modify: `src/conditions.lisp:48-59`, `src/protocol.lisp` (default `provider-name` method)
- Test: `tests/test-conditions-restarts.lisp`

- [ ] **Step 1: Failing test**

```lisp
(fiveam:test api-error-report-names-gemini
  (let ((c (make-condition 'cl-llm-provider:provider-api-error
                           :provider (make-instance 'cl-llm-provider::gemini-provider)
                           :status-code 500 :message "boom")))
    (fiveam:is (search "Google Gemini" (princ-to-string c)))))
```

- [ ] **Step 2: Run to verify failure** — prints "Provider API Error".

- [ ] **Step 3: Implement**

protocol.lisp, after the `provider-name` defgeneric:

```lisp
(defmethod provider-name ((provider llm-provider))
  "Fallback display name for custom providers without a specialized method."
  "Provider")
```

conditions.lisp report — replace the whole `cond` at lines 49-59:

```lisp
               (format s "~A API Error~%"
                       (let ((p (error-provider c)))
                         (if p
                             (handler-case (provider-name p)
                               (error () "Provider"))
                             "Provider")))
```
(delete the now-unused `provider-type` let binding).

- [ ] **Step 4: Run tests, verify pass.**

- [ ] **Step 5: Commit**

```bash
git add src/conditions.lisp src/protocol.lisp tests/test-conditions-restarts.lisp
git commit -m "fix: condition reports use provider-name generic (gemini + custom providers)"
```

**>>> Checkpoint: cobra-lisp-reviewer over Tasks 8-10. <<<**

---

### Task 11: types.lisp hardening — initforms, print-object, intern caps

Unbound-slot errors in `print-object` during error reporting (src/types.lisp:93-99, 215-219 with no `:initform` on id/model/message/finish-reason/usage/raw); unbounded keyword interning from model-generated JSON keys (types.lisp:305); `parse-sse-line` interns arbitrary SSE field names (streaming.lisp:40).

**Files:**
- Modify: `src/types.lisp`, `src/streaming.lisp:36-41`
- Test: `tests/test-request-response-handling.lisp`, `tests/test-streaming.lisp`

- [ ] **Step 1: Failing tests**

```lisp
;; test-request-response-handling.lisp
(fiveam:test response-printable-when-partially-initialized
  (fiveam:finishes
    (princ-to-string (make-instance 'cl-llm-provider:completion-response)))
  (fiveam:finishes
    (princ-to-string (make-instance 'cl-llm-provider::embedding-response))))

(fiveam:test json-keys-over-cap-stay-strings
  (let ((ht (make-hash-table :test 'equal)))
    (setf (gethash (make-string 200 :initial-element #\a) ht) "v")
    (let ((plist (handler-bind ((warning #'muffle-warning))
                   (cl-llm-provider::%json-hash-to-keyword-plist ht))))
      (fiveam:is (stringp (first plist))))))

;; test-streaming.lisp
(fiveam:test sse-unknown-fields-not-interned
  (fiveam:is (null (cl-llm-provider::parse-sse-line "x-custom-field: whatever")))
  (fiveam:is (equal '(:id . "42") (cl-llm-provider::parse-sse-line "id: 42"))))
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

types.lisp: add `:initform nil` to `completion-response` slots `id`, `model`, `message`, `finish-reason`, `usage`, `raw`; and to `embedding-response` slots `embeddings`, `model`, `usage`, `raw`. Guard `embedding-response` print-object: `(length (or (response-embeddings response) '()))`.

`%json-hash-to-keyword-plist` interning branch:

```lisp
       (maphash (lambda (k v)
                  ;; TRUST boundary: keys come from provider JSON, but tool-call
                  ;; ARGUMENT keys are model-generated. Keywords are never GC'd,
                  ;; so pathologically long keys stay strings (with a warning).
                  (let ((key (if (<= (length k) 128)
                                 (intern (string-upcase (substitute #\- #\_ k))
                                         :keyword)
                                 (progn
                                   (warn 'llm-provider-warning
                                         :message (format nil "JSON key of ~D chars exceeds intern cap; keeping string key" (length k)))
                                   k))))
                    (push (%json-hash-to-keyword-plist v) result)
                    (push key result)))
                value)
```

streaming.lisp `parse-sse-line` final clause — whitelist:

```lisp
    ;; Other fields: only the SSE-standard ones; never intern wire data
    (t
     (let ((colon-pos (position #\: line)))
       (when colon-pos
         (let ((field (subseq line 0 colon-pos)))
           (cond
             ((string-equal field "id")
              (cons :id (string-trim '(#\Space) (subseq line (1+ colon-pos)))))
             ((string-equal field "retry")
              (cons :retry (string-trim '(#\Space) (subseq line (1+ colon-pos)))))
             (t nil))))))
```

- [ ] **Step 4: Run tests** — both files, plus test-properties.lisp.

- [ ] **Step 5: Commit**

```bash
git add src/types.lisp src/streaming.lisp tests/test-request-response-handling.lisp tests/test-streaming.lisp
git commit -m "fix: initforms for response slots; cap wire-data keyword interning; SSE field whitelist"
```

---

### Task 12: Streaming — CLOS dispatch and tool-call delta capture

`read-stream-chunk :around` hardcodes `(typep provider 'anthropic-provider)` (streaming.lisp:157-163) defeating extensibility, and both stream parsers silently DROP tool-call deltas (`delta.tool_calls`, `input_json_delta`) — streaming + tools loses the calls with no error.

**Files:**
- Modify: `src/streaming.lisp`, `src/types.lisp` (new stream slot), `src/package.lisp` (export `#:stream-tool-calls`, `#:chunk-tool-call-delta` if not already)
- Test: `tests/test-streaming.lisp`

**Interfaces:**
- Produces: generic `%read-provider-chunk (provider stream)` — new providers specialize this instead of being typep'd. `(stream-tool-calls stream)` → list of assembled `tool-call` objects after the stream finishes. `chunk-tool-call-delta` → list of partial plists `(:index N :id S :function (:name S :arguments fragment))`.

- [ ] **Step 1: Failing tests** (synthetic SSE via string streams — `completion-stream`'s http-stream is any character stream):

```lisp
(fiveam:test openai-stream-accumulates-tool-call-deltas
  (let* ((sse (format nil "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_9\",\"type\":\"function\",\"function\":{\"name\":\"add\",\"arguments\":\"\"}}]}}]}~%~%data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"a\\\":2}\"}}]}}]}~%~%data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}~%~%data: [DONE]~%~%"))
         (provider (make-instance 'cl-llm-provider::openai-provider))
         (stream (make-instance 'cl-llm-provider::completion-stream
                                :provider provider :model "m"
                                :http-stream (make-string-input-stream sse))))
    (loop for chunk = (cl-llm-provider:read-stream-chunk stream)
          while chunk)
    (let ((calls (cl-llm-provider:stream-tool-calls stream)))
      (fiveam:is (= 1 (length calls)))
      (fiveam:is (string= "call_9" (cl-llm-provider:tool-call-id (first calls))))
      (fiveam:is (string= "add" (cl-llm-provider:tool-call-name (first calls))))
      (fiveam:is (= 2 (getf (cl-llm-provider:tool-call-arguments (first calls)) :a))))))

(fiveam:test anthropic-stream-accumulates-tool-use
  (let* ((sse (format nil "event: content_block_start~%data: {\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_9\",\"name\":\"add\"}}~%~%event: content_block_delta~%data: {\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"a\\\":2}\"}}~%~%event: message_stop~%data: {}~%~%"))
         (provider (make-instance 'cl-llm-provider::anthropic-provider))
         (stream (make-instance 'cl-llm-provider::completion-stream
                                :provider provider :model "m"
                                :http-stream (make-string-input-stream sse))))
    (loop for chunk = (cl-llm-provider:read-stream-chunk stream)
          while chunk)
    (let ((calls (cl-llm-provider:stream-tool-calls stream)))
      (fiveam:is (= 1 (length calls)))
      (fiveam:is (string= "toolu_9" (cl-llm-provider:tool-call-id (first calls)))))))
```

- [ ] **Step 2: Run to verify failure** — `stream-tool-calls` undefined; deltas dropped.

- [ ] **Step 3: Implement**

types.lisp `completion-stream` — new slot after `error-condition`:

```lisp
   (tool-call-parts :initform (make-hash-table)
                    :accessor stream-tool-call-parts
                    :documentation "index -> (:id str :name str :arguments adjustable-string),
accumulated from tool-call deltas while streaming. Read via STREAM-TOOL-CALLS.")
```

streaming.lisp — dispatch: delete the `:around` method; rename the existing openai-format `read-stream-chunk` body into `%read-openai-format-chunk (stream)` (a plain defun, body unchanged) and:

```lisp
(defgeneric %read-provider-chunk (provider stream)
  (:documentation "Provider-specific stream reader; specialize for new SSE dialects."))

(defmethod %read-provider-chunk ((provider llm-provider) stream)
  (%read-openai-format-chunk stream))

(defmethod %read-provider-chunk ((provider anthropic-provider) stream)
  (read-anthropic-stream-chunk stream))

(defmethod read-stream-chunk ((stream completion-stream) &key timeout)
  (declare (ignore timeout))  ; TODO: timeout not implemented (documented no-op)
  (%read-provider-chunk (stream-provider stream) stream))
```

`parse-openai-stream-data` — capture deltas:

```lisp
            (tool-call-deltas (when delta (gethash "tool_calls" delta)))
       ...
       (make-instance 'stream-chunk
                      ...
                      :tool-call-delta (when tool-call-deltas
                                         (%json-hash-to-keyword-plist tool-call-deltas))
                      ...)
```
(Return a chunk even when `content` is NIL but `tool-call-deltas` is present — adjust the surrounding `cond` so that case doesn't fall through to nil.)

`parse-anthropic-stream-event` — two new branches:

```lisp
      ;; Tool-use block opening: carries id and name
      ((string= event-type "content_block_start")
       (let ((block (gethash "content_block" json)))
         (when (and block (string= (gethash "type" block) "tool_use"))
           (make-instance 'stream-chunk
                          :delta "" :content "" :index index
                          :tool-call-delta
                          (list (list :index (gethash "index" json)
                                      :id (gethash "id" block)
                                      :function (list :name (gethash "name" block)
                                                      :arguments "")))))))
```
and inside the existing `content_block_delta` branch, alongside `text_delta`:
```lisp
              (json-fragment (when (string= delta-type "input_json_delta")
                               (gethash "partial_json" delta))))
         (cond
           (text (make-instance 'stream-chunk :delta text :content text :index index))
           (json-fragment
            (make-instance 'stream-chunk
                           :delta "" :content "" :index index
                           :tool-call-delta
                           (list (list :index (gethash "index" json)
                                       :function (list :arguments json-fragment))))))
```

Accumulator + assembly (streaming.lisp):

```lisp
(defun %accumulate-tool-call-delta (stream chunk)
  "Fold CHUNK's tool-call deltas into STREAM's per-index accumulator."
  (dolist (part (chunk-tool-call-delta chunk))
    (let* ((idx (or (getf part :index) 0))
           (entry (or (gethash idx (stream-tool-call-parts stream))
                      (list :id nil :name nil
                            :arguments (make-array 0 :element-type 'character
                                                     :adjustable t :fill-pointer 0))))
           (fn (getf part :function)))
      (when (getf part :id) (setf (getf entry :id) (getf part :id)))
      (when (getf fn :name) (setf (getf entry :name) (getf fn :name)))
      (when (getf fn :arguments)
        (buffer-append (getf entry :arguments) (getf fn :arguments)))
      (setf (gethash idx (stream-tool-call-parts stream)) entry))))

(defun stream-tool-calls (stream)
  "Assemble tool-call deltas accumulated during streaming into tool-call objects.
Meaningful once the stream has finished (finish-reason :tool-calls or closed).
Returns a list ordered by tool-call index, or NIL if no tool calls streamed."
  (let ((parts '()))
    (maphash (lambda (idx entry) (push (cons idx entry) parts))
             (stream-tool-call-parts stream))
    (loop for (nil . entry) in (sort parts #'< :key #'car)
          collect (make-instance 'tool-call
                                 :id (getf entry :id)
                                 :name (getf entry :name)
                                 :arguments (%parse-tool-arguments
                                             (copy-seq (getf entry :arguments))
                                             (getf entry :name))))))
```

In BOTH read loops (`%read-openai-format-chunk` and `read-anthropic-stream-chunk`), next to the existing `buffer-append` of the text delta:

```lisp
                          (when (chunk-tool-call-delta chunk)
                            (%accumulate-tool-call-delta stream chunk))
```

Export `#:stream-tool-calls` (and `#:chunk-tool-call-delta` if missing) in package.lisp. Document in `read-stream-chunk`'s defgeneric docstring: "TIMEOUT is currently accepted but not implemented."

- [ ] **Step 4: Run tests** — `tests/test-streaming.lisp` (all existing + new).

- [ ] **Step 5: Commit**

```bash
git add src/streaming.lisp src/types.lisp src/package.lisp tests/test-streaming.lisp
git commit -m "feat: streaming tool-call delta capture + CLOS provider dispatch for stream reading"
```

---

### Task 13: Ollama honesty — capability, tool-call ids, modern embed endpoint

Ollama advertises `:streaming t` but implements no `send-streaming-request`; tool-call ids use unseeded `(random 1000000)` (collision-prone, breaks result correlation); embeddings use the deprecated single-string `/api/embeddings` and silently drop list input and `:dimensions`.

**Files:**
- Modify: `src/providers/ollama.lisp`
- Test: `tests/test-provider-protocols.lisp`

- [ ] **Step 1: Failing tests**

```lisp
(fiveam:test ollama-capabilities-honest
  (let ((provider (make-instance 'cl-llm-provider::ollama-provider)))
    (fiveam:is (null (cl-llm-provider:provider-supports-p provider :streaming)))))

(fiveam:test ollama-tool-call-ids-unique
  (let* ((provider (make-instance 'cl-llm-provider::ollama-provider))
         (raw-json "{\"model\":\"m\",\"message\":{\"role\":\"assistant\",
\"tool_calls\":[{\"function\":{\"name\":\"f\",\"arguments\":{\"x\":1}}},
               {\"function\":{\"name\":\"g\",\"arguments\":{\"y\":2}}}]}}")
         (resp1 (cl-llm-provider:parse-completion-response provider (yason:parse raw-json)))
         (resp2 (cl-llm-provider:parse-completion-response provider (yason:parse raw-json)))
         (ids (mapcar #'cl-llm-provider:tool-call-id
                      (append (cl-llm-provider:response-tool-calls resp1)
                              (cl-llm-provider:response-tool-calls resp2)))))
    (fiveam:is (= 4 (length (remove-duplicates ids :test #'string=))))))

(fiveam:test ollama-embed-response-parses-batch
  (let* ((provider (make-instance 'cl-llm-provider::ollama-provider))
         (raw (yason:parse "{\"model\":\"m\",\"embeddings\":[[0.1,0.2],[0.3,0.4]]}"))
         (resp (cl-llm-provider:parse-embedding-response provider raw)))
    (fiveam:is (= 2 (length (cl-llm-provider::response-embeddings resp))))
    (fiveam:is (= 2 (length (first (cl-llm-provider::response-embeddings resp)))))))
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

Capabilities: `:streaming nil  ; no send-streaming-request implemented yet (NDJSON /api/chat)`.

Tool-call id counter (top of ollama.lisp):

```lisp
(defvar *ollama-tool-call-counter* 0)
(defvar *ollama-tool-call-lock* (bt:make-lock "ollama-tool-call-ids")
  "Serializes tool-call id generation; Ollama responses carry no ids of their own.")

(defun %next-ollama-tool-call-id ()
  (bt:with-lock-held (*ollama-tool-call-lock*)
    (format nil "call_~D" (incf *ollama-tool-call-counter*))))
```
In `parse-completion-response`: `:id (or (gethash "id" tc) (%next-ollama-tool-call-id))`.

Embeddings — `send-embedding-request` switches to the modern batching endpoint:

```lisp
  (let* ((url (format nil "~A/api/embed" (provider-base-url provider)))
         ...)
    (when dimensions
      (warn 'llm-provider-warning
            :provider provider
            :message "Ollama does not support the :dimensions parameter; ignoring it"))
    ...
        (setf (gethash "input" body)
              (etypecase input
                (string input)
                (list input)))
```
(remove `(declare (ignore dimensions))` and the `"prompt"` key). `parse-embedding-response`:

```lisp
  (let ((embeddings (or (gethash "embeddings" raw-response)
                        ;; legacy /api/embeddings single-vector shape
                        (when-let ((e (gethash "embedding" raw-response)))
                          (vector e)))))
    (make-instance 'embedding-response
                   :embeddings (map 'list (lambda (v) (coerce v 'list))
                                    (or embeddings #()))
                   :model (or (gethash "model" raw-response) "unknown")
                   :usage (list :prompt-tokens
                                (or (gethash "prompt_eval_count" raw-response) 0)
                                :total-tokens
                                (or (gethash "prompt_eval_count" raw-response) 0))
                   ...unchanged raw/performance/metadata...))
```

- [ ] **Step 4: Run tests, verify pass.**

- [ ] **Step 5: Commit**

```bash
git add src/providers/ollama.lisp tests/test-provider-protocols.lisp
git commit -m "fix: Ollama honest streaming capability, unique tool-call ids, /api/embed batching"
```

**>>> Checkpoint: cobra-lisp-reviewer over Tasks 11-13. <<<**

---

### Task 14: Tools subsystem — typed conditions, safety propagation, retry hooks

Bare `(error "...")` in registry/validators/categories denies callers typed handling; `execute-tool-calls` flattens `tool-approval-error`/`tool-safety-violation` into result strings sent back to the LLM (a rejected dangerous tool looks like a failed weather lookup); `retry-execution` restart bypasses the on-complete hook.

**Files:**
- Modify: `src/conditions.lisp` (new condition), `src/package.lisp` (export), `src/tools/registry.lisp:108-116`, `src/tools/categories.lisp:41,43,57,75`, `src/tools/validators.lisp:107,139,176`, `src/tools/execution.lisp:151-185,211-227`
- Test: `tests/test-tools-enhanced.lisp`

**Interfaces:**
- Consumes: `cl-llm-provider.tools:make-auto-reject-callback` — exported by Task 9 Step 0 (Task 9 must run before this task).

- [ ] **Step 1: Failing tests**

```lisp
(fiveam:test register-tool-signals-typed-condition
  (let ((registry (cl-llm-provider.tools:make-tool-registry :name "r"))
        (tool (cl-llm-provider:define-tool "dup" "d" '())))
    (cl-llm-provider.tools:register-tool registry tool)
    (fiveam:signals cl-llm-provider:tool-registration-error
      (cl-llm-provider.tools:register-tool registry tool))))

(fiveam:test execute-tool-calls-propagates-safety-conditions
  "Approval rejections must reach the caller, not become LLM-visible strings."
  (let* ((registry (cl-llm-provider.tools:make-tool-registry :name "r"))
         (tool (cl-llm-provider:define-tool "rm" "dangerous" '()
                 :safety-level :dangerous
                 :requires-approval :always
                 :handler (lambda (args) (declare (ignore args)) "done")))
         (call (make-instance 'cl-llm-provider:tool-call
                              :id "c1" :name "rm" :arguments nil))
         (response (make-instance 'cl-llm-provider:completion-response
                                  :tool-calls (list call))))
    (cl-llm-provider.tools:register-tool registry tool)
    (fiveam:signals cl-llm-provider:tool-approval-error
      (cl-llm-provider.tools:execute-tool-calls
       response
       :registry registry
       :approval-callback (cl-llm-provider.tools:make-auto-reject-callback)))))

(fiveam:test retry-execution-restart-fires-on-complete-hook
  (let* ((completions 0)
         (attempts 0)
         (tool (cl-llm-provider:define-tool "flaky" "f" '()
                 :on-complete (lambda (call args result)
                                (declare (ignore call args result))
                                (incf completions))
                 :handler (lambda (args)
                            (declare (ignore args))
                            (incf attempts)
                            (if (= attempts 1) (error "transient") "ok"))))
         (call (make-instance 'cl-llm-provider:tool-call
                              :id "c1" :name "flaky" :arguments nil)))
    (handler-bind ((error (lambda (e)
                            (declare (ignore e))
                            (let ((r (find-restart 'cl-llm-provider.tools::retry-execution)))
                              (when r (invoke-restart r))))))
      (fiveam:is (string= "ok" (cl-llm-provider.tools:execute-tool tool call))))
    (fiveam:is (= 1 completions))))
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

conditions.lisp — new condition after `tool-schema-error`:

```lisp
(define-condition/i tool-registration-error (llm-provider-error)
  ((tool-name :initarg :tool-name
              :initform nil
              :reader error-tool-name
              :documentation "Name of the tool being registered."))
  (:feature tool-calling)
  (:purpose "Signal tool registry conflicts")
  (:documentation "Signaled when tool registration fails (e.g. duplicate name).")
  (:report (lambda (c s)
             (format s "Tool registration error~@[ for ~S~]~@[: ~A~]"
                     (error-tool-name c)
                     (error-message c)))))
```
Export `#:tool-registration-error` and `#:error-tool-name` in package.lisp.

registry.lisp:113:
```lisp
      (error 'tool-registration-error
             :tool-name name
             :message (format nil "Tool ~S already registered in registry ~S. Use :replace t to overwrite."
                              name (registry-name registry)))
```

categories.lisp and validators.lisp: replace each bare `(error "...")` at the cited lines with `(error 'tool-schema-error :reason (format nil <same message and args>))` (these are all invalid-specification errors — `tool-schema-error` with its `:reason` slot fits; `:tool` stays nil).

execution.lisp `execute-tool-calls` — the tool-found branch (lines 216-227):

```lisp
          (tool
           (block execute-one
             (handler-bind
                 ((error (lambda (e)
                           ;; Approval rejections and safety violations must reach
                           ;; the caller — do NOT flatten them into LLM-visible
                           ;; result strings like ordinary tool failures.
                           (unless (typep e '(or tool-approval-error
                                                 tool-safety-violation))
                             (push (cons call e) results)
                             (return-from execute-one)))))
               (push (cons call (execute-tool tool call
                                              :registry registry
                                              :skip-approval skip-approval
                                              :skip-validation skip-validation
                                              :approval-callback approval-callback
                                              :max-safety-level max-safety-level))
                     results))))
```
Update the docstring: "Signals tool-approval-error / tool-safety-violation instead of recording them as results."

execution.lisp `execute-tool` step 5 — hoist the handler+hooks into a local function so `retry-execution` goes through the full lifecycle:

```lisp
    (flet ((run-handler ()
             (let ((result (funcall (tool-handler tool) arguments)))
               (setf (context-end-time context) (get-internal-real-time))
               (setf (context-result context) result)
               (invoke-tool-hook :on-complete tool call arguments result)
               (when registry
                 (invoke-global-hooks registry :on-complete call arguments result))
               result)))
      (handler-bind
          ((error (lambda (e)
                    (setf (context-end-time context) (get-internal-real-time))
                    (setf (context-error context) e)
                    (invoke-tool-hook :on-error tool call arguments e)
                    (when registry
                      (invoke-global-hooks registry :on-error call arguments e)))))
        (restart-case
            (run-handler)
          (use-error-result ()
            :report "Return error description as tool result"
            (format nil "Error executing ~A: ~A" (tool-name tool)
                    (context-error context)))
          (retry-execution ()
            :report "Retry executing the tool handler"
            (run-handler))
          (use-value (v)
            :report "Supply a result value"
            :interactive (lambda ()
                           (format *query-io* "Enter result value (literal): ")
                           (finish-output *query-io*)
                           (let ((*read-eval* nil))
                             (list (read *query-io*))))
            v))))
```

- [ ] **Step 4: Run tests** — `tests/test-tools-enhanced.lisp`, `tests/test-tools-integration.lisp`, `tests/test-tools-support.lisp`.

- [ ] **Step 5: Commit**

```bash
git add src/conditions.lisp src/package.lisp src/tools/registry.lisp src/tools/categories.lisp src/tools/validators.lisp src/tools/execution.lisp tests/test-tools-enhanced.lisp
git commit -m "fix: typed tool conditions; approval/safety rejections propagate; retry fires hooks"
```

---

### Task 15: Deduplicate tool-schema translation

`src/providers/anthropic.lisp:42-88` duplicates the parameter→JSON-Schema conversion from `src/protocol.lisp:186-233` (~120 lines total); only the envelope differs.

**Files:**
- Modify: `src/protocol.lisp:179-247`, `src/providers/anthropic.lisp:29-95`
- Test: existing tests in `tests/test-tools-support.lisp` are the safety net (translation behavior must not change)

- [ ] **Step 1: Run baseline** — `sbcl --noinform --non-interactive --load tests/test-tools-support.lisp` all green (record count).

- [ ] **Step 2: Extract** into protocol.lisp (before `translate-tool-to-provider`):

```lisp
(defun parameter-specs-to-json-schema (tool)
  "Convert TOOL's parameter specs into a JSON Schema hash-table (type \"object\").
Shared by all provider tool translations; only the envelope differs per provider."
  (let ((parameters (make-hash-table :test 'equal)))
    (setf (gethash "type" parameters) "object")
    (setf (gethash "properties" parameters) (make-hash-table :test 'equal))
    (dolist (param (tool-parameters tool))
      <move the existing dolist body from translate-tool-to-provider here verbatim,
       writing into PARAMETERS>)
    (when (tool-required-params tool)
      (setf (gethash "required" parameters) (tool-required-params tool)))
    parameters))
```

Default `translate-tool-to-provider` becomes:

```lisp
(defmethod translate-tool-to-provider ((provider llm-provider) (tool tool-definition))
  "Default implementation: OpenAI function-tool format."
  (let ((result (make-hash-table :test 'equal))
        (function (make-hash-table :test 'equal)))
    (setf (gethash "type" result) "function")
    (setf (gethash "name" function) (tool-name tool))
    (setf (gethash "description" function) (tool-description tool))
    (setf (gethash "parameters" function) (parameter-specs-to-json-schema tool))
    (setf (gethash "function" result) function)
    result))
```

Anthropic method becomes:

```lisp
(defmethod translate-tool-to-provider ((provider anthropic-provider) (tool tool-definition))
  "Anthropic tool format: name/description/input_schema envelope."
  (let ((result (make-hash-table :test 'equal)))
    (setf (gethash "name" result) (tool-name tool))
    (setf (gethash "description" result) (tool-description tool))
    (setf (gethash "input_schema" result) (parameter-specs-to-json-schema tool))
    result))
```

- [ ] **Step 3: Run tests** — test-tools-support.lisp, test-tools-integration.lisp: identical pass counts to baseline.

- [ ] **Step 4: Commit**

```bash
git add src/protocol.lisp src/providers/anthropic.lisp
git commit -m "refactor: extract shared parameter-specs-to-json-schema (removes ~120 duplicated lines)"
```

---

### Task 16: Documentation and small-hygiene sweep

All info/style items in one pass. No behavior changes except typed warnings.

**Files:**
- Modify: `src/protocol.lisp`, `src/api.lisp`, `src/config.lisp`, `src/tokenizer.lisp`, `src/observability.lisp`, `src/model-registry.lisp`, `src/types.lisp`, `src/recovery.lisp`

- [ ] **Step 1: Apply these exact edits:**

1. `src/protocol.lisp:126` — provider-type docstring: add `:gemini` to the enumerated list.
2. `src/protocol.lisp` extract-error-message — rename the `error` binding to `err`; move the `;; Anthropic format` comment from above the `"detail"` lookup to above the first `"error"` lookup, and label `"detail"` as `;; FastAPI/vLLM format`.
3. `src/api.lisp:109-112` — add the missing `))` closing the multi-turn example in `complete`'s docstring.
4. `src/api.lisp:381` — `(car (stream-chunks stream))` → `(first (stream-chunks stream))`.
5. `src/config.lisp:15,20` — `defvar` → `defparameter` for `*default-max-tokens*`, `*default-temperature*`.
6. `src/tokenizer.lisp:11,16` — same for `*chars-per-token-estimate*`, `*message-overhead-tokens*`; `count-tokens` docstring gains: "MODEL and PROVIDER are currently ignored (heuristic estimate only)."
7. `src/observability.lisp` `make-logging-hooks` docstring: ":warn currently behaves identically to :info."
8. `src/observability.lisp:79` invoke-hooks and `src/types.lisp` `%parse-tool-arguments` — `(warn "...")` → `(warn 'llm-provider-warning :message (format nil <same>))`.
9. `src/model-registry.lisp:11-18` — add `:supports-audio` and `:output-dimensions` to the documented schema keys.
10. `src/recovery.lisp` make-retry-handler docstring — already amended in Task 5; verify present.
11. `src/tools/hooks.lisp` positional `:on-error` parsing — DEFERRED (internal helper, low risk); add `;; TODO: accept :on-error via explicit &key` comment at the lambda list.

- [ ] **Step 2: Validate + full test sweep** — every `tests/test-*.lisp` file via sbcl; all green.

- [ ] **Step 3: Commit**

```bash
git add src/protocol.lisp src/api.lisp src/config.lisp src/tokenizer.lisp src/observability.lisp src/model-registry.lisp src/types.lisp src/tools/hooks.lisp
git commit -m "docs: fix docstrings, typed warnings, defparameter for config knobs"
```

---

### Task 17: Packaging — .asd hygiene and telos shim (Option A; see decision note)

`:telos` is not in Quicklisp: nobody can load this library. The `cl-llm-provider-asd` package idiom is deprecated. No `:homepage`/`:source-control` metadata.

**Files:**
- Create: `src/telos-shim.lisp`
- Modify: `cl-llm-provider.asd`
- Test: fresh-load verification (Step 4)

The shim must be FUNCTIONAL, not no-op: `tests/test-conditions-restarts.lisp:781-812`
(Section 6) asserts `(telos:list-features)` contains all 9 feature names and
`(telos:get-intent sym)` is non-nil for annotated symbols. So the shim records
intents/features into simple registries.

Complete telos-symbol inventory used by this codebase (verify with
`grep -rhoE 'telos:[a-z-]+|\((defun/i|defmacro/i|define-condition/i|defintent|deffeature)' src/ tests/`):
`defun/i`, `define-condition/i`, `defintent`, `deffeature`, `telos:get-intent`,
`telos:list-features`. If the grep surfaces more, add them to the shim the same way.

- [ ] **Step 1: Create `src/telos-shim.lisp`:**

```lisp
;;; ABOUTME: Functional shim for the telos intent-annotation system.
;;; Loaded only when the real telos system is absent, so the library
;;; works from Quicklisp without telos. When telos is loaded first,
;;; its package already exists and this file is inert.
;;; The shim RECORDS intents and features (get-intent / list-features work);
;;; it omits telos's richer queries and tooling.

(in-package :cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package :telos)
    (defpackage :telos
      (:use :cl)
      (:export #:defun/i #:define-condition/i #:defintent #:deffeature
               #:get-intent #:list-features))
    (pushnew :telos-shim *features*)))

#+telos-shim
(in-package :telos)

#+telos-shim
(progn

(defvar *intents* (make-hash-table :test 'eq)
  "symbol -> intent plist recorded by defun/i, define-condition/i, defintent.")

(defvar *feature-names* '()
  "Feature symbols recorded by deffeature, oldest first.")

(defun get-intent (symbol)
  "Return the recorded intent plist for SYMBOL, or NIL."
  (gethash symbol *intents*))

(defun list-features ()
  "Return the list of feature symbols recorded by deffeature."
  (reverse *feature-names*))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun split-intent-clauses (body)
    "Split BODY into (values intent-plist clean-body): leading
(:feature ...) / (:purpose ...) style clauses are collected, a leading
docstring is preserved in the clean body."
    (let ((doc nil)
          (intent '()))
      (when (and (stringp (first body)) (rest body))
        (setf doc (pop body)))
      (loop while (and (consp (first body))
                       (keywordp (first (first body))))
            do (let ((clause (pop body)))
                 (setf intent
                       (append intent (list (first clause)
                                            (if (rest (rest clause))
                                                (rest clause)
                                                (second clause)))))))
      (values intent (if doc (cons doc body) body)))))

(defmacro defun/i (name lambda-list &body body)
  (multiple-value-bind (intent clean-body) (split-intent-clauses body)
    `(progn
       (setf (gethash ',name *intents*) ',intent)
       (defun ,name ,lambda-list ,@clean-body))))

(defmacro define-condition/i (name supers slots &rest options)
  (let ((intent (loop for opt in options
                      when (and (consp opt)
                                (member (first opt) '(:feature :purpose)))
                      append (list (first opt) (second opt))))
        (clean (remove-if (lambda (opt)
                            (and (consp opt)
                                 (member (first opt) '(:feature :purpose))))
                          options)))
    `(progn
       (setf (gethash ',name *intents*) ',intent)
       (define-condition ,name ,supers ,slots ,@clean))))

(defmacro defintent (name &rest args)
  `(progn
     (setf (gethash ',name *intents*) ',args)
     ',name))

(defmacro deffeature (name &rest args)
  (declare (ignore args))
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (pushnew ',name *feature-names*)
     ',name))

) ; end #+telos-shim progn
```

Note on `defintent`: annotated names may be macros or conditions, not just
functions (e.g. `(defintent with-auto-recovery ...)`) — the shim keys the
registry by symbol, matching how the tests query it
(`(telos:get-intent 'cl-llm-provider:complete)`).

- [ ] **Step 2: Rewrite `cl-llm-provider.asd` header and system:**

Delete lines 7-10 (the `cl-llm-provider-asd` defpackage/in-package). Update the defsystem:

```lisp
(defsystem "cl-llm-provider"
  :version "0.1.0"
  :author "quasi / quasiLabs"
  :license "MIT"
  :homepage "https://github.com/quasi/cl-llm-provider"
  :source-control (:git "https://github.com/quasi/cl-llm-provider.git")
  :bug-tracker "https://github.com/quasi/cl-llm-provider/issues"
  :description "Unified Common Lisp interface for multiple LLM provider APIs (Anthropic, OpenAI, Gemini, Ollama, OpenRouter)"
  :depends-on (:alexandria
               :serapeum
               :dexador
               :yason
               :bordeaux-threads
               :cl-ppcre
               :uiop)
  :components ((:module "src"
                :components
                ((:file "telos-shim")
                 (:file "package" :depends-on ("telos-shim"))
                 ...rest unchanged, every direct dependency on "package" implicitly
                 gains telos-shim through it...
```
(`:telos` removed from `:depends-on`; devs wanting real intent tracking `(ql:quickload :telos)` first — document this in README's development section. `tests/test-harness.lisp` gets `"src/telos-shim.lisp"` prepended to its `:load` list.)

- [ ] **Step 3: Also update `src/tools/package.lisp`** — its `(:import-from :telos #:defun/i #:defintent)` works unchanged against the shim package. No edit needed; verify only.

- [ ] **Step 4: Verification — fresh load without telos:**

```bash
sbcl --noinform --non-interactive \
  --eval '(push #p"/Users/quasi/quasilabs/projects/cl-llm-provider/" asdf:*local-source-registry-directories*)' \
  --eval '(when (asdf:find-system "telos" nil) (format t "telos visible - test with it hidden too~%"))' \
  --eval '(asdf:load-system "cl-llm-provider")' \
  --eval '(format t "LOADED OK~%")'
```
Expected: `LOADED OK`. Then run the full test sweep (all `tests/test-*.lisp`) — pay particular attention to `tests/test-conditions-restarts.lisp` Section 6 (telos integration): `telos-features-exist`, `telos-intent-on-complete`, `telos-intent-on-conditions`, `telos-intent-on-recovery` must pass against the SHIM (they exercise `get-intent`/`list-features`).

- [ ] **Step 5: Commit**

```bash
git add cl-llm-provider.asd src/telos-shim.lisp tests/test-harness.lisp
git commit -m "feat: telos shim + asd metadata; library loads without telos (release unblocker)"
```

---

### Task 18: Final verification and spec/docs sync

**Files:**
- Modify (as needed): `README.md`, `.claude/skills/integration/references/core-spec.md`, `.claude/skills/dev/SKILL.md`, `canonical-specification/`

- [ ] **Step 1: Full suite** — run every `tests/test-*.lisp` file; also `sbcl --non-interactive --eval '(asdf:test-system "cl-llm-provider")'`. All green.
- [ ] **Step 2: test-strategy-validator** — dispatch the `test-strategy-validator` agent over the suite (CLAUDE.md "before declaring complete" rule).
- [ ] **Step 3: Docs sync** — grep README and integration references for: `make-tool-result` (`:is-error` now omitted when nil), message shapes (Anthropic assistant messages now carry `:content` blocks), `use-fallback-provider` (now at API level), new exports (`translate-message-to-provider`, `stream-tool-calls`, `provider-http-post`, `default-config-file-path`, `tool-registration-error`). Update `canonical-specification/` entries touching R005/INV-003 if they describe the old message shapes. Run the `nitpicker` agent over updated docs.
- [ ] **Step 4: Downstream check** — note for Baba: `ghost` and `agent-q` consume this library; the Anthropic `response-message` shape changed (CLOS tool-calls → content-block plists). Grep both projects for `response-message` usage before merging.
- [ ] **Step 5: Final cobra-lisp-reviewer pass over the whole branch diff, then merge per `superpowers:finishing-a-development-branch`.**

---

## Explicitly Deferred (with rationale)

- **Ollama NDJSON streaming implementation** — new feature, not a fix; capability now honestly reports nil (Task 13).
- **Cross-provider message translation** (feed an OpenAI-shaped assistant message to Anthropic mid-conversation) — needs a design discussion about canonical message schema; same-provider round-trips are the contract this plan establishes.
- **`read-stream-chunk` timeout implementation** — documented no-op (Task 12); needs non-blocking reads per platform.
- **hooks.lisp positional :on-error** — internal helper, TODO comment added (Task 16).
- **Streaming socket leak** — refuted finding; `stream-closed-p` covers `:error` state, no fix needed.

## Codex Review Incorporated (2026-07-08)

An independent Codex review of this plan found 7 issues; all were verified against source and fixed in place:

1. **Telos shim was incomplete (Critical)** — tests call `telos:get-intent` and `telos:list-features` (test-conditions-restarts.lisp:783,792,800,809) and assert non-nil results. Task 17's shim is now FUNCTIONAL (records intents/features in registries) and exports both query functions.
2. **Approval callbacks unexported (Critical)** — `make-interactive-approval-callback` etc. are internal; Task 9 gained Step 0 exporting all four callback constructors from `src/tools/package.lisp`.
3. **Task 6 test used invalid `find-method` eql-specializer stubbing (High)** — rewritten with top-level test-double provider classes (`failing-test-provider`/`working-test-provider` inheriting `openai-provider`); no method cleanup needed.
4. **Task 5 broke two existing tests silently (High)** — `restart-handle-http-error-429`/`-generic` assert `use-fallback-provider` membership (lines ~475, ~500); Task 5 Step 3a now updates them explicitly.
5. **Anthropic coalescing didn't guarantee alternation (High)** — `%anthropic-wire-messages` now runs `%merge-consecutive-user-turns` (merges ANY adjacent user-role wire messages, promoting string content to text blocks); new test covers tool-result-then-user-text.
6. **`provider-http-post` export missing (Medium)** — `src/package.lisp` added to Task 5's files, export step and commit updated.
7. **Task 2 test asserted `"tool-use"` instead of `"tool_use"` (Medium)** — fixed; the contradictory note removed.

## Self-Review Notes

- Every error-severity finding from both review reports maps to a task (1-14, 17); warning-severity to tasks 3-16; info/style to task 16 or the deferred list.
- Type consistency: `translate-message-to-provider` (Tasks 4, 18), `%lisp-to-json-value` (Task 1, used implicitly by all later serialization), `provider-http-post` (Task 5, consumed by all providers), `%resolve-provider`/`%coerce-provider` (Task 6), `stream-tool-calls`/`stream-tool-call-parts` (Task 12) — names used consistently across tasks.
- Branching: this is >10 files — per CLAUDE.md, work happens on a branch (`git checkout -b review-fixes` before Task 1) and Baba has implicitly approved scope by commissioning the plan.
