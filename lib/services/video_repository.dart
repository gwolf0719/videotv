import 'dart:async';
import '../shared/models/video_model.dart';
import 'local_storage_service.dart';

class VideoRepository {
  final LocalStorageService _localStorageService = LocalStorageService();
  final Map<String, List<VideoModel>> _cache = {};
  final StreamController<List<VideoModel>> _realVideosController = StreamController.broadcast();
  final StreamController<List<VideoModel>> _animeVideosController = StreamController.broadcast();
  List<VideoModel> _cachedVideos = [];
  List<VideoModel> _cachedFavorites = [];
  VideoType _currentFilter = VideoType.real;
  bool _isLoadingFromCloud = false;
  
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
  bool get isFirebaseAvailable => false;
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

  VideoRepository();

  void _setLoading(bool loading) {
    _loadingStreamController.add(loading);
  }

  Future<void> initialize() async {
    print('🚀 開始初始化 VideoRepository...');
    
    // 先載入本地暫存資料
    await _loadLocalCacheData();
    
    // 載入本地收藏
    await _loadLocalFavorites();
    
    print('✅ VideoRepository 初始化完成 (本地模式)');
  }
  
  // 載入本地暫存資料
  Future<void> _loadLocalCacheData() async {
    try {
      final hasCachedData = await _localStorageService.hasCachedData();
      
      if (hasCachedData) {
        print('📱 載入本地暫存資料...');
        final cachedVideos = await _localStorageService.getCachedVideoList();
        _cachedVideos = cachedVideos;
        _currentFilter = VideoType.real;
        
        // 發送資料到流中
        _videosStreamController.add(_getFilteredVideos());
        _realVideosController.add(cachedVideos.where((v) => v.type == VideoType.real).toList());
        _animeVideosController.add(cachedVideos.where((v) => v.type == VideoType.anime).toList());
        
        print('✅ 成功載入本地暫存 ${cachedVideos.length} 個影片');
      } else {
        print('⚠️ 沒有本地暫存資料，使用測試資料');
        _initializeTestData();
      }
    } catch (e) {
      print('❌ 載入本地暫存失敗: $e，使用測試資料');
      _initializeTestData();
    }
  }
  
  // 載入本地收藏
  Future<void> _loadLocalFavorites() async {
    try {
      final favoriteIds = await _localStorageService.getFavoriteVideoIds();
      _cachedFavorites = _cachedVideos.where((video) => 
        favoriteIds.contains(video.id)
      ).toList();
      _favoritesStreamController.add(_cachedFavorites);
      print('✅ 載入本地收藏 ${_cachedFavorites.length} 個影片');
    } catch (e) {
      print('❌ 載入本地收藏失敗: $e');
    }
  }

