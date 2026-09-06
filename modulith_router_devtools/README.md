# modulith_router_devtools

The source of the DevTools extension that ships inside
[`modulith_router`](../modulith_router). Never published: what ships is the
**built** web app, copied into `modulith_router/extension/devtools/build`,
which is where DevTools loads it from.

The app it inspects registers `ext.modulith_router.*` from inside an
`assert`, so this tab only has anything to show against a **debug** build.

## Running it

Against a fake app, with no VM service involved — the fastest loop for UI
work:

```sh
flutter run -d chrome --dart-define=use_simulated_environment=true
```

Against a real app: run any app that mounts a `RouterModule` in debug mode,
open DevTools, and the extension appears as its own tab once
`modulith_router` is in the app's resolved dependencies.

## Rebuilding what ships

The build output is committed, so it has to be rebuilt whenever this app
changes:

```sh
dart run devtools_extensions build_and_copy \
  --source=. --dest=../modulith_router/extension/devtools
dart run devtools_extensions validate --package=../modulith_router
```

`build_and_copy` shells out to `flutter`, so `flutter` has to be on `PATH` —
with fvm, `PATH="$HOME/fvm/default/bin:$PATH"` in front of the command.

## Why it polls

`dart:developer.postEvent` is a **no-op on the web**: dart2js compiles it to
nothing, and DDC forwards it only through a `package:dwds` hook. An extension
that waited for events would therefore sit there stale against every Flutter
web app — verified against a real one, where `getState` answered fine and no
event ever arrived.

So the controller polls `getState` once a second and pulls the rest only when
the revision moved. Events stay wired up as a fast path: where they work,
the refresh is immediate instead of up to a second late.

## Layout

| | |
| --- | --- |
| `src/router_client.dart` | what the extension knows about the app, as an interface |
| `src/vm_service_router_client.dart` | the only file that touches `serviceManager` |
| `src/router_controller.dart` | the state, and when to pull more of it |
| `src/model/router_models.dart` | the `ext.modulith_router.*` payloads, parsed |
| `src/ui/` | the tabs |

The client is an interface and the VM service implementation is the only
web-only file, which is what lets `flutter test` drive the whole extension
from a fake — see `test/navigation_tab_test.dart`.
