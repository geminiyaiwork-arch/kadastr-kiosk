import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../shell/kiosk_shell.dart';
import '../../core/network/repository.dart';
import '../common/widgets.dart';

class SocialScreen extends ConsumerWidget {
  const SocialScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final async = ref.watch(socialProvider);
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['navSocial'], sub: t['socSub']),
          AsyncView(async, data: (list) => GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            childAspectRatio: 1.45,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final s in list)
                Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: T.line, width: 1.5),
                    borderRadius: BorderRadius.circular(T.rCard),
                    boxShadow: T.shadow,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: T.line, width: 2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: QrImageView(
                          data: s.url,
                          size: 190,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: T.navy),
                          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: T.navy),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(s.name, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: T.navy)),
                      Text(s.url.replaceFirst(RegExp(r'^https?://'), ''),
                          textAlign: TextAlign.center, style: K.distCount, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
            ],
          )),
        ],
      ),
    );
  }
}
