---
title: compliance checklist
status: α1
---

# α1 compliance checklist

---

## Core Language

- [ ] No exceptions or implicit panics
- [ ] `const` by default; `var` only when necessary
- [ ] Explicit `inout` for by-reference mutation
- [ ] Boolean conditions are explicit (`== true`, `!= false`)
- [ ] Explicit number casts (`u32(x)`, not implicit)
- [ ] No optional chaining; handle `T?` via `match` or explicit checks
- [ ] Single equality operator `==` (no `===`)
- [ ] No implicit type coercion

---

## Type System

- [ ] Strict nominal typing (no accidental structural compatibility)
- [ ] No `any` type; use `unknown` with explicit narrowing
- [ ] Explicit variance annotations (`in`/`out`) where needed
- [ ] Conditional types non-distributive by default
- [ ] Literal type preservation with `const`

---

## Functions

- [ ] `function` keyword for all functions (named, anonymous, inline)
- [ ] No arrow syntax (`=>`)
- [ ] No `fn` shorthand
- [ ] Function signatures always explicit (params, return, error, effects)

---

## Effects

- [ ] Functions declare `effects [...]` when performing side effects
- [ ] Public/ABI exports explicitly declare effects
- [ ] Effect subset rule enforced: called effects ⊆ caller effects
- [ ] Async suspension only with appropriate effects (`net`, `io`, `time`)
- [ ] Effect polymorphism via spread syntax (`...`)

---

## Errors

- [ ] Standalone `error` types declared outside domains
- [ ] Domains as unions of error types
- [ ] `Pick`/`Omit` for precise error subsets
- [ ] `error E` clause on fallible functions
- [ ] Public exports explicitly declare error domain
- [ ] `ok`/`err` only used in functions with `error E`
- [ ] Error values carry context frames
- [ ] Propagation uses `check`/`ensure`/`map_error`

---

## Polymorphism

- [ ] No `role`/`trait`/`protocol` keywords
- [ ] No `impl` blocks
- [ ] No method syntax (`x.method()`)
- [ ] No `self` keyword
- [ ] Operations defined as record types
- [ ] Implementations as namespaced constants (`Type.impl`)
- [ ] Explicit parameter passing for polymorphism

---

## Capabilities

- [ ] Capability parameters marked with `cap`
- [ ] Capabilities passed explicitly (no ambient authority)
- [ ] `fs` effect requires `Fs` capability
- [ ] `net` effect requires `Net` capability
- [ ] `time` effect requires `Clock` capability
- [ ] `rng` effect requires `Rng` capability

---

## Memory

- [ ] Regions explicitly created and disposed
- [ ] `defer region.dispose()` for cleanup
- [ ] Views carry region ID
- [ ] No reading uninitialized memory
- [ ] Mutable views have exclusive access
- [ ] Region transfer is explicit (`view.move`, `view.copy`)

---

## Packages

- [ ] `deps.fe` for dependencies (CLI-editable)
- [ ] `build.fe` for complex build logic (optional)
- [ ] Content addresses computed by tooling
- [ ] `ferrule.lock` committed for reproducibility
- [ ] Package capabilities declared and enforced

---

## Generics

- [ ] Explicit variance (`in`/`out`)
- [ ] Const generics for type-level values
- [ ] Conditional types with `infer`
- [ ] Non-distributive by default
- [ ] Variadic generics (`...Ts`)

---

## Style

- [ ] Types use `PascalCase`
- [ ] Variables/functions use `camelCase`
- [ ] Avoid deep nesting; use early returns
- [ ] Comments add value; no filler comments
- [ ] Input validation at boundaries
- [ ] No hardcoded secrets

---

## Tooling

- [ ] `deps.fe` is valid
- [ ] `ferrule.lock` is up to date
- [ ] All compiler errors resolved
- [ ] All warnings addressed or explicitly allowed
- [ ] Tests pass in deterministic mode

---

## Summary Table

| Feature | Status in α1 |
|---------|--------------|
| Core syntax | Stabilizing |
| Type system (nominal) | Stabilizing |
| Effect system | Stabilizing |
| Region/view | Stabilizing |
| Generics (advanced) | Feature-gated |
| C ABI | Stable |
| WASM components | Feature-gated |
| Inline assembly | Feature-gated |
