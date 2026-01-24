---
title: function syntax
status: α1
implemented:
  - function-keyword
  - named-functions
  - anonymous-functions
  - basic-parameters
  - return-types
  - generic-functions
pending:
  - inout-parameters
  - cap-parameters
deferred:
  - closure-captures (α2)
---

# function syntax

ferrule uses `function` for everything. named functions, anonymous functions, inline lambdas. no arrows, no `fn`, no shorthands. one way to write functions.

## declaration form

```ferrule
function name<TypeParams>(params...) -> ReturnType error ErrorDomain effects [...] {
    // body
}
```

everything after ReturnType is optional.

## named functions

```ferrule
function add(x: i32, y: i32) -> i32 {
  return x + y;
}

function greet(name: String) -> String {
    return "hello, " ++ name;
}
```

## anonymous functions

same `function` keyword:

```ferrule
const double = function(x: i32) -> i32 {
  return x * 2;
};

const greet = function(name: String) -> String {
    return "hello, " ++ name;
};
```

## inline functions

when passing functions as arguments:

```ferrule
map(items, function(item: Item) -> String {
  return item.name;
});

filter(numbers, function(n: i32) -> Bool {
  return n > 0;
});
```

prefer named functions for clarity:

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

## parameters

### basic

```ferrule
function add(x: i32, y: i32) -> i32 { 
  return x + y; 
}
```

### inout (by reference)

```ferrule
function increment(inout counter: u32) -> Unit { 
  counter = counter + 1; 
}
```

the mutation is visible to the caller. see [../core/declarations.md](/docs/core/declarations).

### capabilities

```ferrule
function readFile(path: Path, cap fs: Fs) -> Bytes error IoError effects [fs] {
  return check fs.readAll(path);
}
```

see [../modules/capabilities.md](/docs/modules/capabilities).

## return types

every function must declare a return type:

```ferrule
function greet(name: String) -> String {
    return "hello, " ++ name;
}
```

use `Unit` for functions that don't return a meaningful value:

```ferrule
function log(message: String, cap io: Io) -> Unit effects [io] {
  io.println(message);
}
```

## generic functions

```ferrule
function identity<T>(x: T) -> T {
  return x;
}

function swap<T, U>(pair: { first: T, second: U }) -> { first: U, second: T } {
  return { first: pair.second, second: pair.first };
}
```

see [../core/generics.md](/docs/core/generics).

## error clauses

functions that can fail declare their error domain:

```ferrule
function parsePort(s: String) -> Port error ParseError {
  // can use ok/err/check/ensure
}
```

see [../errors/propagation.md](/docs/errors/propagation).

## effects declaration

```ferrule
function fetch(url: Url, cap net: Net, cap clock: Clock) -> Response error ClientError effects [net, time] {
  // may perform net and time effects
}
```

see [effects](/docs/functions/effects).

## function types

function types in type annotations:

```ferrule
type Predicate<T> = (T) -> Bool;
type Mapper<T, U> = (T) -> U;
type Handler<T, E> = (T) -> Unit error E effects [io];

const isEven: Predicate<i32> = function(n: i32) -> Bool {
  return n % 2 == 0;
};
```

## complete example

```ferrule
function save(
    path: Path, 
    data: View<u8>, 
    cap fs: Fs
) -> Unit error IoError effects [fs] {
    return check fs.writeAll(path, data);
}
```

## summary

| form | syntax |
|------|--------|
| named | `function name(...) -> T { ... }` |
| anonymous | `const f = function(...) -> T { ... };` |
| inline | `map(items, function(x: T) -> U { ... })` |
| generic | `function name<T>(...) -> T { ... }` |
| with effects | `function name(...) -> T effects [...] { ... }` |
| with error | `function name(...) -> T error E { ... }` |
