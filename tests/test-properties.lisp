;;; ABOUTME: Property-based tests for cl-llm-provider using cl-test-hardening/property

(in-package :cl-llm-provider)

(fiveam:def-suite property-suite
  :description "Property-based tests"
  :in cl-llm-provider/test::cl-llm-provider-suite)

(fiveam:in-suite property-suite)

;;;; Tokenizer properties

(th.property:define-property estimate-tokens-non-negative
  :for-all ((text (th.gen:strings :min-length 0 :max-length 500)))
  :holds (>= (estimate-tokens-from-text text) 0)
  :tags (:tokenizer))

(th.property:define-property estimate-tokens-empty-string-is-zero
  :for-all ((text (th.gen:elements "" nil)))
  :holds (= 0 (estimate-tokens-from-text text))
  :tags (:tokenizer))

(th.property:define-property estimate-tokens-monotonic-with-length
  :for-all ((short (th.gen:strings :min-length 1 :max-length 10))
            (extra (th.gen:strings :min-length 1 :max-length 100)))
  :holds (let ((long (concatenate 'string short extra)))
           (<= (estimate-tokens-from-text short)
               (estimate-tokens-from-text long)))
  :tags (:tokenizer))

(th.property:define-property message-tokens-at-least-overhead
  :for-all ((msg (gen-message)))
  :holds (>= (count-message-tokens msg) *message-overhead-tokens*)
  :tags (:tokenizer))

(th.property:define-property count-tokens-monotonic-with-messages
  :for-all ((msgs (gen-conversation :min-length 1 :max-length 5))
            (extra-msg (gen-message)))
  :holds (<= (count-tokens msgs)
             (count-tokens (append msgs (list extra-msg))))
  :tags (:tokenizer))

(th.property:define-property count-tokens-with-system-at-least-without
  :for-all ((msgs (gen-conversation :min-length 1 :max-length 5))
            (system-prompt (th.gen:strings :min-length 1 :max-length 100)))
  :holds (<= (count-tokens msgs)
             (count-tokens-with-system msgs system-prompt))
  :tags (:tokenizer))

(th.property:define-property count-tokens-nil-system-equals-count-tokens
  :for-all ((msgs (gen-conversation :min-length 1 :max-length 5)))
  :holds (= (count-tokens msgs)
            (count-tokens-with-system msgs nil))
  :tags (:tokenizer))

;;;; Message normalization properties

(th.property:define-property plist-to-hash-preserves-content
  :for-all ((role (gen-role))
            (content (gen-content)))
  :holds (let* ((plist (list :role role :content content))
                (hash (plist-to-hash plist)))
           (and (string= (gethash "role" hash) role)
                (string= (gethash "content" hash) content)))
  :tags (:normalization))

(th.property:define-property plist-to-hash-converts-hyphens
  :for-all ((value (th.gen:strings :min-length 1 :max-length 20)))
  :holds (let* ((plist (list :tool-call-id value))
                (hash (plist-to-hash plist)))
           (string= (gethash "tool_call_id" hash) value))
  :tags (:normalization))

;;;; Tool definition properties

(th.property:define-property tool-name-preserved
  :for-all ((tool (gen-tool-definition)))
  :holds (stringp (tool-name tool))
  :tags (:tools))

(th.property:define-property tool-safety-level-valid
  :for-all ((tool (gen-tool-definition)))
  :holds (member (tool-safety-level tool) '(:safe :moderate :dangerous))
  :tags (:tools))

(th.property:define-property tool-required-subset-of-params
  :for-all ((params (th.gen:lists (gen-tool-parameter) :min-length 1 :max-length 5)))
  :holds (let* ((all-names (mapcar (lambda (p) (getf p :name)) params))
                (required (list (first all-names)))
                (tool (make-instance 'tool-definition
                                     :name "test"
                                     :description "test"
                                     :parameters params
                                     :required required)))
           (every (lambda (r) (member r all-names :test #'string=))
                  (tool-required-params tool)))
  :tags (:tools))

;;;; Usage invariant properties

(th.property:define-property usage-total-equals-sum
  :for-all ((usage (gen-usage)))
  :holds (= (getf usage :total-tokens)
            (+ (getf usage :prompt-tokens)
               (getf usage :completion-tokens)))
  :tags (:usage))

;;;; FiveAM test wrappers

(fiveam:test property-estimate-tokens-non-negative
  "estimate-tokens-from-text always returns >= 0"
  (let ((result (th.property:check-property 'estimate-tokens-non-negative :iterations 200)))
    (fiveam:is (th.property:property-result-passed-p result))))

(fiveam:test property-estimate-tokens-empty-is-zero
  "empty/nil text produces 0 tokens"
  (let ((result (th.property:check-property 'estimate-tokens-empty-string-is-zero :iterations 50)))
    (fiveam:is (th.property:property-result-passed-p result))))

(fiveam:test property-estimate-tokens-monotonic
  "longer text produces >= token count"
  (let ((result (th.property:check-property 'estimate-tokens-monotonic-with-length :iterations 200)))
    (fiveam:is (th.property:property-result-passed-p result))))

(fiveam:test property-message-tokens-at-least-overhead
  "single message always has at least overhead tokens"
  (let ((result (th.property:check-property 'message-tokens-at-least-overhead :iterations 200)))
    (fiveam:is (th.property:property-result-passed-p result))))

(fiveam:test property-count-tokens-monotonic
  "more messages produce >= token count"
  (let ((result (th.property:check-property 'count-tokens-monotonic-with-messages :iterations 200)))
    (fiveam:is (th.property:property-result-passed-p result))))

(fiveam:test property-system-prompt-adds-tokens
  "system prompt adds >= 0 tokens"
  (let ((result (th.property:check-property 'count-tokens-with-system-at-least-without :iterations 200)))
    (fiveam:is (th.property:property-result-passed-p result))))

(fiveam:test property-nil-system-is-identity
  "nil system prompt doesn't change token count"
  (let ((result (th.property:check-property 'count-tokens-nil-system-equals-count-tokens :iterations 200)))
    (fiveam:is (th.property:property-result-passed-p result))))

(fiveam:test property-plist-to-hash-preserves-content
  "plist-to-hash preserves role and content values"
  (let ((result (th.property:check-property 'plist-to-hash-preserves-content :iterations 200)))
    (fiveam:is (th.property:property-result-passed-p result))))

(fiveam:test property-plist-to-hash-converts-hyphens
  "plist-to-hash converts keyword hyphens to underscores"
  (let ((result (th.property:check-property 'plist-to-hash-converts-hyphens :iterations 100)))
    (fiveam:is (th.property:property-result-passed-p result))))

(fiveam:test property-tool-name-preserved
  "tool-definition always has string name"
  (let ((result (th.property:check-property 'tool-name-preserved :iterations 100)))
    (fiveam:is (th.property:property-result-passed-p result))))

(fiveam:test property-tool-safety-level-valid
  "tool safety-level is always one of the valid keywords"
  (let ((result (th.property:check-property 'tool-safety-level-valid :iterations 100)))
    (fiveam:is (th.property:property-result-passed-p result))))

(fiveam:test property-tool-required-subset-of-params
  "required params are always a subset of all params"
  (let ((result (th.property:check-property 'tool-required-subset-of-params :iterations 100)))
    (fiveam:is (th.property:property-result-passed-p result))))

(fiveam:test property-usage-total-equals-sum
  "usage total-tokens always equals prompt + completion"
  (let ((result (th.property:check-property 'usage-total-equals-sum :iterations 200)))
    (fiveam:is (th.property:property-result-passed-p result))))
