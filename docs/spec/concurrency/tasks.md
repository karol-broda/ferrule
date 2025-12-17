# Tasks & Structured Concurrency

> **scope:** task scopes, spawning, awaiting, cancellation, failure aggregation  
> **related:** [determinism.md](determinism.md) | [../functions/effects.md](../functions/effects.md) | [../memory/regions.md](../memory/regions.md)

---

## Overview

Ferrule uses **structured concurrency** — tasks form trees where:
- child tasks cannot outlive their parent scope
- cancellation propagates down the tree
- failures are explicitly aggregated

---

## Task Scopes

Create a task scope with `task.scope`:

```ferrule
function get_many(urls: View<Url>, deadline: Time) -> View<Response> error ClientError effects [net, time, alloc] {
  return task.scope(scope => {
    const out = builder.new<Response>(region.current());

    for url in urls {
      const child = scope.spawn(fetch(url, deadline));
      scope.on_settle(child, (r) => {
        match r {
          ok v  -> builder.push(out, v);
          err e -> scope.fail(e);
        }
      });
    }

    check scope.await_all();
    return ok builder.finish(out);
  });
}
```

`task.scope` takes a lambda returning `Result<T, E>` and:
- if the lambda returns `ok v`, the scope evaluates to `v`
- if it returns `err e`, the error propagates to the calling function

---

## Spawning Tasks

```ferrule
const child = scope.spawn(async_operation());
```

`spawn` schedules a task within the scope. The task:
- inherits the scope's cancellation token
- must complete before the scope exits

---

## Awaiting

### Await All

```ferrule
check scope.await_all();
```

Waits for all spawned tasks to complete. Returns error if any task failed (depending on failure policy).

### Await One

```ferrule
const result = scope.await_one(child);
```

Waits for a specific task to complete.

---

## Settlement Callbacks

```ferrule
scope.on_settle(child, (result) => {
  match result {
    ok v  -> handle_success(v);
    err e -> handle_error(e);
  }
});
```

Callbacks run when a task completes, regardless of success or failure.

---

## Cancellation

### Cancellation Tokens

```ferrule
const tok = cancel.token(deadline);
```

Create a token that cancels after a deadline.

### Propagation

When a scope is cancelled:
1. All child tasks receive the cancellation signal
2. Ongoing operations check the token and return early
3. Cleanup runs via `defer`

### Handling Cancellation

```ferrule
function fetch(url: Url, tok: CancelToken) -> Response error ClientError effects [net] {
  const sock = check net.connect(url.host, url.port, tok);
  // tok is checked during the operation
  return check request(sock, url, tok);
}
```

When `check` propagates during cancellation, it attaches `{ cancelled: true }` to the error frame.

---

## Failure Policies

Scopes can use different failure policies:

```ferrule
// fail-fast: cancel siblings on first failure
scope.fail(e);

// collect-all: gather all failures
scope.collect_failure(e);
const all_errors = scope.failures();
```

---

## Region Lifetimes in Tasks

- regions created **inside** a task scope are disposed when the scope exits
- passing a region **out** is allowed, but then you own disposal
- aborted tasks must release their regions — finalizers run, status events are logged

```ferrule
task.scope(scope => {
  const arena = region.arena(1024);
  defer arena.dispose();  // always runs, even on cancellation
  
  // use arena...
  return ok result;
});
```

---

## Context Flow

Context ledgers flow through task boundaries:

```ferrule
with context { request_id: rid } in {
  task.scope(scope => {
    scope.spawn(child_operation());  // inherits request_id context
    // ...
  });
}
```

Errors from child tasks include the inherited context frames.

---

## Example: Parallel Fetch with Timeout

```ferrule
function fetch_all(
  urls: View<Url>, 
  cap net: Net, 
  cap clock: Clock
) -> View<Response> error FetchError effects [net, time, alloc] {
  
  const deadline = clock.now() + Duration.seconds(30);
  
  return task.scope(scope => {
    const results = builder.new<Response>(region.current());
    
    for url in urls {
      scope.spawn(async {
        const resp = check fetch(url, deadline, net);
        builder.push(results, resp);
      });
    }
    
    check scope.await_all();
    return ok builder.finish(results);
  });
}
```


