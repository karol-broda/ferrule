# ferrule α1 — Language Specification (Draft)

<div align="center">

```
α1.1 • alpha 1 draft
```

</div>

> **status:** alpha 1 draft  
> **scope:** full surface syntax + semantics overview; developer experience and usage rules; no implementation details  
> **design goal:** a low-level, modern systems language with explicit memory, strong/expressive types, **errors as values**, structured concurrency, capability-based security

---

## 0. Design Pillars

> [!IMPORTANT]
> **Core Philosophy:** Explicit control, predictable behavior, zero-cost abstractions

1. **immutability-first** — `const` by default; `var` for mutation; `inout` to pass by reference explicitly.
2. **errors as values** — no exceptions; typed error domains; lightweight propagation (`ok`, `err`, `check`, `ensure`, `map_error`) with automatic **context frames**.
3. **explicit effects** — every function declares an **effect set** (e.g., `fs`, `net`, `time`); async is "colorless" and expressed via effects.
4. **regions & views** — clear memory lifetimes without borrow gymnastics; region-checked views with bounds.
5. **capability security** — no ambient authority; fs/net/clock/rng are values you pass.
6. **content-addressed packages** — derivations and provenance are part of the language.
7. **types you can trust** — closed unions, intersections, refinements, type-level naturals, mapped/conditional types (typescript-like power, layout-aware).
8. **determinism on demand** — structured concurrency, deterministic test scheduler, time/rng as capabilities.
9. **no implicit coercions** — booleans, numbers, nullability all explicit; no optional chaining.
10. **toolable by design** — stable abi (c/wasm), typed inline asm, comptime with strict purity, rich diagnostics.

---

## 1. Lexical Structure

- **source file encoding:** utf-8.
- **identifiers:** `[_A-Za-z][_0-9A-Za-z]*` (unicode letters allowed).
- **whitespace:** spaces, tabs, newlines; insignificant except in strings/comments.
- **comments:**

  - line: `// …`
  - block: `/* … */`

### 1.1 Keywords (reserved)

```
const, var, function, return, defer, inout, import, export, package,
type, role, domain, effects, capability, with, context,
match, if, else, for, while, break, continue,
comptime, derivation, use, error, as, where,
asm, component
```

> [!NOTE]
> Future-reserved: `trait`, `class`, `interface` (not used in α1).

---

## 2. Types & Values

### 2.1 Built-in Scalar Types

- signed: `i8 i16 i32 i64 i128`
- unsigned: `u8 u16 u32 u64 u128 usize`
- floats: `f16 f32 f64`
- other: `Bool`, `Char`, `String`, `Bytes`, `Unit` (zero-size)

### 2.2 Compound & Parametric Types

- **arrays:** `Array<T, n>` (fixed length)
- **vectors:** `Vector<T, n>` (simd-aware)
- **views (fat pointers):** `View<T>` and `View<mut T>` (ptr + len + region id)
- **records:** `{ field: Type, ... }`
- **closed unions (discriminated):**

  ```ferrule
  type ParseError = | InvalidByte { index: u32 } | Truncated { expected: u32, actual: u32 };
  ```

- **intersections:** `A & B` (structural protocols + nominal roles)
- **nullable:** postfix `?` (alias of `Maybe<T>`). requires explicit checks; no optional chaining.
- **refinements:** `type Port = u16 where self >= 1 && self <= 65535;`
- **type-level naturals:** `Nat` with arithmetic in bounds/shape expressions.
- **mapped / conditional:**

  ```ferrule
  type Readonly<T> = map T { K => { readonly: true, type: T[K] } };
  type Jsonable<T> = if T is (String | Number | Bool | Null | Array<Jsonable<any>> | Map<String, Jsonable<any>>) then T else Never;
  ```

### 2.3 Roles & Protocols

- **role** gives a nominal name to a structural contract:

  ```ferrule
  role Hashable;
  type Blob = { bytes: View<u8> } & Hashable;
  ```

---

## 3. Declarations & Bindings

### 3.1 Immutability, Mutation, References

```ferrule
const pageSize: usize = layout.page_size();

var counter: u32 = 0;
counter = counter + 1;

function bump(inout x: u32) -> Unit { x = x + 1; }

const buf: View<mut u8> = region.heap().alloc<u8>(4096);
defer region.heap().dispose(); // deterministic, non-throwing
```

- **default binding:** `const` (immutable).
- **mutation:** `var`.
- **by-reference:** `inout` parameters only. no hidden aliasing.

---

## 4. Functions & Effects

### 4.1 Function Form

