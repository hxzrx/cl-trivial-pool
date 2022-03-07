(in-package :cl-trivial-pool)

(defstruct (thread-pool (:constructor make-thread-pool (&key name max-worker-num keepalive-time initial-bindings))
                        (:copier nil)
                        (:predicate thread-pool-p))
  (name              (concatenate 'string "THREAD-POOL-" (string (gensym))) :type string)
  (initial-bindings  nil            :type list)
  (lock              (bt2:make-lock :name "THREAD-POOL-LOCK"))
  (cvar              (bt2:make-condition-variable :name "THREAD-POOL-CVAR"))
  (backlog           (sb-concurrency:make-queue  :name "THREAD POOL PENDING WORK-ITEM QUEUE"))
  (max-worker-num    *default-worker-num* :type fixnum)       ; num of worker threads
  (thread-table      (make-hash-table :weakness :value :synchronized t) :type hash-table) ; may have some dead threads due to gc
  (working-num       0              :type (unsigned-byte 64)) ; num of current busy working threads
  (idle-num          0              :type (unsigned-byte 64)) ; num of current idle threads
  (total-threads-num 0              :type (unsigned-byte 64)) ; num of current total threads
  (blocked-num       0              :type (unsigned-byte 64)) ; num of blocked threads
  (shutdown-p        nil)
  (keepalive-time    *default-keepalive-time* :type (unsigned-byte 64)))

(defparameter *default-thread-pool* (make-thread-pool :name "Default Thread Pool"))

(defun inspect-pool (pool &optional (inspect-work-p nil))
  "Return a detail description of the thread pool."
  (format nil "name: ~d, backlog of work: ~d, max workers: ~d, total threads: ~d, working threads: ~d, idle threads: ~d, blocked threads: ~d, shutdownp: ~d~@[, pending works: ~%~{~d~^~&~}~]"
          (thread-pool-name pool)
          (sb-concurrency:queue-count (thread-pool-backlog pool))
          (thread-pool-max-worker-num pool)
          (thread-pool-total-threads-num pool)
          (thread-pool-working-num pool)
          (thread-pool-idle-num pool)
          (thread-pool-blocked-num pool)
          (thread-pool-shutdown-p pool)
          (when inspect-work-p
            (mapcar #'(lambda(work) (inspect-work work t))
                    (sb-concurrency:list-queue-contents (thread-pool-backlog pool))))))

(defmethod print-object ((pool thread-pool) stream)
  (print-unreadable-object (pool stream :type t)
    (format stream (inspect-pool pool))))

(defun peek-backlog (pool)
  "Return the top pending works of the pool. Return NIL if no pending work in the queue."
  (peek-queue (thread-pool-backlog pool)))

(defun thread-pool-n-concurrent-threads (thread-pool) ; effectiveThreads = totalThreads - blockedThread
  "Return the number of threads in the pool are not blocked."
  (assert (>= (thread-pool-total-threads-num thread-pool) (thread-pool-blocked-num thread-pool)))
  (- (thread-pool-total-threads-num thread-pool)
     (thread-pool-blocked-num thread-pool)))

(defstruct (work-item (:constructor make-work-item (&key function thread-pool status (name "") (desc "")))
                      (:copier nil)
                      (:predicate work-item-p))
  (name)
  (function nil :type function)
  (thread-pool *default-thread-pool* :type thread-pool)
  (result nil :type list)
  (status :created :type symbol) ; :created :running :aborted :ready :finished :cancelled :rejected
  (lock (bt2:make-lock))       ; may be useful in the future
  (cvar (bt2:make-condition-variable))
  (desc))

(defun inspect-work (work &optional (simple-mode t))
  "Return a detail description of the work item."
  (format nil (format nil "name: ~d, desc: ~d~@[, pool: ~d~], status: ~d, result: ~d."
                      (work-item-name work)
                      (work-item-desc work)
                      (unless simple-mode
                        (thread-pool-name (work-item-thread-pool work)))
                      (work-item-status work)
                      (work-item-result work))))

(defmethod print-object ((work work-item) stream)
  (print-unreadable-object (work stream :type t)
    (format stream (inspect-work work))))

(defmethod get-result ((work work-item))
  "Get the result of this `work', returns two values:
The second value denotes if the work has finished.
The first value is the function's returned value list of this work,
or nil if the work has not finished."
  (with-slots (status result) work
    (if (eq status :finished)
        (values result t)
        (values nil nil))))

(defmethod get-status ((work work-item))
  "Return the status of an work-item instance."
  (work-item-status work))

(defun thread-pool-main (thread-pool)
  (let* ((self (bt2:current-thread)))
    (loop (let ((work nil))
            (with-slots (backlog max-worker-num keepalive-time lock cvar idle-num) thread-pool
              (sb-ext:atomic-decf (thread-pool-working-num thread-pool))
              (sb-ext:atomic-incf (thread-pool-idle-num thread-pool))
              ;;(setf (sb-thread:thread-name self) "Thread pool idle worker")
              (let ((start-idle-time (get-internal-run-time)))
                (flet ((exit-while-idle ()
                         (sb-ext:atomic-decf (thread-pool-idle-num thread-pool))
                         (sb-ext:atomic-decf (thread-pool-total-threads-num thread-pool))
                         (return-from thread-pool-main)))
                  (loop (when (thread-pool-shutdown-p thread-pool)
                          (exit-while-idle))
                        (alexandria:when-let (wk (sb-concurrency:dequeue backlog))
                          (when (eq (work-item-status wk) :ready)
                            (setf work wk)
                            #+:ignore(setf (sb-thread:thread-name self)
                                  (concatenate 'string "Thread pool worker: " (work-item-name work)))
                            (sb-ext:atomic-decf (thread-pool-idle-num thread-pool))
                            (sb-ext:atomic-incf (thread-pool-working-num thread-pool))
                            (sb-ext:atomic-update (work-item-status wk) #'(lambda (x)
                                                                            (declare (ignore x))
                                                                            :running))
                            (return)))
                        (when (> (thread-pool-n-concurrent-threads thread-pool) max-worker-num)
                          (exit-while-idle))
                        (let* ((end-idle-time (+ start-idle-time
                                                 (* keepalive-time internal-time-units-per-second)))
                               (idle-time-remaining (- end-idle-time (get-internal-run-time))))
                          (when (minusp idle-time-remaining)
                            (exit-while-idle))
                          (bt2:with-lock-held (lock)
                            (loop until (peek-backlog thread-pool)
                                  do (or (bt2:condition-wait cvar lock
                                                             :timeout (/ idle-time-remaining
                                                                         internal-time-units-per-second))
                                         (return)))))))))
            (unwind-protect-unwind-only
                (catch 'terminate-work
                  (let ((result (multiple-value-list (funcall (work-item-function work)))))
                    (setf (work-item-result work) result
                          (work-item-status work) :finished)))
              (sb-ext:atomic-decf (thread-pool-working-num thread-pool))
              (sb-ext:atomic-decf (thread-pool-total-threads-num thread-pool))
              (setf (work-item-status work) :aborted)
              (bt2:destroy-thread self))))))

(defun add-thread (&optional (pool *default-thread-pool*))
  "Add a thread to a thread pool."
  (bt2:make-thread (lambda () (thread-pool-main pool))
                   :name (concatenate 'string "Worker of " (thread-pool-name pool))
                   :initial-bindings (thread-pool-initial-bindings pool)))


(defun add-task (function thread-pool &key (name "") priority bindings desc)
  "Add a work item to the thread-pool.
Functions are called concurrently and in FIFO order.
A work item is returned, which can be passed to THREAD-POOL-CANCEL-ITEM
to attempt cancel the work.
BINDINGS is a list which specify special bindings
that should be active when FUNCTION is called. These override the
thread pool's initial-bindings."
  (declare (ignore priority)) ; TODO
  (check-type function function)
  (let ((work (make-work-item
               :name name
               :function (if bindings
                             (let ((vars (mapcar #'first bindings))
                                   (vals (mapcar #'second bindings)))
                               (lambda ()
                                 (progv vars vals
                                   (funcall function))))
                             function)
               :status :ready
               :thread-pool thread-pool
               :desc desc)))
    (with-slots (backlog max-worker-num) thread-pool
      (when (thread-pool-shutdown-p thread-pool)
        (error "Attempted to add work item to a shut down thread pool ~S" thread-pool))
      (sb-concurrency:enqueue work backlog)
      (when (and (<= (thread-pool-idle-num thread-pool) 0)
                 (< (thread-pool-n-concurrent-threads thread-pool)
                    max-worker-num))
        (bt2:make-thread (lambda () (thread-pool-main thread-pool))
                         :name (concatenate 'string "Worker of " (thread-pool-name thread-pool))
                         :initial-bindings (thread-pool-initial-bindings thread-pool))
        (sb-ext:atomic-incf (thread-pool-working-num thread-pool))
        (sb-ext:atomic-incf (thread-pool-total-threads-num thread-pool)))
      (bt2:condition-notify (thread-pool-cvar thread-pool)))
    work))

(defun add-tasks (function values thread-pool &key name priority bindings)
  "Add many work items to the pool.
A work item is created for each element of VALUES and FUNCTION is called
in the pool with that element.
Returns a list of the work items added."
  (loop for value in values
        collect (add-task (let ((value value))
                            (lambda () (funcall function value)))
                          thread-pool
                          :name name
                          :priority priority
                          :bindings bindings)))

(defmethod add-work ((work work-item) &optional (pool *default-thread-pool*) priority)
  "Enqueue a work-item to a thread-pool.
The biggest different between `thread-pool-add' and `add-work' is that `add-work' has no bindings specified"
  (declare (ignore priority))
  (unless (eq (work-item-thread-pool work) pool)
    (warn "The thread-pool of the work-item is not as same as the thread-pool provide.
And it will be set to the pool provided")
    (setf (work-item-thread-pool work) pool)) ; this will not likly compete by threads
  (with-slots (backlog max-worker-num) pool
    (when (thread-pool-shutdown-p pool)
      (error "Attempted to add work item to a shut down thread pool ~S" pool))
    (setf (work-item-status work) :ready)
    (sb-concurrency:enqueue work backlog)
    (when (and (<= (thread-pool-idle-num pool) 0)
               (< (thread-pool-n-concurrent-threads pool)
                  max-worker-num))
      (bt2:make-thread (lambda () (thread-pool-main pool))
                       :name (concatenate 'string "Worker of " (thread-pool-name pool))
                       :initial-bindings (thread-pool-initial-bindings pool))
      (sb-ext:atomic-incf (thread-pool-working-num pool))
      (sb-ext:atomic-incf (thread-pool-total-threads-num pool)))
    (bt2:condition-notify (thread-pool-cvar pool)))
  work)

(defmethod add-works ((work-list list) &optional (pool *default-thread-pool*) priority)
  "Enqueue a list of works to a thread-pool, and return the list of works enqueued."
  (loop for work in work-list
        collect (add-work work pool priority)))

(defun cancel-work (work-item)
  "Cancel a work item, removing it from its thread-pool.
Returns true if the item was successfully cancelled,
false if the item had finished or is currently running on a worker thread."
  (sb-ext:atomic-update (work-item-status work-item)
                        #'(lambda (x)
                            (declare (ignore x))
                            :cancelled)))

(defun flush-pool (thread-pool)
  "Cancel all outstanding work on THREAD-POOL.
Returns a list of all cancelled items.
Does not cancel work in progress."
  (with-slots (backlog) thread-pool
    (sb-concurrency::try-walk-queue #'(lambda (work)
                                        (sb-ext:atomic-update (work-item-status work)
                                                              #'(lambda (x)
                                                                  (declare (ignore x))
                                                                  :cancelled)))
                                    backlog)
    (prog1 (sb-concurrency:list-queue-contents backlog)
      (queue-flush backlog))))

(defun shutdown-pool (thread-pool &key abort)
  "Shutdown THREAD-POOL.
This cancels all outstanding work on THREAD-POOL
and notifies the worker threads that they should
exit once their active work is complete.
Once a thread pool has been shut down, no further work
can be added unless it's been restarted by thread-pool-restart.
If ABORT is true then worker threads will be terminated
via TERMINATE-THREAD."
  (with-slots (shutdown-p backlog thread-table) thread-pool
    (setf shutdown-p t)
    (flush-pool thread-pool)
    (when abort
      (dolist (thread (alexandria:hash-table-values thread-table))
        (ignore-errors (bt2:destroy-thread thread))))
    (bt2:condition-notify (thread-pool-cvar thread-pool)))
  (values))

(defun restart-pool (thread-pool)
  "Calling thread-pool-shutdown will not destroy the pool object, but set the slot %shutdown t.
This function set the slot %shutdown nil so that the pool will be used then.
Return t if the pool has been shutdown, and return nil if the pool was active"
  (if (thread-pool-shutdown-p thread-pool)
      (progn (sb-ext:atomic-update (thread-pool-shutdown-p thread-pool)
                                   #'(lambda (x)
                                       (declare (ignore x))
                                       nil))
             t)
      nil))


;;;; thread pool blocking

;;; Thread pool support for hijacking blocking functions.
;;; When the current thread's thread-pool slot is non-nil, the blocking
;;; functions will call THREAD-POOL-BLOCK with the thread pool, the name
;;; of the function and supplied arguments instead of actually blocking.
;;; The thread's thread-pool slot will be set to NIL for the duration
;;; of the call to THREAD-POOL-BLOCK.

;; Mezzano/system/sync.lisp
(defgeneric thread-pool-block (thread-pool blocking-function &rest arguments)
  (:documentation "Called when the current thread's thread-pool slot
is non-NIL and the thread is about to block. The thread-pool slot
is bound to NIL for the duration of the call."))

(defmethod thread-pool-block ((thread-pool thread-pool) blocking-function &rest arguments)
  (declare (dynamic-extent arguments))
  (when (and (eql blocking-function 'bt2:acquire-lock)
             (eql (first arguments) (thread-pool-lock thread-pool)))
    ;; Don't suspend when acquiring the thread-pool lock, this causes
    ;; recursive locking on it.
    (return-from thread-pool-block
      (apply blocking-function arguments)))
  (unwind-protect
       (progn
         (bt2:with-lock-held ((thread-pool-lock thread-pool))
           (incf (thread-pool-blocked-num thread-pool)))
         (apply blocking-function arguments))
    (bt2:with-lock-held ((thread-pool-lock thread-pool))
      (decf (thread-pool-blocked-num thread-pool)))))

;;;; Mezzano/supervisor/sync.lisp
(defmacro thread-pool-blocking-hijack (function-name &rest arguments)
  (let ((self (gensym "SELF"))
        (pool (gensym "POOL")))
    `(let* ((,self (current-thread))
            (,pool (thread-thread-pool ,self)))
       (when ,pool
         (unwind-protect
              (progn
                (setf (thread-thread-pool ,self) nil) ; make sure it will not been call repeatly
                (return-from ,function-name
                  (thread-pool-block ,pool ',function-name ,@arguments)))
           (setf (thread-thread-pool ,self) ,pool))))))

(defmacro thread-pool-blocking-hijack-apply (function-name &rest arguments)
  ;; used when all the parameters are enclosed in a list
  (let ((self (gensym "SELF"))
        (pool (gensym "POOL")))
    `(let* ((,self (current-thread))
            (,pool (thread-thread-pool ,self)))
       (when ,pool
         (unwind-protect
              (progn
                (setf (thread-thread-pool ,self) nil)
                (return-from ,function-name
                  (apply #'thread-pool-block ,pool ',function-name ,@arguments)))
           (setf (thread-thread-pool ,self) ,pool))))))

(defmacro inhibit-thread-pool-blocking-hijack (&body body)
  "Run body with the thread's thread-pool unset."
  (let ((self (gensym "SELF"))
        (pool (gensym "POOL")))
    `(let* ((,self (current-thread))
            (,pool (thread-thread-pool ,self)))
       (unwind-protect
            (progn
              (setf (thread-thread-pool ,self) nil)
              ,@body)
         (setf (thread-thread-pool ,self) ,pool)))))
