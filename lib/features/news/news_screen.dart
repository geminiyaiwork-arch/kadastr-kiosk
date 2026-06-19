import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/models.dart';
import '../../core/network/repository.dart';
import '../../core/theme/press.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../shell/kiosk_shell.dart';
import '../common/widgets.dart';

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});
  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  NewsItem? _open;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final lang = ref.watch(localeProvider);
    final async = ref.watch(newsProvider);

    if (_open != null) {
      final n = _open!;
      return KioskScaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHead(t['pNews']),
            if (n.media != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  resolveMedia('/news/media/${n.media}'),
                  height: 620,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            const SizedBox(height: 18),
            Text('${n.date}   👁 ${n.views}', style: K.newsDate),
            const SizedBox(height: 12),
            Text(n.titleFor(lang), style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800, color: T.navy, height: 1.25)),
            const SizedBox(height: 20),
            KButton(t['back'], variant: 'navy', expand: false, onTap: () => setState(() => _open = null)),
          ],
        ),
      );
    }

    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['pNews']),
          AsyncView(async, data: (list) {
            if (list.isEmpty) return KCard(child: Text(t['newsEmpty'], style: K.cardP));
            return Column(children: [
              for (final n in list) _NewsTile(n: n, lang: lang, onTap: () {
                _openNews(n);
              }),
            ]);
          }),
        ],
      ),
    );
  }

  void _openNews(NewsItem n) {
    setState(() => _open = n);
    // increment view count (fire and forget)
    ref.read(dioProvider).post('/news/${n.id}/view').then((_) {}, onError: (_) {});
  }
}

class _NewsTile extends StatelessWidget {
  const _NewsTile({required this.n, required this.lang, required this.onTap});
  final NewsItem n;
  final String lang;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Press(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: T.line, width: 1.5),
          borderRadius: BorderRadius.circular(T.rCard),
          boxShadow: T.shadow,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 168,
                height: 118,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    n.media != null
                        ? Image.network(resolveMedia('/news/media/${n.media}'), fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const _NewsThumb())
                        : const _NewsThumb(),
                    if (n.mediaType == 'video')
                      const Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Color(0x9910266B), shape: BoxShape.circle),
                          child: SizedBox(width: 54, height: 54, child: Icon(Icons.play_arrow, color: Colors.white, size: 32)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${n.date}   👁 ${n.views}', style: K.newsDate),
                  const SizedBox(height: 8),
                  Text(n.titleFor(lang), style: K.newsTitle, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Text('›', style: TextStyle(fontSize: 40, color: T.muted, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// Gradient placeholder thumbnail (web thumbSVG green gradient).
class _NewsThumb extends StatelessWidget {
  const _NewsThumb();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7FAE7F), Color(0xFF5D8F5D)],
        ),
      ),
    );
  }
}
