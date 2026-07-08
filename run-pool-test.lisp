(ql:quickload :cl-trivial-pool)
(ql:quickload :cl-trivial-pool/tests)
(in-package :cl-trivial-pool-tests)
(loop (test 'pool))
