import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/i18n/strings.dart';
import '../../core/map/cached_tile_provider.dart';
import '../../core/network/models.dart';
import '../../core/network/repository.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/fmt.dart';
import '../../shell/kiosk_shell.dart';
import '../common/widgets.dart';

/// Kadastr palatasi (Andijon sh.) — "Yo'nalish" boshlang'ich nuqtasi.
const _palace = LatLng(40.7821, 72.3442);
const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

class DistrictGeo {
  final LatLng center;
  final List<LatLng>? poly;
  const DistrictGeo(this.center, this.poly);
}

final districtGeoProvider = FutureProvider<Map<String, DistrictGeo>>((ref) async {
  try {
    final raw = await rootBundle.loadString('assets/geo/andijan_districts.json');
    final m = json.decode(raw) as Map<String, dynamic>;
    final out = <String, DistrictGeo>{};
    m.forEach((k, v) {
      final vv = Map<String, dynamic>.from(v as Map);
      final c = vv['center'] as List?;
      if (c == null || c.length < 2) return;
      final center = LatLng((c[0] as num).toDouble(), (c[1] as num).toDouble());
      List<LatLng>? poly;
      final p = vv['poly'] as List?;
      if (p != null && p.length >= 3) {
        poly = p.map((e) => LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble())).toList();
      }
      out[k] = DistrictGeo(center, poly);
    });
    return out;
  } catch (_) {
    return const {};
  }
});

final tileProviderProvider = FutureProvider<TileProvider>((ref) => obtainCachedTileProvider());

TileLayer _osmTiles(TileProvider tp) => TileLayer(
      urlTemplate: _tileUrl,
      userAgentPackageName: 'uz.andkadastrai.kiosk',
      tileProvider: tp,
      maxZoom: 18,
    );

// ─────────────────────────── RO'YXAT + VILOYAT XARITASI ───────────────────────────
class DistrictsScreen extends ConsumerStatefulWidget {
  const DistrictsScreen({super.key});
  @override
  ConsumerState<DistrictsScreen> createState() => _DistrictsScreenState();
}

class _DistrictsScreenState extends ConsumerState<DistrictsScreen> {
  bool _map = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final async = ref.watch(districtsProvider);
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['pDistricts'], sub: t['distSub']),
          // Ro'yxat ⇄ Xarita almashtirgich
          _SegToggle(
            left: t['dvList'] ?? 'Ro‘yxat',
            right: t['dvMap'] ?? 'Xarita',
            leftIcon: Icons.grid_view_rounded,
            rightIcon: Icons.map_rounded,
            value: _map,
            onChanged: (v) => setState(() => _map = v),
          ),
          const SizedBox(height: 14),
          if (_map)
            const _RegionMap()
          else
            AsyncView(async, data: (list) => GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 4.2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final d in list) _DistTile(d: d, objects: t['objects']),
              ],
            )),
        ],
      ),
    );
  }
}

class _SegToggle extends StatelessWidget {
  const _SegToggle({required this.left, required this.right, required this.leftIcon, required this.rightIcon, required this.value, required this.onChanged});
  final String left, right;
  final IconData leftIcon, rightIcon;
  final bool value; // false=left, true=right
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    Widget seg(String label, IconData ic, bool active, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: active ? T.green : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(ic, color: active ? Colors.white : T.muted, size: 24),
                const SizedBox(width: 10),
                Text(label, style: TextStyle(color: active ? Colors.white : T.muted, fontSize: 19, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: T.line)),
      child: Row(children: [
        seg(left, leftIcon, !value, () => onChanged(false)),
        seg(right, rightIcon, value, () => onChanged(true)),
      ]),
    );
  }
}

class _DistTile extends StatelessWidget {
  const _DistTile({required this.d, required this.objects});
  final District d;
  final String objects;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.go('/district/${Uri.encodeComponent(d.name)}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: T.line),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 5))],
        ),
        child: Row(children: [
          Container(
            width: 54, height: 54, alignment: Alignment.center,
            decoration: BoxDecoration(color: T.greenTint, borderRadius: BorderRadius.circular(14)),
            child: Icon(d.isCity ? Icons.location_city_rounded : Icons.map_rounded, color: T.green, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(d.name, style: const TextStyle(color: T.navy, fontSize: 21, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text('${fmt(d.auksion)} $objects', style: K.pgSub),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, size: 34, color: T.muted),
        ]),
      ),
    );
  }
}

