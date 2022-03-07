(in-package :utils)

(defvar *default-worker-num* (max 4 (cpus:get-number-of-processors)))

(defparameter *default-keepalive-time* 60
  "Default value for the idle worker thread keepalive time. Note that it's cpu time, not real time.")

(defmacro unwind-protect-unwind-only (protected-form &body cleanup-forms)
  "Like UNWIND-PROTECT, but CLEANUP-FORMS are not executed if a normal return occurs."
  (let ((abnormal-return (gensym "ABNORMAL-RETURN")))
    `(let ((,abnormal-return t))
       (unwind-protect
            (multiple-value-prog1
                ,protected-form
              (setf ,abnormal-return nil))
         (when ,abnormal-return
           ,@cleanup-forms)))))

#+:sbcl
(defun peek-queue (queue)
  (cadr (sb-concurrency::queue-head queue)))

#+:sbcl
(defun flush-queue (queue)
  "Flush the queue to an empty queue."
  (declare (optimize speed))
  (loop (let* ((head (sb-concurrency::queue-head queue))
               (tail (sb-concurrency::queue-tail queue))
               (next (cdr head)))
          (typecase next
            (null (return nil))
            (cons (when (and (eq head (sb-ext:compare-and-swap (sb-concurrency::queue-head queue)
                                                               head head))
                             (eq nil (sb-ext:compare-and-swap (cdr (sb-concurrency::queue-tail queue))
                                                              nil nil)))
                    (setf (car tail) sb-concurrency::+dummy+
                          (sb-concurrency::queue-head queue) (sb-concurrency::queue-tail queue))
                    (return t)))))))
