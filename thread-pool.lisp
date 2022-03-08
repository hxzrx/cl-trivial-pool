(in-package :cl-trivial-pool)

(defstruct (thread-pool (:constructor make-thread-pool (&key name max-worker-num keepalive-time initial-bindings))
                        (:copier nil)
                        (:predicate thread-pool-p))
  (name              (concatenate 'string "THREAD-POOL-" (string (gensym))) :type string)
  (initial-bindings  nil            :type list)
  (lock              (bt:make-lock "THREAD-POOL-LOCK"))
  (cvar              (bt:make-condition-variable :name "THREAD-POOL-CVAR"))
  (backlog           (make-queue))
  (max-worker-num    *default-worker-num* :type fixnum)       ; num of worker threads
  (thread-table      (make-hash) :type hash-table) ; may have some dead threads due to gc
  (working-num       0              :type (unsigned-byte 64)) ; num of current busy working threads
  (idle-num          0              :type (unsigned-byte 64)) ; num of current idle threads, total = working + idle
  (shutdown-p        nil)
  (keepalive-time    *default-keepalive-time* :type (unsigned-byte 64)))

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
  (peek-queue (thread-pool-backlog pool)))

(defclass work-item ()
  ((name     :initarg :name   :initform "An work item"  :type string    :accessor work-item-name)
   (fun      :initarg :fun                              :type function  :accessor work-item-fun)
   (pool     :initarg :pool   :initform *default-thread-pool* :type thread-pool :accessor work-item-pool)
   (result   :initarg :result :initform nil             :type list      :accessor work-item-result)
   ;; :created :running :aborted :ready :finished :cancelled :rejected
   ;;(status   :initarg :status :initform (list :created) :type list    :accessor work-item-status) ; use list to enable atomic
   (status   :initarg :status :initform (make-atomic :created)    :accessor work-item-status)
   (lock     :initarg :lock   :initform (bt:make-lock)               :accessor work-item-lock)
   (cvar     :initarg :cvar   :initform (bt:make-condition-variable) :accessor work-item-cvar)
   (desc     :initarg :desc   :accessor work-item-desc)))

(defun inspect-work (work &optional (simple-mode t))
  "Return a detail description of the work item."
  (format nil (format nil "name: ~d, desc: ~d~@[, pool: ~d~], status: ~d, result: ~d."
                      (work-item-name work)
                      (work-item-desc work)
                      (unless simple-mode
                        (thread-pool-name (work-item-pool work)))
                      (atomic-place (work-item-status work))
                      (work-item-result work))))

(defmethod print-object ((work work-item) stream)
  (print-unreadable-object (work stream :type t)
    (format stream (inspect-work work))))

(defun make-work-item (&key function (pool *default-thread-pool*) (status :created) (name "A work item") desc)
  (make-instance 'work-item
                 :fun function
                 :pool pool
                 :status (make-atomic status)
                 :name name
                 :desc desc))

(defmethod get-status ((work work-item))
  "Return the status of an work-item instance."
  (atomic-place (work-item-status work)))

(defmethod get-result ((work work-item) &optional (waitp t) (timeout nil))
  "Get the result of this `work', returns two values:
The second value denotes if the work has finished.
The first value is the function's returned value list of this work,
or nil if the work has not finished."
  (case (get-status work) ; :created :ready :running :aborted :finished :cancelled :rejected
    (:finished (values (work-item-result work) t))
    ((:ready :running)
     (if waitp
         (with-slots (lock cvar) work
           (bt:with-lock-held (lock) work
             (loop while (or (eq (get-status work) :ready)
                             (eq (get-status work) :running))
                   do (or (bt:condition-wait cvar lock :timeout timeout)
                          (return))))
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
    (t (warn "The result of this work is abnormal, the status is ~s" (get-status work))
     (values nil nil))))

(defun thread-pool-main (pool)
  (let* ((self (bt:current-thread)))
    (loop (let ((work nil))
            (assert (<= (+ (thread-pool-working-num pool) (thread-pool-idle-num pool)) ; used for debugging
                        (thread-pool-max-worker-num pool)))
            (with-slots (backlog max-worker-num keepalive-time lock cvar) pool
              (atomic-decf (thread-pool-working-num pool))
              (atomic-incf (thread-pool-idle-num pool))
              (let ((start-idle-time (get-internal-run-time)))
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
                        (let* ((end-idle-time (+ start-idle-time
                                                 (* keepalive-time internal-time-units-per-second)))
                               (idle-time-remaining (- end-idle-time (get-internal-run-time))))
                          (when (minusp idle-time-remaining)
                            (exit-while-idle))
                          (bt:with-lock-held (lock)
                            (loop until (peek-backlog pool)
                                  do (or (bt:condition-wait cvar lock
                                                             :timeout (/ idle-time-remaining
                                                                         internal-time-units-per-second))
                                         (return)))))))))
            (unwind-protect-unwind-only
                (catch 'terminate-work
                  (let ((result (multiple-value-list (funcall (work-item-fun work)))))
                    (setf (work-item-result work) result
                          (atomic-place (work-item-status work)) :finished)
                    (bt:condition-notify (work-item-cvar work))))
              (atomic-decf (thread-pool-working-num pool))
              (setf (atomic-place (work-item-status work)) :aborted)
              (bt:condition-notify (work-item-cvar work))
              (bt:destroy-thread self))))))

(defun add-thread (pool)
  "Add a thread to a thread pool."
  (when (> (thread-pool-max-worker-num pool)
           (+ (thread-pool-working-num pool) (thread-pool-idle-num pool)))
    (prog1 (atomic-incf (thread-pool-working-num pool))
      (bt:make-thread (lambda () (thread-pool-main pool))
                      :name (concatenate 'string "Worker of " (thread-pool-name pool))
                      :initial-bindings (thread-pool-initial-bindings pool)))))

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
               :status :ready
               :name name
               :desc desc)))
    (format t "add a new task: ~d~%" work)
    (with-slots (backlog max-worker-num working-num idle-num) pool
      (when (thread-pool-shutdown-p pool)
        (error "Attempted to add work item to a shut down thread pool ~S" pool))
      (enqueue work backlog)
      (when (and (<= (thread-pool-idle-num pool) 0)
                 (< (+ working-num idle-num) max-worker-num))
        (bt:make-thread (lambda () (thread-pool-main pool))
                         :name (concatenate 'string "Worker of " (thread-pool-name pool))
                         :initial-bindings (thread-pool-initial-bindings pool))
        (atomic-incf (thread-pool-working-num pool)))
      (bt:condition-notify (thread-pool-cvar pool)))
    work))

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

