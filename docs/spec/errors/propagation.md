# Error Propagation

> **scope:** `ok`, `err`, `check`, `ensure`, `map_error`, context frames  
> **related:** [domains.md](domains.md) | [../functions/syntax.md](../functions/syntax.md)

---

## Overview

Ferrule provides lightweight sugar for working with `Result<T, E>` values. All error handling is explicit — no hidden control flow.

---

## Construction

### `ok value`

Wrap a success value in `Result`:

```ferrule
return ok data;
```

Only valid in functions with `error E` clause.

### `err Variant { ... }`

Construct an error:

```ferrule
return err NotFound { path: p };
```

Only valid in functions with `error E` clause.

> Using `ok` or `err` in a function without an `error E` clause is a compile error.

---

## Propagation

### `check expr`

Unwrap a `Result` or return the error immediately:

```ferrule
const file = check fs.open(p);
// if fs.open returns err, check returns it from the current function
// if fs.open returns ok, check unwraps the value
```

### `check expr with { frame... }`

Unwrap or return error, adding context frames:

```ferrule
const file = check fs.open(p) with { op: "open", path: p };
```

Context frames attach key/value pairs to the error for debugging.

---

## Guards

### `ensure condition else err Variant { ... }`

Guard pattern for early error return:

```ferrule
ensure capability.granted(fs) === true else err Denied { path: p };
ensure port >= 1 && port <= 65535 else err Invalid { message: "port out of range" };
```

---

## Domain Adaptation

### `map_error expr using (e => NewError)`

Adapt a foreign error domain while preserving context frames:

```ferrule
const bytes = map_error read_file(p) using (e => ClientError.File { cause: e });
```

The mapping function receives the original error and returns a new error in the current domain.

---

## Context Frames

Every `err` or `check ... with { ... }` attaches **key/value frames**:

```ferrule
check fs.read_all(file) with { 
  op: "read_all", 
  path: p,
  region: "us-east-1",
  request_id: rid 
};
```

Frames:
- flow across async boundaries automatically
- are preserved through `map_error`
- appear in error reports and logs

See [../concurrency/tasks.md](../concurrency/tasks.md) for async context propagation.

---

## Complete Example

```ferrule
use error IoError;

function read_file(p: Path, cap fs: Fs) -> Bytes error IoError effects [fs] {
  ensure capability.granted(fs) === true else err Denied { path: p };

  const file = check fs.open(p) with { op: "open" };
  const data = check fs.read_all(file) with { op: "read_all" };

  return ok data;
}
```

---

## Error Composition Example

```ferrule
domain ClientError { 
  File { cause: IoError } 
  | Parse { message: String } 
}

function load_config(p: Path, cap fs: Fs) -> Config error ClientError effects [fs] {
  const bytes = map_error read_file(p, fs) 
                using (e => ClientError.File { cause: e });
  
  return map_error parser.config(bytes) 
         using (e => ClientError.Parse { message: parser.explain(e) });
}
```

---

## Context Ledgers

For request-scoped context that flows through all error handling:

```ferrule
with context { request_id: rid, user_id: uid } in {
  const resp = fetch(url, deadline);
  match resp { 
    ok _  -> log.info("ok"); 
    err e -> log.warn("failed").with({ error: e });
  }
}
```

Ledgers:
- are immutable maps bound to a scope
- automatically attach to all `err`/`check` within the scope
- cross async boundaries without thread-locals

---

## Summary

| Syntax | Purpose |
|--------|---------|
| `ok value` | construct success |
| `err Variant { ... }` | construct error |
| `check expr` | unwrap or propagate |
| `check expr with { ... }` | unwrap or propagate with context |
| `ensure cond else err ...` | guard with early return |
| `map_error expr using (e => ...)` | adapt error domain |


