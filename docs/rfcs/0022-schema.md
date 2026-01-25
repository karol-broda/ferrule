---
rfc: 0022
title: schema - validation and parsing
status: draft
created: 2026-01-24
target: α2
depends: [0021-codec, refinements]
---

# RFC-0014: schema

## summary

schemas validate and parse unknown data into typed ferrule values. they combine parsing, validation, and type inference into a single system. the design is inspired by zod/valibot but leverages ferrule's type system for compile-time safety.

## motivation

external data is untrustworthy:
- http request bodies
- query parameters
- configuration files
- database results
- user input

you need to validate before using. most languages handle this badly:

1. **manual validation**: verbose, error-prone, duplicates type info
2. **runtime reflection**: no compile-time safety
3. **external schema files**: separate from code, can drift

ferrule can unify parsing, validation, and types:

```ferrule
// schema IS the type definition
const UserSchema = schema.object({
    name: schema.string().min(1).max(100),
    email: schema.string().email(),
    age: schema.int().min(13).optional(),
});

// type flows from schema
type User = Schema.infer<UserSchema>;

// parse validates and returns typed value
const user: User = check UserSchema.parse(raw_input);
```

### goals

1. **schema is source of truth**: types derived from schemas
2. **composable**: combine, transform, extend schemas
3. **precise errors**: know exactly what failed and where
4. **zero-cost where possible**: refinements check at construction
5. **extensible**: users define custom validators
6. **interoperable**: standard interface like typescript's standard schema

## detailed design

### core type

```ferrule
/// a schema validates unknown -> T
type Schema<T> = {
    parse: (unknown) -> T error ValidationError,
    
    // optional introspection
    describe: () -> SchemaDescription,
};
```

this minimal interface enables interoperability. any library can implement `Schema<T>`.

### validation errors

```ferrule
error ValidationError {
    Type { expected: String, got: String, path: Path },
    Constraint { message: String, path: Path },
    Missing { field: String, path: Path },
    Unknown { field: String, path: Path },
    Multiple { errors: Array<ValidationError> },
}

type Path = Array<PathSegment>;
type PathSegment = | Field { name: String } | Index { i: usize };
```

errors are structured, not just strings. enables programmatic handling.

### primitive schemas

```ferrule
// string
schema.string() -> Schema<String>
schema.string().min(n) -> Schema<String>
schema.string().max(n) -> Schema<String>
schema.string().length(n) -> Schema<String>
schema.string().regex(pattern) -> Schema<String>
schema.string().email() -> Schema<String>
schema.string().url() -> Schema<String>
schema.string().uuid() -> Schema<String>

// numbers
schema.int() -> Schema<i64>
schema.int().min(n) -> Schema<i64>
schema.int().max(n) -> Schema<i64>
schema.int().positive() -> Schema<i64>
schema.float() -> Schema<f64>

// others
schema.bool() -> Schema<Bool>
schema.literal(value) -> Schema<typeof value>
schema.null() -> Schema<Unit>
```

### object schemas

```ferrule
const PersonSchema = schema.object({
    name: schema.string(),
    age: schema.int().positive(),
});

// infers type { name: String, age: i64 }
type Person = Schema.infer<PersonSchema>;
```

### array schemas

```ferrule
const NumbersSchema = schema.array(schema.int());
// infers Array<i64>

const TupleSchema = schema.tuple([
    schema.string(),
    schema.int(),
    schema.bool(),
]);
// infers (String, i64, Bool)
```

### union schemas

```ferrule
const ResultSchema = schema.union([
    schema.object({ ok: schema.bool().literal(true), value: schema.string() }),
    schema.object({ ok: schema.bool().literal(false), error: schema.string() }),
]);
```

### optional and nullable

```ferrule
schema.string().optional()   // String?
schema.string().nullable()   // String | Null
schema.string().default("") // String, uses default if missing
```

### transformations

schemas can transform during parsing:

```ferrule
const DateSchema = schema.string()
    .regex(date_pattern)
    .transform(|s| Date.parse(s));
// Schema<Date>, not Schema<String>

const TrimmedSchema = schema.string()
    .transform(|s| s.trim());
```

### refinements

add custom validation:

