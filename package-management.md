# Ferrule Package Management & Tooling

> **status:** alpha 1 draft  
> **scope:** package management, dependency resolution, build tooling, and developer experience

---

## Overview

Ferrule's package management is built on **content-addressed packages** with **human-readable manifests**. The system provides:

- **Reproducible builds** via content hashing and derivations
- **Simple declarative syntax** for common cases
- **Pinned versions by default** for stability
- **Full dependency DAG** with transparent transitive dependencies
- **Text-based lockfile** that's git-friendly and human-inspectable
- **Fast, modern tooling** with great UX
- **Extensibility** for complex build logic when needed

---

## 1. File Structure

```
my-project/
├── Package.fe              ← manifest (human-editable, declarative)
├── ferrule.lock            ← lockfile (generated, commit this)
├── build.fe                ← optional build script (full Ferrule)
└── src/
    └── main.fe             ← source files (.fe extension)
```

**Global cache location (standard OS paths):**

- Linux/Unix: `~/.cache/ferrule/`
- macOS: `~/Library/Caches/ferrule/`
- Windows: `%LOCALAPPDATA%\ferrule\cache\`

---

## 2. Package Manifest (`Package.fe`)

A **minimal DSL** (not full Ferrule) optimized for clarity and tooling:

```ferrule
package my.app : 0.1.0

// dependencies with pinned versions by default
require net.http      ~> 1.2.3
require data.json     ~> 2.0.1
require sys.epoll     ~> 1.0.0  when target.os == linux
require testing       ~> latest  scope dev

target x86_64-linux-musl {
  optimize = release
  features = [simd, lto]
}

build {
  entry  = src/main.fe
  output = bin/my-app
  tests  = tests/**/*.fe
}
```

### 2.1 Version Pinning (Default Behavior)

**Ferrule pins versions by default** to ensure reproducibility:

```ferrule
// when you run: ferrule add net.http
require net.http ~> 1.2.3    // ← exact version (pinned)

// you can explicitly allow updates:
require net.http >= 1.2.0 < 2.0.0    // semver range
require net.http ^> 1.2.0            // compatible updates (1.x.x)
require net.http ~> latest           // always latest (not recommended)
```

**Rationale:**

- Prevents surprise breakage from transitive updates
- Makes builds reproducible by default
- Explicit opt-in for version ranges
- Lockfile records exact content hashes regardless

### 2.2 Grammar (Simplified)

```ebnf
Manifest    := PackageDecl Requirement* Target* BuildConfig Extension?

PackageDecl := "package" Identifier ":" Version

Requirement := "require" Identifier VersionSpec Condition? Scope?

VersionSpec := "~>" Version              // exact (pinned)
            | "^>" Version               // compatible (^1.2.0 = >=1.2.0 <2.0.0)
            | ">=" Version "<" Version   // range
            | "~>" "latest"              // always latest (use sparingly)

Condition   := "when" Predicate
Scope       := "scope" ("dev" | "test" | "build")

Target      := "target" Triple "{" Setting* "}"
Setting     := Identifier "=" Value

BuildConfig := "build" "{" Setting* "}"

Extension   := "extend" Path
```

### 2.3 Design Principles

- **Declarative first** — most packages need no scripting
- **Minimal syntax** — easy to read, write, and parse
- **Line-oriented** — tools can safely append/modify
- **Git-friendly** — clean diffs, minimal conflicts
- **Type-safe** — validated against schema
- **Fast to parse** — simple recursive descent, no backtracking

---

## 3. Build Scripts (`build.fe`)

When you need custom logic, use **full Ferrule** in `build.fe`:

```ferrule
// build.fe - optional, for complex builds
package build;

import build { Context, Task };

export const prebuild = function(ctx: Context) -> Unit error BuildError effects [fs, alloc] {
  // generate protobuf code
  const proto = check codegen.protobuf("api.proto");
  check ctx.write_generated("api.fe", proto);
  return ok Unit;
};

export const postbuild = function(ctx: Context) -> Unit error BuildError effects [fs] {
  // copy assets
  check ctx.copy_dir("assets", ctx.output.join("assets"));
  return ok Unit;
};

export const custom_tasks: Array<Task, 2> = [
  { name: "lint", cmd: "ferrule-lint", args: ["--strict"] },
  { name: "bench", cmd: "ferrule-bench", args: ["--release"] }
];
```

Enable in `Package.fe`:

```ferrule
// reference build script
extend ./build.fe
```

---

## 4. Lockfile (`ferrule.lock`)

**Text-based format** with full dependency graph:

```toml
# ferrule.lock
# auto-generated - commit this file
# lockfile-version: 1

