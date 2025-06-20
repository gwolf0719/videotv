# VideoTV 開發指南

## 專案概述

VideoTV 是一個 Flutter Android TV 影片播放器應用，支援手機操作和遙控器操作，具備影片播放、分類瀏覽、Firebase 資料同步等功能。

## 專案架構

### 目錄結構

```
lib/
├── core/
│   ├── constants/
│   │   └── app_constants.dart          # 應用常數定義
│   └── theme/
│       └── app_theme.dart              # 主題配置
├── crawlers/
│   ├── anime_crawler.dart              # 動漫爬蟲
│   └── real_crawler.dart               # 真人影片爬蟲
├── features/
│   └── tv/
│       ├── pages/
│       │   ├── home_page.dart          # 主頁面
│       │   └── video_player_page.dart  # 播放器頁面
│       └── widgets/
│           ├── control_panel.dart      # 控制面板
│           ├── search_bar.dart         # 搜尋列
│           ├── video_card.dart         # 影片卡片
│           └── video_grid.dart         # 影片網格
├── services/
│   ├── firebase_service.dart           # Firebase 服務
│   └── video_repository.dart           # 資料倉庫
├── shared/
│   ├── models/
│   │   └── video_model.dart            # 影片資料模型
│   └── widgets/
│       └── background_pattern_widget.dart # 背景圖案組件
└── main.dart                           # 應用入口
```

### 架構設計原則

1. **單一職責原則**：每個類別只負責一個功能
2. **依賴注入**：使用 Provider 進行狀態管理
3. **模組化設計**：按功能區分模組
4. **可測試性**：每個組件都可獨立測試

## 配置標準

### 1. 常數定義 (app_constants.dart)

```dart
class AppConstants {
  // 應用信息
  static const String appName = 'VideoTV';
  static const String appVersion = '1.0.0';
  
  // 網格佈局
  static const int gridCrossAxisCount = 3;
  static const double gridChildAspectRatio = 0.7;
  static const double gridSpacing = 16.0;
  
  // 字體大小
  static const double titleFontSize = 18.0;
  static const double smallFontSize = 14.0;
  static const double captionFontSize = 12.0;
  
  // 顏色定義
  static const Color primaryColor = Colors.blue;
  static const Color focusedCardColor = Colors.blueAccent;
  static const Color cardColor = Colors.grey;
  static const Color realVideoColor = Colors.green;
  static const Color animeVideoColor = Colors.orange;
  
  // Firebase 節點
  static const String videosNode = 'videos';
  static const String animeVideosNode = 'anime_videos';
  
  // 測試資料
  static const List<Map<String, String>> testVideos = [
    {
      'title': '測試影片 1',
      'thumbnailUrl': 'https://example.com/thumb1.jpg',
      'videoUrl': 'https://example.com/video1.mp4',
      'description': '這是測試影片的描述',
    },
  ];
}
```

### 2. 資料模型 (video_model.dart)

```dart
class VideoModel {
  final String title;
  final String thumbnailUrl;
  final String videoUrl;
  final String description;
  final String duration;
  final DateTime uploadDate;
  final List<String> tags;
  final bool isAnime;

  VideoModel({
    required this.title,
    required this.thumbnailUrl,
    required this.videoUrl,
    this.description = '',
    this.duration = '',
    DateTime? uploadDate,
    this.tags = const [],
    this.isAnime = false,
  }) : uploadDate = uploadDate ?? DateTime.now();

  // 向後相容性
  String get publishTime => uploadDate.toString();

  // JSON 序列化
  factory VideoModel.fromJson(Map<String, dynamic> json) {
    return VideoModel(
      title: json['title'] ?? '',
      thumbnailUrl: json['thumbnailUrl'] ?? '',
      videoUrl: json['videoUrl'] ?? '',
      description: json['description'] ?? '',
      duration: json['duration'] ?? '',
      uploadDate: json['uploadDate'] != null 
          ? DateTime.parse(json['uploadDate']) 
          : DateTime.now(),
      tags: List<String>.from(json['tags'] ?? []),
      isAnime: json['isAnime'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'thumbnailUrl': thumbnailUrl,
      'videoUrl': videoUrl,
      'description': description,
      'duration': duration,
      'uploadDate': uploadDate.toIso8601String(),
      'tags': tags,
      'isAnime': isAnime,
    };
  }
}
```

