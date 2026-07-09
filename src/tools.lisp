(in-package :cl-llm-provider)

;;;; Tool Calling Support

(defun/i define-tool (name description parameters
                    &key required
                         safety-level
                         categories
                         requires-approval
                         parameter-validators
                         on-start
                         on-complete
                         on-error
                         handler
                         metadata)
  "Create a tool definition that can be passed to complete.

NAME - Tool/function name (string)
DESCRIPTION - What the tool does, used by LLM (string)
PARAMETERS - Parameter specifications as plists, each with:
  :name - Parameter name (string)
  :type - Parameter type (:string, :integer, :number, :boolean, :array, :object)
  :description - Parameter description (string)
  :enum - Optional list of allowed values
REQUIRED - List of required parameter names (list of strings)

ENHANCED OPTIONS:
SAFETY-LEVEL - :safe (default), :moderate, or :dangerous
CATEGORIES - List of category keywords (e.g., '(:search :database))
REQUIRES-APPROVAL - NIL, T, :always, or :if-dangerous
PARAMETER-VALIDATORS - Alist of (param-name . validator) where validator is:
  - A function: (lambda (value) t-or-nil)
  - A spec plist: (:type :integer :min 0 :max 100)
  - A named validator: :positive-integer, :email, etc.
ON-START - Hook function (lambda (tool-call arguments) ...)
ON-COMPLETE - Hook function (lambda (tool-call arguments result) ...)
ON-ERROR - Hook function (lambda (tool-call arguments condition) ...)
HANDLER - Execution function (lambda (arguments) ...)
METADATA - Plist of additional metadata (version, author, etc.)

Returns a tool-definition object.

Example:
  (define-tool \"get_weather\"
    \"Get the current weather in a given location\"
    '((:name \"location\"
       :type :string
       :description \"City and state, e.g. San Francisco, CA\")
      (:name \"unit\"
       :type :string
       :enum (\"celsius\" \"fahrenheit\")
       :description \"Temperature unit\"))
    :required '(\"location\"))

Enhanced example:
  (define-tool \"delete_file\"
    \"Delete a file from the filesystem\"
    '((:name \"path\" :type :string :description \"File path\"))
    :required '(\"path\")
    :safety-level :dangerous
    :categories '(:filesystem :destructive)
    :requires-approval :always
    :parameter-validators '((\"path\" . (:pattern \"^/tmp/\")))
    :handler (lambda (args) (delete-file (getf args :path))))"
  (:feature tool-calling)
  (:purpose "Create tool definitions with schema, safety, and execution configuration")
  (make-instance 'tool-definition
                 :name name
                 :description description
                 :parameters parameters
                 :required required
                 :safety-level (or safety-level :safe)
                 :categories categories
                 :requires-approval requires-approval
                 :parameter-validators parameter-validators
                 :on-start on-start
                 :on-complete on-complete
                 :on-error on-error
                 :handler handler
                 :metadata metadata))

(defun/i tool-calls (response)
  "Extract tool calls from a completion response.

RESPONSE - completion-response object from complete

Returns list of tool-call objects, or nil if no tool calls.

Example:
  (let* ((tools (list (define-tool \"get_weather\" ...)))
         (response (complete '((:role \"user\" :content \"What's the weather in Paris?\"))
                             :tools tools)))
    (when-let ((calls (tool-calls response)))
      (dolist (call calls)
        (format t \"Call ~A with ~A~%\"
                (tool-call-name call)
                (tool-call-arguments call)))))"
  (:feature tool-calling)
  (:purpose "Extract tool-call objects from completion response")
  (response-tool-calls response))

(defun/i make-tool-result (tool-call-id result &key is-error)
  "Create a tool result message to send back to the LLM.

TOOL-CALL-ID - ID from the original tool call (string)
RESULT - Result of executing the tool, typically JSON string
IS-ERROR - Whether this represents an error (boolean)

Returns a message plist suitable for inclusion in the messages list.

Example:
  (let* ((call (first (tool-calls response)))
         (result (make-tool-result
                  (tool-call-id call)
                  \"{\\\"temperature\\\": 22, \\\"unit\\\": \\\"celsius\\\"}\")))
    (complete (append original-messages
                      (list (response-message response))
                      (list result))))"
  (:feature tool-calling)
  (:purpose "Create tool result message for LLM conversation continuation")
  (let ((msg (list :role "tool"
                   :tool-call-id tool-call-id
                   :content result)))
    (if is-error
        (append msg (list :is-error t))
        msg)))

;;;; Internal Tool Validation

(defun/i validate-tool-definition (tool)
  "Validate a tool definition, signaling tool-schema-error if invalid.

TOOL - tool-definition object

Returns T if valid."
  (:feature tool-calling)
  (:purpose "Validate tool schema before sending to provider")
  (unless (and (tool-name tool)
               (stringp (tool-name tool))
               (not (string= (tool-name tool) "")))
    (restart-case
        (error 'tool-schema-error
               :tool tool
               :reason "Tool name must be a non-empty string")
      (skip-validation ()
        :report "Skip this validation check"
        nil)
      (use-value (v)
        :report "Supply a corrected tool name"
        :interactive (lambda ()
                       (format t "Enter tool name: ")
                       (list (read-line)))
        (setf (slot-value tool 'name) v))))

  (unless (and (tool-description tool)
               (stringp (tool-description tool)))
    (restart-case
        (error 'tool-schema-error
               :tool tool
               :reason "Tool description must be a string")
      (skip-validation ()
        :report "Skip this validation check"
        nil)
      (use-value (v)
        :report "Supply a corrected description"
        :interactive (lambda ()
                       (format t "Enter description: ")
                       (list (read-line)))
        (setf (slot-value tool 'description) v))))

  (unless (listp (tool-parameters tool))
    (restart-case
        (error 'tool-schema-error
               :tool tool
               :reason "Tool parameters must be a list")
      (skip-validation ()
        :report "Skip this validation check"
        nil)))

  ;; Validate each parameter
  (dolist (param (tool-parameters tool))
    (unless (getf param :name)
      (restart-case
          (error 'tool-schema-error
                 :tool tool
                 :reason (format nil "Parameter missing :name: ~S" param))
        (skip-validation ()
          :report "Skip this validation check"
          nil)))

    (unless (getf param :type)
      (restart-case
          (error 'tool-schema-error
                 :tool tool
                 :reason (format nil "Parameter missing :type: ~S" param))
        (skip-validation ()
          :report "Skip this validation check"
          nil)))

    (unless (member (getf param :type)
                    '(:string :integer :number :boolean :array :object))
      (restart-case
          (error 'tool-schema-error
                 :tool tool
                 :reason (format nil "Invalid parameter type ~S (must be one of :string, :integer, :number, :boolean, :array, :object)"
                                 (getf param :type)))
        (skip-validation ()
          :report "Skip this validation check"
          nil))))

  ;; Validate required list
  (when (tool-required-params tool)
    (unless (every #'stringp (tool-required-params tool))
      (restart-case
          (error 'tool-schema-error
                 :tool tool
                 :reason "Required parameter names must be strings")
        (skip-validation ()
          :report "Skip this validation check"
          nil))))

  t)

(defun/i validate-tools (tools)
  "Validate a list of tool definitions.

TOOLS - List of tool-definition objects

Returns T if all valid, signals tool-schema-error otherwise."
  (:feature tool-calling)
  (:purpose "Validate all tools in a set before API call")
  (dolist (tool tools)
    (restart-case
        (validate-tool-definition tool)
      (skip-invalid-tool ()
        :report (lambda (s)
                  (format s "Skip invalid tool ~A and continue"
                          (handler-case (tool-name tool) (error () "???"))))
        nil)))
  t)
