(in-package :tpool-utils)

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


;;; hash
(defun make-hash ()
  #+sbcl(make-hash-table :weakness :value :synchronized t)
  #+ccl(make-hash-table :weak :value))


;;; fifo queue apis for safe accessing

(defun make-queue (&optional (unbound t))
  "Return an unbound"
  (declare (ignore unbound))
  #+sbcl(sb-concurrency:make-queue)
  #-sbcl(cl-fast-queues:make-safe-fifo))

(defun peek-queue (queue)
  "Return the first item to be dequeued without dequeueing it"
  #+sbcl(cadr (sb-concurrency::queue-head queue))
  #-sbcl(cl-fast-queues:queue-peek queue))

(defun enqueue (item queue)
  #+sbcl(sb-concurrency:enqueue item queue)
  #-sbcl(cl-fast-queues:enqueue item queue))

(defun dequeue (queue)
  #+sbcl(sb-concurrency:dequeue queue)
  #-sbcl(alexandria:when-let (val (cl-fast-queues:dequeue queue))
          (if (eq val cl-fast-queues:*underflow-flag*)
              nil
              val)))

(defun queue-count (queue)
  #+sbcl(sb-concurrency:queue-count queue)
  #-sbcl(cl-fast-queues:queue-count queue))

(defun queue-to-list (queue)
  #+sbcl(sb-concurrency:list-queue-contents queue)
  #-sbcl(cl-fast-queues:queue-to-list queue))

(defun flush-queue (queue)
  "Flush the queue to an empty queue. The returned value should be neglected."
  (declare (optimize speed))
  #+sbcl
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
                    (return t))))))
  #-sbcl(cl-fast-queues:queue-flush queue))

(defun queue-empty-p (queue)
  #+sbcl(sb-concurrency:queue-empty-p queue)
  #-sbcl(cl-fast-queues:queue-empty-p queue))

#-sbcl
(defun sfifo-dequeue (queue)
  "dequeue safe-fast-fifo"
  (alexandria:when-let (val (cl-fast-queues:dequeue queue))
    (if (eq val cl-fast-queues:*underflow-flag*)
        nil
        val)))


;;; atomic operations

(defun make-atomic (init-value)
  "Return a structure that can be cas'ed"
  #+ccl
  (make-array 1 :initial-element init-value)
  #-ccl
  (cons init-value nil))

(defmacro atomic-place (atomic-structure)
  "Return value of atomic-fixnum in macro."
  #+ccl
  `(svref ,atomic-structure 0)
  #-ccl
  `(car ,atomic-structure))

(defmacro atomic-incf (place &optional (diff 1))
  "Atomic incf fixnum in `place' with `diff' and return OLD value."
  #+sbcl
  `(sb-ext:atomic-incf ,place ,diff)
  #+ccl
  `(let ((old ,place))
     (ccl::atomic-incf-decf ,place ,diff)
     old))

(defmacro atomic-decf (place &optional (diff 1))
  "Atomic decf fixnum in `place' with `diff' and return OLD value."
  #+sbcl
  `(sb-ext:atomic-decf ,place ,diff)
  #+ccl
  `(let ((old ,place))
     (ccl::atomic-incf-decf ,place (- ,diff))
     old))

#+ccl
(defmacro compare-and-swap (place old-value new-value)
  "Atomically stores NEW in `place' if `old-value' matches the current value of `place'.
Two values are considered to match if they are EQ.
return T if swap success, otherwise return NIL."
  `(ccl::conditional-store ,place ,old-value ,new-value))

(defmacro atomic-update (place function &rest args)
  "Atomic swap value in `place' with `function' called and return new value."
  #+sbcl
  `(sb-ext:atomic-update ,place ,function ,@args)
  #-sbcl
  (alexandria:with-gensyms (func old-value new-value)
    `(loop :with ,func = ,function
           :for ,old-value = ,place
           :for ,new-value = (funcall ,func ,old-value ,@args)
           :until (compare-and-swap ,place ,old-value ,new-value)
           :finally (return ,new-value))))


;; bordeaux-threads' condition-wait will always return T whether timeout or not,
;; but get-result and thread-pool-main rely on the returned value of condition-wait,
;; and thus this is roughly fixed.
#+ccl
(defun condition-wait (condition-variable lock &key timeout)
  (bt:release-lock lock)
  (let ((success nil))
    (unwind-protect
         (setf success (if timeout
                           (ccl:timed-wait-on-semaphore condition-variable timeout)
                           (ccl:wait-on-semaphore condition-variable)))
      (bt:acquire-lock lock t))
    success))

(defmacro make-nullary (() &body body)
  "Make up a nullary function which accept none args."
  `(lambda () ,@body))

(defmacro make-unary ((arg) &body body)
  "Make up a unary function which accept exactly one argument.
`arg' is the parameter used within `body'."
  ;; (funcall (make-unary (a) (* a a)) 3)
  `(lambda (,arg)
     (declare (ignorable ,arg))
     ,@body))
