# VideoTV 配置參考

## 快速配置清單

### 常數定義模板
```dart
// lib/core/constants/app_constants.dart
class AppConstants {
  // 應用基本信息
  static const String appName = 'VideoTV';
  static const String appVersion = '1.0.0';
  
  // UI 配置
  static const int gridCrossAxisCount = 3;
  static const double gridChildAspectRatio = 0.7;
  static const double gridSpacing = 16.0;
  
  // 字體大小
  static const double titleFontSize = 18.0;
  static const double smallFontSize = 14.0;
  static const double captionFontSize = 12.0;
  
  // 顏色（使用 Color 物件而非整數）
  static const Color primaryColor = Colors.blue;
  static const Color focusedCardColor = Colors.blueAccent;
  static const Color cardColor = Colors.grey;
  
  // Firebase 節點名稱
  static const String videosNode = 'videos';
  static const String animeVideosNode = 'anime_videos';
}
```

### 資料模型模板
```dart
// lib/shared/models/video_model.dart
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

  // 向後相容性屬性
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

  Map<String, dynamic> toJson() => {
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
```

## TV 遙控器支援模板

### 按鍵處理（避免 switch case）
```dart
// 正確的按鍵處理方式
onKeyEvent: (node, event) {
  if (event is KeyDownEvent) {
    if (event.logicalKey == LogicalKeyboardKey.select) {
      onTap();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      FocusScope.of(context).previousFocus();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      FocusScope.of(context).nextFocus();
      return KeyEventResult.handled;
    }
  }
  return KeyEventResult.ignored;
}
```

### 焦點管理模板
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          border: _focusNode.hasFocus 
              ? Border.all(color: Colors.white, width: 2) 
              : null,
        ),
        child: YourWidget(),
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }
}
```

## 狀態管理模板

### VideoRepository 模板
```dart
class VideoRepository extends ChangeNotifier {
  List<VideoModel> _videos = [];
  bool _isLoading = false;
  String? _error;

  List<VideoModel> get videos => _videos;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> initialize() async {
    _setLoading(true);
    try {
      await _loadData();
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ 載入失敗: $e');
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  Future<void> _loadData() async {
    // 實作資料載入邏輯
  }
}
```

### Provider 設定模板
```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VideoRepository()),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        home: HomePage(),
      ),
    );
  }
}
```

## 組件設計模板

### 影片卡片組件
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
              // 縮圖
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
              // 標題
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    video.title,
                    style: const TextStyle(
                      fontSize: AppConstants.smallFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

## 錯誤處理模板

### 統一錯誤處理
```dart
// 統一的錯誤處理函數
void handleError(BuildContext context, dynamic error, {String? message}) {
  debugPrint('❌ 錯誤: $error');
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message ?? '操作失敗: $error'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

// 使用範例
try {
  await someAsyncOperation();
} catch (e) {
  handleError(context, e, message: '載入影片失敗');
}
```

### Firebase 初始化模板
```dart
class FirebaseService {
  static bool _isInitialized = false;
  static DatabaseReference? _database;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Firebase.initializeApp();
      _database = FirebaseDatabase.instance.ref();
      _isInitialized = true;
      debugPrint('✅ Firebase 初始化成功');
    } catch (e) {
      debugPrint('❌ Firebase 初始化失敗: $e');
      // 使用本地測試數據模式
    }
  }

  static DatabaseReference? get database => _database;
  static bool get isInitialized => _isInitialized;
}
```

## 開發規範

### 必須遵循的規則
1. **顏色定義**: 使用 `Color()` 而非整數值
2. **按鍵處理**: 使用 if-else 而非 switch case
3. **資源管理**: 正確釋放 FocusNode 和 Controller
4. **錯誤處理**: 統一的錯誤處理模式
5. **常數使用**: 所有硬編碼值都應定義為常數

### 程式碼審查清單
- [ ] 是否使用正確的顏色定義方式？
- [ ] 是否避免了 switch case 與 LogicalKeyboardKey？
- [ ] 是否正確釋放了所有資源？
- [ ] 是否添加了適當的錯誤處理？
- [ ] 是否支援 TV 遙控器操作？

### 除錯輸出格式
```dart
// 統一的除錯輸出
debugPrint('✅ 成功: 操作完成');
debugPrint('❌ 錯誤: 操作失敗');
debugPrint('⚠️ 警告: 需要注意');
debugPrint('ℹ️ 資訊: 一般訊息');
```

## pubspec.yaml 核心依賴
```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.0.5          # 狀態管理
  firebase_core: ^2.24.2    # Firebase 核心
  firebase_database: ^10.4.0 # 資料庫
  video_player: ^2.8.1      # 影片播放
  wakelock_plus: ^1.1.4     # 螢幕常亮

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

## Android TV 必要配置
```xml
<!-- AndroidManifest.xml -->
<uses-feature 
    android:name="android.software.leanback" 
    android:required="false" />
<uses-feature 
    android:name="android.hardware.touchscreen" 
    android:required="false" />

<category android:name="android.intent.category.LEANBACK_LAUNCHER" />
```

---

此配置參考提供了開發 VideoTV 時的核心模板和最佳實踐，請複製相關模板並根據需求調整。 