# Contributing to Mnemo

Thanks for considering a contribution — Mnemo is small and intentionally
so, which makes improvements especially impactful.

## Setup

1. Install Flutter (stable, 3.x or newer) → https://docs.flutter.dev/get-started
2. Clone the repo and install deps:
   ```bash
   git clone https://github.com/prakash66958-netizen/mnemo.git
   cd mnemo
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   ```
3. Run on an Android device or emulator (API 23+):
   ```bash
   flutter run
   ```

## Before you open a PR

- `flutter analyze --no-fatal-infos` should pass.
- `flutter build apk --debug` should succeed.
- Keep privacy promises: no new outbound network calls, no new required
  permissions, no silent analytics.
- Favor small, focused PRs over large ones.

## Architecture notes

- Widgets live in `lib/features/<name>/` and `lib/widgets/`.
- Business logic lives in `lib/services/` as singletons (e.g.
  `MemoryRepository.instance`). Access them via Riverpod providers in
  `lib/features/shared/providers.dart`.
- Models in `lib/models/` are Isar collections. Running `build_runner` after
  editing any `@collection` class regenerates the `.g.dart` files.
- New Dart files should have a short file-level `///` doc comment explaining
  the file's purpose.

## What we won't merge

- Cloud sync that requires the user to sign in without a clear opt-in flow.
- Third-party analytics SDKs.
- Dependencies that add outbound network calls we can't justify.

## Questions

Open an issue with the `question` label or start a GitHub Discussion.
