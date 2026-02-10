;;; ABOUTME: Tool category constants, helpers, and safety level utilities
(in-package :cl-llm-provider.tools)

;;;; Predefined Tool Categories

(defvar *tool-categories*
  '(:search           ; Information retrieval and search
    :database         ; Database operations (query, insert, update)
    :filesystem       ; File system access (read, write, delete)
    :network          ; Network/HTTP operations
    :calculation      ; Math and computation
    :destructive      ; Data deletion or irreversible modification
    :authentication   ; Auth and identity operations
    :payment          ; Financial transactions
    :admin            ; Administrative actions
    :external-api     ; Third-party API calls
    :ai               ; AI/ML operations
    :messaging)       ; Email, SMS, notifications
  "Predefined tool categories. Custom categories are also allowed.
   Categories help organize tools and enable filtering when selecting
   which tools to provide to an LLM.")

(defun valid-category-p (category)
  "Check if CATEGORY is a valid category keyword.
   Both predefined and custom categories are valid - this just ensures
   the value is a keyword symbol."
  (keywordp category))

(defun normalize-categories (categories)
  "Normalize CATEGORIES to a list of valid category keywords.
   - NIL -> NIL
   - Single keyword -> (keyword)
   - List of keywords -> validated list
   Signals error for invalid category values."
  (cond
    ((null categories) nil)
    ((keywordp categories) (list categories))
    ((listp categories)
     (loop for cat in categories
           unless (keywordp cat)
             do (error "Invalid category ~S: must be a keyword" cat)
           collect cat))
    (t (error "Invalid categories specification: ~S" categories))))

;;;; Safety Levels

(defvar *safety-level-order*
  '(:safe :moderate :dangerous)
  "Safety levels in order from least to most dangerous.")

(defun/i safety-level-value (level)
  "Return numeric value for safety level (for comparison).
   :safe -> 0, :moderate -> 1, :dangerous -> 2"
  (:feature tool-calling)
  (:purpose "Convert safety level keyword to numeric value for comparison")
  (or (position level *safety-level-order*)
      (error "Invalid safety level: ~S (must be :safe, :moderate, or :dangerous)" level)))

(defun/i safety-level<= (level1 level2)
  "Check if LEVEL1 is less than or equal to LEVEL2 in danger.
   E.g., (safety-level<= :safe :moderate) => T
         (safety-level<= :dangerous :safe) => NIL"
  (:feature tool-calling)
  (:purpose "Compare safety levels for access control decisions")
  (<= (safety-level-value level1) (safety-level-value level2)))

(defun valid-safety-level-p (level)
  "Check if LEVEL is a valid safety level keyword."
  (member level *safety-level-order*))

(defun normalize-safety-level (level &optional (default :safe))
  "Normalize LEVEL to a valid safety level, using DEFAULT if NIL."
  (let ((actual (or level default)))
    (unless (valid-safety-level-p actual)
      (error "Invalid safety level: ~S (must be :safe, :moderate, or :dangerous)" actual))
    actual))
