;;;; Here, we treat the promise as a generalization of the thread-pool's work-item.
;;;; The main difference are:
;;;; 1. An work-item is purely a calculation task,
;;;;    which will return the final result once it's been scheduled and there will be no further changes,
;;;;    while an promise's final result may be worked out once only,
;;;;    or may be worked out some time in the future as it depends on some other situations.
;;;;    So, the result of a promise may be another promise with the former's status slot :finished.
;;;;    And so, a promise's final result may be worked out by callbacks through other promise.
;;;; 2. A promise's finish event may results some callbacks.
;;;;    Although this callback can be invoked within the work-item's workload function,
;;;;    in an async context, this is inevitable if a promise is finished by another promise.
;;;; 3. A promise's work-item-status will be set within the promise's own logic,
;;;;    not in thread-main, to isolate from normal work-item.


(in-package :promise)

;;; conditions definition

(define-condition promise-condition (condition)
  ((data   :initarg :data   :initform nil :accessor promise-condition-data))
  ;;(reason :initarg :reason :initform nil :accessor promise-condition-reason))
  (:report (lambda (err stream)
             (format stream "Promise condition with <~s>"
                     (promise-condition-data err)))))

(define-condition promise-warning (warning promise-condition)
  ((reason :initarg :reason :initform nil :accessor promise-warning-reason))
  (:report (lambda (err stream)
             (format stream "Promise warn <~d> with <~s>"
                     (promise-warning-reason err)
                     (promise-condition-data err)))))

(define-condition promise-error (error promise-condition)
  ((reason :initarg :reason :initform nil :accessor promise-error-reason))
  (:report (lambda (err stream)
             (format stream "Promise error <~d> with <~s>"
                     (promise-error-reason err)
                     (promise-condition-data err)))))

(define-condition promise-resolve-condition (promise-condition)
  ()
  (:report (lambda (condition stream)
             (format stream "Promise resolved with value <~s>"
                     (promise-condition-data condition)))))

