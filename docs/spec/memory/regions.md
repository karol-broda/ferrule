---
title: regions
status: α2
implemented: []
pending: []
deferred:
  - heap-region
  - arena-region
  - device-region
  - shared-region
  - region-disposal
  - uninitialized-memory
---

# regions

> this feature is planned for α2. the spec describes what it will be, not what's implemented now.

regions group allocations under a single lifetime. disposing a region frees everything inside it deterministically. there's no garbage collector.

## why regions

traditional memory management has two extremes:
- manual (c): free each allocation individually, easy to mess up
- gc (go, java): automatic but unpredictable, can't control when memory is freed

regions are a middle ground:
- allocate into a region
- when done, dispose the whole region
- everything inside is freed at once

this is particularly good for request-scoped data. allocate all the request's memory in one region, dispose when the request finishes.

## region kinds

| constructor | description |
|-------------|-------------|
| `region.heap()` | general-purpose dynamic region |
| `region.arena(bytes)` | bump-ptr arena, no individual frees |
| `region.device(id)` | device memory (dma, gpu) |
| `region.shared()` | multi-thread access, requires atomics |

each call to `region.heap()` creates a new independent region. there's no global singleton heap.

## creation and disposal

```ferrule
const arena = region.arena(1 << 20);  // 1mb
defer arena.dispose();

const buf: View<mut u8> = arena.alloc<u8>(4096);
// use buf...
// arena disposed when scope exits
```

disposal:
- frees all allocations in the region
- runs destructors for capsule values registered with the region
- returns Unit, never fails
- errors during finalization are logged but don't propagate

disposing a region invalidates all views bound to it. further access traps.

## arenas

arenas are bump allocators. allocation is fast (just increment a pointer), but you can't free individual allocations:

```ferrule
const arena = region.arena(1024 * 1024);  // 1mb
defer arena.dispose();

const a = arena.alloc<u8>(100);   // fast
const b = arena.alloc<u8>(200);   // fast
// can't free a or b individually
// dispose frees everything at once
```

arenas are great for:
- parsing (allocate ast nodes, dispose when done)
- request handling (allocate everything, dispose when request finishes)
- game frames (allocate per-frame data, reset each frame)

## heap regions

heap regions allow individual frees but are slower:

```ferrule
const heap = region.heap();
defer heap.dispose();

const ptr = heap.alloc<u8>(100);
// can use heap.free(ptr) for individual frees
// or let dispose clean everything
```

## transfer between regions

moving data between regions is explicit:

```ferrule
const dst = region.heap();
const moved: View<mut u8> = view.move(buf, to = dst);
```

moving invalidates the source view. using it after transfer is a compile error.

| operation | source after | requirement |
|-----------|--------------|-------------|
| `view.copy(src, to)` | remains valid | element type is copyable |
| `view.move(src, to)` | invalidated | element type has valid move policy |

## shared regions

memory in `region.shared()` may be accessed from multiple threads. mutation requires:
- `atomics` effect
- atomic types or synchronization primitives

```ferrule
const shared = region.shared();
// use with atomic operations only
```

non-atomic concurrent mutation is undefined behavior.

## alloc effect

invoking allocators requires the `alloc` effect:

```ferrule
function grow_buffer(r: Region, want: usize) -> View<mut u8> effects [alloc] {
  return r.alloc_zeroed<u8>(want);
}
```

this makes allocation visible in function signatures.

## uninitialized memory

ferrule forbids reading uninitialized memory. allocation apis define zero-init policy:

| api | behavior |
|-----|----------|
| `alloc_zeroed<T>(...)` | returns zeroed memory |
| `alloc_uninit<T>(...)` | returns `View<Uninit<T>>` |

uninitialized views must be fully initialized before use:

```ferrule
const un: View<Uninit<u32>> = region.heap().alloc_uninit<u32>(4);
// initialize all elements...
const init: View<u32> = view.assume_init(un);  // only legal when fully initialized
```

this prevents undefined behavior from reading garbage.

## device regions

`region.device(id)` exposes device memory:

```ferrule
const gpu = region.device(gpu_id);
const gpu_buf = gpu.alloc<f32>(1024);

// host access may be illegal without mapping
device.copy_to_host(gpu_buf, host_buf);
host.copy_to_device(host_buf, gpu_buf);
```

transfers can fail and return errors.

## regions and scoped ownership

regions work with scoped ownership:
- views can't escape their creation scope
- regions created inside a scope are disposed when the scope exits
- if you pass a region out, you own disposal

```ferrule
function process() -> View<u8> {
    const arena = region.arena(1024);
    defer arena.dispose();
    
    const buf = arena.alloc<u8>(100);
    return buf;  // error: buf escapes its region
}
```

to return data, copy it:

```ferrule
function process(out_region: Region) -> View<u8> effects [alloc] {
    const arena = region.arena(1024);
    defer arena.dispose();
    
    const buf = arena.alloc<u8>(100);
    // ... process buf ...
    return view.copy(buf, to = out_region);  // ok: copy to caller's region
}
```

## example: request-scoped allocation

```ferrule
function handleRequest(req: Request, cap io: Io) -> Response 
    error RequestError 
    effects [alloc, io] 
{
    const arena = region.arena(1 << 20);  // 1mb for this request
    defer arena.dispose();
    
    const body = check parseBody(req, arena);
    const result = check process(body, arena);
    const response = check serialize(result, arena);
    
    // copy response to caller's region before returning
    return response.clone();
}
// arena disposed here, all request memory freed
```
