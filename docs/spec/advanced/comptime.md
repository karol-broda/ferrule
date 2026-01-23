---
title: compile-time evaluation
status: α2
implemented: []
pending: []
deferred:
  - comptime-functions
  - typed-transforms
  - reflection
  - type-introspection
---

# compile-time evaluation

> this feature is planned for α2. the spec describes what it will be, not what's implemented now.

comptime lets you run code at compile time. this is useful for generating lookup tables, validating constants, and code generation.

## comptime functions

functions marked `comptime` run at compile time:

```ferrule
comptime function crc16_table(poly: u16) -> Array<u16, 256> {
  var table: Array<u16, 256> = [0; 256];
  var i: u32 = 0;
  while i < 256 {
    var crc: u16 = u16(i) << 8;
    var j: u32 = 0;
    while j < 8 {
            if (crc & 0x8000) != 0 {
        crc = (crc << 1) ^ poly;
      } else {
        crc = crc << 1;
      }
      j = j + 1;
    }
    table[i] = crc;
    i = i + 1;
  }
  return table;
}

const CRC16 = comptime crc16_table(0x1021);
```

the result is computed at compile time and embedded in the binary.

## rules

comptime functions must be pure and deterministic:
- no ambient io
- no effects (no `effects [...]` declaration)
- no error clause (can't fail)
- results are memoized by arguments
- results are cacheable across builds

this ensures builds are reproducible.

## invocation

use the `comptime` keyword to evaluate at compile time:

```ferrule
const PAGE_SIZE = comptime layout.page_size();
const LOOKUP_TABLE = comptime generate_table();
```

the result must be a constant-evaluable value.

## typed transforms

typed transforms operate on the typed ir (not raw syntax):

```ferrule
transform derive_serialize<T> {
  // generates serialization code for type T
  // output must pass all type checks
}
```

use cases:
- ffi shim generation
- serialization/deserialization codecs
- cli argument parsers
- wasm component interfaces

transforms:
- receive typed ast nodes
- must produce valid, type-checked output
- are applied at compile time

## reflection

query type layouts at compile time:

```ferrule
const page: usize = layout.page_size();
const alignOfBlob: usize = layout.alignof<Blob>();
const sizeOfBlob: usize = layout.sizeof<Blob>();
```

available queries:

| function | returns |
|----------|---------|
| `layout.sizeof<T>()` | size in bytes |
| `layout.alignof<T>()` | alignment in bytes |
| `layout.page_size()` | system page size |
| `layout.cache_line_size()` | cache line size |

## type introspection

limited introspection for transforms:

```ferrule
comptime function field_names<T>() -> Array<String, n> {
  // returns field names of record type T
}

comptime function variant_names<T>() -> Array<String, n> {
  // returns variant names of union type T
}
```

## example: lookup table

```ferrule
comptime function sin_table(steps: u32) -> Array<f32, steps> {
  var table: Array<f32, steps> = [0.0; steps];
  var i: u32 = 0;
  while i < steps {
    const angle = (f32(i) / f32(steps)) * 2.0 * math.PI;
    table[i] = math.sin(angle);
    i = i + 1;
  }
  return table;
}

const SIN_256 = comptime sin_table(256);
```

## what this enables

comptime is essential for:
- **embedded**: compute lookup tables at build time, not runtime
- **zero-cost abstractions**: generate specialized code
- **derive macros**: auto-generate serialization, comparison, etc.
- **validation**: ensure constants are valid at build time

the key is: if the compiler can compute it, do it at compile time.
