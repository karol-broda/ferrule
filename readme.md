# Ferrule

<div align="center">

**A modern systems language with explicit control**

α1 • alpha 1

</div>

---

## What is Ferrule?

Ferrule is a low-level systems language designed around **explicit control** and **predictable behavior**:

- **Errors as values** — no exceptions, typed error domains, lightweight propagation
- **Explicit effects** — functions declare what they can do (`fs`, `net`, `time`, etc.)
- **Regions & views** — deterministic memory without garbage collection
- **Capability security** — no ambient authority; permissions are values you pass
- **Strict nominal types** — no accidental structural compatibility
- **Content-addressed packages** — reproducible builds with provenance

```ferrule
error NotFound { path: Path }
error Denied { path: Path }
domain IoError = NotFound | Denied;

function readConfig(path: Path, cap fs: Fs) -> Config error IoError effects [fs] {
  const data = check fs.readAll(path) with { op: "readConfig" };
  return ok parse(data);
}
```

---

## Quick Start

```bash
# create a new project
ferrule new my-app
cd my-app

# build and run
ferrule build
ferrule run
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [Language Specification](docs/spec/_index.md) | Complete language reference |
| [Package Management](docs/package-management.md) | Manifests, lockfiles, CLI |

### Specification Index

**Core Language**
- [Lexical Structure](docs/spec/core/lexical.md) — encoding, identifiers, keywords
- [Types](docs/spec/core/types.md) — scalars, unions, refinements, nominal typing
- [Declarations](docs/spec/core/declarations.md) — `const`, `var`, `inout`, inference
- [Control Flow](docs/spec/core/control-flow.md) — `if`, `match`, loops
- [Generics](docs/spec/core/generics.md) — variance, conditional types, polymorphism

**Functions & Effects**
- [Function Syntax](docs/spec/functions/syntax.md) — `function` keyword for all
- [Effects](docs/spec/functions/effects.md) — effect system, polymorphism

**Error Handling**
- [Error Domains](docs/spec/errors/domains.md) — standalone errors, Pick/Omit
- [Propagation](docs/spec/errors/propagation.md) — `check`, `ensure`, `map_error`

**Memory**
- [Regions](docs/spec/memory/regions.md) — allocation, disposal, transfer
- [Views](docs/spec/memory/views.md) — fat pointers, slicing, aliasing
- [Capsules](docs/spec/memory/capsules.md) — unique resources

**Modules**
- [Packages](docs/spec/modules/packages.md) — deps.fe, content addressing
- [Imports](docs/spec/modules/imports.md) — resolution
- [Capabilities](docs/spec/modules/capabilities.md) — authority values

**Reference**
- [Grammar](docs/spec/reference/grammar.md) — EBNF
- [Operators](docs/spec/reference/operators.md) — precedence (`==` not `===`)
- [Examples](docs/spec/reference/examples.md) — worked examples

---

## Design Pillars

1. **Immutability-first** — `const` by default
2. **Errors as values** — no exceptions
3. **Explicit effects** — colorless async
4. **Regions & views** — no GC
5. **Capability security** — no ambient authority
6. **Strict nominal types** — no structural compatibility
7. **Content-addressed packages** — reproducible
8. **Determinism on demand** — test scheduling
9. **No implicit coercions** — explicit always
10. **Explicit polymorphism** — records + generics, no OOP

---

## Example

```ferrule
package my.app;

import net.http { Client } using capability net;
import time { Clock } using capability time;

error Timeout { ms: u64 }
error Network { message: String }
domain AppError = Timeout | Network;

// operation record for showing things
type Showable<T> = { show: (T) -> String };

const Response.show: Showable<Response> = {
  show: function(r: Response) -> String { return r.body; }
};

function main(cap net: Net, cap clock: Clock) -> Unit error AppError effects [net, time] {
  const deadline = clock.now() + Duration.seconds(30);
  const response = check fetchWithRetry("https://api.example.com", deadline, net, clock);
  
  io.println(Response.show.show(response));
  return ok Unit;
}

function fetchWithRetry(
  url: String, 
  deadline: Time, 
  cap net: Net, 
  cap clock: Clock
) -> Response error AppError effects [net, time] {
  var attempts: u32 = 0;
  
  while attempts < 3 {
    const result = net.get(url, cancel.token(deadline));
    
    match result {
      ok resp -> return ok resp;
      err e -> {
        attempts = attempts + 1;
        if attempts < 3 {
          clock.sleep(Duration.seconds(1));
        }
      }
    }
  }
  
  return err Timeout { ms: time.until(deadline) };
}
```

---

## Status

**α1 (Alpha 1)** — Language design is stabilizing. Syntax and semantics are subject to change.

---

## License

[Apache 2.0](LICENSE)
