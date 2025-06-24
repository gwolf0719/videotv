import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../shared/models/video_model.dart';

class LocalStorageService {
  static const String _dbName = 'videotv.db';
  static const int _dbVersion = 1;
  static const String _videoTable = 'videos';
  static const String _favoriteTable = 'favorites';
  
  Database? _database;
  
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    
    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createTables,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // 建立影片表
    await db.execute('''
      CREATE TABLE $_videoTable (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        thumbnail_url TEXT,
        type TEXT,
        added_at TEXT,
        metadata TEXT,
        created_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // 建立收藏表
    await db.execute('''
      CREATE TABLE $_favoriteTable (
        video_id TEXT PRIMARY KEY,
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        FOREIGN KEY (video_id) REFERENCES $_videoTable (id)
      )
    ''');

    print('✅ 本地資料庫表格建立完成');
  }

  // 儲存影片列表（不包含播放路徑）
  Future<void> cacheVideoList(List<VideoModel> videos) async {
    final db = await database;
    
    await db.transaction((txn) async {
      // 清空舊資料
      await txn.delete(_videoTable);
      
      // 插入新資料
      for (final video in videos) {
        await txn.insert(
          _videoTable,
          {
            'id': video.id,
            'title': video.title,
            'thumbnail_url': video.thumbnailUrl,
            'type': video.type?.name,
            'added_at': video.addedAt?.toIso8601String(),
            'metadata': video.metadata != null ? jsonEncode(video.metadata) : null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    
    print('✅ 成功暫存 ${videos.length} 個影片資料到本地');
  }

  // 從本地載入影片列表
  Future<List<VideoModel>> getCachedVideoList() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _videoTable,
        orderBy: 'created_at DESC',
      );

      final videos = maps.map((map) {
        Map<String, dynamic>? metadata;
        if (map['metadata'] != null) {
          try {
            metadata = jsonDecode(map['metadata']);
          } catch (e) {
            print('解析 metadata 失敗: $e');
          }
        }

        return VideoModel(
          id: map['id'],
          title: map['title'],
          thumbnailUrl: map['thumbnail_url'],
          // 注意：不載入 videoUrl，播放時才從雲端獲取
          type: VideoModel.parseVideoType(map['type']),
          addedAt: map['added_at'] != null ? DateTime.tryParse(map['added_at']) : null,
          metadata: metadata,
        );
      }).toList();

      print('✅ 從本地載入 ${videos.length} 個影片資料');
      return videos;
    } catch (e) {
      print('❌ 從本地載入影片失敗: $e');
      return [];
    }
  }

  // 儲存收藏列表
  Future<void> addToFavorites(String videoId) async {
    final db = await database;
    await db.insert(
      _favoriteTable,
      {'video_id': videoId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 移除收藏
  Future<void> removeFromFavorites(String videoId) async {
    final db = await database;
    await db.delete(
      _favoriteTable,
      where: 'video_id = ?',
      whereArgs: [videoId],
    );
  }

  // 獲取收藏的影片ID列表
  Future<List<String>> getFavoriteVideoIds() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(_favoriteTable);
    return maps.map((map) => map['video_id'] as String).toList();
  }

  // 檢查是否有本地快取
  Future<bool> hasCachedData() async {
    try {
      final db = await database;
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_videoTable')
      );
      return (count ?? 0) > 0;
    } catch (e) {
      print('檢查本地快取失敗: $e');
      return false;
    }
  }

  // 清空所有快取
  Future<void> clearCache() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(_videoTable);
      await txn.delete(_favoriteTable);
    });
    print('✅ 本地快取已清空');
  }

  // 獲取快取的影片數量
  Future<int> getCachedVideoCount() async {
    try {
      final db = await database;
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_videoTable')
      );
      return count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // 關閉資料庫
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// 儲存或更新影片資料（upsert）
  /// 會根據 id 做 replace，不會清空整個表格
  /// 用於增量更新影片資料
  Future<void> saveVideos(List<VideoModel> videos) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final video in videos) {
        await txn.insert(
          _videoTable,
          {
            'id': video.id,
            'title': video.title,
            'thumbnail_url': video.thumbnailUrl,
            'type': video.type?.name,
            'added_at': video.addedAt?.toIso8601String(),
            'metadata': video.metadata != null ? jsonEncode(video.metadata) : null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    print('✅ saveVideos: 已 upsert ${videos.length} 筆影片資料');
  }
} 