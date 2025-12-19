# Error Domains

> **scope:** standalone error types, error domains, composition, Pick/Omit  
> **related:** [propagation.md](propagation.md) | [../functions/syntax.md](../functions/syntax.md)

---

## Overview

Ferrule uses **errors as values** — no exceptions, no implicit panics. Errors can be defined as standalone types or grouped into domains.

---

## Standalone Error Types

Define error types outside of domains:

```ferrule
error NotFound { path: Path }
error Denied { path: Path, reason: String }
error Timeout { ms: u64 }
error ParseFailed { line: u32, message: String }
```

Standalone errors can be:
- Used directly in function signatures
- Combined into domains
- Reused across multiple domains

---

## Error Domains

Domains group related errors. There are two syntaxes:

### Union Syntax (Preferred)

Reference standalone error types by name:

```ferrule
domain IoError = NotFound | Denied | Timeout;
domain ParseError = ParseFailed | UnexpectedToken;
```

This is the **preferred** syntax when errors are reused across multiple domains.

### Inline Variant Syntax

Define error variants directly within the domain:

```ferrule
domain IoError {
  NotFound { path: Path }
  Denied { path: Path, reason: String }
  Timeout { ms: u64 }
}
```

Use this syntax for domain-specific errors that won't be reused.

Both syntaxes create **unions of error types**.

---

## Domain Composition

Compose domains using union syntax:

```ferrule
// standalone errors
error NotFound { path: Path }
error Denied { path: Path }
error Timeout { ms: u64 }
error ConnectionRefused { host: String }
error ParseFailed { line: u32 }
error UnexpectedToken { token: String }

// domains as unions
domain IoError = NotFound | Denied;
domain NetError = Timeout | ConnectionRefused;
domain ParseError = ParseFailed | UnexpectedToken;

// union of domains
domain AppError = IoError | NetError | ParseError;

// add extra errors to existing domain
domain ExtendedIoError = IoError | PermissionError;
```

---

## Pick and Omit

Extract subsets of errors from domains:

### Pick

Select specific errors:

```ferrule
domain IoError = NotFound | Denied | Timeout;

// only NotFound and Denied
type ReadErrors = Pick<IoError, NotFound | Denied>;
```

### Omit

Exclude specific errors:

```ferrule
// everything except Timeout
type FastIoError = Omit<IoError, Timeout>;
```

### Usage in Signatures

```ferrule
// function can only return specific errors
function quickRead(path: Path, cap fs: Fs) -> Bytes error Pick<IoError, NotFound | Denied> effects [fs] {
  // cannot return Timeout
}

// function excludes certain errors
function fastOp() -> Data error Omit<AppError, Timeout> {
  // guaranteed not to timeout
}
```

---

## Module Default Error

Use `use error` to set a default error domain for the module:

```ferrule
use error IoError;

// functions in this module default to error IoError
function readFile(p: Path) -> Bytes effects [fs] {
  // implicitly: error IoError
}
```

**Public/ABI exports must be explicit** about their error domain regardless of module defaults.

---

## Precise Error Signatures

Use specific errors instead of full domains when appropriate:

```ferrule
// full domain
function process(input: Input) -> Output error AppError { ... }

// precise: only these two errors possible
function validate(input: Input) -> Output error (ParseFailed | InvalidFormat) { ... }
```

---

## Error Type Declaration Syntax

```ferrule
// simple error (no fields)
error ConnectionRefused;

// error with fields
error NotFound { 
  path: Path 
}

// error with multiple fields
error ValidationError { 
  field: String,
  message: String,
  code: u32 
}
```

---

## Example: Full Error Hierarchy

```ferrule
// standalone error types
error NotFound { path: Path }
error Denied { path: Path }
error Timeout { ms: u64, operation: String }
error ConnectionRefused { host: String, port: u16 }
error ParseFailed { line: u32, column: u32, message: String }
error InvalidFormat { expected: String, actual: String }

// group into domains
domain IoError = NotFound | Denied | Timeout;
domain NetError = Timeout | ConnectionRefused;
domain ParseError = ParseFailed | InvalidFormat;

// compose domains
domain AppError = IoError | NetError | ParseError;

// function using composed domain
function loadConfig(path: Path, cap fs: Fs) -> Config error AppError effects [fs] {
  const bytes = check readFile(path, fs);  // IoError
  const parsed = check parse(bytes);        // ParseError
  return ok parsed;
}

// function with precise errors
function readOnly(path: Path, cap fs: Fs) -> Bytes error (NotFound | Denied) effects [fs] {
  // can only fail with NotFound or Denied, never Timeout
}
```

---

## Inline Error Unions

Define error unions inline without creating a domain:

```ferrule
function tryBoth(a: Path, b: Url, cap fs: Fs, cap net: Net) 
  -> Data error (IoError | NetError) effects [fs, net] 
{
  // can return errors from either domain
}
```

---

## Summary

| Syntax | Purpose |
|--------|---------|
| `error Name { fields }` | Standalone error type |
| `domain D = E1 \| E2;` | Domain as union of errors (preferred) |
| `domain D { E1 { } E2 { } }` | Domain with inline variants |
| `domain D = D1 \| D2;` | Compose domains |
| `Pick<D, E1 \| E2>` | Select errors from domain |
| `Omit<D, E1>` | Exclude errors from domain |
| `error (E1 \| E2)` | Inline error union in signatures |
| `use error D;` | Module default domain |
