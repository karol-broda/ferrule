# Declarations & Bindings

> **scope:** `const`, `var`, `inout` — immutability rules, by-reference parameters, type inference  
> **related:** [types.md](types.md) | [../functions/syntax.md](../functions/syntax.md)

---

## Immutability by Default

The default binding is `const` (immutable):

```ferrule
const pageSize: usize = layout.page_size();
```

---

## Mutable Bindings

Use `var` for mutable bindings:

```ferrule
var counter: u32 = 0;
counter = counter + 1;
```

---

## Type Inference Rules

### Unambiguous Literals — Inference Allowed

```ferrule
const x = 42;        // OK: i32 (default integer)
const y = 3.14;      // OK: f64 (default float)
const s = "hello";   // OK: String
const b = true;      // OK: Bool
```

### Ambiguous or Non-Default — Annotation Required

```ferrule
const port: u16 = 8080;      // 8080 could be many int types
const ratio: f32 = 3.14;     // need f32 not f64
const items: Vec<User> = vec.new();  // empty collection needs type
```

### Function Results — Annotation Required

```ferrule
const result = compute();       // ERROR: cannot infer, annotate
const result: Data = compute(); // OK: explicit type
```

### Literal Type Preservation

`const` preserves literal types, `var` widens:

```ferrule
const x = 42;     // type is i32 literal 42
var y = 42;       // type is i32 (widened, because mutable)
```

---

## No Implicit Coercion

Ferrule **never** converts types implicitly:

```ferrule
const a: u16 = 100;
const b: u32 = a;       // ERROR: u16 is not u32

const b: u32 = u32(a);  // OK: explicit conversion
```

This applies to all conversions:
- No int → float
- No narrowing (i32 → i16)
- No widening (i16 → i32)
- No bool coercion
- No null coercion

---

## By-Reference Parameters

Use `inout` for by-reference mutation in function parameters:

```ferrule
function bump(inout x: u32) -> Unit { 
  x = x + 1; 
}
```

**Rules:**
- `inout` is only valid on function parameters
- No hidden aliasing — the reference is explicit
- Callers must pass mutable bindings

---

## Region Allocation Example

```ferrule
const heap: Region = region.heap();
const buf: View<mut u8> = heap.alloc<u8>(4096);
defer heap.dispose();
```

See [../memory/regions.md](../memory/regions.md) for region semantics.

---

## Summary

| Keyword | Meaning |
|---------|---------|
| `const` | immutable binding (default), preserves literal types |
| `var` | mutable binding, widens literal types |
| `inout` | by-reference parameter (mutation visible to caller) |

| Inference | Rule |
|-----------|------|
| Unambiguous literals | Allowed (defaults to i32/f64/String/Bool) |
| Ambiguous types | Annotation required |
| Function call results | Annotation required |
| Non-default types | Annotation required |
