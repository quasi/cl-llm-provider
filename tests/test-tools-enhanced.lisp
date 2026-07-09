;;; ABOUTME: Tests for enhanced tool functionality (validators, registry, approval, hooks, execution)
(th.harness:setup :cl-llm-provider)

(in-package :cl-llm-provider.tools)

(fiveam:def-suite tools-enhanced-suite
  :description "Tests for enhanced tools functionality"
  :in cl-llm-provider/test::cl-llm-provider-suite)

(fiveam:in-suite tools-enhanced-suite)

;;;; Category Tests

(fiveam:test category-constants
  "Verify predefined categories exist"
  (fiveam:is (listp *tool-categories*))
  (fiveam:is (member :search *tool-categories*))
  (fiveam:is (member :database *tool-categories*))
  (fiveam:is (member :filesystem *tool-categories*))
  (fiveam:is (member :destructive *tool-categories*))
  (fiveam:is (member :payment *tool-categories*))
  (fiveam:is (member :authentication *tool-categories*)))

(fiveam:test category-validation
  "Test category validation"
  (fiveam:is (valid-category-p :search))
  (fiveam:is (valid-category-p :custom-category))
  (fiveam:is (not (valid-category-p "string")))
  (fiveam:is (not (valid-category-p 123))))

(fiveam:test category-normalization
  "Test category normalization"
  (fiveam:is (null (normalize-categories nil)))
  (fiveam:is (equal '(:search) (normalize-categories :search)))
  (fiveam:is (equal '(:search :database) (normalize-categories '(:search :database)))))

;;;; Safety Level Tests

(fiveam:test safety-level-order
  "Safety levels are ordered correctly"
  (fiveam:is (= 0 (safety-level-value :safe)))
  (fiveam:is (= 1 (safety-level-value :moderate)))
  (fiveam:is (= 2 (safety-level-value :dangerous))))

(fiveam:test safety-level-comparison
  "Safety level comparisons work"
  (fiveam:is (safety-level<= :safe :safe))
  (fiveam:is (safety-level<= :safe :moderate))
  (fiveam:is (safety-level<= :safe :dangerous))
  (fiveam:is (safety-level<= :moderate :dangerous))
  (fiveam:is (not (safety-level<= :dangerous :safe)))
  (fiveam:is (not (safety-level<= :moderate :safe))))

;;;; Validator Tests

(fiveam:test built-in-validators-exist
  "Built-in validators are defined"
  (fiveam:is (functionp (get-built-in-validator :positive-integer)))
  (fiveam:is (functionp (get-built-in-validator :non-empty-string)))
  (fiveam:is (functionp (get-built-in-validator :email))))

(fiveam:test range-validator
  "Range validator works"
  (let ((v (make-range-validator 0 100)))
    (fiveam:is (funcall v 50))
    (fiveam:is (funcall v 0))
    (fiveam:is (funcall v 100))
    (fiveam:is (not (funcall v -1)))
    (fiveam:is (not (funcall v 101)))))

(fiveam:test pattern-validator
  "Pattern validator works"
  (let ((v (make-pattern-validator "^hello")))
    (fiveam:is (funcall v "hello world"))
    (fiveam:is (not (funcall v "world hello")))))

(fiveam:test length-validator
  "Length validator works"
  (let ((v (make-length-validator :min-length 3 :max-length 10)))
    (fiveam:is (funcall v "hello"))
    (fiveam:is (not (funcall v "hi")))
    (fiveam:is (not (funcall v "this is too long")))))

(fiveam:test enum-validator
  "Enum validator works"
  (let ((v (make-enum-validator '("a" "b" "c"))))
    (fiveam:is (funcall v "a"))
    (fiveam:is (funcall v "b"))
    (fiveam:is (not (funcall v "d")))))

(fiveam:test parse-validator-spec-function
  "Parse function validators"
  (let ((v (parse-validator-spec (lambda (x) (> x 0)))))
    (fiveam:is (funcall v 5))
    (fiveam:is (not (funcall v -1)))))

(fiveam:test parse-validator-spec-keyword
  "Parse keyword validators"
  (let ((v (parse-validator-spec :positive-integer)))
    (fiveam:is (funcall v 5))
    (fiveam:is (not (funcall v 0)))
    (fiveam:is (not (funcall v -1)))))

(fiveam:test parse-validator-spec-plist
  "Parse plist validator specs"
  (let ((v (parse-validator-spec '(:type :integer :min 0 :max 100))))
    (fiveam:is (funcall v 50))
    (fiveam:is (not (funcall v 150)))
    (fiveam:is (not (funcall v "string")))))

;;;; Registry Tests

(fiveam:test create-registry
  "Create a tool registry"
  (let ((reg (make-tool-registry :name "test")))
    (fiveam:is (typep reg 'tool-registry))
    (fiveam:is (string= "test" (registry-name reg)))
    (fiveam:is (= 0 (registry-tool-count reg)))))

(fiveam:test register-and-find-tool
  "Register and find tools in registry"
  (let* ((reg (make-tool-registry))
         (tool (cl-llm-provider:define-tool "test_tool"
                                            "A test tool"
                                            nil)))
    (register-tool reg tool)
    (fiveam:is (= 1 (registry-tool-count reg)))
    (fiveam:is (eq tool (find-tool reg "test_tool")))
    (fiveam:is (null (find-tool reg "nonexistent")))))

(fiveam:test register-tool-signals-typed-condition
  "Duplicate registrations signal tool-registration-error with the tool name."
  (let* ((reg (make-tool-registry))
         (tool (cl-llm-provider:define-tool "dup_tool" "A test tool" nil)))
    (register-tool reg tool)
    (handler-case
        (progn
          (register-tool reg tool)
          (fiveam:fail "Duplicate registration should signal."))
      (cl-llm-provider:tool-registration-error (e)
        (fiveam:is (string= "dup_tool" (cl-llm-provider:error-tool-name e)))))))

(fiveam:test unregister-tool
  "Unregister tools from registry"
  (let* ((reg (make-tool-registry))
         (tool (cl-llm-provider:define-tool "test_tool" "Test" nil)))
    (register-tool reg tool)
    (fiveam:is (= 1 (registry-tool-count reg)))
    (unregister-tool reg "test_tool")
    (fiveam:is (= 0 (registry-tool-count reg)))))

(fiveam:test search-by-category
  "Search tools by category"
  (let* ((reg (make-tool-registry))
         (tool1 (cl-llm-provider:define-tool "search" "Search" nil
                                             :categories '(:search)))
         (tool2 (cl-llm-provider:define-tool "delete" "Delete" nil
                                             :categories '(:destructive))))
    (register-tool reg tool1)
    (register-tool reg tool2)
    (let ((results (search-tools reg :categories '(:search))))
      (fiveam:is (= 1 (length results)))
      (fiveam:is (string= "search" (cl-llm-provider:tool-name (first results)))))))

(fiveam:test search-by-safety-level
  "Search tools by safety level"
  (let* ((reg (make-tool-registry))
         (safe-tool (cl-llm-provider:define-tool "safe" "Safe" nil
                                                 :safety-level :safe))
         (dangerous-tool (cl-llm-provider:define-tool "danger" "Dangerous" nil
                                                      :safety-level :dangerous)))
    (register-tool reg safe-tool)
    (register-tool reg dangerous-tool)
    (let ((safe-only (search-tools reg :max-safety-level :safe)))
      (fiveam:is (= 1 (length safe-only)))
      (fiveam:is (string= "safe" (cl-llm-provider:tool-name (first safe-only)))))))

;;;; Approval Tests

(fiveam:test needs-approval-nil
  "NIL requires-approval means no approval needed"
  (let ((tool (cl-llm-provider:define-tool "test" "Test" nil
                                           :requires-approval nil)))
    (fiveam:is (not (needs-approval-p tool)))))

(fiveam:test needs-approval-always
  "T/:always requires-approval means always approve"
  (let ((tool1 (cl-llm-provider:define-tool "test1" "Test" nil
                                            :requires-approval t))
        (tool2 (cl-llm-provider:define-tool "test2" "Test" nil
                                            :requires-approval :always)))
    (fiveam:is (needs-approval-p tool1))
    (fiveam:is (needs-approval-p tool2))))

(fiveam:test needs-approval-if-dangerous
  ":if-dangerous only requires approval for dangerous tools"
  (let ((safe (cl-llm-provider:define-tool "safe" "Safe" nil
                                           :safety-level :safe
                                           :requires-approval :if-dangerous))
        (dangerous (cl-llm-provider:define-tool "danger" "Dangerous" nil
                                                :safety-level :dangerous
                                                :requires-approval :if-dangerous)))
    (fiveam:is (not (needs-approval-p safe)))
    (fiveam:is (needs-approval-p dangerous))))

(fiveam:test normalize-approval-result
  "Approval result normalization"
  (multiple-value-bind (d a r)
      (normalize-approval-result t '(:a 1))
    (fiveam:is (eq :approved d))
    (fiveam:is (equal '(:a 1) a)))

  (multiple-value-bind (d a r)
      (normalize-approval-result nil '(:a 1))
    (fiveam:is (eq :rejected d)))

  (multiple-value-bind (d a r)
      (normalize-approval-result '(:edited (:b 2)) '(:a 1))
    (fiveam:is (eq :edited d))
    (fiveam:is (equal '(:b 2) a))))

(fiveam:test interactive-approval-rejects-empty-input
  "Empty interactive input rejects instead of crashing on CHAR."
  (let* ((stream (make-two-way-stream
                  (make-string-input-stream (format nil "~%"))
                  (make-broadcast-stream)))
         (callback (make-interactive-approval-callback :stream stream))
         (tool (cl-llm-provider:define-tool "ask" "Ask" nil))
         (call (make-instance 'cl-llm-provider:tool-call
                              :id "call-1"
                              :name "ask"
                              :arguments nil)))
    (fiveam:is (eq :rejected (funcall callback tool call nil)))))

(fiveam:test interactive-approval-edit-does-not-read-eval
  "Edited argument input is read with *read-eval* disabled."
  (let* ((stream (make-two-way-stream
                  (make-string-input-stream (format nil "e~%#.(error \"eval\")~%"))
                  (make-broadcast-stream)))
         (callback (make-interactive-approval-callback :stream stream))
         (tool (cl-llm-provider:define-tool "ask_edit" "Ask" nil))
         (call (make-instance 'cl-llm-provider:tool-call
                              :id "call-1"
                              :name "ask_edit"
                              :arguments nil)))
    (fiveam:signals reader-error
      (funcall callback tool call nil))))

;;;; Hook Tests

(fiveam:test logging-hook-creation
  "Create logging hooks"
  (fiveam:is (functionp (make-logging-hook :on-start)))
  (fiveam:is (functionp (make-logging-hook :on-complete)))
  (fiveam:is (functionp (make-logging-hook :on-error))))

(fiveam:test timing-hook-creation
  "Create timing hooks"
  (let ((hooks (make-timing-hook)))
    (fiveam:is (listp hooks))
    (fiveam:is (functionp (getf hooks :on-start)))
    (fiveam:is (functionp (getf hooks :on-complete)))))

;;;; Execution Context Tests

(fiveam:test execution-context-creation
  "Create execution context"
  (let ((call (make-instance 'cl-llm-provider:tool-call
                             :id "call-1"
                             :name "test"
                             :arguments '(:a 1)))
        (tool (cl-llm-provider:define-tool "test" "Test" nil)))
    (let ((ctx (make-instance 'tool-execution-context
                              :tool-call call
                              :tool-definition tool
                              :arguments '(:a 1))))
      (fiveam:is (eq call (context-tool-call ctx)))
      (fiveam:is (eq tool (context-tool-definition ctx)))
      (fiveam:is (equal '(:a 1) (context-arguments ctx))))))

;;;; Tool Execution Tests

(fiveam:test execute-tool-with-handler
  "Execute a tool with handler"
  (let* ((tool (cl-llm-provider:define-tool "add" "Add numbers" nil
                                            :handler (lambda (args)
                                                       (+ (getf args :a) (getf args :b)))))
         (call (make-instance 'cl-llm-provider:tool-call
                              :id "call-1"
                              :name "add"
                              :arguments '(:a 2 :b 3))))
    (let ((result (execute-tool tool call)))
      (fiveam:is (= 5 result)))))

(fiveam:test execute-tool-safety-violation
  "Execute tool fails on safety violation"
  (let* ((tool (cl-llm-provider:define-tool "danger" "Dangerous" nil
                                            :safety-level :dangerous
                                            :handler (lambda (args) (declare (ignore args)) t)))
         (call (make-instance 'cl-llm-provider:tool-call
                              :id "call-1"
                              :name "danger"
                              :arguments nil)))
    (fiveam:signals cl-llm-provider:tool-safety-violation
      (execute-tool tool call :max-safety-level :safe))))

(fiveam:test execute-tool-approval-rejection
  "Execute tool fails when approval rejected"
  (let* ((tool (cl-llm-provider:define-tool "test" "Test" nil
                                            :requires-approval t
                                            :handler (lambda (args) (declare (ignore args)) t)))
         (call (make-instance 'cl-llm-provider:tool-call
                              :id "call-1"
                              :name "test"
                              :arguments nil)))
    (fiveam:signals cl-llm-provider:tool-approval-error
      (execute-tool tool call
                    :approval-callback (lambda (tool tc args)
                                         (declare (ignore tool tc args))
                                         nil)))))

(fiveam:test execute-tool-calls-propagates-safety-conditions
  "Batch execution keeps safety/approval conditions visible to callers."
  (let* ((tool (cl-llm-provider:define-tool "danger_batch" "Dangerous" nil
                                            :safety-level :dangerous
                                            :handler (lambda (args)
                                                       (declare (ignore args))
                                                       t)))
         (registry (make-tool-registry))
         (call (make-instance 'cl-llm-provider:tool-call
                              :id "call-1"
                              :name "danger_batch"
                              :arguments nil))
         (response (make-instance 'cl-llm-provider:completion-response
                                  :tool-calls (list call))))
    (register-tool registry tool)
    (fiveam:signals cl-llm-provider:tool-safety-violation
      (execute-tool-calls response
                          :registry registry
                          :max-safety-level :safe))))

(fiveam:test retry-execution-restart-fires-on-complete-hook
  "The retry-execution restart retries through the normal hook path."
  (let* ((attempts 0)
         (complete-count 0)
         (tool (cl-llm-provider:define-tool "retry_once" "Retry once" nil
                                            :handler (lambda (args)
                                                       (declare (ignore args))
                                                       (incf attempts)
                                                       (if (= attempts 1)
                                                           (error "first")
                                                           :ok))
                                            :on-complete (lambda (call args result)
                                                           (declare (ignore call args result))
                                                           (incf complete-count))))
         (call (make-instance 'cl-llm-provider:tool-call
                              :id "call-1"
                              :name "retry_once"
                              :arguments nil)))
    (let ((result (handler-bind
                      ((error (lambda (e)
                                (declare (ignore e))
                                (let ((restart (find-restart 'retry-execution)))
                                  (when restart
                                    (invoke-restart restart))))))
                    (execute-tool tool call :skip-approval t :skip-validation t))))
      (fiveam:is (eq :ok result))
      (fiveam:is (= 2 attempts))
      (fiveam:is (= 1 complete-count)))))

(fiveam:test execute-tool-with-hooks
  "Execute tool with lifecycle hooks"
  (let* ((hook-calls nil)
         (tool (cl-llm-provider:define-tool "test" "Test" nil
                                            :on-start (lambda (call args)
                                                        (declare (ignore call args))
                                                        (push :start hook-calls))
                                            :on-complete (lambda (call args result)
                                                           (declare (ignore call args result))
                                                           (push :complete hook-calls))
                                            :handler (lambda (args)
                                                       (declare (ignore args))
                                                       42)))
         (call (make-instance 'cl-llm-provider:tool-call
                              :id "call-1"
                              :name "test"
                              :arguments nil)))
    (execute-tool tool call)
    (fiveam:is (member :start hook-calls))
    (fiveam:is (member :complete hook-calls))))
