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

;;; Run tests
(format t "~%~%Running observability tests...~%")
(fiveam:run! 'observability-suite)
