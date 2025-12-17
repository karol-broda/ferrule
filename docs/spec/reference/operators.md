# Operators

> **scope:** operator precedence, semantics, typing rules  
> **related:** [grammar.md](grammar.md) | [../core/types.md](../core/types.md)

---

## Precedence Table (Low to High)

| Precedence | Operator | Associativity | Description |
|------------|----------|---------------|-------------|
| 1 | `\|\|` | left | logical or |
| 2 | `&&` | left | logical and |
| 3 | `==` `!=` | left | equality |
| 4 | `<` `<=` `>` `>=` | left | comparison |
| 5 | `\|` | left | bitwise or |
| 6 | `^` | left | bitwise xor |
| 7 | `&` | left | bitwise and |
| 8 | `<<` `>>` | left | shift |
| 9 | `+` `-` | left | additive |
| 10 | `*` `/` `%` | left | multiplicative |
| 11 | `!` `-` `~` | right | prefix (unary) |
| 12 | `()` `.` `[]` | left | postfix |

---

## Arithmetic Operators

```ferrule
x + y    // addition
x - y    // subtraction
x * y    // multiplication
x / y    // division
x % y    // remainder
-x       // negation
```

**Rules:**
- Operands must have the same numeric type
- No implicit widening or narrowing
- Explicit casts required: `u32(x)`, `i64(y)`

---

## Bitwise Operators

```ferrule
x & y    // bitwise and
x | y    // bitwise or
x ^ y    // bitwise xor
~x       // bitwise not
x << n   // left shift
x >> n   // right shift (arithmetic for signed, logical for unsigned)
```

**Rules:**
- Operands must be integer types
- Shift amount requires explicit cast to operand width

---

## Logical Operators

```ferrule
a && b   // logical and (short-circuit)
a || b   // logical or (short-circuit)
!a       // logical not
```

**Rules:**
- Operands must be `Bool`
- No implicit boolean coercion

---

## Comparison Operators

### Equality

```ferrule
x == y   // equality
x != y   // inequality
```

**Semantics:**
- Scalars: value comparison
- Records: field-by-field comparison
- Unions: tag + payload comparison
- Views: pointer + length + region comparison

### Ordering

```ferrule
x < y    // less than
x <= y   // less than or equal
x > y    // greater than
x >= y   // greater than or equal
```

**Rules:**
- Operands must have the same type
- Type must implement ordering (numeric types, `Char`)

---

## No Implicit Coercion

Ferrule does **not** perform implicit type coercion:

```ferrule
// WRONG
const x: i32 = 5;
const y: i64 = x;        // ERROR: type mismatch

// CORRECT
const y: i64 = i64(x);   // explicit cast
```

```ferrule
// WRONG
if count { ... }         // ERROR: expected Bool, found i32

// CORRECT
if count != 0 { ... }    // explicit comparison
```

---

## Type Casting

Explicit casts use type constructor syntax:

```ferrule
const a: i32 = 100;
const b: i64 = i64(a);   // widening
const c: i16 = i16(a);   // narrowing (may truncate)
const d: f64 = f64(a);   // int to float
const e: i32 = i32(d);   // float to int (truncates)
```

---

## String Concatenation

```ferrule
const greeting = "Hello, " ++ name ++ "!";
```

The `++` operator concatenates strings. Both operands must be `String`.

---

## Operator Overloading

α1 does **not** support user-defined operator overloading. Operators have fixed semantics for built-in types.

---

## Summary

| Category | Operators | Operand Types |
|----------|-----------|---------------|
| arithmetic | `+ - * / %` | numeric |
| bitwise | `& \| ^ ~ << >>` | integer |
| logical | `&& \|\| !` | `Bool` |
| equality | `== !=` | any (same type) |
| ordering | `< <= > >=` | ordered types |
| string | `++` | `String` |
