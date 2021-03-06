#|
 This file is a part of Radiance
 (c) 2014 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:i-postmodern)

(defvar *current-db* NIL)
(defvar *current-setting* NIL)
(defvar *pool-lock* (bt:make-lock "DATABASE-CONNECTIONS"))
(defvar *pool-available-condition* (bt:make-condition-variable :name "POOL-FREE-CONDITION"))
(defparameter db::*default-pool-size* 5)
(defvar *connection-pool* ())
(defvar *current-con* NIL)

(defun db::spawn-connection (host port user pass db)
  (bt:with-lock-held (*pool-lock*)
    (l:debug :database "Spawning connection for ~a~:[~;:*~]@~a:~a/~a" host port user pass db)
    (push (or (postmodern:connect db user pass host :port port)
              (error 'db:connection-failed :database *current-db*))
          *connection-pool*)))

(defun db::spawn-standard-connection (&optional (setting *current-setting*))
  (apply #'db::spawn-connection setting))

(defun acquire-connection ()
  (bt:with-lock-held (*pool-lock*)
    (loop for con = (pop *connection-pool*)
          until con
          do (l:debug :database "~a Waiting for connection."
                      (bt:current-thread))
             (bt:condition-wait *pool-available-condition* *pool-lock*)
             (l:debug :database "~a Received notification, hopefully getting a connection now."
                      (bt:current-thread))
          finally (progn
                    (l:debug :database "~a Acquired connection." (bt:current-thread))
                    (return con)))))

(defun release-connection (connection)
  (l:debug :database "~a Releasing connection." (bt:current-thread))
  (bt:with-lock-held (*pool-lock*)
    (push connection *connection-pool*))
  (bt:condition-notify *pool-available-condition*))

(defun call-with-connection (function)
  (if *current-con*
      (funcall function)
      (let* ((*current-con* (acquire-connection))
             (postmodern:*database* *current-con*))
        (unless (postmodern:connected-p *current-con*)
          (postmodern:reconnect *current-con*))
        (unwind-protect
             (funcall function)
          (release-connection *current-con*)))))

(defmacro with-connection (&body body)
  `(call-with-connection (lambda () ,@body)))

(defun db:connect (database-name)
  (with-simple-restart (skip "Skip connecting.")
    (flet ((err (msg) (error 'db:connection-failed :database database-name :message msg)))
      (let ((conn (config :connections database-name)))
        (unless conn (err "No such connection found."))
        (when *current-db*
          (warn 'database-connection-already-open :database database-name)
          (db:disconnect))
        ;; Spec restarts for already open.
        (let ((host (or (gethash :host conn) "localhost"))
              (port (or (gethash :port conn) 5432))
              (user (gethash :user conn))
              (pass (gethash :pass conn))
              (db (or (gethash :database conn) (err "No database configured!"))))
          (l:info :database "Connecting ~a ~a~:[~;:*~]@~a:~a/~a"
                  database-name user pass host port db)
          (setf *current-setting* (list host port user pass db)
                *current-db* database-name)
          (dotimes (i db::*default-pool-size*)
            (sleep 0.5)
            (db::spawn-standard-connection))
          (trigger 'db:connected database-name))))))

(defun db:disconnect ()
  (let ((database-name *current-db*))
    (l:info :database "Disconnecting ~a" database-name)
    (bt:with-lock-held (*pool-lock*)
      (loop for con = (pop *connection-pool*)
            while con
            do (postmodern:disconnect con)))
    (setf *current-con* NIL
          *current-setting* NIL
          *current-db* NIL)
    (trigger 'db:disconnected database-name)))

(defun db:connected-p ()
  (not (null *current-db*)))
