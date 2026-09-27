import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../router.dart';

/// Ekran "band" (video/murojaat/kamera) ekanini idle-taymerga bildiradi (kioskBusy ref-count).
///
/// MUHIM (1.9.48): flutter_riverpod 2.6'da `dispose()` ichida `ref.read` ISHLAMAYDI —
/// Flutter `State.dispose()`ni element allaqachon `mounted=false` bo'lgach chaqiradi va
/// ref "Cannot use ref after the widget was disposed" deb otadi. Avval shu sababli
/// hisoblagich kamaymay 1 da QOTIB qolardi → idle-reset, zastavka, zastavka-tinglash va
/// avto-yangilanish abadiy to'xtardi. Endi notifier initState'da olinadi va dispose'da
/// (daraxt yig'ilgach, microtask'da) ishlatiladi.
mixin KioskBusyHold<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  late final StateController<int> _kioskBusyN;
  bool _kioskBusyHeld = false;

  @override
  void initState() {
    super.initState();
    _kioskBusyN = ref.read(kioskBusyProvider.notifier);
  }

  /// true = band (idle-taymer to'xtaydi), false = bo'shadi. Takror chaqiruv xavfsiz.
  void setKioskBusy(bool v) {
    if (v == _kioskBusyHeld) return;
    _kioskBusyHeld = v;
    final n = _kioskBusyN;
    n.update((c) => v ? c + 1 : (c > 0 ? c - 1 : 0));
  }

  bool get kioskBusyHeld => _kioskBusyHeld;

  @override
  void dispose() {
    if (_kioskBusyHeld) {
      _kioskBusyHeld = false;
      final n = _kioskBusyN;
      // dispose paytida provider o'zgartirilmaydi (riverpod debug-assert) — keyinroq.
      scheduleMicrotask(() => n.update((c) => c > 0 ? c - 1 : 0));
    }
    super.dispose();
  }
}
