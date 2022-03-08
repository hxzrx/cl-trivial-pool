(defsystem "cl-trivial-pool"
  :version "0.3.0"
  :description "A common lisp thread pool implemented with atomic operations instead of locks in the worker threads' infinite loop."
  :author "He Xiang-zhi<xz.he@qq.com>"
  :license "MIT"
  :depends-on (:cl-cpus
               :bordeaux-threads
               :alexandria
               :cl-fast-queues)
  :serial t
  :in-order-to ((test-op (test-op "cl-trivial-pool/tests")))
  :components ((:file "packages")
               (:file "utils")
               #+sbcl(:file "thread-pool-sbcl")
               #+ccl(:file "thread-pool-ccl")))


(defsystem "cl-trivial-pool/tests"
  :version "0.3.0"
  :author "He Xiang-zhi<xz.he@qq.com>"
  :license "MIT"
  :serial t
  :depends-on (:cl-trivial-pool
               :parachute)
  :components ((:file "tests"))
  :perform (test-op (o s) (uiop:symbol-call :parachute :test :cl-trivial-pool-tests)))
