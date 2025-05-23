# VideoTV

A simple Flutter Android project that loads a list of videos using a Python web
scraper. The scraper runs on app startup (if Python is available) and saves a
`video_list.json` file locally. Tapping a video opens a player using the
`video_player` package.

## Getting Started

Install Flutter and run the following commands:

```bash
flutter pub get
flutter run
```

The scraper requires Selenium and other Python packages. Install them with:

```bash
pip install -r requirements.txt
```

This project has only the essential files (`pubspec.yaml` and `lib/` sources). If platform folders are missing, create them with:

```bash
flutter create .
```

Then run `flutter run` again.
