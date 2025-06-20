import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../shared/models/video_model.dart';
import 'firebase_service.dart';

class VideoRepository {
  final DatabaseReference _dbRef;
  final FirebaseService _firebaseService = FirebaseService();
  final Map<String, List<VideoModel>> _cache = {};
  final StreamController<List<VideoModel>> _realVideosController = StreamController.broadcast();
  final StreamController<List<VideoModel>> _animeVideosController = StreamController.broadcast();
  List<VideoModel> _cachedVideos = [];
  List<VideoModel> _cachedFavorites = [];
  VideoType _currentFilter = VideoType.real;
  
  // 資料流控制器
  final StreamController<List<VideoModel>> _videosStreamController = 
      StreamController<List<VideoModel>>.broadcast();
  final StreamController<List<VideoModel>> _favoritesStreamController = 
      StreamController<List<VideoModel>>.broadcast();
  final StreamController<bool> _loadingStreamController = 
      StreamController<bool>.broadcast();

  // 公開的資料流
  Stream<List<VideoModel>> get videosStream => _videosStreamController.stream;
  Stream<List<VideoModel>> get favoritesStream => _favoritesStreamController.stream;
  Stream<bool> get loadingStream => _loadingStreamController.stream;

  // Getters
  List<VideoModel> get cachedVideos => _cachedVideos;
  List<VideoModel> get cachedFavorites => _cachedFavorites;
  bool get isFirebaseAvailable => _firebaseService.isAvailable;
  VideoType get currentFilter => _currentFilter;

  // 獲取快取的真人影片
  List<VideoModel> getCachedRealVideos() {
    return _cachedVideos.where((v) => v.type == VideoType.real).toList();
  }

  // 獲取快取的動漫影片
  List<VideoModel> getCachedAnimeVideos() {
    return _cachedVideos.where((v) => v.type == VideoType.anime).toList();
  }

  // 真人影片流
  Stream<List<VideoModel>> get realVideosStream => _realVideosController.stream;
  
  // 動漫影片流
  Stream<List<VideoModel>> get animeVideosStream => _animeVideosController.stream;

  VideoRepository(this._dbRef);

  void _setLoading(bool loading) {
    _loadingStreamController.add(loading);
  }

  Future<void> initialize() async {
    await _firebaseService.initialize();
    if (_firebaseService.isAvailable) {
      await loadFavoriteVideos();
      await loadAllVideos();
    } else {
      // Firebase 不可用時，使用本地測試數據
      _initializeTestData();
    }
  }

  void _initializeTestData() {
    print('🔧 正在初始化本地測試數據...');
    
    final testVideos = [
      VideoModel(
        id: 'test_1',
        title: '測試真人影片 1',
        description: '這是一個測試用的真人影片',
        thumbnailUrl: 'https://via.placeholder.com/300x200/FF6B9D/FFFFFF?text=真人影片1',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
        type: VideoType.real,
        publishTime: DateTime.now().subtract(const Duration(days: 1)),
      ),
      VideoModel(
        id: 'test_2',
        title: '測試真人影片 2',
        description: '這是另一個測試用的真人影片',
        thumbnailUrl: 'https://via.placeholder.com/300x200/6C63FF/FFFFFF?text=真人影片2',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
        type: VideoType.real,
        publishTime: DateTime.now().subtract(const Duration(days: 2)),
      ),
      VideoModel(
        id: 'test_3',
        title: '測試動漫影片 1',
        description: '這是一個測試用的動漫影片',
        thumbnailUrl: 'https://via.placeholder.com/300x200/4ECDC4/FFFFFF?text=動漫影片1',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
        type: VideoType.anime,
        publishTime: DateTime.now().subtract(const Duration(days: 3)),
      ),
      VideoModel(
        id: 'test_4',
        title: '測試動漫影片 2',
        description: '這是另一個測試用的動漫影片',
        thumbnailUrl: 'https://via.placeholder.com/300x200/FF6B9D/FFFFFF?text=動漫影片2',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
        type: VideoType.anime,
        publishTime: DateTime.now().subtract(const Duration(days: 4)),
      ),
    ];

    _cachedVideos = testVideos;
    _currentFilter = VideoType.real;
    
    // 發送資料到流中
    _videosStreamController.add(_getFilteredVideos());
    _realVideosController.add(testVideos.where((v) => v.type == VideoType.real).toList());
    _animeVideosController.add(testVideos.where((v) => v.type == VideoType.anime).toList());
    
    print('✅ 本地測試數據初始化完成，共載入 ${testVideos.length} 個測試影片');
  }

