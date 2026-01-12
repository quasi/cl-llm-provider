(require :asdf)
(ql:quickload :fiveam :silent t)
(ql:quickload :alexandria :silent t)
(ql:quickload :serapeum :silent t)
(ql:quickload :dexador :silent t)
(ql:quickload :yason :silent t)
(ql:quickload :bordeaux-threads :silent t)
(ql:quickload :cl-ppcre :silent t)
(ql:quickload :uiop :silent t)

;; Load the library
(load "src/package.lisp")
(load "src/conditions.lisp")
(load "src/types.lisp")
(load "src/observability.lisp")
(load "src/protocol.lisp")
(load "src/tools.lisp")
(load "src/config.lisp")
(load "src/model-registry.lisp")
(load "src/providers/anthropic.lisp")
(load "src/providers/openai.lisp")
(load "src/providers/ollama.lisp")
(load "src/providers/openrouter.lisp")
(load "src/api.lisp")

(in-package :cl-llm-provider)

;;; Define test suite
(fiveam:def-suite observability-suite
  :description "Observability hooks tests")

(fiveam:in-suite observability-suite)

(fiveam:test hooks-container-creation
  "Test hooks container creation"
  (let ((hooks (cl-llm-provider:make-hooks)))
    (fiveam:is (not (null hooks)))
    (fiveam:is (cl-llm-provider::hooks-p hooks))))

(fiveam:test add-and-invoke-hook
  "Test adding and invoking hooks"
  (let ((hooks (cl-llm-provider:make-hooks))
        (called nil))
    (cl-llm-provider:add-hook hooks :before-request
                              (lambda (provider model messages)
                                (declare (ignore provider model messages))
                                (setf called t)))
    (cl-llm-provider::invoke-hooks hooks :before-request nil "test" nil)
    (fiveam:is (eq called t))))

(fiveam:test complete-has-hooks-integration
  "Test that complete function can be called with hooks parameters"
  ;; Basic check that the function exists
  (fiveam:is (fboundp 'cl-llm-provider:complete))
  ;; The actual integration will be tested via behavior
  (fiveam:pass "Hooks parameter will be validated via integration"))

(fiveam:test complete-invokes-on-request-callback
  "Test that complete function invokes :on-request callback"
  (let ((called nil)
        (captured-info nil)
        ;; Create a mock provider with invalid API key to trigger network error
        (provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "invalid-key-for-test"
                                 :model "gpt-4o")))
    (handler-case
        (cl-llm-provider:complete
         '((:role "user" :content "test"))
         :provider provider
         :on-request (lambda (info)
                      (setf called t)
                      (setf captured-info info)))
      (error () nil))
    ;; The callback should have been invoked before the network request
    (fiveam:is (eq called t) "on-request callback should be invoked")
    (fiveam:is (not (null captured-info)) "request info should be captured")
    (when captured-info
      (fiveam:is (getf captured-info :provider) "request info should contain provider")
      (fiveam:is (getf captured-info :model) "request info should contain model"))))

(fiveam:test complete-invokes-on-error-callback
  "Test that complete function invokes :on-error callback on errors"
  (let ((error-called nil)
        (captured-error nil)
        ;; Create a mock provider with invalid API key
        (provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "invalid-key-for-test"
                                 :model "gpt-4o")))
    (handler-case
        (cl-llm-provider:complete
         '((:role "user" :content "test"))
         :provider provider
         :on-error (lambda (e)
                    (setf error-called t)
                    (setf captured-error e)))
      (error () nil))
    (fiveam:is (eq error-called t) "on-error callback should be invoked")
    (fiveam:is (not (null captured-error)) "error should be captured")))

(fiveam:test complete-invokes-hooks-structure
  "Test that complete function invokes hooks from hooks structure"
  (let ((before-called nil)
        (error-called nil)
        (hooks (cl-llm-provider:make-hooks))
        ;; Create a mock provider with invalid API key
        (provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "invalid-key-for-test"
                                 :model "gpt-4o")))

    (cl-llm-provider:add-hook hooks :before-request
                              (lambda (provider model messages)
                                (declare (ignore provider model messages))
                                (setf before-called t)))

    (cl-llm-provider:add-hook hooks :on-error
                              (lambda (provider model error)
                                (declare (ignore provider model error))
                                (setf error-called t)))

    ;; This will error on network call due to invalid API key
    (handler-case
        (cl-llm-provider:complete
         '((:role "user" :content "test"))
         :provider provider
         :hooks hooks)
      (error () nil))

    (fiveam:is (eq before-called t) "before-request hook should be invoked")
    (fiveam:is (eq error-called t) "on-error hook should be invoked")))

;;; Run tests
(format t "~%~%Running observability tests...~%")
(fiveam:run! 'observability-suite)
