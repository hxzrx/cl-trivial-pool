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
  ((callbacks  :initarg :callbacks  :initform nil :type list :accessor callbacks)
   (errbacks   :initarg :errbacks   :initform nil :type list :accessor errbacks)
   (forward    :initarg :forward    :initform nil :accessor forward)
   (error-obj  :initarg :error-obj  :initform nil :accessor error-obj)
   ;; even if the work-item's status is :finished, the promise may not finish yet, and thus finished-p provides further info
   (finished-p :initarg :finished-p :initform nil :accessor finished-p)
   ))

(defmethod finish-promise ((promise promise) &rest args)
  ;; there will be a method combine to set other slot such as status
  (setf (work-item-result promise) args))

(defmethod reject-promise ((promise promise) condition)
  ;; method combinitions also
  (setf (slot-value promise 'error-obj) condition))

(defmacro make-resolve-fn (promise)
  "Return an function that accept any numbers of arguments to finish the promise"
  ;; (funcall (make-resolve-fn (make-instance 'promise)) 1 2 3)
  (let ((pm (gensym)))
    `(lambda (&rest args)
       (let ((,pm ,promise))
         (apply #'finish-promise ,pm args)))))

(defmethod resolve ((promise promise) &rest args)
  (apply #'finish-promise promise args))

(defmethod reject ((promise promise) condition)
  (reject-promise promise condition))

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
"
  ;; (funcall (work-item-fn (make-promise (lambda (p) (declare (ignore p)) (+ 1 2 3)))))
  ;; (add-work (make-promise (lambda (p) (declare (ignore p)) (+ 1 2 3))))
  (let* ((work (change-class (make-work-item :pool pool
                                             :name name
                                             :desc desc)
                             'promise)))
    (setf (work-item-fn work) (wrap-bindings fn bindings work))
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
     (setf (work-item-fn work) (wrap-bindings fn ,bindings work))
     work))