```ferrule
function name(params...) -> ReturnType [error ErrorDomain]? effects [effect1, effect2, ...] { ... }
```

- **`function`** is the only declaration keyword in α1.
- **effects** enumerate potential side effects; absence means pure/suspend-free.
- **error** clause declares typed failure (see §6). If omitted and `use error` is in scope, the module default applies.

### 4.2 Effects (standard set in α1)

`alloc, cpu, fs, net, time, rng, atomics, simd, io, ffi`

- **rules:**

  - a function may only perform effects it declares.
  - async/suspension is permitted if an appropriate effect exists (`net`, `time`, `io`, etc.).
  - effects compose; callers are not “colored”.

---

## 5. Control Flow

### 5.1 Conditionals

```ferrule
if flag === true { ... } else { ... }        // explicit booleans only
```

- **no implicit truthiness.** comparisons use `===` / `!==` (strict).
- numerical comparisons use `< <= > >=`.

### 5.2 Loops

```ferrule
for x in xs { ... }
while n > 0 { ... }
break; continue;
```

### 5.3 Pattern Matching (Exhaustive)

```ferrule
match code {
  200 -> "ok";
  404 -> "not found";
  _   -> "unknown";
}
```

- unions must be **fully covered** or use `_`.

---

## 6. Errors as Values (Ergonomic, Typed)

### 6.1 Error Domains

```ferrule
domain IoError {
  NotFound    { path: Path }
  Denied      { path: Path }
  Interrupted { op: String }
}
```

- domains are versioned (by package address) and composable.

### 6.2 Fallible Functions (Signature)

- explicit: `-> T error E`
- module default: `use error E;` lets you omit `error E` in local signatures.
- **public/abi exports must be explicit** about `error E`.

### 6.3 Construction & Propagation Sugar

- `ok value` — wrap success.
- `err Variant { ... }` — construct error.
- `check expr [with { frame... }]` — unwrap or return error, optionally adding context.
- `ensure condition else err Variant { ... }` — guard pattern, early error.
- `map_error expr using (e => NewError)` — adapt foreign domain, preserving frames.

```ferrule
use error IoError;

function read_file(p: Path) -> Bytes error IoError effects [fs] {
  ensure capability.granted(fs) === true else err Denied { path: p };

  const file = check fs.open(p) with { op: "open" };
  const data = check fs.read_all(file) with { op: "read_all" };

  return ok data;
}
```

### 6.4 Context Frames

- every `err` / `check ... with { ... }` attaches **key/value frames** (e.g., `op`, `path`, `region`, `request_id`).
- frames flow across async boundaries automatically (see §12).

### 6.5 Error Composition

```ferrule
domain ClientError { File { cause: IoError } | Parse { message: String } }

function load_config(p: Path) -> Config error ClientError effects [fs] {
  const bytes = map_error read_file(p) using (e => ClientError.File { cause: e });
  return map_error parser.config(bytes) using (e => ClientError.Parse { message: parser.explain(e) });
}
```

---

## 7. Modules, Packages, & Imports

### 7.1 Package Header

```ferrule
// human name is a hint; address is content hash (source + derivation)
package net.http@sha256:2f7c…;
```

### 7.2 Imports & Capability Declarations

```ferrule
import time { Clock } using capability time;
import store://e1f4… { io as stdio } using capability fs;
```

- an `import ... using capability X;` declares that resolving this import requires ambient capability `X` during build/load.

### 7.3 Capability Values (No Ambient Authority)

Capabilities are runtime values passed explicitly:

```ferrule
function save(path: Path, data: View<u8>, cap fs: Fs) -> Unit error IoError effects [fs] {
  return check fs.write_all(path, data);
}
```

- **`cap`** marks a parameter as a capability; tools can track/verify capability flows.

---

## 8. Memory Model: Regions & Views

### 8.1 Regions

- **constructors:** `region.heap()`, `region.arena(bytes)`, `region.device(id)`, `region.shared()`
- **lifetime:** deterministic; `dispose()` returns a status event (non-throwing).
- **transfer:** explicit functions move objects/views between regions.

### 8.2 Views

- `View<T>` carries `(ptr, len, regionId)`.
- `View<mut T>` enables mutation of underlying storage.
- bounds are checked unless proven; proven bounds **erase** checks.

```ferrule
const arena = region.arena(1 << 20);
const buf: View<mut u8> = view.make<u8>(arena, count = 4096);
defer arena.dispose();
```

### 8.3 Capsules (Unique Resources)

- **capsule types** are non-copy by default; cloning requires an explicit duplicator provided by the type author.

---

## 9. Concurrency, Async, & Scheduling

### 9.1 Colorless Async via Effects

