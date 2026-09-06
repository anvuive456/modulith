## 0.0.1

* Declare module views, controllers, services, and children through getters.
* Add singleton and factory `Provider` registrations.
* Add `ModuleScope` ownership, parent lookup, lifecycle, and disposal.
* Attach controllers before `init()` and support `injectController` and
  `injectService`.
* Shrink the widget surface to three types: `ModuleWidget` opens a scope,
  `ChildModuleView` mounts a declared child, `ModularWidget` builds a view.
  `ModuleHelper` and `ModuleRef` are gone, and `ModuleProvider` is no longer
  exported.
* Give `ModularWidget.build` a single `ModuleContext` argument — a
  `BuildContext` that also resolves controllers and services — replacing
  `build(context, ref)`. The runtime scope that used to be called
  `ModuleContext` is now `ModuleScope`, which is what `Module.onInit` /
  `onDispose` receive.
* Scope factory instances to whoever resolved them (widget build, requesting
  controller or service) instead of keeping them until the module unmounts,
  with `ModuleScope.release` as a manual escape hatch.
* Add `overrides` on `ModuleWidget`, `ChildModuleView` and `ModuleScope`
  for swapping providers in tests.
* Only notify `Signal` listeners when the value actually changed; add
  `Signal.refresh()` for state mutated in place.
* Add `Controller.isDisposed` and `Controller.addDisposeCallback()`; writes
  to a signal owned by a disposed controller are now no-ops instead of
  throwing.
* Fix `ModularWidget` not rebuilding when its parent passes new values.
* Fix resolving through an already-disposed ancestor scope creating an
  instance that was never disposed; it throws now.
* Give `Service` the same lifecycle as `Controller` — `init()`, `dispose()`,
  `injectService`/`injectController`, `addDisposeCallback`, `isDisposed` —
  through a shared `ModuleMember` base.
* Index providers and children by type and name, and memoize where a lookup
  landed, so resolving through a deep module tree no longer walks it on
  every call.
* Add `Module.name` and `ChildModuleView(name: ...)` for parents that
  declare several children of the same type; declaring two children with the
  same type and name now throws, as does mounting one `Module` instance in
  two live scopes at once.
* Keep a failed rollback from masking the error that caused it when a
  provider's `init()` throws.
* Stop `runModuleApp` swallowing every error in a `runZonedGuarded` that only
  printed them; it now leaves Flutter's error handling alone, and takes an
  optional `onError` for framework and uncaught async errors both.
* Move the implementation to `lib/src`, drop the deprecated `Named`,
  `NamedController` and `NamedService`, and mark internal members
  `@internal`.
