;;; ABOUTME: Parameter validation system with built-in and custom validators
(in-package :cl-llm-provider.tools)

;;;; Validation Patterns

(defvar *email-pattern* "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"
  "Basic email validation regex: localpart@domain.tld")

(defvar *url-pattern* "^https?://"
  "Basic URL validation regex: http:// or https:// prefix")

;;;; Built-in Validators

(defvar *built-in-validators*
  (list
   :positive-integer (lambda (v) (and (integerp v) (> v 0)))
   :non-negative-integer (lambda (v) (and (integerp v) (>= v 0)))
   :positive-number (lambda (v) (and (numberp v) (> v 0)))
   :non-negative-number (lambda (v) (and (numberp v) (>= v 0)))
   :non-empty-string (lambda (v) (and (stringp v) (> (length v) 0)))
   :email (lambda (v) (and (stringp v) (cl-ppcre:scan *email-pattern* v)))
   :url (lambda (v) (and (stringp v) (cl-ppcre:scan *url-pattern* v)))
   :boolean (lambda (v) (typep v 'boolean))
   :string (lambda (v) (stringp v))
   :integer (lambda (v) (integerp v))
   :number (lambda (v) (numberp v)))
  "Plist of built-in named validators.
   Use with :parameter-validators '((\"param\" . :positive-integer))")

(defun get-built-in-validator (name)
  "Get a built-in validator function by NAME keyword."
  (getf *built-in-validators* name))

;;;; Validator Factory Functions

(defun make-range-validator (min max)
  "Create a validator for numeric range [MIN, MAX].
   Either MIN or MAX can be NIL for open-ended ranges."
  (lambda (value)
    (and (numberp value)
         (or (null min) (>= value min))
         (or (null max) (<= value max)))))

(defun make-pattern-validator (pattern)
  "Create a validator for string pattern matching.
   PATTERN is a CL-PPCRE regex string."
  (let ((scanner (cl-ppcre:create-scanner pattern)))
    (lambda (value)
      (and (stringp value)
           (cl-ppcre:scan scanner value)
           t))))

(defun make-length-validator (&key min-length max-length)
  "Create a validator for string/sequence length.
   Either MIN-LENGTH or MAX-LENGTH can be NIL for open-ended ranges."
  (lambda (value)
    (let ((len (if (or (stringp value) (listp value) (vectorp value))
                   (length value)
                   nil)))
      (and len
           (or (null min-length) (>= len min-length))
           (or (null max-length) (<= len max-length))))))

(defun make-enum-validator (allowed-values &key (test #'equal))
  "Create a validator for enumerated values.
   ALLOWED-VALUES is a list of valid options.
   TEST is the comparison function (default EQUAL)."
  (lambda (value)
    (member value allowed-values :test test)))

(defun make-type-validator (type-spec)
  "Create a validator for Common Lisp TYPE-SPEC.
   Uses TYPEP for type checking."
  (lambda (value)
    (typep value type-spec)))

(defun make-composite-validator (&rest validators)
  "Create a validator that requires ALL sub-validators to pass."
  (lambda (value)
    (every (lambda (v) (funcall v value)) validators)))

;;;; Validator Spec Parsing

(defun parse-validator-spec (spec)
  "Parse a validator specification into a validator function.

   SPEC can be:
   - A function: returned as-is
   - A keyword: looked up in *built-in-validators*
   - A plist: parsed according to keys:
     - :type - CL type or JSON schema type (:string, :integer, etc.)
     - :min, :max - numeric range
     - :min-length, :max-length - string/sequence length
     - :pattern - regex pattern (string)
     - :enum - list of allowed values

   Returns a function (lambda (value) -> t/nil)."
  (cond
    ;; Already a function
    ((functionp spec) spec)

    ;; Named built-in validator
    ((keywordp spec)
     (or (get-built-in-validator spec)
         (error "Unknown built-in validator: ~S" spec)))

    ;; Validator spec plist
    ((and (listp spec) (keywordp (first spec)))
     (let ((validators nil))
       ;; Type check
       (when-let ((type-spec (getf spec :type)))
         (push (make-type-validator-from-spec type-spec) validators))

       ;; Numeric range
       (when (or (getf spec :min) (getf spec :max))
         (push (make-range-validator (getf spec :min) (getf spec :max)) validators))

       ;; Length constraints
       (when (or (getf spec :min-length) (getf spec :max-length))
         (push (make-length-validator :min-length (getf spec :min-length)
                                      :max-length (getf spec :max-length))
               validators))

       ;; Pattern match
       (when-let ((pattern (getf spec :pattern)))
         (push (make-pattern-validator pattern) validators))

       ;; Enum values
       (when-let ((enum-vals (getf spec :enum)))
         (push (make-enum-validator enum-vals) validators))

       ;; Combine all validators
       (if (= (length validators) 1)
           (first validators)
           (apply #'make-composite-validator validators))))

    (t (error "Invalid validator specification: ~S" spec))))

(defun make-type-validator-from-spec (type-spec)
  "Create type validator from JSON schema or CL type spec."
  (case type-spec
    (:string (lambda (v) (stringp v)))
    (:integer (lambda (v) (integerp v)))
    (:number (lambda (v) (numberp v)))
    (:boolean (lambda (v) (typep v 'boolean)))
    (:array (lambda (v) (or (listp v) (vectorp v))))
    (:object (lambda (v) (or (hash-table-p v) (and (listp v) (keywordp (first v))))))
    (otherwise (make-type-validator type-spec))))

;;;; Validation Functions

(defgeneric validate-parameter (validator parameter-name value tool)
  (:documentation "Validate a single parameter VALUE against VALIDATOR.
   PARAMETER-NAME is used for error messages.
   TOOL is the tool-definition for error context.
   Returns T if valid.
   Signals tool-validation-error on failure."))

(defmethod validate-parameter ((validator function) parameter-name value tool)
  "Validate using a function validator."
  (if (funcall validator value)
      t
      (error 'tool-validation-error
             :tool tool
             :parameter parameter-name
             :value value
             :validator validator
             :reason "Value failed validation")))

(defmethod validate-parameter ((validator symbol) parameter-name value tool)
  "Validate using a named built-in validator."
  (let ((fn (get-built-in-validator validator)))
    (unless fn
      (error "Unknown validator: ~S" validator))
    (validate-parameter fn parameter-name value tool)))

(defmethod validate-parameter ((validator list) parameter-name value tool)
  "Validate using a validator spec plist."
  (let ((fn (parse-validator-spec validator)))
    (validate-parameter fn parameter-name value tool)))

(defun validate-tool-arguments (tool-definition arguments)
  "Validate ARGUMENTS against TOOL-DEFINITION's parameter validators.

   TOOL-DEFINITION - tool-definition object with parameter-validators slot
   ARGUMENTS - plist of argument values (e.g., (:location \"Paris\" :unit \"celsius\"))

   Returns T if all validations pass.
   Signals tool-validation-error on first validation failure."
  (let ((validators (tool-parameter-validators tool-definition)))
    (when validators
      (loop for (param-name . validator-spec) in validators
            for value = (getf arguments (intern (string-upcase param-name) :keyword))
            ;; Only validate if value is provided (let required param checks handle missing)
            when value
            do (validate-parameter (parse-validator-spec validator-spec)
                                   param-name
                                   value
                                   tool-definition)))
    t))
