# VideoTV

A simple Flutter Android project that fetches a list of videos from jable.tv at
startup. The crawler is implemented in Dart and stores a `video_list.json`
inside the app documents directory. Tapping a video opens a player using the
`video_player` package.

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

### Android NDK Version

If Gradle complains about mismatched NDK versions, open
`android/app/build.gradle.kts` and specify the version required by plugins:

```kotlin
android {
    ndkVersion = "27.0.12077973"
}
```