(defmethod add-work ((work work-item) &optional (pool *default-thread-pool*) priority)
  "Enqueue a work-item to a thread-pool.
The biggest different between `add-task' and `add-work' is that `add-work' has no bindings specified"
  (declare (ignore priority))
  (unless (eq (work-item-pool work) pool)
    (warn "The thread-pool of the work-item is not as same as the thread-pool provide.
And it will be set to the pool provided")
    (setf (work-item-pool work) pool)) ; this will not likly compete by threads
  (with-slots (backlog max-worker-num working-num idle-num) pool
    (when (thread-pool-shutdown-p pool)
      (error "Attempted to add work item to a shut down thread pool ~S" pool))
    (setf (atomic-place (work-item-status work)) :ready)
    (enqueue work backlog)
    (when (and (= (thread-pool-idle-num pool) 0)
               (< (+ working-num idle-num) max-worker-num))
      (format t "should create thread~%")
      (bt:make-thread (lambda () (thread-pool-main pool))
                      :name (concatenate 'string "Worker of " (thread-pool-name pool))
                      :initial-bindings (thread-pool-initial-bindings pool))
      (atomic-incf (thread-pool-working-num pool)))
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
  (with-slots (shutdown-p backlog thread-table) pool
    (setf shutdown-p t)
    (flush-pool pool)
    (when abort
      (dolist (thread (alexandria:hash-table-values thread-table))
        (ignore-errors (bt:destroy-thread thread))))
    (bt:condition-notify (thread-pool-cvar pool)))
  (values))

(defun restart-pool (pool)
  "Calling shutdown-pool will not destroy the pool object, but set the slot shutdown-p t.
This function set the slot shutdown-p nil so that the pool will be used then.
Return t if the pool has been shutdown, and return nil if the pool was active."
  (if (thread-pool-shutdown-p pool)
      (progn (atomic-update (thread-pool-shutdown-p pool)
                                   #'(lambda (x)
                                       (declare (ignore x))
                                       nil))
             t)
      nil))
