import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/ai/ai_screen.dart';
import 'features/common/placeholder_screen.dart';
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

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
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
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/services', builder: (_, __) => const ServicesScreen()),
      GoRoute(path: '/news', builder: (_, __) => const NewsScreen()),
      GoRoute(path: '/social', builder: (_, __) => const SocialScreen()),
      GoRoute(path: '/districts', builder: (_, __) => const DistrictsScreen()),
      GoRoute(
        path: '/district/:name',
        builder: (_, st) => DistrictDetailScreen(name: Uri.decodeComponent(st.pathParameters['name'] ?? '')),
      ),
      GoRoute(path: '/phones', builder: (_, __) => const PhonesScreen()),
      GoRoute(path: '/docs', builder: (_, __) => const DocsScreen()),
      GoRoute(path: '/reception', builder: (_, __) => const ReceptionScreen()),
      GoRoute(path: '/xatlov', builder: (_, __) => const XatlovScreen()),
      GoRoute(path: '/property', builder: (_, __) => const PropertyScreen()),
      GoRoute(path: '/illegal', builder: (_, __) => const IllegalScreen()),
      GoRoute(path: '/appeal', builder: (_, __) => const KioskPlaceholder(titleKey: 'pAppeal', milestone: 'M4')),
      GoRoute(path: '/ai', builder: (_, __) => const AiScreen()),
    ],
  );
});
