# Kadastr Kiosk — Windows build & run

Native Flutter **Windows desktop** kiosk (replaces the Electron web kiosk). Backend
stays `https://api.andkadastrai.uz` (no changes). UI is built at a fixed 1080×1920
portrait canvas, letterboxed.

## Build the Windows `.exe`

Voice (mic), audio (TTS), and the kiosk window can only be tested on **Windows**.
Two ways to get a build:

### A) On a Windows PC (simplest)
Needs: Flutter 3.22.2 + Visual Studio 2022 (Desktop C++ workload).
```powershell
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release
# output: build\windows\x64\runner\Release\kadastr_kiosk.exe  (+ DLLs/data folder)
```
Run `kadastr_kiosk.exe` directly. Microphone access on Win32 is ungated (no manifest
needed); Windows may still show a mic privacy prompt the first time.

### B) GitHub Actions (no Windows PC needed)
`.github/workflows/windows.yml` builds on a `windows-latest` runner and uploads a
`kadastr-kiosk-windows.zip` artifact. To use it:
1. Push the `kiosk_flutter/` folder to a GitHub repo (it is not yet under git).
2. The workflow runs on push / manual dispatch → download the zip artifact → unzip →
   run `kadastr_kiosk.exe`.

## Test checklist on the device
- Home: live stats (14 districts, 10 758 …), language switch (uz/ru/en).
- Screens: districts/detail, phones, news/detail, social QR, docs, reception (book),
  xatlov, property (parcel check), illegal (3 methods).
- Virtual keyboard pops for every text field; uz `ʻ/oʻ/gʻ` keys.
- **Voice (AI page):** greets, listens, transcribes, answers with TTS. Speak a question.
- **MyID QR** (illegal → 3rd method): QR shows; scan with MyID app → your record only.
- Heartbeat: kiosk shows online in admin (`/kiosk/ping`).

## Pending (later milestones)
- M3.1: lip-sync avatar video (media_kit), global "KAI" wake word.
- M4: native camera face-compare (camera_windows) + video appeal; MyGov/OneID.
- M5: kiosk lockdown (fullscreen/autostart/hotkey via window_manager) — wire in main.dart.
- M6: Inno Setup installer + swap the Electron kiosk on the PC.
