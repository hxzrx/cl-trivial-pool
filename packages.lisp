(defpackage #:tpool-utils
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
           #:queue-empty-p
           #:flush-queue
           #:make-atomic
           #:atomic-place
           #:atomic-incf
           #:atomic-decf
           #:atomic-update
           #:make-nullary
           #:make-unary
           #:wrap-bindings
           #:with-error-handling
           #:*debug-on-error*
           #:*promise*
           #:exit-on-error
           ))

(defpackage #:cl-trivial-pool
  (:use #:cl #:tpool-utils)
  (:nicknames #:tpool)
  (:export #:*default-keepalive-time*
           #:*default-worker-num*
           #:*default-thread-pool*
           #:thread-pool
           #:thread-pool-name
           #:thread-pool-initial-bindings
           #:thread-pool-max-worker-num
           #:thread-pool-idle-num
           #:thread-pool-backlog
           #:thread-pool-shutdown-p
           #:thread-pool-keepalive-time
           #:work-item
           #:work-item-pool
           #:work-item-fn
           #:work-item-result
           #:work-item-name
           #:work-item-desc
           #:make-thread-pool
           #:make-work-item
           #:with-work-item
           #:inspect-pool
           #:inspect-work
           #:work-item-p
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

(defpackage #:promise
  (:use #:cl #:tpool-utils #:cl-trivial-pool)
  (:export #:signal-promise-error
           #:signal-promise-warning
           #:signal-promise-condition
           #:promise
           #:promisep
           #:resolve
           #:reject
           #:make-promise
           #:with-promise
           ))