[root]
package = "my.app"
version = "0.1.0"
dependencies = [
  "net.http@1.2.3",
  "data.json@2.0.1",
  "sys.epoll@1.0.0"
]

[[package]]
name = "net.http"
version = "1.2.3"
source = "registry+https://registry.ferrule.dev/"
hash = "sha256:2f7c84a93fb1120ef5e8df9f3d7c9bb4a8c5e6d7f8a9b0c1d2e3f4g5h6i7j8k9"
derivation = "sha256:dead...beef"
dependencies = [
  "net.core@0.9.5",
  "data.bytes@1.1.0"
]

[[package]]
name = "net.core"
version = "0.9.5"
source = "registry+https://registry.ferrule.dev/"
hash = "sha256:a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2"
dependencies = []

[[package]]
name = "data.bytes"
version = "1.1.0"
source = "registry+https://registry.ferrule.dev/"
hash = "sha256:b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2g3"
dependencies = ["net.core@0.9.5"]

[[package]]
name = "data.json"
version = "2.0.1"
source = "registry+https://registry.ferrule.dev/"
hash = "sha256:c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2g3h4"
dependencies = ["data.bytes@1.1.0"]

[[package]]
name = "sys.epoll"
version = "1.0.0"
source = "registry+https://registry.ferrule.dev/"
hash = "sha256:d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2g3h4i5"
dependencies = []

[metadata]
resolved-at = "2025-10-20T10:30:00Z"
resolver-version = "1.0.0"
```

**Properties:**

- Human readable (text format)
- Git friendly (meaningful diffs, manageable merge conflicts)
- Full dependency DAG (complete transitive closure)
- Canonical ordering (alphabetically sorted, deterministic)
- Fast to parse (<1ms even for large projects)
- Standard TOML format
- Easy to inspect and debug (use standard tools: grep, diff, cat)
- Transparent (aligns with Ferrule's explicit control philosophy)

> [!NOTE]
> Ferrule uses a text-based lockfile instead of binary. While binary formats are slightly faster to parse, the benefits of transparency, inspectability, and git-friendliness far outweigh the negligible performance difference (<1ms). Modern package managers like Bun are also moving away from binary lockfiles for these reasons.

---

## 5. Content Addressing & Registry

### 5.1 Two-Level Addressing

**Human layer** (Package.fe):

```ferrule
require net.http ~> 1.2.3
```

**Machine layer** (lockfile):

```
net.http@1.2.3 → sha256:2f7c84a93fb1120ef5e8df9f3d7c9bb4a8c5e6d7...
```

### 5.2 Registry Structure

```
registry.ferrule.dev/
├── index/          ← searchable metadata (name, version, description)
├── packages/       ← source code (by content hash)
├── derivations/    ← build recipes (by hash)
├── artifacts/      ← pre-built binaries (by hash)
└── provenance/     ← build attestations & signatures
```

### 5.3 Resolution Flow

```
1. ferrule add net.http
   ↓
2. Query registry: net.http → latest stable version → 1.2.3
   ↓
3. Fetch metadata: dependencies, derivation
   ↓
4. Compute content hash: sha256:2f7c...
   ↓
5. Update Package.fe: require net.http ~> 1.2.3
   ↓
6. Update ferrule.lock: record package + hash + dependency DAG
   ↓
7. Fetch & cache: download to ~/.cache/ferrule/packages/sha256-2f7c.../
   ↓
8. Verify: check content matches hash
```

---

## 6. CLI Commands

### 6.1 Project Management

```bash
# create new project
ferrule new my-app
ferrule new my-lib --lib

# initialize in existing directory
ferrule init
```

### 6.2 Dependency Management

```bash
# add dependency (pins by default)
ferrule add net.http
# → adds: require net.http ~> 1.2.3 (latest at time of add)

# add with specific version
ferrule add net.http@1.2.0
# → adds: require net.http ~> 1.2.0

# add with version range
ferrule add net.http --range ">=1.2.0 <2.0.0"

# add dev dependency
ferrule add testing --dev
# → adds: require testing ~> 0.5.0 scope dev

# remove dependency
ferrule remove net.http

# update single package
ferrule update net.http
# → updates to latest compatible version
# → updates Package.fe and lockfile

# update all packages (interactive)
ferrule update
# → shows outdated packages
# → allows selection
# → shows changelogs
```

### 6.3 Lockfile Management

```bash
# generate/update lockfile
ferrule lock
# → resolves all dependencies
# → writes ferrule.lock with full dependency DAG

# verify lockfile integrity
ferrule lock --verify
# → checks hashes match content
# → fails if tampering detected

