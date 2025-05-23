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

## Python Crawler

The app relies on a small Python script (`crawler.py`) to fetch the latest
videos from jable.tv. Install the required Python packages first:

```bash
pip install -r requirements.txt
```

Run the crawler manually or let the app execute it on startup. It writes
`video_list.json`, which the app reads to display the list.
