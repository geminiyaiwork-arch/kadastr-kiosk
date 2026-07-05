import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/i18n/strings.dart';
import '../../core/network/models.dart';
import '../../core/network/repository.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/fmt.dart';
import '../../shell/kiosk_shell.dart';
import '../common/widgets.dart';

/// Tuman geo-ma'lumoti (markaz + chegara poligoni) — assets/geo/andijan_districts.json.
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

// ─────────────────────────── RO'YXAT ───────────────────────────
class DistrictsScreen extends ConsumerWidget {
  const DistrictsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final async = ref.watch(districtsProvider);
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['pDistricts'], sub: t['distSub']),
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
              // XARITA — tuman chegarasi/markeri
              if (geo != null) ...[
                _DistrictMap(name: name, geo: geo),
                const SizedBox(height: 14),
              ],
              // KPI plitkalar — auksion yerlar / arizalar
              Row(children: [
                _kpi(Icons.terrain_rounded, labels[4], '${fmt(d.auksion)} ${t['objects']}', T.green),
                _kpi(Icons.description_rounded, labels[5], '${fmt(d.arizalar)} ${t['applications']}', T.blue),
              ]),
              const SizedBox(height: 14),
              // Ma'lumot — yashil chegarali karta (ikonli qatorlar)
              _bordered(child: Column(children: [
                _row(Icons.badge_rounded, labels[0], d.head),
                _row(Icons.engineering_rounded, labels[1], d.engineer),
                _row(Icons.phone_rounded, labels[2], d.phoneClean.isEmpty ? '—' : d.phoneClean),
                _row(Icons.schedule_rounded, labels[3], d.hours, last: true),
              ])),
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

/// Tuman xaritasi — OSM tiles + chegara poligoni (yashil) + markaz markeri.
class _DistrictMap extends StatefulWidget {
  const _DistrictMap({required this.name, required this.geo});
  final String name;
  final DistrictGeo geo;
  @override
  State<_DistrictMap> createState() => _DistrictMapState();
}

class _DistrictMapState extends State<_DistrictMap> {
  final _mc = MapController();

  void _fit() {
    final poly = widget.geo.poly;
    try {
      if (poly != null && poly.length >= 3) {
        _mc.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(poly),
          padding: const EdgeInsets.all(28),
        ));
      } else {
        _mc.move(widget.geo.center, 11);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final poly = widget.geo.poly;
    return ClipRRect(
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
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'uz.andkadastrai.kiosk',
              tileProvider: NetworkTileProvider(),
            ),
            if (poly != null)
              PolygonLayer(polygons: [
                Polygon(
                  points: poly,
                  color: T.green.withOpacity(0.16),
                  borderColor: T.green,
                  borderStrokeWidth: 3.5,
                ),
              ]),
            MarkerLayer(markers: [
              Marker(
                point: widget.geo.center,
                width: 46, height: 46,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.location_on, color: T.green, size: 46,
                    shadows: [Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2))]),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
