import 'package:flutter/material.dart';
import 'package:modulith/modulith.dart';

/// Describes one entry in the feature list on the home screen: a title, an
/// icon, and a factory for the feature's own [Module]. The module is built
/// fresh on every navigation, so each visit gets a clean lifecycle.
class FeatureEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final Module Function() moduleBuilder;

  const FeatureEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.moduleBuilder,
  });
}
