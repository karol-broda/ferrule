# Inline Assembly

> **scope:** typed inline assembly syntax, constraints, targets  
> **related:** [ffi.md](ffi.md) | [../functions/effects.md](../functions/effects.md)

---

## Overview

Ferrule provides **typed inline assembly** with explicit inputs, outputs, and clobbers.

---

## Basic Syntax

```ferrule
asm <target>
  in  { <input bindings> }
  out { <output bindings> }
  clobber [<clobbered registers>]
  [volatile] "<assembly code>";
```

---

## Example: RDTSC

```ferrule
function rdtsc() -> u64 effects [cpu] {
  asm x86_64
    in  {}
    out { lo: u32 in rax, hi: u32 in rdx }
    clobber [rcx, rbx]
    volatile "rdtsc";
  return (u64(hi) << 32) | u64(lo);
}
```

---

## Input Bindings

Bind Ferrule values to registers:

```ferrule
function add_asm(a: u64, b: u64) -> u64 effects [cpu] {
  asm x86_64
    in  { a: u64 in rdi, b: u64 in rsi }
    out { result: u64 in rax }
    clobber []
    "mov rax, rdi\nadd rax, rsi";
  return result;
}
```

---

## Output Bindings

Declare outputs with their types and registers:

```ferrule
out { name: Type in register }
```

Multiple outputs:

```ferrule
out { lo: u32 in eax, hi: u32 in edx }
```

---

## Clobbers

Declare registers modified by the assembly:

```ferrule
clobber [rax, rbx, rcx, memory, flags]
```

Special clobbers:
- `memory` — assembly may read/write memory
- `flags` — assembly modifies condition flags

---

## Volatile

Mark assembly that must not be optimized away:

```ferrule
asm x86_64
  in {}
  out {}
  clobber [memory]
  volatile "mfence";
```

---

## Supported Targets

| Target | Description |
|--------|-------------|
| `x86_64` | 64-bit x86 |
| `x86` | 32-bit x86 |
| `aarch64` | 64-bit ARM |
| `arm` | 32-bit ARM |
| `riscv64` | 64-bit RISC-V |
| `wasm32` | WebAssembly (limited) |

---

## Effect Requirement

Inline assembly requires the `cpu` effect:

```ferrule
function memory_fence() -> Unit effects [cpu] {
  asm x86_64
    in {}
    out {}
    clobber [memory]
    volatile "mfence";
}
```

---

## Example: CPUID

```ferrule
function cpuid(leaf: u32) -> { eax: u32, ebx: u32, ecx: u32, edx: u32 } effects [cpu] {
  asm x86_64
    in  { leaf: u32 in eax }
    out { 
      out_eax: u32 in eax, 
      out_ebx: u32 in ebx, 
      out_ecx: u32 in ecx, 
      out_edx: u32 in edx 
    }
    clobber []
    "cpuid";
  return { 
    eax: out_eax, 
    ebx: out_ebx, 
    ecx: out_ecx, 
    edx: out_edx 
  };
}
```

---

## Example: Atomic Compare-Exchange

```ferrule
function cas(ptr: *u64, expected: u64, desired: u64) -> Bool effects [cpu, atomics] {
  asm x86_64
    in  { 
      ptr: *u64 in rdi, 
      expected: u64 in rax, 
      desired: u64 in rcx 
    }
    out { success: u8 in al }
    clobber [memory, flags]
    volatile "lock cmpxchg [rdi], rcx\nsete al";
  return success !== 0;
}
```

---

## Feature Gate

Inline assembly may be behind a feature gate in early toolchains:

```ferrule
// in Package.fe
target x86_64-linux {
  features = [inline_asm]
}
```


