# Keywords

> **scope:** reserved words in Ferrule α1  
> **related:** [grammar.md](grammar.md) | [../core/lexical.md](../core/lexical.md)

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

### Other

| Keyword | Purpose |
|---------|---------|
| `with` | context/derivation modifier |
| `context` | context ledger |
| `as` | aliasing |
| `comptime` | compile-time evaluation |
| `asm` | inline assembly |
| `component` | WASM component |
| `unsafe_cast` | unsafe type cast |
| `unknown` | dynamic type requiring narrowing |
| `Unit` | unit type/value |
| `distribute` | distributive conditional types |
| `infer` | type inference in conditionals |
| `map` | mapped types |
| `out` | covariant variance |

---

## Removed Keywords

These were in earlier drafts but are **not** in α1:

| Removed | Reason |
|---------|--------|
| `role` | Replaced by record-based polymorphism |
| `trait` | Never used |
| `impl` | Replaced by namespaced constants |
| `self` | Functions use explicit first parameter |
| `fn` | Use `function` for all functions |
| `===` | Use `==` for equality (no triple equals) |
| `!==` | Use `!=` for inequality |

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

These can still be used as regular identifiers outside their special contexts.

---

## Literals

| Literal | Type |
|---------|------|
| `true` | `Bool` |
| `false` | `Bool` |
| `null` | `None` variant of `Maybe<T>` |
| `Unit` | `Unit` type value |

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
