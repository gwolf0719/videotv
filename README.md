# VideoTV

A simple Flutter Android project that shows a predefined list of videos. Tapping a video opens a player using the `video_player` package.

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

### Android NDK Compatibility

If the build fails with an error about an incompatible Android NDK version,
edit `android/app/build.gradle.kts` and set the `ndkVersion` inside the
`android` block:

```kotlin
android {
    ndkVersion = "27.0.12077973"
}
```

This matches the requirement of some plugins such as `video_player_android` and
`path_provider_android`.
