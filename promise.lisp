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
;;;;
;;;; promise可以看作是work的推广, work是promise的一种特殊形式.
;;;; 其区别主要在于, work只是单纯的执行一个计算, 若不考虑排队事件, 可以认为是瞬间执行的呃.
;;;; 而promise是在将来某个时间点才能完成, 其完成还依赖于其它条件, 其完成结果可能是另一个promise,
;;;; 因此需要回调, 底层promise彻底完成后沿着回调链逐级回调到最初的promise, 沿路所有promise都会得到解决.
;;;; 另一个区别是, promise包含了完成事件的回调,
;;;; 当得到解决时通知所关联的其它事件, 这个事件不一定是关联到promise, 可能仅仅是一般简单的调用某个函数.

(in-package :promise)

;;; conditions definition

(define-condition promise-condition (condition)
  ((reason :initarg :reason :initform nil :accessor reason)
   (value  :initarg :value  :initform nil :accessor value))
  (:report (lambda (err stream)
             (format stream "The promise was signaled a condition <~d> with value <~s>" (reason err) (value err)))))

(define-condition promise-warning (warning promise-condition)
  ()
  (:report (lambda (err stream)
             (format stream "The promise was signaled an warning for an warn <~d> with value <~s>" (reason err) (value err)))))

(define-condition promise-error (error promise-condition)
  ()
  (:report (lambda (err stream)
             (format stream "The promise was signaled an error <~d> with value <~s>" (reason err) (value err)))))

