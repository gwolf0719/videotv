# VideoTV

A Flutter Android project that fetches the latest videos from
`https://jable.tv/categories/chinese-subtitle/`. The crawler logic was
converted from Python to Dart. When the app starts it loads `video_list.json`
from the application's documents directory. Tapping the refresh icon runs the
crawler again and updates the file.

## Getting Started

Install Flutter and run the following commands:

```bash
flutter pub get
flutter run
```

This project has only the essential files (`pubspec.yaml` and `lib/` sources). If platform folders are missing, create them with:

```bash
flutter create .
```

Then run `flutter run` again.

The crawler relies on the `http`, `html`, and `path_provider` packages which
are fetched automatically by `flutter pub get`.
