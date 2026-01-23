---
title: views
status: α1
implemented: []
pending:
  - view-type-syntax
  - basic-slicing
deferred:
  - bounds-checking (α2)
  - escape-analysis (α2)
  - pinning (α2)
  - provenance-tracking (α2)
---

# views

views are fat pointers. they reference a range of elements without owning them. a view carries a pointer, a length, and a region id.

```ferrule
View<T>        // immutable view
View<mut T>    // mutable view
```

views are the primary way to pass data around without copying. but they have a key constraint: they can't escape the scope where they were created.

## formation

views are created from arrays or region allocations:

```ferrule
const arr: Array<u8, 100> = [...];
const view: View<u8> = arr[0..50];  // view of first 50 elements
```

```ferrule
const heap = region.heap();
defer heap.dispose();

const buf: View<mut u8> = heap.alloc<u8>(4096);
```

the view records:
- base pointer (with provenance)
- element count
- region id

## slicing

slicing creates a new view with the same region id and a sub-range:

```ferrule
const head: View<u8> = view.slice(buf, start = 0, count = 128);
const tail: View<u8> = view.slice(buf, start = 128, count = buf.len - 128);
```

bounds are checked at slice time.

## scoped views

this is the key rule: **views cannot escape their creation scope**.

```ferrule
function process() -> Unit {
    const data: Array<u8, 1024> = [...];
    const view: View<u8> = data[0..100];
    
    workWith(view);  // ok: passing view down
    
    // return view;  // error: view can't escape function
}
```

this is enforced at compile time. if you try to return a view, or store it in a struct that outlives the scope, you get an error.

```ferrule
function bad() -> View<u8> {
    const arena = region.arena(1024);
    defer arena.dispose();
    
    const buf = arena.alloc<u8>(100);
    return buf;  // error: buf escapes its region
}
```

this is what makes ferrule memory-safe without a borrow checker. views are tied to their source. they can go down the call stack but not up or sideways.

## if you need data to escape, copy it

```ferrule
function returnsData(input: View<u8>) -> Array<u8, 100> {
    var result: Array<u8, 100> = [0; 100];
    mem.copy(result[..], input[0..100]);
    return result;  // ok: result is owned, not a view
}
```

the copy is explicit. you see it in the code. this is a tradeoff: you copy more than you would with a borrow checker, but the rules are simpler.

## mutability

`View<T>` is read-only. multiple aliases are allowed:

```ferrule
const a: View<u8> = buf;
const b: View<u8> = buf;  // both can read
```

`View<mut T>` enables mutation. the exclusive write rule: a mutable view must not be used concurrently with any other view that overlaps the same range.

```ferrule
const a: View<mut u8> = buf[0..50];
const b: View<mut u8> = buf[50..100];  // ok: non-overlapping

const c: View<mut u8> = buf[0..50];
const d: View<u8> = buf[0..50];  // error: overlaps with mutable view
```

data race violations are undefined behavior in release builds. in debug builds, there may be assertions.

## aliasing rules

| scenario | allowed? |
|----------|----------|
| multiple `View<T>` to same data | yes |
| one `View<mut T>`, no other views | yes |
| `View<mut T>` + any overlapping view | no (ub) |

## bounds checking

bounds checks on view access are inserted unless the compiler can prove safety:
- checks in loops are fused for performance
- proven bounds erase checks
- out of bounds is a trap in debug, ub in release

## what's planned

**escape analysis** (α2) will catch more cases at compile time:

```ferrule
function alsoBad() -> Unit {
    var ptr: View<u8> = undefined;
    {
        const arena = region.arena(1024);
        defer arena.dispose();
        ptr = arena.alloc<u8>(100);
    }  // arena disposed here
    
    ptr[0] = 42;  // error: ptr references disposed region
}
```

**pinning** (α2) for ffi and dma:

```ferrule
const pin = view.pin(buf);
defer view.unpin(pin);

// call c function that writes into the pinned buffer
cryptoC.hashUpdate(pin);
```

pinning prevents region compaction for the view's range.

## summary

| type | access | aliasing |
|------|--------|----------|
| `View<T>` | read-only | multiple allowed |
| `View<mut T>` | read-write | exclusive |

views are how you pass data efficiently. the scoped constraint is what makes them safe.
