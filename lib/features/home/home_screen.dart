import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/strings.dart';
import '../../core/network/repository.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/fmt.dart';
import '../../shell/kiosk_shell.dart';
import '../common/svc_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final svc = t['svc'] as List;
    final stats = t['stats'] as List;
    // Live stats (/stats) with offline fallback; '—' while loading.
    final values = ref.watch(statsProvider).maybeWhen(
          data: (s) => s.homeRow.map(fmt).toList(),
          orElse: () => const ['—', '—', '—', '—'],
        );

    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(org: t['heroOrg'], title: t['heroTitle']),
          const SizedBox(height: 34),
          Center(child: Text((t['quick'] as String).toUpperCase(), style: K.secTitle)),
          const SizedBox(height: 24),
          GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 22,
            crossAxisSpacing: 22,
            childAspectRatio: 1.5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < svcList.length; i++)
                SvcTile(
                  icon: svcList[i].$2,
                  label: svc[i],
                  variant: svcList[i].$3,
                  onTap: () => context.go('/${svcList[i].$1}'),
                ),
            ],
          ),
          const SizedBox(height: 38),
          _StatsPanel(title: t['statsTitle'], labels: stats.cast<String>(), values: values),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.org, required this.title});
  final String org, title;
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(T.rLg),
      child: SizedBox(
        height: 380,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(decoration: BoxDecoration(gradient: T.gNavy)),
            Opacity(
              opacity: 0.55,
              child: Image.asset('assets/images/welcome_bg.png', fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(org, textAlign: TextAlign.center, style: K.heroOrg),
                  const SizedBox(height: 16),
                  Text(title, textAlign: TextAlign.center, style: K.heroTitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.title, required this.labels, required this.values});
  final String title;
  final List<String> labels;
  final List<String> values;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: T.gNavyH, borderRadius: BorderRadius.circular(T.rLg)),
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 30),
      child: Column(
        children: [
          Text(title, style: K.statsTitle),
          const SizedBox(height: 20),
          Row(
            children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: i == 0 ? null : const Border(left: BorderSide(color: Color(0x38FFFFFF))),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      children: [
                        Text(values[i], style: K.statsValue),
                        const SizedBox(height: 8),
                        Text(labels[i], textAlign: TextAlign.center, style: K.statsLabel),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
