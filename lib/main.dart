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
  final DatabaseReference _favoritesDbRef =
      FirebaseDatabase.instance.ref().child('favorites');
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _favoriteItems = [];
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

  // 新增：全螢幕 loading 過場動畫
  bool _isShowingLoadingTransition = false;
  String _loadingMessage = '正在處理中...';

  // 新增：選單 FocusNode 陣列
  late final List<FocusNode> _menuFocusNodes;

  // 新增：顯示模式（全部、收藏）
  bool _showFavoritesOnly = true; // 預設顯示收藏

  @override
  void initState() {
    super.initState();
    _showAppVersionToast();
    _initializeWebView();
    _loadFavoriteVideos(); // 先載入收藏影片
    // 初始化選單 FocusNode
    _menuFocusNodes = List.generate(5, (_) => FocusNode()); // 調整為5個選單項目
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
                            if (_apkFilePath == null) {
                              _showToast('找不到更新檔案');
                              return;
                            }

                            // 檢查檔案是否存在
                            final apkFile = File(_apkFilePath!);
                            if (!await apkFile.exists()) {
                              print('[APK安裝] 檔案不存在: ${apkFile.path}');
                              _showToast('檔案不存在，請重新下載');
                              return;
                            }

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
                                print('[APK安裝] OpenFile 結果: ${result.message}');
                                if (result.type != ResultType.done) {
                                  _showToast('開啟失敗: ${result.message}');
                                }
                              }
                            } else {
                              final result = await OpenFile.open(apkFile.path);
                              print('[APK安裝] 開啟結果: ${result.message}');
                              if (result.type != ResultType.done) {
                                _showToast('開啟失敗: ${result.message}');
                              }
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
                            // 使用 getExternalStorageDirectory 來獲取下載目錄
                            final dir = await getExternalStorageDirectory();
                            if (dir == null) {
                              throw Exception('無法獲取儲存空間');
                            }

                            // 確保目錄存在
                            if (!await dir.exists()) {
                              await dir.create(recursive: true);
                            }

                            final filePath = '${dir.path}/update.apk';
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
                            final exists = await file.exists();
                            final size = exists ? await file.length() : 0;
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

  Future<void> _loadFavoriteVideos() async {
    // 顯示全螢幕 loading 動畫
    setState(() {
      _isShowingLoadingTransition = true;
      _loadingMessage = '正在載入收藏影片列表...';
    });

    final snapshot = await _favoritesDbRef.get();
    final data = snapshot.value;
    if (data is List) {
      setState(() {
        _favoriteItems = data
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      });
    } else if (data is Map) {
      setState(() {
        _favoriteItems = (data)
            .values
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    }

    // 設置當前顯示的項目
    setState(() {
      _items = _favoriteItems;
      _isShowingLoadingTransition = false;
    });
  }

  Future<void> _loadAllVideos() async {
    setState(() {
      _isShowingLoadingTransition = true;
      _loadingMessage = '正在載入影片列表...';
    });

    // 同時載入真人影片和動畫影片
    final realSnapshot = await _dbRef.get();
    final animeSnapshot = await _animeDbRef.get();

    List<Map<String, dynamic>> allVideos = [];

    // 處理真人影片
    if (realSnapshot.exists) {
      final data = realSnapshot.value;
      if (data is List) {
        allVideos.addAll(data
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList());
      } else if (data is Map) {
        allVideos.addAll((data)
            .values
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList());
      }
    }

    // 處理動畫影片
    if (animeSnapshot.exists) {
      final data = animeSnapshot.value;
      if (data is List) {
        allVideos.addAll(data
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList());
      } else if (data is Map) {
        allVideos.addAll((data)
            .values
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList());
      }
    }

    setState(() {
      _items = allVideos;
      _isShowingLoadingTransition = false;
    });
  }

  Future<void> _loadRealVideos() async {
    setState(() {
      _isShowingLoadingTransition = true;
      _loadingMessage = '正在載入真人影片列表...';
    });

    final realSnapshot = await _dbRef.get();
    List<Map<String, dynamic>> realVideos = [];

    // 只處理真人影片
    if (realSnapshot.exists) {
      final data = realSnapshot.value;
      if (data is List) {
        realVideos.addAll(data
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList());
      } else if (data is Map) {
        realVideos.addAll((data)
            .values
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList());
      }
    }

    setState(() {
      _items = realVideos;
      _isShowingLoadingTransition = false;
    });
  }

  Future<void> _loadAnimeVideos() async {
    setState(() {
      _isShowingLoadingTransition = true;
      _loadingMessage = '正在載入動畫影片列表...';
    });

    final animeSnapshot = await _animeDbRef.get();
    List<Map<String, dynamic>> animeVideos = [];

    // 只處理動畫影片
    if (animeSnapshot.exists) {
      final data = animeSnapshot.value;
      if (data is List) {
        animeVideos.addAll(data
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList());
      } else if (data is Map) {
        animeVideos.addAll((data)
            .values
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList());
      }
    }

    setState(() {
      _items = animeVideos;
      _isShowingLoadingTransition = false;
    });
  }

  Future<void> _toggleFavorite(Map<String, dynamic> video) async {
    final videoId = video['id']?.toString() ?? video['title'];
    final isCurrentlyFavorite = _isVideoFavorite(video);

    try {
      if (isCurrentlyFavorite) {
        // 移除收藏
        await _favoritesDbRef.child(videoId).remove();
        setState(() {
          _favoriteItems.removeWhere(
              (item) => (item['id']?.toString() ?? item['title']) == videoId);
          if (_showFavoritesOnly) {
            _items = _favoriteItems;
          }
        });
        _showToast('已取消收藏');
      } else {
        // 添加收藏
        await _favoritesDbRef.child(videoId).set(video);
        setState(() {
          _favoriteItems.add(video);
          if (_showFavoritesOnly) {
            _items = _favoriteItems;
          }
        });
        _showToast('已添加到收藏');
      }
    } catch (e) {
      _showToast('操作失敗: $e');
    }
  }

  bool _isVideoFavorite(Map<String, dynamic> video) {
    final videoId = video['id']?.toString() ?? video['title'];
    return _favoriteItems
        .any((item) => (item['id']?.toString() ?? item['title']) == videoId);
  }

  void _toggleDisplayMode() {
    setState(() {
      _showFavoritesOnly = !_showFavoritesOnly;
      if (_showFavoritesOnly) {
        _items = _favoriteItems;
        _showToast('顯示收藏影片');
      } else {
        _loadAllVideos();
        _showToast('顯示全部影片');
      }
    });
  }

  // 新增：顯示 Toast 消息
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

  Future<void> _startCrawling() async {
    // 顯示全螢幕 loading 動畫
    setState(() {
      _isShowingLoadingTransition = true;
      _loadingMessage = '正在爬取真人影片...';
    });

    await _realCrawler.startCrawling();

    // 爬蟲完成後切換到顯示全部影片模式，並隱藏 loading 動畫
    setState(() {
      _isShowingLoadingTransition = false;
      _showFavoritesOnly = false; // 切換到顯示全部影片模式
    });

    // 載入真人影片（只顯示真人影片）
    await _loadRealVideos();

    // 重新觸發 setState 來更新圖片比例
    setState(() {});

    _showToast('真人影片爬取完成');
  }

  Future<void> _startAnimeCrawling() async {
    // 顯示全螢幕 loading 動畫
    setState(() {
      _isShowingLoadingTransition = true;
      _loadingMessage = '正在爬取動畫影片...';
    });

    await _animeCrawler.startCrawling();

    // 爬蟲完成後切換到顯示全部影片模式，並隱藏 loading 動畫
    setState(() {
      _isShowingLoadingTransition = false;
      _showFavoritesOnly = false; // 切換到顯示全部影片模式
    });

    // 載入動畫影片（只顯示動畫影片）
    await _loadAnimeVideos();

    // 重新觸發 setState 來更新圖片比例
    setState(() {});

    _showToast('動畫影片爬取完成');
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
              builder: (_) => VideoPlayerScreen(
                title: video['title'] as String,
                url: finalPlayUrl,
                isAnime: true,
                onPlayStarted: _startBackgroundCrawling, // 新增：播放開始時的回調
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
                onPlayStarted: _startBackgroundCrawling, // 新增：播放開始時的回調
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

  // 新增：背景爬取功能
  void _startBackgroundCrawling() {
    // 延遲 10 秒後開始背景爬取，讓用戶先專注於播放
    Timer(const Duration(seconds: 10), () {
      _backgroundCrawlNextPage();
    });
  }

  // 新增：背景爬取下一頁
  Future<void> _backgroundCrawlNextPage() async {
    try {
      print('🎬 開始背景爬取下一頁影片...');

      // 爬取真人影片下一頁
      await _realCrawler.crawlNextPageInBackground();

      // 等待 5 秒再爬取動畫影片（避免過於頻繁）
      await Future.delayed(const Duration(seconds: 5));
      await _animeCrawler.crawlNextPageInBackground();

      print('🎬 背景爬取完成');

      // 每隔 30 秒繼續爬取下一頁（最多爬取 5 頁）
      Timer(const Duration(seconds: 30), () {
        if (_realCrawler.currentPage < 5) {
          _backgroundCrawlNextPage();
        }
      });
    } catch (e) {
      print('🎬 背景爬取失敗: $e');
    }
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

  // 新增：顯示關閉APP對話框
  void _showExitAppDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('關閉應用程式'),
          content: const Text('確定要關閉 VideoTV 嗎？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                // 關閉APP
                SystemNavigator.pop();
              },
              child: const Text('關閉'),
            ),
          ],
        );
      },
    );
  }

  // 新增：判斷是否為動畫影片
  bool _isAnimeVideo(Map<String, dynamic> video) {
    final detailUrl = video['detail_url'] as String? ?? '';
    return detailUrl.contains('hanime1.me');
  }

  // 修改 _buildMenuTile 支援外部傳入 FocusNode 與 autofocus
  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    required FocusNode focusNode,
    required bool autofocus,
  }) {
    return Focus(
      focusNode: focusNode,
      autofocus: autofocus,
      onKey: (node, event) {
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            // 找到當前 FocusNode 的索引
            final currentIndex = _menuFocusNodes.indexOf(focusNode);
            if (currentIndex > 0) {
              // 如果不是第一個項目，則移動到上一個項目
              FocusScope.of(context)
                  .requestFocus(_menuFocusNodes[currentIndex - 1]);
            }
            HapticFeedback.selectionClick();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            // 找到當前 FocusNode 的索引
            final currentIndex = _menuFocusNodes.indexOf(focusNode);
            if (currentIndex < _menuFocusNodes.length - 1) {
              // 如果不是最後一個項目，則移動到下一個項目
              FocusScope.of(context)
                  .requestFocus(_menuFocusNodes[currentIndex + 1]);
            }
            HapticFeedback.selectionClick();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            onTap();
            HapticFeedback.selectionClick();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: hasFocus
                  ? Colors.white.withOpacity(0.2)
                  : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasFocus
                    ? Colors.white.withOpacity(0.6)
                    : Colors.white.withOpacity(0.1),
                width: hasFocus ? 2 : 1,
              ),
              boxShadow: hasFocus
                  ? [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: hasFocus
                            ? Colors.white.withOpacity(0.3)
                            : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight:
                                  hasFocus ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: hasFocus
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (hasFocus)
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
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
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.video_library,
                                size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('尚無影片資料',
                                style: TextStyle(
                                    fontSize: 18, color: Colors.grey)),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4, // TV 模式使用 4 列
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.65, // 調整為更寬的比例，適合真人影片的比例
                        ),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final isAnime = _isAnimeVideo(item);

                          return Focus(
                            onFocusChange: (hasFocus) {
                              if (hasFocus) {
                                print(
                                    "選擇${isAnime ? '動畫' : '影片'}: ${item['title']}");
                              }
                            },
                            onKey: (node, event) {
                              if (event is RawKeyDownEvent) {
                                if (event.logicalKey ==
                                        LogicalKeyboardKey.select ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.enter ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.space) {
                                  print(
                                      "點擊${isAnime ? '動畫' : '影片'}: ${item['title']}");
                                  _playVideo(item);
                                  HapticFeedback.selectionClick();
                                  return KeyEventResult.handled;
                                }
                                // 處理方向鍵
                                else if (event.logicalKey ==
                                        LogicalKeyboardKey.arrowLeft ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.arrowRight ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.arrowUp ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.arrowDown) {
                                  // 讓方向鍵事件繼續傳遞，這樣 GridView 可以處理焦點移動
                                  return KeyEventResult.ignored;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (context) {
                                final hasFocus = Focus.of(context).hasFocus;
                                return Container(
                                  margin: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: hasFocus
                                        ? Border.all(
                                            color: isAnime
                                                ? Colors.pink
                                                : Colors.blue,
                                            width: 3)
                                        : null,
                                    boxShadow: hasFocus
                                        ? [
                                            BoxShadow(
                                              color: (isAnime
                                                      ? Colors.pink
                                                      : Colors.blue)
                                                  .withOpacity(0.5),
                                              blurRadius: 10,
                                              spreadRadius: 2,
                                            ),
                                          ]
                                        : [
                                            BoxShadow(
                                              color:
                                                  Colors.black.withOpacity(0.1),
                                              blurRadius: 4,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                  ),
                                  child: Card(
                                    elevation: 0,
                                    margin: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: InkWell(
                                      onTap: () {
                                        print(
                                            "點擊${isAnime ? '動畫' : '影片'}: ${item['title']}");
                                        _playVideo(item);
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          // 圖片區域 - 使用 Expanded 讓圖片自動適應
                                          Expanded(
                                            flex: 3, // 圖片占 3/4 的空間
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    const BorderRadius.vertical(
                                                  top: Radius.circular(12),
                                                ),
                                                color: Colors.grey.shade200,
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  item['img_url'].isNotEmpty
                                                      ? Image.network(
                                                          item['img_url'],
                                                          fit: BoxFit
                                                              .cover, // 保持圖片比例，填滿容器
                                                          errorBuilder:
                                                              (context, error,
                                                                  stackTrace) {
                                                            return Container(
                                                              color: Colors.grey
                                                                  .shade300,
                                                              child: Center(
                                                                child: Column(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  children: [
                                                                    Icon(
                                                                      isAnime
                                                                          ? Icons
                                                                              .animation
                                                                          : Icons
                                                                              .video_library,
                                                                      size: 32,
                                                                      color: Colors
                                                                          .grey,
                                                                    ),
                                                                    const SizedBox(
                                                                        height:
                                                                            4),
                                                                    Text(
                                                                      isAnime
                                                                          ? '動畫'
                                                                          : '影片',
                                                                      style:
                                                                          const TextStyle(
                                                                        fontSize:
                                                                            10,
                                                                        color: Colors
                                                                            .grey,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        )
                                                      : Container(
                                                          color: Colors
                                                              .grey.shade300,
                                                          child: Center(
                                                            child: Column(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                Icon(
                                                                  isAnime
                                                                      ? Icons
                                                                          .animation
                                                                      : Icons
                                                                          .video_library,
                                                                  size: 32,
                                                                  color: Colors
                                                                      .grey,
                                                                ),
                                                                const SizedBox(
                                                                    height: 4),
                                                                Text(
                                                                  isAnime
                                                                      ? '動畫'
                                                                      : '影片',
                                                                  style:
                                                                      const TextStyle(
                                                                    fontSize:
                                                                        10,
                                                                    color: Colors
                                                                        .grey,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                  // 播放覆蓋層
                                                  if (hasFocus)
                                                    Container(
                                                      color: Colors.black
                                                          .withOpacity(0.3),
                                                      child: const Center(
                                                        child: Icon(
                                                          Icons
                                                              .play_circle_filled,
                                                          color: Colors.white,
                                                          size: 48,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          // 文字區域 - 固定高度，占 1/4 的空間
                                          Expanded(
                                            flex: 1, // 文字占 1/4 的空間
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.all(8.0),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      item['title'],
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: hasFocus
                                                            ? Colors.blue
                                                            : Colors.black87,
                                                      ),
                                                    ),
                                                  ),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(
                                                        '影片 ${item['id']}',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: hasFocus
                                                              ? Colors
                                                                  .blue.shade300
                                                              : Colors.grey,
                                                        ),
                                                      ),
                                                      // 收藏按鈕
                                                      Focus(
                                                        onKey: (node, event) {
                                                          if (event
                                                              is RawKeyDownEvent) {
                                                            if (event.logicalKey == LogicalKeyboardKey.select ||
                                                                event.logicalKey ==
                                                                    LogicalKeyboardKey
                                                                        .enter ||
                                                                event.logicalKey ==
                                                                    LogicalKeyboardKey
                                                                        .space) {
                                                              _toggleFavorite(
                                                                  item);
                                                              HapticFeedback
                                                                  .selectionClick();
                                                              return KeyEventResult
                                                                  .handled;
                                                            }
                                                          }
                                                          return KeyEventResult
                                                              .ignored;
                                                        },
                                                        child: InkWell(
                                                          onTap: () =>
                                                              _toggleFavorite(
                                                                  item),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(12),
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(4),
                                                            child: Icon(
                                                              _isVideoFavorite(
                                                                      item)
                                                                  ? Icons
                                                                      .favorite
                                                                  : Icons
                                                                      .favorite_border,
                                                              size: 16,
                                                              color: _isVideoFavorite(
                                                                      item)
                                                                  ? Colors.red
                                                                  : (hasFocus
                                                                      ? Colors
                                                                          .blue
                                                                      : Colors
                                                                          .grey),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
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
                                );
                              },
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
              // 全螢幕 loading 過場動畫
              if (_isShowingLoadingTransition)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.85),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 主要旋轉動畫
                          TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 1200),
                            tween: Tween(begin: 0.0, end: 1.0),
                            builder: (context, value, child) {
                              return Transform.rotate(
                                angle: value * 6.28, // 2 * pi
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.blue,
                                      width: 4,
                                    ),
                                    gradient: SweepGradient(
                                      colors: [
                                        Colors.blue.withOpacity(0.1),
                                        Colors.blue,
                                        Colors.lightBlue,
                                        Colors.blue.withOpacity(0.1),
                                      ],
                                      stops: [0.0, 0.3, 0.7, 1.0],
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.cloud_download,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          // 文字動畫
                          TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 800),
                            tween: Tween(begin: 0.0, end: 1.0),
                            builder: (context, value, child) {
                              return Opacity(
                                opacity: value,
                                child: Transform.scale(
                                  scale: 0.8 + (value * 0.2),
                                  child: Text(
                                    _loadingMessage,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          // 進度條動畫
                          TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 1000),
                            tween: Tween(begin: 0.0, end: 1.0),
                            builder: (context, value, child) {
                              return Container(
                                width: 200,
                                height: 4,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2),
                                  color: Colors.white.withOpacity(0.2),
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    width: 200 * value,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(2),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Colors.blue,
                                          Colors.lightBlue,
                                          Colors.cyan,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          // 百分比動畫
                          TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 1000),
                            tween: Tween(begin: 0.0, end: 100.0),
                            builder: (context, value, child) {
                              return Text(
                                '${value.toInt()}%',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // 右側抽屜選單
          endDrawer: Drawer(
            width: 400, // 增加選單寬度
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.blue.shade800,
                    Colors.blue.shade600,
                    Colors.blue.shade400,
                  ],
                ),
              ),
              child: Column(
                children: [
                  // 精簡後的選單標題區域（縮小高度）
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    child: SafeArea(
                      bottom: false,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.video_library,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'VideoTV',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 精簡後的選單選項列表
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildMenuTile(
                            icon: Icons.favorite,
                            title: '收藏影片',
                            subtitle: '查看已收藏的影片',
                            onTap: () {
                              Navigator.pop(context);
                              setState(() {
                                _showFavoritesOnly = true;
                                _items = _favoriteItems;
                                // 切換後重新計算圖片比例
                              });
                              _showToast('顯示收藏影片');
                            },
                            focusNode: _menuFocusNodes[0],
                            autofocus: true,
                          ),
                          _buildMenuTile(
                            icon: Icons.person,
                            title: '真人影片',
                            subtitle: '爬取新的真人影片',
                            onTap: () {
                              Navigator.pop(context);
                              _startCrawling();
                            },
                            focusNode: _menuFocusNodes[1],
                            autofocus: false,
                          ),
                          _buildMenuTile(
                            icon: Icons.animation,
                            title: '裏番動畫',
                            subtitle: '爬取新的動畫影片',
                            onTap: () {
                              Navigator.pop(context);
                              _startAnimeCrawling();
                            },
                            focusNode: _menuFocusNodes[2],
                            autofocus: false,
                          ),
                          // 空格間隔
                          const SizedBox(height: 16),
                          _buildMenuTile(
                            icon: Icons.system_update,
                            title: '軟體更新',
                            subtitle: '檢查並下載最新版本',
                            onTap: () {
                              Navigator.pop(context);
                              _checkForUpdate();
                            },
                            focusNode: _menuFocusNodes[3],
                            autofocus: false,
                          ),
                          _buildMenuTile(
                            icon: Icons.exit_to_app,
                            title: '退出APP',
                            subtitle: '關閉應用程式',
                            onTap: () {
                              Navigator.pop(context);
                              _showExitAppDialog();
                            },
                            focusNode: _menuFocusNodes[4],
                            autofocus: false,
                          ),
                          if (_isLoading)
                            Padding(
                              padding: const EdgeInsets.only(top: 24.0),
                              child: Column(
                                children: [
                                  const CircularProgressIndicator(
                                      color: Colors.white),
                                  const SizedBox(height: 12),
                                  Text(
                                    _statusMessage,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // 不再需要底部說明與其他內容
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
    for (final node in _menuFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String title;
  final String url;
  final bool isAnime; // 新增：標識是否為動畫影片
  final VoidCallback? onPlayStarted; // 新增：播放開始時的回調，設為可選

  const VideoPlayerScreen({
    super.key,
    required this.title,
    required this.url,
    this.isAnime = false, // 預設為真人影片
    this.onPlayStarted, // 新增：播放開始時的回調，設為可選
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  late WebViewController _webViewController; // 新增：用於抓取推薦影片的 WebViewController
  bool _initialized = false;
  String? _error;
  bool _isLoading = true;
  final FocusNode _focusNode = FocusNode();
  bool _showControls = false;
  Timer? _hideControlsTimer;
  Timer? _keepAwakeTimer;
  Map<LogicalKeyboardKey, DateTime> _keyDownTime = {};
  Map<LogicalKeyboardKey, Timer?> _keyHoldTimers = {};
  bool _isLongPress = false;
  double _playbackSpeed = 1.0;
  bool _isFullScreen = false;
  OverlayEntry? _fastSeekOverlay;
  bool _isBuffering = false;

  // 新增：推薦影片相關
  bool _showRecommendations = false;
  List<Map<String, dynamic>> _recommendedVideos = [];
  final FocusNode _recommendationsFocusNode = FocusNode();
  Timer? _continuousSeekTimer; // 新增：連續快進計時器

  @override
  void initState() {
    super.initState();
    _initializeWebView(); // 初始化 WebView
    _initializePlayer();
    _startKeepAwakeTimer();
    _loadRecommendations(); // 載入推薦影片
  }

  // 新增：初始化 WebViewController
  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
  }

  void _startKeepAwakeTimer() {
    _keepAwakeTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && _controller.value.isPlaying) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
        print("🎬 防待機: 保持螢幕喚醒");
      }
    });
  }

  Future<void> _initializePlayer() async {
    try {
      print("🎬 ${widget.isAnime ? '動畫' : '影片'}播放器初始化，URL: ${widget.url}");
      String cleanUrl = widget.url.trim();
      if (cleanUrl.startsWith('"') && cleanUrl.endsWith('"')) {
        cleanUrl = cleanUrl.substring(1, cleanUrl.length - 1);
      }
      print("🎬 清理後的 URL: ${cleanUrl}");

      // 根據影片類型設置不同的 headers
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(cleanUrl),
        httpHeaders: widget.isAnime
            ? {
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
              }
            : {
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
        // 監聽緩衝狀態
        if (_controller.value.isBuffering != _isBuffering) {
          setState(() {
            _isBuffering = _controller.value.isBuffering;
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

        // 播放開始時調用回調
        widget.onPlayStarted?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "無法播放此${widget.isAnime ? '動畫' : '影片'}: $e";
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
        ? current + const Duration(seconds: 5)
        : current - const Duration(seconds: 5);
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
                  Icon(Icons.fast_rewind,
                      color: widget.isAnime ? Colors.pink : Colors.white,
                      size: 80),
                const SizedBox(width: 40),
                if (isRight)
                  Icon(Icons.fast_forward,
                      color: widget.isAnime ? Colors.pink : Colors.white,
                      size: 80),
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
    _recommendationsFocusNode.dispose(); // 新增
    _hideControlsTimer?.cancel();
    _keepAwakeTimer?.cancel();
    _fastSeekOverlay?.remove();
    _continuousSeekTimer?.cancel(); // 新增
    // WebViewController 不需要手動 dispose
    // 取消所有計時器
    for (var timer in _keyHoldTimers.values) {
      timer?.cancel();
    }
    _keyHoldTimers.clear();
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
          // 上鍵顯示/隱藏控制層
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            if (_showRecommendations) {
              // 如果正在顯示推薦，上鍵會隱藏推薦並回到播放
              setState(() {
                _showRecommendations = false;
                _showControls = false;
              });
              _controller.play();
            } else {
              // 正常的控制層顯示/隱藏
              setState(() {
                _showControls = !_showControls;
                _showRecommendations = false;
              });
            }
            HapticFeedback.selectionClick();
            return;
          }
          // 下鍵顯示推薦影片
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (!_showRecommendations) {
              // 只有在未顯示推薦時才顯示
              setState(() {
                _showRecommendations = true;
                _showControls = false;
              });
              _controller.pause(); // 暫停播放
              await _loadRecommendations(); // 載入推薦影片
            }
            HapticFeedback.selectionClick();
            return;
          }
          // OK/Enter/空白鍵切換播放/暫停
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            if (_controller.value.isPlaying) {
              // 暫停時顯示推薦影片列表 (類似 YouTube TV)
              _controller.pause();
              setState(() {
                _showRecommendations = true;
                _showControls = false;
              });
              await _loadRecommendations(); // 確保推薦影片已載入
            } else {
              // 繼續播放時隱藏推薦影片
              _controller.play();
              setState(() {
                _showRecommendations = false;
                _showControls = false;
              });
            }
            HapticFeedback.selectionClick();
            return;
          }
          // 左右鍵處理 - 修復長按快進
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            // 記錄按下時間
            _keyDownTime[event.logicalKey] = DateTime.now();
            _isLongPress = false;

            // 立即執行一次快進/倒退
            _executeSeek(event.logicalKey);

            // 設置長按計時器，500ms 後開始連續快進
            _keyHoldTimers[event.logicalKey]?.cancel();
            _keyHoldTimers[event.logicalKey] =
                Timer(const Duration(milliseconds: 500), () {
              if (mounted && _keyDownTime.containsKey(event.logicalKey)) {
                setState(() {
                  _isLongPress = true;
                });

                // 開始連續快進
                _startContinuousSeek(event.logicalKey);
              }
            });
          }
        } else if (event is RawKeyUpEvent) {
          // 左右鍵快轉/倒退 - 停止連續快進
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            // 取消所有計時器
            _keyHoldTimers[event.logicalKey]?.cancel();
            _keyHoldTimers[event.logicalKey] = null;
            _continuousSeekTimer?.cancel();
            _continuousSeekTimer = null;

            // 清除按下記錄
            _keyDownTime.remove(event.logicalKey);
            setState(() {
              _isLongPress = false;
            });
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
            Text(
              '${widget.isAnime ? '動畫' : '影片'}播放失敗',
              style: const TextStyle(
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 16),
          Text(
            '正在載入${widget.isAnime ? '動畫' : '影片'}...',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          if (widget.isAnime) ...[
            const SizedBox(height: 8),
            const Text(
              '動畫影片可能需要較長時間載入',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
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
          // 緩衝指示器
          if (_isBuffering)
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
          // 推薦影片覆蓋層
          if (_showRecommendations) _buildRecommendationsOverlay(),
          // 控制層
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
                            if (widget.isAnime)
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
                      onTap: () async {
                        setState(() {
                          if (_controller.value.isPlaying) {
                            // 暫停時顯示推薦影片列表 (類似 YouTube TV)
                            _controller.pause();
                            _showRecommendations = true;
                            _showControls = false;
                          } else {
                            // 繼續播放時隱藏推薦影片
                            _controller.play();
                            _showRecommendations = false;
                            _showControls = false;
                          }
                          _onUserInteraction();
                        });

                        // 如果剛暫停，載入推薦影片
                        if (!_controller.value.isPlaying) {
                          await _loadRecommendations();
                        }

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
                            colors: VideoProgressColors(
                              playedColor:
                                  widget.isAnime ? Colors.pink : Colors.red,
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

  // 新增：建構推薦影片覆蓋層
  Widget _buildRecommendationsOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.9),
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '推薦${widget.isAnime ? "動畫" : "影片"}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _recommendedVideos.length,
                itemBuilder: (context, index) {
                  final video = _recommendedVideos[index];
                  return Focus(
                    focusNode: index == 0 ? _recommendationsFocusNode : null,
                    autofocus: index == 0,
                    onKey: (node, event) {
                      if (event is RawKeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.select ||
                            event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.space) {
                          _playRecommendedVideo(video);
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (context) {
                        final hasFocus = Focus.of(context).hasFocus;
                        return Container(
                          width: 160,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: hasFocus
                                ? Border.all(color: Colors.blue, width: 2)
                                : null,
                          ),
                          child: InkWell(
                            onTap: () => _playRecommendedVideo(video),
                            borderRadius: BorderRadius.circular(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(8),
                                      ),
                                      color: Colors.grey.shade800,
                                    ),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (video['img_url']?.isNotEmpty ==
                                            true)
                                          ClipRRect(
                                            borderRadius:
                                                const BorderRadius.vertical(
                                              top: Radius.circular(8),
                                            ),
                                            child: Image.network(
                                              video['img_url'],
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                return const Center(
                                                  child: Icon(
                                                    Icons.video_library,
                                                    color: Colors.white,
                                                    size: 32,
                                                  ),
                                                );
                                              },
                                            ),
                                          )
                                        else
                                          const Center(
                                            child: Icon(
                                              Icons.video_library,
                                              color: Colors.white,
                                              size: 32,
                                            ),
                                          ),
                                        const Center(
                                          child: Icon(
                                            Icons.play_circle_filled,
                                            color: Colors.white,
                                            size: 40,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    video['title'] ?? '未知標題',
                                    style: TextStyle(
                                      color:
                                          hasFocus ? Colors.blue : Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 新增：播放推薦影片
  void _playRecommendedVideo(Map<String, dynamic> video) async {
    setState(() {
      _showRecommendations = false;
    });

    // 停止當前播放
    await _controller.pause();

    // 根據影片類型判斷是否為動畫
    bool isAnimeVideo = false;
    final detailUrl = video['detail_url'] ?? '';
    final videoType = video['type'] ?? '';

    // 如果有類型標記，根據類型判斷
    if (videoType.contains('anime')) {
      isAnimeVideo = true;
    } else if (videoType.contains('actress')) {
      isAnimeVideo = false;
    } else {
      // 如果沒有類型標記，根據 URL 判斷
      isAnimeVideo = detailUrl.contains('hanime1.me');
    }

    String? finalPlayUrl;

    try {
      // 對於真人影片，需要先提取播放 URL
      if (!isAnimeVideo && detailUrl.contains('jable.tv')) {
        print('🎬 真人推薦影片：載入詳細頁面提取播放地址...');

        // 載入影片詳細頁面
        await _webViewController.loadRequest(Uri.parse(detailUrl));
        await Future.delayed(const Duration(seconds: 3));

        // 提取播放 URL（使用與 RealCrawler 相同的邏輯）
        final result = await _webViewController.runJavaScriptReturningResult('''
          (function() {
            console.log('🎬 開始提取真人影片播放地址...');
            
            // 查找 iframe 中的影片地址
            const iframe = document.querySelector('#player iframe');
            if (iframe) {
              const src = iframe.getAttribute('src');
              console.log('🎬 找到 iframe src:', src);
              return JSON.stringify({ success: true, url: src });
            }
            
            // 備用方法：查找 video 標籤
            const video = document.querySelector('video source');
            if (video) {
              const src = video.getAttribute('src');
              console.log('🎬 找到 video src:', src);
              return JSON.stringify({ success: true, url: src });
            }
            
            // 備用方法：查找 script 中的影片地址
            const scripts = document.querySelectorAll('script');
            for (let script of scripts) {
              const content = script.innerHTML;
              if (content.includes('.m3u8') || content.includes('.mp4')) {
                const urlMatch = content.match(/(https?:\\/\\/[^"'\\s]+\\.(m3u8|mp4))/);
                if (urlMatch) {
                  console.log('🎬 從 script 找到播放地址:', urlMatch[1]);
                  return JSON.stringify({ success: true, url: urlMatch[1] });
                }
              }
            }
            
            console.log('🎬 未找到播放地址');
            return JSON.stringify({ success: false, error: '未找到播放地址' });
          })();
        ''');

        String resultString = result.toString();
        dynamic data = jsonDecode(resultString);

        if (data is String) {
          data = jsonDecode(data);
        }

        if (data['success'] == true) {
          finalPlayUrl = data['url'];
          print('🎬 成功提取真人影片播放地址: $finalPlayUrl');
        } else {
          print('🎬 提取播放地址失敗，將在外部瀏覽器開啟');
          finalPlayUrl = null;
        }
      } else {
        // 動畫影片直接使用 detailUrl
        finalPlayUrl = detailUrl;
      }
    } catch (e) {
      print('🎬 提取播放地址時發生錯誤: $e');
      finalPlayUrl = null;
    }

    // 導航到新的影片播放頁面
    if (mounted) {
      if (finalPlayUrl != null && finalPlayUrl.isNotEmpty) {
        // 有播放地址時直接播放
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              title: video['title'] ?? '未知標題',
              url: finalPlayUrl!, // 使用 ! 確保不是 null
              isAnime: isAnimeVideo,
            ),
          ),
        );
      } else {
        // 沒有播放地址時詢問是否在外部瀏覽器開啟
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('無法自動播放'),
              content: Text(
                  '無法自動提取「${video['title'] ?? '未知標題'}」的播放地址。\n\n是否要在外部瀏覽器開啟頁面？\n您可以在瀏覽器中手動播放影片。'),
              actions: <Widget>[
                TextButton(
                  child: const Text('取消'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    // 恢復播放當前影片
                    _controller.play();
                    setState(() {
                      _showRecommendations = false;
                    });
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
                    }
                    // 恢復播放當前影片
                    _controller.play();
                    setState(() {
                      _showRecommendations = false;
                    });
                  },
                ),
              ],
            );
          },
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return '${d.inHours > 0 ? '${twoDigits(d.inHours)}:' : ''}$twoDigitMinutes:$twoDigitSeconds';
  }

  // 修改：執行快轉/倒退
  void _executeSeek(LogicalKeyboardKey key) {
    final isRight = key == LogicalKeyboardKey.arrowRight;

    // 根據是否長按決定快進的時間間隔
    final seekSeconds = _isLongPress ? 5 : 15; // 長按時 5 秒，短按時 15 秒

    final current = _controller.value.position;
    final newPosition = isRight
        ? current + Duration(seconds: seekSeconds)
        : current - Duration(seconds: seekSeconds);

    _controller
        .seekTo(newPosition > Duration.zero ? newPosition : Duration.zero);

    // 顯示快進/倒退指示器
    _showFastSeekOverlay(isRight);
    HapticFeedback.mediumImpact();
  }

  // 新增：載入推薦影片
  Future<void> _loadRecommendations() async {
    try {
      print('🔍 開始載入推薦影片...');

      if (widget.isAnime) {
        // 動畫影片：抓取相關動畫列表
        await _loadAnimeRecommendations();
      } else {
        // 真人影片：抓取同一女優的其他作品
        await _loadActressRecommendations();
      }
    } catch (e) {
      print('載入推薦影片失敗: $e');
      // 如果智能推薦失敗，回退到隨機推薦
      await _loadFallbackRecommendations();
    }
  }

  // 新增：載入動畫推薦影片（從影片內頁抓取相關列表）
  Future<void> _loadAnimeRecommendations() async {
    try {
      print('🎭 載入動畫推薦影片...');

      // 先載入詳細頁面（如果還沒載入）
      final currentUrl = await _webViewController.currentUrl();
      if (currentUrl != widget.url) {
        await _webViewController.loadRequest(Uri.parse(widget.url));
        await Future.delayed(const Duration(seconds: 3));
      }

      final result = await _webViewController.runJavaScriptReturningResult('''
        (function() {
          console.log('🎭 開始抓取動畫相關推薦...');
          
          // 抓取播放清單相關影片
          const playlistContainer = document.querySelector('#playlist-scroll');
          const relatedVideos = [];
          
          if (playlistContainer) {
            console.log('🎭 找到播放清單容器');
            const videoElements = playlistContainer.querySelectorAll('a[href*="/watch"]');
            
            videoElements.forEach((element, index) => {
              if (index >= 10) return; // 限制數量
              
              const title = element.getAttribute('title') || 
                           element.querySelector('img')?.getAttribute('alt') || 
                           element.innerText?.trim() || 
                           '相關動畫 ' + (index + 1);
              
              let href = element.getAttribute('href') || '';
              if (href && !href.startsWith('http')) {
                href = 'https://hanime1.me' + (href.startsWith('/') ? href : '/' + href);
              }
              
              const img = element.querySelector('img');
              let imgSrc = '';
              if (img) {
                imgSrc = img.getAttribute('src') || 
                        img.getAttribute('data-src') || '';
                if (imgSrc && !imgSrc.startsWith('http') && imgSrc.startsWith('/')) {
                  imgSrc = 'https://hanime1.me' + imgSrc;
                }
              }
              
              if (title && href) {
                relatedVideos.push({
                  title: title.substring(0, 100),
                  detail_url: href,
                  img_url: imgSrc,
                  type: 'anime_related'
                });
                console.log('🎭 找到相關動畫:', title);
              }
            });
          }
          
          // 如果播放清單沒有足夠的影片，嘗試從其他地方抓取
          if (relatedVideos.length < 5) {
            console.log('🎭 播放清單影片不足，尋找其他推薦...');
            const allLinks = document.querySelectorAll('a[href*="/watch"]');
            
            allLinks.forEach((link, index) => {
              if (relatedVideos.length >= 10) return;
              
              const title = link.getAttribute('title') || 
                           link.querySelector('img')?.getAttribute('alt') || 
                           link.innerText?.trim();
              
              if (title && title.length > 2) {
                let href = link.getAttribute('href') || '';
                if (href && !href.startsWith('http')) {
                  href = 'https://hanime1.me' + (href.startsWith('/') ? href : '/' + href);
                }
                
                const img = link.querySelector('img');
                let imgSrc = '';
                if (img) {
                  imgSrc = img.getAttribute('src') || 
                          img.getAttribute('data-src') || '';
                  if (imgSrc && !imgSrc.startsWith('http') && imgSrc.startsWith('/')) {
                    imgSrc = 'https://hanime1.me' + imgSrc;
                  }
                }
                
                // 避免重複
                const isDuplicate = relatedVideos.some(v => v.detail_url === href);
                if (!isDuplicate) {
                  relatedVideos.push({
                    title: title.substring(0, 100),
                    detail_url: href,
                    img_url: imgSrc,
                    type: 'anime_general'
                  });
                }
              }
            });
          }
          
          console.log('🎭 總共找到', relatedVideos.length, '個推薦動畫');
          return JSON.stringify({ success: true, videos: relatedVideos });
        })();
      ''');

      String resultString = result.toString();
      dynamic data = jsonDecode(resultString);

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data['success'] == true) {
        List<dynamic> videos = data['videos'];
        final recommendedVideos =
            videos.map((v) => Map<String, dynamic>.from(v)).toList();

        setState(() {
          _recommendedVideos = recommendedVideos;
        });

        print('🎭 成功載入 ${recommendedVideos.length} 個動畫推薦');
      } else {
        throw Exception('無法抓取動畫推薦');
      }
    } catch (e) {
      print('🎭 載入動畫推薦失敗: $e');
      throw e;
    }
  }

  // 新增：載入女優推薦影片（從影片內頁抓取同一女優的其他作品）
  Future<void> _loadActressRecommendations() async {
    try {
      print('👩 載入女優推薦影片...');

      // 先載入詳細頁面（如果還沒載入）
      final currentUrl = await _webViewController.currentUrl();
      if (currentUrl != widget.url) {
        await _webViewController.loadRequest(Uri.parse(widget.url));
        await Future.delayed(const Duration(seconds: 3));
      }

      final result = await _webViewController.runJavaScriptReturningResult('''
        (function() {
          console.log('👩 開始抓取女優推薦...');
          
          // 嘗試找到女優連結
          const actressLinkSelector = '#site-content div div div section:nth-child(2) div:nth-child(1) div:nth-child(1) h6 div a';
          const actressLink = document.querySelector(actressLinkSelector);
          
          let actressUrl = '';
          let actressName = '';
          
          if (actressLink) {
            actressUrl = actressLink.getAttribute('href') || '';
            actressName = actressLink.innerText?.trim() || '';
            console.log('👩 找到女優:', actressName, '連結:', actressUrl);
          } else {
            console.log('👩 未找到女優連結，嘗試其他方法...');
            
            // 備用方法：尋找包含女優名稱的連結
            const possibleActressLinks = document.querySelectorAll('a[href*="/models/"], a[href*="/actress/"], a[href*="/performers/"]');
            if (possibleActressLinks.length > 0) {
              actressUrl = possibleActressLinks[0].getAttribute('href') || '';
              actressName = possibleActressLinks[0].innerText?.trim() || '';
              console.log('👩 備用方法找到女優:', actressName, '連結:', actressUrl);
            }
          }
          
          // 如果找到女優連結，返回女優信息以便後續抓取
          if (actressUrl && actressName) {
            if (!actressUrl.startsWith('http')) {
              actressUrl = 'https://jable.tv' + (actressUrl.startsWith('/') ? actressUrl : '/' + actressUrl);
            }
            
            return JSON.stringify({ 
              success: true, 
              hasActress: true, 
              actressUrl: actressUrl, 
              actressName: actressName 
            });
          } else {
            console.log('👩 沒有找到女優信息，使用一般推薦');
            return JSON.stringify({ 
              success: true, 
              hasActress: false 
            });
          }
        })();
      ''');

      String resultString = result.toString();
      dynamic data = jsonDecode(resultString);

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data['success'] == true && data['hasActress'] == true) {
        // 如果找到女優，載入女優頁面抓取其他作品
        final actressUrl = data['actressUrl'];
        final actressName = data['actressName'];

        print('👩 準備載入女優頁面: $actressName');
        await _webViewController.loadRequest(Uri.parse(actressUrl));
        await Future.delayed(const Duration(seconds: 3));

        await _extractActressVideos(actressName);
      } else {
        throw Exception('未找到女優信息');
      }
    } catch (e) {
      print('👩 載入女優推薦失敗: $e');
      throw e;
    }
  }

  // 新增：從女優頁面抓取影片
  Future<void> _extractActressVideos(String actressName) async {
    try {
      final result = await _webViewController.runJavaScriptReturningResult('''
        (function() {
          console.log('👩 開始從女優頁面抓取影片...');
          
          const videoElements = document.querySelectorAll('.video-img-box');
          const actressVideos = [];
          
          videoElements.forEach((element, index) => {
            if (index >= 10) return; // 限制數量
            
            const titleElement = element.querySelector('.detail .title a');
            const imgElement = element.querySelector('img');
            
            if (titleElement) {
              const title = titleElement.innerText?.trim() || '';
              let detailUrl = titleElement.getAttribute('href') || '';
              let imgUrl = imgElement?.getAttribute('data-src') || 
                           imgElement?.getAttribute('src') || '';
              
              // 確保 URL 是完整的絕對路徑
              if (detailUrl && !detailUrl.startsWith('http')) {
                detailUrl = 'https://jable.tv' + (detailUrl.startsWith('/') ? detailUrl : '/' + detailUrl);
              }
              
              // 確保圖片 URL 是完整的絕對路徑
              if (imgUrl && !imgUrl.startsWith('http') && imgUrl.startsWith('/')) {
                imgUrl = 'https://jable.tv' + imgUrl;
              }
              
              if (title && detailUrl) {
                actressVideos.push({
                  title: title,
                  detail_url: detailUrl,
                  img_url: imgUrl,
                  actress: '$actressName',
                  type: 'actress_video'
                });
                console.log('👩 找到女優作品:', title, '網址:', detailUrl);
              }
            }
          });
          
          console.log('👩 總共找到', actressVideos.length, '個女優作品');
          return JSON.stringify({ success: true, videos: actressVideos });
        })();
      ''');

      String resultString = result.toString();
      dynamic data = jsonDecode(resultString);

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data['success'] == true) {
        List<dynamic> videos = data['videos'];
        final actressVideos =
            videos.map((v) => Map<String, dynamic>.from(v)).toList();

        // 排除當前影片
        actressVideos.removeWhere((video) => video['title'] == widget.title);

        setState(() {
          _recommendedVideos = actressVideos;
        });

        print('👩 成功載入 ${actressVideos.length} 個女優作品推薦');
      } else {
        throw Exception('無法抓取女優作品');
      }
    } catch (e) {
      print('👩 抓取女優作品失敗: $e');
      throw e;
    }
  }

  // 新增：後備推薦方案（隨機推薦）
  Future<void> _loadFallbackRecommendations() async {
    try {
      print('🔄 使用後備推薦方案...');

      final dbRef = FirebaseDatabase.instance.ref();
      final targetRef =
          widget.isAnime ? dbRef.child('anime_videos') : dbRef.child('videos');

      final snapshot = await targetRef.get();
      if (snapshot.exists) {
        final data = snapshot.value;
        List<Map<String, dynamic>> allVideos = [];

        if (data is List) {
          allVideos = data
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
        } else if (data is Map) {
          allVideos = data.values
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        // 隨機選擇 10 個推薦影片（排除當前影片）
        allVideos.removeWhere((video) => video['title'] == widget.title);
        allVideos.shuffle();

        setState(() {
          _recommendedVideos = allVideos.take(10).toList();
        });

        print('🔄 後備推薦載入成功：${_recommendedVideos.length} 個影片');
      }
    } catch (e) {
      print('🔄 後備推薦也失敗了: $e');
    }
  }

  // 新增：開始連續快進
  void _startContinuousSeek(LogicalKeyboardKey key) {
    _continuousSeekTimer?.cancel();
    _continuousSeekTimer =
        Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (mounted && _isLongPress && _keyDownTime.containsKey(key)) {
        _executeSeek(key);
      } else {
        timer.cancel();
      }
    });
  }
}
