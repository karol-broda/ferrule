# Lexical Structure

> **scope:** source encoding, identifiers, keywords, whitespace, comments  
> **related:** [keywords.md](../reference/keywords.md)

---

## Source Files

- **encoding:** UTF-8
- **extension:** `.fe` (e.g., `main.fe`, `server.fe`)

---

## Identifiers

```
[_A-Za-z][_0-9A-Za-z]*
```

Unicode letters are allowed in identifiers.

---

## Whitespace

Spaces, tabs, and newlines are insignificant except within strings and comments.

---

## Comments

### Line Comments

```ferrule
// this is a line comment
```

### Block Comments

```ferrule
/* this is a
   block comment */
```

Block comments may be nested.

---

## Keywords

See [reference/keywords.md](../reference/keywords.md) for the complete list.

**Reserved in α1:**

```
const, var, function, return, defer, inout, import, export, package,
type, role, domain, effects, capability, with, context,
match, if, else, for, while, break, continue,
comptime, derivation, use, error, as, where,
asm, component
```

**Future-reserved (not used in α1):**

```
trait, class, interface
```


