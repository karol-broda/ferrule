# Function Syntax

> **scope:** function declaration form, parameters, return types, anonymous functions  
> **related:** [effects.md](effects.md) | [../errors/domains.md](../errors/domains.md) | [../core/generics.md](../core/generics.md)

---

## Declaration Form

```ferrule
function name<TypeParams>(params...) -> ReturnType [error ErrorDomain]? [effects [...]]? { ... }
```

- **`function`** is the only declaration keyword — for named, anonymous, and inline functions
- **effects** enumerate potential side effects; absence means pure/suspend-free
- **error** clause declares typed failure; see [../errors/domains.md](../errors/domains.md)

---

## Named Functions

```ferrule
function add(x: i32, y: i32) -> i32 {
  return x + y;
}

function greet(name: String) -> String {
  return "Hello, " ++ name;
}
```

---

## Anonymous Functions

Use the same `function` keyword:

```ferrule
const double = function(x: i32) -> i32 {
  return x * 2;
};

const greet = function(name: String) -> String {
  return "Hello, " ++ name;
};
```

**No arrow syntax** — Ferrule does not use `=>` or `fn` shorthands.

---

## Inline Functions

When passing functions as arguments:

```ferrule
map(items, function(item: Item) -> String {
  return item.name;
});

filter(numbers, function(n: i32) -> Bool {
  return n > 0;
});
```

**Prefer named functions for clarity:**

```ferrule
function getName(item: Item) -> String {
  return item.name;
}

function isPositive(n: i32) -> Bool {
  return n > 0;
}

map(items, getName);
filter(numbers, isPositive);
```

---

## Parameters

### Basic Parameters

```ferrule
function add(x: i32, y: i32) -> i32 { 
  return x + y; 
}
```

### Inout Parameters

```ferrule
function increment(inout counter: u32) -> Unit { 
  counter = counter + 1; 
}
```

See [../core/declarations.md](../core/declarations.md#by-reference-parameters).

### Capability Parameters

```ferrule
function readFile(path: Path, cap fs: Fs) -> Bytes error IoError effects [fs] {
  return check fs.readAll(path);
}
```

See [../modules/capabilities.md](../modules/capabilities.md).

---

## Return Types

Every function must declare a return type:

```ferrule
function greet(name: String) -> String {
  return "Hello, " ++ name;
}
```

Use `Unit` for functions that don't return a meaningful value:

```ferrule
function log(message: String) -> Unit effects [io] {
  io.println(message);
}
```

---

## Generic Functions

```ferrule
function identity<T>(x: T) -> T {
  return x;
}

function swap<T, U>(pair: { first: T, second: U }) -> { first: U, second: T } {
  return { first: pair.second, second: pair.first };
}
```

See [../core/generics.md](../core/generics.md).

---

## Error Clauses

Functions that can fail declare their error domain:

```ferrule
function parsePort(s: String) -> Port error ParseError {
  // can use ok/err/check/ensure
}
```

If omitted and `use error` is in scope, the module default applies:

```ferrule
use error IoError;

function readConfig(path: Path) -> Config effects [fs] {
  // implicitly: error IoError
}
```

**Public/ABI exports must be explicit** about `error E`.

See [../errors/propagation.md](../errors/propagation.md) for `ok`/`err`/`check`/`ensure`.

---

## Effects Declaration

```ferrule
function fetch(url: Url) -> Response error ClientError effects [net, time] {
  // may perform net and time effects
}
```

See [effects.md](effects.md) for full effect semantics.

---

## Complete Example

```ferrule
function save(
  path: Path, 
  data: View<u8>, 
  cap fs: Fs
) -> Unit error IoError effects [fs] {
  return check fs.writeAll(path, data);
}
```

---

## Function Types

Function types in type annotations:

```ferrule
type Predicate<T> = (T) -> Bool;
type Mapper<T, U> = (T) -> U;
type Handler<T, E> = (T) -> Unit error E effects [io];

const isEven: Predicate<i32> = function(n: i32) -> Bool {
  return n % 2 == 0;
};
```

---

## Summary

| Form | Syntax |
|------|--------|
| Named | `function name(...) -> T { ... }` |
| Anonymous | `const f = function(...) -> T { ... };` |
| Inline | `map(items, function(x: T) -> U { ... })` |
| Generic | `function name<T>(...) -> T { ... }` |
| With effects | `function name(...) -> T effects [...] { ... }` |
| With error | `function name(...) -> T error E { ... }` |
