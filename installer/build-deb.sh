#!/bin/bash
# Kadastr Kiosk — Linux .deb paket yasash (build/linux bundle'дан).
# Ishlatish:  bash installer/build-deb.sh   (loyiha ildizидаn yoki istalgan joyдан)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VER="$(grep -m1 '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//; s/+.*//')"
VER="${VER:-1.0.0}"
echo "==> Flutter Linux release build…"
flutter build linux --release

STAGE="installer/deb-build/kadastr-kiosk"
rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" "$STAGE/opt/kadastr-kiosk" "$STAGE/usr/bin" "$STAGE/usr/share/applications"
cp -r build/linux/x64/release/bundle/* "$STAGE/opt/kadastr-kiosk/"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: kadastr-kiosk
Version: $VER
Section: utils
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libgstreamer1.0-0, gstreamer1.0-plugins-base, gstreamer1.0-plugins-good, libpulse0, libstdc++6
Maintainer: Kadastr Agentligi <info@andkadastrai.uz>
Description: Davlat Kadastrlari Palatasi — Kiosk
 AI yordamchi, ovozli boshqaruv (wake-word + telefon QR pult), murojaat, xizmatlar.
EOF

cat > "$STAGE/usr/bin/kadastr-kiosk" <<'EOF'
#!/bin/bash
exec /opt/kadastr-kiosk/kadastr_kiosk "$@"
EOF
chmod +x "$STAGE/usr/bin/kadastr-kiosk"

cat > "$STAGE/usr/share/applications/kadastr-kiosk.desktop" <<EOF
[Desktop Entry]
Name=Kadastr Kiosk
Comment=Davlat Kadastrlari Palatasi — Kiosk
Exec=/usr/bin/kadastr-kiosk
Icon=/opt/kadastr-kiosk/data/flutter_assets/assets/images/logo1.png
Type=Application
Categories=Utility;
EOF

OUT="installer/kadastr-kiosk_${VER}_amd64.deb"
dpkg-deb --build --root-owner-group "$STAGE" "$OUT"
echo "==> Tayyor: $OUT"
ls -lh "$OUT"
