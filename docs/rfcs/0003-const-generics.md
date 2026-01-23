---
rfc: 0003
title: const generics
status: draft
created: 2026-01-23
target: α2
---

# RFC-0003: const generics

## summary

const generics allow type parameters to include compile-time constant values, enabling fixed-size arrays, matrices, and other parameterized-by-value types.

## motivation

currently, arrays in ferrule must have their size specified at the type level with a literal:

```ferrule
const buffer: Array<u8, 1024> = [...];
```

there's no way to write a function that works with arrays of any size:

```ferrule
// we want this, but can't express it today
function sum<const N: usize>(arr: Array<i32, N>) -> i32 { ... }
```

const generics enable:
- generic functions over fixed-size containers
- matrices with compile-time dimensions
- ring buffers, fixed-capacity vectors
- simd abstractions

## detailed design

### syntax

const parameters use the `const` keyword in the generic parameter list:

```ferrule
type Matrix<T, const ROWS: usize, const COLS: usize> = {
  data: Array<Array<T, COLS>, ROWS>,
};

function zeros<const ROWS: usize, const COLS: usize>() -> Matrix<f64, ROWS, COLS> {
  return Matrix {
    data: [[0.0; COLS]; ROWS],
  };
}

const m: Matrix<f64, 3, 4> = zeros();
```

### allowed const types

const parameters can be any of these types:
- integer types: `i8`, `i16`, `i32`, `i64`, `i128`, `isize`
- unsigned types: `u8`, `u16`, `u32`, `u64`, `u128`, `usize`
- `bool`
- `char`

### const expressions

const parameters can use expressions that are evaluable at compile time:

```ferrule
type AlignedBuffer<const SIZE: usize> = {
  data: Array<u8, align_up(SIZE, 64)>,
};

function align_up(size: usize, alignment: usize) -> usize {
  return (size + alignment - 1) & ~(alignment - 1);
}
```

the expression must be evaluable with only const inputs.

### inference

const parameters can be inferred from usage:

```ferrule
function length<T, const N: usize>(arr: Array<T, N>) -> usize {
  return N;
}

const arr = [1, 2, 3, 4, 5];
const len = length(arr);  // N inferred as 5
```

### constraints

const parameters cannot use where clauses in α2. this is future work:

```ferrule
// future: const constraints
function safe_divide<const D: i32>(n: i32) -> i32
  where D != 0
{
  return n / D;
}
```

### monomorphization

each unique combination of const parameters creates a separate monomorphized function:

```ferrule
const a = zeros<2, 3>();  // generates zeros_2_3
const b = zeros<4, 4>();  // generates zeros_4_4
```

## drawbacks

- increases binary size with many specializations
- adds complexity to type checking
- inference can be ambiguous in some cases

## alternatives

### macros instead of const generics

generate code with comptime macros:

```ferrule
comptime function make_matrix(rows: usize, cols: usize) { ... }
```

rejected because it doesn't provide the same type safety and ergonomics.

### only literal sizes

require all sizes to be literals, no generics:

```ferrule
const arr: Array<i32, 10> = [...];
```

rejected because it prevents abstracting over array sizes.

## prior art

| language | feature |
|----------|---------|
| rust | `const N: usize` in generics |
| c++ | non-type template parameters |
| zig | comptime parameters |
| d | template value parameters |

rust's approach is most similar to this proposal. zig's comptime is more powerful but less explicit.

## unresolved questions

1. should we allow const parameters in where clauses?
2. how do we handle const parameters in error messages?
3. should const expressions support all operators or a subset?

## future possibilities

- const constraints (`where N > 0`)
- associated const values in interfaces
- const parameter inference from return types
