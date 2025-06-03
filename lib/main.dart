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

// 背景圖案畫家
class BackgroundPatternPainter extends CustomPainter {
  final Color color;

  BackgroundPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 繪製幾何圖案
    const double spacing = 60;
    for (double x = 0; x < size.width + spacing; x += spacing) {
      for (double y = 0; y < size.height + spacing; y += spacing) {
        canvas.drawCircle(Offset(x, y), 2, paint);

        // 添加連接線
        if (x + spacing < size.width) {
          canvas.drawLine(
            Offset(x + 2, y),
            Offset(x + spacing - 2, y),
            paint..strokeWidth = 0.5,
          );
        }
        if (y + spacing < size.height) {
          canvas.drawLine(
            Offset(x, y + 2),
            Offset(x, y + spacing - 2),
            paint..strokeWidth = 0.5,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // 主題色彩設計 - 深色主題為主，適合 TV 觀看
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF0A0A0F), // 深藍黑色背景
        cardColor: const Color(0xFF1A1A2E), // 卡片背景色
        dialogBackgroundColor: const Color(0xFF16213E), // 對話框背景

        // 自定義色彩
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF), // 主要紫色
          secondary: Color(0xFFFF6B9D), // 次要粉色
          tertiary: Color(0xFF4ECDC4), // 第三色 - 青綠色
          surface: Color(0xFF1A1A2E), // 表面色
          background: Color(0xFF0A0A0F), // 背景色
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white,
          onBackground: Colors.white,
        ),

        // 卡片主題
        cardTheme: const CardThemeData(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          color: Color(0xFF1A1A2E),
        ),

        // 應用欄主題
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0A0F),
          foregroundColor: Colors.white,
          elevation: 0,
        ),

        // 文字主題
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
          headlineMedium: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
          bodyLarge: TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
          bodyMedium: TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
          bodySmall: TextStyle(
            color: Colors.white60,
            fontSize: 12,
          ),
        ),

        // 按鈕主題
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),

        // 輸入框主題
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1A2E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6C63FF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF333333)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 2),
          ),
        ),
      ),
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

  Future<void> _showVideoDetails(Map<String, dynamic> video) async {
    if (_isVideoLoading) return;

    // 顯示詳細視窗
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return VideoDetailDialog(
          video: video,
          isAnime: _isAnimeVideo(video),
          isFavorite: _isVideoFavorite(video),
          onToggleFavorite: () => _toggleFavorite(video),
          onPlay: () => _playVideoDirectly(video),
        );
      },
    );
  }

  Future<void> _playVideoDirectly(Map<String, dynamic> video) async {
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
    final theme = Theme.of(context);
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
          backgroundColor: theme.colorScheme.background,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.background,
                  theme.colorScheme.surface.withOpacity(0.3),
                  theme.colorScheme.background,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: Stack(
              children: [
                // 背景裝飾圖案
                Positioned.fill(
                  child: CustomPaint(
                    painter: BackgroundPatternPainter(
                      color: theme.colorScheme.primary.withOpacity(0.03),
                    ),
                  ),
                ),
                // 主要內容
                Positioned.fill(
                  child: _items.isEmpty
                      ? _buildEmptyState(theme)
                      : _buildVideoGrid(theme),
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
                // 載入指示器
                if (_isVideoLoading) _buildVideoLoadingOverlay(theme),
                if (_downloadProgress != null) _buildDownloadProgress(theme),
                // 全螢幕 loading 過場動畫
                if (_isShowingLoadingTransition) _buildLoadingTransition(theme),
              ],
            ),
          ),
          // 重新設計右側抽屜選單
          endDrawer: _buildModernDrawer(theme),
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

  // 建構空狀態頁面
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.3),
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.video_library_outlined,
              size: 80,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '尚無影片資料',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '開啟選單開始爬取影片',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard_return,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '按返回鍵開啟選單',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 建構影片網格
  Widget _buildVideoGrid(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, // TV 模式使用 4 列
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
          childAspectRatio: 0.65, // 調整為更寬的比例，適合影片比例
        ),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          final isAnime = _isAnimeVideo(item);

          return _buildVideoCard(item, isAnime, theme);
        },
      ),
    );
  }

  // 建構影片卡片
  Widget _buildVideoCard(
      Map<String, dynamic> item, bool isAnime, ThemeData theme) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          print("選擇${isAnime ? '動畫' : '影片'}: ${item['title']}");
        }
      },
      onKey: (node, event) {
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            print("點擊${isAnime ? '動畫' : '影片'}: ${item['title']}");
            _showVideoDetails(item);
            HapticFeedback.selectionClick();
            return KeyEventResult.handled;
          }
          // 處理方向鍵
          else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.arrowDown) {
            return KeyEventResult.ignored;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            transform: Matrix4.identity()..scale(hasFocus ? 1.05 : 1.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: hasFocus
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          (isAnime
                                  ? theme.colorScheme.secondary
                                  : theme.colorScheme.primary)
                              .withOpacity(0.2),
                          (isAnime
                                  ? theme.colorScheme.secondary
                                  : theme.colorScheme.primary)
                              .withOpacity(0.1),
                        ],
                      )
                    : null,
                border: hasFocus
                    ? Border.all(
                        color: isAnime
                            ? theme.colorScheme.secondary
                            : theme.colorScheme.primary,
                        width: 3,
                      )
                    : Border.all(
                        color: theme.colorScheme.surface,
                        width: 1,
                      ),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color: (isAnime
                                  ? theme.colorScheme.secondary
                                  : theme.colorScheme.primary)
                              .withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          spreadRadius: 0,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Card(
                elevation: 0,
                margin: EdgeInsets.zero,
                color: theme.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  onTap: () {
                    print("點擊${isAnime ? '動畫' : '影片'}: ${item['title']}");
                    _showVideoDetails(item);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 圖片區域
                      Expanded(
                        flex: 3,
                        child: Container(
                          decoration: const BoxDecoration(
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(16)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (item['img_url']?.isNotEmpty == true)
                                Image.network(
                                  item['img_url'],
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _buildPlaceholderImage(
                                        isAnime, theme);
                                  },
                                )
                              else
                                _buildPlaceholderImage(isAnime, theme),

                              // 類型標籤
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isAnime
                                        ? theme.colorScheme.secondary
                                        : theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    isAnime ? '動畫' : '真人',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),

                              // 收藏標籤
                              if (_isVideoFavorite(item))
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.9),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.favorite,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),

                              // 焦點時的播放圖標
                              if (hasFocus)
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.4),
                                    borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(16)),
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: (isAnime
                                                ? theme.colorScheme.secondary
                                                : theme.colorScheme.primary)
                                            .withOpacity(0.9),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.play_arrow,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // 文字區域
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  item['title'] ?? '未知標題',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: hasFocus
                                        ? (isAnime
                                            ? theme.colorScheme.secondary
                                            : theme.colorScheme.primary)
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'ID: ${item['id'] ?? 'N/A'}',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.6),
                                      ),
                                    ),
                                  ),
                                  if (hasFocus)
                                    Icon(
                                      Icons.touch_app,
                                      size: 16,
                                      color: (isAnime
                                              ? theme.colorScheme.secondary
                                              : theme.colorScheme.primary)
                                          .withOpacity(0.7),
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
            ),
          );
        },
      ),
    );
  }

  // 建構預設圖片
  Widget _buildPlaceholderImage(bool isAnime, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surface,
            theme.colorScheme.surface.withOpacity(0.7),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isAnime ? Icons.animation : Icons.video_library,
              size: 48,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
            const SizedBox(height: 8),
            Text(
              isAnime ? '動畫影片' : '真人影片',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 建構影片載入覆蓋層
  Widget _buildVideoLoadingOverlay(ThemeData theme) {
    return Positioned.fill(
      child: Container(
        color: theme.colorScheme.background.withOpacity(0.8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  '正在準備播放...',
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 建構下載進度
  Widget _buildDownloadProgress(ThemeData theme) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: _downloadProgress,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
              valueColor:
                  AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
            ),
            if (_downloadStatus != null) ...[
              const SizedBox(height: 8),
              Text(
                _downloadStatus!,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 建構載入轉場
  Widget _buildLoadingTransition(ThemeData theme) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.background.withOpacity(0.95),
              theme.colorScheme.surface.withOpacity(0.95),
              theme.colorScheme.background.withOpacity(0.95),
            ],
          ),
        ),
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
                          color: theme.colorScheme.primary,
                          width: 4,
                        ),
                        gradient: SweepGradient(
                          colors: [
                            theme.colorScheme.primary.withOpacity(0.1),
                            theme.colorScheme.primary,
                            theme.colorScheme.secondary,
                            theme.colorScheme.primary.withOpacity(0.1),
                          ],
                          stops: const [0.0, 0.3, 0.7, 1.0],
                        ),
                      ),
                      child: Icon(
                        Icons.cloud_download,
                        color: theme.colorScheme.onSurface,
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
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center,
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
                      color: theme.colorScheme.surface,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 200 * value,
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.secondary,
                              theme.colorScheme.tertiary,
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
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 建構現代化抽屜選單
  Widget _buildModernDrawer(ThemeData theme) {
    return Drawer(
      width: 420,
      backgroundColor: theme.dialogBackgroundColor,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.background,
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: Column(
          children: [
            // 標題區域
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.1),
                    theme.colorScheme.secondary.withOpacity(0.1),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.primary.withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.secondary,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.video_library,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'VideoTV',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '影片總數：${_items.length}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 選單選項
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildModernMenuTile(
                      icon: Icons.favorite_rounded,
                      title: '收藏影片',
                      subtitle: '查看已收藏的影片',
                      gradient: const LinearGradient(
                          colors: [Colors.red, Colors.pink]),
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _showFavoritesOnly = true;
                          _items = _favoriteItems;
                        });
                        _showToast('顯示收藏影片');
                      },
                      focusNode: _menuFocusNodes[0],
                      autofocus: true,
                      theme: theme,
                    ),
                    _buildModernMenuTile(
                      icon: Icons.person_rounded,
                      title: '真人影片',
                      subtitle: '爬取新的真人影片',
                      gradient: LinearGradient(colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.tertiary
                      ]),
                      onTap: () {
                        Navigator.pop(context);
                        _startCrawling();
                      },
                      focusNode: _menuFocusNodes[1],
                      autofocus: false,
                      theme: theme,
                    ),
                    _buildModernMenuTile(
                      icon: Icons.animation_rounded,
                      title: '裏番動畫',
                      subtitle: '爬取新的動畫影片',
                      gradient: LinearGradient(
                          colors: [theme.colorScheme.secondary, Colors.purple]),
                      onTap: () {
                        Navigator.pop(context);
                        _startAnimeCrawling();
                      },
                      focusNode: _menuFocusNodes[2],
                      autofocus: false,
                      theme: theme,
                    ),
                    const SizedBox(height: 20),
                    _buildModernMenuTile(
                      icon: Icons.system_update_rounded,
                      title: '軟體更新',
                      subtitle: '檢查並下載最新版本',
                      gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.deepOrange]),
                      onTap: () {
                        Navigator.pop(context);
                        _checkForUpdate();
                      },
                      focusNode: _menuFocusNodes[3],
                      autofocus: false,
                      theme: theme,
                    ),
                    _buildModernMenuTile(
                      icon: Icons.exit_to_app_rounded,
                      title: '退出APP',
                      subtitle: '關閉應用程式',
                      gradient: const LinearGradient(
                          colors: [Colors.grey, Colors.blueGrey]),
                      onTap: () {
                        Navigator.pop(context);
                        _showExitAppDialog();
                      },
                      focusNode: _menuFocusNodes[4],
                      autofocus: false,
                      theme: theme,
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.primary.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            CircularProgressIndicator(
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _statusMessage,
                              style: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 建構現代化選單項目
  Widget _buildModernMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Gradient gradient,
    required VoidCallback onTap,
    required FocusNode focusNode,
    required bool autofocus,
    required ThemeData theme,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Focus(
        focusNode: focusNode,
        autofocus: autofocus,
        onKey: (node, event) {
          if (event is RawKeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              final currentIndex = _menuFocusNodes.indexOf(focusNode);
              if (currentIndex > 0) {
                FocusScope.of(context)
                    .requestFocus(_menuFocusNodes[currentIndex - 1]);
              }
              HapticFeedback.selectionClick();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              final currentIndex = _menuFocusNodes.indexOf(focusNode);
              if (currentIndex < _menuFocusNodes.length - 1) {
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
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              transform: Matrix4.identity()..scale(hasFocus ? 1.02 : 1.0),
              decoration: BoxDecoration(
                gradient: hasFocus ? gradient : null,
                color: hasFocus
                    ? null
                    : theme.colorScheme.surface.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white.withOpacity(0.3)
                      : theme.colorScheme.primary.withOpacity(0.1),
                  width: hasFocus ? 2 : 1,
                ),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(0.3),
                          blurRadius: 16,
                          spreadRadius: 2,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: hasFocus
                                ? Colors.white.withOpacity(0.2)
                                : theme.colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            icon,
                            color: hasFocus
                                ? Colors.white
                                : theme.colorScheme.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: hasFocus
                                      ? Colors.white
                                      : theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: hasFocus
                                      ? Colors.white.withOpacity(0.8)
                                      : theme.colorScheme.onSurface
                                          .withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (hasFocus)
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// 影片播放器頁面
class VideoPlayerScreen extends StatefulWidget {
  final String title;
  final String url;
  final bool isAnime;

  const VideoPlayerScreen({
    super.key,
    required this.title,
    required this.url,
    this.isAnime = false,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  late WebViewController _webViewController;
  bool _initialized = false;
  bool _isLoading = true;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  double _playbackSpeed = 1.0;
  List<Map<String, dynamic>> _recommendedVideos = [];
  bool _isFullscreen = false;
  final FocusNode _playerFocusNode = FocusNode();
  Timer? _continuousSeekTimer;
  bool _isLongPress = false;
  Map<LogicalKeyboardKey, DateTime> _keyDownTime = {};

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _initializeWebView();
    _hideControlsAfterDelay();
  }

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
  }

  void _initializePlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
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
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放器初始化失敗: $e')),
        );
      }
    }
  }

  void _hideControlsAfterDelay() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _showControlsTemporarily() {
    setState(() {
      _showControls = true;
    });
    _hideControlsAfterDelay();
  }

  void _executeSeek(LogicalKeyboardKey key) {
    if (!_initialized) return;

    final currentPosition = _controller.value.position;
    Duration newPosition;

    if (key == LogicalKeyboardKey.arrowLeft) {
      newPosition = currentPosition - const Duration(seconds: 10);
    } else {
      newPosition = currentPosition + const Duration(seconds: 10);
    }

    if (newPosition < Duration.zero) {
      newPosition = Duration.zero;
    } else if (newPosition > _controller.value.duration) {
      newPosition = _controller.value.duration;
    }

    _controller.seekTo(newPosition);
    _showControlsTemporarily();
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          // 手機版：點擊畫面顯示/隱藏控制界面
          if (_showControls) {
            setState(() {
              _showControls = false;
            });
            _hideControlsTimer?.cancel();
          } else {
            _showControlsTemporarily();
          }
        },
        child: RawKeyboardListener(
          focusNode: _playerFocusNode,
          autofocus: true,
          onKey: (RawKeyEvent event) {
            if (event is RawKeyDownEvent) {
              _keyDownTime[event.logicalKey] = DateTime.now();

              if (event.logicalKey == LogicalKeyboardKey.space ||
                  event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter) {
                if (_initialized) {
                  if (_controller.value.isPlaying) {
                    _controller.pause();
                  } else {
                    _controller.play();
                  }
                  _showControlsTemporarily();
                }
              } else if (event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack) {
                Navigator.pop(context);
              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                  event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _executeSeek(event.logicalKey);

                // 檢查是否長按
                _isLongPress = true;
                Timer(const Duration(milliseconds: 500), () {
                  if (_keyDownTime.containsKey(event.logicalKey)) {
                    _startContinuousSeek(event.logicalKey);
                  }
                });
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                // 增加播放速度
                if (_playbackSpeed < 2.0) {
                  _playbackSpeed += 0.25;
                  _controller.setPlaybackSpeed(_playbackSpeed);
                  _showControlsTemporarily();
                }
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                // 降低播放速度
                if (_playbackSpeed > 0.25) {
                  _playbackSpeed -= 0.25;
                  _controller.setPlaybackSpeed(_playbackSpeed);
                  _showControlsTemporarily();
                }
              }
            } else if (event is RawKeyUpEvent) {
              _keyDownTime.remove(event.logicalKey);
              _isLongPress = false;
            }
          },
          child: Stack(
            children: [
              // 影片播放器
              if (_initialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                )
              else if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                const Center(
                  child: Text(
                    '無法載入影片',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),

              // 控制層
              if (_showControls) _buildControls(),

              // 推薦影片列表 - 手機版在底部顯示
              if (_showControls) _buildRecommendedVideosForMobile(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    if (!_initialized) return const SizedBox();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withOpacity(0.7),
          ],
        ),
      ),
      child: Column(
        children: [
          // 頂部控制欄
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.isAnime ? Colors.pink : Colors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.isAnime ? '動畫' : '真人',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // 底部控制欄
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 進度條
                VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: widget.isAnime ? Colors.pink : Colors.blue,
                    bufferedColor: Colors.white.withOpacity(0.3),
                    backgroundColor: Colors.white.withOpacity(0.1),
                  ),
                ),
                const SizedBox(height: 16),

                // 主要控制按鈕行
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 後退10秒按鈕
                    IconButton(
                      icon: const Icon(Icons.replay_10,
                          color: Colors.white, size: 28),
                      onPressed: () {
                        final newPosition = _controller.value.position -
                            const Duration(seconds: 10);
                        _controller.seekTo(newPosition < Duration.zero
                            ? Duration.zero
                            : newPosition);
                        _showControlsTemporarily();
                      },
                    ),

                    const SizedBox(width: 16),

                    // 播放/暫停按鈕
                    Container(
                      decoration: BoxDecoration(
                        color: (widget.isAnime ? Colors.pink : Colors.blue)
                            .withOpacity(0.8),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          _controller.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                          size: 40,
                        ),
                        onPressed: () {
                          if (_controller.value.isPlaying) {
                            _controller.pause();
                          } else {
                            _controller.play();
                          }
                          _showControlsTemporarily();
                        },
                      ),
                    ),

                    const SizedBox(width: 16),

                    // 前進10秒按鈕
                    IconButton(
                      icon: const Icon(Icons.forward_10,
                          color: Colors.white, size: 28),
                      onPressed: () {
                        final newPosition = _controller.value.position +
                            const Duration(seconds: 10);
                        final maxPosition = _controller.value.duration;
                        _controller.seekTo(newPosition > maxPosition
                            ? maxPosition
                            : newPosition);
                        _showControlsTemporarily();
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 次要控制行
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 播放速度控制
                    GestureDetector(
                      onTap: () {
                        // 循環播放速度：0.5x -> 0.75x -> 1x -> 1.25x -> 1.5x -> 2x -> 0.5x
                        if (_playbackSpeed >= 2.0) {
                          _playbackSpeed = 0.5;
                        } else if (_playbackSpeed >= 1.5) {
                          _playbackSpeed = 2.0;
                        } else if (_playbackSpeed >= 1.25) {
                          _playbackSpeed = 1.5;
                        } else if (_playbackSpeed >= 1.0) {
                          _playbackSpeed = 1.25;
                        } else if (_playbackSpeed >= 0.75) {
                          _playbackSpeed = 1.0;
                        } else {
                          _playbackSpeed = 0.75;
                        }
                        _controller.setPlaybackSpeed(_playbackSpeed);
                        _showControlsTemporarily();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.speed,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${_playbackSpeed}x',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 時間顯示
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${_formatDuration(_controller.value.position)} / ${_formatDuration(_controller.value.duration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),

                    // 全螢幕按鈕
                    IconButton(
                      icon: Icon(
                        _isFullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () {
                        setState(() {
                          _isFullscreen = !_isFullscreen;
                        });
                        _showControlsTemporarily();
                        // 這裡可以添加實際的全螢幕切換邏輯
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedVideos() {
    return Positioned(
      right: 16,
      top: 100,
      bottom: 100,
      width: 300,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '推薦影片',
                style: TextStyle(
                  color: widget.isAnime ? Colors.pink : Colors.blue,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _recommendedVideos.length,
                itemBuilder: (context, index) {
                  final video = _recommendedVideos[index];
                  return _buildRecommendedVideoItem(video);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendedVideoItem(Map<String, dynamic> video) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: InkWell(
        onTap: () => _playRecommendedVideo(video),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 縮圖
              Container(
                width: 80,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade800,
                ),
                child: video['img_url']?.isNotEmpty == true
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          video['img_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.video_library,
                              color: Colors.white54,
                              size: 24,
                            );
                          },
                        ),
                      )
                    : const Icon(
                        Icons.video_library,
                        color: Colors.white54,
                        size: 24,
                      ),
              ),
              const SizedBox(width: 12),

              // 標題
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video['title'] ?? '未知標題',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${video['id'] ?? 'N/A'}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _playRecommendedVideo(Map<String, dynamic> video) {
    // 實現推薦影片播放邏輯
    print('播放推薦影片: ${video['title']}');
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _continuousSeekTimer?.cancel();
    _controller.dispose();
    _playerFocusNode.dispose();
    super.dispose();
  }

  // 手機版推薦影片列表 - 底部橫向滾動
  Widget _buildRecommendedVideosForMobile() {
    // 如果沒有推薦影片，顯示示例數據
    if (_recommendedVideos.isEmpty) {
      _recommendedVideos = [
        {
          'id': 'rec001',
          'title': '推薦影片 1',
          'img_url': '',
          'detail_url': '',
        },
        {
          'id': 'rec002',
          'title': '推薦影片 2',
          'img_url': '',
          'detail_url': '',
        },
        {
          'id': 'rec003',
          'title': '推薦影片 3',
          'img_url': '',
          'detail_url': '',
        },
      ];
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 120, // 在控制欄上方
      height: 120,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withOpacity(0.3),
              Colors.black.withOpacity(0.6),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                '推薦影片',
                style: TextStyle(
                  color: widget.isAnime ? Colors.pink : Colors.blue,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _recommendedVideos.length,
                itemBuilder: (context, index) {
                  final video = _recommendedVideos[index];
                  return _buildMobileRecommendedVideoItem(video);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 手機版推薦影片項目
  Widget _buildMobileRecommendedVideoItem(Map<String, dynamic> video) {
    return Container(
      width: 140,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: InkWell(
        onTap: () => _playRecommendedVideo(video),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          children: [
            // 縮圖
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                  color: Colors.grey.shade800,
                ),
                child: video['img_url']?.isNotEmpty == true
                    ? ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8)),
                        child: Image.network(
                          video['img_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.video_library,
                                color: Colors.white54,
                                size: 32,
                              ),
                            );
                          },
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.video_library,
                          color: Colors.white54,
                          size: 32,
                        ),
                      ),
              ),
            ),

            // 標題
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  video['title'] ?? '未知標題',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 影片詳細對話框
class VideoDetailDialog extends StatefulWidget {
  final Map<String, dynamic> video;
  final bool isAnime;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onPlay;

  const VideoDetailDialog({
    super.key,
    required this.video,
    required this.isAnime,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onPlay,
  });

  @override
  State<VideoDetailDialog> createState() => _VideoDetailDialogState();
}

class _VideoDetailDialogState extends State<VideoDetailDialog> {
  final FocusNode _favoriteFocusNode = FocusNode();
  final FocusNode _playFocusNode = FocusNode();
  final FocusNode _closeFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 自動聚焦到播放按鈕
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _favoriteFocusNode.dispose();
    _playFocusNode.dispose();
    _closeFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 600,
        height: 500,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        ),
        child: Column(
          children: [
            // 圖片區域
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.video['img_url']?.isNotEmpty == true)
                      Image.network(
                        widget.video['img_url'],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey.shade800,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    widget.isAnime
                                        ? Icons.animation
                                        : Icons.video_library,
                                    size: 64,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.isAnime ? '動畫影片' : '真人影片',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    else
                      Container(
                        color: Colors.grey.shade800,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                widget.isAnime
                                    ? Icons.animation
                                    : Icons.video_library,
                                size: 64,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.isAnime ? '動畫影片' : '真人影片',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // 類型標籤
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: widget.isAnime ? Colors.pink : Colors.blue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.isAnime ? '動畫' : '真人',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    // 關閉按鈕
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Focus(
                        focusNode: _closeFocusNode,
                        onKey: (node, event) {
                          if (event is RawKeyDownEvent) {
                            if (event.logicalKey == LogicalKeyboardKey.select ||
                                event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey == LogicalKeyboardKey.space) {
                              Navigator.of(context).pop();
                              HapticFeedback.selectionClick();
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(
                          builder: (context) {
                            final hasFocus = Focus.of(context).hasFocus;
                            return InkWell(
                              onTap: () => Navigator.of(context).pop(),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: hasFocus
                                      ? Colors.white.withOpacity(0.3)
                                      : Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                  border: hasFocus
                                      ? Border.all(
                                          color: Colors.white, width: 2)
                                      : null,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 詳細信息區域
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 標題
                    Text(
                      widget.video['title'] ?? '未知標題',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // 影片ID
                    Text(
                      '影片 ID: ${widget.video['id'] ?? 'N/A'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    // 按鈕區域
                    Row(
                      children: [
                        // 收藏按鈕
                        Expanded(
                          child: Focus(
                            focusNode: _favoriteFocusNode,
                            onKey: (node, event) {
                              if (event is RawKeyDownEvent) {
                                if (event.logicalKey ==
                                        LogicalKeyboardKey.select ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.enter ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.space) {
                                  widget.onToggleFavorite();
                                  HapticFeedback.selectionClick();
                                  setState(() {}); // 更新收藏狀態顯示
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (context) {
                                final hasFocus = Focus.of(context).hasFocus;
                                return InkWell(
                                  onTap: () {
                                    widget.onToggleFavorite();
                                    setState(() {}); // 更新收藏狀態顯示
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    decoration: BoxDecoration(
                                      color: hasFocus
                                          ? Colors.white.withOpacity(0.2)
                                          : Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: hasFocus
                                          ? Border.all(
                                              color: Colors.white, width: 2)
                                          : Border.all(
                                              color:
                                                  Colors.white.withOpacity(0.3),
                                              width: 1),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          widget.isFavorite
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                          color: widget.isFavorite
                                              ? Colors.red
                                              : Colors.white,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          widget.isFavorite ? '取消收藏' : '加入收藏',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 播放按鈕
                        Expanded(
                          flex: 2,
                          child: Focus(
                            focusNode: _playFocusNode,
                            autofocus: true,
                            onKey: (node, event) {
                              if (event is RawKeyDownEvent) {
                                if (event.logicalKey ==
                                        LogicalKeyboardKey.select ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.enter ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.space) {
                                  Navigator.of(context).pop();
                                  widget.onPlay();
                                  HapticFeedback.selectionClick();
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (context) {
                                final hasFocus = Focus.of(context).hasFocus;
                                return InkWell(
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    widget.onPlay();
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    decoration: BoxDecoration(
                                      color: hasFocus
                                          ? (widget.isAnime
                                              ? Colors.pink
                                              : Colors.blue)
                                          : (widget.isAnime
                                              ? Colors.pink.withOpacity(0.7)
                                              : Colors.blue.withOpacity(0.7)),
                                      borderRadius: BorderRadius.circular(8),
                                      border: hasFocus
                                          ? Border.all(
                                              color: Colors.white, width: 2)
                                          : null,
                                    ),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          '立即播放',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
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
    );
  }
}