## TV 遙控器支援

### 焦點管理

```dart
class FocusableWidget extends StatefulWidget {
  @override
  State<FocusableWidget> createState() => _FocusableWidgetState();
}

class _FocusableWidgetState extends State<FocusableWidget> {
  final FocusNode _focusNode = FocusNode();

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // 避免使用 switch case，改用 if-else
          if (event.logicalKey == LogicalKeyboardKey.select) {
            // 處理選擇鍵
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            // 處理上方向鍵
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            // 處理下方向鍵
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            // 處理左方向鍵
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            // 處理右方向鍵
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(/* 內容 */),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }
}
```

## Firebase 整合

### 服務初始化

```dart
class FirebaseService {
  static bool _isInitialized = false;
  static DatabaseReference? _database;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _database = FirebaseDatabase.instance.ref();
      _isInitialized = true;
      debugPrint('✅ Firebase 初始化成功');
    } catch (e) {
      debugPrint('❌ Firebase 初始化失敗: $e');
      // 繼續使用本地測試數據
    }
  }

  static DatabaseReference? get database => _database;
  static bool get isInitialized => _isInitialized;
}
```

## 最佳實踐

### 1. 錯誤處理

```dart
// 統一的錯誤處理模式
try {
  await someAsyncOperation();
} catch (e) {
  debugPrint('❌ 操作失敗: $e');
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('操作失敗: $e')),
    );
  }
}
```

### 2. 狀態管理

```dart
// 使用 Provider 進行狀態管理
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VideoRepository()),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        theme: AppTheme.lightTheme,
        home: const HomePage(),
      ),
    );
  }
}
```

### 3. 資源管理

```dart
// 正確的資源釋放
class ResourceWidget extends StatefulWidget {
  @override
  State<ResourceWidget> createState() => _ResourceWidgetState();
}

class _ResourceWidgetState extends State<ResourceWidget> {
  late VideoPlayerController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network('url');
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
```

### 4. 顏色使用規範

```dart
// 避免直接使用整數顏色值
// ❌ 錯誤方式
Container(color: 0xFF2196F3)

// ✅ 正確方式  
Container(color: Color(0xFF2196F3))
// 或使用預定義常數
Container(color: AppConstants.primaryColor)
```

## 測試策略

### 1. 單元測試

```dart
// test/models/video_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videotv/shared/models/video_model.dart';

void main() {
  group('VideoModel', () {
    test('should create VideoModel from JSON', () {
      final json = {
        'title': 'Test Video',
        'thumbnailUrl': 'test.jpg',
        'videoUrl': 'test.mp4',
      };

      final video = VideoModel.fromJson(json);

      expect(video.title, 'Test Video');
      expect(video.thumbnailUrl, 'test.jpg');
      expect(video.videoUrl, 'test.mp4');
    });

    test('should convert VideoModel to JSON', () {
      final video = VideoModel(
        title: 'Test Video',
        thumbnailUrl: 'test.jpg',
        videoUrl: 'test.mp4',
      );

      final json = video.toJson();

      expect(json['title'], 'Test Video');
      expect(json['thumbnailUrl'], 'test.jpg');
      expect(json['videoUrl'], 'test.mp4');
    });
  });
}
```

### 2. Widget 測試

