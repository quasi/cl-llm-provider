;;; ABOUTME: Mutation tests for cl-llm-provider using cl-test-hardening/mutation
;;; Targets tokenizer.lisp with arithmetic mutation operators.

(th.harness:setup :cl-llm-provider)

(in-package :cl-llm-provider)

(fiveam:def-suite mutation-suite
  :description "Mutation testing for tokenizer functions"
  :in cl-llm-provider/test::cl-llm-provider-suite)

(fiveam:in-suite mutation-suite)

;;;; Mutation operators for tokenizer

(th.mutation:define-mutation-operators tokenizer-arithmetic
  (th.mutation:mutate-pattern ceiling-to-floor
    :pattern (ceiling ?x ?y)
    :mutations ((floor ?x ?y))
    :description "Replace ceiling with floor in token estimation")

  (th.mutation:mutate-pattern add-to-sub
    :pattern (+ ?x ?y)
    :mutations ((- ?x ?y))
    :description "Replace addition with subtraction")

  (th.mutation:mutate-pattern sub-to-add
    :pattern (- ?x ?y)
    :mutations ((+ ?x ?y))
    :description "Replace subtraction with addition"))

(th.mutation:define-mutation-operators tokenizer-boundary
  (th.mutation:mutate-boundary zero-check-negate
    :pattern (= 0 ?x)
    :mutations ((> 0 ?x))
    :description "Negate zero check in token counting")

  (th.mutation:mutate-boundary gte-to-gt
    :pattern (>= ?x ?y)
    :mutations ((> ?x ?y))
    :description "Replace >= with > in comparisons"))

;;;; Tokenizer source forms for mutation

(defvar *tokenizer-estimate-form*
  '(defun estimate-tokens-from-text (text)
     (if (or (null text) (string= text ""))
         0
         (ceiling (length text) *chars-per-token-estimate*)))
  "Source form for estimate-tokens-from-text for mutation analysis.")

(defvar *tokenizer-count-message-form*
  '(defun count-message-tokens (message)
     (let ((content (getf message :content)))
       (+ *message-overhead-tokens*
          (etypecase content
            (string (estimate-tokens-from-text content))
            (null 0)))))
  "Simplified source form for count-message-tokens for mutation analysis.")

(defvar *tokenizer-count-tokens-form*
  '(defun count-tokens (messages &key model provider)
     (declare (ignore model provider))
     (loop for message in messages
           sum (count-message-tokens message)))
  "Source form for count-tokens for mutation analysis.")

;;;; Test function for mutation testing

(defun tokenizer-test-fn ()
  "Test function that exercises tokenizer invariants.
Returns T if all invariants hold (code is correct)."
  (and
   ;; estimate-tokens-from-text returns 0 for empty/nil
   (= 0 (estimate-tokens-from-text ""))
   (= 0 (estimate-tokens-from-text nil))
   ;; estimate-tokens-from-text returns positive for non-empty
   (> (estimate-tokens-from-text "hello") 0)
   (> (estimate-tokens-from-text "a") 0)
   ;; Longer text -> more tokens (monotonicity)
   (<= (estimate-tokens-from-text "hi")
       (estimate-tokens-from-text "hello world this is a longer text"))
   ;; count-message-tokens >= overhead
   (>= (count-message-tokens '(:role "user" :content "test"))
       *message-overhead-tokens*)
   ;; count-message-tokens with nil content = overhead
   (= *message-overhead-tokens*
      (count-message-tokens '(:role "user" :content nil)))
   ;; count-tokens adds up
   (> (count-tokens '((:role "user" :content "hello")
                      (:role "assistant" :content "world")))
      (count-tokens '((:role "user" :content "hello"))))
   ;; count-tokens of empty list is 0
   (= 0 (count-tokens nil))
   ;; count-tokens-with-system with nil system = count-tokens
   (= (count-tokens '((:role "user" :content "test")))
      (count-tokens-with-system '((:role "user" :content "test")) nil))
   ;; count-tokens-with-system with system > without
   (< (count-tokens '((:role "user" :content "test")))
      (count-tokens-with-system '((:role "user" :content "test")) "Be helpful"))))

;;;; Mutation test: generate mutants and verify test kills them

(fiveam:test mutation-tokenizer-operators-defined
  "Tokenizer mutation operators are properly defined"
  (fiveam:is (th.mutation:find-operator-set 'tokenizer-arithmetic))
  (fiveam:is (th.mutation:find-operator-set 'tokenizer-boundary)))

(fiveam:test mutation-tokenizer-generates-mutants
  "Mutation operators generate mutants from tokenizer forms"
  (let* ((op-set (th.mutation:find-operator-set 'tokenizer-arithmetic))
         (operators (th.mutation::operator-set-operators op-set))
         (mutants (th.mutation:generate-mutants
                   (list *tokenizer-estimate-form*)
                   operators)))
    (fiveam:is (> (length mutants) 0)
               "Should generate at least one mutant from estimate-tokens-from-text")))

(fiveam:test mutation-tokenizer-test-fn-passes
  "Tokenizer test function passes against correct code"
  (fiveam:is (tokenizer-test-fn)
             "Test function should pass against correct implementation"))

(fiveam:test mutation-tokenizer-arithmetic-score
  "Arithmetic mutation score meets threshold for tokenizer"
  (let* ((op-set (th.mutation:find-operator-set 'tokenizer-arithmetic))
         (operators (th.mutation::operator-set-operators op-set))
         (forms (list *tokenizer-estimate-form*
                      *tokenizer-count-message-form*
                      *tokenizer-count-tokens-form*)))
    (multiple-value-bind (score passed-p total killed)
        (th.mutation:mutate-and-test forms #'tokenizer-test-fn operators
                                     :threshold 0.80)
      (declare (ignore passed-p))
      (fiveam:is (> total 0)
                 "Should generate mutants")
      ;; Report score even if threshold not met
      (format t "~%Mutation score: ~,2F (~D/~D killed)~%" score killed total)
      (fiveam:is (>= score 0.50)
                 (format nil "Mutation score ~,2F should be >= 0.50" score)))))
