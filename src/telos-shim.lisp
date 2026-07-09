;;; ABOUTME: Functional shim for the telos intent-annotation system.
;;; Loaded only when the real telos package is absent.

(in-package :cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package :telos)
    (defpackage :telos
      (:use :cl)
      (:export #:defun/i #:define-condition/i #:defintent #:deffeature
               #:get-intent #:list-features))
    (pushnew :telos-shim *features*)))

#+telos-shim
(in-package :telos)

#+telos-shim
(progn

(defvar *intents* (make-hash-table :test 'eq)
  "Symbol -> intent plist recorded by defun/i, define-condition/i, defintent.")

(defvar *feature-names* '()
  "Feature symbols recorded by deffeature, oldest first.")

(defun get-intent (symbol)
  "Return the recorded intent plist for SYMBOL, or NIL."
  (gethash symbol *intents*))

(defun list-features ()
  "Return the list of feature symbols recorded by deffeature."
  (reverse *feature-names*))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun split-intent-clauses (body)
    "Split BODY into (values intent-plist clean-body)."
    (let ((doc nil)
          (intent '()))
      (when (and (stringp (first body)) (rest body))
        (setf doc (pop body)))
      (loop while (and (consp (first body))
                       (keywordp (first (first body))))
            do (let ((clause (pop body)))
                 (setf intent
                       (append intent (list (first clause)
                                            (if (rest (rest clause))
                                                (rest clause)
                                                (second clause)))))))
      (values intent (if doc (cons doc body) body)))))

(defmacro defun/i (name lambda-list &body body)
  (multiple-value-bind (intent clean-body) (split-intent-clauses body)
    `(progn
       (setf (gethash ',name *intents*) ',intent)
       (defun ,name ,lambda-list ,@clean-body))))

(defmacro define-condition/i (name supers slots &rest options)
  (let ((intent (loop for opt in options
                      when (and (consp opt)
                                (member (first opt) '(:feature :purpose)))
                        append (list (first opt) (second opt))))
        (clean (remove-if (lambda (opt)
                            (and (consp opt)
                                 (member (first opt) '(:feature :purpose))))
                          options)))
    `(progn
       (setf (gethash ',name *intents*) ',intent)
       (define-condition ,name ,supers ,slots ,@clean))))

(defmacro defintent (name &rest args)
  `(progn
     (setf (gethash ',name *intents*) ',args)
     ',name))

(defmacro deffeature (name &rest args)
  (declare (ignore args))
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (pushnew ',name *feature-names*)
     ',name))

) ; end #+telos-shim progn
