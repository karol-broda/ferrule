---
title: error propagation
status: α1
implemented:
  - ok-construction
  - err-construction
  - check-propagation
pending:
  - ensure-guards
  - check-with-context
deferred:
  - map_error (α2)
  - context-ledgers (α2)
---

# error propagation

ferrule provides lightweight sugar for working with `Result<T, E>`. all error handling is explicit. no hidden control flow, no exceptions.

## construction

### ok

wrap a success value:

```ferrule
return ok data;
```

only valid in functions with `error E` clause.

### err

construct an error:

```ferrule
return err NotFound { path: p };
```

only valid in functions with `error E` clause. using `ok` or `err` without an error clause is a compile error.

## propagation

### check

unwrap a Result or return the error immediately:

```ferrule
const file = check fs.open(p);
```

if `fs.open` returns err, check returns it from the current function. if it returns ok, check unwraps the value.

this is the workhorse of error handling. it's like rust's `?` but more explicit.

### check with context

add context frames when propagating:

```ferrule
const file = check fs.open(p) with { op: "open", path: p };
```

context frames attach key/value pairs to the error for debugging. useful for understanding where errors came from.

> **note (α1):** context frames are debug-only in α1. they're stripped in release builds. the syntax is available but context is only attached in debug mode. full context ledgers are α2.

## guards

### ensure

guard pattern for early error return:

```ferrule
ensure port >= 1 && port <= 65535 else err Invalid { message: "port out of range" };
ensure capability.granted(fs) == true else err Denied { path: p };
```

if the condition is false, the error is returned. this replaces the pattern:

```ferrule
if port < 1 || port > 65535 {
    return err Invalid { message: "port out of range" };
}
```

## complete example

```ferrule
use error IoError;

function read_file(p: Path, cap fs: Fs) -> Bytes error IoError effects [fs] {
    ensure capability.granted(fs) == true else err Denied { path: p };

  const file = check fs.open(p) with { op: "open" };
  const data = check fs.read_all(file) with { op: "read_all" };

  return ok data;
}
```

## what's planned

**map_error** (α2) for adapting error domains:

```ferrule
const bytes = map_error read_file(p) using (e => ClientError.File { cause: e });
```

this lets you convert between error domains while preserving context.

**context ledgers** (α2) for request-scoped context:

```ferrule
with context { request_id: rid, user_id: uid } in {
  const resp = fetch(url, deadline);
    // all errors inside this block have request_id and user_id attached
}
```

ledgers automatically attach to all `err`/`check` within the scope.

## summary

| syntax | purpose |
|--------|---------|
| `ok value` | construct success |
| `err Variant { ... }` | construct error |
| `check expr` | unwrap or propagate |
| `check expr with { ... }` | unwrap or propagate with context |
| `ensure cond else err ...` | guard with early return |
