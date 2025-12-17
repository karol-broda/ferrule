# Standard Library (α1 Surface)

> **scope:** standard library APIs available in α1  
> **related:** [../functions/effects.md](../functions/effects.md) | [../memory/regions.md](../memory/regions.md)

---

## Overview

The standard library provides essential functionality. All APIs return `ok`/`err` using the module's default error domain unless otherwise declared.

---

## Result & Error Handling

### Sugar

| Function | Purpose |
|----------|---------|
| `ok value` | wrap success |
| `err Variant { ... }` | construct error |
| `check expr` | unwrap or propagate |
| `ensure cond else err ...` | guard clause |
| `map_error expr using ...` | adapt error domain |

See [../errors/propagation.md](../errors/propagation.md).

---

## Regions & Views

### Region Constructors

```ferrule
region.heap()           // general-purpose region
region.arena(bytes)     // bump allocator arena
region.device(id)       // device memory region
region.shared()         // thread-safe region
region.current()        // current scope's region
```

### Region Operations

```ferrule
region.dispose()        // free all allocations
region.alloc<T>(count)  // allocate array
region.alloc_zeroed<T>(count)
region.alloc_uninit<T>(count)
```

### View Operations

```ferrule
view.slice(v, start, count)   // sub-view
view.copy(v, to = region)     // copy to region
view.move(v, to = region)     // move to region
view.pin(v)                   // pin for FFI
view.unpin(pin)               // unpin
view.assume_init(uninit)      // convert initialized view
view.from_raw(ptr, len)       // create from raw pointer
```

See [../memory/regions.md](../memory/regions.md) and [../memory/views.md](../memory/views.md).

---

## Tasks & Concurrency

### Task Scope

```ferrule
task.scope(scope => { ... })
scope.spawn(async_op)
scope.await_all()
scope.await_one(task)
scope.on_settle(task, callback)
scope.fail(error)
scope.collect_failure(error)
```

### Cancellation

```ferrule
cancel.token(deadline)
token.is_cancelled()
```

See [../concurrency/tasks.md](../concurrency/tasks.md).

---

## Time

Requires `time` effect and `Clock` capability.

```ferrule
clock.now()                    // current time
clock.sleep(duration)          // suspend
Duration.seconds(n)
Duration.ms(n)
Duration.us(n)
Duration.ns(n)
time.until(deadline)           // duration until deadline
```

---

## Randomness

Requires `rng` effect and `Rng` capability.

```ferrule
rng.u32()                      // random u32
rng.u64()                      // random u64
rng.range(min, max)            // random in range
rng.bytes(view)                // fill view with random bytes
rng.shuffle(view)              // shuffle elements
```

---

## File System

Requires `fs` effect and `Fs` capability.

```ferrule
fs.open(path)                  // open file
fs.create(path)                // create file
fs.read_all(file)              // read entire file
fs.read_all_text(path)         // read as string
fs.write_all(path, data)       // write data
fs.exists(path)                // check existence
fs.stat(path)                  // file metadata
fs.remove(path)                // delete file
fs.mkdir(path)                 // create directory
fs.read_dir(path)              // list directory
```

---

## Network

Requires `net` effect and `Net` capability.

```ferrule
net.connect(host, port, token) // TCP connect
net.listen(addr)               // TCP listen
net.accept(listener)           // accept connection
sock.read(buf)                 // read from socket
sock.write(data)               // write to socket
sock.close()                   // close socket
```

---

## Layout

```ferrule
layout.sizeof<T>()             // size in bytes
layout.alignof<T>()            // alignment
layout.page_size()             // system page size
layout.cache_line_size()       // cache line size
```

---

## SIMD

Requires `simd` effect.

```ferrule
simd.add(a, b)                 // element-wise add
simd.sub(a, b)                 // element-wise subtract
simd.mul(a, b)                 // element-wise multiply
simd.div(a, b)                 // element-wise divide
simd.mul_scalar(v, s)          // scalar multiply
simd.reduce_add(v)             // sum elements
simd.reduce_min(v)             // minimum element
simd.reduce_max(v)             // maximum element
simd.load<T, n>(view, offset)  // load vector
simd.store(view, offset, vec)  // store vector
simd.gt(a, b)                  // greater-than mask
simd.lt(a, b)                  // less-than mask
simd.select(mask, a, b)        // conditional select
```

---

## Text

```ferrule
text.trim(s)                   // trim whitespace
text.split(s, delim)           // split string
text.join(parts, sep)          // join strings
text.contains(s, substr)       // check substring
text.starts_with(s, prefix)
text.ends_with(s, suffix)
text.to_upper(s)
text.to_lower(s)
```

---

## Numbers

```ferrule
number.parse_i32(s)            // parse integer
number.parse_u32(s)
number.parse_i64(s)
number.parse_u64(s)
number.parse_f32(s)
number.parse_f64(s)
number.to_string(n)            // format number
```

---

## Math

```ferrule
math.abs(x)
math.min(a, b)
math.max(a, b)
math.clamp(x, min, max)
math.sqrt(x)
math.pow(base, exp)
math.sin(x)
math.cos(x)
math.tan(x)
math.floor(x)
math.ceil(x)
math.round(x)
math.PI
math.E
```

---

## Memory

```ferrule
mem.copy(dst, src)             // copy bytes
mem.set(dst, value)            // fill with value
mem.secure_zero(view)          // secure zeroing (not optimized away)
mem.compare(a, b)              // compare bytes
```

---

## Builder

```ferrule
builder.new<T>(region)         // create builder
builder.push(b, value)         // append value
builder.finish(b)              // finalize to view
builder.len(b)                 // current length
builder.capacity(b)            // current capacity
```

---

## Testing

```ferrule
testing.mock_clock(start)      // deterministic clock
testing.mock_rng(seed)         // deterministic RNG
testing.deterministic_scheduler(seed)
testing.explore_interleavings(max_runs, fn)
assert(condition)
assert_eq(a, b)
assert_ne(a, b)
```

See [../concurrency/determinism.md](../concurrency/determinism.md).


