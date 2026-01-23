---
rfc: 0005
title: higher-kinded types
status: draft
created: 2026-01-23
target: β
---

# RFC-0005: higher-kinded types

## summary

higher-kinded types (hkt) allow abstracting over type constructors, not just types. this enables generic programming patterns like functor, monad, and applicative without concrete container dependencies.

## motivation

today, we can write a function that maps over a specific container:

```ferrule
function map_option<T, U>(opt: Option<T>, f: function(T) -> U) -> Option<U> {
  match opt {
    Some(x) => Some(f(x)),
    None => None,
  }
}

function map_result<T, U, E>(res: Result<T, E>, f: function(T) -> U) -> Result<U, E> {
  match res {
    Ok(x) => Ok(f(x)),
    Err(e) => Err(e),
  }
}
```

but we can't abstract over "anything mappable":

```ferrule
// we want this
function map<F<_>, T, U>(container: F<T>, f: function(T) -> U) -> F<U> { ... }
```

hkt enables:
- functor, applicative, monad abstractions
- generic traversals
- effect interpreters
- container-agnostic algorithms

## detailed design

### syntax

type constructors are written with `<_>` to indicate arity:

```ferrule
// F is a type constructor that takes one type argument
interface Functor<F<_>> {
  function map<T, U>(self: F<T>, f: function(T) -> U) -> F<U>;
}
```

multi-parameter type constructors:

```ferrule
// F takes two type arguments
interface Bifunctor<F<_, _>> {
  function bimap<A, B, C, D>(
    self: F<A, B>,
    f: function(A) -> C,
    g: function(B) -> D
  ) -> F<C, D>;
}
```

### implementing hkt interfaces

implementations provide the concrete type constructor:

```ferrule
impl Functor<Option> {
  function map<T, U>(self: Option<T>, f: function(T) -> U) -> Option<U> {
    match self {
      Some(x) => Some(f(x)),
      None => None,
    }
  }
}

impl Functor<Result<_, E>> for all E {
  function map<T, U>(self: Result<T, E>, f: function(T) -> U) -> Result<U, E> {
    match self {
      Ok(x) => Ok(f(x)),
      Err(e) => Err(e),
    }
  }
}
```

### using hkt in functions

generic functions can require hkt interfaces:

```ferrule
function double_all<F<_>>(container: F<i32>) -> F<i32>
  where F: Functor
{
  return container.map(|x| x * 2);
}

const doubled_option = double_all(Some(21));  // Some(42)
const doubled_result: Result<i32, string> = double_all(Ok(21));  // Ok(42)
```

### monad example

the classic monad interface:

```ferrule
interface Monad<M<_>> extends Functor<M> {
  function pure<T>(value: T) -> M<T>;
  function flat_map<T, U>(self: M<T>, f: function(T) -> M<U>) -> M<U>;
}

impl Monad<Option> {
  function pure<T>(value: T) -> Option<T> {
    return Some(value);
  }

  function flat_map<T, U>(self: Option<T>, f: function(T) -> Option<U>) -> Option<U> {
    match self {
      Some(x) => f(x),
      None => None,
    }
  }
}
```

### kind system

the compiler tracks kinds:

| kind | meaning |
|------|---------|
| `*` | concrete type (i32, string) |
| `* -> *` | type constructor with one param (Option, List) |
| `* -> * -> *` | two params (Result, Map) |
| `(* -> *) -> *` | takes a type constructor |

kind errors are reported when kinds don't match:

```
error: kind mismatch
  expected: * -> *
  found: *
  in: Functor<i32>
  note: i32 is a type, not a type constructor
```

## drawbacks

- significant complexity in type checker
- harder to understand error messages
- runtime overhead if not monomorphized
- learning curve for users unfamiliar with hkt

## alternatives

### no hkt, use code generation

generate specialized versions with comptime:

```ferrule
comptime function derive_functor<T> { ... }
```

rejected because it doesn't provide the abstraction benefits.

### defunctionalization

encode hkt using type-level tricks without real hkt:

```ferrule
interface Functor {
  type Applied<T>;
  function map<T, U>(self: Applied<T>, f: function(T) -> U) -> Applied<U>;
}
```

rejected because it's verbose and doesn't scale.

### only specific interfaces

provide Functor, Monad etc. as compiler magic, not general hkt.

could be a stepping stone but limits extensibility.

## prior art

| language | approach |
|----------|----------|
| haskell | full hkt with kind inference |
| scala | hkt with `F[_]` syntax |
| rust | no hkt, uses gats as partial workaround |
| ocaml | functors (module-level) |
| purescript | hkt like haskell |

haskell's approach is the gold standard. scala's syntax is similar to this proposal.

## unresolved questions

1. should kind annotations be explicit or inferred?
2. how do we handle variance with hkt?
3. should we support kind polymorphism?
4. what's the monomorphization strategy for hkt?

## future possibilities

- kind polymorphism (`forall k. k -> *`)
- type-level programming with hkt
- effect system built on hkt
- monad transformers
