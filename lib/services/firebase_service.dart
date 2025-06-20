import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../shared/models/video_model.dart';
import '../core/constants/app_constants.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  DatabaseReference? _dbRef;
  DatabaseReference? _animeDbRef;
  DatabaseReference? _favoritesDbRef;
  bool _isAvailable = false;

  bool get isAvailable => _isAvailable;
  DatabaseReference? get dbRef => _dbRef;
  DatabaseReference? get animeDbRef => _animeDbRef;
  DatabaseReference? get favoritesDbRef => _favoritesDbRef;

  Future<bool> initialize() async {
    try {
      // 檢查 Firebase 是否可用
      if (Firebase.apps.isEmpty) {
        print('⚠️ Firebase 未初始化，數據庫服務不可用');
        _isAvailable = false;
        return false;
      }
      
      // 嘗試初始化數據庫引用
      _dbRef = FirebaseDatabase.instance.ref().child(AppConstants.videosNode);
      _animeDbRef = FirebaseDatabase.instance.ref().child(AppConstants.animeVideosNode);
      _favoritesDbRef = FirebaseDatabase.instance.ref().child(AppConstants.favoritesNode);
      
      // 測試連接
      await _dbRef!.limitToFirst(1).once();
      
      _isAvailable = true;
      print('✅ Firebase 數據庫引用初始化成功');
      return true;
    } catch (e) {
      print('⚠️ Firebase 數據庫不可用: $e');
      print('⚠️ 將運行在離線模式下');
      _isAvailable = false;
      _dbRef = null;
      _animeDbRef = null;
      _favoritesDbRef = null;
      return false;
    }
  }

  Future<List<VideoModel>> loadFavoriteVideos() async {
    if (!_isAvailable || _favoritesDbRef == null) {
      print('⚠️ Firebase不可用，無法載入收藏影片');
      return [];
    }
    
    try {
      final snapshot = await _favoritesDbRef!.get();
      return _parseVideosFromSnapshot(snapshot);
    } catch (e) {
      print('載入收藏影片失敗: $e');
      return [];
    }
  }

  Future<List<VideoModel>> loadAllVideos() async {
    if (!_isAvailable || _dbRef == null || _animeDbRef == null) {
      print('⚠️ Firebase不可用，無法載入影片列表');
      return [];
    }

    try {
      // 同時載入真人影片和動畫影片
      final results = await Future.wait([
        _dbRef!.get(),
        _animeDbRef!.get(),
      ]);

      final realSnapshot = results[0];
      final animeSnapshot = results[1];

      List<VideoModel> allVideos = [];
      
      // 處理真人影片
      allVideos.addAll(_parseVideosFromSnapshot(realSnapshot, isAnime: false));
      
      // 處理動畫影片
      allVideos.addAll(_parseVideosFromSnapshot(animeSnapshot, isAnime: true));

      return allVideos;
    } catch (e) {
      print('載入所有影片失敗: $e');
      return [];
    }
  }

  Future<List<VideoModel>> loadVideosByType(VideoType type) async {
    switch (type) {
      case VideoType.real:
        return _loadRealVideos();
      case VideoType.anime:
        return _loadAnimeVideos();
      default:
        return loadAllVideos();
    }
  }

  Future<List<VideoModel>> _loadRealVideos() async {
    if (!_isAvailable || _dbRef == null) return [];
    
    try {
      final snapshot = await _dbRef!.get();
      return _parseVideosFromSnapshot(snapshot, isAnime: false);
    } catch (e) {
      print('載入真人影片失敗: $e');
      return [];
    }
  }

  Future<List<VideoModel>> _loadAnimeVideos() async {
    if (!_isAvailable || _animeDbRef == null) return [];
    
    try {
      final snapshot = await _animeDbRef!.get();
      return _parseVideosFromSnapshot(snapshot, isAnime: true);
    } catch (e) {
      print('載入動畫影片失敗: $e');
      return [];
    }
  }

  List<VideoModel> _parseVideosFromSnapshot(DataSnapshot snapshot, {bool? isAnime}) {
    final data = snapshot.value;
    List<VideoModel> videos = [];

    if (data is List) {
      videos = data
          .whereType<Map>()
          .map((e) => VideoModel.fromMap(e.cast<String, dynamic>()))
          .toList();
    } else if (data is Map) {
      videos = data.values
          .whereType<Map>()
          .map((e) => VideoModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }

    // 如果指定了影片類型，則設置 isAnime 屬性
    if (isAnime != null) {
      videos = videos.map((video) => video.copyWith(type: isAnime ? VideoType.anime : VideoType.real)).toList();
    }

    return videos;
  }

  Future<Map<String, dynamic>?> checkForUpdate() async {
    if (!_isAvailable) return null;
    
    try {
      final ref = FirebaseDatabase.instance.ref();
      final snapshot = await ref.child(AppConstants.latestVersionNode).get();
      
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      print('檢查更新失敗: $e');
      return null;
    }
  }

  Future<bool> addToFavorites(VideoModel video) async {
    if (!_isAvailable || _favoritesDbRef == null) return false;
    
    try {
      await _favoritesDbRef!.push().set(video.toMap());
      return true;
    } catch (e) {
      print('添加到收藏失敗: $e');
      return false;
    }
  }

  Future<bool> removeFromFavorites(String videoId) async {
    if (!_isAvailable || _favoritesDbRef == null) return false;
    
    try {
      final snapshot = await _favoritesDbRef!.get();
      final data = snapshot.value;
      
      if (data is Map) {
        for (final entry in data.entries) {
          final videoData = entry.value as Map;
          if (videoData['id'] == videoId) {
            await _favoritesDbRef!.child(entry.key).remove();
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      print('從收藏移除失敗: $e');
      return false;
    }
  }
} 