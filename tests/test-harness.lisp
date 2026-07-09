;;; ABOUTME: Test harness definition for cl-llm-provider using cl-test-hardening
;;; Defines the harness configuration and top-level test suite.

(require :asdf)
(ql:quickload '(:cl-test-hardening/harness :fiveam) :silent t)

;;; Define test package with top-level suite

(defpackage :cl-llm-provider/test
  (:use :cl)
  (:export #:cl-llm-provider-suite))

(in-package :cl-llm-provider/test)

;;; Top-level suite — all per-file suites are children of this

(fiveam:def-suite cl-llm-provider-suite
  :description "Top-level suite for all cl-llm-provider tests")

;;; Harness definition — the superset of what all test files need

(th.harness:define-harness :cl-llm-provider
  :systems (:fiveam :alexandria :serapeum :dexador :yason
            :bordeaux-threads :cl-ppcre :uiop)
  :load ("src/telos-shim.lisp"
         "src/package.lisp"
         "src/features.lisp"
         "src/conditions.lisp"
         "src/types.lisp"
         "src/observability.lisp"
         "src/config.lisp"
         "src/protocol.lisp"
         "src/streaming.lisp"
         "src/model-registry.lisp"
         "src/tokenizer.lisp"
         "src/tools.lisp"
         "src/tools/package.lisp"
         "src/tools/categories.lisp"
         "src/tools/validators.lisp"
         "src/tools/registry.lisp"
         "src/tools/approval.lisp"
         "src/tools/hooks.lisp"
         "src/tools/execution.lisp"
         "src/providers/anthropic.lisp"
         "src/providers/openai.lisp"
         "src/providers/ollama.lisp"
         "src/providers/openrouter.lisp"
         "src/providers/openai-compatible.lisp"
         "src/providers/gemini.lisp"
         "src/api.lisp"
         "src/recovery.lisp")
  :package :cl-llm-provider)
