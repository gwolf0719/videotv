# VideoTV 開發指南

## 專案概述

VideoTV 是一個 Flutter Android TV 影片播放器應用，支援手機操作和遙控器操作，具備影片播放、分類瀏覽、Firebase 資料同步等功能。

## 專案架構

### 目錄結構

```
lib/
├── core/
│   └── constants/
│       └── app_constants.dart          # 應用常數定義
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
│           ├── video_card.dart         # 影片卡片
│           └── video_grid.dart         # 影片網格
├── services/
│   └── video_repository.dart           # 資料倉庫
├── shared/
│   └── models/
│       └── video_model.dart            # 影片資料模型
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
    // ... 更多測試資料
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

## 元件設計規範

### 1. 影片卡片組件 (video_card.dart)

```dart
class VideoCard extends StatelessWidget {
  final VideoModel video;
  final VoidCallback onTap;
  final bool isFocused;
  final FocusNode focusNode;

  const VideoCard({
    Key? key,
    required this.video,
    required this.onTap,
    this.isFocused = false,
    required this.focusNode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && 
            event.logicalKey == LogicalKeyboardKey.select) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isFocused 
                ? AppConstants.focusedCardColor 
                : AppConstants.cardColor,
            borderRadius: BorderRadius.circular(8),
            border: isFocused 
                ? Border.all(color: Colors.white, width: 2) 
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 影片縮圖
              Expanded(
                flex: 3,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8)
                    ),
                    image: video.thumbnailUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(video.thumbnailUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: video.thumbnailUrl.isEmpty
                      ? const Icon(Icons.video_library, size: 50)
                      : null,
                ),
              ),
              // 影片資訊
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        style: const TextStyle(
                          fontSize: AppConstants.smallFontSize,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (video.duration.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          video.duration,
                          style: TextStyle(
                            fontSize: AppConstants.captionFontSize,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### 2. 控制面板組件 (control_panel.dart)

```dart
class ControlPanel extends StatefulWidget {
  final Function(String) onVideoTypeChanged;
  final VoidCallback onReload;
  final VoidCallback onSettings;

  const ControlPanel({
    Key? key,
    required this.onVideoTypeChanged,
    required this.onReload,
    required this.onSettings,
  }) : super(key: key);

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  String _selectedVideoType = '全部';
  bool _isAdvancedVisible = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 影片類型篩選
          _buildVideoTypeFilter(),
          const SizedBox(height: 16),
          
          // 基本功能按鈕
          _buildBasicControls(),
          
          // 高級功能區塊
          _buildAdvancedSection(),
        ],
      ),
    );
  }

  Widget _buildVideoTypeFilter() {
    return Row(
      children: [
        const Text('影片類型：'),
        const SizedBox(width: 16),
        ...['全部', '真人', '動漫'].map((type) => 
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedVideoType = type;
                });
                widget.onVideoTypeChanged(type);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedVideoType == type 
                    ? AppConstants.primaryColor 
                    : Colors.grey,
              ),
              child: Text(type),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBasicControls() {
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: widget.onReload,
          icon: const Icon(Icons.refresh),
          label: const Text('重新載入'),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: widget.onSettings,
          icon: const Icon(Icons.settings),
          label: const Text('設定'),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _isAdvancedVisible = !_isAdvancedVisible;
            });
          },
          child: Text(_isAdvancedVisible ? '隱藏高級功能' : '顯示高級功能'),
        ),
      ],
    );
  }

  Widget _buildAdvancedSection() {
    if (!_isAdvancedVisible) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text('高級功能', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: _performCrawling,
              child: const Text('執行爬蟲'),
            ),
            ElevatedButton(
              onPressed: _clearCache,
              child: const Text('清除快取'),
            ),
            ElevatedButton(
              onPressed: _showVersionInfo,
              child: const Text('版本資訊'),
            ),
          ],
        ),
      ],
    );
  }

  void _performCrawling() {
    // 爬蟲邏輯
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('爬蟲功能執行中...')),
    );
  }

  void _clearCache() {
    // 清除快取邏輯
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('快取已清除')),
    );
  }

  void _showVersionInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('版本資訊'),
        content: Text('${AppConstants.appName} v${AppConstants.appVersion}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }
}
```

## 服務層設計

### VideoRepository

```dart
class VideoRepository extends ChangeNotifier {
  List<VideoModel> _videos = [];
  List<VideoModel> _animeVideos = [];
  bool _isLoading = false;
  String? _error;

  List<VideoModel> get videos => _videos;
  List<VideoModel> get animeVideos => _animeVideos;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> initialize() async {
    _setLoading(true);
    try {
      await _loadTestData();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _loadTestData() async {
    // 模擬載入延遲
    await Future.delayed(const Duration(milliseconds: 500));
    
    _videos = AppConstants.testVideos
        .map((data) => VideoModel.fromJson(data))
        .toList();
    
    _animeVideos = _videos.where((video) => video.isAnime).toList();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  Future<void> reload() async {
    await initialize();
  }
}
```

## 最佳實踐

### 1. 錯誤處理

```dart
// 統一的錯誤處理
try {
  await someAsyncOperation();
} catch (e) {
  debugPrint('Error: $e');
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
        home: HomePage(),
      ),
    );
  }
}
```

### 3. 焦點管理

```dart
// TV 遙控器焦點處理
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
          switch (event.logicalKey) {
            case LogicalKeyboardKey.select:
              // 處理選擇鍵
              return KeyEventResult.handled;
            case LogicalKeyboardKey.arrowUp:
              // 處理上方向鍵
              return KeyEventResult.handled;
            default:
              return KeyEventResult.ignored;
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

### 4. 資源管理

```dart
// 正確的資源釋放
class ResourceWidget extends StatefulWidget {
  @override
  State<ResourceWidget> createState() => _ResourceWidgetState();
}

class _ResourceWidgetState extends State<ResourceWidget> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network('url');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

## 測試策略

### 1. 單元測試

```dart
// test/models/video_model_test.dart
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
  });
}
```

### 2. Widget 測試

```dart
// test/widgets/video_card_test.dart
void main() {
  testWidgets('VideoCard should display video title', (tester) async {
    final video = VideoModel(
      title: 'Test Video',
      thumbnailUrl: '',
      videoUrl: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VideoCard(
          video: video,
          onTap: () {},
          focusNode: FocusNode(),
        ),
      ),
    );

    expect(find.text('Test Video'), findsOneWidget);
  });
}
```

## 部署配置

### 1. 建置設定

```yaml
# pubspec.yaml
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

### 2. Android 配置

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

### 1. 新功能開發
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

### 3. 效能優化
- 使用 `const` 構造函數
- 避免不必要的 `setState`
- 正確管理 Focus 節點
- 優化圖片載入
- 使用適當的快取策略

## 故障排除

### 常見問題

1. **Firebase 初始化失敗**
   - 檢查 `google-services.json` 配置
   - 確認網路連接狀態
   - 使用本地測試數據模式

2. **影片播放失敗**
   - 檢查影片 URL 有效性
   - 確認網路權限
   - 驗證影片格式支援

3. **遙控器操作無響應**
   - 檢查 Focus 節點設定
   - 驗證按鍵事件處理
   - 確認 TV 模式配置

### 除錯技巧

```dart
// 使用除錯工具
import 'package:flutter/foundation.dart';

void debugLog(String message) {
  if (kDebugMode) {
    debugPrint('[VideoTV] $message');
  }
}

// 條件斷點
assert(() {
  debugLog('Debug information');
  return true;
}());
```

## 版本更新記錄

### v1.0.0 (2024-06-20)
- 完成專案重構
- 實作模組化架構
- 添加 TV 遙控器支援
- 整合 Firebase 服務
- 建立完整測試套件

---

此文檔提供了 VideoTV 專案的完整開發指南，包含架構設計、配置標準、最佳實踐等，請在開發過程中參照使用。 