---
title: ownership and move semantics
status: α1
implemented: []
pending:
  - move-on-assign
  - use-after-move-detection
  - conditional-move-tracking
  - loop-move-detection
  - clone-trait
deferred:
  - escape-analysis (α2)
  - verification-hints (α2)
---

# ownership and move semantics

ferrule uses a scoped ownership model. there's no borrow checker and no garbage collection. instead, ownership is tracked at compile time with simple rules.

the core insight: you don't need to track complex lifetimes if references can't escape their creation scope.

## the rules

1. **views are scoped** - a view can't leave the function that created it
2. **regions are scoped** - region allocations can't escape their region
3. **to escape, copy** - if you need data to leave a scope, you copy it

this gives you memory safety without the complexity of lifetime annotations.

## move semantics

when you assign a value, one of two things happens:

**copy types** duplicate the value:

```ferrule
const a: i32 = 42;
const b = a;      // a is copied
io.println(a);    // ok, a still valid
io.println(b);    // ok, b has its own copy
```

**move types** transfer ownership:

```ferrule
const s: String = "hello";
const t = s;      // s is moved to t
// io.println(s); // error: s was moved
io.println(t);    // ok, t owns the data now
```

the key difference: copy duplicates, move transfers. after a move, the original is invalid.

## which types are copy vs move

by default:

- primitives (i32, f64, bool, etc) are copy
- small structs (roughly < 64 bytes) are copy
- heap-backed types (String, Vec, Box) are move
- unique resources (File, Socket) are move
- large structs are move

you can annotate explicitly:

```ferrule
type SmallBuffer = copy { data: Array<u8, 64> };
type Handle = move { id: u64 };
```

## use after move

the compiler tracks what's been moved:

```ferrule
const data: String = "hello";
process(data);    // data is moved into process

io.println(data); // error: data was moved on line 2
```

the error message tells you where the move happened.

## conditional moves

if a move might happen in one branch, the variable is invalid afterward:

```ferrule
const data: String = "hello";

if condition {
    consume(data);  // moves data
}

// here, data might have been moved (if condition was true)
// or might still be valid (if condition was false)

use(data);  // error: data might have been moved
```

the compiler is conservative. if any path moves the value, it's invalid on all paths after the conditional.

safe patterns:

```ferrule
// move in all branches
if condition {
    consume(data);
} else {
    other(data);
}
// data invalid everywhere, that's fine

// or use clone
if condition {
    consume(data.clone());
}
use(data);  // ok, only the clone was moved
```

## loop moves

you can't move a value inside a loop:

```ferrule
const data: String = "hello";

for i in 0..3 {
    process(data);  // error: would move data multiple times
}
```

the fix is explicit cloning:

```ferrule
for i in 0..3 {
    process(data.clone());  // explicit copy each iteration
}
```

this makes the cost visible. cloning in a hot loop is something you want to think about.

## no partial moves

you can't move a single field out of a struct:

```ferrule
type User = { name: String, email: String };

const user = User { name: "alice", email: "alice@example.com" };
const name = user.name;  // what's the state of user now?
```

ferrule doesn't allow this. if you need one field, destructure the whole thing:

```ferrule
const User { name, email } = user;
// now both name and email are separate values
// user is fully invalid
```

this keeps the rules simple. no tracking of "partially valid" structs.

## clone

to copy a move type, use `clone`:

```ferrule
const s: String = "hello";
const copy = s.clone();  // explicit copy

io.println(s);     // ok, s still valid
io.println(copy);  // ok, copy is independent
```

clone is explicit because copying can be expensive. you should think about whether you really need a copy.

types that can be cloned implement a `Clone` record:

```ferrule
type Clone<T> = {
    clone: (T) -> T
};
```

## why not a borrow checker

a borrow checker (like rust's) can prove more programs safe. but it has costs:

- complex error messages
- fighting the compiler
- lifetime annotations infect your code

ferrule's model is simpler:

- easy to understand rules
- predictable behavior
- explicit copies when needed

the tradeoff is you copy more. for most programs, this is fine. the copies are explicit so you can optimize hot paths.

## safety guarantees

this model eliminates:

- **double free** - regions free everything at once
- **use after free** - views can't escape their scope
- **dangling pointers** - compile-time tracking

these bugs are compile errors, not runtime crashes.

## what's planned for α2

**escape analysis** will catch more cases:

```ferrule
function bad() -> View<u8> {
    const arena = region.arena(1024);
    defer arena.dispose();
    const buf = arena.alloc<u8>(100);
    return buf;  // error: buf escapes its region
}
```

**verification hints** for complex cases:

```ferrule
// assert all paths move data
if condition { consume(data); } else { other(data); }
where data is moved;

// ownership check (extends check keyword)
check moved data;     // compile error if not definitely moved
check valid data;     // compile error if might be moved

// single-iteration loop (known to run exactly once)
once for item in items {
    process(item, data);  // ok, compiler knows only one iteration
}

// compile-time assertions
assert valid data;    // error if might be moved
assert moved data;    // error if might NOT be moved

// branch on move state
if valid data {
    use_data(data);
} else {
    recreate_data();
}
```

these add safety without complexity. the hints verify your intent, they don't bypass checking.

**what we don't add** - no bypass mechanisms:

```ferrule
x as! ValidState      // no: forces compiler to accept
@assume_valid(x)      // no: unchecked assumption (except in unsafe)
#[allow(moved)]       // no: silencing warnings
```

the only escape hatch is `unsafe`, which is explicit about taking responsibility.
