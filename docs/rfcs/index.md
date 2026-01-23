---
title: rfcs
status: active
---

# ferrule rfcs

rfcs (request for comments) describe features that are proposed but not yet part of the core specification. they represent future directions for the language.

## what is an rfc?

an rfc is a design document for a feature that:
- is too large or risky for the current milestone
- needs community feedback before commitment
- represents a significant change to the language

rfcs are not commitments. they may be accepted, modified, or rejected.

## rfc status

| status | meaning |
|--------|---------|
| draft | initial proposal, open for feedback |
| accepted | will be implemented in target version |
| implemented | merged into main spec |
| rejected | decided against |
| deferred | good idea, but not now |

## active rfcs

### α2 target

| rfc | title | status |
|-----|-------|--------|
| [0001](0001-error-transformation) | error transformation (map_error) | draft |
| [0002](0002-debug-context) | debug context frames | draft |
| [0003](0003-const-generics) | const generics | draft |

### β target

| rfc | title | status |
|-----|-------|--------|
| [0005](0005-higher-kinded-types) | higher-kinded types | draft |
| [0006](0006-mapped-types) | mapped types | draft |
| [0010](0010-structured-concurrency) | structured concurrency | draft |
| [0011](0011-async-effects) | async effects | draft |

### future / unscheduled

| rfc | title | status |
|-----|-------|--------|
| 0004 | compile-time evaluation (comptime) | planned |
| 0007 | conditional types | planned |
| 0008 | variadic generics | planned |
| 0009 | template literal types | planned |
| 0012 | capsules (unique resources) | planned |
| 0013 | capability attenuation | planned |
| 0014 | content-addressed packages | planned |
| 0015 | webassembly support | planned |
| 0016 | inline assembly | planned |

## writing an rfc

use the [template](template) as a starting point. an rfc should:

1. explain the motivation clearly
2. describe the design in enough detail to implement
3. discuss tradeoffs and alternatives
4. reference prior art from other languages

## rfc process

1. **draft**: author writes initial proposal
2. **discussion**: community feedback, revisions
3. **decision**: accept, reject, or defer
4. **implementation**: if accepted, implement and test
5. **merge**: move to main spec when stable
