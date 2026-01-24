---
title: generics
status: α1
implemented:
  - basic-generics
  - type-parameters
pending:
  - monomorphization
  - constraints
deferred:
  - const-generics (α2)
  - variance-annotations (α2)
  - impl-sugar (α2)
  - derive (α2)
  - conditional-types (rfc)
  - mapped-types (rfc)
  - variadic-generics (rfc)
  - hkt (rfc)
---

# generics

ferrule uses generics for type abstraction. type parameters go in angle brackets.

## basic generics

```ferrule
type Box<T> = { value: T };

function identity<T>(x: T) -> T {
  return x;
}

function swap<T, U>(pair: { first: T, second: U }) -> { first: U, second: T } {
  return { first: pair.second, second: pair.first };
}
```

generics are monomorphized. `Box<i32>` and `Box<String>` compile to separate types.

## polymorphism via records

instead of traits, ferrule uses records and explicit passing:

```ferrule
// define operations as a record type
type Eq<T> = { 
  eq: (T, T) -> Bool 
};

type Hash<T> = { 
  hash: (T) -> u64 
};

type Hashable<T> = Eq<T> & Hash<T>;
```

create implementations as namespaced constants:

```ferrule
type UserId = { id: u64 };

const UserId.eq: Eq<UserId> = {
  eq: function(a: UserId, b: UserId) -> Bool { return a.id == b.id; }
};

const UserId.hash: Hash<UserId> = {
  hash: function(u: UserId) -> u64 { return u.id; }
};

const UserId.hashable: Hashable<UserId> = {
  eq: UserId.eq.eq,
  hash: UserId.hash.hash
};
```

use in generic functions:

```ferrule
function dedupe<T>(items: View<T>, h: Hashable<T>) -> View<T> effects [alloc] {
  // use h.hash(item), h.eq(a, b)
}

// explicit usage
const unique = dedupe(users, UserId.hashable);
```

this is more verbose than traits but has advantages:
- no magic lookup
- easy to have multiple implementations
- simple to implement in compiler

## constraints

use `where` to constrain type parameters:

```ferrule
function sort<T>(items: View<mut T>, ord: Ord<T>) -> Unit 
    where T is Copy
{
    // T must be copyable
}
```

## combining operation records

use intersection types:

```ferrule
type HashShow<T> = Hashable<T> & Show<T>;

function dedupeAndPrint<T>(items: View<T>, hs: HashShow<T>, cap io: Io) -> Unit effects [alloc, io] {
  const unique = dedupe(items, hs);
  for item in unique {
        io.println(hs.show(item));
  }
}
```

## what's planned

**const generics** (α2) for type-level values:

```ferrule
type Matrix<T, const ROWS: usize, const COLS: usize> = Array<Array<T, COLS>, ROWS>;

function chunk<T, const N: usize>(arr: View<T>) -> View<Array<T, N>> effects [alloc] {
    // split into chunks of size N
}
```

**impl sugar** (α2) to reduce boilerplate:

```ferrule
impl Hashable<UserId> {
    eq: function(a: UserId, b: UserId) -> Bool { return a.id == b.id; },
    hash: function(u: UserId) -> u64 { return u.id; }
}
// equivalent to: const UserId.Hashable: Hashable<UserId> = { ... }

// with auto-resolution
const unique = dedupe<UserId>(users);  // compiler finds UserId.Hashable
```

**derive** (α2) for common interfaces:

```ferrule
type Point = derive(Eq, Hash, Show) {
    x: f64,
    y: f64,
};
// generates Point.Eq, Point.Hash, Point.Show automatically
```

**operator overloading** (α2) via interface desugaring:

```ferrule
type Add<T, Output = T> = {
    add: (T, T) -> Output
};

// a + b  desugars to  T.Add.add(a, b)

impl Add<Point> {
    add: function(a: Point, b: Point) -> Point {
        return Point { x: a.x + b.x, y: a.y + b.y };
    }
}

const p3 = p1 + p2;  // works
```

**variance annotations** (α2):

```ferrule
type Producer<out T> = { get: () -> T };  // covariant
type Consumer<in T> = { accept: (T) -> Unit };  // contravariant
```

## features in rfcs

these are designed but need more thought:

**conditional types** (rfc):
```ferrule
type Unwrap<T> = if T is Result<infer U, infer E> then U else T;
```

**mapped types** (rfc):
```ferrule
type Readonly<T> = map T { K => { readonly: true, type: T[K] } };
```

**variadic generics** (rfc):
```ferrule
function tuple<...Ts>(values: ...Ts) -> (...Ts) {
    return values;
}
```

**higher-kinded types** (rfc):
```ferrule
type Functor<F<_>> = {
    map: <A, B>(fa: F<A>, f: (A) -> B) -> F<B>
};
```

## summary

| feature | status |
|---------|--------|
| basic `<T>` | α1 |
| constraints | α1 |
| const generics | α2 |
| impl sugar | α2 |
| derive | α2 |
| variance | α2 |
| conditional types | rfc |
| mapped types | rfc |
| variadic | rfc |
| hkt | rfc |