# show lockfile contents
ferrule lock --show
# → displays resolved versions and hashes
```

### 6.4 Building & Running

```bash
# build project
ferrule build
# → validates Package.fe
# → checks lockfile
# → fetches dependencies (parallel)
# → runs prebuild hooks
# → compiles
# → runs postbuild hooks

# build with specific target
ferrule build --target x86_64-linux-musl

# run project
ferrule run
ferrule run -- --arg value

# test project
ferrule test
ferrule test tests/integration.fe
```

### 6.5 Dependency Graph Inspection

```bash
# show full dependency tree
ferrule tree
my.app@0.1.0
├── net.http@1.2.3
│   ├── net.core@0.9.5
│   └── data.bytes@1.1.0
│       └── net.core@0.9.5 (*)
├── data.json@2.0.1
│   └── data.bytes@1.1.0 (*)
└── sys.epoll@1.0.0

(*) = shared dependency

# show why a package is included
ferrule why net.core
net.core@0.9.5 is required by:
  ├── net.http@1.2.3 (direct)
  └── data.bytes@1.1.0 (via data.json@2.0.1)

# show reverse dependencies
ferrule deps net.http
net.http@1.2.3 depends on:
  ├── net.core@0.9.5
  └── data.bytes@1.1.0
      └── net.core@0.9.5

# generate DOT graph for visualization
ferrule graph --dot > deps.dot
ferrule graph --dot | dot -Tpng > deps.png
ferrule graph --dot | dot -Tsvg > deps.svg

# show only direct dependencies
ferrule tree --depth 1

# show packages using specific version
ferrule using net.core@0.9.5
```

### 6.6 Package Distribution

```bash
# publish to registry
ferrule publish
# → validates package
# → runs derivation
# → computes content hash
# → uploads to registry
# → registers name → hash mapping

# vendor dependencies (offline builds)
ferrule vendor
# → downloads all dependencies to vendor/
# → builds use vendored packages
```

---

## 7. Modern Developer Experience

### 7.1 Interactive Workflows (Future Plan)

```bash
$ ferrule add
? Package name: █ (fuzzy search)
  net.http       - HTTP client/server
  net.websocket  - WebSocket protocol
  net.tls        - TLS implementation

? Version: (defaults to latest stable)
  → 1.2.3 (latest, 2 weeks ago)
    1.2.2 (3 months ago)
    1.2.1 (6 months ago)

? Add condition? (optional)
  [ ] Platform-specific (linux/darwin/windows)
  [ ] Feature flag
  [x] None

✓ Added net.http@1.2.3 (sha256:2f7c...)
```

### 7.2 Rich Information

```bash
$ ferrule info net.http
net.http@1.2.3
  HTTP client and server implementation

  Content Hash: sha256:2f7c84a93fb1120ef5e8df9f3d7c9bb4...
  Published:    2025-10-15
  License:      MIT
  Repository:   https://github.com/ferrule/net-http

  Dependencies:
    - net.core ~> 0.9.5
    - data.bytes ~> 1.1.0

  Features:
    - async     ✓ (default)
    - tls       ✓ (default)
    - http2     ✗ (optional)
    - compress  ✗ (optional)
```

---

## 8. LSP Integration

The Ferrule language server provides:

### 8.1 Package.fe Support

```ferrule
require net.█
        ↓ (ctrl+space)
// auto-complete from registry:
// - net.http
// - net.websocket
// - net.tls

require net.http ~> █
                    ↓ (ctrl+space)
// show available versions:
// - 1.2.3 (latest)
// - 1.2.2
// - 1.2.1
```

### 8.2 Inline Diagnostics

```ferrule
require net.http ~> 1.0.0
                    ^^^^^ warning: newer version available (1.2.3)
                          hint: run `ferrule update net.http`

require sys.epoll ~> 1.0.0
        ^^^^^^^^^ warning: unused dependency
                  hint: remove with `ferrule remove sys.epoll`
```

### 8.3 Jump to Definition

- Navigate from `import net.http` to cached package source
- Works across all dependencies
- Shows documentation on hover

---

## 9. Caching & Performance

### 9.1 Global Cache

**Standard OS locations:**

Linux/Unix:

```
~/.cache/ferrule/
├── packages/               ← content-addressed packages
│   ├── sha256-2f7c.../     ← net.http@1.2.3
│   ├── sha256-a1b2.../     ← data.json@2.0.1
│   └── ...
├── artifacts/              ← pre-built binaries
│   ├── sha256-3e8d.../     ← compiled artifacts
│   └── ...
└── registry/               ← registry cache
    └── index.db            ← local search index
