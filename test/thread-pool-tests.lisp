(in-package :cl-trivial-pool-tests)


;;; tpool-utils

(defmacro make-parameterless-fun (fun &rest args)
  "(funcall (make-parameterless-fun + 1 3))"
  `(lambda ()
     (funcall #',fun ,@args)))

(defun make-random-list (n &optional (max 100))
  (loop for i below n collect (random max)))

(defun gen-n (n) n)


;;; ------- thread-pool -------

(define-test make-pool-and-inspect :parent pool
  (finish (tpool:inspect-pool (tpool:make-thread-pool)))
  ;;(fail (tpool:inspect-pool (tpool:make-thread-pool :keepalive-time -1))) ; this definitely fails but will signal compile error
  (finish (tpool:inspect-pool (tpool:make-thread-pool :name "" :max-worker-num 10 :keepalive-time 0)))
  (finish (tpool:inspect-pool (tpool:make-thread-pool :name "test pool" :max-worker-num 10 :keepalive-time 1))))

(define-test peek-backlog :parent pool
  (let ((pool (tpool:make-thread-pool)))
    (is eq nil (tpool::peek-backlog pool))
    (tpool-utils:enqueue :work1 (tpool::thread-pool-backlog pool))
    (is eq :work1 (tpool:peek-backlog pool))
    (tpool-utils:enqueue :work2 (tpool::thread-pool-backlog pool))
    (is eq :work1 (tpool:peek-backlog pool))
    (tpool-utils:dequeue (tpool::thread-pool-backlog pool))
    (is eq :work2 (tpool:peek-backlog pool))
    (tpool-utils:dequeue (tpool::thread-pool-backlog pool))
    (is eq nil (tpool:peek-backlog pool))))

(define-test make-work-item :parent pool
  (let ((pool (tpool:make-thread-pool)))
    (finish (tpool:inspect-work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                      :pool pool)))
    (finish (tpool:inspect-work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3))))
    (finish (tpool:inspect-work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                      :pool pool
                                                      :name "name")))
    (finish (tpool:inspect-work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                      :pool pool
                                                      :desc "desc")))
    (finish (tpool:inspect-work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                      :pool pool
                                                      :name "name"
                                                      :desc "desc")))))

(define-test add-work :parent pool
  (let* ((pool (tpool:make-thread-pool))
         (work0 (tpool:make-work-item :name "work0" :function #'(lambda () (+ 1 2 3)))) ; to test in default pool
         (work1 (tpool:make-work-item :name "work1" :function #'(lambda () (+ 1 2 3)))) ; to test in local pool, will be warned
         (work2 (tpool:make-work-item :name "work2" :function (make-parameterless-fun + 1 2 3) ; all test in local pool
                                      :pool pool))
         (work3 (tpool:make-work-item :name "work3" :function (make-parameterless-fun + 1 2 3)
                                      :pool pool))
         (work4 (tpool:make-work-item :name "work4" :function (make-parameterless-fun + 1 2 3)
                                      :pool pool))
         (work5 (tpool:make-work-item :name "work5" :function (make-parameterless-fun + 1 2 3)
                                      :pool pool))
         (work6 (tpool:make-work-item :name "work6" :function (make-parameterless-fun + 1 2 3)
                                      :pool pool))
         (work7 (tpool:make-work-item :name "work7" :function (make-parameterless-fun + 1 2 3)
                                      :pool pool))
         (work8 (tpool:make-work-item :name "work8" :function (make-parameterless-fun + 1 2 3)
                                      :pool pool))
         (work9 (tpool:make-work-item :name "work9" :function (make-parameterless-fun + 1 2 3)
                                      :pool pool)))
    (is eq :created (tpool:get-status work0))
    (is eq :created (tpool:get-status work1))
    (is eq :created (tpool:get-status work2))
    (finish (tpool:add-work work0))
    (finish (tpool:add-work work1 pool))
    (finish (tpool:add-work work2 pool))
    (finish (tpool:add-work work3 pool))
    (finish (tpool:add-work work4 pool))
    (finish (tpool:add-work work5 pool))
    (finish (tpool:add-work work6 pool))
    (finish (tpool:add-work work7 pool))
    (finish (tpool:add-work work8 pool))
    (finish (tpool:add-work work9 pool))
    (sleep 0.0001)
    (is equal (list 6) (tpool:get-result work0))
    (is equal (list 6) (tpool:get-result work1))
    (is equal (list 6) (tpool:get-result work2))
    (is equal (list 6) (tpool:get-result work3))
    (is equal (list 6) (tpool:get-result work4))
    (is equal (list 6) (tpool:get-result work5))
    (is equal (list 6) (tpool:get-result work6))
    (is equal (list 6) (tpool:get-result work7))
    (is equal (list 6) (tpool:get-result work8))
    (is equal (list 6) (tpool:get-result work9))
    (is eq :finished (tpool:get-status work0))
    (is eq :finished (tpool:get-status work1))
    (is eq :finished (tpool:get-status work2))
    (is eq :finished (tpool:get-status work3))
    (is eq nil (tpool:peek-backlog pool))
    (is eq nil (tpool:peek-backlog tpool:*default-thread-pool*))))

(define-test add-works-1 :parent pool
  (let* ((pool (tpool:make-thread-pool))
         (work-list (list (tpool:make-work-item :function #'(lambda () (+ 1 2 3)))
                          (tpool:make-work-item :function #'(lambda () (+ 1 2 3)))
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool))))
    (finish (tpool:add-works work-list pool))
    (sleep 0.0001)
    (is equal (make-list 10 :initial-element 6)
        (mapcar #'(lambda (work) (car (tpool:get-result work))) work-list))
    (is equal (make-list 10 :initial-element :finished)
        (mapcar #'(lambda (work) (tpool:get-status work)) work-list))))

(define-test add-works-2 :parent pool
  (let* ((pool (tpool:make-thread-pool))
         (work-list (list (tpool:make-work-item :function #'(lambda () (+ 1 2 3)))
                          (tpool:make-work-item :function #'(lambda () (+ 1 2 3)))
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool))))
    (finish (tpool:add-works work-list)) ; use the default pool
    (sleep 0.0001)
    (is equal (make-list 10 :initial-element 6)
        (mapcar #'(lambda (work) (car (tpool:get-result work))) work-list))
    (is equal (make-list 10 :initial-element :finished)
        (mapcar #'(lambda (work) (tpool:get-status work)) work-list))))

(define-test pool-main-1 :parent pool
  (let* ((pool (tpool:make-thread-pool))
         (work-list (list (tpool:make-work-item :function #'(lambda () (+ 1 2 3)))
                          (tpool:make-work-item :function #'(lambda () (+ 1 2 3)))
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool))))
    (with-slots ((backlog tpool::backlog)) pool
      (dolist (work work-list)
        (tpool-utils:enqueue work backlog)))
    (is = 10 (tpool-utils:queue-count (tpool::thread-pool-backlog pool))) ; no threads

    (finish (tpool:add-thread pool)) ; add a thread
    ;; run, but will only deal with the works whose status is :ready
    (sleep 0.0001)
    (is equal (make-list 10)
        (mapcar #'(lambda (work) (tpool:get-result work)) work-list))
    (is equal (make-list 10 :initial-element :created)
        (mapcar #'(lambda (work) (tpool:get-status work)) work-list))
    (false (tpool:peek-backlog pool))
    (dolist (work work-list) ; reset the status to ":ready" and add work
      (tpool:set-status work :ready)
      (tpool:add-work work pool))
    (sleep 0.0001) ; all done
    (is equal (make-list 10 :initial-element 6)
        (mapcar #'(lambda (work) (car (tpool:get-result work))) work-list))
    (is equal (make-list 10 :initial-element :finished)
        (mapcar #'(lambda (work) (tpool:get-status work)) work-list))

    (dolist (work work-list) ; reset work-list
      (tpool:set-status work :ready)
      (setf (tpool::work-item-result work) nil))

    (with-slots ((backlog tpool::backlog)) pool ; add to backlog without notify
      (dolist (work work-list)
        (tpool-utils:enqueue work backlog)))
    (is = 10 (tpool-utils:queue-count (tpool::thread-pool-backlog pool))) ; as the thread waiting for cvar

    (bt:condition-notify (tpool::thread-pool-cvar tpool:*default-thread-pool*)) ; 可能是老bug的源头
    (bt:condition-notify (tpool::thread-pool-cvar pool)) ; notify cvar
    (sleep 0.001) ; all done
    (dolist (work work-list)
      (is = 6 (car (tpool:get-result work)))
      (is eq :finished (tpool:get-status work)))
    (is equal (make-list 10 :initial-element 6)
        (mapcar #'(lambda (work) (car (tpool:get-result work))) work-list))
    (is equal (make-list 10 :initial-element :finished)
        (mapcar #'(lambda (work) (tpool:get-status work)) work-list))
    (false (tpool:peek-backlog pool))
    ))

(define-test pool-main-2 :parent pool
  (let* ((pool (tpool:make-thread-pool))
         (work (tpool:make-work-item :function #'(lambda () (values 1 2 3)))))
    (tpool:add-work work pool :xxxx)
    (sleep 0.0001)
    (is equal (list 1 2 3) (tpool:get-result work))))

(define-test cancel-work :parent pool
  (let* ((pool (tpool:make-thread-pool))
         (work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                     :pool pool))
         (work-list (list (tpool:make-work-item :function #'(lambda () (+ 1 2 3))
                                                :pool pool)
                          (tpool:make-work-item :function #'(lambda () (+ 1 2 3))
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool))))
    ;; fill thread with long tasks
    (dotimes (i (tpool::thread-pool-max-worker-num pool))
      (finish (tpool:add-task #'(lambda ()
                                  (sleep 5)
                                  (format t "sleeping tasks finished~%"))
                              pool)))
    (format t "All work thread will sleep 5 seconds.~%")

    (finish (tpool:add-work work pool))
    (finish (tpool:add-works work-list pool))
    (finish (tpool:cancel-work work))

    (dotimes (i 5)
      (sleep 1)
      (format t "~&......~%"))

    (is eql nil (tpool:get-result work))
    (is eql :cancelled (tpool:get-status work))
    (dolist (work work-list)
      (is eql 6 (car (tpool:get-result work)))
      (is eql :finished (tpool:get-status work)))))


(define-test flush-pool :parent pool
  (let* ((pool (tpool:make-thread-pool))
         (work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                     :pool pool))
         (work-list (list (tpool:make-work-item :function #'(lambda () (+ 1 2 3))
                                                :pool pool)
                          (tpool:make-work-item :function #'(lambda () (+ 1 2 3))
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                :pool pool))))
    ;; fill thread with long tasks, and during this period of time, none tasks can be executed.
    (dotimes (i (tpool::thread-pool-max-worker-num pool))
      (finish (tpool:add-task #'(lambda ()
                                  (sleep 5)
                                  (format t "sleeping tasks finished~%"))
                              pool)))
    (finish (tpool:add-work work pool))
    (finish (tpool:add-works work-list pool))
    ;;(finish (tpool:flush-pool pool))
    (finish (format t "~d~%" (tpool:flush-pool pool)))
    (false (tpool:peek-backlog pool))
    (dotimes (i 5)
      (sleep 1)
      (format t "~&......~%"))

    (is eql nil (tpool:get-result work nil))
    (is eql :cancelled (tpool:get-status work))
    (dolist (work work-list)
      (is eql nil (tpool:get-result work nil))
      (is eql :cancelled (tpool:get-status work)))))

#|
(define-test shutdown/restart-pool :parent pool
  (let* ((pool (tpool:make-thread-pool))
         (work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                     :pool pool)))
    (is eq t (tpool:restart-pool pool))
    (finish (tpool:shutdown-pool pool))
    (fail (tpool:add-work work pool))
    (is eq t (tpool:restart-pool pool))
    (tpool:add-thread pool)
    (finish (tpool:shutdown-pool pool))
    (is eq t (tpool:restart-pool pool))
    (format t "pool after restart: ~d~%" pool)
    (finish (tpool:add-work work pool))
    (sleep 0.00001)
    (is equal (list 6) (tpool:get-result work))))
|#

(define-test add-thread :parent pool
  (let* ((pool (tpool:make-thread-pool)))
    (finish (dotimes (i 100)
              (tpool:add-thread pool)))
    (is = (tpool::thread-pool-max-worker-num pool)
        (+ (tpool::thread-pool-working-num pool) (tpool::thread-pool-idle-num pool)))))

(define-test get-result :parent pool
  ;; :created :ready :running :aborted :finished :cancelled :rejected
  (let* ((pool (tpool:make-thread-pool))
         (pool2 (tpool:make-thread-pool))
         (fun-long #'(lambda () (sleep 5) (+ 1 2 3))) ; be a long run task
         (fun-inst #'(lambda () (+ 1 2 3))) ; an instant task
         (work (tpool:make-work-item :function fun-long :pool pool :name "long work")) ; long run work
         (work2 (tpool:make-work-item :function fun-inst :pool pool2 :name "instant work2")) ; instant work
         (work3 (tpool:make-work-item :function (lambda () (error "xxx")) :pool pool :name "error work"))) ; error signals
    ;; :created
    (is-values (tpool:get-result work) (eql nil) (eql nil))
    (is-values (tpool:get-result work nil) (eql nil) (eql nil))
    ;; :aborted
    #+sbcl(setf (car (tpool::work-item-status work)) :aborted)
    #+ccl(setf (svref (tpool::work-item-status work) 0) :aborted)
    (is-values (tpool:get-result work) (eql nil) (eql nil))
    (is-values (tpool:get-result work nil) (eql nil) (eql nil))
    ;; cancelled
    #+sbcl(setf (car (tpool::work-item-status work)) :cancelled)
    #+ccl(setf (svref (tpool::work-item-status work) 0) :cancelled)
    (is-values (tpool:get-result work) (eql nil) (eql nil))
    (is-values (tpool:get-result work nil) (eql nil) (eql nil))
    ;; :rejected
    #+sbcl(setf (car (tpool::work-item-status work)) :rejected)
    #+ccl(setf (svref (tpool::work-item-status work) 0) :rejected)
    (is-values (tpool:get-result work) (eql nil) (eql nil))
    (is-values (tpool:get-result work nil) (eql nil) (eql nil))

    (tpool:add-work work pool)
    (format t "~&The work will last for 5 seconds~%")
    (sleep 0.00001) ; the next test would fail in ccl without this sleep
    (dotimes (i 5)
      (format t "~&......~%")
      (format t "work: ~d~%" work)
      (is eq :running (tpool:get-status work))
      (is-values (tpool:get-result work nil) (eql nil) (eql nil))
      (sleep 1.1))
    ;; finished
    (is eq :finished (tpool:get-status work))
    (is-values (tpool:get-result work nil) (equal (list 6)) (eql t))
    (is-values (tpool:get-result work t) (equal (list 6)) (eql t))
    (format t "~&This test should run instantly.~%")
    (is-values (tpool:get-result work t 1000) (equal (list 6)) (eql t))
    ;; ready
    (dotimes (i (tpool::thread-pool-max-worker-num pool2)) ; let the pool busy for 5 seconds
      (tpool:add-task fun-long pool2))
    (tpool:add-work work2 pool2)
    (is eq :ready (tpool:get-status work2))
    (is-values (tpool:get-result work2 nil) (eql nil) (eql nil))
    (is-values (tpool:get-result work2 nil nil) (eql nil) (eql nil))
    (is-values (tpool:get-result work2 nil 10) (eql nil) (eql nil))
    (format t "~&This test shoule wait for 1 second.~%")
    (is-values (tpool:get-result work2 t 1) (eql nil) (eql nil)) ; test timeout
    (format t "~&This test shoule wait for 4 second.~%")
    (dotimes (i 4)
      (sleep 1)
      (format t "......~%"))
    (is-values (tpool:get-result work2 t) (equal (list 6)) (eql t))
    ;; aborted
    (tpool:add-work work3 pool)
    (sleep 0.0001)
    (is eq :aborted (tpool:get-status work3))
    (is-values (tpool:get-result work3 nil) (eql nil) (eql nil))
    ))

(defparameter *some-bind* 3)

(define-test with-work-item :parent pool
  ;; Will be warned and it's OK.
  (let* ((tpool (tpool:make-thread-pool))
         (work1 (tpool:with-work-item (:pool tpool:*default-thread-pool*) ; bindings nil
                  (+ 1 2 3)))
         (work2 (tpool:with-work-item (:pool tpool:*default-thread-pool* ; bindings non-nil
                                       :bindings '((a 1) (b 2) (c 3)))
                  (+ a b c)))
         (work3 (tpool:with-work-item (:pool tpool
                                       :bindings (list (list '*some-bind* 3)))
                  (+ 3 *some-bind*))))
    (true (tpool:work-item-p work1))
    (true (tpool:work-item-p work2))
    (true (tpool:work-item-p work3))
    (is = 6 (funcall (slot-value work1 'tpool::fn)))
    (is = 6 (funcall (slot-value work2 'tpool::fn)))
    (is = 6 (funcall (slot-value work3 'tpool::fn)))
    (finish (tpool:add-work work1))
    (finish (tpool:add-work work2))
    (finish (tpool:add-work work3))
    (sleep 0.001)
    (format t "work1: ~d~%" work1)
    (format t "work2: ~d~%" work2)
    (format t "work3: ~d~%" work3)
    (format t "with-work-item default pool: ~d~%" tpool:*default-thread-pool*)
    (format t "with-work-item pool: ~d~%" tpool)
    (is = 6 (car (tpool:get-result work1)))
    (is = 6 (car (tpool:get-result work2)))
    (format t "with-work-item default pool: ~d~%" tpool:*default-thread-pool*)
    (format t "with-work-item pool: ~d~%" tpool)
    (is = 6 (car (tpool:get-result work3)))
    (format t "with-work-item default pool: ~d~%" tpool:*default-thread-pool*)
    (format t "with-work-item pool: ~d~%" tpool)))

(define-test get/set-status :parent pool
  (let ((work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)))
        (status :abcd))
    (is eq :created (tpool:get-status work))
    (finish (tpool:set-status work status))
    (is eq status (tpool:get-status work))))

(define-test set-result :parent pool
  (let ((work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)))
        (result "ABC"))
    (finish (tpool:set-result work result))
    (is eq :finished (tpool:get-status work))
    (is-values (tpool:get-result work) (equal (list result)) (eql t))))

(define-test add-work-error :parent pool
  ;; to test the works with error signeled
  (let* ((pool (tpool:make-thread-pool))
         (work0 (tpool:make-work-item :name "work0"
                                      :function #'(lambda ()
                                                    (let ((x (/ 1 (gen-n 0))))
                                                      (format t "This should not be printed, or there must be a bug!~%")
                                                      x))
                                      :pool pool)))
    (is eq :created (tpool:get-status work0))
    (format t "pool: ~d~%" pool)
    (finish (tpool:add-work work0))
    (sleep 0.0001)
    (format t "pool: ~d~%" pool)
    (format t "work: ~d~%" work0)
    (is-values (tpool:get-result work0) (eq nil) (eq nil))
    (is eq :aborted (tpool:get-status work0))))
