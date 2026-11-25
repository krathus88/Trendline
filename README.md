# Trendline

A weight-loss and meal-planning app for Android (with a Windows desktop build). It plans your week of food, including meal prep, from UK supermarket products, and adapts calorie targets to your real weight trend.

## Development

Requires the Flutter SDK (stable channel). First-time cloud setup (Supabase project, Discord sign-in, allowlist): [`docs/SETUP.md`](docs/SETUP.md). Releasing on Google Play: [`docs/PLAY_CONSOLE.md`](docs/PLAY_CONSOLE.md).

```sh
flutter pub get
flutter analyze
flutter test
flutter run --dart-define-from-file=dart_defines.json             # Android
flutter run -d windows --dart-define-from-file=dart_defines.json  # Windows
```

## Privacy

What the app stores and why: [`docs/PRIVACY.md`](docs/PRIVACY.md), and how to delete your account: [`docs/DELETE_ACCOUNT.md`](docs/DELETE_ACCOUNT.md) (both generated from `lib/domain/privacy_policy.dart` with `dart run tool/write_privacy_policy.dart`).

## Licence

[PolyForm Strict 1.0.0](LICENSE.md)
