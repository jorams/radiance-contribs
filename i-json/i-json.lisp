#|
 This file is a part of Radiance
 (c) 2014 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:modularize-user)
(define-module #:i-json
    (:use #:cl #:radiance))
(in-package #:i-json)

(defgeneric serialize (o)
  (:method (o) o)
  (:method ((o string)) o)
  (:method ((o list))
    (mapcar #'serialize o))
  (:method ((o vector))
    (loop for i from 0 below (length o)
          collect (serialize (aref o i))))
  (:method ((o hash-table))
    (loop with n = (make-hash-table :test (hash-table-test o))
          for k being the hash-keys of o
          for v being the hash-values of o
          do (setf (gethash (serialize k) n)
                   (serialize v))
          finally (return n)))
  (:method ((o condition))
    (loop with n = (make-hash-table)
          for d in (c2mop:class-slots (class-of o))
          for s = (c2mop:slot-definition-name d)
          for v = (slot-value o s)
          do (setf (gethash (serialize s) n)
                   (serialize v))
          finally (return n)))
  (:method ((o standard-object))
    ;; We don't want secure data leaking out...
    (princ-to-string o))
  (:method ((o function))
    (princ-to-string o))
  (:method ((o pathname))
    (princ-to-string o)))

(define-api-format json (object)
  (setf (content-type *response*) "application/json; charset=utf-8")
  (with-output-to-string (stream)
    (cl-json:encode-json (serialize object) stream)))

(setf *default-api-format* "json")
