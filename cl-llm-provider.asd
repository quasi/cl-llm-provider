#|
  cl-llm-provider - Unified Common Lisp interface for LLM provider APIs

  Author: quasi / quasiLabs
|#

(in-package :cl-user)
(defpackage cl-llm-provider-asd
  (:use :cl :asdf :uiop))
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
               :uiop
               :telos)
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "features" :depends-on ("package"))
                 (:file "conditions" :depends-on ("package" "features"))
                 (:file "types" :depends-on ("package"))
                 (:file "observability" :depends-on ("types"))
                 (:file "config" :depends-on ("package" "conditions"))
                 (:file "protocol" :depends-on ("package" "types" "conditions"))
                 (:file "streaming" :depends-on ("package" "types" "protocol"))
                 (:file "model-registry" :depends-on ("package" "protocol"))
                 (:file "tokenizer" :depends-on ("types"))
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
                   (:file "openai-compatible")
                   (:file "gemini")))
                 (:file "api" :depends-on ("package" "types" "conditions" "protocol" "config" "tools" "providers"))
                (:file "recovery" :depends-on ("package" "features" "conditions" "config")))))
  :in-order-to ((test-op (test-op "cl-llm-provider/test"))))

(defsystem "cl-llm-provider/test"
  :author "quasi / quasiLabs"
  :license "MIT"
  :depends-on ("cl-llm-provider"
               "fiveam"
               "cl-test-hardening/harness"
               "cl-test-hardening/fixture"
               "cl-test-hardening/property"
               "cl-test-hardening/generators"
               "cl-test-hardening/contract"
               "cl-test-hardening/mutation"
               "cl-test-hardening/operators")
  :components ((:module "tests"
                :components
                ((:file "test-harness")
                 (:file "test-fixtures" :depends-on ("test-harness"))
                 (:file "generators" :depends-on ("test-harness"))
                 (:file "test-properties" :depends-on ("test-harness" "generators"))
                 (:file "test-contracts" :depends-on ("test-harness"))
                 (:file "test-mutations" :depends-on ("test-harness"))
                 (:file "test-gemini-provider" :depends-on ("test-harness"))
                 (:file "test-integration-full-flow" :depends-on ("test-harness"))
                 (:file "test-observability" :depends-on ("test-harness"))
                 (:file "test-provider-introspection" :depends-on ("test-harness"))
                 (:file "test-provider-protocols" :depends-on ("test-harness"))
                 (:file "test-request-response-handling" :depends-on ("test-harness"))
                 (:file "test-streaming" :depends-on ("test-harness"))
                 (:file "test-token-metadata-comprehensive" :depends-on ("test-harness"))
                 ;; test-token-metadata-functional is a standalone script (not FiveAM)
                 ;; Run it directly: sbcl --load tests/test-token-metadata-functional.lisp
                 (:file "test-tokenizer" :depends-on ("test-harness"))
                 (:file "test-tools-enhanced" :depends-on ("test-harness"))
                 (:file "test-tools-integration" :depends-on ("test-harness"))
                 (:file "test-tools-support" :depends-on ("test-harness")))))
  :perform (test-op (o c)
             (symbol-call :fiveam :run!
                          (find-symbol* :cl-llm-provider-suite :cl-llm-provider/test))))
