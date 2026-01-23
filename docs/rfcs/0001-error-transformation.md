---
rfc: 0001
title: error transformation
status: draft
created: 2026-01-23
target: α2
---

# RFC-0001: error transformation

## summary

`map_error` provides syntax for transforming error types at call sites, enabling clean error domain transitions without boilerplate match statements.

## motivation

currently, converting between error types requires verbose matching:

```ferrule
function read_config(path: string) -> Result<Config, ConfigError>
  effects [Fs]
  errors [ConfigError]
{
  const content = match fs.read(path) {
    Ok(c) => c,
    Err(e) => return err(ConfigError.IoFailed(e.to_string())),
  };

  const parsed = match parse_toml(content) {
    Ok(p) => p,
    Err(e) => return err(ConfigError.ParseFailed(e.to_string())),
  };

  return ok(parsed);
}
```

with `map_error`:

```ferrule
function read_config(path: string) -> Result<Config, ConfigError>
  effects [Fs]
  errors [ConfigError]
{
  const content = fs.read(path)
    .map_error(|e| ConfigError.IoFailed(e.to_string()))?;

  const parsed = parse_toml(content)
    .map_error(|e| ConfigError.ParseFailed(e.to_string()))?;

  return ok(parsed);
}
```

## detailed design

### syntax

`map_error` is a method on result types:

```ferrule
result.map_error(transform_fn)
```

where `transform_fn` is `function(E1) -> E2`.

### chaining with propagation

`map_error` composes with `?`:

```ferrule
const value = fallible_call()
  .map_error(|e| NewError.from(e))?;
```

### type signature

```ferrule
impl<T, E> Result<T, E> {
  function map_error<F>(self, f: function(E) -> F) -> Result<T, F> {
    match self {
      Ok(t) => Ok(t),
      Err(e) => Err(f(e)),
    }
  }
}
```

### domain unification

when combining errors from different sources:

```ferrule
error NetworkError = Timeout | ConnectionFailed;
error ParseError = InvalidJson | InvalidXml;
error ApiError = Network(NetworkError) | Parse(ParseError);

function fetch_and_parse(url: string) -> Result<Data, ApiError>
  effects [Net]
  errors [ApiError]
{
  const response = http.get(url)
    .map_error(|e| ApiError.Network(e))?;

  const data = parse(response.body)
    .map_error(|e| ApiError.Parse(e))?;

  return ok(data);
}
```

### shorthand with From

if an error type implements `From`, automatic conversion is available:

```ferrule
impl From<NetworkError> for ApiError {
  function from(e: NetworkError) -> ApiError {
    return ApiError.Network(e);
  }
}

// then this works automatically:
const response = http.get(url)?;  // auto-converts NetworkError to ApiError
```

## drawbacks

- adds complexity to error handling
- implicit conversion with `From` can obscure error origins
- method chaining style differs from other ferrule idioms

## alternatives

### try-with syntax

```ferrule
const value = try http.get(url) with |e| ApiError.Network(e);
```

rejected for being too different from the rest of the language.

### only explicit match

keep error conversion explicit with match statements.

rejected because it creates too much boilerplate.

## prior art

| language | feature |
|----------|---------|
| rust | `map_err`, `From` trait, `?` operator |
| swift | `mapError` on Result |
| kotlin | `mapFailure` on Result |

## unresolved questions

1. should `From` conversion be implicit or require explicit opt-in?
2. how does this interact with context frames?
3. should there be a `map_ok` for symmetry?

## future possibilities

- `and_then` for chaining fallible operations
- `or_else` for error recovery
- context accumulation across `map_error` chains
