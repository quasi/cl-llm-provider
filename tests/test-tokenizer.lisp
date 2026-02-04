(th.harness:setup :cl-llm-provider)

(fiveam:def-suite tokenizer-suite
  :description "Token counting tests"
  :in cl-llm-provider/test::cl-llm-provider-suite)

(fiveam:in-suite tokenizer-suite)

(fiveam:test count-tokens-basic
  "Test basic token counting"
  (let ((count (cl-llm-provider:count-tokens
                '((:role "user" :content "Hello, world!"))
                :model "gpt-4")))
    (fiveam:is (numberp count))
    (fiveam:is (> count 0))))

(fiveam:test count-tokens-estimates-reasonably
  "Test token count is reasonable for known text"
  ;; "Hello, world!" is ~4 tokens in most tokenizers
  (let ((count (cl-llm-provider:count-tokens
                '((:role "user" :content "Hello, world!"))
                :model "gpt-4")))
    (fiveam:is (>= count 2))   ; At least 2 tokens
    (fiveam:is (<= count 10)))) ; At most 10 tokens (with overhead)

(fiveam:test estimate-cost-basic
  "Test basic cost estimation"
  (let ((provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "test"
                                 :model "gpt-4o")))
    (multiple-value-bind (input-cost output-cost total)
        (cl-llm-provider:estimate-cost
         '((:role "user" :content "Hello!"))
         :provider provider
         :model "gpt-4o"
         :max-tokens 100)
      (fiveam:is (numberp input-cost))
      (fiveam:is (numberp output-cost))
      (fiveam:is (numberp total))
      (fiveam:is (> total 0)))))

(fiveam:test estimate-cost-uses-model-metadata
  "Test that cost estimation uses model pricing"
  (let ((provider (make-instance 'cl-llm-provider::openai-provider
                                 :api-key "test")))
    ;; gpt-4o-mini is cheaper than gpt-4o
    (let ((cheap-cost (cl-llm-provider:estimate-cost
                       '((:role "user" :content "Test"))
                       :provider provider
                       :model "gpt-4o-mini"
                       :max-tokens 100))
          (expensive-cost (cl-llm-provider:estimate-cost
                          '((:role "user" :content "Test"))
                          :provider provider
                          :model "gpt-4o"
                          :max-tokens 100)))
      (fiveam:is (< cheap-cost expensive-cost)))))

(fiveam:test format-cost-basic
  "Test basic cost formatting"
  (let ((formatted (with-output-to-string (s)
                     (cl-llm-provider:format-cost 0.0025 s))))
    (fiveam:is (stringp formatted))
    (fiveam:is (search "$" formatted))
    (fiveam:is (search "0.0025" formatted))))

(fiveam:test format-cost-nil
  "Test formatting nil cost"
  (let ((formatted (with-output-to-string (s)
                     (cl-llm-provider:format-cost nil s))))
    (fiveam:is (stringp formatted))
    (fiveam:is (search "N/A" formatted))))

