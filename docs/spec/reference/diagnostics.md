# Diagnostics & Lints

> **scope:** compiler error messages, warnings, helpful hints  
> **related:** [../functions/effects.md](../functions/effects.md) | [../errors/propagation.md](../errors/propagation.md)

---

## Principles

Ferrule prioritizes clear, actionable error messages:

- **Precise location** — line/column with source context
- **Clear explanation** — what went wrong and why
- **Actionable hints** — specific steps to fix the issue
- **Related locations** — where types/regions/effects were defined
- **Consistent format** — same structure across all tools
- **No jargon** — accessible to developers at all levels

---

## Compile-Time Checks

| Check | Description |
|-------|-------------|
| exhaustiveness | `match` covers all variants |
| effect coverage | called function effects ⊆ caller effects |
| capability flow | `fs` effect requires `Fs` capability |
| boolean coercion | `if value` rejected, use `if value == true` |
| numeric coercion | conversions must be explicit |
| region safety | cross-region view misuse flagged |
| unused bindings | warn on unused `const`/`var` |
| nominal typing | incompatible types even with same structure |
| type inference | ambiguous cases require annotation |

---

## Example Diagnostics

### Effect Mismatch

```
error: effect not declared
  ┌─ src/server.fe:12:15
  │
12│   const data = fs.readAll(path);
  │                ^^^^^^^^^^^^^^^^^ function requires effect [fs]
  │
  = note: fs.readAll has effects [fs]
  = help: add 'effects [fs]' to function signature:
          function loadConfig(...) -> Config effects [fs] { ... }
```

### Missing Error Handling

```
error: unhandled fallible result
  ┌─ src/parser.fe:8:18
  │
 8│   const port = parsePort(input);
  │                ^^^^^^^^^^^^^^^^^^ returns Result<Port, ParseError>
  │
  = note: parsePort can fail with ParseError
  = help: handle the error using one of:
          • check parsePort(input)      -- propagate error
          • match parsePort(input) { ... }  -- handle explicitly
```

### Implicit Boolean Coercion

```
error: expected Bool, found u32?
  ┌─ src/main.fe:15:8
  │
15│   if count {
  │      ^^^^^ type is u32?, not Bool
  │
  = note: ferrule does not allow implicit boolean coercion
  = help: be explicit about the condition:
          • if count != null { ... }
          • if count != null && count != 0 { ... }
```

### Nominal Type Mismatch

```
error: type mismatch
  ┌─ src/main.fe:20:18
  │
20│   const post: PostId = user;
  │                        ^^^^ expected PostId, found UserId
  │
  = note: UserId and PostId are different types (nominal typing)
  = note: both have structure { id: u64 } but are not compatible
  = help: use explicit conversion:
          const post: PostId = toPostId(user);
```

### Missing Capability Parameter

```
error: effect [fs] requires capability
  ┌─ src/io.fe:22:1
  │
22│ function readConfig(path: Path) -> Config error IoError effects [fs] {
  │ ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  │
  = note: function declares effect [fs] but has no Fs capability parameter
  = help: add capability parameter:
          function readConfig(path: Path, cap fs: Fs) -> Config error IoError effects [fs]
```

### Non-Exhaustive Match

```
error: non-exhaustive match
  ┌─ src/http.fe:45:3
  │
45│   match response {
  │   ^^^^^ missing coverage for HttpResponse variants
  │
46│     Ok { data } -> process(data);
47│     NotFound -> log.warn("not found");
48│   }
  │
  = note: HttpResponse has 5 variants: Ok, NotFound, Forbidden, ServerError, Timeout
  = help: missing patterns:
          • Forbidden { ... }
          • ServerError { ... }
          • Timeout { ... }
          or add a catch-all: _ -> ...
```

### Region Safety Violation

```
error: view outlives region
  ┌─ src/buffer.fe:18:10
  │
18│   return buf;
  │          ^^^ view bound to region 'arena' which is disposed at line 19
  │
17│   const buf = arena.alloc<u8>(1024);
  │               ----- region created here
19│   defer arena.dispose();
  │         ----- region disposed here
  │
  = help: either return the region with the view, or copy data to outer region:
          • return { buf: buf, region: arena }
          • return view.copy(buf, to = region.heap())
```

### Type Inference Required

```
error: cannot infer type
  ┌─ src/main.fe:10:7
  │
10│   const result = compute();
  │         ^^^^^^ type annotation required
  │
  = note: compute() returns a generic type that cannot be inferred
  = help: add type annotation:
          const result: Data = compute();
```

---

## Warning Levels

| Level | Behavior |
|-------|----------|
| `error` | compilation fails |
| `warning` | compilation continues, logged |
| `hint` | informational suggestion |

---

## Suppressing Warnings

```ferrule
@allow(unused_binding)
const _ignored = someValue;

@allow(deprecated)
oldApi.call();
```

---

## Lint Configuration

In `deps.fe`:

```ferrule
.{
  .lints = .{
    .unused_binding = .warn,
    .deprecated = .error,
    .implicit_return = .allow,
  },
}
```
