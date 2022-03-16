(defpackage #:cl-trivial-pool-tests
  (:use #:cl #:parachute)
  (:export #:test
           #:pool))

(in-package :cl-trivial-pool-tests)


;;; define top test cases

(define-test cl-trivial-pool-tests)
(define-test tpool :parent cl-trivial-pool-tests)
(define-test utils :parent tpool)
(define-test pool :parent tpool)