```

macOS: `~/Library/Caches/ferrule/` (same structure)  
Windows: `%LOCALAPPDATA%\ferrule\cache\` (same structure)

### 9.2 Fast Operations

- **Parallel downloads** — fetch multiple packages concurrently
- **Incremental builds** — only rebuild changed modules
- **Shared cache** — one copy per content hash, shared across projects
- **Binary artifacts** — download pre-built when available
- **Offline mode** — use cached packages when network unavailable

---

## 10. Security & Provenance

### 10.1 Content Verification

Every package fetch:

1. Download by content hash
2. Verify hash matches content
3. Fail if mismatch detected
4. Cache verified content only

### 10.2 Provenance Tracking

```ferrule
// packages include provenance capsule
type Provenance = {
  sourceHash: Sha256Hash,
  derivationHash: Sha256Hash,
  buildInputs: {
    compiler: Tool,
    sysroot: Tool,
    timestamp: Time
  },
  signatures: Array<Signature, n>
};
```

### 10.3 Audit Commands

```bash
# show full dependency tree with hashes
ferrule audit tree

# check for known vulnerabilities
ferrule audit security

# verify all signatures
ferrule audit verify

# show build provenance
ferrule audit provenance net.http@1.2.3
```

---

## 11. Migration & Compatibility

### 11.1 From Other Ecosystems

```bash
# import from other package managers
ferrule import Cargo.toml      # Rust
ferrule import package.json    # Node
ferrule import go.mod          # Go

# generates Package.fe with equivalent dependencies
```

### 11.2 Workspace Support (Future)

```ferrule
// workspace root: Workspace.fe
workspace {
  members = [
    "crates/core",
    "crates/http",
    "crates/cli"
  ]

  shared {
    require testing ~> 0.5.0 scope dev
  }
}
```

---

## 12. Future Enhancements

### 12.1 Alpha 2

- Workspace support for mono-repos
- Private registry support
- Mirror/proxy configuration
- Build caching service
- Dependency vulnerability database

### 12.2 Beyond

- WASM component registry integration
- Binary artifact distribution
- Incremental compilation service
- Distributed build cache
- Package signing with hardware keys

---

## Appendix A: Complete Example

### Project Structure

```
http-server/
├── Package.fe
├── ferrule.lock
├── build.fe
├── src/
│   ├── main.fe
│   ├── server.fe
│   └── router.fe
└── tests/
    └── integration.fe
```

### `Package.fe`

```ferrule
package http.server : 0.1.0

require net.http      ~> 1.2.3
require data.json     ~> 2.0.1
require sys.signals   ~> 0.3.0  when target.os == linux
require testing       ~> 0.5.0  scope dev
require benchmarks    ~> 0.2.0  scope test

target x86_64-linux-musl {
  optimize = release
  features = [simd, lto]
}

target aarch64-darwin {
  optimize = release
  features = [simd]
}

build {
  entry  = src/main.fe
  output = bin/http-server
  tests  = tests/**/*.fe
}

extend ./build.fe
```

### `build.fe`

```ferrule
package build;

import build { Context, Task };

export const prebuild = function(ctx: Context) -> Unit error BuildError effects [fs, alloc] {
  const version = check ctx.package_version();
  const content = text.template("const VERSION: String = \"{version}\";", { version: version });
  check ctx.write_generated("version.fe", content);
  return ok Unit;
};

export const custom_tasks: Array<Task, 1> = [
  { name: "docker", cmd: "docker", args: ["build", "-t", "http-server", "."] }
];
```

### Usage

```bash
# setup
ferrule new http-server
cd http-server

# add dependencies (pinned by default)
ferrule add net.http
ferrule add data.json
ferrule add testing --dev

# develop
ferrule build
ferrule test
ferrule run

# release
ferrule build --release
ferrule publish
```

---

## Appendix B: Package.fe Schema

```ferrule
// for tooling/LSP, Package.fe has a formal schema

type PackageManifest = {
  package: PackageDecl,
  requirements: Array<Requirement, n>,
  targets: Array<TargetConfig, n>,
  build: BuildConfig,
  extension: Path?
};

type PackageDecl = {
  name: String,
  version: SemanticVersion
};

type Requirement = {
  name: String,
  version: VersionSpec,
  condition: Predicate?,
  scope: Scope?
};

type VersionSpec =
  | Pinned { version: SemanticVersion }
  | Compatible { version: SemanticVersion }
  | Range { min: SemanticVersion, max: SemanticVersion }
  | Latest;

type Scope = | Dev | Test | Build;

type TargetConfig = {
  triple: String,
  settings: Map<String, Value>
};

type BuildConfig = {
  entry: Path,
  output: Path,
  tests: Glob
};
```
