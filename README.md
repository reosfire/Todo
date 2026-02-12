# Todo

A cross-platform todo app built with Flutter and Material 3.

## Features

- **Tasks** — create, edit, reorder, and complete tasks with drag-and-drop support
- **Lists & Folders** — organize tasks into lists, group lists into collapsible folders
- **Tags** — label tasks with colored tags for quick filtering
- **Recurring Tasks** — set daily, weekly, monthly, or yearly recurrence rules
- **Smart Lists** — auto-filtered views like *Today*, *Upcoming*, and *All Tasks*
- **Dropbox Sync** — real-time two-way sync via Dropbox API with PKCE OAuth, longpoll-based change detection, and per-entity file storage
- **Dark Mode** — follows system theme automatically

## Tech Stack

| Layer | Details |
|---|---|
| Framework | Flutter (Dart) |
| State management | Provider + ChangeNotifier |
| Design system | Material 3 |
| Cloud sync | Dropbox API v2 (OAuth2 PKCE, longpoll) |
| Persistence | Local JSON files + SharedPreferences |

## Project Structure

```
lib/
├── main.dart              # App entry point
├── state/
│   └── app_state.dart     # Central state management
├── models/                # Data models (Task, TaskList, Folder, Tag, SmartList, etc.)
├── services/
│   ├── storage_service.dart   # Local persistence
│   ├── dropbox_service.dart   # Dropbox OAuth & file API
│   └── sync_service.dart      # Per-entity sync orchestration
└── ui/                    # Pages, dialogs, and list views
```

## Getting Started

### Prerequisites

- Flutter SDK 3.9+
- A Dropbox app key (optional, for sync)

### Run locally

```bash
flutter pub get
flutter run
```

### Dropbox sync setup

1. Create a Dropbox app at [dropbox.com/developers/apps](https://www.dropbox.com/developers/apps) → *Scoped access* → *App folder*
2. Enable `files.content.read` and `files.content.write` permissions
3. Add redirect URIs: your web URL and `todoapp://auth` for mobile
4. Put your app key in `lib/services/dropbox_service.dart`

## Building

### Web

```bash
flutter build web
```

### Android APK (optimized)

```bash
flutter build apk --release --shrink --obfuscate --split-debug-info=build/debug-info
```

## License

This project is provided as-is for personal use.