/// Butun Andijon viloyati — barcha tumanlar poligoni + bosiladigan markerlar + info.
class _RegionMap extends ConsumerWidget {
  const _RegionMap();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final geo = ref.watch(districtGeoProvider).asData?.value ?? const {};
    final tp = ref.watch(tileProviderProvider).asData?.value;
    final list = ref.watch(districtsProvider).asData?.value ?? const <District>[];
    if (tp == null || geo.isEmpty) {
      return const SizedBox(height: 540, child: Center(child: CircularProgressIndicator(color: T.green)));
    }
    final allPts = <LatLng>[];
    for (final g in geo.values) {
      if (g.poly != null) allPts.addAll(g.poly!); else allPts.add(g.center);
    }
    var auk = 0, ariz = 0, cities = 0;
    for (final d in list) { auk += d.auksion; ariz += d.arizalar; if (d.isCity) cities++; }
    final tumans = list.isEmpty ? geo.length : list.length - cities;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 560,
        decoration: BoxDecoration(border: Border.all(color: T.line), borderRadius: BorderRadius.circular(20)),
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: allPts.isNotEmpty
                ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(allPts), padding: const EdgeInsets.all(24))
                : null,
            initialCenter: _palace,
            initialZoom: 8.5,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          ),
          children: [
            _osmTiles(tp),
            PolygonLayer(polygons: [
              for (final g in geo.values)
                if (g.poly != null)
                  Polygon(points: g.poly!, color: T.green.withOpacity(0.10), borderColor: T.green, borderStrokeWidth: 2),
            ]),
            MarkerLayer(markers: [
              for (final e in geo.entries)
                Marker(
                  point: e.value.center,
                  width: 150, height: 60,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () => context.go('/district/${Uri.encodeComponent(e.key)}'),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.location_on, color: T.green, size: 34,
                          shadows: [Shadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2))]),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(6)),
                        child: Text(e.key.replaceAll(' tumani', '').replaceAll(' shahar', ''),
                            style: const TextStyle(color: T.navy, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                ),
            ]),
          ],
        ),
      ),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: T.line),
          boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 5))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44, height: 44, alignment: Alignment.center,
              decoration: BoxDecoration(color: T.greenTint, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.map_rounded, color: T.green, size: 24),
            ),
            const SizedBox(width: 12),
            Text(t['distRegionTitle'] ?? 'Andijon viloyati',
                style: const TextStyle(color: T.navy, fontSize: 23, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            _rstat(Icons.location_city_rounded, '$tumans', t['distTumans'] ?? 'tuman'),
            _rstat(Icons.terrain_rounded, fmt(auk), t['objects'] ?? 'obyekt'),
            _rstat(Icons.description_rounded, fmt(ariz), t['applications'] ?? 'ariza'),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.touch_app_rounded, color: T.muted, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(t['distMapHint'] ?? 'Tuman haqida ma’lumot uchun xaritadagi belgini bosing',
                style: K.pgSub)),
          ]),
        ]),
      ),
    ]);
  }

  Widget _rstat(IconData ic, String value, String label) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ic, color: T.green, size: 24),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: T.navy, fontSize: 28, fontWeight: FontWeight.w800)),
          Text(label, style: K.pgSub),
        ]),
      );
}

// ─────────────────────────── DETAL ───────────────────────────
class DistrictDetailScreen extends ConsumerWidget {
  const DistrictDetailScreen({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final async = ref.watch(districtsProvider);
    final geoAsync = ref.watch(districtGeoProvider);
    final labels = (t['distKV'] as List).cast<String>();
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(name, sub: t['pDistricts']),
          AsyncView(async, data: (list) {
            final d = list.firstWhere((x) => x.name == name,
                orElse: () => District.fromJson({'name': name}));
            final geo = geoAsync.asData?.value[name];
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (geo != null) ...[
                _DistrictMap(name: name, geo: geo),
                const SizedBox(height: 14),
              ],
              Row(children: [
                _kpi(Icons.terrain_rounded, labels[4], '${fmt(d.auksion)} ${t['objects']}', T.green),
                _kpi(Icons.description_rounded, labels[5], '${fmt(d.arizalar)} ${t['applications']}', T.blue),
              ]),
              const SizedBox(height: 14),
              _bordered(child: Column(children: [
                _row(Icons.badge_rounded, labels[0], d.head),
                _row(Icons.engineering_rounded, labels[1], d.engineer),
                _row(Icons.phone_rounded, labels[2], d.phoneClean.isEmpty ? '—' : d.phoneClean),
                _row(Icons.schedule_rounded, labels[3], d.hours, last: true),
              ])),
              const SizedBox(height: 14),
              // Rahbar qabuliga o'tish
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.go('/reception'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  decoration: BoxDecoration(gradient: T.gNavyH, borderRadius: BorderRadius.circular(18), boxShadow: T.shadow),
                  child: Row(children: [
                    const Icon(Icons.event_available_rounded, color: Colors.white, size: 28),
                    const SizedBox(width: 14),
                    Expanded(child: Text(t['distToReception'] ?? 'Shu tuman rahbari qabuliga yozilish',
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 30),
                  ]),
                ),
              ),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _kpi(IconData ic, String label, String value, Color color) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          decoration: BoxDecoration(color: color.withOpacity(0.09), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ic, color: color, size: 26),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(color: T.navy, fontSize: 26, fontWeight: FontWeight.w800)),
            Text(label, style: K.pgSub),
          ]),
        ),
      );

  Widget _bordered({required Widget child}) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: T.line),
          boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 22, offset: Offset(0, 8))],
        ),
        child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 7, color: T.green),
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(20, 6, 20, 6), child: child)),
        ])),
      );

  Widget _row(IconData ic, String label, String value, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: T.line))),
        child: Row(children: [
          Icon(ic, color: T.green, size: 24),
          const SizedBox(width: 14),
          Expanded(flex: 4, child: Text(label, style: const TextStyle(color: T.muted, fontSize: 18))),
          const SizedBox(width: 12),
          Expanded(flex: 5, child: Text(value, textAlign: TextAlign.right,
              style: const TextStyle(color: T.navy, fontSize: 20, fontWeight: FontWeight.w700))),
        ]),
      );
}

