(in-package :cl-llm-provider)

;;;; Tool Calling Support

(defun define-tool (name description parameters &key required)
  "Create a tool definition that can be passed to complete.

NAME - Tool/function name (string)
DESCRIPTION - What the tool does, used by LLM (string)
PARAMETERS - Parameter specifications as plists, each with:
  :name - Parameter name (string)
  :type - Parameter type (:string, :integer, :number, :boolean, :array, :object)
  :description - Parameter description (string)
  :enum - Optional list of allowed values
REQUIRED - List of required parameter names (list of strings)

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
    :required '(\"location\"))"
  (make-instance 'tool-definition
                 :name name
                 :description description
                 :parameters parameters
                 :required required))

(defun tool-calls (response)
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
  (response-tool-calls response))

(defun make-tool-result (tool-call-id result &key is-error)
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
  (list :role "tool"
        :tool-call-id tool-call-id
        :content result
        :is-error is-error))

;;;; Internal Tool Validation

(defun validate-tool-definition (tool)
  "Validate a tool definition, signaling tool-schema-error if invalid.

TOOL - tool-definition object

Returns T if valid."
  (unless (and (tool-name tool)
               (stringp (tool-name tool))
               (not (string= (tool-name tool) "")))
    (error 'tool-schema-error
           :tool tool
           :reason "Tool name must be a non-empty string"))

  (unless (and (tool-description tool)
               (stringp (tool-description tool)))
    (error 'tool-schema-error
           :tool tool
           :reason "Tool description must be a string"))

  (unless (listp (tool-parameters tool))
    (error 'tool-schema-error
           :tool tool
           :reason "Tool parameters must be a list"))

  ;; Validate each parameter
  (dolist (param (tool-parameters tool))
    (unless (getf param :name)
      (error 'tool-schema-error
             :tool tool
             :reason (format nil "Parameter missing :name: ~S" param)))

    (unless (getf param :type)
      (error 'tool-schema-error
             :tool tool
             :reason (format nil "Parameter missing :type: ~S" param)))

    (unless (member (getf param :type)
                    '(:string :integer :number :boolean :array :object))
      (error 'tool-schema-error
             :tool tool
             :reason (format nil "Invalid parameter type ~S (must be one of :string, :integer, :number, :boolean, :array, :object)"
                             (getf param :type)))))

  ;; Validate required list
  (when (tool-required-params tool)
    (unless (every #'stringp (tool-required-params tool))
      (error 'tool-schema-error
             :tool tool
             :reason "Required parameter names must be strings")))

  t)

(defun validate-tools (tools)
  "Validate a list of tool definitions.

TOOLS - List of tool-definition objects

Returns T if all valid, signals tool-schema-error otherwise."
  (dolist (tool tools)
    (validate-tool-definition tool))
  t)
