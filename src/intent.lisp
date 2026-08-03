;;; ABOUTME: Self-contained intent annotations for cl-llm-provider.
;;;
;;; This package owns the annotation macros outright. It is deliberately NOT the
;;; TELOS package and never inspects whether a real telos is loaded.
;;;
;;; The predecessor (telos-shim.lisp) squatted the TELOS package when real telos
;;; was absent, guarded by (unless (fboundp 'defun/i)). That guard was evaluated
;;; twice and independently — once at compile time, once at load time — so the
;;; two could disagree. Worse, the shim and the real telos expanded to
;;; structurally incompatible code, which made every fasl valid ONLY in an image
;;; whose telos-presence matched the one that compiled it. ASDF models no such
;;; dependency, so it could not invalidate on it, and a build in one project
;;; silently poisoned the shared ~/.cache/common-lisp for every other project.
;;; Both load orders were broken (measured: 2 of 4 combinations died with
;;; TELOS::*FEATURE-NAMES* unbound or TELOS::MAKE-INTENT undefined).
;;;
;;; Two invariants fix it, and both are worth preserving:
;;;   1. EVERY MACRO HERE EXPANDS TO A CALL ON A FUNCTION DEFINED IN THIS FILE.
;;;      No expansion names an external package, so a compiled fasl is valid in
;;;      any image regardless of load order.
;;;   2. NOTHING HERE RUNS AT COMPILE TIME except macroexpansion itself, so
;;;      there is no compile-time state left that could disagree with load time.
;;;
;;; Real telos integration is a separate, runtime-only concern — see the optional
;;; "cl-llm-provider/telos" system.
;;;
;;; Regression test: tests/test-load-order.sh

(in-package :cl-user)

(defpackage :cl-llm-provider.intent
  (:use :cl)
  (:documentation
   "Intent annotations recorded by cl-llm-provider. Self-contained by design:
    nothing here depends on the telos system being present.")
  (:export #:defun/i
           #:define-condition/i
           #:defintent
           #:deffeature
           #:get-intent
           #:intent-kind
           #:list-intents
           #:list-features
           #:feature-intent
           #:record-intent
           #:record-feature
           #:malformed-annotation
           #:malformed-annotation-context
           #:malformed-annotation-detail))

(in-package :cl-llm-provider.intent)

;;; Registries.
;;;
;;; These are LOAD-TIME registries: written single-threaded by macro expansions
;;; as each file loads, read-only thereafter. The tables are synchronized as
;;; cheap protection for the tables themselves, but that is NOT a claim that
;;; RECORD-INTENT / RECORD-FEATURE are safe to call concurrently — *feature-names*
;;; is an unguarded list and PUSHNEW on it would lose updates. This package
;;; deliberately has no dependencies (it is the system's first component), so it
;;; takes no lock. Annotate at load time.
;;;
;;; DEFVAR rather than DEFPARAMETER: reloading this file must not erase
;;; annotations already recorded by files loaded after it.

(defvar *intents* (make-hash-table :test 'eq :synchronized t)
  "Symbol -> intent plist recorded by defun/i, define-condition/i, defintent.")

(defvar *intent-kinds* (make-hash-table :test 'eq :synchronized t)
  "Symbol -> :function | :condition | :symbol. Which namespace the intent
   describes, so the optional telos bridge can file it in the right registry.")

(defvar *feature-declarations* (make-hash-table :test 'eq :synchronized t)
  "Feature symbol -> declaration plist recorded by deffeature.")

(defvar *feature-names* '()
  "Feature symbols recorded by deffeature, newest first.")

;;; The recognised vocabularies. These are checked at macroexpansion time: a
;;; keyword can never name a function, so an unrecognised clause is always a typo,
;;; and accepting it silently would drop BOTH the intent and — for a clause
;;; written among the body forms — the form itself.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *intent-clause-keys*
    '(:feature :role :purpose :goals :constraints :assumptions
      :failure-modes :verification)
    "Clause keys accepted by defun/i, define-condition/i and defintent.")

  (defparameter *feature-clause-keys*
    '(:purpose :goals :constraints :assumptions :failure-modes :verification
      :belongs-to :decisions)
    "Keys accepted by deffeature.")

  (define-condition malformed-annotation (program-error)
    ((context :initarg :context :reader malformed-annotation-context)
     (detail  :initarg :detail  :reader malformed-annotation-detail))
    (:report (lambda (c stream)
               (format stream "~A: ~A"
                       (malformed-annotation-context c)
                       (malformed-annotation-detail c))))
    (:documentation
     "Signalled at macroexpansion time for an annotation that cannot mean what
      it appears to mean — an unknown clause key, an odd-length declaration."))

  (defun annotation-error (context fmt &rest args)
    (error 'malformed-annotation
           :context context
           :detail (apply #'format nil fmt args))))

;;; Recording functions. The macros below expand to calls on THESE — never to
;;; forms naming the specials directly — so an expansion carries no dependency
;;; beyond this package.

(defun record-intent (symbol plist &optional kind)
  "Record PLIST as the intent of SYMBOL. Returns SYMBOL.

   KIND, when supplied, names the namespace (:function or :condition). An
   already-recorded kind is never downgraded: defintent retrofits intent onto
   things defun/i already classified, and must not overwrite that with :symbol."
  (setf (gethash symbol *intents*) plist)
  (when (or kind (not (nth-value 1 (gethash symbol *intent-kinds*))))
    (setf (gethash symbol *intent-kinds*) (or kind :symbol)))
  symbol)

(defun record-feature (name plist)
  "Record NAME as a feature with declaration PLIST. Returns NAME.
   Re-declaring a feature updates it in place and does not duplicate the name."
  (setf (gethash name *feature-declarations*) plist)
  (pushnew name *feature-names*)
  name)

(defun get-intent (symbol)
  "Return the recorded intent plist for SYMBOL, or NIL."
  (gethash symbol *intents*))

(defun intent-kind (symbol)
  "Return :function, :condition or :symbol for SYMBOL's recorded intent, or NIL."
  (gethash symbol *intent-kinds*))

(defun list-intents ()
  "Return the symbols carrying a recorded intent."
  (loop for symbol being the hash-keys of *intents* collect symbol))

(defun feature-intent (name)
  "Return the recorded declaration plist for feature NAME, or NIL."
  (gethash name *feature-declarations*))

(defun list-features ()
  "Return the list of feature symbols recorded by deffeature, oldest first."
  (reverse *feature-names*))

;;; Macro support. These run at macroexpansion time, so they must exist at
;;; compile time of every file that uses the macros — including this one.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun check-clause-keys (context plist allowed)
    "Signal unless PLIST is an even-length list keyed only by ALLOWED keywords."
    (unless (evenp (length plist))
      (annotation-error context "odd-length declaration ~S." plist))
    (loop for (key nil) on plist by #'cddr
          unless (member key allowed)
            do (annotation-error
                context "unrecognized key ~S (expected one of ~{~S~^ ~})."
                key allowed)))

  (defun clause-value (clause)
    "The value half of an intent clause. (:key v) yields V; (:key a b) yields
     (A B), so a multi-entry clause like (:goals (:a \"x\") (:b \"y\")) keeps
     every entry. THE ONE definition of this rule — defun/i and
     define-condition/i must not disagree about what the same syntax means."
    (if (rest (rest clause))
        (rest clause)
        (second clause)))

  (defun split-intent-clauses (body context)
    "Split BODY into (values intent-plist docstring declarations clean-body).

     Declarations are popped BEFORE intent clauses are parsed, so
       (defun/i f (x) \"doc\" (declare (ignore x)) (:purpose \"p\") ...)
     and the reverse order both work. Parsing clauses only before declarations
     would compile a trailing (:purpose \"p\") as a live function call — it is
     legal-looking code that fails at runtime, not at compile time."
    (let ((doc nil)
          (declarations '()))
      (when (and (stringp (first body)) (rest body))
        (setf doc (pop body)))
      (loop while (and (consp (first body)) (eq 'declare (first (first body))))
            do (push (pop body) declarations))
      (let ((intent
              (loop while (and (consp (first body))
                               (keywordp (first (first body))))
                    nconc (let ((clause (pop body)))
                            (list (first clause) (clause-value clause))))))
        (check-clause-keys context intent *intent-clause-keys*)
        (values intent doc (nreverse declarations) body)))))

(defmacro defun/i (name lambda-list &body body)
  "DEFUN with leading (:keyword ...) intent clauses recorded, then stripped.
   Clauses may appear before or after a DECLARE. An unrecognised clause key is
   an error, not a silently discarded body form."
  (multiple-value-bind (intent doc declarations clean-body)
      (split-intent-clauses body (format nil "DEFUN/I ~S" name))
    `(progn
       (record-intent ',name ',intent :function)
       (defun ,name ,lambda-list
         ,@(when doc (list doc))
         ,@declarations
         ,@clean-body))))

(defmacro define-condition/i (name supers slots &rest options)
  "DEFINE-CONDITION with intent options recorded, then stripped.
   Recognises the same clause vocabulary as defun/i; every other option is
   passed through to CL:DEFINE-CONDITION untouched."
  (let ((intent (loop for opt in options
                      when (and (consp opt)
                                (member (first opt) *intent-clause-keys*))
                        nconc (list (first opt) (clause-value opt))))
        (clean (remove-if (lambda (opt)
                            (and (consp opt)
                                 (member (first opt) *intent-clause-keys*)))
                          options)))
    (check-clause-keys (format nil "DEFINE-CONDITION/I ~S" name)
                       intent *intent-clause-keys*)
    `(progn
       (record-intent ',name ',intent :condition)
       (define-condition ,name ,supers ,slots ,@clean))))

(defmacro defintent (name &rest args)
  "Record ARGS as the intent of the already-defined NAME.
   Does not assert a kind: NAME may be a function, a class or a condition, and
   whatever defun/i or define-condition/i already recorded stands."
  (check-type name symbol)
  (check-clause-keys (format nil "DEFINTENT ~S" name) args *intent-clause-keys*)
  `(progn
     (record-intent ',name ',args)
     ',name))

(defmacro deffeature (name &rest args)
  "Declare NAME as a feature, recording ARGS (a keyword plist) verbatim.
   ARGS is kept rather than discarded so the optional cl-llm-provider/telos
   bridge can replay these declarations into a real telos at runtime."
  (check-type name symbol)
  (check-clause-keys (format nil "DEFFEATURE ~S" name) args *feature-clause-keys*)
  `(progn
     (record-feature ',name (list ,@(mapcar (lambda (x) `',x) args)))
     ',name))
