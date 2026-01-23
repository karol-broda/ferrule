---
title: control flow
status: α1
implemented:
  - conditionals
  - for-loops
  - while-loops
  - break-continue
  - pattern-matching
  - exhaustiveness-checking
pending:
  - match-check
  - while-match
deferred:
  - const-match (α2)
---

# control flow

---

## Conditionals

```ferrule
if flag == true { ... } else { ... }
```

**Rules:**
- **No implicit truthiness** — conditions must be `Bool`
- Equality uses `==` / `!=` (single operator, no coercion)
- Numerical comparisons use `< <= > >=`

**Boolean literals:** `true` and `false` (lowercase)

### Invalid (Implicit Coercion)

```ferrule
// WRONG: implicit boolean coercion
if count { ... }

// CORRECT: explicit comparison
if count != null && count != 0 { ... }
```

---

## Loops

### For Loop

```ferrule
for x in xs { 
  // x is bound for each element
}
```

### While Loop

```ferrule
while n > 0 { 
  n = n - 1;
}
```

### Break and Continue

```ferrule
break;     // exit loop
continue;  // skip to next iteration
```

---

## Pattern Matching

Pattern matching is the primary mechanism for branching on discriminated unions and destructuring data. Ferrule's patterns integrate with the type system and error handling.

### Basic Match

```ferrule
match code {
  200 -> "ok";
  404 -> "not found";
  _   -> "unknown";
}
```

Match is an **expression** — it produces a value:

```ferrule
const message: String = match code {
  200 -> "success";
  404 -> "not found";
  _   -> "error";
};
```

---

## Pattern Kinds

### Wildcard

`_` matches any value without binding:

```ferrule
match value {
  _ -> handle_any();
}
```

### Literals

Match exact values — integers, strings, booleans, `null`:

```ferrule
match n {
  0 -> "zero";
  1 -> "one";
  _ -> "other";
}

match flag {
  true  -> enabled();
  false -> disabled();
}

match maybe_value {
  null -> handle_missing();
  _    -> handle_present();
}
```

### Bindings

Bind the matched value to a name:

```ferrule
match code {
  n -> log("code was", n);
}
```

### Ranges

Match value ranges with `..` (exclusive) or `..=` (inclusive):

```ferrule
match score {
  0..60    -> "F";
  60..70   -> "D";
  70..80   -> "C";
  80..90   -> "B";
  90..=100 -> "A";
  _        -> "invalid";
}
```

Works with integers and characters:

```ferrule
match c {
  'a'..='z' -> "lowercase";
  'A'..='Z' -> "uppercase";
  '0'..='9' -> "digit";
  _         -> "other";
}
```

### Alternatives

Match multiple patterns with `|` (mirrors union type syntax):

```ferrule
match day {
  "saturday" | "sunday" -> "weekend";
  _ -> "weekday";
}

match code {
  200 | 201 | 204 -> "success";
  400 | 404 | 422 -> "client error";
  _               -> "other";
}
```

### Variant Destructuring

Destructure discriminated unions — the core use case:

```ferrule
type Shape = 
  | Circle { radius: f64 } 
  | Rect { width: f64, height: f64 };

match shape {
  Circle { radius } -> pi * radius * radius;
  Rect { width, height } -> width * height;
}
```

### Result Patterns

Pattern matching integrates with `Result<T, E>`:

```ferrule
match result {
  ok { value }  -> process(value);
  err { error } -> log.error(error);
}
```

### Maybe Patterns

Match `Maybe<T>` (`T?`) values:

```ferrule
match maybe_user {
  Some { value } -> greet(value.name);
  None           -> greet_stranger();
}
```

Since `null` is sugar for `None`:

```ferrule
const user: User? = lookup(id);

match user {
  null -> return err NotFound {};
  u    -> process(u);
}
```

### Record Destructuring

Match and destructure records inline:

```ferrule
type Point = { x: i32, y: i32 };

match point {
  { x: 0, y: 0 } -> "origin";
  { x: 0, y }    -> format("y-axis at {}", y);
  { x, y: 0 }    -> format("x-axis at {}", x);
  { x, y }       -> format("({}, {})", x, y);
}
```

Use `..` to ignore remaining fields:

```ferrule
match user {
  { name: "admin", .. } -> grant_admin();
  { name, email, .. }   -> send_welcome(name, email);
}
```

### Array Patterns

Match array structure:

```ferrule
match items {
  []              -> "empty";
  [single]        -> format("one: {}", single);
  [first, second] -> format("two: {}, {}", first, second);
  [first, ..]     -> format("starts with {}", first);
  [.., last]      -> format("ends with {}", last);
}
```

The `..` rest pattern matches zero or more elements:

```ferrule
match bytes {
  [0x89, 0x50, 0x4E, 0x47, ..] -> "PNG";
  [0xFF, 0xD8, 0xFF, ..]       -> "JPEG";
  _                             -> "unknown";
}
```

### Named Patterns

Bind a value while also matching a pattern using `as`:

