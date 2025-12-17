# Effects

> **scope:** effect system, standard effects, subset rule, effect polymorphism, async suspension  
> **related:** [syntax.md](syntax.md) | [../modules/capabilities.md](../modules/capabilities.md) | [../concurrency/tasks.md](../concurrency/tasks.md)

---

## Overview

- Effects declare **what a function may do** (I/O, allocation, time, atomics, etc.)
- Effects are **part of the function type** but kept **separate from type generics**
- There are **no implicit effects**; absence of `effects [...]` means pure, non-suspending
- Async suspension is allowed **only if** an appropriate effect is present

---

## Standard Effects (α1)

| Effect | Meaning | Typical Capabilities |
|--------|---------|---------------------|
| `alloc` | allocate/free memory in the current region or via an allocator | — |
| `fs` | file system operations (open, read, write, stat) | `Fs` |
| `net` | networking (connect, send, receive) | `Net` |
| `io` | generic non-fs, non-net device I/O | device caps |
| `time` | access clocks, sleep, deadlines | `Clock` |
| `rng` | randomness | `Rng` |
| `atomics` | atomic memory operations | — |
| `simd` | usage of SIMD intrinsics | — |
| `cpu` | privileged CPU instructions (rdtsc, cpuid, fences) | — |
| `ffi` | calls across foreign ABIs (C/WASM/other) | corresponding caps |

> Projects may add domain-specific effects (e.g., `gpu`, `db`) via tooling.

---

## Syntax

Types and effects are **separate** — types in `<>`, effects in `[]`:

```ferrule
function process<T, U>(input: T) -> U effects [alloc, io] { ... }
```

---

## Effect Subset Rule

For any call `g()` inside `f`:

**effects(g) ⊆ effects(f)**

If not satisfied, the compiler diagnoses with the missing effects.

```ferrule
function caller() -> Unit effects [fs] {
  netCall();  // ERROR: requires effect [net], not subset of [fs]
}
```

---

## Effect Inference vs Explicitness

### Within a Module

The compiler may **infer** a function's effect set from its body when omitted.

### Public Symbols

**Public symbols must spell their effect sets explicitly.** This includes:
- Exports from a package/module
- C/WASM component boundaries

Toolchains reject exports with inferred effects.

---

## Effect Polymorphism

### Spread Syntax

Spread parameter function effects into the caller:

```ferrule
function map<T, U>(arr: View<T>, f: (T) -> U) -> View<U> effects [alloc, ...] {
  // ... means: include all effects from f
}
```

### Explicit Effect Variables

For more control, name the effect set:

```ferrule
function map<T, U>(arr: View<T>, f: (T) -> U effects F) -> View<U> 
  effects [alloc, ...F] 
{
  // F is the effect set of f
  // map has alloc plus whatever f has
}
```

### Effect Constraints

Require specific effects:

```ferrule
function withTimeout<T, E>(op: () -> T error E effects F) -> T error E 
  effects [time, ...F]
  where F includes [time]
{
  // F must include time
}
```

---

## Async Suspension

A function may suspend **only if** `effects` includes one of:
- `net`
- `io`
- `time`
- A user-defined suspending effect

```ferrule
function fetch(url: Url, deadline: Time) -> Response error ClientError effects [net, time] {
  const tok = cancel.token(deadline);
  const sock = map_error net.connect(url.host, url.port, tok)
               using (e => ClientError.Timeout { ms: time.until(deadline) });
  return check request(sock, url, tok) with { op: "request" };
}
```

---

## Capabilities vs Effects

- **Effects** describe what might happen
- **Capabilities** are authority values you must pass

### Static Rule

If a function lists `fs` in its effects, it must either:
1. Take at least one `cap Fs` parameter, or
2. Call another function that takes such a parameter

This is enforced by a **capability flow lint**.

```ferrule
function readAll(p: Path, cap fs: Fs) -> Bytes error IoError effects [fs] {
  const f = check fs.open(p);
  const bs = check fs.readAll(f);
  return ok bs;
}
```

---

## Higher-Order Functions with Effects

### Basic Pattern

```ferrule
function forEach<T>(items: View<T>, f: (T) -> Unit effects F) -> Unit effects [...F] {
  for item in items {
    f(item);
  }
}
```

### With Capabilities

Thread capabilities explicitly:

```ferrule
function mapWithCap<T, U, C>(
  arr: View<T>, 
  f: (T, cap c: C) -> U,
  cap c: C
) -> View<U> effects [alloc] {
  // pass capability to each invocation
}

function processFiles(paths: View<Path>, cap fs: Fs) -> View<String> error IoError effects [fs, alloc] {
  return mapWithCap(paths, function(p: Path, cap fs: Fs) -> String {
    return check fs.readAllText(p);
  }, fs);
}
```

---

## Effect-Parametric Helpers

Push effectful edges out for pure, composable helpers:

```ferrule
// pure: works with any call site
function mapOk<T, U, E>(r: Result<T, E>, f: (T) -> U) -> Result<U, E> {
  match r { 
    ok v  -> ok f(v); 
    err e -> err e;
  }
}
```

---

## Purity

A **pure function** has:
- No error clause
- No effects declaration (or empty `effects []`)

```ferrule
function add(x: i32, y: i32) -> i32 {
  return x + y;
}
```

Functions with `error E` clauses are **not pure**, even without explicit effects.

---

## Determinism & Testing

- **Deterministic mode** swaps schedulers and stubs capabilities (`Clock`, `Rng`)
- Effect usage that introduces nondeterminism must route through capabilities

See [../concurrency/determinism.md](../concurrency/determinism.md).

---

## Summary

| Syntax | Meaning |
|--------|---------|
| `effects [fs, net]` | Function has fs and net effects |
| `effects [alloc, ...]` | Has alloc plus spread from parameters |
| `effects [...F]` | Has all effects from F |
| `where F includes [time]` | F must contain time |
| No `effects` clause | Pure (within module) or error if public |
