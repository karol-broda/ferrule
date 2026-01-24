---
title: worked examples
status: α1
---

# worked examples

---

## Parsing with Refinements

```ferrule
type Port = u16 where self >= 1 && self <= 65535;

error Invalid { message: String }
domain ParseError = Invalid;

use error ParseError;

function parsePort(s: String) -> Port error ParseError {
  const trimmed = text.trim(s);
  const n = check number.parse_u16(trimmed) with { op: "parse_u16" };
  
  if n < 1 || n > 65535 { 
    return err Invalid { message: "port out of range" };
  }
  
  return ok Port(n);
}
```

---

## File I/O with Capabilities

```ferrule
error NotFound { path: Path }
error Denied { path: Path }

domain IoError = NotFound | Denied;

function readAll(path: Path, cap fs: Fs) -> Bytes error IoError effects [fs] {
  const file = check fs.open(path);
  return check fs.readAll(file);
}

function writeConfig(config: Config, path: Path, cap fs: Fs) -> Unit error IoError effects [fs] {
  const data = serialize(config);
  return check fs.writeAll(path, data);
}
```

---

## Error Composition with Pick/Omit

```ferrule
error NotFound { path: Path }
error Denied { path: Path }
error Timeout { ms: u64 }
error ParseFailed { line: u32, message: String }

domain IoError = NotFound | Denied | Timeout;
domain ParseError = ParseFailed;
domain AppError = IoError | ParseError;

function loadConfig(p: Path, cap fs: Fs) -> Config error AppError effects [fs] {
  const bytes = map_error readAll(p, fs) 
                using (e => e);  // IoError is subset of AppError
  
  return map_error parser.config(bytes) 
         using (e => e);  // ParseError is subset of AppError
}

// function with precise errors using Pick
function quickRead(path: Path, cap fs: Fs) -> Bytes error Pick<IoError, NotFound | Denied> effects [fs] {
  // guaranteed not to timeout
}
```

---

## Polymorphism with Records

```ferrule
// operation records
type Hasher<T> = { 
  hash: (T) -> u64, 
  eq: (T, T) -> Bool 
};

type Showable<T> = { 
  show: (T) -> String 
};

// type definition
type UserId = { id: u64 };

// implementations as namespaced constants
const UserId.hasher: Hasher<UserId> = {
  hash: function(u: UserId) -> u64 { return u.id; },
  eq: function(a: UserId, b: UserId) -> Bool { return a.id == b.id; }
};

const UserId.show: Showable<UserId> = {
  show: function(u: UserId) -> String { 
    return "User(" ++ u64.toString(u.id) ++ ")"; 
  }
};

// generic function
function dedupe<T>(items: View<T>, h: Hasher<T>) -> View<T> effects [alloc] {
  // use h.hash(item), h.eq(a, b)
}

// usage — explicit
const unique = dedupe(users, UserId.hasher);
```

---

## HTTP Client with Timeout

```ferrule
error Timeout { url: Url, ms: u64 }
error Network { message: String }
error BadStatus { code: u32 }

domain FetchError = Timeout | Network | BadStatus;

function fetch(
  url: Url, 
  deadline: Time,
  cap net: Net,
  cap clock: Clock
) -> Response error FetchError effects [net, time] {
  const tok = cancel.token(deadline);
  
  const sock = map_error net.connect(url.host, url.port, tok)
               using (function(e: NetError) -> FetchError { 
                 return Timeout { url: url, ms: clock.until(deadline) };
               });
  
  return check request(sock, url, tok) with { op: "request" };
}
```

---

## Parallel Processing

```ferrule
function processAll(
  items: View<Item>,
  cap fs: Fs,
  cap clock: Clock
) -> View<Result> error ProcessError effects [fs, time, alloc] {
  
  const deadline = clock.now() + Duration.seconds(30);
  
  return task.scope(function(scope: Scope) -> View<Result> error ProcessError {
    const results = builder.new<Result>(region.current());
    
    for item in items {
      scope.spawn(function() -> Unit error ProcessError {
        const result = check processItem(item, fs);
        builder.push(results, result);
      });
    }
    
    check scope.awaitAll();
    return ok builder.finish(results);
  });
}
```

