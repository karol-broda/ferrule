---
title: capabilities
status: α1
implemented: []
pending:
  - cap-parameter-syntax
  - with-cap-syntax
  - capability-flow-lint
  - linear-constraints
deferred:
  - capability-attenuation (α2)
  - capability-restriction (α2)
---

# capabilities

ferrule has no ambient authority. file system, network, clock, and rng access are values you pass, not globals you access. this is enforced at compile time.

## why capabilities

most languages give you global access to everything. you can open files, make network requests, read the clock, anywhere in your code. this makes auditing hard: to know what a function does, you have to read all the code it calls.

capabilities flip this. a function can only do io if someone passed it the authority to do so. you can tell from the signature what a function might do.

## standard capabilities

| capability | effect | what it does |
|------------|--------|--------------|
| `Io` | `io` | stdin, stdout, stderr |
| `Fs` | `fs` | file system operations |
| `Net` | `net` | network operations |
| `Clock` | `time` | time access, sleep |
| `Rng` | `rng` | randomness |

## entry point: with cap syntax

main receives capabilities via special syntax:

```ferrule
function main(args: Args) -> i32 
    with cap io: Io, cap fs: Fs, cap net: Net, cap clock: Clock
{
    // capabilities available here
    println("hello", io);
    
    const config = loadConfig("config.json", fs);
    
    return 0;
}
```

the `with cap` syntax is special to main. it's where capabilities enter your program. the runtime constructs them from os resources and passes them in.

## other functions: explicit parameters

everywhere else, capabilities are explicit parameters:

```ferrule
function loadConfig(path: String, cap fs: Fs) -> Config error IoError effects [fs] {
    const data = check fs.readFile(path);
    return ok parseConfig(data);
}
```

the `cap` keyword marks a parameter as a capability. this enables flow analysis and makes it clear what authority the function needs.

## capability flow lint

if a function has an effect, it must have the corresponding capability somewhere in the call chain:

```ferrule
function sneaky() -> Unit effects [fs] {
    fs.readFile("secret.txt");  // error: fs not in scope
}
```

the compiler traces capability flow. if you declare an effect, you must either:
1. have a cap parameter for it, or
2. call a function that has the cap

## linear constraints

capabilities can't be stored or returned:

```ferrule
// error: can't store capability in struct
type Bad = {
    io: Io,
};

// error: can't return capability
function steal(cap io: Io) -> Io {
    return io;
}

// error: can't put in array
const caps: Array<Io, 2> = [io, io];
  
// error: can't assign to non-cap variable
const my_io = io;
```

this prevents capability leakage. you can only pass capabilities down the call stack, never sideways or up.

## borrowing vs consuming

by default, passing a capability borrows it:

```ferrule
function main() with cap io: Io {
    helper(io);   // borrow io
    helper(io);   // borrow again, ok
}

function helper(cap io: Io) -> Unit effects [io] {
    println("hello", io);
}
```

you can pass the same capability to multiple calls. the callee borrows it for the duration of the call.

to consume a capability (rare), use `cap move`:

```ferrule
function consumeIo(cap move io: Io) -> Unit {
    // io is consumed, caller loses it
}

function main() with cap io: Io {
    consumeIo(io);  // move
    // helper(io);  // error: io was moved
}
```

## what you can do

```ferrule
// pass to functions (borrow)
println("hello", io);

// pass to nested scopes
if condition {
    println("in branch", io);
}

// pass to closures (if closure doesn't escape)
items.forEach(function(item: Item) -> Unit {
    println(item.name, io);
});
```

## testing with mock capabilities

capabilities make testing easy. inject fakes:

```ferrule
test "handles file not found" {
    const mockFs = testing.mockFs({
        "/config.json": None,  // file doesn't exist
    });
    
    const result = loadConfig("/config.json", mockFs);
    assert(result.isErr());
}
```

you can test io code without touching the real filesystem.

## effects vs capabilities

effects and capabilities are related but different:

| concept | what it is | when checked |
|---------|------------|--------------|
| effect | marker for what might happen | compile-time subset rule |
| capability | authority value to do something | compile-time flow analysis |

some effects need capabilities:
- `fs` needs `Fs`
- `net` needs `Net`
- `time` needs `Clock`

some effects don't need capabilities:
- `alloc` just marks allocation
- `atomics` just marks atomic operations
- `simd` just marks simd usage

see [../functions/effects.md](/docs/functions/effects) for more on effects.

## what's planned

**capability attenuation** (α2) lets you create restricted capabilities:

```ferrule
const readOnlyFs = fs.restrict({ write: false, delete: false });
sandboxedFunction(readOnlyFs);  // can only read files
```

this is useful for sandboxing untrusted code.
