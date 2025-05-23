# VideoTV

A simple Flutter Android project that fetches a video list from `jable.tv` using a Python crawler at startup. The resulting JSON is saved locally and displayed with preview images. Tapping a video opens a player using the `video_player` package.

## Getting Started

Install Flutter and run the following commands:

```bash
flutter pub get
flutter run
```

The Python crawler requires a few packages. Install them with:

```bash
pip install -r requirements.txt
```

This project has only the essential files (`pubspec.yaml` and `lib/` sources). If platform folders are missing, create them with:

```bash
flutter create .
```

Then run `flutter run` again.
