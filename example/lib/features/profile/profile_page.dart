import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';

import 'profile_controller.dart';

class ProfilePage extends ModularWidget {
  const ProfilePage({super.key});

  @override
  Widget build(ModuleContext context) {
    final controller = context.getController<ProfileController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              // Seeded from SettingsController in ProfileController.init().
              controller: controller.name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: controller.save,
                  child: const Text('Save'),
                ),
                const SizedBox(width: 12),
                SignalBuilder(
                  signal: controller.justSaved,
                  builder: (saved) =>
                      saved ? const Text('Saved!') : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
