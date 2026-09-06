# modulith

A lightweight module system for Flutter, and the router built on it. Each
package is published on its own and lives in its own directory here.

| Package | Directory | What it is |
| --- | --- | --- |
| [`modulith`](https://pub.dev/packages/modulith) | [`modulith/`](modulith) | Scoped controllers and services composed as a tree of modules, with reactive signals. |
| [`modulith_router`](https://pub.dev/packages/modulith_router) | [`modulith_router/`](modulith_router) | Navigation 2.0 routing: nested route modules mounted through `RoutingView` outlets, with guards, deep links and scoped DI. |
| — (not published) | [`modulith_router_devtools/`](modulith_router_devtools) | The source of the DevTools extension that ships built inside `modulith_router`. |

`modulith_router` exports the routing API only, so an app that routes
depends on both packages and imports both.

## Working in this repo

Each package resolves on its own, so run pub and the tests from its directory:

```sh
cd modulith && flutter test
cd modulith_router && flutter test
```

`modulith_router` builds against the sources of `../modulith` through its
`pubspec_overrides.yaml`, which stays out of the published archive.

The DevTools extension is the exception: it is a Flutter web app that ships
**built**, so `modulith_router/extension/devtools/build` is committed and has
to be rebuilt whenever `modulith_router_devtools` changes — see that
package's README.

That is also why `modulith_router` carries a `.pubignore`: `pub publish`
drops any directory a `build/` rule can reach, negations included, so the
ignores are restated there anchored to the package root. An ignore added to
`.gitignore` that should also apply to the published archive belongs in both
files.
