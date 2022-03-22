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
  "signal this condition to make a non-local exit."
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

(defun inspect-promise (promise)
  "Return a detail description of the promise."
  (format nil (format nil "name: ~d, status: ~d, result: ~d, resolved: ~d, rejected: ~d, finishedp: ~d, errored-p: ~d~@[, error object: ~d~], there are ~d callbacks and ~d errbacks, forward chain previous: ~d, forward chain next: ~d, pool: ~d."
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
                      (alexandria:when-let (prev (svref (promise-forward promise) 0))
                        (work-item-name prev))
                      (alexandria:when-let (next (svref (promise-forward promise) 1))
                        (work-item-name next))
                      (alexandria:when-let (pool (work-item-pool promise))
                        (thread-pool-name pool)))))

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
                                         (funcall (alexandria:curry #'reject work) err)
                                         (return-from exit-on-condition err))
                                     (let ((result% (multiple-value-list (funcall fn work))))
                                       (unless (promise-resolved-p *promise*) ; will not enter here if errored
                                         (apply #'resolve *promise* result%)
                                         (apply #'values result%))
                                     ))))
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
     (setf (work-item-fn work) (wrap-bindings (lambda ()
                                                (let ((*promise* work))
                                                  (with-condition-handling
                                                      (lambda (err)
                                                        (funcall (alexandria:curry #'reject work) err)
                                                        (return-from exit-on-condition err))
                                                    (let ((result% (multiple-value-list (funcall fn work))))
                                                      (unless (promise-resolved-p *promise*) ; will not enter here if errored
                                                        (apply #'resolve *promise* result%)
                                                        (apply #'values result%))))))
                                              ,bindings))
     work))

(defmacro promise-chain-previous (promise)
  "Return the first promise of a promise chain."
  (let ((promise% (gensym)))
    `(let ((,promise% ,promise))
       (svref (promise-forward ,promise%) 0))))

(defmacro promise-chain-next (promise)
  "Return the last promise of a promise chain."
  (let ((promise% (gensym)))
    `(let ((,promise% ,promise))
       (svref (promise-forward ,promise%) 1))))

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
   the callbacked object, and the error-obj of the promise. (lambda (obj err) ... )"
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

(defmethod do-callbacks ((promise promise))
  "Deal with all callbacks"
  (when (promise-finished-p promise)
    (with-slots (callbacks result) promise
      (unless (queue-empty-p callbacks)
        (loop until (queue-empty-p callbacks)
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
        (setf (svref (promise-forward new-promise) 0) promise)
        (set-status new-promise :created) ; this may be a redundancy
        (attach-echoback new-promise
                         promise
                         (lambda (promise &rest values)
                           (apply #'resolve promise values))
                         (lambda (promise condition) (reject promise condition)))
        (add-work new-promise))
      (setf (slot-value promise 'finished-p) t))
  (setf (slot-value promise 'resolved-p) t) ; this slot can be modified if it's forward promise is rejected.
  promise)

(defmethod resolve-promise% :after ((promise promise) &rest args)
  "Deal with the callbacks, and, if this promise is the tail of the chain, try to resolve the head."
  (do-callbacks promise) ; do-callbacks checks finished-p
  (when (and (null (promisep (car args)))
             (promisep (promise-chain-previous promise)))
    (apply #'resolve (promise-chain-previous promise) args)))

;; reject
(defmethod reject-promise% ((promise promise) condition)
  "Reject a promise with a condition (or others), set related slots, do the errbacks."
  (set-result promise condition)
  (set-status promise :errored)
  (setf (slot-value promise 'resolved-p) nil ; should setf again since it may have been resolved by a forward promise
        (slot-value promise 'finished-p) nil
        (slot-value promise 'error-obj) condition
        (slot-value promise 'errored-p) t
        (slot-value promise 'rejected-p) t)
  promise)

(defmethod reject-promise% :after ((promise promise) condition)
  "Deal with the errbacks, and, if this promise is the tail of the chain, reject the head."
  (do-errbacks promise) ; do-errbacks checks errored-p
  (when (promisep (promise-chain-previous promise))
    (reject (promise-chain-previous promise) condition))) ; the previous promise may have been resolved.

(defmethod resolve ((promise promise) &rest args)
  "Resolve a promise with the final value, or another promise, and support resolving the promise with itself.
Resolve is top to bottom, then bottom to top.
The intermediate of the forward chain can be passed as I considered."
  (apply #'resolve-promise% promise args)
  promise)

(defmethod resolve :after ((promise promise) &rest args)
  "Doing this will not go on running the codes below resolve.
Checking if current promise eq to *promise*, to avoid exiting from the echobacks chain."
  (when (eq promise *promise*)
    (apply #'signal-promise-resolving args)))

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
  (let* ((work (make-empty-promise pool name))
         (*promise* work))
    (with-condition-handling
        (lambda (err)
          (funcall (alexandria:curry #'reject work) err)
          (reject work err)
          (return-from exit-on-condition work))
      (let ((result% (multiple-value-list (funcall fn))))
        (unless (promise-resolved-p *promise*) ; will not enter here if errored
          (apply #'resolve *promise* result%)
          (apply #'values result%))))
    work))

(defmacro promisify-form (&rest forms)
  "Turns the forms into a nullary function, the encapsulate it with promisify-fn and finally return a promise."
  ;; (promisify-form 1)
  ;; (promisify-form (+ 1 1))
  ;; (promisify-form (error "xx"))
  `(promisify-fn (lambda ()
                   ,@forms)))