- suspensions are allowed when effects include `net`, `io`, or `time`.
- function shape is unchanged; `check/err` work the same.

```ferrule
function fetch(url: Url, deadline: Time) -> Response error ClientError effects [net, time] {
  const tok = cancel.token(deadline);
  const sock = map_error net.connect(url.host, url.port, tok)
               using (e => ClientError.Timeout { ms: time.until(deadline) });
  return check request(sock, url, tok) with { op: "request" };
}
```

### 9.2 Structured Concurrency

- **task scopes** create trees; cancellation tokens and deadlines are built-in; failure aggregation is explicit.

```ferrule
function get_many(urls: View<Url>, deadline: Time) -> View<Response> error ClientError effects [net, time, alloc] {
  return task.scope(scope => {
    const out = builder.new<Response>(region.current());

    for url in urls {
      const child = scope.spawn(fetch(url, deadline));
      scope.on_settle(child, (r) => {
        match r {
          ok v  -> builder.push(out, v);
          err e -> scope.fail(e); // policy chooses fail-fast or collect
        }
      });
    }

    check scope.await_all();
    return ok builder.finish(out);
  });
}
```

### 9.3 Deterministic Scheduler (Tests)

- test mode replaces schedulers with deterministic versions; time/rng are capabilities that tests can stub.

---

## 10. Compile-Time & Metaprogramming

### 10.1 Comptime Functions (Pure, Deterministic)

```ferrule
comptime function crc16_table(poly: u16) -> Array<u16, 256> { ... }
const CRC16 = comptime crc16_table(0x1021);
```

- no ambient io; memoized by arguments; results are cacheable.

### 10.2 Typed Transforms (Macro-like, Safe)

- operate on typed ir; output must pass all checks; used to generate ffi shims, serde codecs, cli parsers, wasm components.

### 10.3 Reflection (Layout Queries)

```ferrule
const page: usize = layout.page_size();
const alignOfBlob: usize = layout.alignof<Blob>();
```

---

## 11. Data-Oriented Performance

- **shapers:** declaratively convert AoS↔SoA for hot loops:

  ```ferrule
  shaper to_soa<T> { input: Array<T>, output: { fields: each T } }
  ```

- **simd/simt types:** `Vector<T,n>`, `Mask<n>`; fallback scalarization is explicit in diagnostics.
- **prefetch/cache hints:** portable intrinsics that degrade gracefully.

---

## 12. Context Ledgers

- a **context ledger** is an immutable map bound to a scope; all `err`/`check` attach it to error frames.

```ferrule
with context { request_id: rid, user_id: uid } in {
  const resp = fetch(url, deadline);
  match resp { ok _ -> log.info("ok"); err e -> log.warn("failed").with({ error: e }) }
}
```

- ledgers cross async boundaries without thread-locals.

---

## 13. Reproducible Builds & Derivations

### 13.1 Derivation Blocks

```ferrule
derivation stdlib {
  inputs {
    source   = hash("sha256:deaf…beef");
    compiler = tool("ferrulec", "1.0.0");
    sysroot  = tool("musl", "1.2.5");
  }
  params { target = "x86_64-linux-musl"; features = { simd: true, lto: "thin" } }
  policy { network = false; capabilities = ["fs"] }
}
```

- package addresses are the hash of **source + derivation**.
- imports may **mutate** derivations to produce new addresses:

```ferrule
import stdlib { io } with { features = { simd: false } };
```

- artifacts embed **provenance capsules** (compiler id, sysroot, flags).

---

## 14. Foreign Interfaces & Components

### 14.1 C ABI

```ferrule
export c function add(x: i32, y: i32) -> i32 { return x + y; }
import c function getenv(name: *u8) -> *u8;
```

- headers generated from types; calling conventions checked.

### 14.2 WASM Component Model

```ferrule
export wasm component interface {
  function http_get(url: String) -> Bytes error ClientError effects [net];
}
```

- interfaces are generated from type/effect signatures; versions tracked via package hashes.

### 14.3 Typed Inline Assembly

```ferrule
function rdtsc() -> u64 effects [cpu] {
  asm x86_64
    in  {}
    out { lo: u32 in rax, hi: u32 in rdx }
    clobber [rcx, rbx]
    volatile "rdtsc";
  return (u64(hi) << 32) | u64(lo);
}
```

---

## 15. Nullability & Interop

- `T?` is **explicit**; must be handled with `match` or comparisons.
- **no optional chaining**.
- ffi may return nullable pointers; convert to safe unions/errors before use.

```ferrule
const raw: *u8? = getenv(name);
if raw == null { return err NotFound { path: name_as_path(name) } }
```

