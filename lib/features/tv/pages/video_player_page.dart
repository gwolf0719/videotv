import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:video_player/video_player.dart';
import '../../../shared/models/video_model.dart';
import '../../../core/constants/app_constants.dart';

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
  String? _playUrl;
  String _statusMessage = '正在載入影片...';
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  @override
  void dispose() {
    _videoController?.dispose();
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
            _playUrl = playUrl;
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
      
      setState(() {
        _isVideoLoading = false;
        _statusMessage = '影片已準備就緒';
      });
      
      // 自動播放
      _videoController!.play();
      
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
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreen) {
      return _buildFullScreenPlayer();
    }

    return Scaffold(
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
                  onPressed: _videoController?.value.isPlaying == true
                      ? () => _videoController!.pause()
                      : () => _videoController!.play(),
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
          Expanded(
            child: Opacity(
              opacity: 0.0,
              child: _webViewController != null
                  ? WebViewWidget(controller: _webViewController!)
                  : const SizedBox.shrink(),
            ),
          ),
        ],
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

  Widget _buildFullScreenPlayer() {
    return Scaffold(
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
          ],
        ),
      ),
    );
  }
} 