```dart
// test/widgets/video_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videotv/features/tv/widgets/video_card.dart';
import 'package:videotv/shared/models/video_model.dart';

void main() {
  testWidgets('VideoCard should display video title', (tester) async {
    final video = VideoModel(
      title: 'Test Video',
      thumbnailUrl: '',
      videoUrl: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoCard(
            video: video,
            onTap: () {},
            focusNode: FocusNode(),
          ),
        ),
      ),
    );

    expect(find.text('Test Video'), findsOneWidget);
  });
}
```

## 部署配置

### 1. pubspec.yaml

```yaml
name: videotv
description: A Flutter Android TV video player app
version: 1.0.0+1

environment:
  sdk: ">=3.0.0 <4.0.0"
  flutter: ">=3.10.0"

dependencies:
  flutter:
    sdk: flutter
  provider: ^6.0.5
  firebase_core: ^2.24.2
  firebase_database: ^10.4.0
  video_player: ^2.8.1
  webview_flutter: ^4.4.2
  wakelock_plus: ^1.1.4

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

### 2. Android TV 配置

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    
    <uses-feature 
        android:name="android.software.leanback" 
        android:required="false" />
    <uses-feature 
        android:name="android.hardware.touchscreen" 
        android:required="false" />
    
    <application
        android:label="VideoTV"
        android:icon="@mipmap/ic_launcher"
        android:banner="@drawable/banner">
        
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:screenOrientation="landscape">
            
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
                <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

## 開發流程

### 1. 新功能開發步驟
1. 在 `features/` 下創建對應模組
2. 實作 Widget 組件
3. 添加必要的服務
4. 更新常數定義
5. 編寫測試
6. 更新文檔

### 2. 程式碼審查清單
- [ ] 遵循單一職責原則
- [ ] 正確處理資源釋放
- [ ] 添加適當的錯誤處理
- [ ] 支援 TV 遙控器操作
- [ ] 編寫相應測試
- [ ] 更新相關文檔
- [ ] 使用正確的顏色定義方式
- [ ] 避免 switch case 與 LogicalKeyboardKey

### 3. 效能優化建議
- 使用 `const` 構造函數
- 避免不必要的 `setState`
- 正確管理 Focus 節點
- 優化圖片載入
- 使用適當的快取策略

## 故障排除

### 常見問題

1. **Firebase 初始化失敗**
   ```
   ❌ Firebase 初始化失敗: FirebaseApp name [DEFAULT] already exists!
   ```
   - 解決方案：添加重複初始化檢查
   - 使用本地測試數據作為備案

2. **影片播放失敗**
   - 檢查影片 URL 有效性
   - 確認網路權限
   - 驗證影片格式支援

3. **遙控器操作無響應**
   - 檢查 Focus 節點設定
   - 驗證按鍵事件處理
   - 確認 TV 模式配置

4. **編譯錯誤：switch case 問題**
   ```
   Non-constant case expression
   ```
   - 解決方案：改用 if-else 替代 switch case

### 除錯技巧

```dart
// 使用統一的除錯輸出格式
void debugLog(String message, {String prefix = 'VideoTV'}) {
  if (kDebugMode) {
    debugPrint('[$prefix] $message');
  }
}

// 使用表情符號增強可讀性
debugLog('✅ 操作成功');
debugLog('❌ 操作失敗');
debugLog('⚠️ 警告訊息');
```

## 版本更新記錄

### v1.0.0 (2024-06-20)
- ✅ 完成專案重構
- ✅ 實作模組化架構
- ✅ 添加 TV 遙控器支援
- ✅ 整合 Firebase 服務
- ✅ 建立完整測試套件
- ✅ 修復所有編譯錯誤
- ✅ 優化程式碼結構

### 重構成果
- **編譯狀態**: ✅ 零錯誤
- **警告數量**: 17個輕微警告
- **APK 狀態**: ✅ 成功產生
- **功能完整性**: ✅ 100% 保留

---

此文檔提供了 VideoTV 專案的完整開發指南，包含架構設計、配置標準、最佳實踐等，請在開發過程中參照使用。 