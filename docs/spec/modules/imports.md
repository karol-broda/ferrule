# Imports

> **scope:** import syntax, name resolution, content-addressed imports, derivation mutation  
> **related:** [packages.md](packages.md) | [capabilities.md](capabilities.md)

---

## Basic Import

Import by name (resolved via `Package.fe` manifest and `ferrule.lock`):

```ferrule
import time { Clock };
import mylib.http { get, post };
```

---

## Capability-Gated Imports

An import can declare that loading requires build-time capability permission:

```ferrule
import time { Clock } using capability time;
import mylib.http { get, post } using capability net;
```

This is **build-time** capability gating — the build tool must have permission `X` to load the import.

At **runtime**, capabilities are still passed explicitly as values (no ambient authority).

---

## Content-Addressed Imports

For critical dependencies, import by explicit content address:

```ferrule
import store://sha256:e1f4a3b2... { io as stdio } using capability fs;
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
import store://sha256:... { io as stdio };
```

---

## Selective Imports

Import specific items:

```ferrule
import net.http { get, post, Client };
```

Or import the module namespace:

```ferrule
import net.http;
// use as: http.get(...), http.Client, etc.
```

---

## Derivation Mutation

Imports can override derivation parameters, producing a different content address:

```ferrule
import stdlib { io } with { features: { simd: false } };
```

The `with { ... }` clause:
- modifies the imported package's build configuration
- creates a variant with a different content address
- the lockfile records both original and mutated addresses

---

## Example

```ferrule
package my.app;

// standard imports
import time { Clock } using capability time;
import net.http { Client, Response } using capability net;

// pinned critical dependency
import store://sha256:abc123... { crypto } using capability ffi;

// modified derivation
import stdlib { io } with { features: { debug: true } };
```


