# VideoTV

A simple Flutter Android project that fetches the latest videos from
`jable.tv` on start. The crawler is implemented in Dart and stores the
retrieved list as `video_list.json` in the app's documents directory.
Tapping a video opens a player using the `video_player` package.

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

### Android NDK

If the build complains about mismatched NDK versions, edit
`android/app/build.gradle.kts` and make sure it contains:

```kotlin
android {
    ndkVersion = "27.0.12077973"
}
```
