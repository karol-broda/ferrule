---
rfc: 0020
title: runtime specs
status: draft
created: 2026-01-24
target: α2
depends: []
---

# RFC-0020: runtime specs

## summary

runtime specs are record types that define what capabilities a runtime must provide. code declares what spec it requires, and the compiler verifies the target runtime satisfies it. this enables write-once-run-anywhere code while maintaining compile-time safety.

## motivation

ferrule targets multiple execution environments:

- native binaries (linux, macos, windows)
- webassembly (browser, cloudflare workers, deno deploy)
- embedded (no os, bare metal)

each environment provides different capabilities. native has full filesystem access; wasm in browsers has none. code that uses `fs.read_file()` cannot run on cloudflare workers.

without runtime specs, this is a runtime error or silent failure. with runtime specs, it's a compile-time error:

```
error: runtime does not satisfy constraint
  ┌─ src/main.fe:1:1
  │
1 │ function main() with runtime: Full {
  │                               ^^^^
  │
  = note: target 'cloudflare-workers' provides Server
  = note: your code requires Full (needs Fs)
```

## detailed design

### runtime specs as types

a runtime spec is a record type that bundles capabilities:

```ferrule
/// minimal runtime - scripts, cli tools, pure computation
pub type Minimal = {
    io: Io,
    clock: Clock,
    rng: Rng,
};

/// server runtime - http servers, apis, network services
pub type Server = Minimal & {
    net: Net,
};

/// full runtime - native apps with fs, env, process control
pub type Full = Server & {
    fs: Fs,
    env: Env,
    process: Process,
};

/// embedded runtime - bare metal, no os
pub type Embedded = {
    io: Io,      // might be uart
    clock: Clock,
    gpio: Gpio,  // hardware-specific
};
```

### declaring requirements

code declares what runtime spec it needs:

```ferrule
// requires server runtime
function main() -> Never with runtime: Server {
    http.serve("0.0.0.0", 8080, handler, runtime.net, runtime.io);
}

// requires full runtime
function main() -> i32 with runtime: Full {
    const config = runtime.fs.read_file("config.json");
    // ...
}
```

### custom specs

users define their own specs for specific needs:

```ferrule
type MyAppRuntime = Server & {
    db: DatabaseCapability,
    cache: CacheCapability,
};

function main() with runtime: MyAppRuntime {
    // has io, clock, rng, net (from Server)
    // plus db and cache
}
```

### target manifests

each compile target declares what spec it provides:

```ferrule
// in ferrule compiler or target definition
const target_linux_x86_64: Full = {
    io: LinuxIo,
    clock: LinuxClock,
    rng: LinuxRng,
    net: LinuxNet,
    fs: LinuxFs,
    env: LinuxEnv,
    process: LinuxProcess,
};

const target_cloudflare_workers: Server = {
    io: WorkersIo,
    clock: WorkersClock,
    rng: WorkersRng,
    net: WorkersNet,
};

const target_stm32f4: Embedded = {
    io: UartIo,
    clock: SysTickClock,
    gpio: Stm32Gpio,
};
```

### compile-time checking

the compiler verifies:

1. the target provides a type that satisfies the required spec
2. all capability accesses go through the runtime parameter
3. no ambient authority sneaks in

```ferrule
function main() with runtime: Server {
    runtime.fs.read_file("x");  // error: Server has no field 'fs'
}
```

### optional capabilities

use `Maybe` for optional capabilities:

```ferrule
type FlexibleRuntime = {
    io: Io,
    net: Net,
    fs: Maybe<Fs>,  // optional
};

function main() with runtime: FlexibleRuntime {
    match runtime.fs {
        Some(fs) => use_filesystem(fs),
        None => use_fallback(),
    }
}
```

### capability subsetting

specs can require subsets of capabilities:

```ferrule
// read-only fs
type ReadOnlyFs = {
    read_file: (Path) -> Bytes error FsError effects [fs],
    exists: (Path) -> Bool effects [fs],
    // no write_file, no delete
};

type SecureRuntime = Server & {
    fs: ReadOnlyFs,  // restricted fs
};
```

## drawbacks

- adds complexity to the type system
- runtime as a parameter is verbose
- could lead to spec proliferation

## alternatives

### tier numbers

use numeric tiers (tier 1, tier 2, tier 3) instead of types.

rejected: not composable, not extensible, arbitrary ordering.

### capability checks at call sites

check each capability individually:

```ferrule
function main() with cap io: Io, cap net: Net, cap fs: Fs { ... }
```

this works but doesn't compose. you can't say "i need whatever Server provides" without listing every capability.

### no compile-time checking

let runtime errors happen.

rejected: defeats the purpose of a typed language.

## prior art

| system | approach |
|--------|----------|
| wintercg/wintertc | minimum common web platform api |
| rust cfg | conditional compilation per target |
| go build tags | file-level target selection |
| zig | comptime target checks |

wintercg is closest to this proposal. the difference: ferrule specs are types, not documentation.

## unresolved questions

1. how to handle gradual capability addition (runtime might add fs later)?
2. should specs be structural or nominal?
3. how to version specs as capabilities evolve?

## future possibilities

- capability attenuation: `runtime.fs.restrict({ write: false })`
- capability delegation: pass subsets to untrusted code
- runtime negotiation: "give me the best you have"
- wasm component model integration
