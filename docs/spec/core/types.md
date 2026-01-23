---
title: types and values
status: α1
implemented:
  - nominal-typing
  - scalar-types
  - records
  - unions
  - result-type
  - maybe-type
  - arrays
pending:
  - copy-vs-move
  - string-internals
deferred:
  - refinements (α2)
  - type-level-naturals (β)
  - variance-annotations (α2)
  - mapped-types (rfc)
  - conditional-types (rfc)
  - intersections (α2)
---

# types and values

ferrule uses strict nominal typing. this means types with identical structure are not compatible. if you define two types that look the same, they're still different types.

## nominal typing

```ferrule
type UserId = { id: u64 };
type PostId = { id: u64 };

const user: UserId = { id: 1 };
const post: PostId = user;  // error: UserId is not PostId
```

to convert between types, write a function:

```ferrule
function toPostId(u: UserId) -> PostId {
  return PostId { id: u.id };
}
```

this is intentional. it prevents bugs where you accidentally pass a user id where a post id was expected.

## scalar types

| category | types |
|----------|-------|
| signed integers | `i8`, `i16`, `i32`, `i64`, `i128` |
| unsigned integers | `u8`, `u16`, `u32`, `u64`, `u128`, `usize` |
| floats | `f32`, `f64` |
| other | `Bool`, `Char`, `Unit` |

`String` is not a scalar. it's a managed type backed by a byte buffer. see [string internals](#string-internals).

## number literals

number literals are polymorphic until resolved:

```ferrule
const x = 42;           // i32 (default integer)
const y = 3.14;         // f64 (default float)
const port: u16 = 8080; // u16 (from annotation)
const ratio: f32 = 3.14; // f32 (from annotation)
```

rules:
- if annotated, use that type
- if not annotated, default to i32 for integers, f64 for floats
- if the literal doesn't fit, error

```ferrule
const x: u8 = 300;  // error: 300 does not fit in u8
```

## copy vs move types

types are either copy or move. this determines what happens on assignment.

**copy types** are duplicated on assignment. the original stays valid:

```ferrule
const a: Point = { x: 1.0, y: 2.0 };
const b = a;      // copied
println(a.x);     // ok, a still valid
```

**move types** transfer ownership. the original becomes invalid:

```ferrule
const s: String = "hello";
const t = s;      // moved
// println(s);    // error: s was moved
```

by default:
- primitives and small structs are copy
- heap-allocated types (String, Box, File) are move
- large structs are move

you can annotate explicitly when needed:

```ferrule
type SmallBuffer = copy { data: Array<u8, 64> };
type BigThing = move { data: Array<u8, 1024> };
```

to copy a move type, use clone:

```ferrule
const u = t.clone();  // explicit copy
println(t);           // ok, t still valid
println(u);           // ok, u is independent copy
```

see [../memory/ownership.md](/docs/memory/ownership) for more on move semantics.

## no any type

there's no `any` type. for dynamic data, use `unknown`:

```ferrule
const data: unknown = parseExternal(input);

// can't use unknown directly
data.field;  // error: can't access properties on unknown

// must narrow first
if data is User {
    data.name;  // ok, data is now User
}
```

## arrays

fixed-length arrays:

```ferrule
Array<T, n>
```

the length `n` is part of the type. `Array<u8, 10>` and `Array<u8, 20>` are different types.

## vectors (simd)

simd-aware fixed vectors:

```ferrule
Vector<T, n>
```

these map to hardware vector registers when possible.

## views

views are fat pointers that reference a range of elements:

```ferrule
View<T>        // immutable
View<mut T>    // mutable
```

views carry a pointer, length, and region id. they can't escape the scope where they were created. see [../memory/views.md](/docs/memory/views).

## strings

```ferrule
String    // immutable utf-8 view
```

strings are immutable. for mutable byte manipulation, use `View<mut u8>`.

## bytes

```ferrule
Bytes     // immutable byte view
```

for mutation, use `View<mut u8>`.

## records

records are product types with named fields:

```ferrule
type User = {
    name: String,
    age: u32,
};

const user = User { name: "alice", age: 30 };
```

## unions

unions are sum types with named variants:

```ferrule
type ParseError = 
  | InvalidByte { index: u32 } 
  | Truncated { expected: u32, actual: u32 };
```

you must handle all variants in a match, or use `_` to catch the rest. see [control-flow.md](/docs/control-flow).

## result type

```ferrule
type Result<T, E> = | ok { value: T } | err { error: E };
```

`ok value` and `err variant { ... }` are sugar for constructing this union.

see [../errors/propagation.md](/docs/errors/propagation).

## maybe type

```ferrule
type Maybe<T> = | Some { value: T } | None;
```

`T?` is sugar for `Maybe<T>`:

```ferrule
const x: u32? = Some { value: 42 };
const y: u32? = None;
```

there's no optional chaining. handle `Maybe` via match or explicit comparisons.

## polymorphism via records

instead of traits, ferrule uses records and explicit passing:

```ferrule
// define operations as record types
type Hasher<T> = { 
  hash: (T) -> u64, 
  eq: (T, T) -> Bool 
};

// create implementation as namespaced constant
const UserId.hasher: Hasher<UserId> = {
  hash: function(u: UserId) -> u64 { return u.id; },
  eq: function(a: UserId, b: UserId) -> Bool { return a.id == b.id; }
};

// generic function takes record as parameter
function dedupe<T>(items: View<T>, h: Hasher<T>) -> View<T> effects [alloc] {
  // use h.hash(item), h.eq(a, b)
}

// explicit usage
const unique = dedupe(users, UserId.hasher);
```

no trait/role/protocol keywords. no impl blocks. no self. no automatic resolution.

the plan is to add `impl` sugar and `derive` in a future version. see [generics.md](/docs/generics).

## string internals

`String` is a managed view over utf-8 bytes. internally it's `(ptr, len, region_id)`. utf-8 validity is guaranteed by construction.

strings are immutable. to modify:

1. copy to a `View<mut u8>` buffer
2. modify the buffer
3. validate and construct new string via `string.from_utf8(view)`

```ferrule
const result = string.from_utf8(modified_bytes);
// result is Result<String, Utf8Error>
```

## features deferred to later

these are designed but not in α1:

**refinements** (α2):
```ferrule
type Port = u16 where self >= 1 && self <= 65535;
```

**variance annotations** (α2):
```ferrule
type Producer<out T> = { get: () -> T };
type Consumer<in T> = { accept: (T) -> Unit };
```

**intersections** (α2):
```ferrule
type HashShow<T> = Hasher<T> & Showable<T>;
```

**mapped types** (rfc):
```ferrule
type Readonly<T> = map T { K => { readonly: true, type: T[K] } };
```

**conditional types** (rfc):
```ferrule
type Unwrap<T> = if T is Result<infer U, infer E> then U else T;
```
