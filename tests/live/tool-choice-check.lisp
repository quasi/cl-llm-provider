;;;; Live wire-compatibility check: named (string) tool_choice.
;;;;
;;;; NOT part of the ASDF test-op. It hits real provider endpoints and spends
;;;; real tokens, so it must never run unattended in CI. Run it by hand when
;;;; touching request serialization, or when a provider changes its API.
;;;;
;;;; What it proves that the unit tests cannot:
;;;;   The unit tests in tests/test-request-response-handling.lisp stub out
;;;;   PROVIDER-HTTP-POST and assert on the JSON we emit. They confirm the
;;;;   shape we intend to send -- they cannot confirm the provider accepts it.
;;;;   This script closes that gap by forcing a real tool call.
;;;;
;;;; Background: a string tool-choice must serialize as a structured object.
;;;; A bare string is rejected:
;;;;   400 Invalid value: 'extract'. Supported values are: 'none', 'auto',
;;;;   and 'required'.
;;;;
;;;; Usage (note --load, not --script, so ~/.sbclrc loads quicklisp):
;;;;   LIVE_PROVIDER=openai     LIVE_MODEL=gpt-4o-mini \
;;;;     sbcl --non-interactive --load tests/live/tool-choice-check.lisp
;;;;   LIVE_PROVIDER=gemini     LIVE_MODEL=gemini-3-flash-preview ...
;;;;   LIVE_PROVIDER=openrouter LIVE_MODEL=openai/gpt-4o-mini ...
;;;;     (OpenRouter needs a namespaced slug, not a bare model name.)
;;;;
;;;; Keys come from ~/.config/cl-llm-provider/config.lisp (which sets the
;;;; provider env vars) or from the environment directly. A missing key
;;;; surfaces as "Provider configuration error: missing <VAR>" -- that is a
;;;; config miss, NOT a serialization failure. Read the FAIL text before
;;;; concluding anything about the code.
;;;;
;;;; Verified passing 2026-08-01 on openai, gemini, and openrouter.

(ql:quickload :cl-llm-provider :silent t)

(in-package :cl-llm-provider)

(load-configuration-from-file)

(let* ((type (intern (string-upcase (or (uiop:getenv "LIVE_PROVIDER") "openai"))
                     :keyword))
       (model (or (uiop:getenv "LIVE_MODEL") "gpt-4o-mini"))
       (tool (make-instance 'tool-definition
                            :name "extract"
                            :description "Extract a person's name."
                            :parameters '((:name "name" :type :string
                                           :description "The person's name"))
                            :required '("name"))))
  (format t "~&Live check: ~A / ~A~%" type model)
  (handler-case
      (let* ((provider (make-provider type :model model))
             (raw (send-completion-request
                   provider
                   '((:role "user" :content "Ada Lovelace wrote the first program."))
                   :model model
                   :max-tokens 100
                   :tools (list tool)
                   ;; The whole point: a NAMED (string) tool choice.
                   :tool-choice "extract"))
             (response (parse-completion-response provider raw)))
        (format t "~&PASS ~A: tool-calls=~S~%" type (response-tool-calls response)))
    (error (e)
      (format t "~&FAIL ~A: ~A~%" type e)
      (uiop:quit 1))))
