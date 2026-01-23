---
rfc: 0011
title: async effects
status: draft
created: 2026-01-23
target: β
depends: [0010]
---

# RFC-0011: async effects

## summary

async in ferrule is an effect, not a type. functions declare `effects [Async]` to indicate they may suspend, and the runtime handles scheduling. this unifies async with the effect system and enables effect-based concurrency control.

## motivation

most languages treat async as a type-level distinction:

```typescript
// typescript: Promise<T> vs T
async function fetch(): Promise<Response> { ... }
```

```rust
// rust: impl Future<Output=T> vs T
async fn fetch() -> Response { ... }
```

this leads to function coloring: async functions can only be called from async contexts, creating a split in the codebase.

ferrule's approach: async is an effect, not a type:

```ferrule
function fetch() -> Response
  effects [Async, Net]
{
  // may suspend
}
```

benefits:
- unified with the effect system
- effect polymorphism works across sync/async
- no special async/await syntax
- runtime is pluggable

## detailed design

### async as an effect

the `Async` effect marks functions that may suspend:

```ferrule
function sleep(duration: Duration)
  effects [Async, Clock]
{
  intrinsic_suspend_for(duration);
}

function fetch_data(url: string) -> Response
  effects [Async, Net]
{
  const conn = net.connect(url)?;
  const data = conn.read_all();  // suspends until data ready
  return Response.parse(data);
}
```

### no async/await keywords

functions with `Async` effect are called normally:

```ferrule
function process() effects [Async, Net] {
  const data = fetch_data("https://example.com");  // may suspend
  return transform(data);
}
```

no `await` keyword needed. the compiler and runtime handle suspension transparently.

### effect subsumption

pure functions can be called from async contexts (normal effect subsumption):

```ferrule
function pure_compute(x: i32) -> i32 {
  return x * 2;
}

function async_work() effects [Async] {
  const result = pure_compute(21);  // pure function called from async
  return result;
}
```

### runtime interface

the async runtime is provided through a capability:

```ferrule
function main() with [Io, Async] {
  // Async capability provides the runtime
  const result = async_work();
  io.println(result);
}
```

different runtimes can be plugged in:

```ferrule
// single-threaded event loop
import runtime/single_threaded as async_runtime;

// multi-threaded work stealing
import runtime/multi_threaded as async_runtime;

// deterministic testing runtime
import runtime/testing as async_runtime;
```

### suspension points

only specific operations can suspend. these are marked in the stdlib:

```ferrule
// in stdlib
function sleep(duration: Duration) effects [Async, Clock] {
  intrinsic_suspend();  // only stdlib can call this
}

function read(fd: FileDescriptor, buf: View<mut u8>) -> usize
  effects [Async, Fs]
{
  intrinsic_io_wait(fd, IoEvent.Read);
  intrinsic_read(fd, buf)
}
```

user code suspends by calling these functions, not directly.

### cancellation

async operations can be cancelled through scope cancellation:

```ferrule
function with_timeout<T>(
  duration: Duration,
  f: function() effects [Async] -> T
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

when cancelled, pending operations throw a `Cancelled` error.

### blocking operations

some operations fundamentally block (cpu-bound work, legacy ffi). these are marked:

```ferrule
function compress(data: View<u8>) -> View<u8>
  effects [Blocking]  // not Async, but Blocking
{
  // cpu-bound work
}
```

`Blocking` and `Async` compose:

```ferrule
function async_compress(data: View<u8>) -> View<u8>
  effects [Async, Blocking]
{
  return task.run_blocking(|| compress(data));
}
```

### select and race

selecting from multiple async operations:

```ferrule
function first_response(urls: Array<string, N>) -> Response
  effects [Async, Net]
{
  return task.race(urls.map(|url| || fetch(url)));
}

function select_example() effects [Async, Net, Clock] {
  match task.select {
    data = fetch("url") => process(data),
    _ = clock.sleep(seconds(5)) => timeout_error(),
  }
}
```

### generators and async iterators

generators naturally compose with async:

```ferrule
generator function lines(fd: FileDescriptor) -> string
  effects [Async, Fs]
{
  var buf = [0u8; 4096];
  while true {
    const n = read(fd, buf);
    if n == 0 { break; }
    for line in split_lines(buf[..n]) {
      yield line;
    }
  }
}

function process_file(path: string) effects [Async, Fs] {
  const fd = open(path)?;
  for line in lines(fd) {
    process(line);
  }
}
```

## drawbacks

- implicit suspension makes it harder to reason about where context switches happen
- no `await` means less visual indication of async boundaries
- runtime abstraction has overhead
- different from most mainstream languages

## alternatives

### explicit await

require await keyword at suspension points:

```ferrule
const data = await fetch(url);
```

rejected to keep consistency with effect system (you don't "await" Io effects).

### async/sync function split

separate syntax for async functions:

```ferrule
async function fetch() -> Response { ... }
```

rejected because it creates function coloring.

### colorless async (like zig)

all functions can suspend, no special syntax:

benefits: maximum flexibility
drawbacks: harder to reason about, any function could suspend

this proposal is a middle ground: explicit via effects but no syntax coloring.

## prior art

| language | approach |
|----------|----------|
| koka | async as effect |
| eff | algebraic effects including async |
| ocaml 5 | effects for concurrency |
| go | goroutines, implicit concurrency |
| zig | async without coloring |

koka and eff are closest to this proposal.

## unresolved questions

1. how do we handle async in comptime?
2. what's the default runtime (single or multi-threaded)?
3. how do we debug async code effectively?
4. should there be a way to "run synchronously" for testing?

## future possibilities

- effect handlers for custom async interpretations
- async drop for cleanup
- pinned tasks for ffi callbacks
- io_uring / epoll backend selection
- wasm async support
