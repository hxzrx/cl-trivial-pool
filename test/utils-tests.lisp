(in-package :cl-trivial-pool-tests)


(define-test peek-queue :parent utils
  (let ((queue (tpool-utils:make-queue)))
    (is eq nil (tpool-utils:peek-queue queue))
    (is eq nil (tpool-utils:peek-queue queue))

    (tpool-utils:enqueue nil queue)
    (is eq nil (tpool-utils:peek-queue queue))

    (tpool-utils:dequeue queue)
    (is eq nil (tpool-utils:peek-queue queue))

    (tpool-utils:enqueue t queue)
    (is eq t (tpool-utils:peek-queue queue))

    (tpool-utils:dequeue queue)
    (is eq nil (tpool-utils:peek-queue queue))

    (tpool-utils:enqueue 1 queue)
    (is = 1 (tpool-utils:peek-queue queue))
    (tpool-utils:enqueue 2 queue)
    (is = 1 (tpool-utils:peek-queue queue))))

(define-test flush-queue :parent utils
  (let ((queue (tpool-utils:make-queue)))
    (true (tpool-utils:queue-empty-p queue))
    (finish (tpool-utils:flush-queue queue))
    (true (tpool-utils:queue-empty-p queue))

    (tpool-utils:enqueue nil queue)
    (false (tpool-utils:queue-empty-p queue))
    (finish (tpool-utils:flush-queue queue))
    (true (tpool-utils:queue-empty-p queue))

    (tpool-utils:enqueue 1 queue)
    (false (tpool-utils:queue-empty-p queue))
    (finish (tpool-utils:flush-queue queue))
    (true (tpool-utils:queue-empty-p queue))

    (tpool-utils:enqueue 1 queue)
    (tpool-utils:enqueue 2 queue)
    (tpool-utils:enqueue 3 queue)
    (finish (tpool-utils:flush-queue queue))
    (true (tpool-utils:queue-empty-p queue))
    (finish (tpool-utils:flush-queue queue))))

(define-test make-nullary :parent utils
  (is = 6 (funcall (tpool-utils:make-nullary ()
                     (+ 1 2 3)))))

(define-test make-unary :parent utils
  (let ((x 10))
    (is = (* x x) (funcall (tpool-utils:make-unary (a)
                             (* a a))
                           x))))

(define-test make-binary :parent utils
  (is = 3 (funcall (tpool-utils:make-binary (a b) (+ a b)) 1 2)))

(define-test make-n-ary :parent utils
  (is = 6 (funcall (tpool-utils:make-n-ary (a b c) (+ a b c)) 1 2 3)))

(define-test wrap-bindings :parent utils
  (is = 3 (funcall (tpool-utils:wrap-bindings #'(lambda () (+ a b)) '((a 1) (b 2)))))
  (is = 6 (funcall (tpool-utils:wrap-bindings #'(lambda (x) (+ a b x)) '((a 1) (b 2)) 3)))
  (is = 4 (funcall (tpool-utils:wrap-bindings #'(lambda (x) (+ 1 x)) nil 3)))
  (is = 3 (funcall (tpool-utils:wrap-bindings #'(lambda (x y) (+ x y)) nil 1 2)))
  (is = 6 (funcall (tpool-utils:wrap-bindings #'(lambda () (+ 1 2 3)) nil)))
  (is = 6 (funcall (tpool-utils:wrap-bindings #'(lambda () (+ 1 2 3))))))

(defstruct struct-otf
  (xx 12345))

(define-test atomic-peek :parent utils
  (let ((atom1 (tpool-utils:make-atomic 12345))
        (atom2 (make-struct-otf)))
    (is = 12345 (tpool-utils:atomic-peek (tpool-utils:atomic-place atom1)))
    (is = 12345 (tpool-utils:atomic-peek (struct-otf-xx atom2)))
    (tpool-utils:atomic-set (tpool-utils:atomic-place atom1) 54321)
    (tpool-utils:atomic-set (struct-otf-xx atom2) 54321)
    (is = 54321 (tpool-utils:atomic-peek (tpool-utils:atomic-place atom1)))
    (is = 54321 (tpool-utils:atomic-peek (struct-otf-xx atom2)))))