(defun make-promise-condition (data)
  (make-instance 'promise-condition :data data))

(defun make-promise-warning (data reason)
  (make-instance 'promise-warning :data data :reason reason))

(defun make-promise-error (data reason)
  (make-instance 'promise-error :data data :reason reason))

(defun make-promise-resolve-condition (value)
  (make-instance 'promise-resolve-condition :data value))

(defun signal-promise-condition (data)
  (signal 'promise-condition :data data))

(defun signal-promise-warning (data reason)
  (warn 'promise-warning :data data :reason reason))

(defun signal-promise-error (data reason)
  (error 'promise-error :data data :reason reason))

(defun signal-promise-resolving (value)
  "signal this condition to make a non-local exit.
this function is suggested to be invoked explicity after calling resolve and do not want to execute the codes there after."
  (signal 'promise-resolve-condition :data value))

;;; promise class definition

;; forward: used when one promise should be fulfillment by another promise,
;;   this happens when the work-item-fn returns a promise.
;;   In a forward chain, this slot shared among the promises:
;;     the 0th place keeps the original promise and the 1st keeps the last,
;;     all the intermediate promises can be passed as I considered.
;; finished-p: even if the work-item's status is :finished, the promise may not finish yet,
;;   and thus finished-p provides further info:
;;     T for result's OK, NIL for errored or not finished yet
(defclass promise (work-item)
  ((callbacks  :initarg :callbacks  :initform (make-queue 10 nil) :accessor promise-callbacks)
   (errbacks   :initarg :errbacks   :initform (make-queue 10 nil) :accessor promise-errbacks)
   (forward    :initarg :forward    :initform (make-array 2 :initial-element nil) :accessor promise-forward)
   (resolved-p :initarg :resolved-p :initform nil :accessor promise-resolved-p)
   (finished-p :initarg :finished-p :initform nil :accessor promise-finished-p)
   (rejected-p :initarg :rejected-p :initform nil :accessor promise-rejected-p)
   (errored-p  :initarg :errored-p  :initform nil :accessor promise-errored-p)
   (error-obj  :initarg :error-obj  :initform nil :accessor promise-error-obj)
   ))

(defmethod initialize-instance :after ((promise promise) &key &allow-other-keys)
  (with-slots (forward) promise
    (setf (svref forward 0) promise)))

(defun inspect-promise (promise)
  "Return a detail description of the promise."
  (format nil (format nil "name: ~d, status: ~d, result: ~d, resolved: ~d, rejected: ~d, finishedp: ~d, errored-p: ~d~@[, error object: ~d~], there are ~d callbacks and ~d errbacks, forward to: ~d."
                      (work-item-name promise)
                      (atomic-place (work-item-status promise))
                      (work-item-result promise)
                      (promise-resolved-p promise)
                      (promise-rejected-p promise)
                      (promise-finished-p promise)
                      (promise-errored-p promise)
                      (when (promise-errored-p promise) (promise-error-obj promise))
                      (queue-count (promise-callbacks promise))
                      (queue-count (promise-errbacks promise))
                      (svref (promise-forward promise) 1))))

(defmethod print-object ((promise promise) stream)
  (print-unreadable-object (promise stream :type t)
    (format stream (inspect-promise promise))))

(defun promisep (promise)
  "Is this a promise?"
  (subtypep (type-of promise) 'promise))

(defun make-empty-promise (&optional (pool *default-thread-pool*) (name (string (gensym "PROMISE-"))))
  "Return an empty promise with nil fn slot."
  (change-class (make-work-item :pool pool :name name) 'promise))

(defun make-promise (fn &key (pool *default-thread-pool*)
                          (name (string (gensym "PROMISE-")))
                          bindings desc)
  "This function returns an promise instance by specifying it's work-item-fn.
`fn', the create function, is a function which accepts exact one argument: an promise object, which is the work-item's workload function.

The functions resolve and reject can be called within the body of fn to resolve or reject the promise accordingly.

The value returned by `fn' should be the result of the workload which can be the real result, a promise, or a condition if an error signals.

so, if there's no error signaled, this result will:
1. fullfill the promise, 2. as a normal return to fill the result slot of the promise object.

Thus the template of the create function `fn' would like:
  (lambda (promise)
    (let* ((result-or-condition (run-the-real-workload)))
      (resolve-or-reject-the-promise) ; by invkoing resolve or reject
      result-or-condition))

by using with-condition-handling, errors will be handled with rejecte called."
  ;; (funcall (work-item-fn (make-promise (lambda (p) (declare (ignore p)) (+ 1 2 3)))))
  ;; (add-work (make-promise (lambda (p) (declare (ignore p)) (+ 1 2 3))))
  (let* ((work (change-class (make-work-item :pool pool
                                             :name name
                                             :desc desc)
                             'promise)))
    (setf (work-item-fn work) (wrap-bindings
                               (lambda ()
                                 (let ((*promise* work))
                                   (with-condition-handling
                                       (lambda (err)
                                         (funcall (alexandria:curry #'reject work) err) ; (reject work err)
                                         (return-from exit-on-condition err))
                                     (funcall fn work))))
                               bindings))

    work))

(defmacro with-promise ((promise &key (pool *default-thread-pool*) bindings (name (string (gensym "PROMISE-"))) desc)
                        &body body)
  "Make a promise instance by specify it's create-function's body.
The functions resolve and reject can be called within `body' to resolve or reject the new promise accordingly.
Like the function make-promise, with-promise's `body' parameter should return the result of the workload.
This is the preferred way to make a promise."
  ;; (with-promise (promise) (+ 1 1))
  ;; (funcall (work-item-fn (with-promise (promise) (+ 1 1))))
  ;; (with-promise (promise :bindings '((a 1) (b 2))) (+ a b))
  ;; (funcall (work-item-fn (with-promise (promise :bindings '((a 1) (b 2))) (+ a b))))
  ;; (add-work (with-promise (promise :bindings '((a 1) (b 2))) (+ a b)))
  `(let* ((work (change-class (make-work-item :pool ,pool
                                              :name ,name
                                              :desc ,desc)
                              'promise))
          (fn (make-unary (,promise) ,@body)))
     ;;( setf (work-item-fn work) (wrap-bindings fn ,bindings work))
     (setf (work-item-fn work) (wrap-bindings (lambda ()
                                                (let ((*promise* work))
                                                  (with-condition-handling
                                                      (lambda (err)
                                                        (funcall (alexandria:curry #'reject work) err) ; (reject work err)
                                                        (return-from exit-on-condition err))
                                                    (funcall fn work))))
                                              ,bindings))
     work))

(defmethod promise-chain-head ((promise promise))
  "Return the first promise of a promise chain."
  (svref (promise-forward promise) 0))

(defmethod promise-chain-tail ((promise promise))
  "Return the last promise of a promise chain."
  (svref (promise-forward promise) 1))

(defmethod attach-callback ((promise promise) callback-to callback-fn)
  "Enqueue an callback to the promise.
A callback is a length-2 list whose car is any object (may be another promise, or even be nil),
and whose cadr is a function that accepts at least two args:
   the callbacked object, and the result of the promise. (lambda (obj &rest result) ... )
If a promise is chained to another promise, the callback should designed to fulfillment the promised chained."
  (enqueue (list callback-to callback-fn)
           (slot-value promise 'callbacks))
  promise)

(defmethod attach-errback ((promise promise) errback-to errback-fn)
  "Enqueue an error callback to the promise.
An error callback is a length-2 list whose car is any object (may be another promise, or even be nil),
and whose cadr is a function that accepts exactly two args:
   the callbacked object, and the error-obj of the promise. (lambda (obj err) ... )
"
  (enqueue (list errback-to errback-fn)
           (slot-value promise 'errbacks))
  promise)

(defmethod attach-echoback ((promise promise) echoback-obj callback-fn errback-fn)
  "In many circumstance, an callback and an errback should be avaliable for the same object in a promise.
And `attach-echoback' attach both callback and errback to the promise.
`echoback-obj' is such an object and callback-fn, errback-fn are the echo functions, correspondingly"
  (attach-callback promise echoback-obj callback-fn)
  (attach-errback  promise echoback-obj errback-fn)
  promise)

(defmethod do-callbacks :before ((promise promise))
  "Check if some promise's status is :finished with a non-promise result while the finished-p slot is nil.
This happens in a degenerated promise (a promise whose function has neither referenced to the promise object nor resolve/reject it)"
  ;; this is a scratchy patch, the code can be placed on a better place!
  ;; can put it in the clean form or unwind-protect when making a promise
  (when (and (eq :finished (get-status promise))
             (null (promise-finished-p promise))
             (null (promisep (car (get-result promise))))) ; add null, 03/21
    (setf (slot-value promise 'finished-p) t)))

(defmethod do-callbacks ((promise promise))
  "Deal with all callbacks"
  (when (promise-finished-p promise)
    (with-slots (callbacks result) promise
      (unless (queue-empty-p callbacks)
        (loop until (queue-empty-p callbacks) ; Oh, I've misused unless and trapped!
              do (let* ((callback (dequeue callbacks))
                        (callback-obj (car callback))
                        (callback-fn  (cadr callback)))
                   (apply callback-fn callback-obj result))))))
  promise)

(defmethod do-errbacks ((promise promise))
  "Deal with all errbacks"
  (when (promise-errored-p promise)
    (with-slots ((errbacks errbacks) (condition error-obj)) promise
      (unless (queue-empty-p errbacks)
        (loop until (queue-empty-p errbacks)
              do (let* ((errback (dequeue errbacks))
                        (errback-obj (car errback))
                        (errback-fn  (cadr errback)))
                   (funcall errback-fn errback-obj condition))))))
  promise)

(defmethod do-echobacks ((promise promise))
  "Deal with all callbacks and errbacks."
  (do-callbacks promise)
  (do-errbacks promise)
  promise)

(defmethod do-abnormal-status ((promise promise) status)
  "Deal with work-item's statuses"
  ;; :created :running :aborted :ready :finished :cancelled :rejected, and a new :errored
  ;; :aborted, when an error is captured by thread-main without
  ;; :errored, when something is called explicitly by reject, or an error is signaled
  (case status
    (:aborted (reject promise (make-promise-error :aborted "Aborted by thread pool.")))
    (:rejected (reject promise (make-promise-error :rejected "Rejected by thread pool.")))
    (:cancelled (reject promise (make-promise-error :cancelled "Cancelled by thread pool.")))
    ;;(:errored (reject promise (make-promise-error :cancelled "Cancelled by thread pool."))) ; :errored should have been rejected
    (otherwise t))
  promise)


(defmethod run-promise ((promise promise))
  "Run a promise in the current thread.
Check to run first, then process all callbacks and errorbacks of the promise in order.
Note: 1. invoking this method only when the promise has finished (The final result has got out or an error has signaled).
      2. the slots of result, status, finished, errored-p, error-obj should have already been set.
      3. although this method can be invoked in the main thread,
         sending a promise to a thread pool is recommondated,
         this method is invoked by resolve and is not exported."
  (let ((status (get-status promise)))
    (when (eq status :created)
      (set-status promise :running)
      (let ((new-result (multiple-value-list (funcall (work-item-fn promise)))))
        (cond ((promisep (car new-result)) ; the promise should habe been rejected if an error was signaled
               (resolve promise new-result))
              ((null (work-item-result promise))
               (resolve promise new-result))
              ((promise-finished-p promise)
               (format *debug-io* "The promise has been finished, promise:~d, value: ~d~%" promise new-result))
              ((promise-resolved-p promise)
               (format *debug-io* "The promise has been resolved, promise:~d, value: ~d~%" promise new-result))
              ((promise-rejected-p promise)
               (format *debug-io* "The promise has been rejected, promise:~d, value: ~d~%" promise new-result))
              ((typep (car new-result) 'error)
               (format *debug-io* "Error should have been handled in `run-promise`, when this was printed, there must be a bug, promise:~d, value: ~d~%" promise new-result))
              (t (format *debug-io* "When this was printed, there may be a bug, promise:~d, value: ~d~%" promise new-result))))))
  (do-abnormal-status promise (get-status promise))
  ;;(do-callbacks promise) ; should only be calleb by resolve
  ;;(do-errbacks promise)) ; should only be called by reject
  promise)

(defmethod run-promise :after ((promise promise))
  (when (eq :running (get-status promise)) ; if error signaled in work-item-fn, the status will be changed
    (set-status promise :finished)))


;;; the core resolve and reject method

;; resolve
(defmethod resolve-promise% ((promise promise) &rest args)
  "Resolve a promise with a final value, or another promise.
If the promise is resolved with a promise, set the later to the forward."
  (set-result promise args)
  (set-status promise :finished)
  (if (promisep (car args))
      (let ((new-promise (car args)))
        (setf (svref (promise-forward promise) 1) new-promise)
        (setf (slot-value new-promise 'forward) (promise-forward promise))
        (set-status new-promise :created) ; this setf deal with a promise fulfillment with itself
        (run-promise new-promise))  ; can send it to the pool either, and if sent, should change its status to :created
      (setf (slot-value promise 'finished-p) t))
  (setf (slot-value promise 'resolved-p) t)
  promise)

(defmethod resolve-promise% :after ((promise promise) &rest args)
  "Deal with the callbacks, and, if this promise is the tail of the chain, try to resolve the head."
  (do-callbacks promise)
  ;; eq denotes that it's a forwarded promise,
  ;; the head is not compared, for the sake that one might resolve a promise with itself (may be useless)
  (when (and (null (promisep (car args)))
             (eq promise (promise-chain-tail promise))
             (null (eq (promise-chain-head promise) (promise-chain-tail promise)))) ; get rid of repeat solving
    (apply #'resolve (promise-chain-head promise) args)))   ; and resolve the head promise again.

;; reject
(defmethod reject-promise% ((promise promise) condition)
  "Reject a promise with a condition, set related slots, do the errbacks."
  (set-result promise condition) ; will change status to :finished
  (set-status promise :errored)
  (setf (slot-value promise 'error-obj) condition
        (slot-value promise 'errored-p) t
        (slot-value promise 'rejected-p) t)
  promise)

(defmethod reject-promise% :after ((promise promise) condition)
  "Deal with the errbacks, and, if this promise is the tail of the chain, reject the head."
  (do-errbacks promise)
  ;; eq denotes that this promise is a forwarded promise,
  ;; the head is not compared, for the sake that one might reject a promise with itself (may be useless)
  (when (and (eq promise (promise-chain-tail promise))
             (null (eq (promise-chain-head promise) (promise-chain-tail promise)))) ; get rid of repeat solving
    (reject (promise-chain-head promise) condition)))   ; and reject the head promise again.

(defmethod resolve ((promise promise) &rest args)
  "Resolve a promise with the final value, or another promise, and support resolving the promise with itself.
Resolve is top to bottom, then bottom to top.
The intermediate of the forward chain can be passed as I considered."
  ;; do not add non-local exits to resolve :after methos since it will break echobacks
  (apply #'resolve-promise% promise args)
  promise)

(defmethod reject ((promise promise) condition)
  "Reject a promise with a condition instance.
Reject is bottom to top, since the forwarded promise is only something that takes place of the head promise's result in the future,
If an error' signaled in a promise, it cannot propagate to the bottom.
However, if an error's signaled, it should propagate to the top to reject the head promise.
A promise can be rejected with anything while a condition is preferred since it has the uniform interface."
  (if *promise-error*
      (unless (promise-rejected-p promise)
        (reject-promise% promise condition))
      (if (typep condition 'error)
          (error condition)
          (signal-promise-error condition (string (gensym "PROMISE-ERROR-")))))
  promise)


;;; some utils

(defun promisify-fn (fn &key (pool *default-thread-pool*) (name (string (gensym "FN-PROMISIFIED-"))))
  "Turns any value or set of values into a promise, unless a promise is passed in which case it is returned."
  (let ((promise (make-empty-promise pool name)))
    (with-condition-handling
        (lambda (err)
          (reject promise err)
          (do-errbacks promise)
          (return-from exit-on-condition))
      (let* ((vals (multiple-value-list (funcall fn)))
             (promise-maybe (car vals)))
        (if (promisep promise-maybe)
            (setf promise promise-maybe)
            (apply 'resolve promise vals))))
    promise))

(defmacro promisify-form (&rest forms)
  "Turns the forms into a nullary function, the encapsulate it with promisify-fn and finally return a promise."
  ;; (promisify 1)
  ;; (promisify (+ 1 1))
  ;; (promisify (error "xx"))
  `(promisify-fn (lambda ()
                   ,@forms)))


#+:ignore
(defmethod find-forward ((promise promise)) ; not been used
  "Check if this promise has been forwarded.
Return nil if it has no forward promise, else return the forwarded promise object.
Note that promises in a chain shared one forward, the intermediate promise takes no effect in fact."
  (svref (promise-forward promise) 1))
