# Data-Oriented Performance

> **scope:** shapers, SIMD types, prefetch hints, cache optimization  
> **related:** [../memory/views.md](../memory/views.md) | [../functions/effects.md](../functions/effects.md)

---

## Shapers (AoS ↔ SoA)

Declaratively convert between Array-of-Structs and Struct-of-Arrays:

```ferrule
shaper to_soa<T> { 
  input: Array<T>, 
  output: { fields: each T } 
}
```

### Example

```ferrule
type Particle = { x: f32, y: f32, z: f32, mass: f32 };

// AoS layout
const particles: Array<Particle, 1000> = ...;

// convert to SoA for SIMD-friendly access
const soa = shaper.to_soa(particles);
// soa.x: Array<f32, 1000>
// soa.y: Array<f32, 1000>
// soa.z: Array<f32, 1000>
// soa.mass: Array<f32, 1000>
```

---

## SIMD Types

### Vector Types

```ferrule
Vector<T, n>   // SIMD vector of n elements of type T
Mask<n>        // boolean mask for vector operations
```

### Operations

```ferrule
const a: Vector<f32, 4> = [1.0, 2.0, 3.0, 4.0];
const b: Vector<f32, 4> = [5.0, 6.0, 7.0, 8.0];

const sum = simd.add(a, b);       // element-wise add
const prod = simd.mul(a, b);      // element-wise multiply
const dot = simd.reduce_add(simd.mul(a, b));  // dot product
```

### Masking

```ferrule
const mask: Mask<4> = simd.gt(a, b);  // a > b element-wise
const selected = simd.select(mask, a, b);  // conditional select
```

### Effect Requirement

SIMD operations require the `simd` effect:

```ferrule
function dot_product(a: View<f32>, b: View<f32>) -> f32 effects [simd] {
  // ...
}
```

---

## Fallback Scalarization

When SIMD is unavailable, operations fall back to scalar code. This is **explicit in diagnostics**:

```
warning: simd operation scalarized
  ┌─ src/math.fe:42:12
  │
42│   const sum = simd.add(a, b);
  │               ^^^^^^^^^^^^^^ target lacks AVX support, using scalar fallback
```

---

## Prefetch & Cache Hints

Portable intrinsics that degrade gracefully:

```ferrule
function process_large_array(data: View<f32>) -> f32 effects [simd] {
  var sum: f32 = 0.0;
  var i: usize = 0;
  
  while i < data.len {
    // hint: prefetch data 256 elements ahead
    cache.prefetch(data, offset = i + 256, locality = L1);
    
    sum = sum + data[i];
    i = i + 1;
  }
  
  return sum;
}
```

### Prefetch Localities

| Locality | Meaning |
|----------|---------|
| `L1` | prefetch to L1 cache |
| `L2` | prefetch to L2 cache |
| `L3` | prefetch to L3 cache |
| `NTA` | non-temporal (streaming) |

### Graceful Degradation

On platforms without prefetch support, hints are no-ops.

---

## Cache-Aligned Allocation

```ferrule
const aligned_buf = region.heap().alloc_aligned<f32>(
  count = 1024,
  align = layout.cache_line_size()
);
```

---

## Memory Ordering Hints

```ferrule
// hint: this loop accesses memory sequentially
for i in 0..data.len {
  // compiler may optimize for sequential access
  process(data[i]);
}

// hint: random access pattern
for idx in shuffled_indices {
  // compiler won't assume locality
  process(data[idx]);
}
```

---

## Hot/Cold Path Hints

```ferrule
function process(x: i32) -> i32 {
  if x === 0 {
    // cold path: rarely taken
    @cold {
      return handle_zero();
    }
  }
  
  // hot path: common case
  return x * 2;
}
```

---

## Example: SIMD Vector Normalization

```ferrule
function normalize(v: View<mut f32>) -> Unit effects [simd] {
  // compute magnitude squared
  var mag_sq: f32 = 0.0;
  for x in v {
    mag_sq = mag_sq + x * x;
  }
  
  const mag = math.sqrt(mag_sq);
  
  if mag === 0.0 {
    return;
  }
  
  const inv_mag = 1.0 / mag;
  
  // normalize in-place using SIMD
  const chunks = v.len / 4;
  var i: usize = 0;
  while i < chunks {
    const vec = simd.load<f32, 4>(v, offset = i * 4);
    const scaled = simd.mul_scalar(vec, inv_mag);
    simd.store(v, offset = i * 4, scaled);
    i = i + 1;
  }
  
  // handle remainder
  i = chunks * 4;
  while i < v.len {
    v[i] = v[i] * inv_mag;
    i = i + 1;
  }
}
```


