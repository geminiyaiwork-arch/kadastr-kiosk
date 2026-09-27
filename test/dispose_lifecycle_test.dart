import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr_kiosk/core/network/api_client.dart';
import 'package:kadastr_kiosk/core/network/models.dart';
import 'package:kadastr_kiosk/core/network/repository.dart';
import 'package:kadastr_kiosk/features/ai/ai_screen.dart';
import 'package:kadastr_kiosk/features/ai/voice_controller.dart';
import 'package:kadastr_kiosk/features/common/kfield.dart';
import 'package:kadastr_kiosk/router.dart';
import 'package:kadastr_kiosk/shell/kiosk_busy.dart';
import 'package:kadastr_kiosk/shell/vk_fields.dart';

import 'ambient_attract_test.dart' show FakeRecorder;
import 'speech_queue_test.dart' show FakeClipPlayer;

/// Regressiya: riverpod 2.6'da `dispose()` ichida `ref.read` OTADI. Avval shu sababli
/// kioskBusy 1 da qotib qolardi, AI sahifadan chiqqach qo'lda yozuv davom etib uy
/// sahifasida javob berardi, klaviatura maydoni ro'yxatdan o'chmasdi.

class _Busy extends ConsumerStatefulWidget {
  const _Busy();
  @override
  ConsumerState<_Busy> createState() => _BusyState();
}

class _BusyState extends ConsumerState<_Busy> with KioskBusyHold {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => setKioskBusy(true));
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// Tarmoqsiz dio: hamma so'rov 404 (testWidgets muhitida haqiqiy HTTP yo'q).
class _Offline implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async =>
      ResponseBody.fromString('{"error":"offline"}', 404, headers: {
        Headers.contentTypeHeader: ['application/json']
      });
  @override
  void close({bool force = false}) {}
}

Widget _host(ProviderContainer c, Widget child) =>
    UncontrolledProviderScope(container: c, child: MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('KioskBusyHold releases kioskBusy when the screen is disposed', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(_host(c, const _Busy()));
    await tester.pump();
    expect(c.read(kioskBusyProvider), 1);
    await tester.pumpWidget(_host(c, const SizedBox()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(c.read(kioskBusyProvider), 0);
  });

  testWidgets('KField unregisters from the virtual keyboard on dispose', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ctl = TextEditingController();
    await tester.pumpWidget(_host(c, KField(controller: ctl)));
    await tester.pump();
    expect(c.read(vkFieldsProvider).length, 1);
    await tester.pumpWidget(_host(c, const SizedBox()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(c.read(vkFieldsProvider), isEmpty);
  });

  testWidgets('leaving the AI page while tap-to-talk is recording cancels the recording', (tester) async {
    final rec = FakeRecorder();
    final c = ProviderContainer(overrides: [
      dioProvider.overrideWithValue(Dio(BaseOptions(baseUrl: 'http://offline/api/v1'))..httpClientAdapter = _Offline()),
      avatarProvider.overrideWith((ref) async => const AvatarConfig()),
      aiWarmupProvider.overrideWith((ref) async => {'loading': false}),
      statsProvider.overrideWith((ref) async => Stats.empty),
      xatlov937Provider.overrideWith((ref) async => <String, dynamic>{}),
      voiceProvider.overrideWith((ref) => VoiceController(ref, player: FakeClipPlayer(), recorder: rec)),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(_host(c, const AiScreen()));
    await tester.pump(const Duration(milliseconds: 500)); // _init + greet (offline → silent)
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.read(voiceProvider).recording, isTrue);
    expect(await rec.isRecording(), isTrue);

    await tester.pumpWidget(_host(c, const SizedBox())); // Back → another page
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(c.read(voiceProvider).recording, isFalse);
    expect(await rec.isRecording(), isFalse);
    expect(c.read(introPlayingProvider), isFalse);
    // the 20 s safety timer of the cancelled recording must not fire an answer later
    await tester.pump(const Duration(seconds: 21));
    expect(c.read(voiceProvider).phase, isNot(VoicePhase.thinking));
  });
}