---

## Region Management

```ferrule
// copy to caller's region
function cloneToRegion(src: View<u8>, dstRegion: Region) -> View<u8> effects [alloc] {
  return view.copy(src, to = dstRegion);
}

// return region along with view
function cloneWithRegion(src: View<u8>) -> { data: View<u8>, region: Region } effects [alloc] {
  const heap = region.heap();
  const dst = view.copy(src, to = heap);
  return { data: dst, region: heap };
}

// arena for temporary allocations
function processWithArena(input: View<u8>) -> Output effects [alloc] {
  const arena = region.arena(1 << 20);  // 1MB
  defer arena.dispose();
  
  const temp = arena.alloc<u8>(input.len * 2);
  // use temp for intermediate work...
  
  // copy result to heap before arena is disposed
  const result = view.copy(output, to = region.heap());
  return result;
}
```

---

## Compile-Time Table Generation

```ferrule
comptime function crc16Table(poly: u16) -> Array<u16, 256> {
  var table: Array<u16, 256> = [0; 256];
  var i: u32 = 0;
  
  while i < 256 {
    var crc: u16 = u16(i) << 8;
    var j: u32 = 0;
    
    while j < 8 {
      if (crc & 0x8000) != 0 {
        crc = (crc << 1) ^ poly;
      } else {
        crc = crc << 1;
      }
      j = j + 1;
    }
    
    table[i] = crc;
    i = i + 1;
  }
  
  return table;
}

const CRC16_TABLE = comptime crc16Table(0x1021);

function crc16(data: View<u8>) -> u16 {
  var crc: u16 = 0xFFFF;
  
  for byte in data {
    const idx = ((crc >> 8) ^ u16(byte)) & 0xFF;
    crc = (crc << 8) ^ CRC16_TABLE[usize(idx)];
  }
  
  return crc;
}
```

---

## Context Ledgers

```ferrule
function handleRequest(req: Request, cap fs: Fs, cap net: Net) -> Response error AppError effects [fs, net] {
  with context { request_id: req.id, user_id: req.user } in {
    const config = check loadConfig(fs);
    const data = check fetchExternal(req.url, net);
    
    // all errors within this block carry request_id and user_id
    return ok processData(data, config);
  }
}
```

---

## Generics with Variance

```ferrule
// covariant — can only output T
type Producer<out T> = { get: () -> T };

// contravariant — can only input T  
type Consumer<in T> = { accept: (T) -> Unit };

// Producer<Cat> is assignable to Producer<Animal>
function printAnimal(p: Producer<Animal>, cap io: Io) -> Unit effects [io] {
  io.println(p.get().name);
}

const catProducer: Producer<Cat> = { get: function() -> Cat { return myCat; } };
printAnimal(catProducer, io);  // OK: Cat is Animal
```

---

## Conditional Types

```ferrule
type Unwrap<T> = if T is Result<infer U, infer E> then U else T;

type UnwrappedConfig = Unwrap<Result<Config, Error>>;  // Config

type ElementType<A> = if A is Array<infer T, infer N> then T else Never;

type StringElement = ElementType<Array<String, 10>>;  // String
```

---

## Higher-Order Functions with Effect Spread

```ferrule
function map<T, U>(arr: View<T>, f: (T) -> U) -> View<U> effects [alloc, ...] {
  const result = builder.new<U>(region.current());
  for item in arr {
    builder.push(result, f(item));
  }
  return builder.finish(result);
}

// caller's effects include alloc + whatever the passed function has
function processAll(items: View<Item>, cap fs: Fs) -> View<Output> effects [alloc, fs] {
  return map(items, function(item: Item) -> Output effects [fs] {
    return check fs.process(item);
  });
}
```
