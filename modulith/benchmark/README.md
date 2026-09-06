# Benchmarks

Informational micro-benchmarks — they print numbers, they don't assert a
pass/fail threshold. Wall-clock timing varies by machine, so gating CI on an
exact number would just be flaky. Use them to eyeball the current cost and to
catch a regression that changes the *complexity class* (e.g. lookup suddenly
becoming O(n²) in module depth), not to enforce an exact µs budget.

Not run by plain `flutter test` (they live outside `test/`, so the default
runner won't discover them) — run each explicitly:

```sh
flutter test benchmark/signal_benchmark.dart
flutter test benchmark/module_resolution_benchmark.dart
```

- **signal_benchmark.dart** — cost of `Signal.value =` (set + notify) as the
  number of listeners grows (0/1/10/100). Confirms it's linear in listener
  count, not something worse.
- **module_resolution_benchmark.dart** — cost of `ModuleRef.getController`
  as the number of ancestor modules it has to walk through grows
  (1/10/50/100 levels deep). Each scope indexes its own providers and
  memoizes where a lookup landed, so the number should stay flat as depth
  grows; a number that climbs with depth means that memoization broke.

For real frame-time/jank profiling on an actual device (not just Dart-side
cost), see `/example/integration_test` instead.
