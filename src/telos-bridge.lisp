;;; ABOUTME: Optional runtime bridge publishing cl-llm-provider's recorded
;;; intents into a real telos. Part of the "cl-llm-provider/telos" system.
;;;
;;; This is deliberately a RUNTIME bridge, not a compile-time one. cl-llm-provider
;;; proper never uses telos's macros, so none of its fasls carry a telos
;;; reference and their validity does not depend on load order — which is the
;;; whole point (see src/intent.lisp). Everything telos-specific is confined to
;;; this file, in a system that declares :telos as a real ASDF dependency, so
;;; ASDF can model and invalidate it properly.
;;;
;;; Fidelity is the requirement here, not just "it loads". Before real telos was
;;; displaced, a telos-first image got feature intents, feature MEMBERSHIP,
;;; feature DECISIONS, and classes filed as classes. A bridge that publishes only
;;; the first of those is a regression nobody notices, because the queries
;;; succeed and quietly return nothing.

(in-package :cl-user)

(defpackage :cl-llm-provider.telos-bridge
  (:use :cl)
  (:documentation "Publishes cl-llm-provider's intent annotations into telos.")
  (:export #:publish-to-telos
           #:telos-publication-error
           #:publication-error-subject
           #:publication-error-cause
           #:skip-annotation))

(in-package :cl-llm-provider.telos-bridge)

;;; telos exposes no programmatic registration API — its registries are written
;;; only by its macros — so the bridge reaches three internal symbols. Check them
;;; once, at load, with a message that names the incompatibility. Without this a
;;; telos rename surfaces as an undefined-function error mid-publication, which
;;; is how the bug this whole change fixes used to present.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (dolist (name '("REGISTER-FEATURE" "REGISTER-ENTITY-INTENT" "REGISTER-MEMBER"
                  "REPLACE-FEATURE-DECISIONS" "CLASSIFY-SYMBOL-INTENT-TARGET"
                  "*CLASS-INTENT-REGISTRY*"))
    (let ((symbol (find-symbol name :telos)))
      (unless (and symbol (or (fboundp symbol) (boundp symbol)))
        (error "cl-llm-provider/telos needs TELOS::~A, which this telos does not ~
                provide. The bridge is built against telos 1.2.x internals."
               name)))))

(defparameter *intent-keys*
  '(:purpose :goals :constraints :assumptions :failure-modes :verification
    :belongs-to :role :members)
  "The slots of TELOS:INTENT, and so exactly the keys TELOS:MAKE-INTENT accepts.
   :decisions is recorded by deffeature but lives in a separate telos registry,
   so PUBLISH-DECISIONS handles it rather than it being dropped here.")

