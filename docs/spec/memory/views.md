# Views

> **scope:** view formation, slicing, mutability, aliasing, bounds, pinning  
> **related:** [regions.md](regions.md) | [../core/types.md](../core/types.md)

---

## Overview

Views are **fat pointers** that carry:
- base pointer (with provenance)
- element count (len)
- region ID

```ferrule
View<T>        // immutable view
View<mut T>    // mutable view
```

---

## View Formation

Forming a view records:
- base pointer provenance
- element count (len)
- region ID

```ferrule
const heap = region.heap();
const buf: View<mut u8> = heap.alloc<u8>(4096);
```

---

## Slicing

Slicing yields a new view with the **same region ID** and a sub-range:

```ferrule
const head: View<u8> = view.slice(buf, start = 0, count = 128);
const tail: View<u8> = view.slice(buf, start = 128, count = buf.len - 128);
```

Bounds are validated at slice time.

---

## Mutability

### Immutable Views

`View<T>` provides **read-only** access. Multiple aliases are allowed:

```ferrule
const a: View<u8> = buf;
const b: View<u8> = buf;  // both can read
```

### Mutable Views

`View<mut T>` enables mutation. **Exclusive write rule:** a mutable view must not be used concurrently with any other view that overlaps the same range.

α1 enforces:
- **static checks** for obvious overlaps within a scope
- **debug assertions** (optional) for dynamic overlaps

> Data race violations are **undefined behavior** in release builds.

---

## Aliasing Rules

| Scenario | Allowed? |
|----------|----------|
| multiple `View<T>` to same data | ✓ yes |
| one `View<mut T>`, no other views | ✓ yes |
| `View<mut T>` + any overlapping view | ✗ no (UB) |

For shared regions, see [regions.md#shared-regions](regions.md#shared-regions).

---

## Bounds Checking

- bounds checks on `View` access are inserted unless the compiler proves safety
- checks in loops are **fused** for performance
- proven bounds **erase** checks

---

## Pinning

Some operations (FFI, DMA) require stable addresses:

```ferrule
const pin = view.pin(buf);
defer view.unpin(pin);

// call C function that writes into the pinned buffer
crypto_c.hash_update(pin);
```

Rules:
- pinning prevents region compaction or movement for the view's range
- must be **unpinned** explicitly or by disposal
- pinning in `region.arena` is always allowed

---

## Layout & Alignment

Each type has machine layout: `size`, `align`, and (for unions) niche data.

- alignment/packing attributes can be specified at type definition time
- misaligned raw loads/stores are rejected or lowered to safe sequences

```ferrule
const align: usize = layout.alignof<Blob>();
const size: usize = layout.sizeof<Blob>();
```

---

## Provenance

Pointer provenance is preserved across view operations. Casts that would break provenance are rejected unless done through `ffi` gates.

---

## Worked Example: FFI Pinning

```ferrule
function hash_in_place(buf: View<mut u8>) -> Unit effects [ffi] {
  const pin = view.pin(buf);
  defer view.unpin(pin);
  
  const ok = crypto_c.hash_update(pin);
  if ok === false { 
    // handle error 
  }
}
```

---

## Summary

| Type | Access | Aliasing |
|------|--------|----------|
| `View<T>` | read-only | multiple allowed |
| `View<mut T>` | read-write | exclusive |


