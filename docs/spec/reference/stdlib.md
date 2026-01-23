---
title: standard library
status: α1
implemented:
  - basic-io
  - result-maybe
pending:
  - file-system
  - math
  - text
deferred:
  - network (α2)
  - concurrency (β)
  - simd (β)
---

# standard library

the standard library is organized in layers. lower layers are always available, higher layers need explicit imports.

## layer 1: intrinsics

intrinsics are built into the compiler. they're accessed with `@` prefix, no import needed.

```ferrule
@sizeOf<T>()           // size in bytes
@alignOf<T>()          // alignment
@typeInfo<T>()         // type reflection
@intToPtr<*T>(addr)    // address to pointer
@ptrToInt(ptr)         // pointer to address
@bitCast<T>(val)       // reinterpret bits
@compileError(msg)     // compile-time error
```

intrinsics are implemented directly in the compiler, generating llvm ir.

## layer 2: core (prelude)

core types are automatically in scope for all files. no import needed.

```ferrule
// primitives
type Bool;
type Char;
type String;
type Unit;
type Never;

// integers
type i8, i16, i32, i64, i128;
type u8, u16, u32, u64, u128, usize;

// floats
type f32, f64;

// containers
type Result<T, E>;
type Maybe<T>;
type Array<T, const N: usize>;
type View<T>;
type View<mut T>;
```

## layer 3: std (explicit import)

standard library modules. must be imported.

```ferrule
import std.io { println, print, stdin, stdout };
import std.fs { File, readFile, writeFile };
import std.text { format, split, join };
import std.math { sin, cos, sqrt, PI };
import std.mem { copy, zero };
import std.collections { Vec, HashMap };
```

## layer 4: platform (explicit import)

platform-specific apis.

```ferrule
import std.os.linux { syscall, mmap };
import std.os.windows { CreateFile };
import std.embedded.arm { NVIC, SCB };
```

## how it fits together

user code calls stdlib functions. stdlib functions call runtime functions (implemented in zig). runtime functions call the os.

example flow for `println("hi")`:
1. user calls `println("hi")`
2. `std.io.println` receives the call
3. `std.io.println` calls `rt_println(ptr, len)` (extern to zig)
4. zig runtime's `rt_println` calls `write(STDOUT, ptr, len)`

ferrule files define the api. zig runtime provides the implementation. intrinsics bridge the gap for low-level operations.

## io

requires `io` effect and `Io` capability.

```ferrule
io.println(message)     // print line to stdout
io.print(message)       // print without newline
io.eprintln(message)    // print to stderr
io.read_line()          // read line from stdin
io.flush()              // flush stdout
```

## file system

requires `fs` effect and `Fs` capability.

```ferrule
fs.open(path)           // open file
fs.create(path)         // create file
fs.read_all(file)       // read entire file
fs.read_all_text(path)  // read as string
fs.write_all(path, data)
fs.exists(path)
fs.remove(path)
fs.mkdir(path)
fs.read_dir(path)
```

## text

```ferrule
text.trim(s)
text.split(s, delim)
text.join(parts, sep)
text.contains(s, substr)
text.starts_with(s, prefix)
text.ends_with(s, suffix)
text.to_upper(s)
text.to_lower(s)
```

## math

```ferrule
math.abs(x)
math.min(a, b)
math.max(a, b)
math.clamp(x, min, max)
math.sqrt(x)
math.pow(base, exp)
math.sin(x)
math.cos(x)
math.floor(x)
math.ceil(x)
math.round(x)
math.PI
math.E
```

## memory

```ferrule
mem.copy(dst, src)
mem.set(dst, value)
mem.secure_zero(view)   // not optimized away
mem.compare(a, b)
```

## layout

```ferrule
layout.sizeof<T>()
layout.alignof<T>()
layout.page_size()
layout.cache_line_size()
```

## embedded support

for embedded/bare metal, skip the runtime:

```ferrule
#![no_std]
#![no_runtime]

// no stdlib imports available
// must use intrinsics directly

const UART: *volatile u32 = @intToPtr(*volatile u32, 0x4000_0000);

function uart_write(byte: u8) -> Unit {
    unsafe {
        UART.* = @as(u32, byte);
    }
}

function main() -> Never {
    uart_write('H');
    loop {}
}
```

## statics

for global state:

```ferrule
static BUFFER: Array<u8, 1024> = [0; 1024];
static CONFIG: Config = Config { baud: 9600 };

// mutable statics require unsafe
static mut COUNTER: u32 = 0;

unsafe {
    COUNTER = COUNTER + 1;
}
```

## extern structs

for c-compatible layout:

```ferrule
type CHeader = extern {
    magic: u32,
    version: u16,
    flags: u16,
};
```

## packed structs

for bit-level layout:

```ferrule
type NetworkHeader = packed {
    version: u4,
    ihl: u4,
    dscp: u6,
    ecn: u2,
};
```

## volatile

for memory-mapped io:

```ferrule
type UartRegisters = extern {
    data: volatile u32,
    status: volatile u32,
    control: volatile u32,
};
```

## what's planned

**network** (α2):
```ferrule
net.connect(host, port)
net.listen(addr)
sock.read(buf)
sock.write(data)
```

**time** (α2):
```ferrule
clock.now()
clock.sleep(duration)
Duration.seconds(n)
Duration.ms(n)
```

**randomness** (α2):
```ferrule
rng.u32()
rng.range(min, max)
rng.bytes(view)
```

**testing** (α2):
```ferrule
test "description" {
    assert_eq(result, expected);
}
```

**simd** (β):
```ferrule
simd.add(a, b)
simd.mul(a, b)
simd.reduce_add(v)
```

## stdlib structure

| path | purpose |
|------|---------|
| `stdlib/core/prelude.fe` | auto-imported types |
| `stdlib/core/intrinsics.fe` | wrappers around @builtins |
| `stdlib/std/io.fe` | i/o operations |
| `stdlib/std/fs.fe` | file system |
| `stdlib/std/text.fe` | string manipulation |
| `stdlib/std/math.fe` | math functions |
| `stdlib/std/mem.fe` | memory operations |
| `stdlib/std/collections/vec.fe` | vector type |
| `stdlib/std/collections/hashmap.fe` | hash map type |
| `stdlib/runtime/runtime.zig` | zig runtime support |