---

## 16. Diagnostics & Lints (Developer Experience)

- **exhaustiveness checks** for `match`, error domains, and effect coverage.
- **no implicit boolean coercion**: `if value` is rejected; use `if value === true`.
- **no implicit numeric coercion**: conversions must be explicit (e.g., `u32(x)`).
- **region safety**: cross-region view misuse is flagged.
- **capability flow**: missing or unused `cap` parameters are flagged.
- **determinism mode**: bans nondeterministic effects unless explicitly annotated.

---

## 17. Standard Library (α1 Surface)

- **result sugar:** `ok`, `err`, `check`, `ensure`, `map_error`.
- **regions & views:** allocation, move, slice, bounds.
- **task:** `scope`, `spawn`, `await_all`, `on_settle`, `cancel.token`.
- **time, rng, net, fs:** capability interfaces (minimal).
- **layout:** sizeof/alignof/page size.
- **simd:** basic vector ops, masks, reductions.

> [!NOTE]
> Std apis return `ok/err` using the module's default error domain unless otherwise declared.

---

## 18. Style, Naming, and Security Guidelines

- **naming:**

  - types, domains, roles: `PascalCase` (`IoError`, `Blob`, `Hashable`)
  - variables, functions, fields: `camelCase` (`requestId`, `readFile`)
  - constants: `camelCase` or `SCREAMING_SNAKE` by convention, project-wide consistent.

- **comments:** concise, non-redundant.
- **avoid deep nesting:** use early `ensure` / `return`.
- **input validation:** validate at boundaries; use refinements for invariants.
- **no hardcoded secrets:** pass via capabilities or derivation parameters.
- **favor pure helpers:** small, composable functions; keep effectful edges thin.

---

## 19. Grammar (EBNF, Informative)

```ebnf
Identifier   := Letter { Letter | Digit | "_" }
Letter       := /* unicode letter or _ */
Digit        := "0"…"9"

Module       := PackageDecl { ImportDecl } { TopDecl }

PackageDecl  := "package" Identifier "@" Hash ";"
ImportDecl   := "import" ImportSource "{" ImportList "}" [ "using" "capability" Identifier ] ";"
ImportSource := Identifier | "store://" Hash
ImportList   := Identifier { "," Identifier } [ "as" Identifier ]

TopDecl      := TypeDecl | RoleDecl | DomainDecl | DerivationDecl | FunctionDecl | CapabilityDecl

TypeDecl     := "type" Identifier "=" TypeExpr ";"
RoleDecl     := "role" Identifier ";"
DomainDecl   := "domain" Identifier "{" Variant { Variant } "}"
Variant      := Identifier [ "{" FieldList "}" ]
FieldList    := Field { "," Field }
Field        := Identifier ":" TypeExpr

DerivationDecl := "derivation" Identifier "{" DerivationBody "}"
DerivationBody := "inputs" "{" KVList "}" "params" "{" KVList "}" "policy" "{" KVList "}"
KVList         := KVPair { "," KVPair }
KVPair         := Identifier "=" Expr

CapabilityDecl := "capability" Identifier ";"

FunctionDecl := "function" Identifier "(" ParamList? ")" "->" TypeExpr
                [ "error" Identifier ]
                [ "effects" "[" EffectList? "]" ]
                Block
ParamList    := Param { "," Param }
Param        := [ "cap" ] [ "inout" ] Identifier ":" TypeExpr
EffectList   := Identifier { "," Identifier }

Block        := "{" { Statement } "}"
Statement    := VarDecl | ConstDecl | If | While | For | Match | Return | Defer | Expr ";"

ConstDecl    := "const" Identifier ":" TypeExpr "=" Expr ";"
VarDecl      := "var"   Identifier ":" TypeExpr "=" Expr ";"
If           := "if" Expr Block [ "else" Block ]
While        := "while" Expr Block
For          := "for" Identifier "in" Expr Block
Match        := "match" Expr "{" Case { Case } "}"
Case         := Pattern "->" Expr ";"
Return       := "return" Expr ";"
Defer        := "defer" Expr ";"

TypeExpr     := SimpleType { TypeOp }
SimpleType   := Identifier
             | "{" FieldList "}"
             | "|" Identifier { "|" Identifier }
             | TypeExpr "&" TypeExpr
             | TypeExpr "where" Predicate
             | "Array" "<" TypeExpr "," NatExpr ">"
             | "Vector" "<" TypeExpr "," NatExpr ">"
             | "View" "<" [ "mut" ] TypeExpr ">"
             | TypeExpr "?"                /* nullable */

Expr         := Primary { Postfix | InfixOp Primary }
Primary      := Literal | Identifier | "(" Expr ")"
Postfix      := "(" ArgList? ")" | "." Identifier
ArgList      := Expr { "," Expr }

Literal      := Number | StringLit | BoolLit | BytesLit | "null"
```

