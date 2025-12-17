# Deterministic Scheduling & Testing

> **scope:** test schedulers, time/rng stubs, reproducible interleavings  
> **related:** [tasks.md](tasks.md) | [../modules/capabilities.md](../modules/capabilities.md)

---

## Overview

Ferrule supports **determinism on demand** — the ability to replay exact execution sequences for testing and debugging.

---

## Deterministic Mode

In test mode, the runtime:
- replaces schedulers with deterministic versions
- stubs time and RNG capabilities
- records/replays task interleavings

---

## Time Capability Stubbing

```ferrule
function test_timeout_behavior() {
  const mock_clock = testing.mock_clock(start = Time.epoch());
  
  // create a scope with the mock clock
  task.scope_with(scope, clock = mock_clock, () => {
    const tok = cancel.token(mock_clock.now() + Duration.seconds(10));
    
    scope.spawn(async {
      // this operation will see mock time
      const result = fetch_with_timeout(url, tok);
    });
    
    // advance time deterministically
    mock_clock.advance(Duration.seconds(5));
    // task still running...
    
    mock_clock.advance(Duration.seconds(6));
    // now past deadline, cancellation triggers
  });
}
```

---

## RNG Capability Stubbing

```ferrule
function test_randomized_algorithm() {
  const mock_rng = testing.mock_rng(seed = 12345);
  
  // algorithm receives deterministic RNG
  const result1 = shuffle(items, mock_rng);
  
  // reset and replay
  mock_rng.reset();
  const result2 = shuffle(items, mock_rng);
  
  // result1 === result2 (same seed, same sequence)
}
```

---

## Scheduler Instrumentation

The deterministic scheduler can:
- record all task switches
- replay exact interleavings
- detect data races (in debug builds)

```ferrule
function test_concurrent_access() {
  const scheduler = testing.deterministic_scheduler(seed = 42);
  
  scheduler.run(() => {
    task.scope(scope => {
      scope.spawn(producer());
      scope.spawn(consumer());
      check scope.await_all();
    });
  });
  
  // replay with same seed produces identical behavior
}
```

---

## Race Detection

In deterministic mode, the runtime can instrument shared memory access:

```ferrule
function test_no_races() {
  const scheduler = testing.deterministic_scheduler(
    seed = 42,
    detect_races = true
  );
  
  scheduler.run(() => {
    // concurrent code...
  });
  
  // if races detected, test fails with detailed report
}
```

---

## Interleaving Exploration

Test multiple interleavings systematically:

```ferrule
function test_all_interleavings() {
  testing.explore_interleavings(max_runs = 1000, () => {
    task.scope(scope => {
      scope.spawn(task_a());
      scope.spawn(task_b());
      check scope.await_all();
    });
    
    // assert invariants hold regardless of interleaving
    assert(invariant_holds());
  });
}
```

---

## Capability Injection Pattern

The capability system makes deterministic testing natural:

```ferrule
// production code
function process(cap clock: Clock, cap rng: Rng) -> Result effects [time, rng] {
  const delay = rng.range(100, 500);
  clock.sleep(Duration.ms(delay));
  // ...
}

// test code
function test_process() {
  const mock_clock = testing.mock_clock();
  const mock_rng = testing.mock_rng(seed = 123);
  
  // inject mocks — no code changes needed
  const result = process(mock_clock, mock_rng);
  
  // verify behavior with deterministic time/randomness
}
```

---

## Summary

| Feature | Purpose |
|---------|---------|
| `mock_clock` | deterministic time |
| `mock_rng` | deterministic randomness |
| `deterministic_scheduler` | reproducible task ordering |
| `explore_interleavings` | systematic testing |
| race detection | find data races in tests |


