---
rfc: 0021
title: codec - serialization and deserialization
status: draft
created: 2026-01-24
target: α2
depends: [comptime]
---

# RFC-0013: codec

## summary

codecs are records that encode values to bytes and decode bytes to values. the design separates the **what** (the codec interface) from the **how** (format implementations), enabling format-agnostic code and user-defined formats.

## motivation

serialization is everywhere:
- api responses (json)
- configuration files (toml, yaml)
- binary protocols (protobuf, msgpack)
- database storage
- ipc and rpc

most languages couple serialization to specific formats or require runtime reflection. ferrule can do better:

1. **format-agnostic code**: write once, serialize to any format
2. **no runtime reflection**: derive at compile time
3. **user-extensible**: implement your own formats
4. **zero-copy where possible**: views into buffers
5. **streaming support**: don't require full buffers

### what's wrong with existing approaches

**serde (rust)**:
- excellent design, but proc macros are complex
- attribute soup for customization
- compile times suffer

**json libraries (most languages)**:
- format-specific, can't switch to msgpack easily
- often use runtime reflection (slow, no compile-time safety)

**protobuf/flatbuffers**:
- require external schema files and codegen
- not native to the language

ferrule's approach: codecs are just records. derive generates them at comptime. no macros, no external tools.

## detailed design

### core types

```ferrule
/// encodes T to bytes
type Encoder<T> = {
    encode: (T, Writer) -> Unit error EncodeError,
};

/// decodes T from bytes  
type Decoder<T> = {
    decode: (Reader) -> T error DecodeError,
};

/// bidirectional codec
type Codec<T> = Encoder<T> & Decoder<T>;

/// writer abstraction (buffer, stream, etc.)
type Writer = {
    write: (View<u8>) -> Unit error IoError,
    write_byte: (u8) -> Unit error IoError,
};

/// reader abstraction
type Reader = {
    read: (usize) -> View<u8> error IoError,
    read_byte: () -> u8 error IoError,
    peek: (usize) -> View<u8> error IoError,
};
```

### format markers

formats are zero-size types used for disambiguation:

```ferrule
type Json;
type Msgpack;
type Toml;
type Bincode;
```

these enable multiple codecs per type:

```ferrule
const User.json: Codec<User> = { ... };
const User.msgpack: Codec<User> = { ... };
const User.bincode: Codec<User> = { ... };
```

### primitive codecs

stdlib provides codecs for primitives:

```ferrule
// json format
const i32.json: Codec<i32> = json.int_codec();
const String.json: Codec<String> = json.string_codec();
const Bool.json: Codec<Bool> = json.bool_codec();

// msgpack format
const i32.msgpack: Codec<i32> = msgpack.int_codec();
const String.msgpack: Codec<String> = msgpack.string_codec();
```

### derived codecs

use `derive` to generate codecs at comptime:

```ferrule
type User = derive(Codec<Json>, Codec<Msgpack>) {
    id: u64,
    name: String,
    email: String,
    age: u32?,  // optional field
};

// generates:
// const User.json: Codec<User> = { ... };
// const User.msgpack: Codec<User> = { ... };
```

### field customization

attributes control serialization behavior:

```ferrule
type ApiResponse = derive(Codec<Json>) {
    @rename("user_id")
    id: u64,
    
    @skip_if_none
    metadata: Metadata?,
    
    @flatten
    common: CommonFields,
    
    @rename_all("camelCase")
    user_data: UserData,
};
```

available attributes:
- `@rename("name")` - use different name in output
- `@skip` - never serialize this field
- `@skip_if_none` - omit if None
- `@flatten` - inline nested struct fields
- `@default(value)` - use default if missing on decode
- `@rename_all("style")` - camelCase, snake_case, etc.

### manual implementation

for custom logic, implement the codec manually:

```ferrule
const SpecialType.json: Codec<SpecialType> = {
    encode: function(value: SpecialType, w: Writer) -> Unit error EncodeError {
        // custom encoding logic
        w.write(value.custom_format());
    },
    decode: function(r: Reader) -> SpecialType error DecodeError {
        // custom decoding logic
        const bytes = r.read(EXPECTED_SIZE);
        return SpecialType.parse(bytes);
    },
};
```

### usage

```ferrule
// encode to bytes
const bytes = json.encode(user, User.json);

// decode from bytes
const user = check json.decode(bytes, User.json);

// with writer/reader (streaming)
json.encode_to(user, User.json, writer);
const user = check json.decode_from(User.json, reader);
```

### format implementations

each format implements the encoding/decoding logic:

```ferrule
// json module
pub function encode<T>(value: T, codec: Codec<T>) -> Bytes {
    const buffer = buffer.new();
    const writer = buffer.writer();
    codec.encode(value, writer);
    return buffer.to_bytes();
}

pub function decode<T>(bytes: Bytes, codec: Codec<T>) -> T error DecodeError {
    const reader = bytes.reader();
    return codec.decode(reader);
}
```

### streaming and incremental

codecs work with readers/writers, enabling:

```ferrule
// stream json array without buffering entire thing
function stream_users(users: Iterator<User>, w: Writer, cap io: Io) -> Unit error IoError {
    json.array_start(w);
    for user in users {
        json.encode_element(user, User.json, w);
    }
    json.array_end(w);
}
```

### error handling

decode errors are precise:

```ferrule
error DecodeError {
    UnexpectedType { expected: String, got: String, path: String },
    MissingField { name: String, path: String },
    InvalidValue { message: String, path: String },
    UnexpectedEnd,
    InvalidUtf8 { position: usize },
}
```

the `path` field tracks json path (e.g., `$.users[0].email`).

### schema introspection (future)

codecs can expose their schema for documentation/validation:

```ferrule
type Schema = 
    | Object { fields: Array<FieldSchema> }
    | Array { items: Schema }
    | String
    | Number
    | Boolean
    | Null
    | OneOf { variants: Array<Schema> };

type SchemaProvider<T> = {
    schema: () -> Schema,
};

// for openapi generation
const User.schema: Schema = User.json.schema();
```

## drawbacks

- derive requires comptime (α2)
- attribute syntax adds complexity
- multiple format codecs per type could be confusing
- streaming api is more complex than simple `to_json()`

## alternatives

### runtime reflection

use runtime type info for serialization.

rejected: slow, no compile-time guarantees, doesn't fit ferrule's philosophy.

### schema-first (protobuf style)

define schemas in separate files, generate code.

rejected: external tooling, extra build step, not ergonomic.

### single format

just support json, add others later.

considered: simpler initially, but the abstraction is worth it for format-agnostic code.

### trait-based (rust serde)

use trait system with compiler magic.

not applicable: ferrule uses records, not traits. but the concept is similar.

## prior art

| system | approach | lesson |
|--------|----------|--------|
| rust serde | trait + derive macro | excellent abstraction, but complex macros |
| go encoding/json | struct tags + reflection | simple but runtime overhead |
| haskell aeson | typeclass + generics | clean but requires typeclass machinery |
| python pydantic | class + runtime validation | great dx, but runtime |
| typescript zod | schema-first | type inference is powerful |

serde's visitor pattern is elegant. this proposal simplifies by using reader/writer directly.

## unresolved questions

1. how to handle recursive types (tree structures)?
2. should there be a `Codec<T, Format>` with format as type parameter?
3. how to handle versioning (schema evolution)?
4. should `derive` be built-in or a stdlib comptime function?

## future possibilities

- binary format optimization (zero-copy, memory-mapped)
- schema evolution and migration
- json schema / openapi generation
- graphql type generation
- database orm integration
- rpc stub generation (grpc, json-rpc)