  Future<void> loadAllVideos() async {
    _setLoading(true);
    try {
      final videos = await _firebaseService.loadAllVideos();
      _cachedVideos = videos;
      _currentFilter = VideoType.real;
      _videosStreamController.add(_getFilteredVideos());
    } catch (e) {
      print('載入所有影片失敗: $e');
      _videosStreamController.addError(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadFavoriteVideos() async {
    _setLoading(true);
    try {
      final favorites = await _firebaseService.loadFavoriteVideos();
      _cachedFavorites = favorites;
      _favoritesStreamController.add(_cachedFavorites);
    } catch (e) {
      print('載入收藏影片失敗: $e');
      _favoritesStreamController.addError(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadVideosByType(VideoType type) async {
    _setLoading(true);
    try {
      final videos = await _firebaseService.loadVideosByType(type);
      _cachedVideos = videos;
      _currentFilter = type;
      _videosStreamController.add(_getFilteredVideos());
    } catch (e) {
      print('載入${type.toString()}失敗: $e');
      _videosStreamController.addError(e);
    } finally {
      _setLoading(false);
    }
  }

  void filterVideos(VideoType type) {
    _currentFilter = type;
    _videosStreamController.add(_getFilteredVideos());
  }

  List<VideoModel> _getFilteredVideos() {
    return _cachedVideos.where((video) => 
      _currentFilter == VideoType.all || video.type == _currentFilter
    ).toList();
  }

  Future<bool> addToFavorites(VideoModel video) async {
    try {
      final success = await _firebaseService.addToFavorites(video);
      if (success) {
        if (!_cachedFavorites.any((v) => v.id == video.id)) {
          _cachedFavorites.add(video);
          _favoritesStreamController.add(_cachedFavorites);
        }
      }
      return success;
    } catch (e) {
      print('添加到收藏失敗: $e');
      return false;
    }
  }

  Future<bool> removeFromFavorites(String videoId) async {
    try {
      final success = await _firebaseService.removeFromFavorites(videoId);
      if (success) {
        _cachedFavorites.removeWhere((video) => video.id == videoId);
        _favoritesStreamController.add(_cachedFavorites);
      }
      return success;
    } catch (e) {
      print('從收藏移除失敗: $e');
      return false;
    }
  }

  bool isFavorite(String? videoId) {
    if (videoId == null) return false;
    return _cachedFavorites.any((video) => video.id == videoId);
  }

  Future<Map<String, dynamic>?> checkForUpdate() async {
    return await _firebaseService.checkForUpdate();
  }

  void updateVideos(List<VideoModel> videos) {
    _cachedVideos = videos;
    _videosStreamController.add(_getFilteredVideos());
  }

  VideoModel? getVideoById(String id) {
    try {
      return _cachedVideos.firstWhere((video) => video.id == id);
    } catch (e) {
      return null;
    }
  }

  // 載入真人影片
  Future<void> loadRealVideos() async {
    if (!_firebaseService.isAvailable) {
      // Firebase 不可用時返回測試數據
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
      // Firebase 不可用時返回測試數據
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

  // 更新真人影片
  Future<void> updateRealVideos(List<VideoModel> videos) async {
    try {
      final data = videos.map((v) => v.toMap()).toList();
      await _dbRef.child('realVideos').set(data);
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
      final data = videos.map((v) => v.toMap()).toList();
      await _dbRef.child('animeVideos').set(data);
      _cache['anime'] = videos;
      _animeVideosController.add(videos);
    } catch (e) {
      print('更新動漫影片失敗: $e');
      throw e;
    }
  }

  // 從快取獲取真人影片
  List<VideoModel> getCachedRealVideos() {
    return _cache['real'] ?? [];
  }

  // 從快取獲取動漫影片
  List<VideoModel> getCachedAnimeVideos() {
    return _cache['anime'] ?? [];
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
            
            // 確保有必要的欄位
            if (map['title'] != null) {
              // 設定預設類型
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
              // 設定預設類型
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
      return video.title.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  void dispose() {
    _videosStreamController.close();
    _favoritesStreamController.close();
    _loadingStreamController.close();
    _realVideosController.close();
    _animeVideosController.close();
  }
} 