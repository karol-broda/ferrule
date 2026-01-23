---
title: foreign function interface
status: α2
implemented: []
pending: []
deferred:
  - c-abi
  - extern-import
  - extern-export
  - header-generation
  - wasm-component-model (β)
---

# foreign function interface

> this feature is planned for α2. the spec describes what it will be, not what's implemented now.

ffi lets ferrule code call c functions and expose ferrule functions to c.

## extern declarations

declare c functions you want to call:

```ferrule
extern "C" function getenv(name: *u8) -> *u8;
extern "C" function malloc(size: usize) -> *u8;
extern "C" function free(ptr: *u8) -> Unit;
```

calling extern functions requires unsafe:

```ferrule
function get_environment_variable(name: String) -> Maybe<String> {
    unsafe {
        const ptr = getenv(name.as_ptr());
        if ptr == null {
            return None;
        }
        return Some { value: String.from_c_str(ptr) };
    }
}
```

## exporting to c

expose ferrule functions to c:

```ferrule
export "C" function add(x: i32, y: i32) -> i32 {
    return x + y;
}
```

this generates:
- c-compatible calling convention
- symbol with c linkage
- header file with proper types

## raw pointers

raw pointers exist for ffi. they're unsafe to use.

```ferrule
*T      // pointer to T (nullable)
*mut T  // mutable pointer to T
```

converting between pointers and views:

```ferrule
unsafe {
    // view to pointer
    const ptr: *u8 = view.as_ptr(buf);
    
    // pointer to view (must know length)
    const view: View<u8> = View.from_raw(ptr, len);
}
```

## extern structs

for c-compatible layout:

```ferrule
type CHeader = extern {
    magic: u32,
    version: u16,
    flags: u16,
};
```

extern structs:
- use c layout rules
- can be passed to/from c functions
- can be cast to/from raw pointers

## type mapping

| ferrule | c |
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
| `Bool` | `bool` |

## calling conventions

specify calling convention when needed:

```ferrule
extern "C" function normal_function() -> i32;
extern "C" "stdcall" function win32_function() -> i32;
extern "C" "fastcall" function optimized_function() -> i32;
```

## header generation

running `ferrule build` generates c headers:

```c
// generated: my_lib.h
#pragma once
#include <stdint.h>

int32_t add(int32_t x, int32_t y);

typedef struct CHeader {
    uint32_t magic;
    uint16_t version;
    uint16_t flags;
} CHeader;
```

## embedded: interrupt handlers

for embedded systems, mark interrupt handlers:

```ferrule
#[interrupt]
function timer_handler() -> Unit {
    // handle timer interrupt
    // no capabilities here
}

#[interrupt(priority = 3)]
function uart_rx_handler() -> Unit {
    // handle uart receive
}
```

interrupt handlers:
- can't have parameters
- can't have capabilities
- must be fast
- should only touch statics or memory-mapped io

## safety guidelines

1. validate at boundaries - check pointers, lengths, invariants
2. convert to safe types - use View instead of raw pointers
3. mark nullable - c pointers are often nullable
4. check return codes - convert c errors to ferrule error domains
5. minimize unsafe surface - wrap unsafe ops in safe functions

```ferrule
// unsafe internals
function read_c_string(ptr: *u8) -> String {
    unsafe {
        // find null terminator
        var len: usize = 0;
        while (ptr + len).* != 0 {
            len = len + 1;
        }
        return String.from_raw(ptr, len);
    }
}

// safe api
function get_env(name: String) -> Maybe<String> {
    unsafe {
        const ptr = getenv(name.as_ptr());
        if ptr == null {
            return None;
        }
        return Some { value: read_c_string(ptr) };
    }
}
```

## wasm (β)

wasm component model support is planned for later:

```ferrule
export wasm component interface {
    function process(data: Bytes) -> Bytes;
}

import wasm component "wasi:http/handler" {
    function handle(request: Request) -> Response;
}
```
