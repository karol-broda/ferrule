# Ferrule Language Specification

> **version:** α1  
> **status:** draft  
> **design goal:** a low-level, modern systems language with explicit memory, strong nominal types, errors as values, structured concurrency, capability-based security

---

## How to Read This Spec

Each document in this specification is the **single source of truth** for its topic. Cross-references link to canonical definitions rather than duplicating content.

**Conventions:**
- `code` for syntax and identifiers
- **bold** for emphasis and key terms
- `[link](path)` references the canonical definition

---

## Design Pillars

1. **Immutability-first** — `const` by default; `var` for mutation; `inout` to pass by reference explicitly
2. **Errors as values** — no exceptions; typed error domains; lightweight propagation with automatic context frames
3. **Explicit effects** — every function declares an effect set; async is "colorless" and expressed via effects
4. **Regions & views** — clear memory lifetimes without garbage collection
5. **Capability security** — no ambient authority; fs/net/clock/rng are values you pass
6. **Content-addressed packages** — reproducible builds with provenance
7. **Strict nominal types** — no accidental structural compatibility; types must match exactly
8. **Determinism on demand** — structured concurrency, deterministic test scheduler, time/rng as capabilities
9. **No implicit coercions** — booleans, numbers, nullability all explicit
10. **Explicit polymorphism** — records + generics + explicit passing, no OOP

---

## Specification Index

### Core Language

| Document | Scope |
|----------|-------|
| [core/lexical.md](core/lexical.md) | source encoding, identifiers, keywords, comments |
| [core/types.md](core/types.md) | scalars, compounds, unions, refinements, nominal typing |
| [core/declarations.md](core/declarations.md) | `const`, `var`, `inout` bindings, inference rules |
| [core/control-flow.md](core/control-flow.md) | `if`, `match`, `for`, `while`, `break`, `continue` |
| [core/generics.md](core/generics.md) | type parameters, variance, conditional types, polymorphism |

### Functions & Effects

| Document | Scope |
|----------|-------|
| [functions/syntax.md](functions/syntax.md) | function declaration, `function` keyword for all |
| [functions/effects.md](functions/effects.md) | effect system, polymorphism, async suspension |

### Error Handling

| Document | Scope |
|----------|-------|
| [errors/domains.md](errors/domains.md) | standalone errors, domains, Pick/Omit, composition |
| [errors/propagation.md](errors/propagation.md) | `ok`, `err`, `check`, `ensure`, `map_error`, context frames |

### Memory Model

| Document | Scope |
|----------|-------|
| [memory/regions.md](memory/regions.md) | region kinds, creation, disposal, transfer |
| [memory/views.md](memory/views.md) | view formation, slicing, mutability, aliasing, bounds |
| [memory/capsules.md](memory/capsules.md) | unique resources, finalizers |

### Modules & Packages

| Document | Scope |
|----------|-------|
| [modules/packages.md](modules/packages.md) | deps.fe, build.fe, content addressing |
| [modules/imports.md](modules/imports.md) | import syntax, resolution |
| [modules/capabilities.md](modules/capabilities.md) | capability parameters, flow analysis |

### Concurrency

| Document | Scope |
|----------|-------|
| [concurrency/tasks.md](concurrency/tasks.md) | `task.scope`, `spawn`, `await_all`, cancellation |
| [concurrency/determinism.md](concurrency/determinism.md) | test schedulers, time/rng stubs |

### Advanced Features

| Document | Scope |
|----------|-------|
| [advanced/comptime.md](advanced/comptime.md) | `comptime` functions, typed transforms, reflection |
| [advanced/ffi.md](advanced/ffi.md) | C ABI, WASM component model |
| [advanced/asm.md](advanced/asm.md) | typed inline assembly |
| [advanced/performance.md](advanced/performance.md) | shapers, SIMD, prefetch hints |

### Reference

| Document | Scope |
|----------|-------|
| [reference/grammar.md](reference/grammar.md) | complete EBNF grammar |
| [reference/operators.md](reference/operators.md) | operator precedence (`==` not `===`) |
| [reference/keywords.md](reference/keywords.md) | reserved words (no `role`, `trait`, `impl`) |
| [reference/stdlib.md](reference/stdlib.md) | standard library surface |
| [reference/diagnostics.md](reference/diagnostics.md) | error messages, lints |
| [reference/style.md](reference/style.md) | naming, formatting guidelines |
| [reference/examples.md](reference/examples.md) | worked examples |
| [reference/checklist.md](reference/checklist.md) | α1 compliance checklist |

### Package Management

| Document | Scope |
|----------|-------|
| [../package-management.md](../package-management.md) | manifests, lockfiles, CLI, registry |

---

## Key Decisions (α1)

| Topic | Decision |
|-------|----------|
| Equality | Single `==` operator (no `===`) |
| Functions | `function` keyword for all (no arrows, no `fn`) |
| Polymorphism | Records + generics + explicit passing (no traits/roles) |
| Types | Strict nominal (no structural compatibility) |
| Dynamic | `unknown` type (no `any`) |
| Inference | Unambiguous literals OK, boundaries require annotation |
| Effects | Separate from types, spread syntax for polymorphism |
| Errors | Standalone `error` types, domains as unions, Pick/Omit |
| Packages | `deps.fe` (CLI-editable) + optional `build.fe` (code) |

---

## Version History

| Version | Status | Notes |
|---------|--------|-------|
| α1 | draft | initial specification |
