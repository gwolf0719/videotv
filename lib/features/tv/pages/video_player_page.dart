import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../shared/models/video_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/video_repository.dart';

class VideoPlayerPage extends StatefulWidget {
  final VideoModel video;

  const VideoPlayerPage({
    super.key,
    required this.video,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  WebViewController? _webViewController;
  VideoPlayerController? _videoController;
  
  bool _isWebViewLoading = true;
  bool _isVideoLoading = false;
  String _statusMessage = '正在載入影片...';
  bool _isFullScreen = false;
  
  // 遙控器控制相關變數
  bool _isPaused = false;
  bool _showRecommendedMenu = false;
  Timer? _longPressTimer;
  bool _isLongPressing = false;
  int _seekSeconds = 10; // 預設快進/快退秒數
  String? _lastPressedKey;
  
  // Focus 相關
  final FocusNode _mainFocusNode = FocusNode();
  
  // 推薦影片相關
  List<VideoModel> _recommendedVideos = [];
  int _selectedRecommendedIndex = 0;
  final VideoRepository _videoRepository = VideoRepository(
    FirebaseDatabase.instance.ref(),
  );

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _loadRecommendedVideos();
    _initializeWakelock();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _longPressTimer?.cancel();
    _mainFocusNode.dispose();
    _disableWakelock();
    super.dispose();
  }

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            print("✅ 頁面載入完成: $url");
            setState(() {
              _isWebViewLoading = false;
            });
            _extractPlayUrl();
          },
          onWebResourceError: (error) {
            print("❌ WebView 錯誤: ${error.description}");
            setState(() {
              _statusMessage = '網頁載入失敗: ${error.description}';
              _isWebViewLoading = false;
            });
          },
        ),
      );

    // 檢查是否有詳細頁面 URL
    if (widget.video.videoUrl != null && widget.video.videoUrl!.isNotEmpty) {
      _webViewController!.loadRequest(Uri.parse(widget.video.videoUrl!));
    } else {
      setState(() {
        _statusMessage = '無效的影片連結';
        _isWebViewLoading = false;
      });
    }
  }

  Future<void> _loadRecommendedVideos() async {
    try {
      await _videoRepository.initialize();
      
      // 從快取獲取所有影片
      final realVideos = _videoRepository.getCachedRealVideos();
      final animeVideos = _videoRepository.getCachedAnimeVideos();
      final allVideos = [...realVideos, ...animeVideos];
      
      if (allVideos.isNotEmpty) {
        final videos = allVideos
            .where((v) => v.id != widget.video.id)
            .take(6)
            .toList();
        setState(() {
          _recommendedVideos = videos;
        });
      }
    } catch (e) {
      print('載入推薦影片失敗: $e');
    }
  }

  // 初始化螢幕常亮功能
  void _initializeWakelock() async {
    try {
      await WakelockPlus.enable();
      print('✅ 螢幕常亮已啟用');
    } catch (e) {
      print('❌ 啟用螢幕常亮失敗: $e');
    }
  }

  // 禁用螢幕常亮
  void _disableWakelock() async {
    try {
      await WakelockPlus.disable();
      print('✅ 螢幕常亮已禁用');
    } catch (e) {
      print('❌ 禁用螢幕常亮失敗: $e');
    }
  }

  // 管理螢幕常亮狀態
  void _manageWakelock(bool isPlaying) async {
    try {
      if (isPlaying) {
        await WakelockPlus.enable();
        print('🔆 播放中：螢幕常亮已啟用');
      } else {
        await WakelockPlus.disable();
        print('🌙 暫停中：螢幕常亮已禁用');
      }
    } catch (e) {
      print('❌ 管理螢幕常亮失敗: $e');
    }
  }

  Future<void> _extractPlayUrl() async {
    if (_webViewController == null) return;

    setState(() {
      _isVideoLoading = true;
      _statusMessage = '正在解析影片地址...';
    });

    try {
      // 等待頁面完全載入
      await Future.delayed(const Duration(seconds: 3));

      final result = await _webViewController!.runJavaScriptReturningResult('''
        (function() {
          console.log('開始搜尋播放地址...');
          
          // 方法1: 檢查全域變數 hlsUrl
          if (typeof window.hlsUrl !== 'undefined' && window.hlsUrl) {
            console.log('找到 hlsUrl:', window.hlsUrl);
            return JSON.stringify({ success: true, url: window.hlsUrl, source: 'hlsUrl' });
          }
          
          // 方法2: 檢查其他常見的全域變數
          const globalVars = [
            'videoUrl', 'playUrl', 'streamUrl', 'mp4Url', 'video_url', 'play_url',
            'sourceUrl', 'mediaUrl', 'videoSrc', 'src', 'videoSource'
          ];
          for (let varName of globalVars) {
            if (typeof window[varName] !== 'undefined' && window[varName]) {
              console.log('找到全域變數', varName + ':', window[varName]);
              return JSON.stringify({ success: true, url: window[varName], source: varName });
            }
          }
          
          // 方法3: 搜尋 video 標籤
          const videoElements = document.querySelectorAll('video');
          for (let video of videoElements) {
            if (video.src && video.src.trim() !== '') {
              console.log('找到 video 標籤 src:', video.src);
              return JSON.stringify({ success: true, url: video.src, source: 'video_tag' });
            }
            
            // 檢查 source 子元素
            const sources = video.querySelectorAll('source');
            for (let source of sources) {
              if (source.src && source.src.trim() !== '') {
                console.log('找到 source 標籤 src:', source.src);
                return JSON.stringify({ success: true, url: source.src, source: 'source_tag' });
              }
            }
          }
          
          // 方法4: 搜尋 script 中的 m3u8 或 mp4 連結
          const scripts = Array.from(document.scripts);
          for (let script of scripts) {
            const content = script.innerText || script.innerHTML || '';
            
            // 搜尋 m3u8 檔案
            const m3u8Match = content.match(/https?:\\/\\/[^\\s"']+\\.m3u8[^\\s"']*/);
            if (m3u8Match) {
              console.log('在 script 中找到 m3u8:', m3u8Match[0]);
              return JSON.stringify({ success: true, url: m3u8Match[0], source: 'script_m3u8' });
            }
            
            // 搜尋 mp4 檔案
            const mp4Match = content.match(/https?:\\/\\/[^\\s"']+\\.mp4[^\\s"']*/);
            if (mp4Match) {
              console.log('在 script 中找到 mp4:', mp4Match[0]);
              return JSON.stringify({ success: true, url: mp4Match[0], source: 'script_mp4' });
            }
          }
          
          console.log('未找到播放地址');
          return JSON.stringify({ success: false, error: '未找到播放地址' });
        })();
      ''');

      // 修復 JSON 解析問題
      String resultString = result.toString();
      
      // 移除多餘的引號
      if (resultString.startsWith('"') && resultString.endsWith('"')) {
        resultString = resultString.substring(1, resultString.length - 1);
        // 解碼轉義字符
        resultString = resultString.replaceAll('\\"', '"').replaceAll('\\\\', '\\');
      }

      print('🔍 JavaScript返回結果: $resultString');

      try {
        final data = jsonDecode(resultString);
        
        if (data['success'] == true) {
          final playUrl = data['url'];
          final source = data['source'];
          
          print('✅ 找到播放地址: $playUrl (來源: $source)');
          
          setState(() {
            _statusMessage = '準備播放影片...';
          });
          
          await _initializeVideoPlayer(playUrl);
        } else {
          setState(() {
            _statusMessage = '無法找到播放地址: ${data['error'] ?? '未知錯誤'}';
            _isVideoLoading = false;
          });
        }
      } catch (e) {
        print('❌ JSON解析失敗: $e');
        print('🐛 原始結果: $resultString');
        setState(() {
          _statusMessage = '解析影片地址失敗';
          _isVideoLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '提取播放地址時出錯: $e';
        _isVideoLoading = false;
      });
    }
  }

  Future<void> _initializeVideoPlayer(String url) async {
    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
      
      await _videoController!.initialize();
      
      // 添加播放狀態監聽器
      _videoController!.addListener(() {
        if (_videoController != null) {
          final isPlaying = _videoController!.value.isPlaying;
          final wasPaused = _isPaused;
          
          setState(() {
            _isPaused = !isPlaying;
          });
          
          // 當播放狀態改變時管理螢幕常亮
          if (wasPaused != !isPlaying) {
            _manageWakelock(isPlaying);
          }
        }
      });
      
      setState(() {
        _isVideoLoading = false;
        _statusMessage = '影片已準備就緒';
        _isPaused = false;
      });
      
      // 自動播放
      _videoController!.play();
      
      // 開始播放時啟用螢幕常亮
      _manageWakelock(true);
      
    } catch (e) {
      setState(() {
        _statusMessage = '播放器初始化失敗: $e';
        _isVideoLoading = false;
      });
    }
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
    
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      // 全螢幕模式確保螢幕常亮
      if (_videoController?.value.isPlaying == true) {
        _manageWakelock(true);
      }
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  // 播放/暫停控制
  void _togglePlayPause() {
    if (_videoController == null) return;
    
    final isCurrentlyPlaying = _videoController!.value.isPlaying;
    
    setState(() {
      _isPaused = isCurrentlyPlaying;
    });
    
    if (isCurrentlyPlaying) {
      _videoController!.pause();
      _manageWakelock(false); // 暫停時禁用螢幕常亮
    } else {
      _videoController!.play();
      _manageWakelock(true); // 播放時啟用螢幕常亮
      // 播放時隱藏推薦選單
      setState(() {
        _showRecommendedMenu = false;
      });
    }
  }

  // 影片進度控制
  void _seekVideo(int seconds) {
    if (_videoController == null || !_videoController!.value.isInitialized) return;
    
    final currentPosition = _videoController!.value.position;
    final newPosition = currentPosition + Duration(seconds: seconds);
    final maxDuration = _videoController!.value.duration;
    
    if (newPosition >= Duration.zero && newPosition <= maxDuration) {
      _videoController!.seekTo(newPosition);
    }
  }

  // 快進/快退（長按時使用）
  void _fastSeek(bool forward) {
    if (_videoController == null || !_videoController!.value.isInitialized) return;
    
    final totalDuration = _videoController!.value.duration.inSeconds;
    final seekAmount = (totalDuration / 10).round(); // 1/10 的影片長度
    
    _seekVideo(forward ? seekAmount : -seekAmount);
  }

  // 鍵盤事件處理
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    
    final key = event.logicalKey;
    
    // 播放/暫停控制
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
      _togglePlayPause();
      return true;
    }
    
    // ESC 鍵退出全螢幕
    if (key == LogicalKeyboardKey.escape) {
      if (_isFullScreen) {
        _toggleFullScreen();
      } else {
        Navigator.of(context).pop();
      }
      return true;
    }
    
    // 根據播放狀態處理左右鍵
    if (_isPaused) {
      // 暫停狀態：處理推薦影片選擇
      return _handlePausedState(key);
    } else {
      // 播放狀態：處理快進/快退
      return _handlePlayingState(key);
    }
  }

  bool _handlePausedState(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowDown) {
      // 下鍵：顯示/隱藏推薦影片選單
      setState(() {
        _showRecommendedMenu = !_showRecommendedMenu;
        _selectedRecommendedIndex = 0;
      });
      return true;
    }
    
    if (_showRecommendedMenu && _recommendedVideos.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        setState(() {
          _selectedRecommendedIndex = 
              (_selectedRecommendedIndex - 1 + _recommendedVideos.length) % _recommendedVideos.length;
        });
        return true;
      }
      
      if (key == LogicalKeyboardKey.arrowRight) {
        setState(() {
          _selectedRecommendedIndex = 
              (_selectedRecommendedIndex + 1) % _recommendedVideos.length;
        });
        return true;
      }
      
      if (key == LogicalKeyboardKey.enter) {
        // 播放選中的推薦影片
        final selectedVideo = _recommendedVideos[_selectedRecommendedIndex];
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPlayerPage(video: selectedVideo),
          ),
        );
        return true;
      }
    }
    
    return false;
  }

  bool _handlePlayingState(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowLeft) {
      _handleLeftArrowDown();
      return true;
    }
    
    if (key == LogicalKeyboardKey.arrowRight) {
      _handleRightArrowDown();
      return true;
    }
    
    if (key == LogicalKeyboardKey.arrowUp) {
      _handleArrowUp();
      return true;
    }
    
    return false;
  }

  void _handleLeftArrowDown() {
    _lastPressedKey = 'left';
    _startLongPressDetection();
  }

  void _handleRightArrowDown() {
    _lastPressedKey = 'right';
    _startLongPressDetection();
  }

  void _handleArrowUp() {
    _longPressTimer?.cancel();
    _isLongPressing = false;
    
    if (_lastPressedKey != null && !_isLongPressing) {
      // 短按：快進/快退10秒
      if (_lastPressedKey == 'left') {
        _seekVideo(-_seekSeconds);
      } else if (_lastPressedKey == 'right') {
        _seekVideo(_seekSeconds);
      }
    }
    
    _lastPressedKey = null;
  }

  void _startLongPressDetection() {
    _longPressTimer?.cancel();
    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      _isLongPressing = true;
      if (_lastPressedKey == 'left') {
        _fastSeek(false); // 快退1/10影片長度
      } else if (_lastPressedKey == 'right') {
        _fastSeek(true); // 快進1/10影片長度
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreen) {
      return _buildFullScreenPlayer();
    }

    return Focus(
      focusNode: _mainFocusNode,
      onKeyEvent: (node, event) {
        return _handleKeyEvent(event) ? KeyEventResult.handled : KeyEventResult.ignored;
      },
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(
            widget.video.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            // 影片播放區域
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: _buildVideoPlayer(),
              ),
            ),
            
            // 控制按鈕
            Container(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _togglePlayPause,
                    icon: Icon(
                      _videoController?.value.isPlaying == true
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                    label: Text(
                      _videoController?.value.isPlaying == true ? '暫停' : '播放',
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _toggleFullScreen,
                    icon: const Icon(Icons.fullscreen),
                    label: const Text('全螢幕'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _extractPlayUrl,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新載入'),
                  ),
                ],
              ),
            ),
            
            // 操作說明
            if (!_isFullScreen) _buildControlHints(),
            
            // 推薦影片選單
            if (_showRecommendedMenu && _recommendedVideos.isNotEmpty)
              _buildRecommendedMenu(),
            
            // 狀態訊息
            Padding(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              child: Text(
                _statusMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            // WebView (隱藏，僅用於解析)
            SizedBox(
              height: 0,
              child: Opacity(
                opacity: 0.0,
                child: _webViewController != null
                    ? WebViewWidget(controller: _webViewController!)
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_isWebViewLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              '正在載入網頁...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_isVideoLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              '正在解析影片...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_videoController != null && _videoController!.value.isInitialized) {
      return GestureDetector(
        onTap: () {
          if (_videoController!.value.isPlaying) {
            _videoController!.pause();
          } else {
            _videoController!.play();
          }
        },
        child: Stack(
          children: [
            VideoPlayer(_videoController!),
            if (!_videoController!.value.isPlaying)
              const Center(
                child: Icon(
                  Icons.play_circle_filled,
                  size: 64,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Text(
            _statusMessage,
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _extractPlayUrl,
            child: const Text('重試'),
          ),
        ],
      ),
    );
  }

  Widget _buildControlHints() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.defaultPadding,
        vertical: 8,
      ),
      child: Column(
        children: [
          Text(
            '遙控器操作說明：',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '播放時：← → 快進/快退 (長按：1/10影片長度)\n'
            '暫停時：↓ 推薦影片選單，← → 選擇影片\n'
            '📱 播放時自動保持螢幕常亮',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedMenu() {
    return Container(
      height: 150,
      margin: const EdgeInsets.all(AppConstants.defaultPadding),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '推薦影片',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _recommendedVideos.length,
              itemBuilder: (context, index) {
                final video = _recommendedVideos[index];
                final isSelected = index == _selectedRecommendedIndex;
                
                return Container(
                  width: 120,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: video.hasThumbnail
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  video.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.video_library,
                                      color: Colors.white54,
                                      size: 30,
                                    );
                                  },
                                ),
                              )
                            : const Icon(
                                Icons.video_library,
                                color: Colors.white54,
                                size: 30,
                              ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          video.displayTitle,
                          style: TextStyle(
                            color: isSelected ? Colors.blue : Colors.white70,
                            fontSize: 10,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullScreenPlayer() {
    return Focus(
      focusNode: _mainFocusNode,
      onKeyEvent: (node, event) {
        return _handleKeyEvent(event) ? KeyEventResult.handled : KeyEventResult.ignored;
      },
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleFullScreen,
          child: Stack(
            children: [
              if (_videoController != null && _videoController!.value.isInitialized)
                Center(child: VideoPlayer(_videoController!))
              else
                Center(
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              
              // 返回按鈕
              Positioned(
                top: 40,
                left: 20,
                child: GestureDetector(
                  onTap: _toggleFullScreen,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.fullscreen_exit,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              
              // 全螢幕操作說明
              Positioned(
                bottom: 40,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '播放時：← → 快進/快退 (長按：1/10影片長度)\n'
                    '暫停時：↓ 推薦影片選單，← → 選擇影片\n'
                    'ESC 或點擊退出全螢幕\n'
                    '📱 播放時自動保持螢幕常亮',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
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