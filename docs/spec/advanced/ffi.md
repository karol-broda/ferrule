# Foreign Function Interface

> **scope:** C ABI, WASM component model, interop rules  
> **related:** [asm.md](asm.md) | [../memory/views.md](../memory/views.md)

---

## C ABI

### Exporting to C

```ferrule
export c function add(x: i32, y: i32) -> i32 { 
  return x + y; 
}
```

This generates:
- C-compatible calling convention
- Header file with proper types
- Symbol with C linkage

### Importing from C

```ferrule
import c function getenv(name: *u8) -> *u8;
import c function malloc(size: usize) -> *u8;
import c function free(ptr: *u8) -> Unit;
```

C imports:
- require the `ffi` effect to call
- may return nullable pointers
- must be validated before use in safe code

---

## Pointer Conversion

Raw pointers `*T` exist only at FFI boundaries:

```ferrule
const raw: *u8? = getenv(name);
if raw === null { 
  return err NotFound { path: name_as_path(name) };
}

// convert to safe view before use
const view: View<u8> = view.from_raw(raw, len);
```

Immediately after crossing the boundary:
- convert to `View<T>` or validate and wrap in capsule types
- or mark as tainted and restrict usage until validated

---

## FFI Effect

Dereferencing raw pointers requires the `ffi` effect:

```ferrule
function process_c_data(ptr: *u8, len: usize) -> Bytes effects [ffi] {
  const view = view.from_raw_unchecked(ptr, len);
  return bytes.copy(view);
}
```

---

## WASM Component Model

### Exporting Components

```ferrule
export wasm component interface {
  function http_get(url: String) -> Bytes error ClientError effects [net];
  function process(data: Bytes) -> Bytes;
}
```

### Importing Components

```ferrule
import wasm component "wasi:http/handler" {
  function handle(request: Request) -> Response;
}
```

Component interfaces are generated from type/effect signatures. Versions are tracked via package hashes.

---

## Type Mapping

### C Type Mapping

| Ferrule | C |
|---------|---|
| `i8` | `int8_t` |
| `i16` | `int16_t` |
| `i32` | `int32_t` |
| `i64` | `int64_t` |
| `u8` | `uint8_t` |
| `u16` | `uint16_t` |
| `u32` | `uint32_t` |
| `u64` | `uint64_t` |
| `f32` | `float` |
| `f64` | `double` |
| `*T` | `T*` |
| `Bool` | `bool` / `_Bool` |

### Struct Layout

Structs exported to C use C-compatible layout:

```ferrule
export c type Point = { x: f64, y: f64 };
// generates: struct Point { double x; double y; };
```

---

## Calling Conventions

Explicit calling convention specification:

```ferrule
import c(stdcall) function WinAPI_CreateFile(...) -> Handle;
import c(cdecl) function legacy_func(...) -> i32;
```

---

## Header Generation

Running `ferrule build` generates C headers:

```c
// generated: my_lib.h
#pragma once

#include <stdint.h>

int32_t add(int32_t x, int32_t y);

typedef struct Point {
  double x;
  double y;
} Point;
```

---

## Safety Guidelines

1. **Validate at boundaries** — check pointers, lengths, and invariants immediately
2. **Convert to safe types** — use `View<T>` instead of raw pointers in safe code
3. **Use capsules for resources** — wrap handles in capsule types with finalizers
4. **Mark nullable** — C pointers are often nullable, use `*T?`
5. **Check return codes** — convert C-style errors to Ferrule error domains


