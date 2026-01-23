---
rfc: 0002
title: debug context frames
status: draft
created: 2026-01-23
target: α2
---

# RFC-0002: debug context frames

## summary

context frames attach debugging information to errors as they propagate, providing rich stack traces without runtime overhead in release builds.

## motivation

when an error propagates through multiple functions, you lose context:

```
error: IoError.NotFound
```

vs:

```
error: IoError.NotFound
  at read_config (config.fe:42)
  at initialize (app.fe:15)
  at main (main.fe:8)
  context: reading configuration file "/etc/app/config.toml"
```

context frames provide the second form while being stripped in release builds.

## detailed design

### adding context

use `with_context` to attach information:

```ferrule
function read_config(path: string) -> Result<Config, ConfigError>
  effects [Fs]
  errors [ConfigError]
{
  const content = fs.read(path)
    .with_context(|| "reading config file: " ++ path)?;

  return parse(content);
}
```

### context is lazy

the closure is only called if an error occurs:

```ferrule
.with_context(|| expensive_debug_string())  // not called on success
```

### frame structure

each context frame contains:

```ferrule
type ContextFrame = {
  message: string,
  file: string,
  line: u32,
  column: u32,
};
```

### accumulation

frames accumulate as errors propagate:

```ferrule
function load_app() -> Result<App, AppError> {
  const config = read_config("/etc/app/config.toml")
    .with_context(|| "loading application")?;
  // ...
}
```

produces:

```
error: IoError.NotFound
  context: reading config file: /etc/app/config.toml
  context: loading application
  at load_app (app.fe:12)
  at main (main.fe:5)
```

### debug vs release

| build mode | behavior |
|------------|----------|
| debug | full context frames, file/line info |
| release | context frames stripped, minimal info |
| release-safe | context frames kept, performance impact |

compile flag: `--release-context` to keep context in release.

### introspection

errors can be inspected for context:

```ferrule
match result {
  Err(e) => {
    for frame in e.context_frames() {
      log.error("{}: {}:{}", frame.message, frame.file, frame.line);
    }
  },
  Ok(_) => {},
}
```

### ensure with context

`ensure` can include context:

```ferrule
ensure user.is_admin()
  else return err(AuthError.Forbidden)
  with_context "checking admin permission for user: " ++ user.id;
```

## drawbacks

- overhead in debug builds
- increases binary size with debug info
- adds complexity to error type representation

## alternatives

### external tracing

use a separate tracing system:

```ferrule
trace.span("reading config") {
  fs.read(path)?;
};
```

could complement context frames but doesn't attach to errors directly.

### no context, just stack traces

rely on stack traces alone.

rejected because stack traces don't carry semantic context.

## prior art

| language/library | feature |
|------------------|---------|
| rust anyhow | `.context()` method |
| go | `fmt.Errorf("context: %w", err)` |
| python | exception chaining |

rust's anyhow is the primary inspiration.

## unresolved questions

1. should context frames cross async boundaries?
2. how much file/line info to include by default?
3. should there be structured context (key-value pairs)?

## future possibilities

- structured context with key-value pairs
- context categories (user-facing vs debug)
- integration with logging/tracing
