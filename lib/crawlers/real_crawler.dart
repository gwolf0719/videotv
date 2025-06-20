import 'package:firebase_database/firebase_database.dart';
import '../shared/models/video_model.dart';
import '../core/constants/app_constants.dart';

/// 簡化版真人影片爬蟲
/// 這個版本專為重構後的架構設計，不依賴 WebViewController
class RealCrawler {
  final DatabaseReference? _dbRef;
  
  RealCrawler() : _dbRef = FirebaseDatabase.instance.ref().child(AppConstants.videosNode);

  /// 爬取並保存影片資料
  Future<List<VideoModel>> crawlAndSave() async {
    if (_dbRef == null) {
      throw Exception('Firebase 資料庫不可用');
    }

    try {
      // 模擬爬取過程 - 在實際實作中，這裡會是真實的網頁爬取邏輯
      final videos = await _simulateCrawling();
      
      // 載入現有資料
      final existingVideos = await _loadExistingData();
      
      // 合併新舊資料，避免重複
      final mergedVideos = _mergeVideos(existingVideos, videos);
      
      // 保存到 Firebase
      await _saveToFirebase(mergedVideos);
      
      return mergedVideos;
    } catch (e) {
      throw Exception('爬取真人影片失敗: $e');
    }
  }

  /// 模擬爬取過程
  Future<List<VideoModel>> _simulateCrawling() async {
    await Future.delayed(const Duration(seconds: 2));
    
    return [
      VideoModel(
        id: 'real_${DateTime.now().millisecondsSinceEpoch}_1',
        title: '新爬取的真人影片 1',
        description: '這是一個新爬取的真人影片',
        thumbnailUrl: 'https://via.placeholder.com/300x200/FF6B9D/FFFFFF?text=新真人影片1',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
        type: VideoType.real,
        duration: '20:30',
        uploadDate: DateTime.now(),
        tags: ['新爬取', '真人', '影片'],
      ),
      VideoModel(
        id: 'real_${DateTime.now().millisecondsSinceEpoch}_2',
        title: '新爬取的真人影片 2',
        description: '這是另一個新爬取的真人影片',
        thumbnailUrl: 'https://via.placeholder.com/300x200/6C63FF/FFFFFF?text=新真人影片2',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
        type: VideoType.real,
        duration: '18:45',
        uploadDate: DateTime.now(),
        tags: ['新爬取', '真人', '夢境'],
      ),
    ];
  }

  /// 載入現有資料
  Future<List<VideoModel>> _loadExistingData() async {
    try {
      final snapshot = await _dbRef!.get();
      if (!snapshot.exists) return [];

      final data = snapshot.value;
      final List<VideoModel> videos = [];

      if (data is List) {
        for (final item in data) {
          if (item is Map) {
            try {
              final map = Map<String, dynamic>.from(item);
              if (map['title'] != null) {
                videos.add(VideoModel.fromMap(map));
              }
            } catch (e) {
              print('解析影片資料失敗: $e');
            }
          }
        }
      } else if (data is Map) {
        for (final value in data.values) {
          if (value is Map) {
            try {
              final map = Map<String, dynamic>.from(value);
              if (map['title'] != null) {
                videos.add(VideoModel.fromMap(map));
              }
            } catch (e) {
              print('解析影片資料失敗: $e');
            }
          }
        }
      }

      return videos;
    } catch (e) {
      print('載入現有資料失敗: $e');
      return [];
    }
  }

  /// 合併新舊資料
  List<VideoModel> _mergeVideos(List<VideoModel> existing, List<VideoModel> newVideos) {
    final Map<String, VideoModel> videoMap = {};
    
    // 添加現有影片
    for (final video in existing) {
      videoMap[video.id] = video;
    }
    
    // 添加新影片（會覆蓋相同 ID 的舊影片）
    for (final video in newVideos) {
      videoMap[video.id] = video;
    }
    
    return videoMap.values.toList();
  }

  /// 保存到 Firebase
  Future<void> _saveToFirebase(List<VideoModel> videos) async {
    try {
      final data = videos.map((v) => v.toMap()).toList();
      await _dbRef!.set(data);
    } catch (e) {
      throw Exception('保存到 Firebase 失敗: $e');
    }
  }
}


