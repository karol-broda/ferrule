---
title: imports
status: α1
implemented: []
pending:
  - basic-import
  - selective-import
deferred:
  - capability-gated-imports (α2)
  - content-addressed-imports (β)
  - derivation-mutation (β)
---

# imports

ferrule uses a rust-like module system. files are modules, directories with `mod.fe` are submodules.

## project structure

| file | purpose |
|------|---------|
| `Package.fe` | package manifest (like cargo.toml) |
| `ferrule.lock` | lockfile for dependencies |
| `src/main.fe` | binary entrypoint |
| `src/lib.fe` | library root (optional) |
| `src/parser/mod.fe` | submodule definition |
| `src/parser/lexer.fe` | file in submodule |
| `tests/*.fe` | test files |

directories with `mod.fe` become submodules. the module path matches the file path: `src/parser/lexer.fe` is `parser.lexer`.

## visibility

```ferrule
function helper() { }              // default: module-private
pub function process() { }         // public to package
pub export function api() { }      // public to everyone (lib.fe only)
```

## local imports

```ferrule
// from local modules
import parser { Parser, ParseError };  // from src/parser/mod.fe
import utils { helper };               // from src/utils.fe

// re-export
pub import lexer { Token };  // re-export from lexer.fe
```

---

## basic import

Import by name (resolved via `Package.fe` manifest and `ferrule.lock`):

```ferrule
import time { Duration };
import mylib.http { Client, Request };
```

---

## Capability-Gated Imports

An import can declare that loading requires build-time capability permission:

```ferrule
import time { Duration } using capability time;
import mylib.http { Client, Request } using capability net;
```

This is **build-time** capability gating — the build tool must have permission `X` to load the import.

At **runtime**, capabilities are still passed explicitly as values (no ambient authority).

---

## Content-Addressed Imports

For critical dependencies, import by explicit content address:

```ferrule
import store://sha256:e1f4a3b2... { BufferedWriter } using capability fs;
```

Direct hash imports:
- pin to exact versions
- bypass name resolution
- provide maximum reproducibility

---

## Import Resolution

Name-based imports are resolved:

1. Check `Package.fe` manifest for declared dependencies
2. Look up content address in `ferrule.lock`
3. Fetch from cache or registry
4. Verify content hash

---

## Aliasing

Rename imports with `as`:

```ferrule
import net.http { Client as HttpClient };
import store://sha256:... { Response as HttpResponse };
```

---

## Selective Imports

Import specific items:

```ferrule
import net.http { Client, Request, Response };
```

Or import the module namespace:

```ferrule
import net.http;
// use as: http.Client, http.Request, etc. (types only)
// operations like get/post are methods on the Net capability
```

---

## Derivation Mutation

Imports can override derivation parameters, producing a different content address:

```ferrule
import stdlib.collections { Vec } with { features: { simd: false } };
```

The `with { ... }` clause:
- modifies the imported package's build configuration
- creates a variant with a different content address
- the lockfile records both original and mutated addresses

---

## Example

```ferrule
package my.app;

// type imports (capabilities are received at runtime, not imported)
import time { Duration };
import net.http { Client, Response };

// pinned critical dependency
import store://sha256:abc123... { Crypto } using capability ffi;

// modified derivation
import stdlib.collections { Vec } with { features: { debug: true } };
```


