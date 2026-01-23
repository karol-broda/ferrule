---
title: ferrule language specification
version: α1
status: draft
last_updated: 2026-01-22
---

# ferrule language specification

this is the specification for ferrule α1. it describes what the language is and what it will be. each document has front matter that tells you what's implemented, what's planned, and what's been deferred to future versions.

the spec is the single source of truth. if something isn't in here, it's not part of the language yet.

## how to read this

each document has yaml front matter at the top:

```yaml
---
title: some feature
status: α1          # α1, α2, β, or rfc
implemented:        # sections that work right now
  - basic-stuff
  - other-thing
pending:            # sections planned for this phase
  - advanced-stuff
deferred:           # pushed to later phase or rfc
  - complex-thing
---
```

status meanings:
- `α1` means it's part of the current milestone
- `α2` means next milestone
- `β` means later
- `rfc` means it's a proposal, not committed

conventions:
- `code` for syntax and identifiers
- `[link](path)` references the canonical definition
- examples are runnable unless marked otherwise

## design pillars

these are the core ideas that guide decisions:

1. **immutability first** - `const` by default, `var` when you need mutation, `inout` for explicit by-reference
2. **errors as values** - no exceptions, typed error domains, lightweight propagation
3. **explicit effects** - functions declare what they do, async is just another effect
4. **scoped ownership** - views can't escape their scope, no borrow checker, no gc
5. **capability security** - no ambient authority, fs/net/clock/rng are values you pass
6. **strict nominal types** - types with the same shape aren't compatible
7. **no implicit coercions** - booleans, numbers, nullability all explicit
8. **explicit polymorphism** - records + generics, no traits or oop

## what's in α1

the core language that you can actually use:

| feature | status |
|---------|--------|
| primitives (i8-i128, u8-u128, f32/f64, bool, char, string) | implemented |
| records and discriminated unions | implemented |
| pattern matching with exhaustiveness | implemented |
| basic generics (monomorphization) | partial |
| error handling (ok/err/check/ensure) | implemented |
| effects (declaration, subset rule) | partial |
| move semantics | planned |
| capabilities (with cap syntax) | planned |
| unsafe blocks | planned |
| basic stdlib | partial |

## what's deferred

these features are designed but not part of α1:

| feature | target | notes |
|---------|--------|-------|
| regions (heap, arena) | α2 | memory allocation model |
| views (fat pointers) | α2 | with escape analysis |
| capability attenuation | α2 | restrict, compose |
| comptime | α2 | compile-time evaluation |
| test framework | α2 | test blocks, ferrule test |
| structured concurrency | β | task.scope, spawn, await |
| async (suspend effect) | β | effect-based, pluggable runtimes |
| hkt | rfc | [higher-kinded types](/rfcs/0005-higher-kinded-types) |
| mapped types | rfc | [type transformation](/rfcs/0006-mapped-types) |
| conditional types | rfc | planned |
| variadic generics | rfc | planned |

> **looking for future features?** check out the [rfcs](/rfcs) for proposed additions to the language.

## specification index

### core language

| document | scope |
|----------|-------|
| [core/lexical](./core/lexical.md) | source encoding, identifiers, keywords, comments |
| [core/types](./core/types.md) | scalars, compounds, unions, nominal typing |
| [core/declarations](./core/declarations.md) | const, var, inout, move semantics |
| [core/control-flow](./core/control-flow.md) | if, match, for, while, break, continue |
| [core/generics](./core/generics.md) | type parameters, constraints |

### functions and effects

| document | scope |
|----------|-------|
| [functions/syntax](./functions/syntax.md) | function declaration |
| [functions/effects](./functions/effects.md) | effect system, standard effects |

### error handling

| document | scope |
|----------|-------|
| [errors/domains](./errors/domains.md) | error types, domains as unions |
| [errors/propagation](./errors/propagation.md) | ok, err, check, ensure |

### memory model

| document | scope |
|----------|-------|
| [memory/ownership](./memory/ownership.md) | move semantics, copy vs move |
| [memory/regions](./memory/regions.md) | region kinds, creation, disposal |
| [memory/views](./memory/views.md) | view formation, slicing, bounds |

### modules and capabilities

| document | scope |
|----------|-------|
| [modules/packages](./modules/packages.md) | package structure, deps.fe |
| [modules/imports](./modules/imports.md) | import syntax |
| [modules/capabilities](./modules/capabilities.md) | capability parameters, with cap syntax |

### unsafe

| document | scope |
|----------|-------|
| [unsafe/blocks](./unsafe/blocks.md) | raw pointers, extern calls |

### concurrency (β)

| document | scope |
|----------|-------|
| [concurrency/tasks](./concurrency/tasks.md) | task.scope, spawn, await |
| [concurrency/determinism](./concurrency/determinism.md) | test schedulers |

### advanced (α2+)

| document | scope |
|----------|-------|
| [advanced/comptime](./advanced/comptime.md) | comptime functions, reflection |
| [advanced/ffi](./advanced/ffi.md) | c abi, extern |

### reference

| document | scope |
|----------|-------|
| [reference/grammar](./reference/grammar.md) | complete ebnf grammar |
| [reference/keywords](./reference/keywords.md) | reserved words |
| [reference/stdlib](./reference/stdlib.md) | standard library surface |

## key decisions

these are the choices that define ferrule:

| topic | decision |
|-------|----------|
| equality | single `==` operator, no `===` |
| functions | `function` keyword for all, no arrows, no `fn` |
| polymorphism | records + generics, `impl`/`derive` sugar in α2 |
| memory | scoped ownership + move semantics, no borrow checker |
| capabilities | linear, can't store/return, with cap syntax for main |
| effects | separate from capabilities, subset rule enforced |
| errors | error types, domains as unions, context frames debug-only |
| inference | unambiguous literals ok, boundaries need annotation |
| unsafe | blocks enable raw pointers/extern, don't disable other checks |

## to be defined

these decisions are still open:

| topic | options |
|-------|---------|
| integer overflow | wrap in release, trap in debug (zig-style) |
| division by zero | trap |
| out of bounds | trap in debug, undefined in release |
| error recovery | how many errors before bail, cascading strategy |

## language identity

ferrule is a systems language where effects and capabilities are first-class. you get low-level control with safety guarantees about what code can do, not just what memory it touches.

target users:
- embedded developers who want more safety than c
- security-critical systems where capability audit trails matter
- developers who want rust-style safety without fighting the borrow checker

what it's not:
- not rust (no borrow checker, simpler generics)
- not zig (effects and capabilities are language features)
- not go (no gc, explicit error handling)
