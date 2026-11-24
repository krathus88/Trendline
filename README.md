# Trendline

A weight-loss and meal-planning app for Android (with a Windows desktop build). It plans your week of food, including meal prep, from UK supermarket products, and adapts calorie targets to your real weight trend.

## Development

Requires the Flutter SDK (stable channel). First-time cloud setup (Supabase project, Discord sign-in, allowlist): [`docs/SETUP.md`](docs/SETUP.md).

```sh
flutter pub get
flutter analyze
flutter test
flutter run --dart-define-from-file=dart_defines.json             # Android
flutter run -d windows --dart-define-from-file=dart_defines.json  # Windows
```

## Licence

[PolyForm Strict 1.0.0](LICENSE.md)
