#|
  cl-llm-provider - Unified Common Lisp interface for LLM provider APIs

  Author: quasi / quasiLabs
|#

(in-package :cl-user)
(defpackage cl-llm-provider-asd
  (:use :cl :asdf))
(in-package :cl-llm-provider-asd)

(defsystem "cl-llm-provider"
  :version "0.1.0"
  :author "quasi / quasiLabs"
  :license "MIT"
  :description "Unified Common Lisp interface for multiple LLM provider APIs (Anthropic, OpenAI, Ollama, OpenRouter)"
  :depends-on (:alexandria
               :serapeum
               :dexador
               :yason
               :bordeaux-threads
               :cl-ppcre
               :uiop)
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "conditions" :depends-on ("package"))
                 (:file "types" :depends-on ("package"))
                 (:file "config" :depends-on ("package" "conditions"))
                 (:file "protocol" :depends-on ("package" "types" "conditions"))
                 (:file "tools" :depends-on ("package" "types" "conditions"))
                 (:module "providers"
                  :depends-on ("package" "types" "conditions" "protocol" "tools")
                  :components
                  ((:file "anthropic")
                   (:file "openai")
                   (:file "ollama")
                   (:file "openrouter")
                   (:file "openai-compatible")))
                 (:file "api" :depends-on ("package" "types" "conditions" "protocol" "config" "tools" "providers")))))
  :in-order-to ((test-op (test-op "cl-llm-provider/test"))))

(defsystem "cl-llm-provider/test"
  :author "quasi / quasiLabs"
  :license "MIT"
  :depends-on ("cl-llm-provider"
               "fiveam")
  :components ((:module "tests"
                :components
                ((:file "package")
                 (:file "test-tools" :depends-on ("package"))
                 (:file "test-providers" :depends-on ("package"))
                 (:file "test-integration" :depends-on ("package")))))
  :perform (test-op (o c)
             (symbol-call :fiveam :run!
                          (find-symbol* :cl-llm-provider-suite :cl-llm-provider/test))))
