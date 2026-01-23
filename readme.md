# ferrule

<div align="center">

**a systems language where effects and capabilities are first-class**

α1

</div>

---

## what is ferrule?

ferrule is a low-level systems language where you get zig-level control with safety guarantees about *what code can do*, not just what memory it touches.

- **errors as values** — no exceptions, typed error domains, lightweight propagation
- **explicit effects** — functions declare what they can do (`fs`, `net`, `time`, etc.)
- **scoped ownership** — move semantics without a borrow checker
- **capability security** — no ambient authority; permissions are values you pass
- **strict nominal types** — no accidental structural compatibility

```ferrule
error NotFound { path: Path }
error Denied { path: Path }
type IoError = NotFound | Denied;

function readConfig(path: Path, cap fs: Fs) -> Config error IoError effects [fs] {
  const data = check fs.readAll(path);
  return ok parse(data);
}
```

---

## quick start

```bash
# create a new project
ferrule new my-app
cd my-app

# build and run
ferrule build
ferrule run
```

---

## documentation

| document | description |
|----------|-------------|
| [language specification](docs/spec/_index.md) | complete language reference |
| [package management](docs/package-management.md) | manifests, lockfiles, cli |

### specification index

**core language**
- [lexical structure](docs/spec/core/lexical.md) — encoding, identifiers, keywords
- [types](docs/spec/core/types.md) — scalars, unions, nominal typing
- [declarations](docs/spec/core/declarations.md) — `const`, `var`, `inout`, move semantics
- [control flow](docs/spec/core/control-flow.md) — `if`, `match`, loops
- [generics](docs/spec/core/generics.md) — type parameters, constraints

**functions and effects**
- [function syntax](docs/spec/functions/syntax.md) — `function` keyword for all
- [effects](docs/spec/functions/effects.md) — effect system, subset rule

**error handling**
- [error domains](docs/spec/errors/domains.md) — standalone errors, domains as unions
- [propagation](docs/spec/errors/propagation.md) — `check`, `ensure`

**memory**
- [ownership](docs/spec/memory/ownership.md) — move semantics, copy vs move
- [regions](docs/spec/memory/regions.md) — allocation, disposal (α2)
- [views](docs/spec/memory/views.md) — fat pointers, slicing (α2)

**modules**
- [packages](docs/spec/modules/packages.md) — deps.fe, project structure
- [imports](docs/spec/modules/imports.md) — resolution, visibility
- [capabilities](docs/spec/modules/capabilities.md) — `with cap` syntax, linear types

**unsafe**
- [unsafe blocks](docs/spec/unsafe/blocks.md) — raw pointers, extern calls

**reference**
- [grammar](docs/spec/reference/grammar.md) — ebnf
- [keywords](docs/spec/reference/keywords.md) — reserved words
- [operators](docs/spec/reference/operators.md) — precedence (`==` not `===`)
- [stdlib](docs/spec/reference/stdlib.md) — standard library

---

## design pillars

1. **immutability first** — `const` by default
2. **errors as values** — no exceptions
3. **explicit effects** — functions declare what they do
4. **scoped ownership** — move semantics, no borrow checker
5. **capability security** — no ambient authority
6. **strict nominal types** — no structural compatibility
7. **no implicit coercions** — explicit always
8. **explicit polymorphism** — records + generics, no traits

---

## example

```ferrule
package my.app;

import std.io { println };

error Timeout { ms: u64 }
error Network { message: String }
type AppError = Timeout | Network;

function main(args: Args) -> i32 
    with cap io: Io, cap net: Net, cap clock: Clock
{
    const deadline = clock.now() + Duration.seconds(30);
    
    match fetchWithRetry("https://api.example.com", deadline, net, clock) {
        ok resp => {
            println(resp.body, io);
            return 0;
        },
        err e => {
            println("request failed", io);
            return 1;
        }
    }
}

function fetchWithRetry(
    url: String, 
    deadline: Time, 
    cap net: Net, 
    cap clock: Clock
) -> Response error AppError effects [net, time] {
    var attempts: u32 = 0;
    
    while attempts < 3 {
        match net.get(url) {
            ok resp => return ok resp,
            err e => {
                attempts = attempts + 1;
                if attempts < 3 {
                    clock.sleep(Duration.seconds(1));
                }
            }
        }
    }
    
    return err Timeout { ms: 30000 };
}
```

---

## status

**α1** — language design is stabilizing. core features working, many planned features not yet implemented.

see the [specification](`docs/spec/_index.md`) for what's implemented vs planned.

---

## license

[apache 2.0](LICENSE)
