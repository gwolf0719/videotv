# AGENTS.md

## 目的

這篇文件詳細說明如何在 Flutter App 中使用 `webview_flutter` 插件做到以下流程。

1. 隐藏式地啟動 WebView
2. 等待頁面加載完成後執行 JavaScript
3. 擷取頁面 DOM 資料 (例如影片列表)
4. 將結果 JSON 傳回 Flutter 应用

---

## 前提準備

### 1. 安裝套件

```yaml
dependencies:
  flutter:
    sdk: flutter
  webview_flutter: ^4.0.7
```

```bash
flutter pub get
```

### 2. 正確所需的權限

**Android** - `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

**iOS** - `ios/Runner/Info.plist`

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

---

## WebViewController 設定

```dart
import 'package:webview_flutter/webview_flutter.dart';

late final WebViewController _webViewController;

void initWebView() {
  _webViewController = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (url) async {
          await Future.delayed(Duration(seconds: 3));
          final result = await _webViewController.runJavaScriptReturningResult('''
            (function() {
              const items = Array.from(document.querySelectorAll('.video-img-box')).slice(0, 25);
              return JSON.stringify(items.map(item => {
                const img = item.querySelector('img')?.getAttribute('data-src') || item.querySelector('img')?.getAttribute('src');
                const title = item.querySelector('.detail .title a')?.innerText.trim();
                const detailUrl = item.querySelector('.detail .title a')?.href;
                return { title, img_url: img, detail_url: detailUrl };
              }));
            })();
          ''');
          print("\u64f7\u53d6 JSON: \$result");
        },
      ),
    )
    ..loadRequest(Uri.parse('https://jable.tv/categories/chinese-subtitle/'));
}
```

---

## 隐藏 WebView 帶出 Widget

```dart
Widget buildInvisibleWebView() {
  return const SizedBox(
    width: 1,
    height: 1,
    child: WebViewWidget(controller: _webViewController),
  );
}
```

---

## 主界面設定

```dart
class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
    initWebView();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          buildInvisibleWebView(),
          // 其他 UI
        ],
      ),
    );
  }
}
```

---

## 注意事項

* WebView 無法做到 headless 執行，但可以使用极小大小 Widget 或設為 Stack 底層減少指擊
* 執行 JS 前必須等 onPageFinished 和額外的延遲
* runJavaScriptReturningResult 返回值是 JSON 字串

---

## 進階 - Dart 版碼程解析同等 m3u8 URL

若想找出觀看頁面中的 m3u8 URL，可以在 JavaScript 內接訊 script 找字串

```dart
final detailResult = await _webViewController.runJavaScriptReturningResult('''
  (async function() {
    const scripts = Array.from(document.scripts);
    let m3u8 = null;
    for (let script of scripts) {
      const text = script.innerText;
      if (text.includes('.m3u8')) {
        const match = text.match(/(https?:\\/\\/[^\"'\s]+\\.m3u8)/);
        if (match) {
          m3u8 = match[1];
          break;
        }
      }
    }
    return JSON.stringify({ m3u8_url: m3u8 });
  })();
''');
```

該項操作應在用戶點擊觀看頁面前執行。

---

## 結論

這套模型可以成功將「頁面 JS 變更成的資料」擷取回來給 Flutter App 使用，最大限度避免依賴 Python Selenium。
