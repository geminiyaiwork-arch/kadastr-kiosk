import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/ai/ai_screen.dart';
import 'features/appeal/appeal_screen.dart';
import 'features/districts/districts_screen.dart';
import 'features/home/home_screen.dart';
import 'features/illegal/illegal_screen.dart';
import 'features/info/info_screens.dart';
import 'features/news/news_screen.dart';
import 'features/phones/phones_screen.dart';
import 'features/property/property_screen.dart';
import 'features/services/services_screen.dart';
import 'features/social/social_screen.dart';

/// Current top-level route path (drives the always-on voice listener's
/// page-aware behaviour: direct on /ai, paused on /appeal).
final currentRouteProvider = StateProvider<String>((_) => '/');

/// Root navigator — global dialoglar (auto-update oynasi) uchun.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final loc = state.uri.path;
      Future.microtask(() {
        if (ref.read(currentRouteProvider) != loc) {
          ref.read(currentRouteProvider.notifier).state = loc;
        }
      });
      return null;
    },
    routes: [
      GoRoute(path: '/', pageBuilder: (_, st) => _fx(st, const HomeScreen())),
      GoRoute(path: '/services', pageBuilder: (_, st) => _fx(st, const ServicesScreen())),
      GoRoute(path: '/news', pageBuilder: (_, st) => _fx(st, const NewsScreen())),
      GoRoute(path: '/social', pageBuilder: (_, st) => _fx(st, const SocialScreen())),
      GoRoute(path: '/districts', pageBuilder: (_, st) => _fx(st, const DistrictsScreen())),
      GoRoute(
        path: '/district/:name',
        pageBuilder: (_, st) => _fx(st, DistrictDetailScreen(name: Uri.decodeComponent(st.pathParameters['name'] ?? ''))),
      ),
      GoRoute(path: '/phones', pageBuilder: (_, st) => _fx(st, const PhonesScreen())),
      GoRoute(path: '/docs', pageBuilder: (_, st) => _fx(st, const DocsScreen())),
      GoRoute(path: '/reception', pageBuilder: (_, st) => _fx(st, const ReceptionScreen())),
      GoRoute(path: '/xatlov', pageBuilder: (_, st) => _fx(st, const XatlovScreen())),
      GoRoute(path: '/property', pageBuilder: (_, st) => _fx(st, const PropertyScreen())),
      GoRoute(path: '/illegal', pageBuilder: (_, st) => _fx(st, const IllegalScreen())),
      GoRoute(path: '/appeal', pageBuilder: (_, st) => _fx(st, const AppealScreen())),
      GoRoute(path: '/ai', pageBuilder: (_, st) => _fx(st, const AiScreen())),
    ],
  );
});

/// Sahifa o'tish EFEKTI: yangi sahifa "yig'iladi" (kattalashib, ko'tarilib, so'nishдan
/// paydo bo'ladi), eski sahifa "shamol bo'lib sochiladi" (kattalashib, burilib, uchib so'nadi).
Page<void> _fx(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      transitionDuration: const Duration(milliseconds: 560),
      reverseTransitionDuration: const Duration(milliseconds: 460),
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final inC = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        final outC = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInCubic);
        return AnimatedBuilder(
          animation: Listenable.merge([animation, secondaryAnimation]),
          child: child,
          builder: (context, child) {
            final i = inC.value;   // 0->1 kirish (yig'ilish)
            final o = outC.value;  // 0->1 chiqish (sochilish)
            final leaving = o > 0.0001;
            final scale = leaving ? (1 + 0.20 * o) : (0.90 + 0.10 * i);
            final opacity = (leaving ? (1 - o) : i).clamp(0.0, 1.0);
            final dx = leaving ? (70.0 * o) : 0.0;
            final dy = leaving ? (-36.0 * o) : (40.0 * (1 - i));
            final rot = leaving ? (0.07 * o) : (0.045 * (1 - i));
            return Opacity(
              opacity: opacity,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translate(dx, dy)
                  ..rotateZ(rot)
                  ..scale(scale),
                child: child,
              ),
            );
          },
        );
      },
    );
