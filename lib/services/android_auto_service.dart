import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

/// Android Auto 媒體服務處理器
class AndroidAutoMediaHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final BehaviorSubject<List<MediaItem>> _queueSubject =
      BehaviorSubject.seeded(<MediaItem>[]);

  /// 影片列表數據流
  @override
  BehaviorSubject<List<MediaItem>> get queue => _queueSubject;

  AndroidAutoMediaHandler() {
    _init();
  }

  Future<void> _init() async {
    // 監聽播放狀態變化
    _audioPlayer.playbackEventStream.listen(_broadcastState);

    // 監聽播放位置變化
    _audioPlayer.positionStream.listen((position) {
      playbackState.add(playbackState.value.copyWith(
        updatePosition: position,
      ));
    });

    // 設置初始狀態
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  /// 廣播播放狀態
  void _broadcastState(PlaybackEvent event) {
    final playing = _audioPlayer.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_audioPlayer.processingState]!,
      playing: playing,
      updatePosition: _audioPlayer.position,
      bufferedPosition: _audioPlayer.bufferedPosition,
      speed: _audioPlayer.speed,
      queueIndex: event.currentIndex,
    ));
  }

  /// 設置影片隊列
  @override
  Future<void> updateQueue(List<MediaItem> mediaItems) async {
    _queueSubject.add(mediaItems);
  }

  /// 從影片數據更新隊列
  Future<void> updateQueueFromVideos(List<Map<String, dynamic>> videos) async {
    final mediaItems = videos.map((video) {
      return MediaItem(
        id: video['id'] ?? 'unknown_${videos.indexOf(video)}',
        album: video['type'] == 'anime' ? '動畫影片' : '真人影片',
        title: video['title'] ?? '未知標題',
        artist: 'VideoTV',
        artUri: Uri.tryParse(video['img_url'] ?? ''),
        extras: {
          'detail_url': video['detail_url'],
          'type': video['type'],
          'source_url': video['source_url'],
        },
      );
    }).toList();

    await updateQueue(mediaItems);
  }

  @override
  Future<void> play() async {
    try {
      await _audioPlayer.play();
    } catch (e) {
      print('播放錯誤: $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
    } catch (e) {
      print('暫停錯誤: $e');
    }
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      print('跳轉錯誤: $e');
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    try {
      if (index < 0 || index >= queue.value.length) return;

      final mediaItem = queue.value[index];

      // 這裡需要實際的播放URL，可能需要先從詳情頁面抓取
      final playUrl = mediaItem.extras?['source_url'] as String?;
      if (playUrl?.isNotEmpty == true) {
        await _audioPlayer.setUrl(playUrl!);
        await play();
      } else {
        // 如果沒有直接播放URL，需要從詳情頁面獲取
        print('需要從詳情頁面獲取播放URL: ${mediaItem.extras?['detail_url']}');
        // 這裡可以調用爬蟲服務獲取實際播放URL
      }
    } catch (e) {
      print('跳轉到項目錯誤: $e');
    }
  }

  @override
  Future<void> skipToNext() async {
    final currentIndex = playbackState.value.queueIndex ?? 0;
    await skipToQueueItem(currentIndex + 1);
  }

  @override
  Future<void> skipToPrevious() async {
    final currentIndex = playbackState.value.queueIndex ?? 0;
    await skipToQueueItem(currentIndex - 1);
  }

  @override
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      await super.stop();
    } catch (e) {
      print('停止錯誤: $e');
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  /// 搜索影片
  @override
  Future<List<MediaItem>> search(String query,
      [Map<String, dynamic>? extras]) async {
    final allItems = queue.value;
    if (query.isEmpty) return allItems;

    return allItems.where((item) {
      return item.title.toLowerCase().contains(query.toLowerCase()) ||
          (item.album?.toLowerCase().contains(query.toLowerCase()) ?? false);
    }).toList();
  }

  /// 獲取子項目（分類瀏覽）
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    switch (parentMediaId) {
      case AndroidAutoMediaLibrary.recentMediaId:
        // 返回最近播放的影片
        return queue.value.take(20).toList();

      case AndroidAutoMediaLibrary.animeMediaId:
        // 返回動畫影片
        return queue.value.where((item) => item.album == '動畫影片').toList();

      case AndroidAutoMediaLibrary.realMediaId:
        // 返回真人影片
        return queue.value.where((item) => item.album == '真人影片').toList();

      default:
        return queue.value;
    }
  }

  /// 清理資源
  Future<void> dispose() async {
    await _audioPlayer.dispose();
    await _queueSubject.close();
  }
}

/// Android Auto 媒體庫結構
class AndroidAutoMediaLibrary {
  static const String rootMediaId = 'root';
  static const String recentMediaId = 'recent';
  static const String animeMediaId = 'anime';
  static const String realMediaId = 'real';

  /// 獲取根目錄項目
  static List<MediaItem> getRootMediaItems() {
    return [
      const MediaItem(
        id: recentMediaId,
        title: '最近播放',
        album: 'VideoTV',
        playable: false,
      ),
      const MediaItem(
        id: animeMediaId,
        title: '動畫影片',
        album: 'VideoTV',
        playable: false,
      ),
      const MediaItem(
        id: realMediaId,
        title: '真人影片',
        album: 'VideoTV',
        playable: false,
      ),
    ];
  }
}
