---
title: error domains
status: α1
implemented:
  - standalone-error-types
  - domain-syntax
pending:
  - domain-composition
  - use-error-default
deferred:
  - pick-omit (α2)
  - inline-error-unions (α2)
---

# error domains

ferrule uses errors as values. no exceptions, no implicit panics. errors are types you define and return.

## standalone error types

define error types outside of domains:

```ferrule
error NotFound { path: Path }
error Denied { path: Path, reason: String }
error Timeout { ms: u64 }
error ParseFailed { line: u32, message: String }
```

standalone errors can be:
- used directly in function signatures
- combined into domains
- reused across multiple domains

## domains

domains group related errors into a union. two syntaxes:

### union syntax (preferred)

reference standalone error types by name:

```ferrule
domain IoError = NotFound | Denied | Timeout;
domain ParseError = ParseFailed | UnexpectedToken;
```

use this when errors are reused across multiple domains.

### inline variant syntax

define error variants directly:

```ferrule
domain IoError {
  NotFound { path: Path }
  Denied { path: Path, reason: String }
  Timeout { ms: u64 }
}
```

use this for domain-specific errors that won't be reused.

## domain composition

compose domains using union syntax:

```ferrule
// standalone errors
error NotFound { path: Path }
error Denied { path: Path }
error Timeout { ms: u64 }
error ConnectionRefused { host: String }
error ParseFailed { line: u32 }

// domains as unions
domain IoError = NotFound | Denied;
domain NetError = Timeout | ConnectionRefused;
domain ParseError = ParseFailed;

// union of domains
domain AppError = IoError | NetError | ParseError;

// add extra errors to existing domain
domain ExtendedIoError = IoError | PermissionError;
```

## module default error

use `use error` to set a default error domain for the module:

```ferrule
use error IoError;

// functions in this module default to error IoError
function readFile(p: Path, cap fs: Fs) -> Bytes effects [fs] {
  // implicitly: error IoError
}
```

public exports must be explicit about their error domain regardless of module defaults.

## precise error signatures

use specific errors instead of full domains when appropriate:

```ferrule
// full domain
function process(input: Input) -> Output error AppError { ... }

// precise: only these two errors possible
function validate(input: Input) -> Output error (ParseFailed | InvalidFormat) { ... }
```

this helps callers know exactly what can fail.

## complete example

```ferrule
// standalone error types
error NotFound { path: Path }
error Denied { path: Path }
error Timeout { ms: u64, operation: String }
error ConnectionRefused { host: String, port: u16 }
error ParseFailed { line: u32, column: u32, message: String }

// group into domains
domain IoError = NotFound | Denied | Timeout;
domain NetError = Timeout | ConnectionRefused;
domain ParseError = ParseFailed;

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

## what's planned

**pick/omit** (α2) for extracting subsets:

```ferrule
// only NotFound and Denied
type ReadErrors = Pick<IoError, NotFound | Denied>;

// everything except Timeout
type FastIoError = Omit<IoError, Timeout>;
```

## summary

| syntax | purpose |
|--------|---------|
| `error Name { fields }` | standalone error type |
| `domain D = E1 \| E2;` | domain as union (preferred) |
| `domain D { E1 { } E2 { } }` | domain with inline variants |
| `domain D = D1 \| D2;` | compose domains |
| `error (E1 \| E2)` | inline error union in signatures |
| `use error D;` | module default domain |
