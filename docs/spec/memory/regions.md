# Regions

> **scope:** region kinds, creation, disposal, transfer, allocators  
> **related:** [views.md](views.md) | [capsules.md](capsules.md) | [../functions/effects.md](../functions/effects.md)

---

## Overview

- **regions** group allocations under a single lifetime
- disposing a region frees everything inside it **deterministically**
- there is **no garbage collector** — all lifetimes are either lexical (via `defer`) or explicit (via capsule finalizers)
- each call to `region.heap()` creates a **new independent region** — there is no global singleton heap

---

## Region Kinds (α1)

| Constructor | Description |
|-------------|-------------|
| `region.heap()` | general-purpose dynamic region |
| `region.arena(bytes)` | bump-ptr arena; individual frees are disallowed |
| `region.device(id)` | memory associated with a device (DMA, GPU) |
| `region.shared()` | multiple threads may access; requires `atomics` for mutation |

> Regions are values; they can be passed, stored, and disposed.

```ferrule
const arena = region.arena(1 << 20);
const buf: View<mut u8> = arena.alloc<u8>(4096);
defer arena.dispose();
```

---

## Creation

### Heap Region

```ferrule
const heap = region.heap();
defer heap.dispose();
```

### Arena Region

```ferrule
const arena = region.arena(1024 * 1024);  // 1MB
defer arena.dispose();
```

### Current Region

`region.current()` returns the region implicitly associated with the current lexical scope created by tooling (`task.scope`, test harnesses, etc.).

α1 **does not** auto-nest regions; you explicitly pass regions to APIs that allocate.

---

## Disposal

`region.dispose()`:
- logically frees all allocations in the region
- runs deterministic **destructors** for capsule values registered with the region
- returns `Unit` — **never fails**
- errors during finalization are logged but don't propagate

```ferrule
const r = region.arena(1024);
defer r.dispose();
// all allocations freed when scope exits
```

Disposing a region **invalidates** all views bound to it; further access traps.

> Finalizer errors are logged to the debugging/observability subsystem but do not affect control flow.

---

## Transfer (Reparenting)

Move between regions is explicit and **deep** for trivially movable types:

```ferrule
const dst = region.heap();
const moved: View<mut u8> = view.move(buf, to = dst);
```

### Rules

1. Moving **invalidates** the source view; using it after transfer is a compile-time error (or runtime trap in dynamic paths)
2. Types with **external attachments** (file handles, device memory, host pointers) must define a `move_into(to: Region)` policy; if absent, moves are rejected
3. Moving into `region.device` requires a device-visible layout; otherwise rejected or performed via a layout adapter

### Copy vs Move

| Operation | Source After | Requirement |
|-----------|--------------|-------------|
| `view.copy(src, to)` | remains valid | element type is copyable |
| `view.move(src, to)` | invalidated | element type has valid move policy |

---

## Shared Regions

Memory in `region.shared()` may be accessed from multiple tasks/threads. Mutation requires:
- `atomics` effect
- atomic types or synchronization primitives from stdlib

> Non-atomic concurrent mutation of overlapping ranges is **undefined behavior**.

---

## Allocators & `alloc` Effect

Standard allocators operate **within a region**; invoking them requires the `alloc` effect:

```ferrule
function grow_buffer(r: Region, want: usize) -> View<mut u8> effects [alloc] {
  return r.alloc_zeroed<u8>(want);
}
```

Custom allocators can be passed as capabilities to further constrain policies (e.g., arenas that forbid free).

---

## Uninitialized Memory

α1 **forbids reading from uninitialized memory**.

Allocation APIs define zero-init policy explicitly:

| API | Behavior |
|-----|----------|
| `alloc_zeroed<T>(...)` | returns zeroed memory |
| `alloc_uninit<T>(...)` | returns `View<Uninit<T>>` |

Uninitialized views must be **fully initialized** before transmuting:

```ferrule
const un: View<Uninit<u32>> = region.heap().alloc_uninit<u32>(4);
// initialize all elements...
const init: View<u32> = view.assume_init(un);  // only legal when fully initialized
```

---

## Device Regions & DMA

`region.device(id)` exposes device memory:

- host access may be illegal — attempting read/write without device mapping yields compile-time error or runtime trap
- transfers require explicit copy functions:

```ferrule
device.copy_to_host(device_view, host_view);
host.copy_to_device(host_view, device_view);
```

These can return `err` values for transfer failures.

---

## Task Scopes & Region Lifetimes

- regions created **inside** a task scope are disposed when the scope exits
- passing a region **out** of its creating scope is allowed, but then **you** own disposal
- compilers warn if a region is never disposed

See [../concurrency/tasks.md](../concurrency/tasks.md).

---

## Worked Example

```ferrule
// copy to caller's region
function clone_to_region(src: View<u8>, dst_region: Region) -> View<u8> effects [alloc] {
  return view.copy(src, to = dst_region);
}

// return region along with view (caller owns disposal)
function clone_with_region(src: View<u8>) -> { data: View<u8>, region: Region } effects [alloc] {
  const heap = region.heap();
  const dst  = view.copy(src, to = heap);
  return { data: dst, region: heap };
}
```