> [!NOTE]
> This EBNF is illustrative and omits precedence tables (α1 toolchains should provide them with the parser).

---

## 20. Worked Examples (Concise)

### 20.1 Parsing with Refinements + Result Sugar

```ferrule
type Port = u16 where self >= 1 && self <= 65535;

domain ParseError { Invalid { message: String } }

use error ParseError;

function parse_port(s: String) -> Port error ParseError {
  const trimmed = text.trim(s);
  const n = number.parse_u16(trimmed);   // ok(u16) | err(ParseError)
  const v = check n with { op: "parse_u16" };
  if v < 1 || v > 65535 { return err Invalid { message: "out of range" } }
  return ok Port(v);
}
```

### 20.2 Files with Capabilities

```ferrule
domain IoError { NotFound { path: Path } | Denied { path: Path } }

function read_all(path: Path, cap fs: Fs) -> Bytes error IoError effects [fs] {
  const file = check fs.open(path);
  return check fs.read_all(file);
}
```

---

## 21. Compliance Checklist (α1)

- [ ] no exceptions or implicit panics
- [ ] `const` by default; `var` only when necessary
- [ ] explicit `inout` for by-ref mutation
- [ ] boolean conditions are explicit (`=== true`, `!== false`)
- [ ] explicit number casts (`u32(x)`, not implicit)
- [ ] no optional chaining; handle `T?` via `match` or explicit checks
- [ ] functions declare `effects [...]` and (at public boundaries) `error E`
- [ ] capability parameters marked with `cap` and passed explicitly
- [ ] imports are content-addressed; derivations specified for builds
- [ ] error values carry context frames; propagation uses `check/ensure`
- [ ] region/view usage is safe and validated by the compiler

---

## 22. Versioning & Stability (α1)

- **source stability:** identifiers and keywords above are **tentative** but intended to stabilize quickly.
- **binary stability:** c/wasm abi generation is defined by the exported signatures at the package’s content address.
- **feature gates:** `simd`, `asm`, `component`, and `typed transforms` may be behind gates in early toolchains.

---

## 23. Appendix: Operator Hints (Informative)

- arithmetic: `+ - * / %` (no implicit widen/narrow)
- bit ops: `& | ^ ~ << >>` (shifts require explicit cast to width)
- logic: `&& || !` (operands must be `Bool`)
- equality: `=== !==` (strict), value/shape-aware for scalars/records; unions compare tag + payload

---

# Ferrule α1.1 — Effects & Memory Addendum (Expanded Spec)

> **status:** alpha 1.1 draft  
> **scope:** expands **§4 Effects**, **§8 Regions & Views**, and **memory management** semantics across the spec. no implementation guidance—only developer-facing rules and language behavior.

> [!IMPORTANT]
> This addendum provides detailed semantics for effects and memory management. For the core language overview, see the sections above.

---

## 4. Effects — Detailed Semantics

### 4.0 Overview

- effects declare **what a function may do** (i/o, allocation, time, atomics, etc.).
- async suspension is allowed **only** if an appropriate effect is present.
- effects are **part of the function type** and propagate through calls.
- there are **no implicit effects**; absence of `effects [...]` means _pure, non-suspending_.

### 4.1 Standard Effects (α1 set)

| effect    | meaning (high level)                                           | typical capabilities |
| --------- | -------------------------------------------------------------- | -------------------- |
| `alloc`   | allocate/free memory in the current region or via an allocator | —                    |
| `fs`      | file system operations (open, read, write, stat)               | `Fs`                 |
| `net`     | networking (connect, send, receive)                            | `Net`                |
| `io`      | generic non-fs, non-net device i/o                             | device caps          |
| `time`    | access clocks, sleep, deadlines                                | `Clock`              |
| `rng`     | randomness                                                     | `Rng`                |
| `atomics` | atomic memory operations                                       | —                    |
| `simd`    | usage of simd intrinsics                                       | —                    |
| `cpu`     | privileged cpu instructions (rdtsc, cpuid, fences)             | —                    |
| `ffi`     | calls across foreign abis (c/wasm/other)                       | corresponding caps   |

> [!NOTE]
> Projects may add domain-specific effects (e.g., `gpu`, `db`) via tooling, but α1 compilers only _recognize_ the above for built-in linting.

