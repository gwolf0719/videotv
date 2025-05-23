# VideoTV

A simple Flutter Android project that fetches a list of videos using a Python
scraper. When the app starts it runs `crawler.py` to obtain the latest data and
stores the results locally for the home page.

## Getting Started

Install Flutter and run the following commands:

```bash
flutter pub get
flutter run
```

The app relies on a Python 3 script for scraping. Install the required Python
packages and Chrome WebDriver before running:

```bash
pip install requests beautifulsoup4 undetected-chromedriver selenium
```

The crawler writes `video_list.json` under the application documents directory
each time the app launches.

This project has only the essential files (`pubspec.yaml` and `lib/` sources). If platform folders are missing, create them with:

```bash
flutter create .
```

Then run `flutter run` again.
