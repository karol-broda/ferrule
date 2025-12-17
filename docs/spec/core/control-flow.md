# Control Flow

> **scope:** conditionals, loops, pattern matching  
> **related:** [types.md](types.md) | [../errors/propagation.md](../errors/propagation.md)

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

```ferrule
match code {
  200 -> "ok";
  404 -> "not found";
  _   -> "unknown";
}
```

### Exhaustiveness

Unions must be **fully covered** or use `_` as a catch-all:

```ferrule
type Status = | Ok | NotFound | Forbidden | ServerError;

match status {
  Ok        -> handle_ok();
  NotFound  -> handle_not_found();
  Forbidden -> handle_forbidden();
  _         -> handle_other();  // covers ServerError and any future variants
}
```

Missing coverage is a compile error. See [../reference/diagnostics.md](../reference/diagnostics.md#non-exhaustive-match).

### Destructuring

```ferrule
match result {
  ok { value } -> process(value);
  err { error } -> log.error(error);
}
```

### Guards

```ferrule
match code {
  n if n >= 200 && n < 300 -> "success";
  n if n >= 400 && n < 500 -> "client error";
  n if n >= 500            -> "server error";
  _                        -> "unknown";
}
```
