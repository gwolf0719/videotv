# VideoTV

這是一個簡單的 Flutter Android 範例。啟動後會透過隱藏式 `WebView` 抓取 jable.tv 的影片清單，
點擊影片後會解析頁面中的 m3u8 連結並以 `video_player` 播放。

影片清單會同步儲存在 Firebase Realtime Database 的 `videos` 節點
(https://videotv-fc3b9-default-rtdb.firebaseio.com/)。

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
