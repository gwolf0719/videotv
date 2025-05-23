# VideoTV

A simple Flutter Android project. When launched the app runs a Python web
scraper to download the latest video list from jable.tv. The list is saved as
`video_list.json` in the device's documents directory and displayed with
thumbnails. Selecting a video opens the player using the `video_player` package.

## Getting Started

Install Flutter and run the following commands:

```bash
flutter pub get
flutter run
```

Before running the app the Python dependencies must be installed so the scraper
can be executed:

```bash
pip install -r requirements.txt
```

You can also run the scraper manually with:

```bash
python3 crawler.py
```

This project has only the essential files (`pubspec.yaml` and `lib/` sources). If platform folders are missing, create them with:

```bash
flutter create .
```

Then run `flutter run` again.
