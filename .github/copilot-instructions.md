# Copilot Instructions for `iboard_flutter`

## Architecture snapshot

- `lib/main.dart` wires a single `MaterialApp` around an extensive `MultiProvider`; almost all features hang off `ChangeNotifier` providers in `lib/providers`. Any new feature should plug into this graph so it initializes alongside the rest of the boot flow.
- `AppDataProvider` (`lib/providers/app_data_provider.dart`) is the source of truth for login/device identity, cached `SettingsModel`, timers (login, health check), and downstream dependency injection (e.g., it hands its `ApiClient` to ad/announcement/weather/printer providers). Keep long-lived timers and SharedPreferences access centralized here.
- Screen routing is simple: `/main` → `MainPage` hosts the default dashboard, `/live-monitor-webview` shows the remote monitor, while `/settings` and `/carousel-settings` expose admin flows. Widgets for the dashboard live in `lib/widgets/mainscreen/**` split into `top_display`, `mid_display`, `bottom_display` modules plus helper controls.

## State & data flow

- Carousel behavior is orchestrated by `CarouselStateProvider`, `TopAdCarouselProvider`, `FullscreenAdProvider`, and `AnnouncementCarouselProvider`. They exchange signals through explicit setter methods (see `MainScreenPage._setupProviderReferences`). Whenever you change timings or pause/resume semantics, update both the state provider and the concrete carousel provider to stay in sync.
- `WeatherProvider` owns the bottom ticker (weather cards, QR codes, warnings) and exposes `updateCarouselPauseState` so top-level pages can pause all timers together. Call its `initializeBottomCarousel()` + `startPeriodicUpdate()` mirrors when creating new entry points.
- Printer/payment flows talk to an Orange Pi edge box: `PrinterProvider` caches the IP (SharedPreferences), updates it via `updateOrangePiIp`, and schedules `startPeriodicHealthCheck`. Pairing code that assumes a printer exists must call `setApiClient` and `initialize()` before issuing print jobs.
- Network access is abstracted through `http/api_client.dart`, which handles retries, request timeouts, token refresh, and friendly error mapping. Never hit `http` directly; add wrappers inside `ApiClient` so login/token refresh stays consistent.

## Conventions & patterns

- Methods throughout the app include a numbered doc comment (`///5，描述...`). Preserve the numbering sequence when editing existing methods and add new numbers when adding methods in touched files.
- Logging is primarily via `logger` and `debugPrint`; messaging is bilingual/Chinese. Keep user-facing strings in Chinese where possible to match existing UX.
- Shared assets live under `assets/defaults/**`; most widgets expect a fallback image/JSON to exist. When introducing new asset-driven widgets, register them in `pubspec.yaml` and mirror the existing defaults pattern.
- Providers should expose explicit `initialize*`, `startPeriodic*`, and `set*Provider` hooks instead of relying on constructors. Follow the same pattern to avoid race conditions during `HomePageState._initializeDeviceId`.

## Developer workflow

- Install deps and pull generated code with:
  - `flutter pub get`
  - `flutter pub run build_runner build --delete-conflicting-outputs` whenever you touch model/provider annotations (Freezed/JsonSerializable comments are already in place even though Riverpod isnt used here).
- Quick sanity runs target large-format displays; prefer `flutter run -d linux` or a kiosk Android target. `flutter test` currently only exercises default samples—add focused widget/provider tests when you change business logic.
- For debugging carousel timing issues, rely on the built-in debug timers (`startDebugTimer`, `_startCarouselWatchdog`) instead of sprinkling new logs; extend those helpers if you need more insight.

## External touchpoints

- Backend contract lives in `httpapi.json` + `api.md`. Keep these in sync when you add endpoints, and update `AppDataProvider.initializeAndLogin`/`ApiClient` wrappers so token refresh hooks stay wired.
- Device metadata and files flow through `managers/file_manager.dart` and `utils/device_id_util.dart`. Reuse them rather than reimplementing storage/ID logic.

## Expectations for AI changes

- Favor the existing `provider` package; despite `.cursor/rules` mentioning Riverpod, this app is _not_ using it. Dont introduce Riverpod/HookConsumerWidget unless you are migrating the whole stack.
- Keep responses/code comments in Chinese when user-facing, and remember to tag new timer/worker logic with graceful cancellation in `dispose()`.
- Before sending large UI changes, sanity-check layout in `lib/widgets/mainscreen` to maintain the top (ads), mid (announcements/arrears), and bottom (weather/news) 3-zone structure.
