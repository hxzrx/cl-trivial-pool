(defpackage #:cl-trivial-pool-tests
  (:use #:cl #:parachute)
  (:export #:test
           #:pool))


(in-package :cl-trivial-pool-tests)

;;; utils

(defmacro make-parameterless-fun (fun &rest args)
  "(funcall (make-parameterless-fun + 1 3))"
  `(lambda ()
     (funcall #',fun ,@args)))

(defun make-random-list (n &optional (max 100))
  (loop for i below n collect (random max)))


;;; define test cases

(define-test cl-trivial-pool-tests)
(define-test tpool :parent cl-trivial-pool-tests)
(define-test utils :parent tpool)
(define-test pool :parent tpool)

#+sbcl
(define-test peek-queue :parent utils
  (let ((queue (sb-concurrency:make-queue)))
    (is eq nil (utils:peek-queue queue))
    (is eq nil (utils:peek-queue queue))

    (sb-concurrency:enqueue nil queue)
    (is eq nil (utils:peek-queue queue))

    (sb-concurrency:dequeue queue)
    (is eq nil (utils:peek-queue queue))

    (sb-concurrency:enqueue t queue)
    (is eq t (utils:peek-queue queue))

    (sb-concurrency:dequeue queue)
    (is eq nil (utils:peek-queue queue))

    (sb-concurrency:enqueue 1 queue)
    (is = 1 (utils:peek-queue queue))
    (sb-concurrency:enqueue 2 queue)
    (is = 1 (utils:peek-queue queue))))

#+sbcl
(define-test flush-queue :parent utils
  (let ((queue (sb-concurrency:make-queue)))
    (true (sb-concurrency:queue-empty-p queue))
    (false (utils:flush-queue queue))

    (sb-concurrency:enqueue nil queue)
    (false (sb-concurrency:queue-empty-p queue))
    (utils:flush-queue queue)
    (true (sb-concurrency:queue-empty-p queue))

    (sb-concurrency:enqueue 1 queue)
    (false (sb-concurrency:queue-empty-p queue))
    (true (utils:flush-queue queue))
    (true (sb-concurrency:queue-empty-p queue))

    (sb-concurrency:enqueue 1 queue)
    (sb-concurrency:enqueue 2 queue)
    (sb-concurrency:enqueue 3 queue)
    (true (utils:flush-queue queue))
    (true (sb-concurrency:queue-empty-p queue))
    (false (utils:flush-queue queue))))


;;; ------- thread-pool -------

(define-test make-pool-and-inspect :parent tpool
  (finish (tpool:inspect-pool (tpool:make-thread-pool)))
  ;;(fail (tpool:inspect-pool (tpool:make-thread-pool :keepalive-time -1))) ; this definitely fails but will signal compile error
  (finish (tpool:inspect-pool (tpool:make-thread-pool :name "" :max-worker-num 10 :keepalive-time 0)))
  (finish (tpool:inspect-pool (tpool:make-thread-pool :name "test pool" :max-worker-num 10 :keepalive-time 1))))

(define-test peek-backlog :parent tpool
  (let ((pool (tpool:make-thread-pool)))
    (is eq nil (tpool::peek-backlog pool))
    #+sbcl(sb-concurrency:enqueue :work1 (tpool::thread-pool-backlog pool))
    #-sbcl(cl-fast-queues:enqueue :work1 (tpool::thread-pool-backlog pool))
    (is eq :work1 (tpool:peek-backlog pool))
    #+sbcl(sb-concurrency:enqueue :work2 (tpool::thread-pool-backlog pool))
    #-sbcl(cl-fast-queues:enqueue :work2 (tpool::thread-pool-backlog pool))
    (is eq :work1 (tpool:peek-backlog pool))
    #+sbcl(sb-concurrency:dequeue (tpool::thread-pool-backlog pool))
    #-sbcl(utils:sfifo-dequeue (tpool::thread-pool-backlog pool))
    (is eq :work2 (tpool:peek-backlog pool))
    #+sbcl(sb-concurrency:dequeue (tpool::thread-pool-backlog pool))
    #-sbcl(utils:sfifo-dequeue (tpool::thread-pool-backlog pool))
    (is eq nil (tpool:peek-backlog pool))))

(define-test make-work-item :parent tpool
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

(define-test add-work :parent tpool
  (let* ((pool (tpool:make-thread-pool))
         (work0 (tpool:make-work-item :function #'(lambda () (+ 1 2 3)))) ; to test in default pool
         (work1 (tpool:make-work-item :function #'(lambda () (+ 1 2 3)))) ; to test in local pool, will be warned
         (work2 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3) ; all test in local pool
                                      :pool pool))
         (work3 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                      :pool pool))
         (work4 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                      :pool pool))
         (work5 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                      :pool pool))
         (work6 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                      :pool pool))
         (work7 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                      :pool pool))
         (work8 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                      :pool pool))
         (work9 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
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

(define-test add-works-1 :parent tpool
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

(define-test add-works-2 :parent tpool
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

(define-test pool-main-1 :parent tpool
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
        #+sbcl(sb-concurrency:enqueue work backlog)
        #-sbcl(cl-fast-queues:enqueue work backlog)))
    #+sbcl(is = 10 (sb-concurrency:queue-count (tpool::thread-pool-backlog pool))) ; no threads
    #-sbcl(is = 10 (cl-fast-queues:queue-count (tpool::thread-pool-backlog pool)))

    (finish (tpool:add-thread pool)) ; add a thread
    ;; run, but will only deal with the works whose status is :ready
    (sleep 0.0001)
    (is equal (make-list 10)
        (mapcar #'(lambda (work) (tpool:get-result work)) work-list))
    (is equal (make-list 10 :initial-element :created)
        (mapcar #'(lambda (work) (tpool:get-status work)) work-list))
    (false (tpool:peek-backlog pool))

    (dolist (work work-list) ; reset the status to ":ready" and add work
      #+sbcl(setf (car (tpool::work-item-status work)) :ready)
      #-sbcl(setf (svref (tpool::work-item-status work) 0) :ready)
      (tpool:add-work work pool))

    (sleep 0.0001) ; all done
    (is equal (make-list 10 :initial-element 6)
        (mapcar #'(lambda (work) (car (tpool:get-result work))) work-list))
    (is equal (make-list 10 :initial-element :finished)
        (mapcar #'(lambda (work) (tpool:get-status work)) work-list))

    (dolist (work work-list) ; reset work-list
      #+sbcl(setf (car (tpool::work-item-status work)) :ready)
      #-sbcl(setf (svref (tpool::work-item-status work) 0) :ready)
      (setf (tpool::work-item-result work) nil))

    (with-slots ((backlog tpool::backlog)) pool ; add to backlog without notify
      (dolist (work work-list)
        #+sbcl(sb-concurrency:enqueue work backlog)
        #-sbcl(cl-fast-queues:enqueue work backlog)))
    #+:sbcl(is = 10 (sb-concurrency:queue-count (tpool::thread-pool-backlog pool))) ; as the thread waiting for cvar
    #-:sbcl(is = 10 (cl-fast-queues:queue-count (tpool::thread-pool-backlog pool)))

    (bt:condition-notify (tpool::thread-pool-cvar pool)) ; notify cvar
    (sleep 0.0001) ; all done
    (is equal (make-list 10 :initial-element 6)
        (mapcar #'(lambda (work) (car (tpool:get-result work))) work-list))
    (is equal (make-list 10 :initial-element :finished)
        (mapcar #'(lambda (work) (tpool:get-status work)) work-list))
    (false (tpool:peek-backlog pool))
    ))

(define-test pool-main-2 :parent tpool
  (let* ((pool (tpool:make-thread-pool))
         (work (tpool:make-work-item :function #'(lambda () (values 1 2 3)))))
    (tpool:add-work work pool :xxxx)
    (sleep 0.0001)
    (is equal (list 1 2 3) (tpool:get-result work))))

(define-test cancel-work :parent tpool
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


(define-test flush-pool :parent tpool
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

(define-test shutdown/restart-pool :parent tpool
  (let* ((pool (tpool:make-thread-pool))
         (work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                     :pool pool)))
    (is eq nil (tpool:restart-pool pool))
    (finish (tpool:shutdown-pool pool))
    (fail (tpool:add-work work pool))
    (is eq t (tpool:restart-pool pool))
    (tpool:add-thread pool)
    (finish (tpool:shutdown-pool pool))
    (is eq t (tpool:restart-pool pool))
    (finish (tpool:add-work work pool))
    (sleep 0.00001)
    (is equal (list 6) (tpool:get-result work))))

(define-test add-thread :parent tpool
  (let* ((pool (tpool:make-thread-pool)))
    (finish (dotimes (i 100)
              (tpool:add-thread pool)))
    (is = (tpool::thread-pool-max-worker-num pool)
        (+ (tpool::thread-pool-working-num pool) (tpool::thread-pool-idle-num pool)))))

(define-test get-result :parent tpool
  ;; :created :ready :running :aborted :finished :cancelled :rejected
  (let* ((pool (tpool:make-thread-pool))
         (pool2 (tpool:make-thread-pool))
         (fun-long #'(lambda () (sleep 5) (+ 1 2 3))) ; be a long run task
         (fun-inst #'(lambda () (+ 1 2 3))) ; an instant task
         (work (tpool:make-work-item :function fun-long :pool pool :name "work")) ; long run work
         (work2 (tpool:make-work-item :function fun-inst :pool pool2 :name "work2"))) ; instant work
    ;; :created
    (is-values (tpool:get-result work) (eql nil) (eql nil))
    (is-values (tpool:get-result work nil) (eql nil) (eql nil))
    ;; :aborted
    (setf (car (tpool::work-item-status work)) :aborted)
    (is-values (tpool:get-result work) (eql nil) (eql nil))
    (is-values (tpool:get-result work nil) (eql nil) (eql nil))
    ;; cancelled
    (setf (car (tpool::work-item-status work)) :cancelled)
    (is-values (tpool:get-result work) (eql nil) (eql nil))
    (is-values (tpool:get-result work nil) (eql nil) (eql nil))
    ;; :rejected
    (setf (car (tpool::work-item-status work)) :rejected)
    (is-values (tpool:get-result work) (eql nil) (eql nil))
    (is-values (tpool:get-result work nil) (eql nil) (eql nil))

    (tpool:add-work work pool)
    (format t "~&The work will last for 5 seconds~%")
    (dotimes (i 5)
      (format t "~&......~%")
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
    (is-values (tpool:get-result work2 t 1) (eql nil) (eql nil))
    (is-values (tpool:get-result work2 t) (equal (list 6)) (eql t))))
