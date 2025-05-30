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
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'crawlers/real_crawler.dart';
import 'crawlers/anime_crawler.dart';

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
  final DatabaseReference _animeDbRef =
      FirebaseDatabase.instance.ref().child('anime_videos');
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;
  String _statusMessage = '準備開始爬蟲';
  bool _isVideoLoading = false;
  double? _downloadProgress; // 下載進度百分比 (0~1)
  String? _downloadStatus; // 下載狀態訊息
  double? _apkDownloadProgress;
  String? _apkDownloadStatus;
  String? _apkFilePath;
  late RealCrawler _realCrawler;
  late AnimeCrawler _animeCrawler;

  // 新增：用於處理鍵盤輸入的 FocusNode
  final FocusNode _homeFocusNode = FocusNode();
  // 新增：控制右側選單顯示的 GlobalKey
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _showAppVersionToast();
    _checkForUpdate();
    _initializeWebView();
    _loadVideosFromFirebase();
  }

  Future<void> _showAppVersionToast() async {
    try {
      final info = await PackageInfo.fromPlatform();
      Fluttertoast.showToast(
        msg: '版本：${info.version}',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.black87,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    } catch (e) {}
  }

  Future<void> _checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final localVersion = info.version;
      final ref = FirebaseDatabase.instance.ref();
      final snapshot = await ref.child('latest_version_info').get();
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        final latestVersion = data['latest_version'] ?? '';
        final apkUrl = data['apk_url'] ?? '';
        if (latestVersion != '' &&
            latestVersion != localVersion &&
            apkUrl != '') {
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => StatefulBuilder(
              builder: (context, setStateDialog) {
                return AlertDialog(
                  title: const Text('有新版本可用'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          '目前版本：$localVersion\n最新版本：$latestVersion\n請下載最新版以獲得最佳體驗。'),
                      if (_apkDownloadProgress != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: Column(
                            children: [
                              LinearProgressIndicator(
                                  value: _apkDownloadProgress),
                              const SizedBox(height: 8),
                              Text(_apkDownloadStatus ?? '',
                                  style: const TextStyle(fontSize: 14)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  actions: [
                    if (_apkFilePath != null)
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          try {
                            // 檢查檔案是否存在
                            final apkFile =
                                File('/storage/emulated/0/Download/update.apk');
                            if (apkFile.existsSync()) {
                              print('[APK安裝] 開啟檔案: ${apkFile.path}');

                              // 使用 Android Intent 直接安裝
                              if (Platform.isAndroid) {
                                const platform = MethodChannel('install_apk');
                                try {
                                  await platform.invokeMethod('installApk', {
                                    'filePath': apkFile.path,
                                  });
                                } catch (e) {
                                  print('[APK安裝] Intent 方式失敗，嘗試 OpenFile: $e');
                                  // fallback 到原本方式
                                  final result =
                                      await OpenFile.open(apkFile.path);
                                  print(
                                      '[APK安裝] OpenFile 結果: ${result.message}');
                                  if (result.type != ResultType.done) {
                                    _showToast('開啟失敗: ${result.message}');
                                  }
                                }
                              } else {
                                final result =
                                    await OpenFile.open(apkFile.path);
                                print('[APK安裝] 開啟結果: ${result.message}');
                                if (result.type != ResultType.done) {
                                  _showToast('開啟失敗: ${result.message}');
                                }
                              }
                            } else {
                              print('[APK安裝] 檔案不存在: ${apkFile.path}');
                              _showToast('檔案不存在，請重新下載');
                            }
                          } catch (e) {
                            print('[APK安裝] 錯誤: $e');
                            _showToast('開啟失敗: $e');
                          }
                        },
                        child: const Text('安裝/開啟'),
                      ),
                    if (_apkDownloadProgress == null ||
                        _apkDownloadProgress! < 1)
                      TextButton(
                        onPressed: () async {
                          print('[APK下載] 開始下載...');

                          setStateDialog(() {
                            _apkDownloadProgress = 0;
                            _apkDownloadStatus = '開始下載...';
                          });

                          try {
                            // 直接使用系統 Download 資料夾路徑
                            final downloadPath = '/storage/emulated/0/Download';
                            final filePath = '$downloadPath/update.apk';
                            print('[APK下載] 準備下載到: $filePath');

                            final dio = Dio();
                            await dio.download(
                              apkUrl,
                              filePath,
                              onReceiveProgress: (received, total) {
                                if (total != -1) {
                                  final percent = (100 * received / total)
                                      .toStringAsFixed(0);
                                  print(
                                      '[APK下載] 進度: $received/$total ($percent%)');
                                  setStateDialog(() {
                                    _apkDownloadProgress = received / total;
                                    _apkDownloadStatus = '下載中 $percent%';
                                  });
                                }
                              },
                            );

                            // 檢查檔案是否真的存在
                            final file = File(filePath);
                            final exists = file.existsSync();
                            final size = exists ? file.lengthSync() : 0;
                            print(
                                '[APK下載] 下載完成 檔案存在: $exists 大小: ${size}bytes 路徑: $filePath');

                            setStateDialog(() {
                              _apkDownloadProgress = 1;
                              _apkDownloadStatus =
                                  exists ? '下載完成' : '下載失敗：檔案不存在';
                              _apkFilePath = exists ? filePath : null;
                            });
                          } catch (e) {
                            print('[APK下載] 下載失敗: $e');
                            setStateDialog(() {
                              _apkDownloadProgress = null;
                              _apkDownloadStatus = '下載失敗: $e';
                            });
                          }
                        },
                        child: const Text('下載新版'),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('稍後'),
                    ),
                  ],
                );
              },
            ),
          );
        }
      }
    } catch (e) {
      // 忽略錯誤，不影響主流程
    }
  }

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            print("✅ 頁面載入完成: $url");
            if (url.contains('chinese-subtitle') && _isLoading) {
              _realCrawler.extractVideoData();
            } else if (url.contains('hanime1.me') && _isLoading) {
              _animeCrawler.extractVideoData();
            }
          },
        ),
      );

    _realCrawler = RealCrawler(
      webViewController: _webViewController,
      dbRef: _dbRef,
      onLoadingChange: (isLoading) {
        setState(() {
          _isLoading = isLoading;
        });
      },
      onStatusChange: (status) {
        setState(() {
          _statusMessage = status;
        });
      },
      onDataUpdate: (items) {
        setState(() {
          _items = items;
        });
      },
    );

    _animeCrawler = AnimeCrawler(
      webViewController: _webViewController,
      dbRef: _animeDbRef,
      onLoadingChange: (isLoading) {
        setState(() {
          _isLoading = isLoading;
        });
      },
      onStatusChange: (status) {
        setState(() {
          _statusMessage = status;
        });
      },
      onDataUpdate: (items) {
        setState(() {
          _items = items;
        });
      },
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
    await _realCrawler.startCrawling();
  }

  Future<void> _startAnimeCrawling() async {
    await _animeCrawler.startCrawling();
  }

  Future<void> _playVideo(Map<String, dynamic> video) async {
    if (_isVideoLoading) return;
    setState(() {
      _isVideoLoading = true;
    });
    final detailUrl = video['detail_url'] as String?;
    if (detailUrl == null || detailUrl.isEmpty) {
      _showToast('沒有找到影片詳細頁面');
      setState(() {
        _isVideoLoading = false;
      });
      return;
    }
    try {
      await _webViewController.loadRequest(Uri.parse(detailUrl));
      await Future.delayed(const Duration(seconds: 3));
      String? playUrl;
      bool isAnime = detailUrl.contains('hanime1.me');

      if (isAnime) {
        playUrl = await _animeCrawler.extractPlayUrl();
      } else {
        playUrl = await _realCrawler.extractPlayUrl();
      }

      if (playUrl != null && playUrl.isNotEmpty) {
        final String finalPlayUrl = playUrl; // 確保 playUrl 不是 null

        // 根據影片類型選擇播放器
        if (isAnime) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AnimeVideoPlayerScreen(
                title: video['title'] as String,
                url: finalPlayUrl,
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoPlayerScreen(
                title: video['title'] as String,
                url: finalPlayUrl,
              ),
            ),
          );
        }
      } else {
        // 無法自動提取播放地址時，詢問是否要在外部瀏覽器開啟
        if (mounted) {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('無法自動播放'),
                content: const Text(
                    '無法自動提取播放地址。\n\n是否要在外部瀏覽器開啟頁面？\n您可以在瀏覽器中手動播放影片。'),
                actions: <Widget>[
                  TextButton(
                    child: const Text('取消'),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                  TextButton(
                    child: const Text('開啟瀏覽器'),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      final uri = Uri.parse(detailUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                        _showToast('已在外部瀏覽器開啟');
                      } else {
                        _showToast('無法開啟瀏覽器');
                      }
                    },
                  ),
                ],
              );
            },
          );
        }
      }
    } catch (e) {
      _showToast('載入失敗: $e');
    }
    setState(() {
      _isVideoLoading = false;
    });
  }

  Future<void> _downloadVideo(String url, String fileName) async {
    setState(() {
      _downloadProgress = 0;
      _downloadStatus = '開始下載...';
    });
    try {
      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/$fileName';
      final dio = Dio();
      await dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _downloadProgress = received / total;
              _downloadStatus =
                  '下載中... ${(100 * _downloadProgress!).toStringAsFixed(0)}%';
            });
          }
        },
      );
      setState(() {
        _downloadProgress = 1;
        _downloadStatus = '下載完成: $fileName';
        print('[APK下載] 檔案是否存在: ${File(savePath).existsSync()} 路徑: $savePath');
      });
      Fluttertoast.showToast(msg: '下載完成: $fileName');
    } catch (e) {
      setState(() {
        _downloadProgress = null;
        _downloadStatus = '下載失敗: $e';
      });
      Fluttertoast.showToast(msg: '下載失敗: $e');
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

  // 新增：顯示關於對話框
  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('關於 VideoTV'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('影片總數：${_items.length}'),
              const SizedBox(height: 8),
              const Text('使用說明：'),
              const Text('• 按返回鍵開啟選單'),
              const Text('• 點選影片可直接播放'),
              const Text('• 支援電視遙控器操作'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('關閉'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        print("🔙 WillPopScope: 捕獲到返回鍵事件");
        // 攔截返回鍵行為
        if (_scaffoldKey.currentState?.isEndDrawerOpen == true) {
          // 如果右側選單已經打開，關閉它
          print("🔙 WillPopScope: 關閉選單");
          Navigator.pop(context);
        } else {
          // 否則打開右側選單
          print("🔙 WillPopScope: 開啟選單");
          _scaffoldKey.currentState?.openEndDrawer();
        }
        return false; // 永遠阻止預設的返回行為
      },
      child: RawKeyboardListener(
        focusNode: _homeFocusNode,
        autofocus: true,
        onKey: (RawKeyEvent event) {
          if (event is RawKeyDownEvent) {
            print("🔙 RawKeyboardListener: 捕獲到按鍵事件: ${event.logicalKey}");
            // 移除返回鍵處理，避免與 WillPopScope 衝突
            // 其他鍵盤按鍵處理可以在這裡添加
          }
        },
        child: Scaffold(
          key: _scaffoldKey,
          body: Stack(
            children: [
              // 影片網格列表
              Positioned.fill(
                child: _items.isEmpty
                    ? const Center(child: Text('尚無影片資料'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
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
                                                child: const Icon(
                                                    Icons.video_library),
                                              );
                                            },
                                          )
                                        : Container(
                                            color: Colors.grey.shade300,
                                            child:
                                                const Icon(Icons.video_library),
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0),
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
              if (_downloadProgress != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 20,
                  child: Column(
                    children: [
                      LinearProgressIndicator(value: _downloadProgress),
                      if (_downloadStatus != null)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(_downloadStatus!,
                              style: const TextStyle(color: Colors.white)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          // 右側抽屜選單
          endDrawer: Drawer(
            child: Container(
              color: Colors.grey[100],
              child: Column(
                children: [
                  // 選單標題
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 30, horizontal: 20),
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.cloud_download,
                            color: Colors.white,
                            size: 30,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '影片爬蟲',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_isLoading)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _statusMessage,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // 選單選項
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        if (!_isLoading) ...[
                          ListTile(
                            leading: const Icon(Icons.person, size: 30),
                            title: const Text('爬取真人影片'),
                            subtitle: const Text('從 jable.tv 爬取中文字幕影片'),
                            onTap: () {
                              Navigator.pop(context);
                              _startCrawling();
                            },
                          ),
                          const Divider(),
                          ListTile(
                            leading: const Icon(Icons.animation, size: 30),
                            title: const Text('爬取動畫影片'),
                            subtitle: const Text('從 hanime1.me 爬取動畫影片'),
                            onTap: () {
                              Navigator.pop(context);
                              _startAnimeCrawling();
                            },
                          ),
                          const Divider(),
                        ] else ...[
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: Column(
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 16),
                                  Text('正在執行爬蟲作業...'),
                                ],
                              ),
                            ),
                          ),
                        ],
                        ListTile(
                          leading: const Icon(Icons.info_outline, size: 30),
                          title: const Text('關於'),
                          subtitle: Text('目前共有 ${_items.length} 個影片'),
                          onTap: () {
                            Navigator.pop(context);
                            _showAboutDialog();
                          },
                        ),
                      ],
                    ),
                  ),
                  // 底部說明
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: const Text(
                      '提示：再次按返回鍵可關閉此選單',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _homeFocusNode.dispose();
    super.dispose();
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
  Timer? _keepAwakeTimer; // 防止待機的計時器
  Map<LogicalKeyboardKey, DateTime> _keyDownTime = {};
  double _playbackSpeed = 1.0;
  bool _isFullScreen = false;
  OverlayEntry? _fastSeekOverlay;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _startKeepAwakeTimer(); // 啟動防待機功能
  }

  // 防止電視進入待機狀態
  void _startKeepAwakeTimer() {
    _keepAwakeTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      // 每30秒觸發一次用戶交互，防止待機
      if (mounted && _controller.value.isPlaying) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
        print("🎬 防待機: 保持螢幕喚醒");
      }
    });
  }

  Future<void> _initializePlayer() async {
    try {
      print("🎬 正在初始化播放器，URL: \\${widget.url}");
      String cleanUrl = widget.url.trim();
      if (cleanUrl.startsWith('"') && cleanUrl.endsWith('"')) {
        cleanUrl = cleanUrl.substring(1, cleanUrl.length - 1);
      }
      print("🎬 清理後的 URL: \\${cleanUrl}");
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
        await _controller.setPlaybackSpeed(_playbackSpeed);
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

  void _onDoubleTap(bool isRight) {
    final current = _controller.value.position;
    final seek = isRight
        ? current + const Duration(seconds: 10)
        : current - const Duration(seconds: 10);
    _controller.seekTo(seek > Duration.zero ? seek : Duration.zero);
    _showFastSeekOverlay(isRight);
    HapticFeedback.mediumImpact();
    _onUserInteraction();
  }

  void _showFastSeekOverlay(bool isRight) {
    _fastSeekOverlay?.remove();
    _fastSeekOverlay = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!isRight)
                  Icon(Icons.fast_rewind, color: Colors.white, size: 80),
                const SizedBox(width: 40),
                if (isRight)
                  Icon(Icons.fast_forward, color: Colors.white, size: 80),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_fastSeekOverlay!);
    Future.delayed(const Duration(milliseconds: 500), () {
      _fastSeekOverlay?.remove();
      _fastSeekOverlay = null;
    });
  }

  void _onChangeSpeed() async {
    final speeds = [0.5, 1.0, 1.5, 2.0];
    final result = await showModalBottomSheet<double>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: speeds
            .map((s) => ListTile(
                  title: Text('${s}x',
                      style: TextStyle(
                          fontWeight: s == _playbackSpeed
                              ? FontWeight.bold
                              : FontWeight.normal)),
                  onTap: () => Navigator.pop(context, s),
                ))
            .toList(),
      ),
    );
    if (result != null) {
      setState(() {
        _playbackSpeed = result;
      });
      await _controller.setPlaybackSpeed(_playbackSpeed);
      _onUserInteraction();
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
        DeviceOrientation.portraitDown,
      ]);
    }
    _onUserInteraction();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _hideControlsTimer?.cancel();
    _keepAwakeTimer?.cancel(); // 取消防待機計時器
    _fastSeekOverlay?.remove();
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onUserInteraction,
      onDoubleTapDown: (details) {
        final width = MediaQuery.of(context).size.width;
        if (details.localPosition.dx < width / 2) {
          _onDoubleTap(false); // 左半邊倒退
        } else {
          _onDoubleTap(true); // 右半邊快轉
        }
      },
      child: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Stack(
                children: [
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
                            IconButton(
                              onPressed: _onChangeSpeed,
                              icon: Icon(Icons.speed,
                                  color: Colors.white, size: 26),
                              tooltip: '播放速度',
                            ),
                            IconButton(
                              onPressed: _toggleFullScreen,
                              icon: Icon(
                                  _isFullScreen
                                      ? Icons.fullscreen_exit
                                      : Icons.fullscreen,
                                  color: Colors.white,
                                  size: 26),
                              tooltip: _isFullScreen ? '退出全螢幕' : '全螢幕',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: Colors.red,
                              bufferedColor: Colors.white30,
                              backgroundColor: Colors.white10,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(_controller.value.position),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                              Text(_formatDuration(_controller.value.duration),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return '${d.inHours > 0 ? '${twoDigits(d.inHours)}:' : ''}$twoDigitMinutes:$twoDigitSeconds';
  }
}

// 動畫專用播放器
class AnimeVideoPlayerScreen extends StatefulWidget {
  final String title;
  final String url;

  const AnimeVideoPlayerScreen({
    super.key,
    required this.title,
    required this.url,
  });

  @override
  State<AnimeVideoPlayerScreen> createState() => _AnimeVideoPlayerScreenState();
}

class _AnimeVideoPlayerScreenState extends State<AnimeVideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  String? _error;
  bool _isLoading = true;
  final FocusNode _focusNode = FocusNode();
  bool _showControls = false;
  Timer? _hideControlsTimer;
  Timer? _keepAwakeTimer; // 防止待機的計時器
  Map<LogicalKeyboardKey, DateTime> _keyDownTime = {};
  double _playbackSpeed = 1.0;
  bool _isFullScreen = false;
  OverlayEntry? _fastSeekOverlay;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _startKeepAwakeTimer(); // 啟動防待機功能
  }

  // 防止電視進入待機狀態
  void _startKeepAwakeTimer() {
    _keepAwakeTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      // 每30秒觸發一次用戶交互，防止待機
      if (mounted && _controller.value.isPlaying) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
        print("🎬 防待機: 保持螢幕喚醒");
      }
    });
  }

  Future<void> _initializePlayer() async {
    try {
      print("🎬 動畫播放器初始化，URL: \\${widget.url}");
      String cleanUrl = widget.url.trim();
      if (cleanUrl.startsWith('"') && cleanUrl.endsWith('"')) {
        cleanUrl = cleanUrl.substring(1, cleanUrl.length - 1);
      }
      print("🎬 清理後的 URL: \\${cleanUrl}");

      // 動畫影片使用不同的 headers
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(cleanUrl),
        httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          'Referer': 'https://hanime1.me/',
          'Accept': '*/*',
          'Accept-Language': 'zh-TW,zh;q=0.9,en;q=0.8',
          'Accept-Encoding': 'gzip, deflate, br',
          'Connection': 'keep-alive',
          'Sec-Fetch-Dest': 'video',
          'Sec-Fetch-Mode': 'no-cors',
          'Sec-Fetch-Site': 'cross-site',
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
        await _controller.setPlaybackSpeed(_playbackSpeed);
        await _controller.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "無法播放此動畫影片: $e";
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
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _onDoubleTap(bool isRight) {
    final current = _controller.value.position;
    final seek = isRight
        ? current + const Duration(seconds: 10)
        : current - const Duration(seconds: 10);
    _controller.seekTo(seek > Duration.zero ? seek : Duration.zero);
    _showFastSeekOverlay(isRight);
    HapticFeedback.mediumImpact();
    _onUserInteraction();
  }

  void _showFastSeekOverlay(bool isRight) {
    _fastSeekOverlay?.remove();
    _fastSeekOverlay = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!isRight)
                  Icon(Icons.fast_rewind, color: Colors.white, size: 80),
                const SizedBox(width: 40),
                if (isRight)
                  Icon(Icons.fast_forward, color: Colors.white, size: 80),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_fastSeekOverlay!);
    Future.delayed(const Duration(milliseconds: 500), () {
      _fastSeekOverlay?.remove();
      _fastSeekOverlay = null;
    });
  }

  void _onChangeSpeed() async {
    final speeds = [0.5, 1.0, 1.5, 2.0];
    final result = await showModalBottomSheet<double>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: speeds
            .map((s) => ListTile(
                  title: Text('${s}x',
                      style: TextStyle(
                          fontWeight: s == _playbackSpeed
                              ? FontWeight.bold
                              : FontWeight.normal)),
                  onTap: () => Navigator.pop(context, s),
                ))
            .toList(),
      ),
    );
    if (result != null) {
      setState(() {
        _playbackSpeed = result;
      });
      await _controller.setPlaybackSpeed(_playbackSpeed);
      _onUserInteraction();
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
        DeviceOrientation.portraitDown,
      ]);
    }
    _onUserInteraction();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _hideControlsTimer?.cancel();
    _keepAwakeTimer?.cancel(); // 取消防待機計時器
    _fastSeekOverlay?.remove();
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
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
              '動畫播放失敗',
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
            const SizedBox(height: 8),
            const Text(
              '可能原因：\n• 影片源無效\n• 網路連線問題\n• 格式不支援',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 12),
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
            '正在載入動畫影片...',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            '動畫影片可能需要較長時間載入',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerWidgetWithControls() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onUserInteraction,
      onDoubleTapDown: (details) {
        final width = MediaQuery.of(context).size.width;
        if (details.localPosition.dx < width / 2) {
          _onDoubleTap(false); // 左半邊倒退
        } else {
          _onDoubleTap(true); // 右半邊快轉
        }
      },
      child: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Stack(
                children: [
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
                            const Icon(Icons.animation,
                                color: Colors.white, size: 20),
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
                            IconButton(
                              onPressed: _onChangeSpeed,
                              icon: Icon(Icons.speed,
                                  color: Colors.white, size: 26),
                              tooltip: '播放速度',
                            ),
                            IconButton(
                              onPressed: _toggleFullScreen,
                              icon: Icon(
                                  _isFullScreen
                                      ? Icons.fullscreen_exit
                                      : Icons.fullscreen,
                                  color: Colors.white,
                                  size: 26),
                              tooltip: _isFullScreen ? '退出全螢幕' : '全螢幕',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: Colors.pink,
                              bufferedColor: Colors.white30,
                              backgroundColor: Colors.white10,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(_controller.value.position),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                              Text(_formatDuration(_controller.value.duration),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 防待機指示器
                  if (_controller.value.isPlaying)
                    Positioned(
                      top: 100,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.visibility,
                                color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('防待機',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return '${d.inHours > 0 ? '${twoDigits(d.inHours)}:' : ''}$twoDigitMinutes:$twoDigitSeconds';
  }
}