(defun signal-promise-condition (reason value)
  (signal 'promise-condition :reason reason :value value))

(defun signal-promise-warning (reason value)
  (warn 'promise-warning :reason reason :value value))

(defun signal-promise-error (reason value)
  (error 'promise-error :reason reason :value value))


;;; promise class definition

(defclass promise (work-item)
  ((callbacks  :initarg :callbacks  :initform (make-queue) :type list :accessor promise-callbacks)
   (errbacks   :initarg :errbacks   :initform (make-queue) :type list :accessor promise-errbacks)
   ;; used when one promise should be fulfillment by another promise, this happens when the work-item-fn return a promise.
   ;; in a forward chain, this slot shared among the promises, the 0th place keeps the original promise and the 1st keeps the last.
   (forward    :initarg :forward    :initform (make-array 2 :initial-element nil) :accessor promise-forward)
   ;; even if the work-item's status is :finished, the promise may not finish yet, and thus finished-p provides further info
   ;; T for result's OK, NIL for errored or not finished yet
   (finished-p :initarg :finished-p :initform nil :accessor promise-finished-p)
   (errored-p  :initarg :errored-p  :initform nil :accessor promise-errored-p)
   (error-obj  :initarg :error-obj  :initform nil :accessor promise-error-obj)
   ))

(defmethod initialize-instance :after ((promise promise) &key &allow-other-keys)
  (with-slots (forward) promise
    (setf (svref forward 0) promise)))

(defun inspect-promise (promise)
  "Return a detail description of the promise."
  (format nil (format nil "name: ~d, status: ~d, result: ~d, finishedp: ~d, errored-p: ~d~@[, error object: ~d~], there are ~d callbacks and ~d errbacks, forward to: ~d."
                      (work-item-name promise)
                      (atomic-place (work-item-status promise))
                      (work-item-result promise)
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

(defmethod promise-chain-head ((promise promise))
  "Return the first promise of a promise chain."
  (svref (promise-forward promise) 0))

(defmethod promise-chain-tail ((promise promise))
  "Return the last promise of a promise chain."
  (svref (promise-forward promise) 1))

(defmethod resolve-promise% ((promise promise) &rest args)
  "Resolve a promise with a final value, or another promise."
  (set-result promise args)
  (set-status promise :finished)
  (if (promisep (car args))
      (let ((new-promise (car args)))
        (setf (svref (promise-forward promise) 1) new-promise)
        (setf (slot-value new-promise 'forward) (promise-forward promise))
        (run-promise new-promise))  ; can send it to the pool either
      (setf (slot-value promise 'finished-p) t))
  promise)

(defmethod resolve-promise% :after ((promise promise) &rest args)
  "Deal with the callbacks, and, if this promise is the tail of the chain, resolve the head."
  (do-callbacks promise)
  ;; eq denotes that it's a forwarded promise,
  ;; the head is not compared, for the sake that one might resolve a promise with itself (may be useless)
  (when (and (eq promise (promise-chain-tail promise))
             (null (eq (promise-chain-head promise) (promise-chain-tail promise)))) ; get rid of repeat solving
    (resolve-promise% (promise-chain-head promise) args)))   ; and resolve the head promise again.


(defmethod reject-promise% ((promise promise) condition)
  ;; method combinitions also
  (set-result promise condition)
  (set-status promise :finished)
  (setf (slot-value promise 'error-obj) condition
        (slot-value promise 'errored-p) t)
  promise)

(defmethod reject-promise% :after ((promise promise) condition)
  "Deal with the errbacks, and, if this promise is the tail of the chain, reject the head."
  (do-errbacks promise)
  ;; eq denotes that it's a forwarded promise,
  ;; the head is not compared, for the sake that one might reject a promise with itself (may be useless)
  (when (and (eq promise (promise-chain-tail promise))
             (null (eq (promise-chain-head promise) (promise-chain-tail promise)))) ; get rid of repeat solving
    (reject-promise% (promise-chain-head promise) condition)))   ; and reject the head promise again.

(defmethod resolve ((promise promise) &rest args)
  "Resolve a promise with the final value, or another promise, and support resolving the promise with itself."
  (apply #'resolve-promise% promise args))

(defmethod reject ((promise promise) condition)
  "Reject a promise with a condition instance."
  (reject-promise% promise condition))

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

by using with-error-handling, errors will be handled with rejecte called.
"
  ;; (funcall (work-item-fn (make-promise (lambda (p) (declare (ignore p)) (+ 1 2 3)))))
  ;; (add-work (make-promise (lambda (p) (declare (ignore p)) (+ 1 2 3))))
  (let* ((work (change-class (make-work-item :pool pool
                                             :name name
                                             :desc desc)
                             'promise)))
    (setf (work-item-fn work) (wrap-bindings
                               (lambda ()
                                (let ((*promise* work))
                                  (with-error-handling
                                      (lambda (err)
                                        (funcall (alexandria:curry #'reject work) err) ; (reject work err)
                                        (return-from exit-on-error))
                                    (funcall fn work))))
                               bindings))

    work))

(defmacro with-promise ((promise &key (pool *default-thread-pool*) bindings name desc) &body body)
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
                                                  (with-error-handling
                                                      (lambda (err)
                                                        (funcall (alexandria:curry #'reject work) err) ; (reject work err)
                                                        (return-from exit-on-error))
                                                    (funcall fn work))))
                                              ,bindings))
     work))

(defmethod attach-callback ((promise promise) callback-to callback-fn)
  "Enqueue an callback to the promise.
A callback is a length-2 list whose car is any object (may be another promise, or even be nil),
and whose cadr is a function that accepts at least two args:
   the callbacked object, and the result of the promise. (lambda (obj &rest result) ... )
If a promise is chained to another promise, the callback should designed to fulfillment the promised chained."
  (enqueue (list callback-to callback-fn)
           (slot-value promise 'callbacks)))

(defmethod attach-errback ((promise promise) errback-to errback-fn)
  "Enqueue an error callback to the promise.
An error callback is a length-2 list whose car is any object (may be another promise, or even be nil),
and whose cadr is a function that accepts exactly two args:
   the callbacked object, and the error-obj of the promise. (lambda (obj err) ... )
"
  (enqueue (list errback-to errback-fn)
           (slot-value promise 'errbacks)))

(defmethod attach-echoback ((promise promise) echoback-obj callback-fn errback-fn)
  "In many circumstance, an callback and an errback should be avaliable for the same object in a promise.
And `attach-echoback' attach both callback and errback to the promise.
`echoback-obj' is such an object and callback-fn, errback-fn are the echo functions, correspondingly"
  (attach-callback promise echoback-obj callback-fn)
  (attach-errback  promise echoback-obj errback-fn))

(defmethod do-callback% ((promise promise) callback)
  "Deal with one callback"
  (let ((result (work-item-result promise))
        (callback-obj (car callback))
        (callback-fn  (cadr callback)))
    (apply callback-fn callback-obj result)))

(defmethod do-callbacks ((promise promise))
  "Deal with all callbacks"
  (when (promise-finished-p promise)
    (let ((callbacks (promise-callbacks promise)))
      (unless (queue-empty-p callbacks)
        (let ((result (work-item-result promise)))
          (loop unless (queue-empty-p callbacks)
                do (let* ((callback (dequeue callbacks))
                          (callback-obj (car callback))
                          (callback-fn  (cadr callback)))
                     (apply callback-fn callback-obj result)))))))
  promise)

(defmethod do-errback% ((promise promise) errback)
  "Deal with one errback"
  (let ((condition (promise-error-obj promise))
        (errback-obj (car errback))
        (errback-fn  (cadr errback)))
    (apply errback-fn errback-obj condition)))

(defmethod do-errbacks ((promise promise))
  "Deal with all errbacks"
  (when (promise-errored-p promise)
    (let ((errbacks (promise-errbacks promise)))
      (unless (queue-empty-p errbacks)
        (let ((condition (promise-error-obj promise)))
          (loop unless (queue-empty-p errbacks)
                do (let* ((errback (dequeue errbacks))
                          (errback-obj (car errback))
                          (errback-fn  (cadr errback)))
                     (apply errback-fn errback-obj condition)))))))
  promise)

(defmethod run-promise ((promise promise))
  "Processing all callbacks and errorbacks of the promise in order.
Note that invoking this method only when the promise has finished (The final result has got out or an error has signaled).
And Note that the slots of result, status, finished, errored-p, error-obj should have already been set."
  (if (promise-errored-p promise)
      (when (promise-errbacks promise)
        (with-slots (error-obj errbacks) promise
          (loop unless (queue-empty-p errbacks)
                  do (do-errback% promise (dequeue errbacks)))))
      (when (promise-finished-p promise)
        (with-slots (result callbacks) promise
          (loop unless (queue-empty-p callbacks)
                  do (do-callback% promise (dequeue callbacks))))))
  promise)

(defun promisify-fn (fn &key (pool *default-thread-pool*) (name (string (gensym "FN-PROMISIFIED-"))))
  "Turns any value or set of values into a promise, unless a promise is passed in which case it is returned."
  (let ((promise (make-empty-promise pool name)))
    (with-error-handling
        (lambda (err)
          ;;(signal-error promise err)
          (reject promise err)
          (do-errbacks promise)
          (return-from exit-on-error))
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

(defmethod find-forward ((promise promise))
  "Check if this promise has been forwarded.
Return nil if it has no forward promise, else return the forwarded promise object.
Note that promises in a chain shared one forward, the intermediate promise takes no effect in fact."
  (svref (promise-forward promise) 1))


;; 处理转发链, finished时, 在resolve的:after中, 查看是否有转发,
;; 如果有, 对转发再调用一次resolve函数, 如果是错误, 就调用reject函数.