### 4.2 Function Types with Effects

- **declaration form**

```ferrule
function f(x: T) -> U error E effects [fs, time] { ... }
```

- **type form (informative)**

```
(T) -> U error E effects [fs, time]
```

This type can be used for higher-order params:

```ferrule
function retry<T, E1, E2>(
  attempts: u32,
  op: (Unit) -> T error E1 effects [net, time],
  adapt: (E1) -> E2
) -> T error E2 effects [net, time] {
  var i: u32 = 0;
  while i < attempts {
    const r = op(());
    match r {
      ok v  -> return ok v;
      err e -> { i = i + 1; if i === attempts { return err adapt(e) } }
    }
  }
  return err adapt(/* unreachable sentinel by typing */);
}
```

- a function **cannot** call another function whose effect set is **not a subset** of its own.

### 4.3 Effect Subset Rule (Static)

For any call `g()` inside `f`:

$$\text{effects}(g) \subseteq \text{effects}(f)$$

If not satisfied, the compiler diagnoses with the missing effects.

### 4.4 Effect Inference (Local) & Explicitness (Public)

- **within a module**, the compiler may infer a function's effect set from its body when omitted.
- **public symbols** (exported from a package/module, or crossing c/wasm component boundaries) **must** spell their effect sets explicitly. toolchains reject exports with inferred effects.

### 4.5 Async Suspension

- a function may suspend **only if** `effects` includes one of: `net`, `io`, `time`, or a user-defined effect marked as _suspending_ by tooling.
- suspension points are recorded in debug capsules for profilers.

### 4.6 Capabilities vs Effects

- **effects** describe _what might happen_; **capabilities** are _authority values_ you must pass.
- static rule: if a function lists `fs` in its effects, it must either:

  - take at least one `cap Fs` parameter, or
  - call another function that takes such a parameter and does not capture ambient authority.

- this is enforced by a **capability flow lint**.

```ferrule
function read_all(p: Path, cap fs: Fs) -> Bytes error IoError effects [fs] {
  const f  = check fs.open(p);
  const bs = check fs.read_all(f);
  return ok bs;
}
```

### 4.7 Higher-Order Effects

- parameter function types carry their own effect sets.
- **composition rule**: caller's effects must include the **union** of any invoked parameter-function effects.

### 4.8 Effect Polymorphism (Informative)

α1 encourages **effect-parametric helpers** by pushing effectful edges out:

```ferrule
function map_ok<T, U, E>(r: Result<T, E>, f: (T) -> U) -> Result<U, E> {
  match r { ok v -> ok f(v); err e -> err e }
}
```

> [!TIP] > `map_ok` is pure; it composes with both pure and effectful call sites.

### 4.9 Determinism & Testing

- **deterministic mode** swaps schedulers and stubs capabilities (`Clock`, `Rng`) to repeat interleavings.
- effect usage that would introduce nondeterminism (e.g., `rng`) must route through the corresponding capability instance provided by tests.

---

## 8. Regions & Views — Transfer Rules & Safety

### 8.0 Overview

- **regions** group allocations under a single lifetime; disposing a region frees everything inside it deterministically.
- **views** are fat pointers `(ptr, len, regionId)` with optional mutability (`View<T>` vs `View<mut T>`).
- there is **no garbage collector**; safety is achieved via regions, views, and capsules.

### 8.1 Region Kinds (α1)

- `region.heap()` — general-purpose dynamic region.
- `region.arena(bytes)` — bump-ptr arena; individual frees are disallowed.
- `region.device(id)` — memory associated with a device (e.g., dma, gpu).
- `region.shared()` — multiple threads may access; requires `atomics` for mutation.

> [!NOTE]
> Regions are values; they can be passed, stored, and disposed. Disposing returns a **status event** (never throws).

```ferrule
const arena = region.arena(1 << 20);
const buf: View<mut u8> = view.make<u8>(arena, count = 4096);
defer arena.dispose();
```

### 8.2 Creation, Current Region, and Scope

- `region.current()` returns the region implicitly associated with the current lexical scope created by tooling (`task.scope`, test harnesses, etc.).
- α1 **does not** auto-nest regions; you explicitly pass regions to apis that allocate.

### 8.3 View Formation & Slicing

- forming a view records:

  - base pointer provenance
  - element count (len)
  - region id

- **slicing** yields a new view with the **same region id** and a sub-range of the original; bounds are validated.

```ferrule
const head: View<u8> = view.slice(buf, start = 0, count = 128);
```

### 8.4 Region Transfer (Reparenting)

- **move between regions** is explicit and **deep** for trivially movable types; it performs an element-wise copy and yields a new view bound to the destination region.

