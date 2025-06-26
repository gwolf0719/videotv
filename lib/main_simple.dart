import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'services/video_repository.dart';
import 'shared/models/video_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('⚠️ 運行在本地測試數據模式');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VideoTV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        cardColor: const Color(0xFF1A1A2E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFFFF6B9D),
          tertiary: Color(0xFF4ECDC4),
          surface: Color(0xFF1A1A2E),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white,
        ),
      ),
      home: const MyHomePage(title: 'VideoTV'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final VideoRepository _videoRepository = VideoRepository();
  List<VideoModel> _videos = [];
  bool _isLoading = false;
  String _statusMessage = '準備就緒';

  @override
  void initState() {
    super.initState();
    _initializeVideoRepository();
  }

  Future<void> _initializeVideoRepository() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '正在初始化...';
    });

    try {
      await _videoRepository.initialize();
      
      // 載入本地測試數據
      final videos = await _videoRepository.getAllVideos();
      
      setState(() {
        _videos = videos;
        _isLoading = false;
        _statusMessage = '載入完成 (${videos.length} 個影片)';
      });
      
      print('✅ VideoRepository 初始化成功，載入 ${videos.length} 個影片');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '初始化失敗: $e';
      });
      print('❌ VideoRepository 初始化失敗: $e');
    }
  }

  void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: Colors.black54,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 狀態欄
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                if (_isLoading) ...[
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '影片數量: ${_videos.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          
          // 影片列表
          Expanded(
            child: _videos.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.video_library_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isLoading ? '正在載入...' : '暫無影片',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (!_isLoading) ...[
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _initializeVideoRepository,
                            child: const Text('重新載入'),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _videos.length,
                    itemBuilder: (context, index) {
                      final video = _videos[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          leading: video.thumbnailUrl.isNotEmpty
                              ? Image.network(
                                  video.thumbnailUrl,
                                  width: 80,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 80,
                                      height: 60,
                                      color: Colors.grey[800],
                                      child: const Icon(Icons.broken_image),
                                    );
                                  },
                                )
                              : Container(
                                  width: 80,
                                  height: 60,
                                  color: Colors.grey[800],
                                  child: const Icon(Icons.video_file),
                                ),
                          title: Text(
                            video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (video.channel.isNotEmpty)
                                Text('頻道: ${video.channel}'),
                              if (video.date.isNotEmpty)
                                Text('日期: ${video.date}'),
                              Text(
                                video.isAnime ? '動畫' : '真人',
                                style: TextStyle(
                                  color: video.isAnime
                                      ? Colors.pink
                                      : Colors.blue,
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              video.isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: video.isFavorite ? Colors.red : null,
                            ),
                            onPressed: () {
                              _toggleFavorite(video);
                            },
                          ),
                          onTap: () {
                            _playVideo(video);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _initializeVideoRepository,
        tooltip: '重新載入',
        child: const Icon(Icons.refresh),
      ),
    );
  }

  void _toggleFavorite(VideoModel video) async {
    try {
      if (video.isFavorite) {
        await _videoRepository.removeFavorite(video.id);
        _showToast('已移除收藏');
      } else {
        await _videoRepository.addFavorite(video);
        _showToast('已加入收藏');
      }
      
      // 重新載入列表
      final videos = await _videoRepository.getAllVideos();
      setState(() {
        _videos = videos;
      });
    } catch (e) {
      _showToast('操作失敗: $e');
    }
  }

  void _playVideo(VideoModel video) {
    if (video.url.isEmpty) {
      _showToast('無法播放：影片URL為空');
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          videoModel: video,
          allVideos: _videos,
          currentIndex: _videos.indexOf(video),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _videoRepository.dispose();
    super.dispose();
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final VideoModel videoModel;
  final List<VideoModel> allVideos;
  final int currentIndex;

  const VideoPlayerScreen({
    super.key,
    required this.videoModel,
    required this.allVideos,
    required this.currentIndex,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isLoading = true;
      });

      if (widget.videoModel.url.isEmpty) {
        throw Exception('影片URL為空');
      }

      final uri = Uri.parse(widget.videoModel.url);
      _controller = VideoPlayerController.networkUrl(uri);
      await _controller.initialize();

      if (mounted) {
        setState(() {
          _initialized = true;
          _isLoading = false;
        });

        await _controller.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失敗: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.videoModel.title,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _isLoading
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在載入影片...'),
                ],
              )
            : _initialized
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      SizedBox(height: 16),
                      Text('影片載入失敗'),
                    ],
                  ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}