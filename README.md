# Mnemo

**Your private second brain.** An offline-first universal memory inbox for Android.

Mnemo catches screenshots, links, copied text, chat snippets, notes, ideas,
and reminders — then classifies, tags, and remembers them entirely on-device.
No cloud AI. No backend. No accounts. Nothing leaves your phone.

> 🌐 **Landing pages:**
> - Firebase Hosting: [https://mnemo-5d13a.web.app/](https://mnemo-5d13a.web.app/)
> - GitHub Pages: [https://prakash66958-netizen.github.io/mnemo/](https://prakash66958-netizen.github.io/mnemo/)
> - Source in [`docs/`](./docs)

---

## Highlights

- **Privacy first** — everything lives in an on-device Isar database.
- **Fully offline** — OCR, classification, and reminders all run locally.
- **Universal share target** — send anything from any Android app into Mnemo.
- **Habit tracker** — daily habits with optional recurring reminders (e.g.
  "drink water every 2 hours from 8 AM to 10 PM").
- **Custom categories** — unlimited user-created categories with auto-picked
  theme-matching icons.
- **Smart classifier** — bilingual (English + Hinglish) keyword rules tag
  reminders, promises, links, study, work, shopping, ideas, and more.
- **Promise detection** — spots commitments like "I'll send tomorrow at 5 pm"
  or "Kal bhej dunga" and offers to set a reminder.
- **Full backup / restore** — export to JSON, share to Drive / Gmail / Files
  via the system share sheet; imports round-trip every reminder and habit
  notification schedule.
- **Local full-text search** with category and date filters.
- **Material 3 UI** with light / dark / system theme.

## Tech stack

- **Flutter 3** (stable channel) + **Material 3**
- **Riverpod 2** — state management
- **Isar 3** — local NoSQL database
- **Google ML Kit Text Recognition** — on-device OCR for screenshots
- **flutter_local_notifications 18** — offline reminders and habit pings,
  with exact-alarm support, boot persistence, and a monochrome status-bar icon
- **go_router 14** — declarative routing
- **receive_sharing_intent** / **share_plus** — inbound + outbound share sheets
- **url_launcher** — external link handoff with a scheme allowlist
- **image_picker**, **path_provider**, **shared_preferences**, **intl**

## Project structure

```
.
├── android/          # Flutter Android host (AndroidManifest, Gradle)
├── lib/              # Dart source
│   ├── core/         # constants, theme, category enum + CategoryDef
│   ├── models/       # Isar entities (MemoryItem, Reminder, Habit, HabitCompletion)
│   ├── services/     # repositories + business logic (classifier, OCR,
│   │                 # notifications, share intent, share out, DB)
│   ├── features/     # per-screen UI grouped by feature
│   │   ├── inbox/
│   │   ├── categories/
│   │   ├── habits/
│   │   ├── reminder/
│   │   ├── memory/
│   │   ├── save/
│   │   ├── home/
│   │   ├── settings/
│   │   ├── onboarding/
│   │   └── shared/   # Riverpod providers
│   └── widgets/      # reusable UI (MemoryCard, CategoryBadge, MnemoNavBar, ...)
├── docs/
│   ├── index.html    # landing page (served by GitHub Pages)
│   ├── styles.css
│   ├── script.js
│   └── design/       # HTML design previews for the app UI
├── web/              # Flutter Web scaffold
└── test/             # widget + unit tests
```

The architecture is a clean one-way dependency chain:

```
UI (features/) → providers (shared/) → services/ → Isar
```

Each layer is replaceable in isolation; widgets never touch the DB directly.

## Running locally

```bash
# 1. Install Flutter (3.x stable). https://docs.flutter.dev/get-started
# 2. Connect an Android device or start an emulator (API 23+).
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Android `minSdk` is 23 (required by Isar + ML Kit).

## Building a release APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

For the Play Store, replace the debug signing config in
`android/app/build.gradle.kts` with your own `key.properties` and `.jks`
keystore — both are already in `.gitignore`.

## Permissions

Mnemo asks for the minimum required:

- `POST_NOTIFICATIONS` — show reminder alerts (Android 13+)
- `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` — fire reminders even when the
  phone is idle
- `RECEIVE_BOOT_COMPLETED` — re-register pending reminders after reboot
- `VIBRATE` — reminder haptics

No location, no contacts, no storage, no network. The app makes **zero**
outbound network calls at runtime (plugin-level HTTP clients from ML Kit and
url_launcher are included in the binary but the app doesn't invoke them).

## Privacy

- All memory content, screenshots, reminders, and habits are stored in
  `getApplicationDocumentsDirectory()` — app-private sandboxed storage.
- Screenshots are copied into an app-private folder; the original file
  doesn't need to stay.
- Backups are plain JSON files you export via the system share sheet
  (Drive, Gmail, Files, Bluetooth — your choice).
- Link tapping validates the URL scheme against an allowlist
  (`http`, `https`, `mailto`, `tel`, `sms`) so pasted links can't hand off
  to `intent://…` or `javascript:` payloads.

## Contributing

Issues and PRs welcome. See `CONTRIBUTING.md`.

## License

MIT — see [`LICENSE`](./LICENSE).
