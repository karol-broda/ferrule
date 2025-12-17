# Capabilities

> **scope:** capability parameters, flow analysis, no ambient authority  
> **related:** [imports.md](imports.md) | [../functions/effects.md](../functions/effects.md)

---

## Overview

Ferrule has **no ambient authority**. File system, network, clock, and RNG access are **values you pass**, not globals you access.

---

## Capability Parameters

Mark capability parameters with `cap`:

```ferrule
function save(path: Path, data: View<u8>, cap fs: Fs) -> Unit error IoError effects [fs] {
  return check fs.write_all(path, data);
}
```

The `cap` keyword:
- marks a parameter as a capability
- enables tools to track/verify capability flows
- makes authority explicit in function signatures

---

## No Ambient Authority

Functions cannot access capabilities without receiving them:

```ferrule
// WRONG: where does fs come from?
function read_config() -> Config effects [fs] {
  return fs.read_all("config.json");  // ERROR: fs not in scope
}

// CORRECT: fs is passed explicitly
function read_config(cap fs: Fs) -> Config error IoError effects [fs] {
  return check fs.read_all("config.json");
}
```

---

## Capability Flow Lint

Static rule: if a function lists an effect (e.g., `fs`) in its effects, it must either:

1. take at least one corresponding `cap` parameter, or
2. call another function that takes such a parameter

Violations are flagged by the capability flow lint.

---

## Standard Capabilities

| Capability | Effect | Purpose |
|------------|--------|---------|
| `Fs` | `fs` | file system operations |
| `Net` | `net` | network operations |
| `Clock` | `time` | time access, sleep |
| `Rng` | `rng` | randomness |

---

## Capability Threading

For higher-order functions, thread capabilities explicitly:

```ferrule
function map_with_cap<T, U, C>(
  arr: View<T>, 
  f: (T, cap c: C) -> U, 
  cap c: C
) -> View<U> effects [alloc] {
  // passes capability to each invocation of f
}

function process_files(paths: View<Path>, cap fs: Fs) -> View<String> error IoError effects [fs, alloc] {
  return map_with_cap(paths, (p, cap fs: Fs) => {
    return check fs.read_all_text(p);
  }, fs);
}
```

---

## Testing with Capabilities

Capabilities enable deterministic testing by injecting stubs:

```ferrule
function test_with_mock_time() {
  const mock_clock = testing.mock_clock(start = 1000);
  
  // function under test receives mock capability
  const result = timeout_operation(cap clock = mock_clock);
  
  // advance time deterministically
  mock_clock.advance(500);
}
```

See [../concurrency/determinism.md](../concurrency/determinism.md).

---

## Entry Point

The program entry point receives capabilities from the runtime:

```ferrule
function main(cap fs: Fs, cap net: Net, cap clock: Clock) -> Unit error AppError effects [fs, net, time] {
  // all authority flows from here
}
```

---

## Example: Capability Scoping

```ferrule
function process_request(
  request: Request,
  cap fs: Fs,
  cap net: Net,
  cap clock: Clock
) -> Response error AppError effects [fs, net, time] {
  
  // read config (needs fs)
  const config = check read_config(fs);
  
  // fetch external data (needs net, clock for timeout)
  const data = check fetch_with_timeout(request.url, clock, net);
  
  // write result (needs fs)
  check write_response(request.id, data, fs);
  
  return ok Response { status: 200 };
}
```


