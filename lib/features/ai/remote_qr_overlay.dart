import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/tokens.dart';
import 'remote_session.dart';

/// Burchakдаги QR — telefon orqali ovozli so'rash uchun. Telefon ulangach
/// QR yashirinadi (kichik "Telefon ulandi" belgisi chiqadi).
class RemoteQrOverlay extends ConsumerWidget {
  const RemoteQrOverlay({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(remoteSessionProvider);
    if (s.token.isEmpty) return const SizedBox.shrink();
    final url = ref.read(remoteSessionProvider.notifier).phoneUrl;
    return Positioned(
      right: 28,
      bottom: 150,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
        child: s.connected ? const _ConnectedBadge() : _QrCard(url: url),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('qr'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x2A10266B), offset: Offset(0, 8), blurRadius: 26)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('📱 Telefon orqali so‘rang',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: T.navy)),
          const SizedBox(height: 12),
          QrImageView(
            data: url,
            version: QrVersions.auto,
            size: 188,
            gapless: true,
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 10),
          const SizedBox(
            width: 188,
            child: Text(
              'Kamera bilan skanerlang →\nmikrofonni bosib gapiring',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.3, color: T.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectedBadge extends StatelessWidget {
  const _ConnectedBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('conn'),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF16A34A),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x3316A34A), offset: Offset(0, 6), blurRadius: 20)],
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.smartphone_rounded, color: Colors.white, size: 28),
        SizedBox(width: 10),
        Text('Telefon ulandi', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
      ]),
    );
  }
}
