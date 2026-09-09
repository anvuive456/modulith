## 0.3.0

* `RouterService` and `RouterController` are exported (modulith 0.2.0), so
  the module that declares `RouterModule` in its `children` owns them: a
  controller of the app module can `injectService<RouterService>()` and
  navigate from `init()`, without waiting for the router to be mounted.
* Both now live as long as the module that declares the router, not as long
  as the `RouterModule` mount. Mounting `RouterModule` on its own — as the
  router's own tests do — is unchanged: with no ancestor declaring it, its
  exports stay local.
* Requires `modulith: ^0.2.0`.

## 0.2.0

* `RouterObserver` — a hook on `RouterModule` and `RouterService` that
  reports what the navigation pipeline decides: `NavigationStarted`,
  `RouteMatched`, `RedirectApplied`, `GuardEvaluated` (with the route it is
  declared on and how long it took), `DeactivationBlocked`,
  `NavigationEnded` and `StackChanged`, all tied together by a
  `navigationId`. `LoggingRouterObserver` prints them.
* A router with no observers builds no events, times no guards and allocates
  nothing for the hook. An observer that throws is reported through
  `FlutterError.reportError` and the navigation carries on.
* Debug builds attach an inspector that posts every router event on the VM
  service (`modulith_router:event`) and answers `ext.modulith_router.*`:
  `listRouters`, `getState`, `getRouteTable`, `getNavigationTree` (frames,
  navigators, pages, activations, and the stacks background branches retain)
  and `getEventLog` (the last 500 events, so a tool that connects late sees
  what it missed). Attached from inside an `assert`, so a release build has
  no inspector, no log and no registered extensions.
* A DevTools extension, shipped built in `extension/devtools`: opening
  DevTools against a debug build adds a **modulith_router** tab. Nothing to
  install; its source lives in `modulith_router_devtools/` in the repository.
  * **Navigation** — the live navigator tree: outlets, pages, and the stacks
    background branches retain, with the activation behind each page.
  * **Route table** — the compiled table, filterable, plus a URL tester
    (`ext.modulith_router.matchTrace`) that answers *without navigating*:
    the chain that matched and its parameters, or every route the matcher
    tried and where it gave up; the redirect hops and where they land; and
    the guards that would run there.

## 0.1.1

* Add an example: a single-file tour of persistent branch tabs, a push that
  answers with the value it is popped with, and a guard that redirects out of
  a branch.

## 0.1.0

First release.

* Exports the routing API only: an app that routes depends on `modulith`
  as well and imports both libraries.
* `RouterModule` — the router as a modulith module: `RouterService` (route
  table, navigation, `RouterConfig`) and `RouterController` (`uri`, `canPop`,
  `isNavigating`, `activeRouteName` as signals).
* `ModuleRoute`, `ViewRoute` and `RedirectRoute`, with `:param`, `*` and `**`
  patterns, pathless routes, named routes and reverse routing (`goNamed`,
  `uriFor`).
* `RouteMatcher` — the route table compiled once into a tree; matching costs
  the length of the URL, tries literal before `:param` before wildcard, and
  rejects duplicate sibling patterns, duplicate names and shadowed parameter
  names when the table is built.
* `RoutingView` — the routing outlet, as a page-based `Navigator`
  (`OutletMode.stack`) or a single swapped child (`OutletMode.replace`), with
  its own `HeroController` so nested outlets don't fight over one.
* `ChildRouting.stack` / `ChildRouting.outlet` on every route, which is what
  makes a pathless route a shell — no separate `ShellRoute` concept.
* Route data reaches a module through `ModuleRoute.builder`, which receives
  the `ActivatedRoute`; nothing router-specific is injected into module
  scopes. `context.route` and `context.router` for widgets.
* `RouteReuse.byPathParams` (default), `always` and `never` decide whether an
  activation — and with it a module scope — survives a parameter change.
* Guards: `RouteGuard.canActivate` with allow/block/redirect, global guards
  first then root to leaf, async, with a generation counter so a newer
  navigation supersedes an older one, and a redirect limit that names the
  loop. `registerDeactivationGuard` for unsaved-changes prompts.
* `push<T>` resolves with the value passed to `pop`, over an imperative frame
  that can sit on a location outside the current chain.
* Deep links, browser back/forward and the Android back button through
  `RouteInformationParser` / `currentConfiguration` / `popRoute`, with back
  going to the deepest outlet that has something to pop.
* `errorBuilder` for unmatched URLs; a declared `**` route takes precedence.
