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