  void _initializeTestData() {
    print('🔧 正在初始化本地測試數據...');
    
    final List<VideoModel> testVideos = [
      VideoModel(
        id: 'test_1',
        title: '測試真人影片 1',
        thumbnailUrl: 'https://via.placeholder.com/300x200/FF6B9D/FFFFFF?text=真人影片1',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
        type: VideoType.real,
        addedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      VideoModel(
        id: 'test_2',
        title: '測試真人影片 2',
        thumbnailUrl: 'https://via.placeholder.com/300x200/6C63FF/FFFFFF?text=真人影片2',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
        type: VideoType.real,
        addedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      VideoModel(
        id: 'test_3',
        title: '測試動漫影片 1',
        thumbnailUrl: 'https://via.placeholder.com/300x200/4ECDC4/FFFFFF?text=動漫影片1',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
        type: VideoType.anime,
        addedAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
      VideoModel(
        id: 'test_4',
        title: '測試動漫影片 2',
        thumbnailUrl: 'https://via.placeholder.com/300x200/FF6B9D/FFFFFF?text=動漫影片2',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
        type: VideoType.anime,
        addedAt: DateTime.now().subtract(const Duration(days: 4)),
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
      final videos = await _localStorageService.getCachedVideoList();
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
      final favorites = await _localStorageService.getFavoriteVideoIds();
      _cachedFavorites = _cachedVideos.where((video) => 
        favorites.contains(video.id)
      ).toList();
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
      final videos = await _localStorageService.getCachedVideoList();
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
      // 先更新本地
      await _localStorageService.addToFavorites(video.id);
      
      if (!_cachedFavorites.any((v) => v.id == video.id)) {
        _cachedFavorites.add(video);
        _favoritesStreamController.add(_cachedFavorites);
      }
      
      return true;
    } catch (e) {
      print('添加到收藏失敗: $e');
      return false;
    }
  }

  Future<bool> removeFromFavorites(String videoId) async {
    try {
      // 先更新本地
      await _localStorageService.removeFromFavorites(videoId);
      
      _cachedFavorites.removeWhere((video) => video.id == videoId);
      _favoritesStreamController.add(_cachedFavorites);
      
      return true;
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
    return null;
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
  
  // 獲取影片的完整資訊（包含播放路徑）
  Future<VideoModel?> getVideoWithPlayUrl(String videoId) async {
    try {
      // 先從本地獲取基本資訊
      final localVideo = getVideoById(videoId);
      if (localVideo == null) {
        print('❌ 找不到影片: $videoId');
        return null;
      }
      
      // 如果本地已有播放路徑，直接返回
      if (localVideo.hasVideoUrl) {
        return localVideo;
      }
      
      print('⚠️ 無法獲取影片播放路徑，返回本地資訊');
      return localVideo;
      
    } catch (e) {
      print('❌ 獲取影片播放路徑失敗: $e');
      return getVideoById(videoId);
    }
  }
  
  // 檢查是否正在從雲端載入
  bool get isLoadingFromCloud => _isLoadingFromCloud;
  
  // 獲取本地快取統計資訊
  Future<Map<String, dynamic>> getCacheInfo() async {
    try {
      final count = await _localStorageService.getCachedVideoCount();
      final hasCache = await _localStorageService.hasCachedData();
      
      return {
        'hasCache': hasCache,
        'videoCount': count,
        'realCount': _cachedVideos.where((v) => v.type == VideoType.real).length,
        'animeCount': _cachedVideos.where((v) => v.type == VideoType.anime).length,
        'favoriteCount': _cachedFavorites.length,
      };
    } catch (e) {
      return {
        'hasCache': false,
        'videoCount': 0,
        'realCount': 0,
        'animeCount': 0,
        'favoriteCount': 0,
      };
    }
  }
  
  // 清空本地快取
  Future<void> clearLocalCache() async {
    try {
      await _localStorageService.clearCache();
      _cachedVideos.clear();
      _cachedFavorites.clear();
      
      // 重新初始化測試資料
      _initializeTestData();
      
      print('✅ 本地快取已清空並重新初始化');
    } catch (e) {
      print('❌ 清空本地快取失敗: $e');
    }
  }

  // 載入真人影片
  Future<void> loadRealVideos() async {
    if (!isFirebaseAvailable) {
      // Firebase 不可用時返回測試數據
      final testRealVideos = _cachedVideos.where((v) => v.type == VideoType.real).toList();
      _cache['real'] = testRealVideos;
      _realVideosController.add(testRealVideos);
      return;
    }

    try {
      final videos = await _localStorageService.getCachedVideoList();
      _cache['real'] = videos;
      _realVideosController.add(videos.where((v) => v.type == VideoType.real).toList());
    } catch (e) {
      print('載入真人影片失敗: $e');
      _realVideosController.addError(e);
    }
  }

  // 載入動漫影片
  Future<void> loadAnimeVideos() async {
    if (!isFirebaseAvailable) {
      // Firebase 不可用時返回測試數據
      final testAnimeVideos = _cachedVideos.where((v) => v.type == VideoType.anime).toList();
      _cache['anime'] = testAnimeVideos;
      _animeVideosController.add(testAnimeVideos);
      return;
    }

    try {
      final videos = await _localStorageService.getCachedVideoList();
      _cache['anime'] = videos;
      _animeVideosController.add(videos.where((v) => v.type == VideoType.anime).toList());
    } catch (e) {
      print('載入動漫影片失敗: $e');
      _animeVideosController.addError(e);
    }
  }

  // 更新真人影片
  Future<void> updateRealVideos(List<VideoModel> videos) async {
    try {
      await _localStorageService.cacheVideoList(videos);
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
      await _localStorageService.cacheVideoList(videos);
      _cache['anime'] = videos;
      _animeVideosController.add(videos);
    } catch (e) {
      print('更新動漫影片失敗: $e');
      throw e;
    }
  }

  // 搜尋影片
  List<VideoModel> searchVideos(String query, {VideoType? type}) {
    List<VideoModel> allVideos = [];
    
    if (type == null || type == VideoType.real) {
      allVideos.addAll(_cachedVideos.where((v) => v.type == VideoType.real).toList());
    }
    if (type == null || type == VideoType.anime) {
      allVideos.addAll(_cachedVideos.where((v) => v.type == VideoType.anime).toList());
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

  Future<void> crawlAndSaveVideos(VideoType type) async {
    // Implementation of crawlAndSaveVideos method
  }
} 