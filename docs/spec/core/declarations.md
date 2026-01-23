---
title: declarations and bindings
status: α1
implemented:
  - const-bindings
  - var-bindings
  - inout-parameters
  - type-inference
  - no-implicit-coercion
pending:
  - move-on-assignment
  - use-after-move-errors
deferred:
  - region-allocation-syntax (α2)
---

# declarations and bindings

this covers how you declare variables and what happens when you assign them.

## immutability by default

the default binding is `const`:

```ferrule
const pageSize: usize = layout.page_size();
```

const bindings can't be reassigned. this is the common case and should be your default.

## mutable bindings

use `var` when you need mutation:

```ferrule
var counter: u32 = 0;
counter = counter + 1;
```

## type inference

ferrule infers types when unambiguous:

```ferrule
const x = 42;        // i32 (default integer)
const y = 3.14;      // f64 (default float)
const s = "hello";   // String
const b = true;      // Bool
```

annotation required when ambiguous or non-default:

```ferrule
const port: u16 = 8080;      // could be many int types
const ratio: f32 = 3.14;     // need f32 not f64
const items: Vec<User> = vec.new();  // empty collection needs type
```

function results always need annotation:

```ferrule
const result = compute();       // error: can't infer, annotate
const result: Data = compute(); // ok
```

## literal type preservation

`const` preserves literal types, `var` widens:

```ferrule
const x = 42;     // type is literal 42
var y = 42;       // type is i32 (widened)
```

this matters for const generics and refinement types.

## no implicit coercion

ferrule never converts types implicitly:

```ferrule
const a: u16 = 100;
const b: u32 = a;       // error: u16 is not u32

const b: u32 = u32(a);  // ok: explicit conversion
```

this applies to everything:
- no int to float
- no narrowing (i32 to i16)
- no widening (i16 to i32)
- no bool coercion
- no null coercion

## move semantics

when you assign a move type, ownership transfers:

```ferrule
const s: String = "hello";
const t = s;      // s is moved to t
// s is now invalid
```

this is not a copy. the data isn't duplicated. `s` becomes unusable after the assignment.

for copy types, assignment duplicates:

```ferrule
const a: i32 = 42;
const b = a;      // a is copied to b
// both a and b are valid
```

see [types.md](types#copy-vs-move-types) for which types are copy vs move.

## use after move

using a moved value is a compile error:

```ferrule
const data: String = "hello";
const other = data;  // move

println(data);  // error: data was moved
```

the compiler tracks which variables have been moved and errors if you try to use them.

## conditional moves

if a value might be moved in one branch, it's invalid after the conditional:

```ferrule
const data: String = "hello";

if condition {
    consume(data);  // moves data
}

use_data(data);  // error: data might have been moved
```

the safe pattern is to move in all branches:

```ferrule
const data: String = "hello";

if condition {
    consume(data);
} else {
    other_consume(data);
}
// data is invalid on all paths, which is fine
```

## loop moves

you can't move the same variable in a loop:

```ferrule
const data: String = "hello";

for i in 0..3 {
    process(data);  // error: can't move in loop
}
```

use clone if you need to pass owned data in each iteration:

```ferrule
for i in 0..3 {
    process(data.clone());  // explicit copy each time
}
```

## by-reference parameters

use `inout` for by-reference mutation:

```ferrule
function bump(inout x: u32) -> Unit { 
  x = x + 1; 
}

var counter: u32 = 0;
bump(inout counter);
// counter is now 1
```

rules:
- `inout` is only valid on function parameters
- callers must pass mutable bindings
- the mutation is visible to the caller

## destructuring

you can destructure records and arrays:

```ferrule
const User { name, age } = user;  // moves both fields out
// user is now fully invalid

const [first, second, ...rest] = items;  // array destructuring
```

partial moves (moving just one field) are not allowed. if you need one field, destructure the whole thing.

## summary

| keyword | meaning |
|---------|---------|
| `const` | immutable binding, preserves literal types |
| `var` | mutable binding, widens literal types |
| `inout` | by-reference parameter |

| assignment | behavior |
|------------|----------|
| copy type | duplicates value, both valid |
| move type | transfers ownership, original invalid |
