import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env.dart';
import '../network/api_client.dart';

/// Posts POST /kiosk/ping {id, version} every 60s so the admin shows this
/// kiosk online. Reports the real app version (not the stale web "1.4.1").
class HeartbeatHost extends ConsumerStatefulWidget {
  const HeartbeatHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<HeartbeatHost> createState() => _HeartbeatHostState();
}

class _HeartbeatHostState extends ConsumerState<HeartbeatHost> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ping();
    _timer = Timer.periodic(const Duration(milliseconds: Env.heartbeatMs), (_) => _ping());
  }

  Future<void> _ping() async {
    try {
      await ref.read(dioProvider).post('/kiosk/ping', data: {
        'id': Env.kioskId,
        'version': Env.appVersion,
      });
    } catch (_) {/* offline — ignore */}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
