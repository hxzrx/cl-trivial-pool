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

(define-test queue-flush :parent utils
  (let ((queue (sb-concurrency:make-queue)))
    (true (sb-concurrency:queue-empty-p queue))
    (false (utils:queue-flush queue))

    (sb-concurrency:enqueue nil queue)
    (false (sb-concurrency:queue-empty-p queue))
    (utils:queue-flush queue)
    (true (sb-concurrency:queue-empty-p queue))

    (sb-concurrency:enqueue 1 queue)
    (false (sb-concurrency:queue-empty-p queue))
    (true (utils:queue-flush queue))
    (true (sb-concurrency:queue-empty-p queue))

    (sb-concurrency:enqueue 1 queue)
    (sb-concurrency:enqueue 2 queue)
    (sb-concurrency:enqueue 3 queue)
    (true (utils:queue-flush queue))
    (true (sb-concurrency:queue-empty-p queue))
    (false (utils:queue-flush queue))))


;;; ------- thread-pool -------

(define-test make-pool-and-inspect :parent tpool
  (finish (tpool:inspect-pool (tpool:make-thread-pool)))
  ;;(fail (tpool:inspect-pool (tpool:make-thread-pool :keepalive-time -1))) ; this definitely fails but will signal compile error
  (finish (tpool:inspect-pool (tpool:make-thread-pool :name "" :max-worker-num 10 :keepalive-time 0)))
  (finish (tpool:inspect-pool (tpool:make-thread-pool :name "test pool" :max-worker-num 10 :keepalive-time 1))))

(define-test peek-backlog :parent tpool
  (let ((pool (tpool:make-thread-pool)))
    (is eq nil (tpool::peek-backlog pool))
    (sb-concurrency:enqueue :work1 (tpool::thread-pool-backlog pool))
    (is eq :work1 (tpool:peek-backlog pool))
    (sb-concurrency:enqueue :work2 (tpool::thread-pool-backlog pool))
    (is eq :work1 (tpool:peek-backlog pool))
    (sb-concurrency:dequeue (tpool::thread-pool-backlog pool))
    (is eq :work2 (tpool:peek-backlog pool))
    (sb-concurrency:dequeue (tpool::thread-pool-backlog pool))
    (is eq nil (tpool:peek-backlog pool))))

(define-test make-work-item :parent tpool
  (let ((pool (tpool:make-thread-pool)))
    (finish (tpool:inspect-work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                        :thread-pool pool)))
    (finish (tpool:inspect-work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3))))
    (finish (tpool:inspect-work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                        :thread-pool pool
                                                        :name "name")))
    (finish (tpool:inspect-work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                        :thread-pool pool
                                                        :desc "desc")))
    (finish (tpool:inspect-work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                        :thread-pool pool
                                                        :name "name"
                                                        :desc "desc")))))

(define-test add-work :parent tpool
  (let* ((pool (tpool:make-thread-pool))
         (work0 (tpool:make-work-item :function #'(lambda () (+ 1 2 3)))) ; to test in default pool
         (work1 (tpool:make-work-item :function #'(lambda () (+ 1 2 3)))) ; to test in local pool, will be warned
         (work2 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3) ; all test in local pool
                                       :thread-pool pool))
         (work3 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                       :thread-pool pool))
         (work4 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                       :thread-pool pool))
         (work5 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                       :thread-pool pool))
         (work6 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                       :thread-pool pool))
         (work7 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                       :thread-pool pool))
         (work8 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                       :thread-pool pool))
         (work9 (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                       :thread-pool pool)))
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
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool))))
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
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool))))
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
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool))))
    (with-slots ((backlog tpool::backlog)) pool
      (dolist (work work-list)
        (sb-concurrency:enqueue work backlog)))
    (is = 10 (sb-concurrency:queue-count (tpool::thread-pool-backlog pool))) ; no threads

    (finish (tpool:add-thread pool)) ; add a thread

    ;; run, but will only deal with the works whose status is :ready
    (sleep 0.0001)
    (is equal (make-list 10)
        (mapcar #'(lambda (work) (tpool:get-result work)) work-list))
    (is equal (make-list 10 :initial-element :created)
        (mapcar #'(lambda (work) (tpool:get-status work)) work-list))
    (false (tpool:peek-backlog pool))

    (dolist (work work-list) ; reset the status to ":ready" and add work
      (setf (tpool::work-item-status work) :ready)
      (tpool:add-work work pool))

    (sleep 0.0001) ; all done
    (is equal (make-list 10 :initial-element 6)
        (mapcar #'(lambda (work) (car (tpool:get-result work))) work-list))
    (is equal (make-list 10 :initial-element :finished)
        (mapcar #'(lambda (work) (tpool:get-status work)) work-list))

    (dolist (work work-list) ; reset work-list
      (setf (tpool::work-item-status work) :ready)
      (setf (tpool::work-item-result work) nil))

    (with-slots ((backlog tpool::backlog)) pool ; add to backlog without notify
      (dolist (work work-list)
        (sb-concurrency:enqueue work backlog)))
    (is = 10 (sb-concurrency:queue-count (tpool::thread-pool-backlog pool))) ; as the thread waiting for cvar

    (bt2:condition-notify (tpool::thread-pool-cvar pool)) ; notify cvar
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
                                      :thread-pool pool))
         (work-list (list (tpool:make-work-item :function #'(lambda () (+ 1 2 3))
                                                 :thread-pool pool)
                          (tpool:make-work-item :function #'(lambda () (+ 1 2 3))
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool))))
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
                                      :thread-pool pool))
         (work-list (list (tpool:make-work-item :function #'(lambda () (+ 1 2 3))
                                                 :thread-pool pool)
                          (tpool:make-work-item :function #'(lambda () (+ 1 2 3))
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool)
                          (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                                 :thread-pool pool))))
    ;; fill thread with long tasks
    (dotimes (i (tpool::thread-pool-max-worker-num pool))
      (finish (tpool:add-task #'(lambda ()
                              (sleep 5)
                              (format t "sleeping tasks finished~%"))
                          pool)))
    (format t "All work thread will sleep 5 seconds.~%")

    (finish (tpool:add-work work pool))
    (finish (tpool:add-works work-list pool))
    (finish (tpool:flush-pool pool))
    (false (tpool:peek-backlog pool))

    (dotimes (i 5)
      (sleep 1)
      (format t "~&......~%"))

    (is eql nil (tpool:get-result work))
    (is eql :cancelled (tpool:get-status work))
    (dolist (work work-list)
      (is eql nil (tpool:get-result work))
      (is eql :cancelled (tpool:get-status work)))))

(define-test shutdown/restart-pool :parent tpool
  (let* ((pool (tpool:make-thread-pool))
         (work (tpool:make-work-item :function (make-parameterless-fun + 1 2 3)
                                     :thread-pool pool)))
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