(define-condition telos-publication-error (error)
  ((subject :initarg :subject :reader publication-error-subject)
   (cause   :initarg :cause   :reader publication-error-cause))
  (:report (lambda (c stream)
             (format stream "Could not publish ~S into telos: ~A"
                     (publication-error-subject c)
                     (publication-error-cause c))))
  (:documentation
   "One annotation could not be published. Signalled with a SKIP-ANNOTATION
    restart so a single malformed declaration cannot abort the whole system
    load."))

(defmacro with-annotation-restart ((subject) &body body)
  "Run BODY; on error signal TELOS-PUBLICATION-ERROR offering SKIP-ANNOTATION.
   Returns 1 if BODY completed, 0 if it was skipped, so callers can count.

   Do NOT nest these: FIND-RESTART picks the innermost SKIP-ANNOTATION, so an
   outer form would resume and report a publication that did not happen."
  (let ((condition (gensym "CONDITION"))
        (subject-value (gensym "SUBJECT")))
    ;; SUBJECT is bound once: it appears in both the handler and the :report
    ;; lambda, and evaluating a caller's form twice per skip is the Double-Tap.
    `(let ((,subject-value ,subject))
       (restart-case
           (handler-bind
               ((error (lambda (,condition)
                         (unless (typep ,condition 'telos-publication-error)
                           (error 'telos-publication-error
                                  :subject ,subject-value :cause ,condition)))))
             ,@body
             1)
         (skip-annotation ()
           :report (lambda (s)
                     (format s "Skip ~S and publish the rest." ,subject-value))
           0)))))

(defun plist-to-intent (plist)
  "Build a TELOS:INTENT from one of our recorded plists.
   :feature is our defun/i spelling of telos's :belongs-to. Keys telos's struct
   does not have are dropped — :decisions is the only one, and it is published
   separately."
  (let ((args '()))
    (loop for (key value) on plist by #'cddr
          for canonical = (if (eq key :feature) :belongs-to key)
          when (member canonical *intent-keys*)
            do (setf (getf args canonical) value))
    (apply #'telos:make-intent args)))

(defun publish-decisions (name plist)
  "Replay a feature's :decisions into telos's separate decision registry."
  (let ((decisions (getf plist :decisions)))
    (when decisions
      (telos::replace-feature-decisions
       name
       (mapcar (lambda (d)
                 (telos:make-decision :id (getf d :id)
                                      :chose (getf d :chose)
                                      :over (getf d :over)
                                      :because (getf d :because)
                                      :date (getf d :date)
                                      :decided-by (getf d :decided-by)))
               decisions)))))

(defun publish-features ()
  "Register every deffeature declaration, with its decisions, into telos.
   Returns the number published."
  (loop for name in (cl-llm-provider.intent:list-features)
        sum (with-annotation-restart (name)
              (let ((plist (cl-llm-provider.intent:feature-intent name)))
                (telos::register-feature name (plist-to-intent plist))
                (publish-decisions name plist)))))

(defun resolve-kind (symbol)
  "Decide which telos registry SYMBOL's intent belongs in.

   defun/i and define-condition/i recorded the kind directly. defintent did not —
   it retrofits intent onto something defined elsewhere, and in this library that
   is usually a CLOS class. Defer to telos's own classifier for those, so the
   bridge files things exactly where telos's defintent would have."
  (case (cl-llm-provider.intent:intent-kind symbol)
    (:condition :condition)
    (:function :function)
    (t (telos::classify-symbol-intent-target symbol))))

(defun publish-intent (symbol plist)
  "File one recorded intent in the right telos registry, and record it as a
   member of its feature so TELOS:FEATURE-MEMBERS can find it."
  (let ((kind (resolve-kind symbol))
        (intent (plist-to-intent plist)))
    ;; telos's defintent special-cases classes: they go in the class registry,
    ;; not through register-entity-intent. Mirror that exactly.
    (if (eq kind :class)
        (setf (gethash symbol telos::*class-intent-registry*) intent)
        (telos::register-entity-intent kind symbol intent))
    (telos::register-member (getf plist :feature) symbol kind)))

(defun publish-intents ()
  "Register every defun/i, define-condition/i and defintent annotation with
   telos. Returns the number published."
  (loop for symbol in (cl-llm-provider.intent:list-intents)
        for plist = (cl-llm-provider.intent:get-intent symbol)
        ;; An empty plist means the annotation carried no clauses; telos has
        ;; nothing to file, and a blank intent would only make GET-INTENT lie
        ;; about coverage.
        when plist
          sum (with-annotation-restart (symbol)
                (publish-intent symbol plist))))

(defun publish-to-telos (&key (on-error :skip))
  "Replay every annotation cl-llm-provider recorded into the loaded telos.
   Idempotent: re-running overwrites the same registry entries.
   Returns (values feature-count intent-count).

   ON-ERROR :skip (the default) warns about an annotation that cannot be
   published and continues with the rest — loading this system must not be able
   to abort a consumer's build over one malformed declaration. :signal lets the
   TELOS-PUBLICATION-ERROR through for a caller that wants to handle it.

   This is where the SKIP-ANNOTATION restart is actually invoked; offering a
   restart nobody drives would be a guarantee in the docstring only."
  (handler-bind
      ((telos-publication-error
         (lambda (condition)
           (when (eq on-error :skip)
             (warn "cl-llm-provider/telos: ~A" condition)
             (let ((restart (find-restart 'skip-annotation condition)))
               (when restart (invoke-restart restart)))))))
    (values (publish-features) (publish-intents))))

;;; Loading this system IS the request to publish. A plain toplevel form runs at
;;; load and never at compile — wrapping it in eval-when would reintroduce
;;; exactly the compile-time/load-time split this change exists to remove.
(publish-to-telos)
