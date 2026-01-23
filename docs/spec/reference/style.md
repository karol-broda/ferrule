---
title: style and naming
status: α1
---

# style and naming guidelines

---

## Naming Conventions

### Types, Domains, Roles

Use `PascalCase`:

```ferrule
type HttpClient = { ... };
domain IoError { ... }
role Hashable;
```

### Variables, Functions, Fields

Use `camelCase`:

```ferrule
const requestId = generateId();
function readFile(path: Path) -> Bytes { ... }
type User = { firstName: String, lastName: String };
```

### Constants

Use `camelCase` or `SCREAMING_SNAKE_CASE` consistently project-wide:

```ferrule
const maxRetries = 3;
const DEFAULT_TIMEOUT = Duration.seconds(30);
```

### Packages

Use lowercase dot-separated names:

```ferrule
package net.http;
package data.json;
package my.app.server;
```

---

## Formatting

### Indentation

Use 2 spaces (no tabs):

```ferrule
function process(x: i32) -> i32 {
  if x > 0 {
    return x * 2;
  } else {
    return 0;
  }
}
```

### Line Length

Prefer lines under 100 characters. Break long expressions:

```ferrule
const result = very_long_function_name(
  first_argument,
  second_argument,
  third_argument
);
```

### Braces

Opening brace on same line:

```ferrule
function foo() -> Unit {
  // ...
}

if condition {
  // ...
} else {
  // ...
}
```

---

## Code Organization

### Avoid Deep Nesting

Use early returns and `ensure`:

```ferrule
// PREFER
function process(input: Input) -> Output error ProcessError {
  ensure input.valid === true else err InvalidInput { ... };
  ensure input.size < MAX_SIZE else err TooLarge { ... };
  
  // main logic at low nesting level
  return ok transform(input);
}

// AVOID
function process(input: Input) -> Output error ProcessError {
  if input.valid === true {
    if input.size < MAX_SIZE {
      // deeply nested
      return ok transform(input);
    } else {
      return err TooLarge { ... };
    }
  } else {
    return err InvalidInput { ... };
  }
}
```

### Small, Focused Functions

Break large functions into smaller helpers:

```ferrule
function processRequest(req: Request) -> Response error AppError effects [fs, net] {
  const config = check loadConfig(fs);
  const data = check fetchData(req.url, net);
  const result = check transform(data, config);
  return ok formatResponse(result);
}
```

### Pure Helpers

Keep effectful edges thin; push pure logic into helpers:

```ferrule
// pure: easy to test, easy to reason about
function validatePort(n: u32) -> Bool {
  return n >= 1 && n <= 65535;
}

// effectful: thin wrapper
function readPort(path: Path, cap fs: Fs) -> Port error ConfigError effects [fs] {
  const text = check fs.read_all_text(path);
  const n = check number.parse_u32(text);
  ensure validatePort(n) === true else err InvalidPort { value: n };
  return ok Port(n);
}
```

---

## Comments

### Principles

- comments must add value
- prefer clear code over explanatory comments
- don't write filler comments

### Good Comments

```ferrule
// handles the edge case where the buffer wraps around
const effective_len = if end > start { end - start } else { capacity - start + end };

// SAFETY: pointer is valid because we just allocated it above
const view = view.from_raw_unchecked(ptr, len);
```

### Bad Comments

```ferrule
// increment counter
counter = counter + 1;

// check if x is greater than 10
if x > 10 { ... }
```

### Documentation Comments

```ferrule
/// parses a port number from a string
/// 
/// returns ParseError if the string is not a valid number
/// or if the number is outside the valid port range (1-65535)
function parsePort(s: String) -> Port error ParseError { ... }
```

---

## Security Guidelines

### Input Validation

Validate at boundaries:

```ferrule
function handleRequest(raw: Bytes) -> Response error AppError {
  const request = check parseRequest(raw);  // validate structure
  ensure request.size < MAX_REQUEST_SIZE else err TooLarge { ... };
  ensure isAllowedPath(request.path) === true else err Forbidden { ... };
  // ...
}
```

### No Hardcoded Secrets

Pass secrets via capabilities or configuration:

```ferrule
// WRONG
const API_KEY = "sk-12345...";

// CORRECT
function callApi(cap secrets: Secrets) -> Response effects [net] {
  const key = secrets.get("API_KEY");
  // ...
}
```

### Use Refinements for Invariants

```ferrule
type Port = u16 where self >= 1 && self <= 65535;
type Email = String where text.contains(self, "@");
```

### Secure Memory Handling

```ferrule
function processSecret(secret: View<u8>) -> Hash effects [alloc] {
  const hash = crypto.hash(secret);
  mem.secure_zero(secret);  // not optimized away
  return hash;
}
```

---

## Summary

| Element | Convention |
|---------|------------|
| types, domains, roles | `PascalCase` |
| variables, functions, fields | `camelCase` |
| constants | `camelCase` or `SCREAMING_SNAKE_CASE` |
| packages | `lowercase.dot.separated` |
| indentation | 2 spaces |
| braces | same line |


