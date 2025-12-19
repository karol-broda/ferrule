current state:
```bash
➜ ./zig-out/bin/ferrule examples/fizzbuzz.fe
=== compiling examples/fizzbuzz.fe ===
parsed successfully
=== semantic analysis ===
semantic analysis completed: 1 statements typed
=== code generation ===
=== compilation complete ===

➜ ./out/fizzbuzz
fizzbuzz from 1 to 30:

1
2
fizz
4
buzz
...
fizzbuzz

done
```

## features

### i/o builtins

| function | type |
|----------|------|
| `println(s: String)` | `() effects [io]` |
| `print(s: String)` | `() effects [io]` |
| `print_i32(v: i32)` | `() effects [io]` |
| `print_i64(v: i64)` | `() effects [io]` |
| `print_f64(v: f64)` | `() effects [io]` |
| `print_bool(v: Bool)` | `() effects [io]` |
| `print_newline()` | `() effects [io]` |
| `read_char()` | `i32 effects [io]` |

### control flow

- `if cond { } else if cond { } else { }`
- `while cond { }`
- `for i in 0..10 { }` (range loops)
- `for x in array { }` (array iteration)

### types

- scalars: `i8`, `i16`, `i32`, `i64`, `u8`, `u16`, `u32`, `u64`, `f32`, `f64`, `Bool`
- `String`, `Array`
- ranges: `0..10`

### operators

- arithmetic: `+`, `-`, `*`, `/`, `%`
- comparison: `==`, `!=`, `<`, `>`, `<=`, `>=`
- logical: `&&`, `||`

## build

```bash
nix develop --command zig build
./zig-out/bin/ferrule examples/fizzbuzz.fe
./out/fizzbuzz
```

## examples

```ferrule
// fizzbuzz with for-range
function main() -> i32 effects [io] {
  for i in 1..31 {
    const by3 = i % 3 == 0;
    const by5 = i % 5 == 0;

    if by3 && by5 {
      println("fizzbuzz");
    } else if by3 {
      println("fizz");
    } else if by5 {
      println("buzz");
    } else {
      print_i32(i);
      print_newline();
    }
  }
  return 0;
}
```

```ferrule
// array iteration
function main() -> i32 effects [io] {
  const numbers = [1, 2, 3, 4, 5];
  var sum: i32 = 0;
  for n in numbers {
    sum = sum + n;
  }
  print_i32(sum); // 15
  return 0;
}
```

```ferrule
// stdin reading
function main() -> i32 effects [io] {
  const c = read_char();
  print_i32(c); // ascii code
  return 0;
}
```
