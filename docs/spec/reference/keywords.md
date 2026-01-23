---
title: keywords
status: α1
implemented:
  - declaration-keywords
  - control-flow-keywords
  - type-keywords
pending: []
deferred: []
---

# keywords

---

## Reserved Keywords (α1)

These identifiers are reserved and cannot be used as variable, function, or type names:

### Declarations

| Keyword | Purpose |
|---------|---------|
| `const` | immutable binding |
| `var` | mutable binding |
| `function` | function declaration |
| `type` | type alias/definition |
| `error` | error type declaration |
| `domain` | error domain declaration |
| `capability` | capability declaration |

### Modifiers

| Keyword | Purpose |
|---------|---------|
| `inout` | by-reference parameter |
| `export` | public symbol |
| `import` | module import |
| `package` | package declaration |
| `use` | module-level defaults |
| `effects` | effect declaration |
| `cap` | capability parameter |
| `pub` | public visibility |

### Control Flow

| Keyword | Purpose |
|---------|---------|
| `if` | conditional |
| `else` | conditional branch |
| `match` | pattern matching |
| `check` | unwrap result, used with `match check` |
| `for` | iteration |
| `while` | loop |
| `break` | exit loop |
| `continue` | skip iteration |
| `return` | function return |
| `defer` | deferred execution |

### Error Handling

| Keyword | Purpose |
|---------|---------|
| `ok` | success construction |
| `err` | error construction |
| `check` | unwrap or propagate |
| `ensure` | guard clause |

### Type System

| Keyword | Purpose |
|---------|---------|
| `where` | type constraints/refinement |
| `is` | type narrowing |
| `in` | contravariant |
| `out` | covariant |
| `infer` | type inference in conditionals |
| `map` | mapped types |
| `distribute` | distributive conditional |

### memory and safety

| keyword | purpose |
|---------|---------|
| `unsafe` | unsafe block |
| `move` | explicit ownership transfer |
| `copy` | explicit copy annotation |
| `clone` | explicit clone |
| `static` | static allocation |

### other

| keyword | purpose |
|---------|---------|
| `with` | context/capability modifier |
| `context` | context ledger |
| `as` | aliasing |
| `comptime` | compile-time evaluation |
| `asm` | inline assembly |
| `component` | wasm component |
| `unknown` | dynamic type requiring narrowing |
| `Unit` | unit type/value |

---

## planned keywords (α2)

| keyword | purpose |
|---------|---------|
| `impl` | implementation sugar |
| `derive` | auto-derive implementations |
| `test` | test block declaration |
| `once` | single-iteration loop |
| `assert` | compile-time assertions |
| `verify` | verification blocks |
| `valid` | ownership state check |
| `moved` | ownership state check |
| `packed` | packed struct layout |
| `extern` | c-compatible struct layout |
| `transmute` | bit reinterpretation |

---

## removed keywords

these were in earlier drafts but are **not** in α1:

| removed | reason |
|---------|--------|
| `role` | replaced by record-based polymorphism |
| `trait` | never used |
| `self` | functions use explicit first parameter |
| `fn` | use `function` for all functions |
| `===` | use `==` for equality (no triple equals) |
| `!==` | use `!=` for inequality |
| `null` | use `None` variant of `Maybe<T>` instead |
| `unsafe_cast` | replaced by `unsafe` block + transmute |

---

## Contextual Keywords

Some identifiers have special meaning only in specific contexts:

| Identifier | Context | Meaning |
|------------|---------|---------|
| `self` | refinement `where` clause | the value being refined |
| `to` | `view.move`, `view.copy` | destination parameter |
| `using` | `map_error` | transform function |
| `volatile` | inline assembly | prevent optimization |
| `clobber` | inline assembly | register clobber list |
| `mut` | `View<mut T>` | mutable view |

These can still be used as regular identifiers outside their special contexts.

---

## Literals

| Literal | Type |
|---------|------|
| `true` | `Bool` |
| `false` | `Bool` |
| `Unit` | `Unit` type value |

> **Note:** `None` is not a literal but a union variant constructor for `Maybe<T>`. Use `None` directly when constructing optional values: `const x: u32? = None;`

---

## Operators as Keywords

These are operators, not keywords, but are reserved:

```
+ - * / %
& | ^ ~ << >>
&& || !
== != < <= > >=
++ 
-> =>
...
```
