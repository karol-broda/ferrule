# Types & Values

> **scope:** scalar types, compound types, parametric types, unions, refinements, nominal typing, polymorphism  
> **related:** [declarations.md](declarations.md) | [generics.md](generics.md) | [../memory/views.md](../memory/views.md)

---

## Nominal Typing (Strict)

Ferrule uses **strict nominal typing**. Types with identical structure are NOT compatible:

```ferrule
type UserId = { id: u64 };
type PostId = { id: u64 };

const user: UserId = { id: 1 };
const post: PostId = user;  // ERROR: UserId is not PostId
```

To convert between types, use explicit functions:

```ferrule
function toPostId(u: UserId) -> PostId {
  return PostId { id: u.id };
}
```

---

## Built-in Scalar Types

| Category | Types |
|----------|-------|
| signed integers | `i8`, `i16`, `i32`, `i64`, `i128` |
| unsigned integers | `u8`, `u16`, `u32`, `u64`, `u128`, `usize` |
| floats | `f16`, `f32`, `f64` |
| other | `Bool`, `Char`, `Unit` (zero-size) |

> `String` and `Bytes` are region-allocated managed types, not scalars. See [String Internals](#string-internals).

---

## Number Literals

Number literals are **polymorphic in the AST** until resolved:

```ferrule
const x = 42;           // resolved to i32 (default integer)
const y = 3.14;         // resolved to f64 (default float)
const port: u16 = 8080; // resolved to u16 (from annotation)
const ratio: f32 = 3.14; // resolved to f32 (from annotation)
```

**Rules:**
- If annotated, use the annotation type
- If not annotated, default to `i32` for integers, `f64` for floats
- If literal doesn't fit the type, error

```ferrule
const x: u8 = 300;  // ERROR: 300 does not fit in u8
```

---

## No `any` Type

Ferrule has **no `any` type**. For dynamic data, use `unknown`:

```ferrule
const data: unknown = parseExternal(input);

// cannot use unknown directly
data.field;  // ERROR: cannot access properties on unknown

// must narrow first
if data is User {
  data.name;  // OK: data is now User
}

// or explicit unsafe cast (auditable)
const user = unsafe_cast<User>(data);
```

---

## Compound & Parametric Types

### Arrays (Fixed Length)

```ferrule
Array<T, n>
```

### Vectors (SIMD-aware)

```ferrule
Vector<T, n>
```

### Views (Fat Pointers)

```ferrule
View<T>        // immutable: (ptr, len, region_id)
View<mut T>    // mutable
```

See [../memory/views.md](../memory/views.md) for full semantics.

### Strings

```ferrule
String    // immutable UTF-8 view
```

For mutable byte manipulation, use `View<mut u8>`.

### Bytes

```ferrule
Bytes     // immutable byte view
```

For mutation, use `View<mut u8>`.

### Records

```ferrule
{ field: Type, ... }
```

### Closed Unions (Discriminated)

```ferrule
type ParseError = 
  | InvalidByte { index: u32 } 
  | Truncated { expected: u32, actual: u32 };
```

Unions must be fully covered in `match` or use `_`. See [control-flow.md](control-flow.md#pattern-matching).

---

## Result Type (Built-in)

```ferrule
type Result<T, E> = | ok { value: T } | err { error: E };
```

`ok value` and `err Variant { ... }` are sugar for constructing this union.

See [../errors/propagation.md](../errors/propagation.md) for usage.

---

## Maybe Type (Built-in)

```ferrule
type Maybe<T> = | Some { value: T } | None;
```

**Sugar:**
- `T?` is equivalent to `Maybe<T>`

```ferrule
const x: u32? = Some { value: 42 };
const y: u32? = None;
```

There is **no optional chaining**. Handle `T?` via `match` or explicit comparisons.

---

## Intersections

```ferrule
A & B
```

Combines record types. Used for composing operation records:

```ferrule
type Hasher<T> = { hash: (T) -> u64, eq: (T, T) -> Bool };
type Showable<T> = { show: (T) -> String };
type HashShow<T> = Hasher<T> & Showable<T>;
```

---

## Refinements

```ferrule
type Port = u16 where self >= 1 && self <= 65535;
```

The `where` clause specifies a predicate:
- **Compile-time:** checked when provable
- **Runtime:** checked otherwise (returns error or traps)

---

## Type-Level Naturals

`Nat` type with arithmetic in bounds/shape expressions.

---

## Variance

Explicit variance annotations for generic type parameters:

```ferrule
// out = covariant (can only output T)
type Producer<out T> = { get: () -> T };

// in = contravariant (can only input T)
type Consumer<in T> = { accept: (T) -> Unit };

// invariant (default) — can input and output T
type Box<T> = { value: T, set: (T) -> Unit };
```

---

## Polymorphism via Records

Instead of traits/roles, Ferrule uses **records + generics + explicit passing**:

```ferrule
// 1. define operations as record types
type Hasher<T> = { 
  hash: (T) -> u64, 
  eq: (T, T) -> Bool 
};

// 2. define type
type UserId = { id: u64 };

// 3. create implementation as namespaced constant
const UserId.hasher: Hasher<UserId> = {
  hash: function(u: UserId) -> u64 { return u.id; },
  eq: function(a: UserId, b: UserId) -> Bool { return a.id == b.id; }
};

// 4. generic function takes record as parameter
function dedupe<T>(items: View<T>, h: Hasher<T>) -> View<T> effects [alloc] {
  // use h.hash(item), h.eq(a, b)
}

// 5. explicit usage
const unique = dedupe(users, UserId.hasher);
```

**No OOP features:**
- No `trait` / `role` / `protocol` keywords
- No `impl` blocks
- No method syntax (`x.method()`)
- No `self` keyword
- No automatic resolution

See [generics.md](generics.md) for full generics specification.

---

## Mapped Types

```ferrule
type Readonly<T> = map T { K => { readonly: true, type: T[K] } };
```

---

## Conditional Types

```ferrule
type Unwrap<T> = if T is Result<infer U, infer E> then U else T;
```

**Non-distributive by default.** For distribution over unions:

```ferrule
type Distributed<T> = distribute T { each U => Array<U> };
```

---

## String Internals

`String` is a managed view over UTF-8 bytes with region binding `(ptr, len, region_id)`. UTF-8 validity is guaranteed by construction.

Strings are **immutable**. To modify string data:

1. Copy to a new `View<mut u8>` buffer in a region
2. Modify the buffer
3. Validate and construct a new String via `string.from_utf8(view)` which returns `Result<String, Utf8Error>`