```ferrule
const PasswordSchema = schema.string()
    .min(8)
    .refine(
        |s| s.contains_uppercase() && s.contains_digit(),
        "must contain uppercase and digit"
    );

// async refinement for db checks
const UniqueEmailSchema = schema.string()
    .email()
    .refine_async(
        |email, ctx| ctx.db.is_email_available(email),
        "email already taken"
    );
```

### coercion

optionally coerce types:

```ferrule
// strict: "42" fails for int
const StrictAge = schema.int();

// coerce: "42" becomes 42
const CoercedAge = schema.coerce.int();
```

### error customization

```ferrule
const AgeSchema = schema.int()
    .min(0, "age cannot be negative")
    .max(150, "age seems unrealistic");
```

### composition

schemas compose:

```ferrule
const AddressSchema = schema.object({ ... });
const PersonSchema = schema.object({ ... });

const FullPersonSchema = PersonSchema.extend({
    address: AddressSchema,
});

const PartialPerson = PersonSchema.partial();  // all fields optional
const RequiredPerson = PersonSchema.required(); // all fields required
const PickedPerson = PersonSchema.pick(["name", "email"]);
const OmittedPerson = PersonSchema.omit(["password"]);
```

### integration with codecs

schemas and codecs work together:

```ferrule
// parse json string into validated type
function parse_json<T>(json: String, s: Schema<T>) -> T error ParseError {
    const raw = check json.parse_value(json);  // json -> unknown
    return check s.parse(raw);                  // unknown -> T
}

// in http handler
function create_user(body: Bytes, cap net: Net) -> Response error AppError effects [net] {
    const input = check parse_json(body.to_string(), CreateUserSchema);
    // input is fully typed and validated
    const user = check db.create_user(input);
    return json_response(user, User.json);
}
```

### integration with refinement types

schemas can produce refinement types:

```ferrule
// refinement type
type Email = String where email.is_valid(self);

// schema that produces refinement type
const EmailSchema: Schema<Email> = schema.string().email().as<Email>();
```

### standard schema interface

for interoperability (inspired by typescript's standard schema):

```ferrule
/// minimal interface any validator can implement
type StandardSchema<T> = {
    validate: (unknown) -> T error ValidationError,
};

// our schemas implement it
impl StandardSchema<T> for Schema<T> {
    validate: self.parse,
}

// third-party validators can implement it too
// enabling framework interop
```

### http integration

schemas integrate with http handlers:

```ferrule
type Route<Params, Query, Body, Response> = {
    path: PathPattern<Params>,
    query: Schema<Query>,
    body: Schema<Body>,
    response: Codec<Response>,
    handler: (Params, Query, Body, Context) -> Response error HttpError,
};

const create_user_route: Route<Unit, Unit, CreateUserInput, User> = {
    path: path("/users"),
    query: schema.object({}),
    body: CreateUserSchema,
    response: User.json,
    handler: create_user_handler,
};
```

## drawbacks

- method chaining is less ferrule-idiomatic
- schema definition is separate from type (until comptime inference)
- runtime validation overhead
- complex schema compositions can be hard to understand

## alternatives

### refinement types only

use refinement types for all validation:

```ferrule
type Email = String where email.is_valid(self);
type Age = u8 where self >= 0 && self <= 150;
```

good for simple cases, but:
- can't validate across fields
- can't do async validation
- no transformation

schemas complement refinement types, not replace them.

### derive-based validation

```ferrule
type User = derive(Validate) {
    @min(1) @max(100)
    name: String,
    
    @email
    email: String,
};
```

considered: could work, but schemas are more flexible for:
- runtime schema composition
- different validations for same type
- partial validation

### no built-in validation

let users build their own.

rejected: validation is too fundamental. a standard interface enables ecosystem interop.

## prior art

| library | lesson |
|---------|--------|
| zod | builder pattern is ergonomic, type inference is key |
| valibot | tree-shakable, smaller than zod |
| yup | async validation is important |
| joi | good error messages matter |
| arktype | type-first can work |
| effect/schema | integration with effect system |
| standard schema | interoperability via minimal interface |

zod's success shows developers want schema-as-source-of-truth.

## unresolved questions

1. how to infer types from schemas at comptime?
2. should transformations be separate from validation?
3. how to handle recursive schemas?
4. should there be sync vs async parse methods?

## future possibilities

- form validation integration
- openapi/json schema generation
- graphql type generation
- database model integration
- cli argument parsing from schemas
- environment variable parsing
