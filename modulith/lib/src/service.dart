import 'module_member.dart';

/// A plain module-owned collaborator: anything that isn't per-view reactive
/// state, e.g. a repository or an API client.
///
/// Services are created lazily, on first lookup. Like a `Controller` they
/// get [init] and [dispose], can pull in their own dependencies with
/// `injectService` / `injectController`, and can register cleanup with
/// `addDisposeCallback` — what they don't get is `createSignal`, because
/// state the UI watches belongs in a `Controller`.
abstract class Service extends ModuleMember {}
