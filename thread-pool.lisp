(in-package :cl-trivial-pool)

(defparameter *default-wait-time* 0.005
  "The time when waiting for condition variable to get rid of lost wakeups.
If the work-item is sent through a scheduler,
This wait-time should not be greater then the resolutin of the scheduler.")

(defstruct (thread-pool (:constructor make-thread-pool (&key (name (string (gensym "THREAD-POOL-")))
                                                          (max-worker-num *default-worker-num*)
                                                          (keepalive-time *default-keepalive-time*)
                                                          initial-bindings))
                        (:copier nil)
                        (:predicate thread-pool-p))
  (name              (string (gensym "THREAD-POOL-")) :type string)
  (initial-bindings nil            :type list)
  (lock             (bt:make-lock "THREAD-POOL-PICKING-WORK-ITEM-LOCK"))
  (cvar             (bt:make-condition-variable :name "THREAD-POOL-PICKING-WORK-ITEM-CVAR"))
  (lock-add-thread  (bt:make-lock "THREAD-POOL-ADD-THREAD-LOCK"))
  (backlog          #+sbcl(make-queue 20 t "BACKLOG-QUEUE") #-sbcl(make-queue 20 t))
  (max-worker-num   *default-worker-num* :type fixnum)       ; num of worker threads
  (thread-table     (make-hash) :type hash-table)            ; may have some dead threads due to gc
  (working-num      0 #+sbcl :type #+sbcl(unsigned-byte 64)) ; use #reader to make it atomic peekable
  (idle-num         0 #+sbcl :type #+sbcl(unsigned-byte 64)) ; num of current idle threads, total = working + idle
  (shutdown-p       nil)
  (keepalive-time   *default-keepalive-time* :type (unsigned-byte 64)))

(defparameter *default-thread-pool* (make-thread-pool :name "Default Thread Pool"))

(defun inspect-pool (pool &optional (inspect-work-p nil))
  "Return a detail description of the thread pool."
  (format nil "name: ~d, backlog of work: ~d, max workers: ~d, current working threads: ~d, idle threads: ~d, shutdownp: ~d, all threads: ~d, ~@[, pending works: ~%~{~d~^~&~}~]"
          (thread-pool-name pool)
          (queue-count (thread-pool-backlog pool))
          (thread-pool-max-worker-num pool)
          (thread-pool-working-num pool)
          (thread-pool-idle-num pool)
          (thread-pool-shutdown-p pool)
          (alexandria:hash-table-values (thread-pool-thread-table pool))
          (when inspect-work-p
            (mapcar #'(lambda(work) (inspect-work work t))
                    (queue-to-list (thread-pool-backlog pool))))))

(defmethod print-object ((pool thread-pool) stream)
  (print-unreadable-object (pool stream :type t)
    (format stream (inspect-pool pool))))

(defun peek-backlog (pool)
  "Return the top pending work-item of the pool. Return NIL if no pending works in the queue."
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (peek-queue (thread-pool-backlog pool)))

(defclass work-item ()
  ((name     :initarg :name   :initform (string (gensym "WORK-ITEM-"))  :type string    :accessor work-item-name)
   (fn       :initarg :fn     :initform nil :accessor work-item-fn)
   (pool     :initarg :pool   :initform nil :accessor work-item-pool)
   (result   :initarg :result :initform nil :type list :accessor work-item-result)
   ;; :created :running :aborted :ready :finished :cancelled :rejected
   ;;(status   :initarg :status :initform (list :created) :type list    :accessor work-item-status) ; use list to enable atomic
   (status   :initarg :status :initform (make-atomic :created)    :accessor work-item-status)
   (lock     :initarg :lock   :initform (bt:make-lock)               :accessor work-item-lock)
   (cvar     :initarg :cvar   :initform (bt:make-condition-variable) :accessor work-item-cvar)
   (desc     :initarg :desc   :initform nil :accessor work-item-desc)))

(defun inspect-work (work &optional (simple-mode t))
  "Return a detail description of the work item."
  (format nil (format nil "name: ~d, desc: ~d~@[, pool: ~d~], status: ~d, result: ~d, pool: ~d."
                      (work-item-name work)
                      (work-item-desc work)
                      (unless simple-mode
                        (thread-pool-name (work-item-pool work)))
                      (atomic-place (work-item-status work))
                      (work-item-result work)
                      (thread-pool-name (work-item-pool work)))))

(defmethod print-object ((work work-item) stream)
  (print-unreadable-object (work stream :type t)
    (format stream (inspect-work work))))

(defun work-item-p (work)
  "Return T if `work' is an instance of work-item or else return NIL."
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (subtypep (type-of work) 'work-item))

(defun make-work-item (&key function
                         (pool *default-thread-pool*)
                         (name (string (gensym "WORK-ITEM-")))
                         bindings desc)
  (declare (function function))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (make-instance 'work-item
                 :fn (if bindings
                         (let ((vars (mapcar #'first bindings))
                               (vals (mapcar #'second bindings)))
                           (lambda () (progv vars vals
                                        (funcall function))))
                         function)
                 :pool pool
                 :status (make-atomic :created)
                 :name name
                 :desc desc))

(defmacro with-work-item ((&key (pool *default-thread-pool*)
                             (name (string (gensym "WORK-ITEM-")))
                             bindings desc) &body body)
  "Return an work-item object whose fn slot is made up with `body'"
  ;; (with-work-item () (+ 1 1))
  ;; (funcall (slot-value (with-work-item () (+ 1 1)) 'fn))
  ;; (funcall (work-item-fn (with-work-item (:bindings '((a 1) (b 2))) (+ a b))))
  (let ((binds (gensym))
        (bindings% bindings))
    `(let* ((work (make-instance 'work-item :pool ,pool
                                            :status (make-atomic :created)
                                            :name ,name
                                            :desc ,desc))
            (,binds ,bindings%)
            (fn (if ,binds
                    (let ((vars (mapcar #'first ,binds))
                          (vals (mapcar #'second ,binds)))
                      (lambda () (progv vars vals
                                   (funcall (make-nullary () ,@body)))))
                    (make-nullary () ,@body))))
       (setf (slot-value work 'fn) fn)
       work)))

(defmethod get-status ((work work-item))
  "Return the status of an work-item instance."
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (atomic-place (work-item-status work)))

(defmethod set-status ((work work-item) new-status)
  "Set the status slot of work to a new value"
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (atomic-set (atomic-place (work-item-status work)) new-status))

(defmethod get-result ((work work-item) &optional (waitp t) (timeout nil))
  "Get the result of this `work', returns two values:
The second value denotes if the work has finished.
The first value is the function's returned value list of this work,
or nil if the work has not finished."
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (case (get-status work) ; :created :ready :running :aborted :finished :cancelled :rejected
    (:finished (values (work-item-result work) t))
    ((:ready :running)
     (if waitp
         (with-slots (lock cvar) work
           (bt:with-lock-held (lock)
             (if timeout
                 (loop while (or (eq (get-status work) :ready)
                                 (eq (get-status work) :running))
                       do (or #+sbcl(bt:condition-wait cvar lock :timeout timeout)
                              #+ccl(tpool-utils::condition-wait cvar lock :timeout timeout)
                              (return)))
                 ;; repeatly wait with small timeout to deal with the lost wakeups
                 (loop while (or (eq (get-status work) :ready)
                                 (eq (get-status work) :running))
                       do (and #+sbcl(bt:condition-wait cvar lock :timeout *default-wait-time*)
                               #+ccl(tpool-utils::condition-wait cvar lock :timeout *default-wait-time*)
                               (null (or (eq (get-status work) :ready)
                                         (eq (get-status work) :running)))
                              (return)))))
           (with-slots (status result) work
             (if (eq (atomic-place status) :finished)
                 (values result t)
                 (values nil nil))))
         (with-slots (status result) work
           (if (eq (atomic-place status) :finished)
               (values result t)
               (values nil nil)))))
    (:created (warn "The work has not been added to a thread pool.")
     (values nil nil))
    (t (warn "The result of this work is abnormal, the status is ~s." (get-status work))
     (values nil nil))))

(defmethod set-result ((work work-item) result)
  "Set the result of `work' directly and return the work instance itself."
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (if (listp result)
      (setf (work-item-result work) result)
      (setf (work-item-result work) (list result)))
  work)

(defmethod set-result :after ((work work-item) result)
  "Set the status slot with :finished"
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (declare (ignore result))
  (set-status work :finished))

(defun thread-pool-main (pool)
  (let* ((self (bt:current-thread)))
    (loop (let ((work nil))
            (with-slots (backlog max-worker-num keepalive-time lock cvar) pool
              (atomic-decf (thread-pool-working-num pool))
              (atomic-incf (thread-pool-idle-num pool))
              (let ((start-idle-time (get-internal-real-time)))
                (flet ((exit-while-idle ()
                         (atomic-decf (thread-pool-idle-num pool))
                         (return-from thread-pool-main)))
                  (loop (when (thread-pool-shutdown-p pool)
                          (exit-while-idle))
                        (alexandria:when-let (wk (dequeue backlog))
                          (when (eq (atomic-place (work-item-status wk)) :ready)
                            (setf work wk)
                            (atomic-decf (thread-pool-idle-num pool))
                            (atomic-incf (thread-pool-working-num pool))
                            (atomic-update (atomic-place (work-item-status wk)) #'(lambda (x)
                                                                                    (declare (ignore x))
                                                                                    :running))
                            (return)))
                        (when (> (+ (thread-pool-working-num pool)
                                    (thread-pool-idle-num pool))
                                 max-worker-num)
                          (exit-while-idle))
                        (let* ((max-idle-time (* keepalive-time internal-time-units-per-second))
                               (end-idle-time (+ start-idle-time max-idle-time))
                               (idle-time-remaining (- end-idle-time (get-internal-real-time)))
                               (wait-num (truncate (/ idle-time-remaining
                                                      *default-wait-time*
                                                      internal-time-units-per-second))))
                          (when (minusp idle-time-remaining) ; make sure condition-wait' timeout >= zero
                            (exit-while-idle))
                          (bt:with-lock-held (lock)
                            (loop until (peek-backlog pool)
                                  do (progn
                                       (decf wait-num)
                                       (or #+sbcl(bt:condition-wait cvar lock :timeout *default-wait-time*)
                                           #+ccl(tpool-utils::condition-wait cvar lock :timeout *default-wait-time*)
                                           (> wait-num 0)
                                           (return))))))))))
            (unwind-protect-unwind-only
                (catch 'terminate-work
                  (let ((last-err nil))
                    (handler-bind ((error (lambda (err)
                                            (setf (atomic-place (work-item-status work)) :aborted)
                                            (setf last-err err)
                                            (bt:condition-notify (work-item-cvar work))
                                            (unless *debug-pool-on-error*
                                              (throw 'terminate-work err)))))
                      (restart-case
                          (let ((result (multiple-value-list (funcall (work-item-fn work)))))
                            (when (eq :running (get-status work)) ; the status may be modified during fn's executing
                              (setf (work-item-result work) result)
                              (set-status work :finished))
                            (bt:condition-notify (work-item-cvar work)))
                        (default-restart ()
                          :report (lambda (s) (format s "~&An error <~s> occured when executing work!~%" last-err))
                          (log:debug "Error: <~s>, work: ~d" last-err work))))))
              (atomic-decf (thread-pool-working-num pool))
              (setf (atomic-place (work-item-status work)) :aborted)
              (bt:condition-notify (work-item-cvar work))
              (log:debug "Thread destroyed due to error: ~d" self)
              (destroy-thread-forced self))))))

(defun add-thread (pool)
  "Add a thread to a thread pool regardless of how many threads there are."
  ;;(declare (thread-pool pool))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (when (> (thread-pool-max-worker-num pool)
           (+ (thread-pool-working-num pool) (thread-pool-idle-num pool)))
    (prog1 (atomic-incf (thread-pool-working-num pool))
      (setf (gethash (gensym) (thread-pool-thread-table pool))
            (bt:make-thread (lambda () (thread-pool-main pool))
                            :name (concatenate 'string "WORKER-OF-" (thread-pool-name pool))
                            :initial-bindings (thread-pool-initial-bindings pool))))))

(declaim (inline add-work))
(defmethod add-work ((work work-item) &optional (pool *default-thread-pool*) priority)
  "Enqueue a work-item to a thread-pool."
  (declare (ignore priority))
  (if (thread-pool-p (work-item-pool work))
      (setf pool (work-item-pool work))
      (setf (slot-value work 'pool) pool))
  (with-slots (backlog max-worker-num working-num idle-num lock-add-thread) pool
    (when (thread-pool-shutdown-p pool)
      (error "Attempted to add work item to a shutted down thread pool ~S" pool))
    (unless (eq :created (get-status work))
      (warn "Attempted to add a '~s' work item to a thread pool ~d." (get-status work) work))
    (setf (atomic-place (work-item-status work)) :ready)
    ;; should be in order enqueue -> add-thread -> notify,
    ;; or if in order add-thread -> enqueue -> notify, the thread may fail to pick this work
    (enqueue work backlog)
    (bt:with-lock-held (lock-add-thread)
      (when (and (= (thread-pool-idle-num pool) 0)
                 (< (+ working-num idle-num) max-worker-num))
        (setf (gethash (gensym) (thread-pool-thread-table pool))
              (bt:make-thread (lambda () (thread-pool-main pool))
                              :name (concatenate 'string "WORKER-OF-" (thread-pool-name pool))
                              :initial-bindings (thread-pool-initial-bindings pool)))
        (atomic-incf (thread-pool-working-num pool))))
    (bt:condition-notify (thread-pool-cvar pool)))
  work)

(defmethod add-works ((work-list list) &optional (pool *default-thread-pool*) priority)
  "Enqueue a list of works to a thread-pool, and return the list of works enqueued."
  (loop for work in work-list
        collect (add-work work pool priority)))

(defun cancel-work (work-item)
  "Cancel a work item, removing it from its thread-pool.
Returns true if the item was successfully cancelled,
false if the item had finished or is currently running on a worker thread."
  (atomic-update (atomic-place (work-item-status work-item))
                 #'(lambda (x)
                     (declare (ignore x))
                     :cancelled)))

(defun add-task (function pool &key (name "") priority bindings desc)
  "Add a work item to the thread-pool.
Functions are called concurrently and in FIFO order.
A work item is returned, which can be passed to CANCEL-WORK
to attempt cancel the work.
BINDINGS is a list which specify special bindings
that should be active when FUNCTION is called. These override the
thread pool's initial-bindings."
  (declare (ignore priority)) ; TODO
  (check-type function function)
  (let ((work (make-work-item
               :function (if bindings
                             (let ((vars (mapcar #'first bindings))
                                   (vals (mapcar #'second bindings)))
                               (lambda () (progv vars vals
                                            (funcall function))))
                             function)
               :pool pool
               :name name
               :desc desc)))
    (add-work work)))

(defun add-tasks (function values pool &key name priority bindings)
  "Add many work items to the pool.
A work item is created for each element of VALUES and FUNCTION is called
in the pool with that element.
Returns a list of the work items added."
  (loop for value in values
        collect (add-task (let ((value value))
                            (lambda () (funcall function value)))
                          pool
                          :name name
                          :priority priority
                          :bindings bindings)))

(defun flush-pool (pool)
  "Cancel all outstanding work on THREAD-POOL.
Returns a list of all cancelled items.
Does not cancel work in progress."
  (with-slots (backlog) pool
    (let ((lst (queue-to-list backlog)))
      (flush-queue backlog)
      (dolist (work lst)
        (when (eq (atomic-place (work-item-status work)) :ready)
          (atomic-update (atomic-place (work-item-status work))
                         #'(lambda (x)
                             (declare (ignore x))
                             :cancelled))))
      lst)))

(defun shutdown-pool (pool &key abort)
  "Shutdown THREAD-POOL.
This cancels all outstanding work on THREAD-POOL
and notifies the worker threads that they should
exit once their active work is complete.
Once a thread pool has been shut down, no further work
can be added unless it's been restarted by thread-pool-restart.
If ABORT is true then worker threads will be terminated
via TERMINATE-THREAD."
  (with-slots (shutdown-p backlog thread-table working-num idle-num) pool
    (setf shutdown-p t)
    (flush-pool pool)
    (when abort
      (dolist (thread (alexandria:hash-table-values thread-table))
        (ignore-errors (bt:destroy-thread thread))))
    (bt:condition-notify (thread-pool-cvar pool))
    (log:info "Shutting down the pool, wait for a second....")
    (sleep 1)
    (clrhash thread-table)
    (setf working-num 0
          idle-num 0))
  t)

#|
(defun restart-pool (pool)
  "Calling shutdown-pool will not destroy the pool object, but set the slot shutdown-p t.
This function set the slot shutdown-p nil so that the pool will be used then.
Return t if the pool has been shutdown, and return nil if the pool was active."
  ;; restart seems useless
  (shutdown-pool pool)
  (atomic-update (thread-pool-shutdown-p pool)
                 #'(lambda (x)
                     (declare (ignore x))
                     nil))
  t)
|#
