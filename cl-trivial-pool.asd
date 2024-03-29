(defsystem "cl-trivial-pool"
  :version "0.5.1"
  :description "A common lisp thread pool implemented with atomic operations instead of locks in the worker threads' infinite loop."
  :author "He Xiang-zhi <xz.he@qq.com>"
  :license "MIT"
  :depends-on (#+sbcl :sb-concurrency
               :cl-cpus
               :bordeaux-threads
               :alexandria
               :cl-fast-queues
               :log4cl)
  :serial t
  :in-order-to ((test-op (test-op "cl-trivial-pool/tests")))
  :components ((:file "packages")
               (:file "utils")
               (:file "thread-pool")
               (:file "promise")))


(defsystem "cl-trivial-pool/tests"
  :version "0.5.1"
  :author "He Xiang-zhi <xz.he@qq.com>"
  :license "MIT"
  :serial t
  :depends-on (:cl-trivial-pool
               :parachute)
  :components ((:module "test"
                :serial t
                :components ((:file "packages")
                             (:file "utils-tests")
                             (:file "thread-pool-tests")
                             (:file "promise-tests"))))
  :perform (test-op (o s) (uiop:symbol-call :parachute :test :cl-trivial-pool-tests)))
