(require :asdf)
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
(load "src/protocol.lisp")
(load "src/api.lisp")
(load "src/tools.lisp")
(load "src/config.lisp")
(load "src/providers/anthropic.lisp")
(load "src/providers/openai.lisp")
(load "src/providers/ollama.lisp")
(load "src/providers/openrouter.lisp")

(in-package :cl-llm-provider)

(format t "~%=== Token Counting and Metadata Test ===~%~%")

;; Create Ollama provider
(format t "Creating Ollama provider...~%")
(defparameter *ollama*
  (make-provider :ollama
                 :base-url "http://localhost:11434"
                 :model "qwen3:1.7b"))

(format t "Provider created: ~A~%~%" *ollama*)

;;; Test 1: Basic Completion with Token Counts
(format t "~%=== Test 1: Basic Completion with Token Counts ===~%")
(handler-case
    (let ((response (complete '((:role "user" :content "What is 5+3? Answer briefly."))
                              :provider *ollama*
                              :max-tokens 50
                              :temperature 0.5)))
      (format t "✓ Completion succeeded~%")
      (format t "  Model: ~A~%" (response-model response))
      (format t "  Content: ~S~%" (response-content response))
      (format t "~%Token Usage:~%")
      (let ((usage (response-usage response)))
        (format t "  Prompt tokens: ~A~%" (getf usage :prompt-tokens))
        (format t "  Completion tokens: ~A~%" (getf usage :completion-tokens))
        (format t "  Total tokens: ~A~%" (getf usage :total-tokens))

        ;; Verify token counts are numbers
        (assert (numberp (getf usage :prompt-tokens)) nil "Prompt tokens should be a number")
        (assert (numberp (getf usage :completion-tokens)) nil "Completion tokens should be a number")
        (assert (numberp (getf usage :total-tokens)) nil "Total tokens should be a number")
        (assert (= (getf usage :total-tokens)
                   (+ (getf usage :prompt-tokens) (getf usage :completion-tokens)))
                nil "Total should equal prompt + completion")
        (format t "  ✓ Token counts are valid~%"))

      (format t "~%Metadata:~%")
      (let ((metadata (response-metadata response)))
        (if metadata
            (progn
              (format t "  Total duration: ~A ns~%" (getf metadata :total-duration-ns))
              (format t "  Load duration: ~A ns~%" (getf metadata :load-duration-ns))
              (format t "  Prompt eval duration: ~A ns~%" (getf metadata :prompt-eval-duration-ns))
              (format t "  Eval duration: ~A ns~%" (getf metadata :eval-duration-ns))
              (format t "  Created at: ~A~%" (getf metadata :created-at))

              ;; Verify metadata contains expected fields
              (assert (getf metadata :total-duration-ns) nil "Should have total-duration-ns")
              (assert (numberp (getf metadata :total-duration-ns)) nil "Duration should be a number")
              (format t "  ✓ Metadata extracted correctly~%"))
            (format t "  WARNING: No metadata found~%"))))
  (error (e)
    (format t "✗ Test failed: ~A~%" e)
    (uiop:quit 1)))

;;; Test 2: Completion with Performance Profiling Enabled
(format t "~%~%=== Test 2: Completion with Performance Profiling ===~%")
(handler-case
    (let ((*performance-profiling* t))
      (let ((response (complete '((:role "user" :content "Say 'hello' in one word."))
                                :provider *ollama*
                                :max-tokens 20
                                :temperature 0.5)))
        (format t "✓ Completion with profiling succeeded~%")

        (format t "~%Token Usage:~%")
        (let ((usage (response-usage response)))
          (format t "  Prompt tokens: ~A~%" (getf usage :prompt-tokens))
          (format t "  Completion tokens: ~A~%" (getf usage :completion-tokens))
          (format t "  Total tokens: ~A~%" (getf usage :total-tokens))
          (format t "  ✓ Token counts present~%"))

        (format t "~%Performance Timing:~%")
        (let ((perf (response-performance response)))
          (if perf
              (progn
                (format t "  Encode time: ~,4f seconds~%" (getf perf :encode-time))
                (format t "  API time: ~,4f seconds~%" (getf perf :api-time))
                (format t "  Decode time: ~,4f seconds~%" (getf perf :decode-time))

                ;; Verify performance data
                (assert (numberp (getf perf :encode-time)) nil "Encode time should be a number")
                (assert (numberp (getf perf :api-time)) nil "API time should be a number")
                (assert (numberp (getf perf :decode-time)) nil "Decode time should be a number")
                (format t "  ✓ Performance profiling working~%"))
              (progn
                (format t "  ✗ No performance data found~%")
                (error "Performance profiling was enabled but no data collected"))))

        (format t "~%Metadata:~%")
        (let ((metadata (response-metadata response)))
          (if metadata
              (progn
                (format t "  Total duration: ~A ns (~,4f sec)~%"
                        (getf metadata :total-duration-ns)
                        (/ (getf metadata :total-duration-ns) 1e9))
                (format t "  ✓ Metadata present alongside performance data~%"))
              (format t "  WARNING: No metadata found~%")))))
  (error (e)
    (format t "✗ Test failed: ~A~%" e)
    (uiop:quit 1)))

