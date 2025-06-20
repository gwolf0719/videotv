import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../shared/models/video_model.dart';
import 'firebase_service.dart';

class VideoRepository {
  final DatabaseReference _dbRef;
  final FirebaseService _firebaseService = FirebaseService();
  final Map<String, List<VideoModel>> _cache = {};
  
  // 資料流控制器
  final StreamController<List<VideoModel>> _realVideosController = StreamController.broadcast();
  final StreamController<List<VideoModel>> _animeVideosController = StreamController.broadcast();
  final StreamController<List<VideoModel>> _favoritesController = StreamController.broadcast();
  final StreamController<bool> _loadingController = StreamController.broadcast();

  // 快取資料
  List<VideoModel> _cachedVideos = [];
  List<VideoModel> _cachedFavorites = [];

  // 公開的資料流
  Stream<List<VideoModel>> get realVideosStream => _realVideosController.stream;
  Stream<List<VideoModel>> get animeVideosStream => _animeVideosController.stream;
  Stream<List<VideoModel>> get favoritesStream => _favoritesController.stream;
  Stream<bool> get loadingStream => _loadingController.stream;

  // Getters
  bool get isFirebaseAvailable => _firebaseService.isAvailable;

  VideoRepository(this._dbRef);

  // 初始化
  Future<void> initialize() async {
    await _firebaseService.initialize();
    if (_firebaseService.isAvailable) {
      await loadFavoriteVideos();
    } else {
      _initializeTestData();
    }
  }

  // 初始化測試資料
  void _initializeTestData() {
    print('🔧 正在初始化本地測試數據...');
    
    final testVideos = [
      VideoModel(
        id: 'test_real_1',
        title: '測試真人影片 1',
        description: '這是一個測試用的真人影片',
        thumbnailUrl: 'https://via.placeholder.com/300x200/FF6B9D/FFFFFF?text=真人影片1',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
        type: VideoType.real,
        duration: '10:25',
        uploadDate: DateTime.now().subtract(const Duration(days: 1)),
        tags: ['測試', '真人', '影片'],
      ),
      VideoModel(
        id: 'test_real_2',
        title: '測試真人影片 2',
        description: '這是另一個測試用的真人影片',
        thumbnailUrl: 'https://via.placeholder.com/300x200/6C63FF/FFFFFF?text=真人影片2',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
        type: VideoType.real,
        duration: '15:30',
        uploadDate: DateTime.now().subtract(const Duration(days: 2)),
        tags: ['測試', '真人', '夢境'],
      ),
      VideoModel(
        id: 'test_anime_1',
        title: '測試動漫影片 1',
        description: '這是一個測試用的動漫影片',
        thumbnailUrl: 'https://via.placeholder.com/300x200/4ECDC4/FFFFFF?text=動漫影片1',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
        type: VideoType.anime,
        duration: '8:45',
        uploadDate: DateTime.now().subtract(const Duration(days: 3)),
        tags: ['測試', '動漫', '冒險'],
      ),
      VideoModel(
        id: 'test_anime_2',
        title: '測試動漫影片 2',
        description: '這是另一個測試用的動漫影片',
        thumbnailUrl: 'https://via.placeholder.com/300x200/FF6B9D/FFFFFF?text=動漫影片2',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
        type: VideoType.anime,
        duration: '12:10',
        uploadDate: DateTime.now().subtract(const Duration(days: 4)),
        tags: ['測試', '動漫', '逃脫'],
      ),
    ];

    _cachedVideos = testVideos;
    _cache['real'] = testVideos.where((v) => v.type == VideoType.real).toList();
    _cache['anime'] = testVideos.where((v) => v.type == VideoType.anime).toList();
    
    // 發送資料到流中
    _realVideosController.add(_cache['real']!);
    _animeVideosController.add(_cache['anime']!);
    
    print('✅ 本地測試數據初始化完成，共載入 ${testVideos.length} 個測試影片');
  }

  // 載入真人影片
  Future<void> loadRealVideos() async {
    if (!_firebaseService.isAvailable) {
      final testRealVideos = _cachedVideos.where((v) => v.type == VideoType.real).toList();
      _cache['real'] = testRealVideos;
      _realVideosController.add(testRealVideos);
      return;
    }

    try {
      final snapshot = await _dbRef.child('realVideos').get();
      final videos = _parseVideosFromSnapshot(snapshot, VideoType.real);
      _cache['real'] = videos;
      _realVideosController.add(videos);
    } catch (e) {
      print('載入真人影片失敗: $e');
      _realVideosController.addError(e);
    }
  }

  // 載入動漫影片
  Future<void> loadAnimeVideos() async {
    if (!_firebaseService.isAvailable) {
      final testAnimeVideos = _cachedVideos.where((v) => v.type == VideoType.anime).toList();
      _cache['anime'] = testAnimeVideos;
      _animeVideosController.add(testAnimeVideos);
      return;
    }

    try {
      final snapshot = await _dbRef.child('animeVideos').get();
      final videos = _parseVideosFromSnapshot(snapshot, VideoType.anime);
      _cache['anime'] = videos;
      _animeVideosController.add(videos);
    } catch (e) {
      print('載入動漫影片失敗: $e');
      _animeVideosController.addError(e);
    }
  }

