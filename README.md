A common lisp thread pool implemented with atomic operations instead of locks in the worker threads' main loop. This pool supports sbcl and ccl currently. This is the successor of cl-mzpool <https://github.com/hxzrx/cl-mzpool>.

### thread-pool
Struct, the definition of the thread pool.

#### Slots
name: the name of the thread pool, string type. It will be set to a random unique name if it's not provided.

initial-bindings:  the environment of this pool which is an alist such as `(list (var1 val1) (va2 val2))`. This parameter, combined with the bindings of a function, will make a closure of that function and encapsulated to a `work-item` and then sent to a thread pool. The default value of this parameter is NIL.

lock: the lock used to wait for the condition variable's notification of a new work-item's arrival.

cvar: the condition variable to wait for the notification of a new work-item's arrival.

backlog: the pending queue of the work-item.

max-worker-num: the maximum of the count of the worker threads, integer type. It's default value is `*default-worker-num*`.

thread-table: a hash table to keep up with the pool's threads.

working-num: the number of threads which are busy working currently.

idle-num: the number of threads which are idle currently.

shutdown-p: the flag that the pool's status is shutdown or not.

keepalive-time: the max idle time (in seconds) of the worker thread, the thread will return if it's idle time exceeds this limit, integer type, default to `*default-keepalive-time*`.

### work-item
Class, the definition of the work whose instances can be sent to the thread pool.

#### Slots
name: the name of this work-item, string type.

fun: the function that we want to run in a thread pool, note that it's not the vanilla function we sent but a closure bound with the bindings of the thread-pool (as well as the function's own bindings if provided).

pool: the thread pool this work-item should be sent to, default to `*default-thread-pool*` if not provided.

result: the list of the result of the function. Note that the real result of `fun` will be converted to a list by `multiple-value-list` so that `fun` can return multiple values.

status: the status of this work-item, should be one of `(:created :ready :running :aborted :finished :cancelled :rejected)`.

lock:  the  lock used to wait for the condition variable's notification of the result of the function.

cvar: the condition variable to wait for the notification of the result of the function.

desc: description of this work-item, string type.

### make-thread-pool
Constructor of `thread-pool`, return an instance of `thread-pool`.

Parameters: (&key name max-worker-num keepalive-time initial-bindings)

### make-work-item
function, return an instance of `work-item`.

parameters: (&key function pool status name desc)

### inspect-pool
function , return a detail description string of the thread pool.

parameters: (pool &optional (inspect-work-p nil))

inspect-work-p: if it's true, the long string of the work-items in backlog will be returned, default to nil.

### inspect-work
function, return a detail description of the work item.

parameters: (work &optional (simple-mode t))

simple-mode: if it's NIL, the name of the thread pool it bound to will be showed, default to T.

### peek-backlog

function, return the top pending work-item of the pool, and return NIL if no pending work-items.

parameters: pool

### add-thread
function, add a thread to a thread pool.

parameters: pool

Note that this function will be seldom called since `add-work` and `add-task` will choose to create a thread.

### add-task
function, add a work-item to the thread-pool. Functions are called concurrently and in FIFO order. A work item is returned, which can be passed to `cancel-work` to attempt cancel the work.

parameters: (function pool &key (name "") priority bindings desc)

function: a function object which has null parameter.

pool: a thread-pool instance.

priority: currently not implemented.

bindings: a list which specify special bindings  that should be active when function is called. These override the thread pool's initial-bindings if overlapped.

### add-tasks
function, add many work items to the pool.   A work item is created for each element of VALUES and FUNCTION is called in the pool with that element. Returns a list of the work items added.

parameters: (function values pool &key name priority bindings)

### add-work

method, enqueue a work-item to a thread-pool's backlog. The biggest different between `add-task` and `add-work` is that `add-work` has no bindings specified. Return the work-item itself.

parameters: ((work work-item) &optional (pool *default-thread-pool*) priority)

### add-works

method, enqueue a list of works to a thread-pool, and return the list of works enqueued.

parameters: ((work-list list) &optional (pool *default-thread-pool*) priority)

### get-result
function, get the result of this `work`, returns two values:  The second value denotes if the work has finished. The first value is the function's returned value list of this work, or nil if the work has not finished.

parameters: ((work work-item) &optional (waitp t) (timeout nil))

waitp: if waitp is true, the function will wait for the running result of the work-item and the current thread will suspend until the work-item's function's return or timeout, its default value is T.

timeout: timed in seconds.

### get-status
function: return the status of an work-item instance. The returned status should be one of `(:created :ready :running :aborted :finished :cancelled :rejected)`.

parameters: ((work work-item))

### cancel-work
function, cancel a work item, removing it from its thread-pool. Returns true if the item was successfully cancelled, false if the item had finished or is currently running on a worker thread. The work-item's status will be set to :cancelled if it's revoked by this function.

parameters: work-item

### flush-pool
function, cancel all works in `backlog` slot of a thread-pool. Returns a list of all cancelled items. Does not cancel work in progress.

parameters: pool

### shutdown-pool
function: shutdown a thread pool. Cancels all pending work on the thread pool. Once a thread pool has been shut down, no further work can be added unless it's been restarted by thread-pool-restart.

parameters: pool &key abort

abort: if abort is true then worker threads will be terminated via bt:destroy-thread.

### restart-pool
function, calling shutdown-pool will not destroy the pool object, but set the slot shutdown-p t. This function set the slot shutdown-p nil so that the pool will be used then. Return t if the pool has been shutdown, and return nil if the pool was active.

parameters: pool

### terminate-work
symbol, used in the body of a work-item's function to make a non-local transfer via `(throw 'terminate-work ...).
