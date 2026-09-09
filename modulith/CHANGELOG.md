## 0.2.0

* `Provider(..., exported: true)` — hands a provider to the scope of the
  module that declares this one in `children`, so a controller or service of
  a parent module can resolve what a module below it registers. Lookups
  themselves still only travel up; the provider is hoisted once, when the
  ancestor scope is built.
* An exported provider is *owned* by the ancestor: created there, disposed
  with it, and resolvable while the module that declares it is not mounted.
  Parent and child resolve the same instance — the export is removed from
  the declaring scope, so there is no way to end up with two.
* An export travels as far up as there is a scope to receive it, through
  modules that declare no provider of their own. It is overridden on the
  module that owns it, and colliding with an ancestor's registration or with
  a sibling's export throws at mount, like a duplicate registration already
  did.
* Module declarations (`children`, `controllers`, `services`) are now read
  once per module *instance* and cached, instead of once per mount. Exported
  providers are collected before the declaring module is mounted, and both
  reads have to see the same `Provider` objects.
* "Not found" now says the lookup only travels up, and points at
  `exported: true`.

## 0.1.0

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
