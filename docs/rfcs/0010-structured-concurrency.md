---
rfc: 0010
title: structured concurrency
status: draft
created: 2026-01-23
target: β
---

# RFC-0010: structured concurrency

## summary

structured concurrency ensures that concurrent tasks have well-defined lifetimes that follow lexical scopes. tasks cannot outlive their parent scope, preventing resource leaks and making concurrent code easier to reason about.

## motivation

unstructured concurrency leads to problems:

```ferrule
// unstructured: tasks can outlive the function
function process() {
  spawn do_work();  // when does this finish?
  spawn do_more();  // what if this fails?
  return;           // tasks are orphaned
}
```

issues with unstructured concurrency:
- tasks can outlive the function that spawned them
- no guarantee all tasks complete before returning
- errors can be lost
- cancellation is manual and error-prone
- resource cleanup order is undefined

structured concurrency solves these:

```ferrule
function process() {
  task.scope |scope| {
    scope.spawn(do_work);
    scope.spawn(do_more);
  };  // waits for all tasks, propagates errors
}
```

## detailed design

### task scopes

the `task.scope` construct creates a scope for concurrent tasks:

```ferrule
function parallel_sum(data: View<i32>) -> i32
  effects [Async]
{
  const mid = data.len() / 2;
  const left = data[..mid];
  const right = data[mid..];

  var left_sum: i32 = 0;
  var right_sum: i32 = 0;

  task.scope |scope| {
    scope.spawn || {
      left_sum = sum(left);
    };
    scope.spawn || {
      right_sum = sum(right);
    };
  };

  return left_sum + right_sum;
}
```

### scope semantics

1. **all tasks complete before scope exits**: the scope blocks until all spawned tasks finish
2. **errors propagate**: if any task fails, the scope returns the first error
3. **cancellation cascades**: if the scope is cancelled, all tasks are cancelled
4. **no escaping**: task handles cannot leave the scope

```ferrule
task.scope |scope| {
  const handle = scope.spawn(compute);
  // handle is only valid inside this scope
};
// handle is not accessible here
```

### spawning tasks

tasks are spawned with closures:

```ferrule
scope.spawn || {
  // task body
};

// with captured values (including capabilities)
const x = 42;
scope.spawn || {
  io.println(x);  // captures x and io
};
```

### awaiting results

tasks return values through `join`:

```ferrule
task.scope |scope| {
  const task1 = scope.spawn || -> i32 { return expensive_compute(); };
  const task2 = scope.spawn || -> i32 { return another_compute(); };

  const result1 = task1.join();
  const result2 = task2.join();

  return result1 + result2;
};
```

### cancellation

scopes support cancellation:

```ferrule
function with_timeout<T>(
  duration: Duration,
  f: function() -> T
) -> Result<T, Timeout>
  effects [Async, Clock]
{
  return task.scope |scope| {
    const work = scope.spawn(f);
    const timer = scope.spawn || {
      clock.sleep(duration);
      scope.cancel();
    };

    return work.join();
  };
}
```

### nested scopes

scopes can nest, with child scopes respecting parent cancellation:

```ferrule
task.scope |outer| {
  outer.spawn || {
    task.scope |inner| {
      // if outer is cancelled, inner is too
      inner.spawn(work);
    };
  };
};
```

### nursery pattern

for dynamic task spawning, use a nursery:

```ferrule
function process_all(items: View<Item>) effects [Async] {
  task.nursery |nursery| {
    for item in items {
      nursery.spawn || {
        process(item);
      };
    }
  };
}
```

the difference from scope: nursery allows spawning while running.

### effect interaction

structured concurrency requires the `Async` effect:

```ferrule
function parallel_work() effects [Async] {
  task.scope |scope| { ... };
}

// cannot use task.scope without Async effect
function sync_work() {  // no Async effect
  task.scope |scope| { ... };  // error: Async effect required
}
```

### error handling

errors in tasks propagate to the scope:

```ferrule
function fallible_parallel() -> Result<i32, MyError>
  effects [Async]
  errors [MyError]
{
  return task.scope |scope| {
    scope.spawn || -> Result<i32, MyError> {
      return may_fail()?;
    };
  };
}
```

if multiple tasks fail, the first error is returned and other tasks are cancelled.

## drawbacks

- overhead of task management
- learning curve for developers used to unstructured concurrency
- some patterns (background workers, daemons) don't fit structured model

## alternatives

### go-style goroutines

fire and forget:

```ferrule
go do_work();  // runs in background, no scope
```

rejected because it leads to the problems structured concurrency solves.

### rust-style explicit scoping

use lifetime parameters:

```ferrule
fn scoped<'a>(scope: &'a Scope) { ... }
```

rejected because we don't have lifetime syntax.

### actor model

message-passing actors with mailboxes:

```ferrule
const actor = spawn_actor(MyActor);
actor.send(Message);
```

could coexist with structured concurrency but is a different abstraction.

## prior art

| language/library | approach |
|------------------|----------|
| trio (python) | nurseries, cancel scopes |
| kotlin | coroutine scopes |
| swift | task groups |
| java (jep 428) | structured concurrency api |
| structured concurrency (paper) | original formalization |

trio's design is the primary inspiration for this proposal.

## unresolved questions

1. how do we handle blocking operations in tasks?
2. what's the task scheduling strategy (work stealing, etc.)?
3. should we support priorities for tasks?
4. how do capabilities flow into spawned tasks?

## future possibilities

- async iterators with structured spawning
- select/race operations
- channels for task communication
- task-local storage
- custom schedulers
