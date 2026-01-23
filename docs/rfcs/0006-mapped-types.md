---
rfc: 0006
title: mapped types
status: draft
created: 2026-01-23
target: β
depends: [0003]
---

# RFC-0006: mapped types

## summary

mapped types allow transforming the shape of record types at the type level, enabling patterns like making all fields optional, readonly, or transforming field types.

## motivation

common patterns require creating variations of existing types:

```ferrule
type User = {
  id: u64,
  name: string,
  email: string,
};

// manual partial type
type PartialUser = {
  id: Option<u64>,
  name: Option<string>,
  email: Option<string>,
};

// manual readonly type
type ReadonlyUser = {
  const id: u64,
  const name: string,
  const email: string,
};
```

with mapped types:

```ferrule
type PartialUser = Partial<User>;
type ReadonlyUser = Readonly<User>;
```

## detailed design

### basic syntax

mapped types iterate over the fields of a type:

```ferrule
type Partial<T> = {
  [K in keyof T]: Option<T[K]>,
};

type Readonly<T> = {
  const [K in keyof T]: T[K],
};
```

### keyof operator

`keyof T` produces a union of field name types:

```ferrule
type UserKeys = keyof User;  // "id" | "name" | "email"
```

### field access

`T[K]` accesses the type of field K in T:

```ferrule
type IdType = User["id"];  // u64
```

### modifiers

mapped types can add or remove modifiers:

```ferrule
// add const (readonly)
type Readonly<T> = {
  const [K in keyof T]: T[K],
};

// remove const (mutable)
type Mutable<T> = {
  var [K in keyof T]: T[K],
};

// add optional
type Partial<T> = {
  [K in keyof T]?: T[K],
};

// remove optional (required)
type Required<T> = {
  [K in keyof T]-?: T[K],
};
```

### standard mapped types

built into the prelude:

```ferrule
type Partial<T>   // all fields optional
type Required<T>  // all fields required
type Readonly<T>  // all fields const
type Mutable<T>   // all fields var
type Pick<T, K>   // subset of fields
type Omit<T, K>   // exclude fields
```

### pick and omit

select or exclude specific fields:

```ferrule
type UserCredentials = Pick<User, "email" | "password">;
// { email: string, password: string }

type PublicUser = Omit<User, "password" | "email">;
// { id: u64, name: string }
```

### transforming field types

change the type of all fields:

```ferrule
type Nullable<T> = {
  [K in keyof T]: Option<T[K]>,
};

type Promisified<T> = {
  [K in keyof T]: Promise<T[K]>,
};
```

### conditional mapping

combine with conditional types (RFC-0007):

```ferrule
type FunctionsOnly<T> = {
  [K in keyof T as T[K] extends function ? K : never]: T[K],
};
```

## drawbacks

- significant type system complexity
- harder to understand error messages
- potential for abuse creating complex type gymnastics

## alternatives

### comptime type generation

use comptime to generate types:

```ferrule
comptime type Partial<T> = generate_partial(T);
```

more flexible but less type-safe.

### manual type definitions

just write out the types manually.

fine for one-offs but doesn't scale.

## prior art

| language | feature |
|----------|---------|
| typescript | mapped types, keyof, indexed access |
| flow | $Keys, $Values |
| scala 3 | match types |

typescript's mapped types are the direct inspiration.

## unresolved questions

1. how do mapped types interact with generics?
2. should we allow computed field names?
3. how do we display mapped types in error messages?

## future possibilities

- key remapping (`as` clause)
- recursive mapped types
- template literal types for field names
