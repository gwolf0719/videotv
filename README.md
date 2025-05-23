# VideoTV

這是一個簡單的 Flutter Android 範例。啟動後會透過隱藏式 `WebView` 抓取 jable.tv 的影片清單，
點擊影片後會解析頁面中的 m3u8 連結並以 `video_player` 播放。

## 安裝套件

在 `pubspec.yaml` 中加入：

```yaml
dependencies:
  webview_flutter: ^4.0.7
  video_player: ^2.7.0
```

接著執行 `flutter pub get`。

## 權限設定

**Android** 在 `android/app/src/main/AndroidManifest.xml` 加入：

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

**iOS** 在 `ios/Runner/Info.plist` 加入：

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

## 開始使用

1. 安裝 Flutter SDK。
2. 在專案目錄執行下列指令：

```bash
flutter pub get
flutter run
```

若缺少 `android` 或 `ios` 等平台資料夾，可先執行：

```bash
flutter create .
```

之後再次執行 `flutter run`。
