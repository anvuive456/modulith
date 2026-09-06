import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../model/router_models.dart';

/// Everything known about one page: the activation behind it, and the frame
/// that owns it.
class PageDetailsView extends StatelessWidget {
  /// Describes [page], or shows why there is nothing to describe.
  const PageDetailsView({super.key, required this.page, required this.frame});

  /// The selected page, or `null` when nothing is selected.
  final PageData? page;

  /// The frame that owns [page].
  final FrameData? frame;

  @override
  Widget build(BuildContext context) {
    final page = this.page;
    if (page == null) {
      return _Message(
        text: 'Select a page in the navigation tree.',
        style: Theme.of(context).subtleTextStyle,
      );
    }

    final activation = page.activation;
    return ListView(
      primary: false,
      padding: const EdgeInsets.all(denseSpacing),
      children: [
        if (activation == null)
          _Section(
            title: 'Error page',
            entries: [
              ('uri', page.uri),
              ('reason', 'no route matched'),
              ('pageKey', page.pageKey),
            ],
          )
        else ...[
          _Section(
            title: 'Activation #${activation.id}',
            entries: [
              ('route', activation.routePath),
              ('kind', activation.kind),
              ('name', activation.name ?? '—'),
              ('matched', activation.matchedPath),
              ('uri', activation.uri),
              ('module', activation.module ?? '— (ViewRoute)'),
              ('reuse', activation.reuse),
              ('childRouting', activation.childRouting),
              ('pageKey', page.pageKey),
            ],
          ),
          _Section(
            title: 'Parameters',
            entries: [
              ...activation.params.entries.map(
                (entry) => (entry.key, entry.value),
              ),
              if (activation.params.isEmpty) ('—', 'no path parameters'),
            ],
          ),
          _Section(
            title: 'Query',
            entries: [
              ...activation.query.entries.map(
                (entry) => (entry.key, entry.value),
              ),
              if (activation.query.isEmpty) ('—', 'no query parameters'),
            ],
          ),
          _Section(
            title: 'Guards',
            entries: [
              for (final guard in activation.guards)
                (guard, activation.routePath),
              if (activation.guards.isEmpty)
                ('—', 'no guards declared on this route'),
            ],
          ),
          _Section(
            title: 'Extra',
            entries: [
              (
                'extra',
                activation.extra == null
                    ? '— (nothing passed)'
                    : '${activation.extra}',
              ),
            ],
          ),
        ],
        if (frame case final frame?)
          _Section(
            title: 'Frame #${frame.id}',
            entries: [
              ('uri', frame.uri),
              ('awaitsResult', '${frame.awaitsResult}'),
              ('renderStart', '${frame.renderStart}'),
              (
                'anchor',
                frame.anchorActivationId == null
                    ? 'root navigator'
                    : '#${frame.anchorActivationId}',
              ),
              (
                'activations',
                frame.activations.map((id) => '#$id').join(' → '),
              ),
            ],
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.entries});

  final String title;
  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: defaultSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.boldTextStyle),
          const SizedBox(height: densePadding),
          for (final (label, value) in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: densePadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 108,
                    child: Text(label, style: theme.subtleTextStyle),
                  ),
                  Expanded(
                    child: SelectableText(value, style: theme.fixedFontStyle),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(defaultSpacing),
      child: Text(text, textAlign: TextAlign.center, style: style),
    ),
  );
}
