---
title: tasks and structured concurrency
status: β
implemented: []
pending: []
deferred:
  - task-scope
  - spawn-and-await
  - cancellation
  - failure-policies
  - context-flow
---

# tasks and structured concurrency

> this feature is planned for β. the spec describes what it will be, not what's implemented now.

ferrule uses structured concurrency. tasks form trees where:
- child tasks can't outlive their parent scope
- cancellation propagates down the tree
- failures are explicitly aggregated

this eliminates "fire and forget" patterns that lead to resource leaks and hard-to-debug races.

## task scopes

create a task scope with `task.scope`:

```ferrule
function get_many(urls: View<Url>, deadline: Time, cap net: Net) -> View<Response> 
    error ClientError 
    effects [net, time, alloc] 
{
  return task.scope(scope => {
    const out = builder.new<Response>(region.current());

    for url in urls {
            const child = scope.spawn(fetch(url, deadline, net));
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

the scope:
- tracks all spawned tasks
- ensures they complete before the scope exits
- propagates cancellation on failure

## spawning

```ferrule
const child = scope.spawn(async_operation());
```

spawn schedules a task within the scope. the task:
- inherits the scope's cancellation token
- must complete before the scope exits

you can't spawn outside a scope. there's no global task pool.

## awaiting

await all tasks:

```ferrule
check scope.await_all();
```

or await a specific task:

```ferrule
const result = scope.await_one(child);
```

## cancellation

cancellation tokens propagate through the task tree:

```ferrule
const tok = cancel.token(deadline);

// when deadline passes, tok cancels
// all tasks using tok receive the cancellation
```

when a scope is cancelled:
1. all child tasks receive the cancellation signal
2. ongoing operations check the token and return early
3. cleanup runs via `defer`

handling cancellation in your code:

```ferrule
function fetch(url: Url, tok: CancelToken, cap net: Net) -> Response 
    error ClientError 
    effects [net] 
{
  const sock = check net.connect(url.host, url.port, tok);
  // tok is checked during the operation
  return check request(sock, url, tok);
}
```

## failure policies

scopes can use different failure policies:

```ferrule
// fail-fast: cancel siblings on first failure
scope.fail(e);

// collect-all: gather all failures
scope.collect_failure(e);
const all_errors = scope.failures();
```

fail-fast is the default. it's usually what you want: if one request fails, cancel the others and return the error.

## regions and tasks

regions created inside a task scope are disposed when the scope exits:

```ferrule
task.scope(scope => {
  const arena = region.arena(1024);
    defer arena.dispose();  // runs even on cancellation
  
  // use arena...
  return ok result;
});
```

aborted tasks must release their regions. finalizers run, status events are logged.

## context flow

context flows through task boundaries:

```ferrule
with context { request_id: rid } in {
  task.scope(scope => {
        scope.spawn(child_operation());  // inherits request_id
    // ...
  });
}
```

errors from child tasks include the inherited context frames. this helps with debugging distributed operations.

## async model

ferrule's async is effect-based. the `suspend` effect marks functions that may pause:

```ferrule
function fetch(url: String, cap net: Net) -> Response 
    error NetError 
    effects [net, suspend] 
{
    const socket = net.connect(url.host, url.port)?;
    return ok socket.readAll()?;  // may suspend here
}
```

there's no function coloring. you can call suspend functions from any context that allows the suspend effect. the runtime handles the actual suspension and resumption.

different runtimes can plug in:
- tokio-style for server workloads
- single-threaded for embedded
- deterministic for testing

see the async rfc for details.

## example: parallel fetch with timeout

```ferrule
function fetch_all(
  urls: View<Url>, 
  cap net: Net, 
  cap clock: Clock
) -> View<Response> error FetchError effects [net, time, alloc, suspend] {
  
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
