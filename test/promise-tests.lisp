(in-package :cl-trivial-pool-tests)

(defun gen-0 ()
  0)

(define-test make-promise-condition :parent promise
  (let* ((reason "some-reason")
         (data 123456)
         (condition (promise:make-promise-condition data reason))
         (warning   (promise:make-promise-warning data reason))
         (err       (promise:make-promise-error data reason)))
    (of-type promise:promise-condition condition)
    (of-type promise:promise-warning   warning)
    (of-type promise:promise-error     err)
    (is equal reason (slot-value condition 'promise::reason))
    (is equal data   (slot-value condition 'promise::data))
    (is equal reason (slot-value warning 'promise::reason))
    (is equal data   (slot-value warning 'promise::data))
    (is equal reason (slot-value err 'promise::reason))
    (is equal data   (slot-value err 'promise::data))))

(define-test signal-promise-condition :parent promise
  (fail (promise:signal-promise-error 123 "xxx"))
  (finish (promise:signal-promise-warning 123 "xxx"))
  (finish (promise:signal-promise-condition 123 "xxx")))

(define-test inspect-promise :parent promise
  (finish (promise:inspect-promise (make-instance 'promise:promise))))

(define-test promisep :parent promise
  (let ((promise (make-instance 'promise:promise))
        (work (tpool:make-work-item)))
    #+sbcl(is-values (promise:promisep promise) (eq t) (eq t))
    #-sbcl(is eql t (promise:promisep promise))

    #+sbcl(is-values (promise:promisep work) (eq nil) (eq t))
    #-sbcl(is eql nil (promise:promisep work))

    #+sbcl(is-values (tpool:work-item-p promise) (eq t) (eq t))
    #-sbcl(is eql t (tpool:work-item-p work))

    #+sbcl(is-values (tpool:work-item-p work) (eq t) (eq t))
    #-sbcl(is eql t (tpool:work-item-p work))))

(define-test make-empty-promise :parent promise
  (true (promise:promisep (promise:make-empty-promise))))

(define-test make-promise :parent promise
  (let* ((pool (tpool:make-thread-pool))
         ;; simple-promise degenerates to a normal work-item, so it will neither be resolved nor finished.
         (simple-promise (promise:make-promise (lambda (promise) (declare (ignore promise)) (+ 1 2 3)) :pool pool))
         ;; simple-err-promise degenerates to a normal work-item, but the error will be handled and rejected with that.
         (simple-err-promise (promise:make-promise (lambda (promise)
                                                     (declare (ignore promise))
                                                     (let* ((x (gen-0))
                                                            (y (/ 1 x)))
                                                       (format t "This cannot be reached, or there must be a bug!~%")
                                                       y))
                                                   :pool pool))
         ;; explicit resolve invoking
         (resolvable-promise (promise:make-promise (lambda (promise)
                                                     (let ((result (+ 1 2 3)))
                                                       (promise:resolve promise result)
                                                       result))
                                                   :pool pool))
         ;; error signaled by promise:signal-promise-error, this is also a degenerated normal work-item
         (rejectable-promise-1 (promise:make-promise (lambda (promise)
                                                       (declare (ignore promise))
                                                       (promise:signal-promise-error 123 "test error promise")
                                                       (format t "This cannot be reached, or there must be a bug!~%"))
                                                     :pool pool))
         ;; explicit reject invoking, reject with an promise-error
         (rejectable-promise-2 (promise:make-promise (lambda (promise)
                                                       (promise:reject promise (promise:make-promise-error 123 "xx"))
                                                       (format t "This cannot be reached, or there must be a bug!~%"))
                                                     :pool pool))
         ;; explicit reject invoking, reject with a normal error
         (rejectable-promise-3 (promise:make-promise (lambda (promise)
                                                       (promise:reject promise (make-instance 'error))
                                                       (format t "This cannot be reached, or there must be a bug!~%"))
                                                     :pool pool))
         ;; explicit reject invoking, reject with an ordinary data
         (rejectable-promise-4 (promise:make-promise (lambda (promise)
                                                       (promise:reject promise 123)
                                                       (format t "This cannot be reached, or there must be a bug!~%"))
                                                     :pool pool)))
    (finish (tpool:add-work simple-promise))
    (finish (tpool:add-work simple-err-promise))
    (finish (tpool:add-work resolvable-promise))
    (finish (tpool:add-work rejectable-promise-1))
    (finish (tpool:add-work rejectable-promise-2))
    (finish (tpool:add-work rejectable-promise-3))
    (finish (tpool:add-work rejectable-promise-4))
    (sleep 0.0001)
    ;; degenerated promise
    (is-values (tpool:get-result simple-promise) (equal (list 6)) (eq t))
    (is eq :finished (tpool:get-status simple-promise))
    (is eq nil (promise:promise-finished-p simple-promise)) ; will not be finished a normal work-item
    (is eq nil (promise:promise-resolved-p simple-promise)) ; will not be resolved either
    (is eq nil (promise:promise-rejected-p simple-promise))
    (is eq nil (promise:promise-errored-p  simple-promise))
    (is eq nil (promise:promise-error-obj  simple-promise))
    ;; degenerated promise with error signaled
    (is-values (tpool:get-result simple-err-promise) (eq nil) (eq nil))
    (of-type error (car (tpool:work-item-result simple-err-promise)))
    (is eq :errored (tpool:get-status simple-err-promise))
    (is eq nil (promise:promise-finished-p simple-err-promise))
    (is eq nil (promise:promise-resolved-p simple-err-promise))
    (is eq t   (promise:promise-rejected-p simple-err-promise))
    (is eq t   (promise:promise-errored-p  simple-err-promise))
    (of-type error (promise:promise-error-obj simple-err-promise))
    ;; resolvable promise
    (is-values (tpool:get-result resolvable-promise) (equal (list 6)) (eq t))
    (is eq :finished (tpool:get-status resolvable-promise))
    (is eq t   (promise:promise-finished-p resolvable-promise)) ; finished and resolved
    (is eq t   (promise:promise-resolved-p resolvable-promise))
    (is eq nil (promise:promise-rejected-p resolvable-promise))
    (is eq nil (promise:promise-errored-p  resolvable-promise))
    (is eq nil (promise:promise-error-obj  resolvable-promise))
    ;; rejectable promise, error signaled with promise:signal-promise-error, also a degenerated normal work-item
    (is-values (tpool:get-result rejectable-promise-1) (eq nil) (eq nil))
    (of-type error (car (tpool:work-item-result rejectable-promise-1)))
    (is eq :errored (tpool:get-status rejectable-promise-1))
    (is eq nil (promise:promise-finished-p rejectable-promise-1))
    (is eq nil (promise:promise-resolved-p rejectable-promise-1))
    (is eq t   (promise:promise-rejected-p rejectable-promise-1))
    (is eq t   (promise:promise-errored-p  rejectable-promise-1))
    (of-type error (promise:promise-error-obj rejectable-promise-1))
    ;; explicit reject invoking, reject with an promise-error
    (is-values (tpool:get-result rejectable-promise-2) (eq nil) (eq nil))
    (of-type error (car (tpool:work-item-result rejectable-promise-2)))
    (is eq :errored (tpool:get-status rejectable-promise-2))
    (is eq nil (promise:promise-finished-p rejectable-promise-2))
    (is eq nil (promise:promise-resolved-p rejectable-promise-2))
    (is eq t   (promise:promise-rejected-p rejectable-promise-2))
    (is eq t   (promise:promise-errored-p  rejectable-promise-2))
    (of-type error (promise:promise-error-obj rejectable-promise-2))
    ;; explicit reject invoking, reject with a normal error
    (is-values (tpool:get-result rejectable-promise-3) (eq nil) (eq nil))
    (of-type error (car (tpool:work-item-result rejectable-promise-3)))
    (is eq :errored (tpool:get-status rejectable-promise-3))
    (is eq nil (promise:promise-finished-p rejectable-promise-3))
    (is eq nil (promise:promise-resolved-p rejectable-promise-3))
    (is eq t   (promise:promise-rejected-p rejectable-promise-3))
    (is eq t   (promise:promise-errored-p  rejectable-promise-3))
    (of-type error (promise:promise-error-obj rejectable-promise-3))
    ;; explicit reject invoking, reject with an ordinary data
    (is-values (tpool:get-result rejectable-promise-4) (eq nil) (eq nil))
    (of-type error (car (tpool:work-item-result rejectable-promise-4)))
    (is eq :errored (tpool:get-status rejectable-promise-4))
    (is eq nil (promise:promise-finished-p rejectable-promise-4))
    (is eq nil (promise:promise-resolved-p rejectable-promise-4))
    (is eq t   (promise:promise-rejected-p rejectable-promise-4))
    (is eq t   (promise:promise-errored-p  rejectable-promise-4))
    (of-type error (promise:promise-error-obj rejectable-promise-4))
    ))

(define-test with-promise :parent promise
  (let* ((pool (tpool:make-thread-pool))
         ;; simple-promise degenerates to a normal work-item, so it will neither be resolved nor finished.
         (simple-promise (promise:with-promise (promise :pool pool) (+ 1 2 3)))
         ;; degenerated promise, with bindings specified
         (simple-promise-with-bindings (promise:with-promise (promise :bindings '((a 1) (b 2) (c 3)) :pool pool)
                                         (+ a b c)))
         ;; simple-err-promise degenerates to a normal work-item, but the error will be handled and rejected with that.
         (simple-err-promise (promise:with-promise (promise :pool pool :name "simple-err-promise")
                               (let* ((x (gen-0))
                                      (y (/ 1 x)))
                                 (format t "This cannot be reached, or there must be a bug!~%")
                                 y)))
         ;; explicit resolve invoking
         (resolvable-promise (promise:with-promise (promise :pool pool)
                               (let ((result (+ 1 2 3)))
                                 (promise:resolve promise result)
                                 result)))
         ;; error signaled by promise:signal-promise-error, this is also a degenerated normal work-item
         (rejectable-promise-1 (promise:with-promise (promise :pool pool)
                                 (promise:signal-promise-error 123 "test error promise")
                                 (format t "This cannot be reached, or there must be a bug!~%")))
         ;; explicit reject invoking, reject with an promise-error
         (rejectable-promise-2 (promise:with-promise (promise :pool pool)
                                 (promise:reject promise (promise:make-promise-error 123 "xx"))
                                 (format t "This cannot be reached, or there must be a bug!~%")))
         ;; explicit reject invoking, reject with a normal error
         (rejectable-promise-3 (promise:with-promise (promise :pool pool)
                                 (promise:reject promise (make-instance 'error))
                                 (format t "This cannot be reached, or there must be a bug!~%")))
         ;; explicit reject invoking, reject with an ordinary data
         (rejectable-promise-4 (promise:with-promise (promise :pool pool)
                                 (promise:reject promise 123)
                                 (format t "This cannot be reached, or there must be a bug!~%"))))
    (finish (tpool:add-work simple-promise))
    (finish (tpool:add-work simple-promise-with-bindings))
    (finish (tpool:add-work simple-err-promise))
    (finish (tpool:add-work resolvable-promise))
    (finish (tpool:add-work rejectable-promise-1))
    (finish (tpool:add-work rejectable-promise-2))
    (finish (tpool:add-work rejectable-promise-3))
    (finish (tpool:add-work rejectable-promise-4))
    (sleep 0.0001)

    ;; degenerated promise
    (is-values (tpool:get-result simple-promise) (equal (list 6)) (eq t))
    (is eq :finished (tpool:get-status simple-promise))
    (is eq nil (promise:promise-finished-p simple-promise)) ; will not be finished a normal work-item
    (is eq nil (promise:promise-resolved-p simple-promise)) ; will not be resolved either
    (is eq nil (promise:promise-rejected-p simple-promise))
    (is eq nil (promise:promise-errored-p  simple-promise))
    (is eq nil (promise:promise-error-obj  simple-promise))
    ;; degenerated promise with bindings
    (is-values (tpool:get-result simple-promise-with-bindings) (equal (list 6)) (eq t))
    (is eq :finished (tpool:get-status simple-promise-with-bindings))
    (is eq nil (promise:promise-finished-p simple-promise-with-bindings)) ; will not be finished a normal work-item
    (is eq nil (promise:promise-resolved-p simple-promise-with-bindings)) ; will not be resolved either
    (is eq nil (promise:promise-rejected-p simple-promise-with-bindings))
    (is eq nil (promise:promise-errored-p  simple-promise-with-bindings))
    (is eq nil (promise:promise-error-obj  simple-promise-with-bindings))
    ;; degenerated promise with error signaled
    (is-values (tpool:get-result simple-err-promise) (eq nil) (eq nil))
    (of-type error (car (tpool:work-item-result simple-err-promise)))
    (is eq :errored (tpool:get-status simple-err-promise))
    (is eq nil (promise:promise-finished-p simple-err-promise))
    (is eq nil (promise:promise-resolved-p simple-err-promise))
    (is eq t   (promise:promise-rejected-p simple-err-promise))
    (is eq t   (promise:promise-errored-p  simple-err-promise))
    (of-type error (promise:promise-error-obj simple-err-promise))
    (format t "......promise: ~d~%" simple-err-promise)
    ;; resolvable promise
    (is-values (tpool:get-result resolvable-promise) (equal (list 6)) (eq t))
    (is eq :finished (tpool:get-status resolvable-promise))
    (is eq t   (promise:promise-finished-p resolvable-promise)) ; finished and resolved
    (is eq t   (promise:promise-resolved-p resolvable-promise))
    (is eq nil (promise:promise-rejected-p resolvable-promise))
    (is eq nil (promise:promise-errored-p  resolvable-promise))
    (is eq nil (promise:promise-error-obj  resolvable-promise))
    ;; rejectable promise, error signaled with promise:signal-promise-error, also a degenerated normal work-item
    (is-values (tpool:get-result rejectable-promise-1) (eq nil) (eq nil))
    (of-type error (car (tpool:work-item-result rejectable-promise-1)))
    (is eq :errored (tpool:get-status rejectable-promise-1))
    (is eq nil (promise:promise-finished-p rejectable-promise-1))
    (is eq nil (promise:promise-resolved-p rejectable-promise-1))
    (is eq t   (promise:promise-rejected-p rejectable-promise-1))
    (is eq t   (promise:promise-errored-p  rejectable-promise-1))
    (of-type error (promise:promise-error-obj rejectable-promise-1))
    ;; explicit reject invoking, reject with an promise-error
    (is-values (tpool:get-result rejectable-promise-2) (eq nil) (eq nil))
    (of-type error (car (tpool:work-item-result rejectable-promise-2)))
    (is eq :errored (tpool:get-status rejectable-promise-2))
    (is eq nil (promise:promise-finished-p rejectable-promise-2))
    (is eq nil (promise:promise-resolved-p rejectable-promise-2))
    (is eq t   (promise:promise-rejected-p rejectable-promise-2))
    (is eq t   (promise:promise-errored-p  rejectable-promise-2))
    (of-type error (promise:promise-error-obj rejectable-promise-2))
    ;; explicit reject invoking, reject with a normal error
    (is-values (tpool:get-result rejectable-promise-3) (eq nil) (eq nil))
    (of-type error (car (tpool:work-item-result rejectable-promise-3)))
    (is eq :errored (tpool:get-status rejectable-promise-3))
    (is eq nil (promise:promise-finished-p rejectable-promise-3))
    (is eq nil (promise:promise-resolved-p rejectable-promise-3))
    (is eq t   (promise:promise-rejected-p rejectable-promise-3))
    (is eq t   (promise:promise-errored-p  rejectable-promise-3))
    (of-type error (promise:promise-error-obj rejectable-promise-3))
    ;; explicit reject invoking, reject with an ordinary data
    (is-values (tpool:get-result rejectable-promise-4) (eq nil) (eq nil))
    (of-type error (car (tpool:work-item-result rejectable-promise-4)))
    (is eq :errored (tpool:get-status rejectable-promise-4))
    (is eq nil (promise:promise-finished-p rejectable-promise-4))
    (is eq nil (promise:promise-resolved-p rejectable-promise-4))
    (is eq t   (promise:promise-rejected-p rejectable-promise-4))
    (is eq t   (promise:promise-errored-p  rejectable-promise-4))
    (of-type error (promise:promise-error-obj rejectable-promise-4))
    ))
