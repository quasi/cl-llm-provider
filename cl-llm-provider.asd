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
                 (:file "streaming" :depends-on ("package" "types" "protocol"))
                 (:file "model-registry" :depends-on ("package" "protocol"))
                 (:file "tools" :depends-on ("package" "types" "conditions"))
                 ;; Enhanced tools module (registry, validators, approval, hooks, execution)
                 (:module "tools-enhanced"
                  :pathname "tools"
                  :depends-on ("package" "types" "conditions" "tools")
                  :components
                  ((:file "package")
                   (:file "categories" :depends-on ("package"))
                   (:file "validators" :depends-on ("package" "categories"))
                   (:file "registry" :depends-on ("package" "categories" "validators"))
                   (:file "approval" :depends-on ("package" "categories" "registry"))
                   (:file "hooks" :depends-on ("package"))
                   (:file "execution" :depends-on ("package" "categories" "validators" "registry" "approval" "hooks"))))
                 (:module "providers"
                  :depends-on ("package" "types" "conditions" "protocol" "model-registry" "tools")
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
