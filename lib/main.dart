import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VideoTV',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final WebViewController _webViewController;
  final DatabaseReference _dbRef =
      FirebaseDatabase.instance.ref().child('videos');
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;
  String _statusMessage = '準備開始爬蟲';
  bool _isVideoLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _loadVideosFromFirebase();
  }

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            print("✅ 頁面載入完成: $url");
            if (url.contains('chinese-subtitle') && _isLoading) {
              _extractVideoData();
            }
          },
        ),
      );
  }

  Future<void> _loadVideosFromFirebase() async {
    final snapshot = await _dbRef.get();
    final data = snapshot.value;
    if (data is List) {
      setState(() {
        _items = data
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      });
    } else if (data is Map) {
      setState(() {
        _items = (data as Map)
            .values
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    }
  }

  Future<void> _startCrawling() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '正在載入網站...';
      _items.clear();
    });

    try {
      await _webViewController.loadRequest(
        Uri.parse('https://jable.tv/categories/chinese-subtitle/'),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '載入失敗: $e';
      });
    }
  }

  Future<void> _extractVideoData() async {
    setState(() {
      _statusMessage = '正在抓取影片資料...';
    });

    try {
      final result = await _webViewController.runJavaScriptReturningResult('''
        (function() {
          const items = Array.from(document.querySelectorAll('.video-img-box'));
          console.log('找到', items.length, '個影片');
          
          const videos = [];
          for (let i = 0; i < items.length; i++) {
            const item = items[i];
            const titleElement = item.querySelector('.detail .title a');
            const imgElement = item.querySelector('img');
            
            videos.push({
              id: i + 1,
              title: titleElement?.innerText?.trim() || '未知標題',
              detail_url: titleElement?.href || '',
              img_url: imgElement?.getAttribute('data-src') || imgElement?.getAttribute('src') || ''
            });
          }
          
          return JSON.stringify({ success: true, videos: videos });
        })();
      ''');

      String resultString = result.toString();
      dynamic data = jsonDecode(resultString);

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data['success'] == true) {
        List<dynamic> videos = data['videos'];
        setState(() {
          _items = videos.map((v) => Map<String, dynamic>.from(v)).toList();
          _isLoading = false;
          _statusMessage = '成功抓取 ${_items.length} 個影片';
        });
        await _dbRef.set(_items);
      } else {
        throw Exception('抓取失敗');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '抓取錯誤: $e';
      });
    }
  }

  Future<void> _playVideo(Map<String, dynamic> video) async {
    if (_isVideoLoading) return;
    setState(() {
      _isVideoLoading = true;
    });
    final detailUrl = video['detail_url'];
    if (detailUrl == null || detailUrl.isEmpty) {
      _showToast('沒有找到影片詳細頁面');
      setState(() {
        _isVideoLoading = false;
      });
      return;
    }
    try {
      // 載入影片詳細頁面
      await _webViewController.loadRequest(Uri.parse(detailUrl));
      // 等待頁面載入
      await Future.delayed(const Duration(seconds: 3));
      // 嘗試獲取播放地址
      final String? playUrl = await _extractPlayUrl();
      if (playUrl != null && playUrl.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              title: video['title'],
              url: playUrl,
            ),
          ),
        );
      } else {
        _showToast('無法找到播放地址');
      }
    } catch (e) {
      _showToast('載入失敗: $e');
    }
    setState(() {
      _isVideoLoading = false;
    });
  }

  Future<String?> _extractPlayUrl() async {
    try {
      final result = await _webViewController.runJavaScriptReturningResult('''
        (function() {
          console.log('開始搜尋播放地址...');
          
          // 方法1: 檢查全域變數 hlsUrl
          if (typeof window.hlsUrl !== 'undefined') {
            console.log('找到 hlsUrl:', window.hlsUrl);
            return JSON.stringify({ success: true, url: window.hlsUrl, source: 'hlsUrl' });
          }
          
          // 方法2: 搜尋 script 標籤中的 hlsUrl
          const scripts = Array.from(document.scripts);
          for (let script of scripts) {
            const content = script.innerText || script.innerHTML || '';
            const match = content.match(/var\\s+hlsUrl\\s*=\\s*['"]([^'"]+)['"]/);
            if (match && match[1]) {
              console.log('在 script 中找到 hlsUrl:', match[1]);
              return JSON.stringify({ success: true, url: match[1], source: 'script' });
            }
          }
          
          // 方法3: 搜尋頁面中的 .m3u8 URL
          const pageContent = document.documentElement.outerHTML;
          const m3u8Match = pageContent.match(/https?:\\/\\/[^\\s"'<>]+\\.m3u8[^\\s"'<>]*/);
          if (m3u8Match) {
            console.log('在頁面中找到 m3u8:', m3u8Match[0]);
            return JSON.stringify({ success: true, url: m3u8Match[0], source: 'page' });
          }
          
          console.log('沒有找到播放地址');
          return JSON.stringify({ success: false, error: '沒有找到播放地址' });
        })();
      ''');

      String resultString = result.toString();
      dynamic data = jsonDecode(resultString);

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data['success'] == true) {
        print("✅ 找到播放地址: ${data['url']} (來源: ${data['source']})");
        return data['url'];
      } else {
        print("❌ 未找到播放地址: ${data['error']}");
        return null;
      }
    } catch (e) {
      print("❌ 提取播放地址時發生錯誤: $e");
      return null;
    }
  }

  void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 影片網格列表
          Positioned.fill(
            child: _items.isEmpty
                ? const Center(child: Text('尚無影片資料'))
                : GridView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, // 每行4個
                      childAspectRatio: 0.7, // 可依需求調整
                    ),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Card(
                        margin: const EdgeInsets.all(8),
                        child: InkWell(
                          onTap: () {
                            print("點擊影片: \\${item['title']}");
                            _playVideo(item);
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: item['img_url'].isNotEmpty
                                    ? Image.network(
                                        item['img_url'],
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          return Container(
                                            color: Colors.grey.shade300,
                                            child:
                                                const Icon(Icons.video_library),
                                          );
                                        },
                                      )
                                    : Container(
                                        color: Colors.grey.shade300,
                                        child: const Icon(Icons.video_library),
                                      ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  item['title'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text(
                                  '影片 \\${item['id']}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // 隱藏的 WebView
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: 1,
              child: WebViewWidget(controller: _webViewController),
            ),
          ),
          if (_isVideoLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: !_isLoading
          ? FloatingActionButton.extended(
              onPressed: _startCrawling,
              label: const Text('開始爬蟲'),
              icon: const Icon(Icons.cloud_download),
            )
          : null,
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String title;
  final String url;

  const VideoPlayerScreen({
    super.key,
    required this.title,
    required this.url,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  String? _error;
  bool _isLoading = true;
  final FocusNode _focusNode = FocusNode();
  bool _showControls = false;
  Timer? _hideControlsTimer;
  Map<LogicalKeyboardKey, DateTime> _keyDownTime = {};

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      print("🎬 正在初始化播放器，URL: ${widget.url}");

      // 清理 URL
      String cleanUrl = widget.url.trim();
      if (cleanUrl.startsWith('"') && cleanUrl.endsWith('"')) {
        cleanUrl = cleanUrl.substring(1, cleanUrl.length - 1);
      }

      print("🎬 清理後的 URL: $cleanUrl");

      // 創建播放器控制器，支援 HLS
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(cleanUrl),
        httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15',
          'Referer': 'https://jable.tv/',
          'Accept': '*/*',
        },
      );

      _controller.addListener(() {
        if (_controller.value.hasError) {
          setState(() {
            _error = _controller.value.errorDescription;
            _isLoading = false;
          });
        }
      });

      await _controller.initialize();

      if (mounted) {
        setState(() {
          _initialized = true;
          _isLoading = false;
        });

        // 自動開始播放
        await _controller.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "無法播放此影片: $e";
          _isLoading = false;
        });
      }
    }
  }

  void _onUserInteraction() {
    setState(() {
      _showControls = true;
    });
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      setState(() {
        _showControls = false;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKey: (RawKeyEvent event) async {
        if (event is RawKeyDownEvent) {
          _onUserInteraction();
          // 返回鍵直接退出
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack ||
              event.logicalKey == LogicalKeyboardKey.backspace) {
            Navigator.pop(context);
            HapticFeedback.selectionClick();
            return;
          }
          // 上下鍵顯示/隱藏控制層
          if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.arrowDown) {
            setState(() {
              _showControls = !_showControls;
            });
            HapticFeedback.selectionClick();
            return;
          }
          // OK/Enter/空白鍵切換播放/暫停
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            if (_controller.value.isPlaying) {
              _controller.pause();
            } else {
              _controller.play();
            }
            HapticFeedback.selectionClick();
            return;
          }
          // 左右鍵記錄按下時間
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _keyDownTime[event.logicalKey] = DateTime.now();
          }
        } else if (event is RawKeyUpEvent) {
          // 左右鍵快轉/倒轉
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            final downTime = _keyDownTime[event.logicalKey];
            if (downTime != null) {
              final duration = DateTime.now().difference(downTime);
              if (duration.inMilliseconds > 500) {
                // 長按 30 秒
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  final newPosition =
                      _controller.value.position + Duration(seconds: 30);
                  _controller.seekTo(newPosition);
                } else {
                  final newPosition =
                      _controller.value.position - Duration(seconds: 30);
                  _controller.seekTo(newPosition > Duration.zero
                      ? newPosition
                      : Duration.zero);
                }
              } else {
                // 點按 10 秒
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  final newPosition =
                      _controller.value.position + Duration(seconds: 10);
                  _controller.seekTo(newPosition);
                } else {
                  final newPosition =
                      _controller.value.position - Duration(seconds: 10);
                  _controller.seekTo(newPosition > Duration.zero
                      ? newPosition
                      : Duration.zero);
                }
              }
              HapticFeedback.selectionClick();
              _keyDownTime.remove(event.logicalKey);
            }
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _error != null
            ? _buildErrorWidget()
            : _isLoading
                ? _buildLoadingWidget()
                : _initialized
                    ? _buildPlayerWidgetWithControls()
                    : _buildLoadingWidget(),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            const Text(
              '播放失敗',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '未知錯誤',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _isLoading = true;
                      _initialized = false;
                    });
                    _initializePlayer();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('重試'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            '正在載入影片...',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerWidgetWithControls() {
    return Stack(
      children: [
        // 全螢幕影片播放器
        Center(
          child: AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          ),
        ),
        // 控制層（自動隱藏/顯示）
        AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !_showControls,
            child: Stack(
              children: [
                // 控制層
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.title,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 播放/暫停按鈕
                Center(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_controller.value.isPlaying) {
                          _controller.pause();
                        } else {
                          _controller.play();
                        }
                        _onUserInteraction();
                      });
                      HapticFeedback.selectionClick();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
                // 進度條
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.red,
                        bufferedColor: Colors.white30,
                        backgroundColor: Colors.white10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