```ferrule
const dst = region.heap();
const moved: View<mut u8> = view.move(buf, to = dst);
```

- **rules**:

  1. moving **invalidates** the source view; using it after transfer is a compile-time error in most cases, or a runtime trap in dynamic paths.
  2. types with **external attachments** (file handles, device memory, host pointers) must define a `move_into(to: Region)` policy; if absent, moves are rejected.
  3. moving into `region.device` requires a device-visible layout; otherwise the operation is rejected or performed via a **layout adapter** that you specify explicitly.

### 8.5 Copy vs Move

- `view.copy(src, to)` performs a **copy** (source remains valid). availability depends on element type copyability.
- `view.move(src, to)` performs a **move** (source invalidated). works for any element type with a valid move policy.

### 8.6 Mutability & Aliasing

- `View<T>` — **read-only** access to the underlying memory. multiple aliases are allowed.
- `View<mut T>` — **mutable** access. **exclusive write** rule: a `View<mut T>` must not be used concurrently with any other view that overlaps the same range. α1 enforces:

  - **static checks** for obvious overlaps within a scope.
  - **debug assertions** (optional) for dynamic overlaps.

> [!WARNING]
> Data race violations are **undefined behavior** in release builds.

### 8.7 Shared Regions

- memory in `region.shared()` may be accessed from multiple tasks/threads. mutation requires:

  - `atomics` effect, and
  - atomic types or synchronization primitives from stdlib.

> [!WARNING]
> Non-atomic concurrent mutation of overlapping ranges is **undefined behavior**.

### 8.8 Disposal Semantics

- `region.dispose()`:

  - logically frees all allocations in the region;
  - runs deterministic **destructors** for capsule values registered with the region;
  - returns a **status event** (for tracing) but **never** throws or return an error value.

- disposing a region **invalidates** all views bound to it; further access traps.

```ferrule
const r = region.arena(1024);
defer r.dispose(); // status is recorded to the observability channel
```

### 8.9 Capsules (Unique Resources)

- capsule types are **non-copy** and **non-clone** unless the type author provides a duplicator.
- on region disposal, capsules receive a **finalize** call (cannot throw). failures are emitted as status events.

### 8.10 Pinning

- some operations (ffi, dma) require stable addresses. `view.pin(v)`:

  - prevents region compaction or movement for the view's range;
  - must be **unpinned** explicitly or by disposal;
  - pinning in `region.arena` is always allowed; pinning in moving/compacting regions (not in α1) would be rejected.

### 8.11 Layout & Alignment

- each type has machine layout: `size`, `align`, and (for unions) **niche** data.
- you may specify alignment/packing attributes at type definition time. misaligned raw loads/stores are rejected or lowered to safe sequences.

### 8.12 Uninitialized & Zeroing

> [!CAUTION]
> α1 forbids reading from uninitialized memory.

- allocation apis define zero-init policy explicitly:

  - `alloc_zeroed<T>(...)` returns zeroed memory.
  - `alloc_uninit<T>(...)` returns `View<Uninit<T>>`, which must be **fully initialized** via designated writes before transmuting to `View<T>`.

```ferrule
const un: View<Uninit<u32>> = region.heap().alloc_uninit<u32>(4);
// initialize...
const init: View<u32> = view.assume_init(un);  // only legal when fully initialized
```

### 8.13 Bounds & Provenance

- bounds checks on `View` access are inserted unless the compiler proves safety; checks in loops are **fused**.
- pointer provenance is preserved across view operations; casts that would break provenance are rejected unless done through `ffi` gates.

### 8.14 Device Regions & DMA

- `region.device(id)` exposes device memory. rules:

  - host access may be illegal; attempting to read/write without a device mapping yields a compile-time error or a runtime trap, depending on target.
  - transfers between host and device require explicit copy functions (`device.copy_to_host`, `host.copy_to_device`) that can report **err** values.

---

## 8.x Memory Management — General Semantics

### 8.x.1 No GC, Deterministic Lifetimes

- there is **no garbage collector**. all object lifetimes are either:

  - **lexical** via region disposal and `defer`, or
  - **explicit** via capsule finalizers.

### 8.x.2 Allocators & `alloc` Effect

- standard allocators operate **within a region**; invoking them requires the `alloc` effect.
- custom allocators can be passed as capabilities to further constrain policies (e.g., arenas that forbid free).

```ferrule
function grow_buffer(r: Region, want: usize) -> View<mut u8> effects [alloc] {
  return r.alloc_zeroed<u8>(want);
}
```

### 8.x.3 Builders & Bulk Construction

