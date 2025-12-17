# Compile-Time Evaluation

> **scope:** comptime functions, typed transforms, reflection  
> **related:** [../core/types.md](../core/types.md)

---

## Comptime Functions

Functions marked `comptime` run at compile time:

```ferrule
comptime function crc16_table(poly: u16) -> Array<u16, 256> {
  var table: Array<u16, 256> = [0; 256];
  var i: u32 = 0;
  while i < 256 {
    var crc: u16 = u16(i) << 8;
    var j: u32 = 0;
    while j < 8 {
      if (crc & 0x8000) !== 0 {
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

---

## Comptime Rules

Comptime functions must be **pure and deterministic**:
- no ambient I/O
- no effects (no `effects [...]` declaration)
- no error clause (cannot fail)
- results are memoized by arguments
- results are cacheable across builds

---

## Comptime Invocation

Use `comptime` keyword to evaluate at compile time:

```ferrule
const PAGE_SIZE = comptime layout.page_size();
const LOOKUP_TABLE = comptime generate_table();
```

The result must be a constant-evaluable value.

---

## Typed Transforms

Typed transforms operate on the **typed IR** (not raw syntax):

```ferrule
transform derive_serialize<T> {
  // generates serialization code for type T
  // output must pass all type checks
}
```

Use cases:
- FFI shim generation
- Serialization/deserialization codecs
- CLI argument parsers
- WASM component interfaces

Transforms:
- receive typed AST nodes
- must produce valid, type-checked output
- are applied at compile time

---

## Reflection (Layout Queries)

Query type layouts at compile time:

```ferrule
const page: usize = layout.page_size();
const alignOfBlob: usize = layout.alignof<Blob>();
const sizeOfBlob: usize = layout.sizeof<Blob>();
```

### Available Queries

| Function | Returns |
|----------|---------|
| `layout.sizeof<T>()` | size in bytes |
| `layout.alignof<T>()` | alignment in bytes |
| `layout.page_size()` | system page size |
| `layout.cache_line_size()` | cache line size |

---

## Type Introspection

Limited introspection for transforms:

```ferrule
comptime function field_names<T>() -> Array<String, n> {
  // returns field names of record type T
}

comptime function variant_names<T>() -> Array<String, n> {
  // returns variant names of union type T
}
```

---

## Example: Lookup Table Generation

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

---

## Feature Gates

In early toolchains, some comptime features may be behind feature gates:
- `typed_transforms`
- `advanced_reflection`


