(in-package :tpool-utils)

(defvar *default-worker-num* (max 4 (cpus:get-number-of-processors)))

(defparameter *default-keepalive-time* 60
  "Default value for the idle worker thread keepalive time. Note that it's a wall time amount of seconds.")

(defvar *debug-pool-on-error* nil
  "If t, will not catch errors passing through the handlers and will let them bubble up to the debugger.")

(defvar *debug-promise-on-error* nil
  "If t, will not catch errors passing through the handlers and will let them bubble up to the debugger.")

(defparameter *promise* nil
  "A promise that will be rebound when making a promise instance.")

(defparameter *promise-error* nil
  "A promise error that will be rebound when a error is signaled or when a promise is rejected.")


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

(defun make-queue (&optional (init-length 100) (unbound t) (name (string (gensym "QUEUE-"))))
  "Return an unbound"
  (declare (ignore unbound))
  #-sbcl(declare (ignore name))
  #+sbcl(declare (ignore init-length))
  #+sbcl(sb-concurrency:make-queue :name name)
  #-sbcl(cl-fast-queues:make-safe-fifo :init-length init-length :waitp nil))

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

(defmacro compare-and-swap (place old new)
  "Atomically stores NEW in `place' if `old' value matches the current value of `place'.
Two values are considered to match if they are EQ.
return T if swap success, otherwise return NIL."
  ;; https://github.com/Shinmera/atomics/blob/master/atomics.lisp
  #+sbcl
  (let ((tmp (gensym "OLD")))
    `(let ((,tmp ,old)) (eq ,tmp (sb-ext:cas ,place ,tmp ,new))))
  #+ccl
  `(ccl::conditional-store ,place ,old ,new)
  #+clasp
  (let ((tmp (gensym "OLD")))
    `(let ((,tmp ,old)) (eq ,tmp (mp:cas ,place ,tmp ,new))))
  #+ecl
  (let ((tmp (gensym "OLD")))
    `(let ((,tmp ,old)) (eq ,tmp (mp:compare-and-swap ,place ,tmp ,new))))
  #+allegro
  `(if (excl:atomic-conditional-setf ,place ,new ,old) T NIL)
  #+lispworks
  `(system:compare-and-swap ,place ,old ,new)
  #+mezzano
  (let ((tmp (gensym "OLD")))
    `(let ((,tmp ,old))
       (eq ,tmp (mezzano.extensions:compare-and-swap ,place ,tmp ,new))))
  #-(or allegro ccl clasp ecl lispworks mezzano sbcl)
  (no-support 'CAS))

(defmacro atomic-update (place function &rest args)
  "Atomically swap value in `place' with `function' called and return new value."
  #+sbcl
  `(sb-ext:atomic-update ,place ,function ,@args)
  #-sbcl
  (alexandria:with-gensyms (func old-value new-value)
    `(loop :with ,func = ,function
           :for ,old-value = ,place
           :for ,new-value = (funcall ,func ,old-value ,@args)
           :until (compare-and-swap ,place ,old-value ,new-value)
           :finally (return ,new-value))))

(defmacro atomic-set (place new-value)
  "Atomically update the `place' with `new-value'"
  ;; (atomic-set (atomic-place (make-atomic 0)) 100)
  `(atomic-update ,place
                  #'(lambda (x)
                      (declare (ignore x))
                      ,new-value)))

(defmacro atomic-peek (place)
  "Atomically get the value of `place' without change it."
  #+sbcl
  `(progn
     (sb-thread:barrier (:read))
     ,place)
  #-sbcl
  (alexandria:with-gensyms (val)
    `(loop for ,val = ,place
           until (compare-and-swap ,place ,val ,val)
           finally (return ,val))))

(defun peek-queue (queue)
  (declare (optimize speed))
  "Return the first item to be dequeued without dequeueing it"
  #-sbcl(cl-fast-queues:queue-peek queue)
  #+sbcl
  (loop (let* ((head (sb-concurrency::queue-head queue))
               (next (cdr head)))
          (typecase next
            (null (return nil))
            (cons (when (compare-and-swap (sb-concurrency::queue-head queue)
                                          head head)
                    (return (car next))))))))


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

(defun destroy-thread-forced (thread)
  "bt:destroy-thread will signal error if `thread' is the current thread.
this function will try to destroy the thread anyhow."
  #+sbcl (sb-thread:terminate-thread thread)
  #+ccl (ccl:process-kill thread)
  #-(or sbcl ccl) (bt:destroy-thread thread))


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

(defmacro make-binary ((arg1 arg2) &body body)
  "Make up a unary function which accept exactly one argument.
`arg' is the parameter used within `body'."
  ;; (funcall (make-binary (a b) (+ a b)) 1 2)
  `(lambda (,arg1 ,arg2)
     (declare (ignorable ,arg1 ,arg2))
     ,@body))

(defmacro make-n-ary ((&rest args) &body body)
  "Make up a n-ary function which accept any number of arguments.
`args' is the parameters used within `body'."
  ;; (funcall (make-n-ary (a b c) (+ a b c)) 1 2 3)
  `(lambda (,@args)
     (declare (ignorable ,@args))
     ,@body))


(defun wrap-bindings (fn &optional bindings &rest args)
  "Wrap bindings to function `fn' and return an lambda that accepts none parameters. `args' is the arguments of function `fn'"
  ;; (funcall (wrap-bindings #'(lambda () (+ a b)) '((a 1) (b 2))))
  ;; (funcall (wrap-bindings #'(lambda (x) (+ a b x)) '((a 1) (b 2)) 3))
  ;; (funcall (wrap-bindings #'(lambda (x) (+ 1 x)) nil 3))
  ;; (funcall (wrap-bindings #'(lambda (x y) (+ x y)) nil 1 2))
  ;; (funcall (wrap-bindings #'(lambda () (+ 1 2 3)) nil))
  ;; (funcall (wrap-bindings #'(lambda () (+ 1 2 3))))
  (if bindings
      (let ((vars (mapcar #'first bindings))
            (vals (mapcar #'second bindings)))
        (lambda () (progv vars vals
                     (apply fn args))))
      (if args
          (lambda () (apply fn args))
          fn)))

#+:ignore
(defmacro with-error-handling ((blockname &optional promise) error-fn &body body)
  "Wraps some nice restarts around the bits of code that run our promises and handles errors."
  (let ((last-err (gensym "last-err")))
    `(let ((,last-err nil))
       (block ,blockname
         (handler-bind
             ((error (lambda (e)
                       (setf ,last-err e)
                       (unless *debug-on-error*
                         (funcall ,error-fn e)))))
           (restart-case
               (progn ,@body)
             (reject-promise ()
               :report (lambda (s) (format s "Reject the promise ~a" ,promise))
               (format *debug-io* "~&;; promise rejected~%")
               (funcall ,error-fn ,last-err))))))))

(defmacro with-condition-handling (error-handler &body body)
  "Wraps some nice restarts around the bits of code that run our promises and handles errors.
As well as, when in a degenerated promise, use this to resolve the promise"
  (let ((last-err (gensym "last-err")))
    `(let ((,last-err nil)
           (*promise-error* nil))
       (block exit-on-condition
         (handler-bind
             ((error (lambda (err) ; used to handle unhandled error and resolve the promise
                       (let ((*promise-error* err))
                         (setf ,last-err err)
                         (cl-trivial-pool:set-status *promise* :errored)
                         (unless *debug-promise-on-error*
                           (funcall ,error-handler err)))))
              (promise:promise-resolve-condition (lambda (condition) ; used to resolve a promise that's not been resolved explicitly
                                                   (let ((val (promise::promise-condition-data condition)))
                                                     (return-from exit-on-condition val)))))
           (restart-case
               (progn ,@body)
             (reject-promise ()
               :report (lambda (s) (format s "~&Reject the promise ~a.~%" *promise*))
               (format *debug-io* "~&The promise was rejected: ~d.~%" *promise*)
               (funcall ,error-handler ,last-err))))))))
