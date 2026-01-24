---
title: effects
status: α1
implemented:
  - effect-syntax
  - effect-subset-rule
  - standard-effects
pending:
  - effect-inference
  - capability-flow-lint
deferred:
  - effect-polymorphism (α2)
  - suspend-effect (β)
  - async-suspension (β)
---

# effects

effects declare what a function might do. io, allocation, time access, that kind of thing. they're part of the function type but separate from type generics.

no effects means pure. you can tell from the signature whether a function does io.

## syntax

types go in `<>`, effects go in `[]`:

```ferrule
function process<T, U>(input: T, cap io: Io) -> U effects [alloc, io] {
    // ...
}
```

a function with no effects clause is pure:

```ferrule
function add(x: i32, y: i32) -> i32 {
    return x + y;
}
```

## standard effects

| effect | meaning | needs capability? |
|--------|---------|-------------------|
| `alloc` | allocate/free memory | no |
| `fs` | file system operations | yes, `Fs` |
| `net` | networking | yes, `Net` |
| `io` | generic device io | yes, device cap |
| `time` | access clocks, sleep | yes, `Clock` |
| `rng` | randomness | yes, `Rng` |
| `atomics` | atomic memory operations | no |
| `simd` | simd intrinsics | no |
| `cpu` | privileged cpu instructions | no |
| `ffi` | foreign abi calls | depends |

some effects need capabilities (fs, net, time, rng). others don't (alloc, atomics, simd). see [../modules/capabilities.md](/docs/modules/capabilities).

## subset rule

for any call `g()` inside `f`, the effects of g must be a subset of f's effects:

```ferrule
function caller() -> Unit effects [fs] {
    netCall();  // error: requires [net], not in [fs]
}
```

this is the core enforcement. you can't sneak effects past the caller.

## effects vs capabilities

this is important to understand: they're related but different.

**effects** are markers. they say "this function might do io" or "this function might allocate". they're compile-time information.

**capabilities** are values. they're the authority to actually do the io. you pass them around.

the relationship:

| effect | capability | explanation |
|--------|------------|-------------|
| `fs` | `Fs` | need Fs cap to do fs effect |
| `net` | `Net` | need Net cap to do net effect |
| `time` | `Clock` | need Clock cap to do time effect |
| `rng` | `Rng` | need Rng cap to do rng effect |
| `alloc` | none | just marks allocation |
| `atomics` | none | just marks atomic ops |

if a function has `effects [fs]`, it must have a `cap fs: Fs` somewhere in the call chain. this is checked by the capability flow lint.

```ferrule
function readAll(p: Path, cap fs: Fs) -> Bytes error IoError effects [fs] {
    const f = check fs.open(p);
    return ok check fs.readAll(f);
}
```

## purity

a pure function has no effects and no error clause:

```ferrule
function add(x: i32, y: i32) -> i32 {
    return x + y;
}
```

functions with `error E` are not pure even if they have no effects. error propagation is a form of control flow.

## effect inference

within a module, the compiler can infer effects from the function body. but public symbols must spell them out:

```ferrule
// private, inference ok
function helper(cap io: Io) {
    io.println("hello");  // inferred: effects [io]
}

// public, must be explicit
pub function api(cap io: Io) -> Unit effects [io] {
    helper(io);
}
```

exports without explicit effects are rejected.

## higher-order functions

when you take a function as parameter, you need to handle its effects:

```ferrule
function forEach<T>(items: View<T>, f: (T) -> Unit effects F) -> Unit effects [...F] {
  for item in items {
    f(item);
  }
}
```

the `...F` spreads the effects from f into forEach's effects. whatever effects f has, forEach also has.

## threading capabilities

for higher-order functions that need capabilities:

```ferrule
function processFiles(paths: View<Path>, cap fs: Fs) -> View<String> 
    error IoError 
    effects [fs, alloc] 
{
    return paths.map(function(p: Path) -> String effects [fs] {
    return check fs.readAllText(p);
    });
}
```

the capability flows through the closure.

## what's planned

**effect polymorphism** (α2) with named effect variables:

```ferrule
function map<T, U>(arr: View<T>, f: (T) -> U effects F) -> View<U> 
    effects [alloc, ...F] 
{
    // F is whatever effects f has
}
```

**suspend effect** (β) for async:

```ferrule
function fetch(url: String, cap net: Net) -> Response 
    error NetError 
    effects [net, suspend] 
{
    const socket = net.connect(url.host, url.port)?;
    return ok socket.readAll()?;  // may suspend here
}
```

the suspend effect means the function may pause and resume. this is how async works without function coloring. see the async rfc for details.

## summary

| syntax | meaning |
|--------|---------|
| `effects [fs, net]` | has fs and net effects |
| `effects [alloc, ...]` | has alloc plus spread from params |
| `effects [...F]` | has all effects from F |
| no effects clause | pure (private) or error (public) |
