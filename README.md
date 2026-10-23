# Elicius IoT Platform — mobile app (Flutter)

Android + iOS version of the web dashboard in this repo (`../src`). It talks to
the same backends, uses the same login, roles and dashboards, so anything saved
on the web shows up here and vice versa.

## Run it

Flutter SDK is installed at `~/development/flutter` (add `~/development/flutter/bin` to `PATH`).

```bash
cd mobile
flutter pub get
flutter run                      # on a connected phone or a running emulator
flutter build apk --release      # Android APK → build/app/outputs/flutter-apk/
flutter build ipa                # iOS — needs a Mac with Xcode + an Apple developer account
```

If the first Android build fails with "Gradle threw an error while downloading
artifacts", Java is failing over IPv6 on this network — build with
`JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true flutter build apk`.

### Pointing at other backends

Hosts default to production (`bs1` … `bs7`). Override any of them at build time:

```bash
flutter run --dart-define=VISUALIZATION_HOST=http://10.0.2.2:8001 \
            --dart-define=AIR_QUALITY_REPORTS_HOST=http://10.0.2.2:8002
```

`10.0.2.2` is your computer as seen from the Android emulator (a real phone needs
the computer's LAN IP). Keys: `CAAS_HOST`, `DEVICE_REGISTRATION_HOST`,
`VISUALIZATION_HOST`, `DATA_DOWNLOADER_HOST`, `ALERTS_HOST`,
`AIR_QUALITY_REPORTS_HOST`, `MQTT_WS_HOST`, `DEVICE_TELEMETRY_HOST`.

## Screens

| Web page | Mobile |
|---|---|
| Login | Login (keep me signed in = token saved in the device keystore; SSO shown disabled) |
| Home | Home — the user's `Home_page` dashboard, live + historical widgets |
| Live status | Group list → device cards (Live / Threshold / Inactive, packet count, date + time) → tap for full payload + live trend |
| Plant View | View with live markers; edit: base image, markers, square/rectangle shapes, canvas size; Export PNG via share sheet |
| Dashboards | Group → folders (create / rename / delete) → dashboard; long-press a widget to remove it |
| Device alerts | KPIs, warning-vs-alarm chart, filters, paging; alert sheet with timeline, action history, Troubleshoot, Acknowledge |
| Alert rules (thresholds) | Per-device rules: add / edit / enable / delete (platform admin) |
| Data downloader | Group, devices, range, email, job name, interval; recent exports with download (share sheet) |
| AI reports | Group → devices (unsupported ones disabled), templates, period, generate + progress; view (in-app), download, email, delete |
| Device Administration | Tabs: devices (+ group membership), groups, MQTT servers, device types → parameters (with Import JSON) |
| Access management | Tabs: organisations, members (add by user search, roles), groups (device links), device permissions, roles |

Not carried over to mobile: the drag-and-resize dashboard **builder** (adding new
widgets and arranging the grid) — build dashboards on the web; they appear here.
Plant SCADA, Industry Design and Assistant are hidden in the web sidebar, so they
aren't in the app either.

## Code layout (mirrors the web app's layering)

- `lib/core/api/endpoints.dart` — every backend host and route (web: `apiService.tsx` `ServiceHost` / `Endpoint`).
- `lib/core/api/api_service.dart` — the only HTTP client: Bearer token, error messages, 401 → sign out.
- `lib/api/` — domain APIs (telemetry + live stream, dashboards, alerts, plant views).
- `lib/state/` — Riverpod providers (the Flutter equivalent of the Redux slices).
- `lib/core/permissions.dart` — roles, page rules and action rules (web: `lib/permissions.ts`). Add rules there, not in screens.
- `lib/core/theme/app_theme.dart` — design tokens copied from `src/styles/tokens.css`.
- `lib/screens/` — one folder per page; `lib/widgets/` — shared chrome and the dashboard widget renderer.

Plant views: this app uses the backend's `/v1/digital-twins` routes when the
server has them; otherwise it saves plant views on the phone (and says so on screen).

## Tests

```bash
flutter analyze
flutter test
```