/// Tuman xaritasi — keshlangan OSM tiles + chegara poligoni + markaz + "Yo'nalish" (OSRM).
class _DistrictMap extends ConsumerStatefulWidget {
  const _DistrictMap({required this.name, required this.geo});
  final String name;
  final DistrictGeo geo;
  @override
  ConsumerState<_DistrictMap> createState() => _DistrictMapState();
}

class _DistrictMapState extends ConsumerState<_DistrictMap> {
  final _mc = MapController();
  List<LatLng>? _route;
  bool _routing = false;

  void _fit() {
    final poly = widget.geo.poly;
    try {
      if (poly != null && poly.length >= 3) {
        _mc.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(poly), padding: const EdgeInsets.all(28)));
      } else {
        _mc.move(widget.geo.center, 11);
      }
    } catch (_) {}
  }

  Future<void> _toggleRoute() async {
    if (_route != null) { setState(() => _route = null); return; }
    setState(() => _routing = true);
    final r = await _fetchRoute(_palace, widget.geo.center);
    if (!mounted) return;
    setState(() { _route = r; _routing = false; });
    if (r != null && r.length >= 2) {
      try {
        _mc.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(r), padding: const EdgeInsets.all(30)));
      } catch (_) {}
    }
  }

  Future<List<LatLng>?> _fetchRoute(LatLng from, LatLng to) async {
    final url = 'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final resp = await client.getUrl(Uri.parse(url)).then((r) => r.close());
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final j = json.decode(body) as Map<String, dynamic>;
      final coords = (((j['routes'] as List?)?.first as Map?)?['geometry'] as Map?)?['coordinates'] as List?;
      if (coords == null) return null;
      return coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final tp = ref.watch(tileProviderProvider).asData?.value;
    final poly = widget.geo.poly;
    if (tp == null) {
      return const SizedBox(height: 340, child: Center(child: CircularProgressIndicator(color: T.green)));
    }
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 340,
          decoration: BoxDecoration(border: Border.all(color: T.line), borderRadius: BorderRadius.circular(20)),
          child: FlutterMap(
            mapController: _mc,
            options: MapOptions(
              initialCenter: widget.geo.center,
              initialZoom: poly != null ? 9.5 : 11,
              onMapReady: _fit,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              _osmTiles(tp),
              if (poly != null)
                PolygonLayer(polygons: [
                  Polygon(points: poly, color: T.green.withOpacity(0.16), borderColor: T.green, borderStrokeWidth: 3.5),
                ]),
              if (_route != null)
                PolylineLayer(polylines: [
                  Polyline(points: _route!, color: T.blue, strokeWidth: 5),
                ]),
              MarkerLayer(markers: [
                if (_route != null)
                  const Marker(point: _palace, width: 46, height: 46, alignment: Alignment.topCenter,
                      child: Icon(Icons.account_balance_rounded, color: T.blue, size: 40,
                          shadows: [Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2))])),
                Marker(point: widget.geo.center, width: 46, height: 46, alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on, color: T.green, size: 46,
                        shadows: [Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2))])),
              ]),
            ],
          ),
        ),
      ),
      // Yo'nalish tugmasi
      Positioned(
        right: 14, bottom: 14,
        child: GestureDetector(
          onTap: _routing ? null : _toggleRoute,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: _route != null ? T.blue : Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _routing
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: T.blue))
                  : Icon(_route != null ? Icons.close_rounded : Icons.directions_rounded,
                      color: _route != null ? Colors.white : T.blue, size: 24),
              const SizedBox(width: 8),
              Text(
                _route != null ? (t['distHideRoute'] ?? 'Yashirish') : (t['distRoute'] ?? 'Yo‘nalish'),
                style: TextStyle(color: _route != null ? Colors.white : T.navy, fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