```ferrule
match code {
  n as 200..300 -> log("success", n);
  n as 400..500 -> log("client error", n);
  n             -> log("other", n);
}
```

Useful for capturing a whole structure while destructuring:

```ferrule
match user {
  u as { role: "admin", .. } -> audit_admin(u);
  { name, .. }               -> greet(name);
}
```

### Nested Patterns

Patterns compose naturally:

```ferrule
type Response = 
  | Success { data: Data } 
  | Error { code: i32, message: String };

type Data = 
  | User { name: String, age: u32 } 
  | Empty;

match response {
  Success { data: User { name, age } } -> welcome(name, age);
  Success { data: Empty }              -> handle_empty();
  Error { code: 404, .. }              -> not_found();
  Error { code, message }              -> handle_error(code, message);
}
```

---

## Guards

Add conditions with `where` (consistent with type refinements):

```ferrule
match point {
  { x, y } where x == y     -> "on diagonal";
  { x, y } where x + y == 0 -> "on anti-diagonal";
  _                         -> "elsewhere";
}
```

Guards can reference bound variables:

```ferrule
match user {
  { age, .. } where age < 18  -> restrict_content();
  { age, .. } where age >= 65 -> apply_discount();
  _                           -> standard_access();
}
```

---

## Exhaustiveness

All `match` expressions must cover every possible value.

### Union Coverage

Unions must be fully covered or use `_`:

```ferrule
type Status = | Ok | NotFound | Forbidden | ServerError;

// exhaustive: all variants listed
match status {
  Ok         -> handle_ok();
  NotFound   -> handle_not_found();
  Forbidden  -> handle_forbidden();
  ServerError -> handle_server_error();
}

// also valid: wildcard covers remainder
match status {
  Ok       -> handle_ok();
  NotFound -> handle_not_found();
  _        -> handle_other();
}
```

Missing coverage is a compile error. See [../reference/diagnostics.md](../reference/diagnostics.md#non-exhaustive-match).

### Integer Exhaustiveness

Integer matches require `_` or complete range coverage:

```ferrule
match byte {
  0..128   -> "low";
  128..256 -> "high";
}
```

---

## Match with Error Propagation

### Match Check

Combine pattern matching with error propagation using `match check`:

```ferrule
match check fetch(url) {
  Response { status: 200, body } -> process(body);
  Response { status: 404, .. }   -> return err NotFound { url };
  Response { status, .. }        -> return err HttpError { status };
}
```

`match check` unwraps `ok` values for matching, while `err` propagates automatically (like `check` does).

Equivalent to:

```ferrule
const response = check fetch(url);
match response {
  Response { status: 200, body } -> process(body);
  Response { status: 404, .. }   -> return err NotFound { url };
  Response { status, .. }        -> return err HttpError { status };
}
```

### Matching Error Variants

Match on error domain variants:

```ferrule
match result {
  ok { value } -> process(value);
  err { error: NotFound { path } } -> log("missing: {}", path);
  err { error: Denied { reason } } -> log("denied: {}", reason);
  err { error } -> return err error;
}
```

---

## Conditional Binding

### If Match

Single-pattern conditional without full exhaustiveness:

```ferrule
if match maybe_value {
  Some { value } -> {
    process(value);
  }
}
```

With else:

```ferrule
if match result {
  ok { value } where value > 0 -> {
    handle_positive(value);
  }
} else {
  handle_other();
}
```

### Const Match

Unwrap a pattern or diverge (return/break/continue):

```ferrule
const Some { value } = maybe_value else {
  return err NotFound {};
};
// value is now bound
```

The else block must diverge:

```ferrule
const ok { config } = load_config() else {
  panic("failed to load config");
};
```

### While Match

Loop while a pattern matches:

```ferrule
while match iter.next() {
  Some { value } -> {
    process(value);
  }
}
```

---

## Arm Syntax

Each arm uses `->` for the body:

```ferrule
match value {
  pattern -> expression;
  pattern -> { 
    statement1;
    statement2;
    result_expression
  };
}
```

Arms are terminated with `;`.

---

## Summary

| Pattern | Example | Description |
|---------|---------|-------------|
| Wildcard | `_` | Match anything |
| Literal | `42`, `"foo"`, `null` | Exact value |
| Binding | `x` | Bind matched value |
| Range | `0..10`, `'a'..='z'` | Value ranges |
| Alternative | `A \| B` | Match either |
| Variant | `Some { value }` | Destructure union |
| Record | `{ x, y }` | Destructure record |
| Array | `[a, .., z]` | Destructure array |
| Named | `x as Pattern` | Bind while matching |

| Form | Purpose |
|------|---------|
| `match` | Exhaustive multi-arm matching |
| `match check` | Match + error propagation |
| `if match` | Single-pattern conditional |
| `const P = expr else` | Unwrap or diverge |
| `while match` | Loop while pattern matches |

| Guard | Syntax |
|-------|--------|
| Condition | `pattern where condition` |
