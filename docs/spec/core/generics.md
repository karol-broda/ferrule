# Generics

> **scope:** type parameters, constraints, advanced generic features, polymorphism patterns  
> **related:** [types.md](types.md) | [../functions/syntax.md](../functions/syntax.md)

---

## Basic Generics

Type parameters in angle brackets:

```ferrule
type Box<T> = { value: T };

function identity<T>(x: T) -> T {
  return x;
}

function swap<T, U>(pair: { first: T, second: U }) -> { first: U, second: T } {
  return { first: pair.second, second: pair.first };
}
```

---

## Variance Annotations

Explicit variance for type parameters:

```ferrule
// out = covariant (producer, can only output T)
type Producer<out T> = { get: () -> T };

// in = contravariant (consumer, can only input T)
type Consumer<in T> = { accept: (T) -> Unit };

// invariant (default) — can both input and output
type Cell<T> = { get: () -> T, set: (T) -> Unit };
```

### Variance Rules

| Annotation | Meaning | Example |
|------------|---------|---------|
| `<out T>` | Covariant | `Producer<Cat>` assignable to `Producer<Animal>` |
| `<in T>` | Contravariant | `Consumer<Animal>` assignable to `Consumer<Cat>` |
| `<T>` | Invariant | No subtype relationship |

---

## Const Generics

Type-level values:

```ferrule
function chunk<T, const N: usize>(arr: View<T>) -> View<Array<T, N>> effects [alloc] {
  // split into chunks of size N
}

type Matrix<T, const ROWS: usize, const COLS: usize> = Array<Array<T, COLS>, ROWS>;

const m: Matrix<f64, 3, 3> = ...;
```

---

## Conditional Types

Type-level conditionals:

```ferrule
type Unwrap<T> = if T is Result<infer U, infer E> then U else T;

type IsString<T> = if T is String then true else false;
```

### The `infer` Keyword

Extract types from patterns:

```ferrule
type ReturnType<F> = if F is ((...args) -> infer R) then R else Never;

type ElementType<A> = if A is Array<infer T, infer N> then T else Never;

type ErrorType<R> = if R is Result<infer T, infer E> then E else Never;
```

### Non-Distributive by Default

Conditional types do NOT distribute over unions by default:

```ferrule
type ToArray<T> = Array<T>;
type X = ToArray<String | Number>;  // Array<String | Number>
```

Use `distribute` for distribution:

```ferrule
type Distributed<T> = distribute T { each U => Array<U> };
type Y = Distributed<String | Number>;  // Array<String> | Array<Number>
```

---

## Mapped Types

Transform type structure:

```ferrule
type Readonly<T> = map T { K => { readonly: true, type: T[K] } };

type Partial<T> = map T { K => { optional: true, type: T[K] } };

type Nullable<T> = map T { K => T[K]? };
```

---

## Template Literal Types

String manipulation at type level:

```ferrule
type EventName<T> = `on${Capitalize<T>}`;

type ClickEvent = EventName<"click">;  // "onClick"

type Getter<K> = `get${Capitalize<K>}`;
type Setter<K> = `set${Capitalize<K>}`;
```

---

## Variadic Generics

Variable number of type parameters:

```ferrule
function tuple<...Ts>(values: ...Ts) -> (...Ts) {
  return values;
}

function zip<...Ts>(arrays: ...View<Ts>) -> View<(...Ts)> effects [alloc] {
  // zip arrays together
}

// usage
const t = tuple(1, "hello", true);  // (i32, String, Bool)
const zipped = zip(numbers, strings);  // View<(i32, String)>
```

---

## Higher-Kinded Types

Type constructors as parameters:

```ferrule
// F<_> is a type that takes one type parameter
type Functor<F<_>> = {
  map: <A, B>(fa: F<A>, f: (A) -> B) -> F<B>
};

// implementations
const arrayFunctor: Functor<Array<_, N>> = {
  map: function<A, B>(arr: Array<A, N>, f: (A) -> B) -> Array<B, N> { ... }
};

const maybeFunctor: Functor<Maybe> = {
  map: function<A, B>(ma: Maybe<A>, f: (A) -> B) -> Maybe<B> {
    match ma {
      Some { value } -> Some { value: f(value) };
      None -> None;
    }
  }
};
```

---

## Polymorphism via Records

Ferrule uses **records + generics** for polymorphism instead of traits:

### Define Operation Records

```ferrule
type Eq<T> = { 
  eq: (T, T) -> Bool 
};

type Hash<T> = { 
  hash: (T) -> u64 
};

type Hashable<T> = Eq<T> & Hash<T>;

type Show<T> = { 
  show: (T) -> String 
};
```

### Create Implementations as Constants

```ferrule
type UserId = { id: u64 };

const UserId.eq: Eq<UserId> = {
  eq: function(a: UserId, b: UserId) -> Bool { return a.id == b.id; }
};

const UserId.hash: Hash<UserId> = {
  hash: function(u: UserId) -> u64 { return u.id; }
};

const UserId.hashable: Hashable<UserId> = {
  eq: UserId.eq.eq,
  hash: UserId.hash.hash
};

const UserId.show: Show<UserId> = {
  show: function(u: UserId) -> String { 
    return "User(" ++ u64.toString(u.id) ++ ")"; 
  }
};
```

### Use in Generic Functions

```ferrule
function dedupe<T>(items: View<T>, h: Hashable<T>) -> View<T> effects [alloc] {
  // use h.hash(item), h.eq(a, b)
}

function format<T>(items: View<T>, s: Show<T>) -> String {
  // use s.show(item)
}

// explicit usage
const unique = dedupe(users, UserId.hashable);
const output = format(users, UserId.show);
```

### Combine Operation Records

```ferrule
type HashShow<T> = Hashable<T> & Show<T>;

function dedupeAndPrint<T>(items: View<T>, hs: HashShow<T>) -> Unit effects [alloc, io] {
  const unique = dedupe(items, hs);
  for item in unique {
    io.println(hs.show(item));
  }
}
```

---

## Constraints on Type Parameters

Use `where` for constraints:

```ferrule
function sort<T>(items: View<mut T>, ord: Ord<T>) -> Unit 
  where T is Copy  // T must be copyable
{
  // ...
}
```

---

## Summary

| Feature | Syntax |
|---------|--------|
| Basic generics | `<T, U>` |
| Variance | `<out T>`, `<in T>` |
| Const generics | `<const N: usize>` |
| Conditional types | `if T is ... then ... else ...` |
| Infer | `infer R` in patterns |
| Mapped types | `map T { K => ... }` |
| Template literals | `` `prefix${T}suffix` `` |
| Variadic | `<...Ts>` |
| Higher-kinded | `<F<_>>` |
| Distribution | `distribute T { each U => ... }` |

