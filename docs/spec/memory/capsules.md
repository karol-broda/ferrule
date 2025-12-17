# Capsules

> **scope:** unique resources, finalization, non-copy semantics  
> **related:** [regions.md](regions.md) | [views.md](views.md)

---

## Overview

**Capsule types** represent unique resources that:
- are **non-copy** by default
- require explicit duplication (if allowed by the type author)
- receive finalization calls on region disposal

---

## Non-Copy Semantics

Capsules cannot be implicitly copied:

```ferrule
const file: File = fs.open(path);
const copy = file;  // ERROR: File is a capsule type, cannot copy
```

If the type author provides a duplicator, explicit cloning is possible:

```ferrule
const copy = file.duplicate();  // only if File defines duplicate()
```

---

## Finalization

On region disposal, capsules receive a **finalize** call:
- finalization **cannot throw** — it always completes
- failures are emitted as status events to the observability subsystem
- finalization order follows allocation order (LIFO within a region)

```ferrule
type FileHandle = capsule {
  fd: i32,
  
  finalize: function(self) -> Unit {
    syscall.close(self.fd);
  }
};
```

---

## Registration

Capsules are automatically registered with their owning region:

```ferrule
const heap = region.heap();
const handle: FileHandle = heap.create_capsule(FileHandle { fd: fd });
defer heap.dispose();  // handle.finalize() called here
```

---

## Use Cases

- file handles
- network sockets
- device handles
- database connections
- any resource requiring explicit cleanup

---

## Secure Zeroing

For sensitive data, use secure zeroing that is **not** optimized away:

```ferrule
mem.secure_zero(secret_view);
```

Capsules holding secrets should call this in their finalizer.

---

## Constant-Time Operations

Types may be annotated as **constant-time**; branches on their values are linted:

```ferrule
type SecretKey = capsule {
  bytes: View<u8>,
  constant_time: true
};

// compiler warns if code branches on SecretKey contents
```


