;;; ABOUTME: Tool registry class for central tool management with search/filter capabilities
(in-package :cl-llm-provider.tools)

;;;; Tool Registry Class

(defclass tool-registry ()
  ((tools :initform (make-hash-table :test 'equal)
          :type hash-table
          :accessor registry-tools
          :documentation "Hash table mapping tool names to tool-definition objects.")
   (name :initarg :name
         :initform "default"
         :type string
         :reader registry-name
         :documentation "Human-readable registry name.")
   (description :initarg :description
                :initform nil
                :type (or string null)
                :reader registry-description
                :documentation "Description of this tool registry.")
   (default-safety-level :initarg :default-safety-level
                         :initform :safe
                         :type keyword
                         :accessor registry-default-safety-level
                         :documentation "Default safety level for tools without explicit level.")
   (approval-callback :initarg :approval-callback
                      :initform nil
                      :type (or function null)
                      :accessor registry-approval-callback
                      :documentation "Default approval callback for tools requiring approval.")
   (global-hooks :initarg :global-hooks
                 :initform nil
                 :type list
                 :accessor registry-global-hooks
                 :documentation "Plist of global lifecycle hooks (:on-start fn :on-complete fn :on-error fn)."))
  (:documentation "Central registry for tool definitions with search and filtering capabilities."))

(defmethod print-object ((registry tool-registry) stream)
  (print-unreadable-object (registry stream :type t)
    (format stream "~A (~D tools)"
            (registry-name registry)
            (hash-table-count (registry-tools registry)))))

;;;; Global Registry

(defvar *tool-registry* nil
  "Global tool registry instance. Create with (make-tool-registry).")

(defun make-tool-registry (&key name description default-safety-level approval-callback global-hooks)
  "Create a new tool registry.

   NAME - Human-readable name for the registry
   DESCRIPTION - Description of the registry's purpose
   DEFAULT-SAFETY-LEVEL - Default safety level for registered tools (:safe, :moderate, :dangerous)
   APPROVAL-CALLBACK - Default approval callback function
   GLOBAL-HOOKS - Plist of global lifecycle hooks"
  (make-instance 'tool-registry
                 :name (or name "default")
                 :description description
                 :default-safety-level (or default-safety-level :safe)
                 :approval-callback approval-callback
                 :global-hooks global-hooks))

(defun ensure-registry ()
  "Ensure *tool-registry* exists, creating default if needed.
   Returns the global registry."
  (unless *tool-registry*
    (setf *tool-registry* (make-tool-registry :name "global")))
  *tool-registry*)

;;;; Registry Operations (Generic Functions)

(defgeneric register-tool (registry tool &key replace)
  (:documentation "Register a tool in the registry.
   If REPLACE is NIL (default) and a tool with the same name exists,
   signals an error. If REPLACE is T, replaces the existing tool.
   Returns the tool."))

(defgeneric unregister-tool (registry tool-name)
  (:documentation "Remove a tool from the registry by name.
   Returns the removed tool-definition or NIL if not found."))

(defgeneric find-tool (registry name)
  (:documentation "Find a tool by exact name.
   Returns tool-definition or NIL if not found."))

(defgeneric search-tools (registry &key name-pattern description-pattern
                                        categories safety-level max-safety-level)
  (:documentation "Search for tools matching criteria.
   NAME-PATTERN - Substring to match tool names (case-insensitive)
   DESCRIPTION-PATTERN - Substring to match descriptions (case-insensitive)
   CATEGORIES - List of categories (tools must have at least one)
   SAFETY-LEVEL - Exact safety level match
   MAX-SAFETY-LEVEL - Maximum safety level (exclude more dangerous tools)
   Returns list of matching tool-definition objects."))

(defgeneric list-tools (registry &key categories safety-level)
  (:documentation "List all tools, optionally filtered by categories or safety level.
   Returns list of tool-definition objects."))

(defgeneric registry-tool-count (registry)
  (:documentation "Return the number of tools in the registry."))

;;;; Method Implementations

(defmethod register-tool ((registry tool-registry) (tool tool-definition) &key replace)
  "Register a tool in the registry."
  (let* ((name (tool-name tool))
         (existing (gethash name (registry-tools registry))))
    (when (and existing (not replace))
      (error "Tool ~S already registered in registry ~S. Use :replace t to overwrite."
             name (registry-name registry)))
    (setf (gethash name (registry-tools registry)) tool)
    tool))

(defmethod unregister-tool ((registry tool-registry) (tool-name string))
  "Remove a tool from the registry by name."
  (let ((tool (gethash tool-name (registry-tools registry))))
    (when tool
      (remhash tool-name (registry-tools registry)))
    tool))

(defmethod find-tool ((registry tool-registry) (name string))
  "Find a tool by exact name."
  (gethash name (registry-tools registry)))

(defmethod registry-tool-count ((registry tool-registry))
  "Return the number of tools in the registry."
  (hash-table-count (registry-tools registry)))

(defmethod search-tools ((registry tool-registry)
                         &key name-pattern description-pattern
                              categories safety-level max-safety-level)
  "Search for tools matching criteria."
  (let ((results nil))
    (maphash
     (lambda (name tool)
       (declare (ignore name))
       (when (tool-matches-p tool
                             :name-pattern name-pattern
                             :description-pattern description-pattern
                             :categories categories
                             :safety-level safety-level
                             :max-safety-level max-safety-level)
         (push tool results)))
     (registry-tools registry))
    (nreverse results)))

(defmethod list-tools ((registry tool-registry) &key categories safety-level)
  "List all tools, optionally filtered."
  (if (or categories safety-level)
      (search-tools registry :categories categories :safety-level safety-level)
      (let ((results nil))
        (maphash (lambda (name tool)
                   (declare (ignore name))
                   (push tool results))
                 (registry-tools registry))
        (nreverse results))))

;;;; Helper Functions

(defun tool-matches-p (tool &key name-pattern description-pattern
                                 categories safety-level max-safety-level)
  "Check if TOOL matches the given search criteria."
  (and
   ;; Name pattern (case-insensitive substring)
   (or (null name-pattern)
       (search (string-downcase name-pattern)
               (string-downcase (tool-name tool))))

   ;; Description pattern (case-insensitive substring)
   (or (null description-pattern)
       (search (string-downcase description-pattern)
               (string-downcase (tool-description tool))))

   ;; Categories (tool must have at least one of the specified categories)
   (or (null categories)
       (intersection categories (tool-categories tool)))

   ;; Exact safety level
   (or (null safety-level)
       (eq safety-level (tool-safety-level tool)))

   ;; Maximum safety level
   (or (null max-safety-level)
       (safety-level<= (tool-safety-level tool) max-safety-level))))

;;;; Convenience Functions

(defun register (tool &key (registry (ensure-registry)) replace)
  "Register a tool in the global or specified registry.

   TOOL - tool-definition object to register
   REGISTRY - registry to use (defaults to global)
   REPLACE - if T, replace existing tool with same name

   Returns the registered tool."
  (register-tool registry tool :replace replace))

(defun find-tool-by-name (name &key (registry (ensure-registry)))
  "Find a tool by name in the global or specified registry."
  (find-tool registry name))

(defun tools-by-category (category &key (registry (ensure-registry)))
  "Get all tools with a specific category."
  (search-tools registry :categories (list category)))

(defun safe-tools (&key (registry (ensure-registry)))
  "Get all tools with :safe safety level."
  (search-tools registry :max-safety-level :safe))

(defun tools-for-llm (&key (registry (ensure-registry))
                           max-safety-level
                           categories
                           exclude-requiring-approval)
  "Get tools suitable for passing to complete, with optional filtering.

   REGISTRY - registry to search (defaults to global)
   MAX-SAFETY-LEVEL - exclude tools more dangerous than this level
   CATEGORIES - only include tools with at least one of these categories
   EXCLUDE-REQUIRING-APPROVAL - if T, exclude tools that require approval

   Returns list of tool-definition objects."
  (let ((tools (search-tools registry
                             :max-safety-level max-safety-level
                             :categories categories)))
    (if exclude-requiring-approval
        (remove-if #'needs-approval-p tools)
        tools)))
