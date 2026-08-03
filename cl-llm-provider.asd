#|
  cl-llm-provider - Unified Common Lisp interface for LLM provider APIs

  Author: quasi / quasiLabs
|#

(asdf:defsystem "cl-llm-provider"
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
                ((:file "intent")
                 (:file "package" :depends-on ("intent"))
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

;;; Optional telos integration.
;;;
;;; cl-llm-provider proper records its annotations in its own package and never
;;; touches telos, so its fasls are valid in any image regardless of load order.
;;; Load THIS system to additionally publish those annotations into a real telos.
;;; The dependency is declared, so ASDF can invalidate on it — unlike the old
;;; telos-shim, which guessed at telos's presence from ambient state and produced
;;; fasls that only loaded in an image matching the one that built them.
;;; Load-order regression test.
;;;
;;; Deliberately NOT chained into cl-llm-provider/test's test-op: it spawns five
;;; cold SBCL builds and would turn a seconds-long feedback loop into a
;;; minutes-long one. Run it before releasing, or after touching src/intent.lisp
;;; or anything about how telos is reached:
;;;
;;;     (asdf:test-system "cl-llm-provider/load-order")   ; or tests/test-load-order.sh
(asdf:defsystem "cl-llm-provider/load-order"
  :author "quasi / quasiLabs"
  :license "MIT"
  :description "Fresh-image regression test for telos load-order independence"
  :perform (test-op (o c)
             (declare (ignore o c))
             (let* ((script (uiop:subpathname
                             (asdf:system-source-directory "cl-llm-provider")
                             "tests/test-load-order.sh"))
                    (exit (uiop:run-program (list "/bin/zsh" (namestring script))
                                            :output t :error-output t
                                            :ignore-error-status t)))
               (unless (zerop exit)
                 (error "Load-order regression test failed (exit ~a). ~
                         cl-llm-provider's fasls must load regardless of whether ~
                         telos was loaded first — see src/intent.lisp." exit)))))

;;; Everything, in one command.
;;;
;;; The fast suite and the load-order test have opposite economics — seconds in
;;; one image versus minutes across nine — so they are separate systems. This
;;; chains both, so "run all the tests" is one discoverable thing rather than a
;;; instruction someone has to remember:
;;;
;;;     (asdf:test-system "cl-llm-provider/test-all")
(asdf:defsystem "cl-llm-provider/test-all"
  :author "quasi / quasiLabs"
  :license "MIT"
  :description "Runs the FiveAM suite and the fresh-image load-order test"
  :in-order-to ((test-op (test-op "cl-llm-provider/test")
                         (test-op "cl-llm-provider/load-order"))))

(asdf:defsystem "cl-llm-provider/telos"
  :author "quasi / quasiLabs"
  :license "MIT"
  :description "Publishes cl-llm-provider's intent annotations into telos"
  :depends-on ("cl-llm-provider" "telos")
  :components ((:module "src"
                :components ((:file "telos-bridge")))))

(asdf:defsystem "cl-llm-provider/test"
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
                 (:file "test-tools-support" :depends-on ("test-harness"))
                 (:file "test-conditions-restarts" :depends-on ("test-harness")))))
  :perform (test-op (o c)
             (symbol-call :fiveam :run!
                          (find-symbol* :cl-llm-provider-suite :cl-llm-provider/test))))
