import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:modulith/modulith.dart';

import '../../core/settings_controller.dart';

/// The username itself lives on the app-wide [SettingsController]; this
/// controller owns the *editing* of it — the text field's state, and the
/// short-lived "Saved!" flag.
class ProfileController extends Controller {
  late final SettingsController _settings;
  late final justSaved = createSignal<bool>(false);

  /// The page is a plain [ModularWidget], so the field's controller lives
  /// here rather than in a `State`.
  final name = TextEditingController();

  Timer? _resetTimer;

  @override
  void init() {
    // injectController walks up to AppModule, which declares SettingsController.
    _settings = injectController<SettingsController>();
    name.text = _settings.username.value;

    // Cleanup registered up front instead of overriding dispose() — handy
    // when the thing to cancel is created later, or in several places.
    addDisposeCallback(name.dispose);
    addDisposeCallback(() => _resetTimer?.cancel());
  }

  void save() {
    _settings.setUsername(name.text);
    justSaved.value = true;
    _resetTimer?.cancel();
    _resetTimer = Timer(
      const Duration(seconds: 2),
      () => justSaved.value = false,
    );
  }
}