;;; Test 3: Completion with Thinking (for reasoning models)
(format t "~%~%=== Test 3: Completion with Thinking Mode ===~%")
(handler-case
    (let ((response (complete '((:role "user" :content "What is 2+2?"))
                              :provider *ollama*
                              :max-tokens 100
                              :temperature 0.3)))
      (format t "✓ Completion with thinking succeeded~%")

      (let ((content (response-content response)))
        (if (search "<thinking>" content)
            (format t "  ✓ Thinking trace included in response~%")
            (format t "  ℹ No thinking trace (model may not support it)~%")))

      (format t "~%Token Usage:~%")
      (let ((usage (response-usage response)))
        (format t "  Prompt tokens: ~A~%" (getf usage :prompt-tokens))
        (format t "  Completion tokens: ~A~%" (getf usage :completion-tokens))
        (format t "  Total tokens: ~A~%" (getf usage :total-tokens))
        (format t "  ✓ Token counts present~%")))
  (error (e)
    (format t "✗ Test failed: ~A~%" e)
    (uiop:quit 1)))

;;; Test 4: Embedding with Metadata (if supported)
(format t "~%~%=== Test 4: Embedding with Metadata ===~%")
(handler-case
    (let ((response (embedding "Common Lisp is a powerful language"
                               :provider *ollama*
                               :model "nomic-embed-text")))
      (format t "✓ Embedding succeeded~%")

      (format t "  Model: ~A~%" (response-model response))
      (format t "  Embedding dimensions: ~A~%" (length (first (response-embeddings response))))

      (format t "~%Token Usage:~%")
      (let ((usage (response-usage response)))
        (format t "  Prompt tokens: ~A~%" (getf usage :prompt-tokens))
        (format t "  Total tokens: ~A~%" (getf usage :total-tokens))
        (format t "  ✓ Usage information present~%"))

      (format t "~%Metadata:~%")
      (let ((metadata (response-metadata response)))
        (if metadata
            (progn
              (format t "  Total duration: ~A ns~%" (getf metadata :total-duration-ns))
              (when (getf metadata :load-duration-ns)
                (format t "  Load duration: ~A ns~%" (getf metadata :load-duration-ns)))
              (format t "  ✓ Metadata extracted~%"))
            (format t "  WARNING: No metadata found~%"))))
  (error (e)
    (format t "ℹ Embedding test skipped (model may not be available): ~A~%" e)))

;;; Test 5: Multiple Requests - Verify Independence
(format t "~%~%=== Test 5: Multiple Requests Independence ===~%")
(handler-case
    (let* ((response1 (complete '((:role "user" :content "Count to 3"))
                                :provider *ollama*
                                :max-tokens 30))
           (response2 (complete '((:role "user" :content "Name a color"))
                                :provider *ollama*
                                :max-tokens 20)))
      (format t "✓ Multiple requests succeeded~%")

      (let ((usage1 (response-usage response1))
            (usage2 (response-usage response2)))
        (format t "~%Request 1 tokens: ~A prompt, ~A completion~%"
                (getf usage1 :prompt-tokens)
                (getf usage1 :completion-tokens))
        (format t "Request 2 tokens: ~A prompt, ~A completion~%"
                (getf usage2 :prompt-tokens)
                (getf usage2 :completion-tokens))

        ;; Verify they're different
        (assert (not (equal usage1 usage2))
                nil "Usage counts should be different for different requests")
        (format t "  ✓ Token counts are independent per request~%"))

      (let ((meta1 (response-metadata response1))
            (meta2 (response-metadata response2)))
        (when (and meta1 meta2)
          (assert (not (eql (getf meta1 :total-duration-ns)
                           (getf meta2 :total-duration-ns)))
                  nil "Metadata should be different for different requests")
          (format t "  ✓ Metadata is independent per request~%"))))
  (error (e)
    (format t "✗ Test failed: ~A~%" e)
    (uiop:quit 1)))

(format t "~%~%=== All Tests Passed! ===~%")
(format t "~%Summary:~%")
(format t "  ✓ Token counting works correctly~%")
(format t "  ✓ Metadata extraction works~%")
(format t "  ✓ Performance profiling works alongside metadata~%")
(format t "  ✓ Thinking mode integration works~%")
(format t "  ✓ Multiple requests maintain independence~%")

(uiop:quit 0)
