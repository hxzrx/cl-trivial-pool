(defpackage #:utils
  (:use #:cl)
  (:export #:*default-worker-num*
           #:*default-keepalive-time*
           #:unwind-protect-unwind-only
           #:make-hash
           #:make-queue
           #:peek-queue
           #:enqueue
           #:dequeue
           #:queue-count
           #:queue-to-list
           #:flush-queue
           #:make-atomic
           #:atomic-place
           #:atomic-incf
           #:atomic-decf
           #:atomic-update
           )
  #+:sbcl(:export #:peek-queue
                  #:flush-queue)
  #+:ccl(:export #:atomic-update
                 #:sfifo-dequeue
                 ))

(defpackage #:cl-trivial-pool
  (:use #:cl #:utils)
  (:nicknames #:tpool)
  (:export #:*default-keepalive-time*
           #:*default-worker-num*
           #:*default-thread-pool*
           #:thread-pool
           #:work-item
           #:make-thread-pool
           #:make-work-item
           #:inspect-pool
           #:inspect-work
           #:peek-backlog
           #:add-thread
           #:add-task
           #:add-tasks
           #:add-work
           #:add-works
           #:get-result
           #:get-status
           #:cancel-work
           #:flush-pool
           #:shutdown-pool
           #:restart-pool
           #:terminate-work))
