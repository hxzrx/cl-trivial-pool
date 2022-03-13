;;;; promise可以看作是work的推广, work是promise的一种特殊形式.
;;;; 其区别主要在于, work只是单纯的执行一个计算, 若不考虑排队事件, 可以认为是瞬间执行的呃.
;;;; 而promise是在将来某个时间点才能完成, 其完成还依赖于其它条件, 其完成结果可能是另一个promise,
;;;; 因此需要回调, 底层promise彻底完成后沿着回调链逐级回调到最初的promise, 沿路所有promise都会得到解决.
;;;; 另一个区别是, promise包含了完成事件的回调,
;;;; 当得到解决时通知所关联的其它事件, 这个事件不一定是关联到promise, 可能仅仅是一般简单的调用某个函数.

(in-package :cl-trivial-pool)

;;; conditions definition

(defun wrap-bindings (fn bindings)
  "wrap bindings to function `fn' who accept none parameters"
  ;; (funcall (wrap-bindings #'(lambda () (+ a b)) '((a 1) (b 2))))
  (if bindings
      (let ((vars (mapcar #'first bindings))
            (vals (mapcar #'second bindings)))
        (lambda () (progv vars vals
                     (funcall fn))))
      fn))

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
  "return an function that accept any numbers of arguments to finish the promise"
  ;; (funcall (make-resolve-fn (make-instance 'promise)) 1 2 3)
  (let ((pm (gensym)))
    `(lambda (&rest args)
       (let ((,pm ,promise))
         (apply #'finish-promise ,pm args)))))

(defmacro make-reject-fn (promise)
  ;; (funcall (make-reject-fn (make-instance 'promise)) :sss)
  (let ((pm (gensym)))
    `(lambda (condition)
       (let ((,pm ,promise))
         (funcall #'reject-promise ,pm condition)))))

(defun make-promise (&key create-fun
                       (pool *default-thread-pool*)
                       (name (string (gensym "PROMISE-")))
                       bindings desc)
  ;; create-fn is a function which accepts exact two arguments: the resolve function and the reject function.
  ;; the resolve function accept at least one argument to finish the promise,
  ;; the reject function accept an condition object and it's revoked when some error is signaled.
  (let* ((work (make-work-item :pool pool
                               :name name
                               :bindings bindings
                               :desc desc))
         (promise (change-class work 'promise))
         (resolve-fn (make-resolve-fn promise))
         (reject-fn (make-reject-fn promise)))
    (setf (work-item-fun promise)
          #'(lambda () (funcall create-fun resolve-fn reject-fn)))
    promise))


(defmacro make-create-fn-helper (promise resolve reject &body body)
  ;; the returned value of this function, should be the returnen value of body,
  ;; new promise can be created with the body, so the returned can be a promise, this will set to the promise's result slot.
  (declare (ignorable promise resolve reject))
  `(progn  ,@body))


(defmacro make-create-fn (promise-obj resolve-fn reject-fn &body body)
  ;; (funcall (make-create-fn 1 2 3 4))
  (declare (ignorable promise resolve reject))
  (lambda () (make-create-fn-helper promise resolve reject body)))


(defmacro with-promise ((promise resolve reject
                         &key; (promise-obj (gensym "promise-"))
                           ;(resolve-fn (gensym "resolve-fn"))
                           ;(reject-fn (gensym "reject-fn"))
                           (pool *default-thread-pool*)
                           bindings
                           name)
                        &body body)
  (let* ((promised-work (change-class (make-work-item :pool pool
                                                      :name name
                                                      :bindings bindings)
                                     'promise))
         (resolve-fn (make-resolve-fn promised-work))
         (reject-fn (make-reject-fn promised-work))
         (zero-arg-fun (lambda ()
                         `(let ((,promise ,promised-work))
                           (declare (ignorable ,promise))
                           (flet ((,resolve (&rest args) (apply ,resolve-fn args))
                                  (,reject (condition) (funcall ,reject-fn condition)))
                             (declare (ignorable ,resolve ,reject))
                             (let ((res (multiple-value-list (funcall #'(lambda () ,@body)))))
                               (unless (slot-value ,promise 'fun)
                                 (setf (slot-value ,promise 'result) res))
                               res))))))
    (setf (slot-value promised-work 'fun) zero-arg-fun)
    promised-work))