  // 載入收藏影片
  Future<void> loadFavoriteVideos() async {
    if (!_firebaseService.isAvailable) {
      _cachedFavorites = [];
      _favoritesController.add(_cachedFavorites);
      return;
    }

    try {
      final favorites = await _firebaseService.loadFavoriteVideos();
      _cachedFavorites = favorites;
      _favoritesController.add(_cachedFavorites);
    } catch (e) {
      print('載入收藏影片失敗: $e');
      _favoritesController.addError(e);
    }
  }

  // 獲取快取的真人影片
  List<VideoModel> getCachedRealVideos() {
    return _cache['real'] ?? [];
  }

  // 獲取快取的動漫影片
  List<VideoModel> getCachedAnimeVideos() {
    return _cache['anime'] ?? [];
  }

  // 更新真人影片
  Future<void> updateRealVideos(List<VideoModel> videos) async {
    try {
      if (_firebaseService.isAvailable) {
        final data = videos.map((v) => v.toMap()).toList();
        await _dbRef.child('realVideos').set(data);
      }
      _cache['real'] = videos;
      _realVideosController.add(videos);
    } catch (e) {
      print('更新真人影片失敗: $e');
      throw e;
    }
  }

  // 更新動漫影片
  Future<void> updateAnimeVideos(List<VideoModel> videos) async {
    try {
      if (_firebaseService.isAvailable) {
        final data = videos.map((v) => v.toMap()).toList();
        await _dbRef.child('animeVideos').set(data);
      }
      _cache['anime'] = videos;
      _animeVideosController.add(videos);
    } catch (e) {
      print('更新動漫影片失敗: $e');
      throw e;
    }
  }

  // 添加到收藏
  Future<bool> addToFavorites(VideoModel video) async {
    try {
      if (_firebaseService.isAvailable) {
        final success = await _firebaseService.addToFavorites(video);
        if (!success) return false;
      }
      
      if (!_cachedFavorites.any((v) => v.id == video.id)) {
        _cachedFavorites.add(video);
        _favoritesController.add(_cachedFavorites);
      }
      return true;
    } catch (e) {
      print('添加到收藏失敗: $e');
      return false;
    }
  }

  // 從收藏移除
  Future<bool> removeFromFavorites(String videoId) async {
    try {
      if (_firebaseService.isAvailable) {
        final success = await _firebaseService.removeFromFavorites(videoId);
        if (!success) return false;
      }
      
      _cachedFavorites.removeWhere((video) => video.id == videoId);
      _favoritesController.add(_cachedFavorites);
      return true;
    } catch (e) {
      print('從收藏移除失敗: $e');
      return false;
    }
  }

  // 檢查是否為收藏
  bool isFavorite(String? videoId) {
    if (videoId == null) return false;
    return _cachedFavorites.any((video) => video.id == videoId);
  }

  // 根據 ID 獲取影片
  VideoModel? getVideoById(String id) {
    try {
      // 先從快取中查找
      for (final videos in _cache.values) {
        for (final video in videos) {
          if (video.id == id) return video;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 搜尋影片
  List<VideoModel> searchVideos(String query, {VideoType? type}) {
    List<VideoModel> allVideos = [];
    
    if (type == null || type == VideoType.real) {
      allVideos.addAll(getCachedRealVideos());
    }
    if (type == null || type == VideoType.anime) {
      allVideos.addAll(getCachedAnimeVideos());
    }

    if (query.isEmpty) return allVideos;

    final lowerQuery = query.toLowerCase();
    return allVideos.where((video) {
      return video.title.toLowerCase().contains(lowerQuery) ||
             (video.description?.toLowerCase().contains(lowerQuery) ?? false) ||
             (video.tags?.any((tag) => tag.toLowerCase().contains(lowerQuery)) ?? false);
    }).toList();
  }

  // 解析 Firebase 資料
  List<VideoModel> _parseVideosFromSnapshot(DataSnapshot snapshot, VideoType defaultType) {
    if (!snapshot.exists) return [];

    final data = snapshot.value;
    final List<VideoModel> videos = [];

    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          try {
            final map = Map<String, dynamic>.from(item);
            
            if (map['title'] != null) {
              if (map['type'] == null) {
                map['type'] = defaultType.name;
              }
              
              // 兼容舊格式
              if (map['img_url'] != null && map['thumbnailUrl'] == null) {
                map['thumbnailUrl'] = map['img_url'];
              }
              if (map['detail_url'] != null && map['videoUrl'] == null) {
                map['videoUrl'] = map['detail_url'];
              }

              final video = VideoModel.fromMap(map);
              videos.add(video);
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
              if (map['type'] == null) {
                map['type'] = defaultType.name;
              }
              
              // 兼容舊格式
              if (map['img_url'] != null && map['thumbnailUrl'] == null) {
                map['thumbnailUrl'] = map['img_url'];
              }
              if (map['detail_url'] != null && map['videoUrl'] == null) {
                map['videoUrl'] = map['detail_url'];
              }

              final video = VideoModel.fromMap(map);
              videos.add(video);
            }
          } catch (e) {
            print('解析影片資料失敗: $e');
          }
        }
      }
    }

    return videos;
  }

  // 釋放資源
  void dispose() {
    _realVideosController.close();
    _animeVideosController.close();
    _favoritesController.close();
    _loadingController.close();
  }
} 