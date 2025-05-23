# VideoTV

This Flutter Android project fetches a video list from [jable.tv](https://jable.tv/categories/chinese-subtitle/) on startup. The list is stored as `video_list.json` in the app's documents directory and displayed with preview images. Tapping a video opens a player using the `video_player` package.

## Getting Started

Install Flutter and run:

```bash
flutter pub get
flutter create .    # if platform folders are missing
flutter run
```

If the Android build complains about an NDK mismatch, edit `android/app/build.gradle.kts` and set:

```kotlin
android {
    ndkVersion = "27.0.12077973"
}
```

## Dependencies
- http
- html
- path_provider
- video_player
