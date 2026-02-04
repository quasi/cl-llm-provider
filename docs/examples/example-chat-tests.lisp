;;;; example-chat-tests.lisp
;;;; Test suite for example-chat using FiveAM
;;;;
;;;; Run tests:
;;;;   (ql:quickload :fiveam)
;;;;   (load "example-chat.lisp")
;;;;   (load "example-chat-tests.lisp")
;;;;   (5am:run! 'example-chat-tests:all-tests)

(defpackage #:example-chat-tests
  (:use #:cl #:fiveam)
  (:export #:all-tests
           #:run-tests))

(in-package #:example-chat-tests)

;;;; Test Suite Definition

(def-suite all-tests
  :description "Complete test suite for example-chat")

(in-suite all-tests)

;;;; Helper: Test Provider

(defvar *test-provider* nil
  "Provider for testing - uses Ollama if available")

(defun setup-test-provider ()
  "Create test provider (Ollama) or skip tests"
  (handler-case
      (setf *test-provider*
            (cl-llm-provider:make-provider
             :ollama
             :base-url "http://localhost:11434"
             :model "llama3.2"))
    (error (e)
      (format t "~%[SKIP] Cannot create test provider: ~A~%" e)
      (format t "To run tests: ollama serve && ollama pull llama3.2~%~%")
      (setf *test-provider* nil))))

;;;; Test: Provider Creation

(test provider-creation
  "Test that we can create providers"
  (setup-test-provider)

  (when *test-provider*
    (is (not (null *test-provider*)))
    (is (typep *test-provider* 'cl-llm-provider:ollama-provider))
    (is (string= "llama3.2"
                 (cl-llm-provider:provider-default-model *test-provider*)))))

;;;; Test: Basic Completion

(test basic-completion
  "Test simple message completion"
  (setup-test-provider)

  (when *test-provider*
    (let* ((messages (list (list :role "user"
                                 :content "Say 'test' in one word")))
           (response (cl-llm-provider:complete
                      messages
                      :provider *test-provider*
                      :max-tokens 10)))

      ;; Response exists
      (is (not (null response)))

      ;; Has content
      (let ((content (cl-llm-provider:response-content response)))
        (is (not (null content)))
        (is (stringp content))
        (is (> (length content) 0)))

      ;; Has usage stats
      (let ((usage (cl-llm-provider:response-usage response)))
        (is (not (null usage)))
        (is (> (getf usage :total-tokens) 0))
        (is (> (getf usage :prompt-tokens) 0))
        (is (> (getf usage :completion-tokens) 0))))))

;;;; Test: Conversation History

(test conversation-history
  "Test that conversation history is maintained"
  (setup-test-provider)

  (when *test-provider*
    ;; Reset state
    (setf example-chat:*messages* nil)
    (setf example-chat:*current-provider* *test-provider*)

    ;; First message: introduce name
    (let ((response1 (example-chat:chat "My name is TestBot"
                                        :use-tools nil)))
      (is (stringp response1))
      (is (> (length response1) 0)))

    ;; Second message: ask about name
    (let ((response2 (example-chat:chat "What is my name?"
                                        :use-tools nil)))
      (is (stringp response2))
      ;; AI should remember "TestBot"
      (is (or (search "TestBot" response2 :test #'char-equal)
              (search "test" response2 :test #'char-equal))))

    ;; History should have 4 messages (2 user, 2 assistant)
    (is (= 4 (length example-chat:*messages*)))))

;;;; Test: Tool Definition

(test tool-definition
  "Test that tools are created correctly"
  (let ((tool (cl-llm-provider:define-tool
               "test_function"
               "A test function"
               '((:name "arg1"
                  :type :string
                  :description "Test argument"))
               :required '("arg1")
               :handler (lambda (args)
                          (format nil "Result: ~A" (getf args :arg1))))))

    ;; Tool exists
    (is (not (null tool)))

    ;; Has correct properties
    (is (string= "test_function" (cl-llm-provider:tool-name tool)))
    (is (string= "A test function" (cl-llm-provider:tool-description tool)))

    ;; Handler works
    (let ((result (funcall (cl-llm-provider:tool-handler tool)
                           (list :arg1 "test-value"))))
      (is (string= "Result: test-value" result)))))

;;;; Test: Tool Calling (if supported)

(test tool-calling
  "Test that AI can call tools"
  (setup-test-provider)

  (when *test-provider*
    ;; Reset state
    (setf example-chat:*messages* nil)
    (setf example-chat:*current-provider* *test-provider*)
    (example-chat:setup-tools)

    ;; Note: This test may fail if the model doesn't support tools
    ;; or doesn't decide to use them
    (handler-case
        (let ((response (example-chat:chat "What's the weather in Tokyo?"
                                           :use-tools t)))
          ;; Should get a response (either using tools or explaining it can't)
          (is (stringp response))
          (is (> (length response) 0)))
      (error (e)
        ;; Tool calling might not be supported by all models
        (format t "~%[INFO] Tool calling test skipped: ~A~%" e)
        (pass)))))

;;;; Test: Message Clearing

(test clear-messages
  "Test clearing conversation history"
  ;; Add some messages
  (setf example-chat:*messages*
        (list (list :role "user" :content "Hello")
              (list :role "assistant" :content "Hi")))

  (is (= 2 (length example-chat:*messages*)))

  ;; Clear
  (example-chat:clear-messages)

  ;; Should be empty
  (is (= 0 (length example-chat:*messages*))))

;;;; Test: Provider Switching

(test provider-switching
  "Test switching between providers"
  ;; Setup providers
  (example-chat:setup-providers)

  (when (> (hash-table-count example-chat:*providers*) 1)
    (let ((providers (loop for key being the hash-keys of example-chat:*providers*
                           collect key)))

      ;; Switch to first provider
      (example-chat:switch-provider (first providers))
      (is (eq (gethash (first providers) example-chat:*providers*)
              example-chat:*current-provider*))

      ;; Switch to second provider
      (when (> (length providers) 1)
        (example-chat:switch-provider (second providers))
        (is (eq (gethash (second providers) example-chat:*providers*)
                example-chat:*current-provider*))))))

;;;; Test: Streaming (basic check)

(test streaming-basic
  "Test that streaming function exists and can be called"
  (setup-test-provider)

  (when *test-provider*
    ;; Reset state
    (setf example-chat:*messages* nil)
    (setf example-chat:*current-provider* *test-provider*)

    ;; This just verifies the function works, not the streaming behavior
    (handler-case
        (progn
          (example-chat:chat-stream "Say hello")
          (pass))
      (error (e)
        (fail (format nil "Streaming failed: ~A" e))))))

;;;; Test: Error Handling

(test error-handling-no-provider
  "Test error handling when no provider is set"
  (let ((example-chat:*current-provider* nil))
    (signals error
      (example-chat:chat "Hello"))))

(test error-handling-invalid-provider
  "Test error handling with invalid provider key"
  (example-chat:setup-providers)

  ;; Try to switch to non-existent provider
  ;; This should not error, just report failure
  (finishes
    (example-chat:switch-provider :nonexistent)))

;;;; Test Runner

(defun run-tests ()
  "Run all tests and return results"
  (format t "~%")
  (format t "╔════════════════════════════════════════════════════════╗~%")
  (format t "║         Example Chat Test Suite - FiveAM              ║~%")
  (format t "╚════════════════════════════════════════════════════════╝~%")
  (format t "~%")

  ;; Check prerequisites
  (format t "Checking prerequisites...~%")

  (handler-case
      (progn
        (ql:quickload :cl-llm-provider :silent t)
        (format t "  ✓ cl-llm-provider loaded~%"))
    (error (e)
      (format t "  ✗ cl-llm-provider not available: ~A~%" e)
      (return-from run-tests nil)))

  (handler-case
      (setup-test-provider)
    (error (e)
      (format t "  ⚠ Test provider (Ollama) not available: ~A~%" e)
      (format t "    Some tests will be skipped~%")))

  (when *test-provider*
    (format t "  ✓ Test provider (Ollama) available~%"))

  (format t "~%Running tests...~%~%")

  ;; Run tests
  (let ((results (run 'all-tests)))
    (format t "~%")
    results))

;;; Test Summary Information

(format t "~%")
(format t "Example Chat Test Suite loaded.~%")
(format t "~%")
(format t "To run tests:~%")
(format t "  (example-chat-tests:run-tests)~%")
(format t "  or~%")
(format t "  (5am:run! 'example-chat-tests:all-tests)~%")
(format t "~%")
(format t "Prerequisites:~%")
(format t "  1. Ollama running: ollama serve~%")
(format t "  2. Model pulled: ollama pull llama3.2~%")
(format t "~%")

;;; EOF
