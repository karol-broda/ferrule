---
title: unsafe blocks
status: α1
implemented: []
pending:
  - unsafe-block-syntax
  - raw-pointers
  - extern-calls
  - transmute
deferred:
  - inline-assembly (rfc)
---

# unsafe blocks

most ferrule code is safe. the compiler checks memory safety, type safety, effect tracking, and capability flow. but sometimes you need to do things the compiler can't verify. that's what unsafe is for.

unsafe doesn't turn off all checks. it enables specific operations that can't be verified at compile time. you're taking responsibility for correctness.

## what unsafe enables

inside an unsafe block, you can:
- use raw pointers
- do pointer arithmetic
- call extern functions
- transmute between types
- access union fields without matching

## what unsafe does not turn off

these still apply inside unsafe:
- type checking (types must match)
- effect checking (effects must be declared)
- bounds checking on views (still happens)
- capability flow (still tracked)

unsafe is surgical. it enables specific operations, not a free-for-all.

## syntax

```ferrule
unsafe {
    // unsafe operations allowed here
}
```

the block is explicit. you can grep for `unsafe` to find all the places that need manual audit.

## raw pointers

outside unsafe, you can't use raw pointers:

```ferrule
const ptr: *u8 = ...;  // error: raw pointers not allowed
```

inside unsafe, you can:

```ferrule
unsafe {
    const ptr: *u8 = view.asPtr(buf);
    const value = ptr.*;  // dereference
}
```

raw pointer types:
- `*T` - pointer to T (nullable)
- `*mut T` - mutable pointer to T

## pointer arithmetic

```ferrule
unsafe {
    const ptr: *u8 = view.asPtr(buf);
    const offset = ptr + 10;  // pointer arithmetic
    const value = offset.*;
}
```

this is unchecked. you can go out of bounds. you're responsible for correctness.

## extern calls

calling c functions requires unsafe:

```ferrule
extern "C" function strlen(s: *u8) -> usize;

function getLength(s: String) -> usize {
    unsafe {
        return strlen(s.asPtr());
    }
}
```

the extern declaration is outside unsafe, but the call is inside. this is because the declaration is just a type signature, the call is where you're trusting the foreign code.

## transmute

reinterpreting bits as a different type:

```ferrule
unsafe {
    const bits: u32 = 0x3f800000;
    const f: f32 = transmute<u32, f32>(bits);  // 1.0
}
```

transmute doesn't convert, it reinterprets. the bit pattern stays the same, the type changes. this is very easy to get wrong.

## union field access

normally you access union variants through match:

```ferrule
match value {
    Foo { x } => ...,
    Bar { y } => ...,
}
```

in unsafe, you can access a field directly:

```ferrule
unsafe {
    const x = value.Foo.x;  // assumes it's Foo, no check
}
```

if it's actually Bar, you get garbage or undefined behavior.

## unsafe functions

a function can be marked unsafe:

```ferrule
unsafe function dangerousTransmute<T, U>(val: T) -> U {
    return transmute<T, U>(val);
}
```

calling an unsafe function requires an unsafe block:

```ferrule
const result = unsafe { dangerousTransmute<i32, f32>(42) };
```

this makes the call site explicit about taking responsibility.

## guidelines

**minimize unsafe surface area.** wrap unsafe operations in safe abstractions:

```ferrule
// unsafe internals
function View.asPtr<T>(v: View<T>) -> *T {
    unsafe {
        return v.base;
    }
}

// safe api
function View.get<T>(v: View<T>, idx: usize) -> T {
    if idx >= v.len {
        panic("index out of bounds");
    }
    unsafe {
        return (v.base + idx).*;
    }
}
```

the user calls `get`, which is safe. the bounds check happens before the pointer dereference. the unsafe block is small and auditable.

**document why it's safe.** unsafe code should have comments explaining why the invariants hold:

```ferrule
unsafe {
    // safe because: buf was allocated with at least 10 bytes
    // and we're reading byte 5
    const val = (buf + 5).*;
}
```

**ffi boundaries are always unsafe.** foreign code can do anything. even if the c function is "safe", you're trusting the implementation.

## what's planned

**inline assembly** (rfc) for low-level control:

```ferrule
function disableInterrupts() -> Unit {
    unsafe {
        asm {
            "cpsid i"
        }
    }
}
```

this is important for embedded and kernel work, but needs careful design.