- the stdlib `builder<T>` lets you accumulate elements efficiently into a region without realloc thrash. all builder apis require `alloc`.

### 8.x.4 Constant-Time & Secret Data

- types may be annotated as **constant-time**; branches on their values are linted.
- secure zeroing (`mem.secure_zero`) is provided and **not** optimized away.

### 8.x.5 Interop with Raw Pointers

- raw pointers `*T` exist only at ffi/asm boundaries. immediately after crossing the boundary:

  - convert to `View<T>` or validate and wrap in capsule types;
  - or mark as tainted and restrict usage until validated.

- dereferencing a raw pointer requires the `ffi` effect and is restricted to dedicated apis.

### 8.x.6 Error Handling in Memory APIs

- memory apis returning fallible results use the module's error domain (or a dedicated one like `AllocError`).
- out-of-memory cases are **errors as values**, not panics, unless a project explicitly opts into abort-on-oom via derivation policy.

---

## 9. Concurrency & Scheduling — Clarifications Tied to Effects/Memory

### 9.1 Task Scopes & Region Lifetimes

- regions created **inside** a task scope are disposed when the scope exits (via `defer` or normal control flow).
- passing a region **out** of its creating scope is allowed, but then **you** own disposal. compilers warn if a region is never disposed.

### 9.2 Cancellation, Deadlines, and Memory

- aborted tasks must release their regions. finalizers run; status events are logged.
- `check` during cancellation attaches a `{ cancelled: true }` frame to the propagated error automatically.

### 9.3 Shared Region Races

- concurrent reads are allowed; concurrent writes require `atomics` or synchronization.

> [!WARNING]
> Data races on shared memory are **undefined behavior**; tests in deterministic mode can instrument to detect them.

---

## 4.y Worked Examples (Effects) — Concise

```ferrule
domain IoError { NotFound { path: Path } | Denied { path: Path } }
use error IoError;

// pure helper
function parse_u32(s: String) -> u32 error IoError {
  const n = number.parse_u32(s);
  return check n with { op: "parse_u32" };
}

// effectful wrapper
function read_and_parse(path: Path, cap fs: Fs) -> u32 error IoError effects [fs] {
  const data = check fs.read_all_text(path);
  return parse_u32(data);
}

// higher-order with effect subset enforcement
function with_timeout<T, E>(
  deadline: Time,
  op: (Unit) -> T error E effects [net, time]
) -> T error E effects [net, time] {
  return op(());
}
```

---

## 8.y Worked Examples (Region Transfer & Memory)

```ferrule
// move from arena to heap
function clone_to_heap(src: View<u8>) -> View<u8> effects [alloc] {
  const heap = region.heap();
  const dst  = view.copy(src, to = heap);
  defer heap.dispose(); // or return heap and let caller own lifetime
  return dst;
}

// pin for ffi call
function hash_in_place(buf: View<mut u8>) -> Unit effects [ffi] {
  const pin = view.pin(buf);
  defer view.unpin(pin);
  // call c function that writes into the pinned buffer
  const ok = crypto_c.hash_update(pin);
  if ok === false { /* handle error domain as needed */ }
}
```

---

## 8.z Formal-ish Rules (Informative)

**typing judgments (sketch)**

- values: $\Gamma \vdash e : T$
- effects: $\Gamma \vdash e : T \triangleright \varepsilon$ where $\varepsilon$ is a set of effects
- call: if $\Gamma \vdash f : (A) \to B\ \text{error}\ E \triangleright \varepsilon_f$ and $\Gamma \vdash a : A \triangleright \varepsilon_a$, then

  $$\Gamma \vdash f(a) : B\ \text{error}\ E \triangleright (\varepsilon_f \cup \varepsilon_a)$$

  and **require** $(\varepsilon_f \cup \varepsilon_a) \subseteq \varepsilon_{\text{context}}$

- region transfer: if $\Gamma \vdash v : \text{View}\langle T \rangle_r$, $\Gamma \vdash r' : \text{Region}$, and $\text{movable}(T, r \to r')$, then

  $$\Gamma \vdash \text{move}(v, r \to r') : \text{View}\langle T \rangle_{r'}$$

  and invalidate $v$.

**aliasing (informative)**

- for $\text{View}\langle\text{mut}\ T\rangle$ values $v_1$ and $v_2$ in region $r$ with ranges $[\text{lo}_1..\text{hi}_1]$ and $[\text{lo}_2..\text{hi}_2]$ used concurrently:

  - if intervals overlap, behavior is undefined unless all writes are atomic and $\text{atomics} \in \varepsilon_{\text{context}}$.
