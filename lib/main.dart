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
import 'core/constants/app_constants.dart';

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

  // 檢查 Firebase 是否已經初始化，避免重複初始化
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase 初始化成功');
  } catch (e) {
    // Firebase 初始化失敗，使用本地數據
    print('⚠️ Firebase初始化失敗，將使用本地測試數據: $e');
  }

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
  DatabaseReference? _dbRef;
  DatabaseReference? _animeDbRef;
  DatabaseReference? _favoritesDbRef;
  bool _isFirebaseAvailable = false;
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
    _initializeFirebaseReferences();
    _showAppVersionToast();
    _initializeWebView();
    _loadTestData(); // 載入測試數據
    // 初始化選單 FocusNode
    _menuFocusNodes = List.generate(5, (_) => FocusNode()); // 調整為5個選單項目
  }

  void _initializeFirebaseReferences() {
    try {
      _dbRef = FirebaseDatabase.instance.ref().child('videos');
      _animeDbRef = FirebaseDatabase.instance.ref().child('anime_videos');
      _favoritesDbRef = FirebaseDatabase.instance.ref().child('favorites');
      _isFirebaseAvailable = true;
      print('✅ Firebase 數據庫引用初始化成功');
      _loadFavoriteVideos(); // 載入Firebase數據
    } catch (e) {
      print('⚠️ Firebase 數據庫不可用，使用本地測試數據: $e');
      _isFirebaseAvailable = false;
    }
  }

  void _loadTestData() {
    // 移除測試數據，確保僅使用雲端數據
    if (!_isFirebaseAvailable) {
      print('⚠️ Firebase不可用，無法載入影片清單');
      setState(() {
        _items = [];
        _favoriteItems = [];
      });
    }
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
        // 使用固定的 GitHub APK 下載連結
        final apkUrl = AppConstants.apkDownloadUrl;
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

    if (_isFirebaseAvailable && _dbRef != null && _animeDbRef != null) {
      _realCrawler = RealCrawler(
        webViewController: _webViewController,
        dbRef: _dbRef!,
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
        dbRef: _animeDbRef!,
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
    } else {
      print('⚠️ Firebase不可用，爬蟲功能將被禁用');
    }
  }

  Future<void> _loadFavoriteVideos() async {
    if (!_isFirebaseAvailable || _favoritesDbRef == null) {
      print('⚠️ Firebase不可用，使用本地收藏數據');
      return;
    }
    
    // 顯示全螢幕 loading 動畫
    setState(() {
      _isShowingLoadingTransition = true;
      _loadingMessage = '正在載入收藏影片列表...';
    });

    final snapshot = await _favoritesDbRef!.get();
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
    if (!_isFirebaseAvailable || _dbRef == null || _animeDbRef == null) {
      print('⚠️ Firebase不可用，無法載入影片列表');
      setState(() {
        _items = [];
      });
      return;
    }
    
    setState(() {
      _isShowingLoadingTransition = true;
      _loadingMessage = '正在載入影片列表...';
    });

    // 同時載入真人影片和動畫影片
    final realSnapshot = await _dbRef!.get();
    final animeSnapshot = await _animeDbRef!.get();

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
    if (!_isFirebaseAvailable || _dbRef == null) {
      print('⚠️ Firebase不可用，無法載入真人影片');
      return;
    }
    
    setState(() {
      _isShowingLoadingTransition = true;
      _loadingMessage = '正在載入真人影片列表...';
    });

    final realSnapshot = await _dbRef!.get();
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
    if (!_isFirebaseAvailable || _animeDbRef == null) {
      print('⚠️ Firebase不可用，無法載入動畫影片');
      return;
    }
    
    setState(() {
      _isShowingLoadingTransition = true;
      _loadingMessage = '正在載入動畫影片列表...';
    });

    final animeSnapshot = await _animeDbRef!.get();
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
        if (_isFirebaseAvailable && _favoritesDbRef != null) {
          await _favoritesDbRef!.child(videoId).remove();
        }
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
        if (_isFirebaseAvailable && _favoritesDbRef != null) {
          await _favoritesDbRef!.child(videoId).set(video);
        }
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
        // 導覽到播放器頁面（統一處理，不需要分別判斷影片類型）
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              title: video['title'] as String,
              url: playUrl!, // 使用非空斷言，因為已經檢查過不為null
              isAnime: isAnime,
            ),
          ),
        );
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 響應式設計：根據螢幕寬度決定列數
          int crossAxisCount;
          double childAspectRatio;

          // 檢查當前列表是否為動畫內容
          bool isAnimeContent =
              _items.isNotEmpty && _isAnimeVideo(_items.first);

          if (constraints.maxWidth > 1200) {
            // 大螢幕 (TV/桌面)
            crossAxisCount = 4;
            // 動畫直向封面需要更高的容器，真人橫向縮圖需要更寬的容器
            childAspectRatio = isAnimeContent ? 0.5 : 1.2;
          } else if (constraints.maxWidth > 800) {
            // 平板
            crossAxisCount = 3;
            childAspectRatio = isAnimeContent ? 0.55 : 1.1;
          } else if (constraints.maxWidth > 600) {
            // 大手機橫向
            crossAxisCount = 2;
            childAspectRatio = isAnimeContent ? 0.6 : 1.0;
          } else {
            // 手機直向
            crossAxisCount = 2;
            childAspectRatio = isAnimeContent ? 0.65 : 0.95;
          }

          return GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: crossAxisCount == 1 ? 0 : 6, // 減少間距
              mainAxisSpacing: 8, // 減少主軸間距
              childAspectRatio: childAspectRatio,
            ),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              final isAnime = _isAnimeVideo(item);

              return _buildVideoCard(item, isAnime, theme);
            },
          );
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
                      // 圖片區域 - 根據內容類型調整比例
                      Expanded(
                        flex: isAnime ? 4 : 2, // 動畫需要更大圖片區域，真人影片橫向圖片可以較小
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
                                _buildDynamicImage(
                                    item['img_url'], isAnime, theme)
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
                              // 移除 ID 顯示，僅保留焦點圖示
                              if (hasFocus)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Icon(
                                    Icons.touch_app,
                                    size: 16,
                                    color: (isAnime
                                            ? theme.colorScheme.secondary
                                            : theme.colorScheme.primary)
                                        .withOpacity(0.7),
                                  ),
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

  // 建構動態比例圖片 - 根據內容類型優化顯示
  Widget _buildDynamicImage(String imageUrl, bool isAnime, ThemeData theme) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: FutureBuilder<ImageInfo>(
        future: _getImageInfo(imageUrl),
        builder: (context, snapshot) {
          // 根據內容類型設置不同的預設填滿策略
          BoxFit imageFit = BoxFit.cover;

          if (snapshot.hasData && snapshot.data != null) {
            final imageInfo = snapshot.data!;
            final imageWidth = imageInfo.image.width.toDouble();
            final imageHeight = imageInfo.image.height.toDouble();
            final imageAspectRatio = imageWidth / imageHeight;

            if (isAnime) {
              // 動畫內容 - 通常是直向封面
              if (imageAspectRatio < 1.0) {
                // 直向圖片：填滿整個容器
                imageFit = BoxFit.cover;
              } else {
                // 橫向圖片：保持完整顯示，避免裁切
                imageFit = BoxFit.contain;
              }
            } else {
              // 真人影片 - 通常是橫向縮圖
              if (imageAspectRatio > 1.0) {
                // 橫向圖片：保持完整顯示，避免裁切
                imageFit = BoxFit.contain;
              } else {
                // 直向圖片：填滿整個容器
                imageFit = BoxFit.cover;
              }
            }
          }

          if (snapshot.hasData && snapshot.data != null) {
            return Image.network(
              imageUrl,
              width: double.infinity,
              height: double.infinity,
              fit: imageFit,
              errorBuilder: (context, error, stackTrace) {
                return _buildPlaceholderImage(isAnime, theme);
              },
            );
          } else if (snapshot.hasError) {
            return _buildPlaceholderImage(isAnime, theme);
          } else {
            // 載入中顯示佔位符
            return Container(
              width: double.infinity,
              height: double.infinity,
              color: theme.colorScheme.surface.withOpacity(0.3),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary.withOpacity(0.5),
                  ),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  // 獲取圖片信息
  Future<ImageInfo> _getImageInfo(String imageUrl) async {
    final imageProvider = NetworkImage(imageUrl);
    final stream = imageProvider.resolve(const ImageConfiguration());
    final completer = Completer<ImageInfo>();

    final listener = ImageStreamListener((ImageInfo info, bool _) {
      if (!completer.isCompleted) {
        completer.complete(info);
      }
    }, onError: (dynamic exception, StackTrace? stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(exception, stackTrace);
      }
    });

    stream.addListener(listener);

    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } finally {
      stream.removeListener(listener);
    }
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
  bool _isFullscreen = true; // 預設全螢幕
  final FocusNode _playerFocusNode = FocusNode();
  Timer? _continuousSeekTimer;
  bool _isLongPress = false;
  Map<LogicalKeyboardKey, DateTime> _keyDownTime = {};
  bool _isLoadingRecommendations = false;

  // Firebase 參考
  DatabaseReference? _dbRef;
  DatabaseReference? _animeDbRef;
  bool _isFirebaseAvailable = false;

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
    _initializePlayer();
    _initializeWebView();
    _hideControlsAfterDelay();
    // 修改：無論是手機版還是TV版都載入推薦影片
    _loadRecommendedVideos();
  }

  void _initializeFirebase() {
    try {
      _dbRef = FirebaseDatabase.instance.ref('videos');
      _animeDbRef = FirebaseDatabase.instance.ref('anime_videos');
      _isFirebaseAvailable = true;
      print('✅ 播放器Firebase初始化成功');
    } catch (e) {
      print('⚠️ 播放器Firebase不可用: $e');
      _isFirebaseAvailable = false;
    }
  }

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
  }

  Future<void> _loadRecommendedVideos() async {
    setState(() {
      _isLoadingRecommendations = true;
    });

    if (!_isFirebaseAvailable) {
      print('⚠️ Firebase不可用，無法載入推薦影片');
      setState(() {
        _recommendedVideos = [];
        _isLoadingRecommendations = false;
      });
      return;
    }

    try {
      if (widget.isAnime) {
        // 動畫影片：載入隨機推薦
        await _loadRandomAnimeRecommendations();
      } else {
        // 真人影片：載入女優作品推薦
        await _loadActressRecommendations();
      }
    } catch (e) {
      print('載入推薦影片失敗: $e');
      setState(() {
        _isLoadingRecommendations = false;
      });
    }
  }

  // 載入女優作品推薦
  Future<void> _loadActressRecommendations() async {
    try {
      // 從當前影片URL獲取女優資訊
      final actressVideos = await _getActressVideos(widget.url);

      if (actressVideos.isNotEmpty) {
        setState(() {
          _recommendedVideos = actressVideos;
          _isLoadingRecommendations = false;
        });
      } else {
        // 如果沒有女優作品，回退到隨機推薦
        await _loadRandomRealRecommendations();
      }
    } catch (e) {
      print('載入女優作品推薦失敗: $e');
      // 回退到隨機推薦
      await _loadRandomRealRecommendations();
    }
  }

  // 從當前影片URL獲取女優作品列表
  Future<List<Map<String, dynamic>>> _getActressVideos(
      String currentVideoUrl) async {
    try {
      print('🎯 開始女優推薦流程...');
      print('📺 當前影片: ${widget.title}');
      
      // 首先需要從當前播放的影片標題或URL找到對應的詳細頁面URL
      String? detailUrl = await _findVideoDetailUrl(widget.title);

      if (detailUrl == null) {
        print('❌ 找不到影片詳細頁面URL，使用當前播放URL');
        detailUrl = widget.url; // 嘗試使用當前播放的URL
        
        // 檢查URL是否看起來像是詳細頁面URL
        if (!detailUrl.contains('/videos/') && !detailUrl.contains('/watch/')) {
          print('❌ 當前URL不是影片詳細頁面，放棄女優推薦');
          return [];
        }
      }

      print('📄 載入影片詳細頁面: $detailUrl');

      // 載入影片詳細頁面
      await _webViewController.loadRequest(Uri.parse(detailUrl));
      await Future.delayed(const Duration(seconds: 4)); // 增加等待時間

      // 提取女優連結
      print('🔍 正在尋找女優連結...');
      final actressUrl = await _extractActressUrl();
      if (actressUrl == null) {
        print('❌ 無法找到女優連結，可能是無女優影片或頁面結構改變');
        return [];
      }

      print('🎭 成功找到女優頁面，準備載入作品列表...');

      // 載入女優作品列表頁面
      await _webViewController.loadRequest(Uri.parse(actressUrl));
      print('⏱️ 等待女優頁面載入完成...');

      // 提取女優作品列表
      print('📋 開始抓取女優作品清單...');
      final actressVideos = await _extractActressVideos();
      
      if (actressVideos.isNotEmpty) {
        print('🎉 女優推薦流程完成！獲得 ${actressVideos.length} 個推薦影片');
      } else {
        print('⚠️ 沒有抓取到女優作品，將使用隨機推薦');
      }
      
      return actressVideos;
    } catch (e) {
      print('❌ 獲取女優作品過程中發生異常: $e');
      return [];
    }
  }

  // 從Firebase中找到對應的影片詳細頁面URL
  Future<String?> _findVideoDetailUrl(String title) async {
    if (!_isFirebaseAvailable || _dbRef == null) {
      print('⚠️ Firebase不可用，無法查找影片詳細URL');
      return null;
    }
    
    try {
      final realSnapshot = await _dbRef!.get();
      if (realSnapshot.exists) {
        final data = realSnapshot.value;
        List<Map<String, dynamic>> videos = [];

        if (data is List) {
          videos = data
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
        } else if (data is Map) {
          videos = (data)
              .values
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        // 尋找匹配的影片
        for (final video in videos) {
          if (video['title'] == title) {
            return video['detail_url'];
          }
        }
      }
    } catch (e) {
      print('查找影片詳細URL失敗: $e');
    }
    return null;
  }

  // 提取女優連結
  Future<String?> _extractActressUrl() async {
    try {
      final result = await _webViewController.runJavaScriptReturningResult('''
        (function() {
          try {
            console.log('🔍 開始搜尋女優連結...');
            
            // 方法1: 使用精確的XPath路徑
            console.log('📍 使用XPath: /html/body/div[3]/div/div/div[1]/section[2]/div[1]/div[1]/h6/div/a');
            
            try {
              const xpath = '/html/body/div[3]/div/div/div[1]/section[2]/div[1]/div[1]/h6/div/a';
              const result = document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
              const actressLink = result.singleNodeValue;
              
              if (actressLink && actressLink.href) {
                const href = actressLink.href.toString();
                const name = (actressLink.innerText || actressLink.textContent || '未知女優').toString();
                console.log('✅ 找到女優連結 (XPath):', href);
                console.log('🎭 女優名稱:', name);
                return '{"success":true,"url":"' + href + '","name":"' + name + '","method":"xpath"}';
              }
            } catch (xpathError) {
              console.log('XPath 執行失敗:', xpathError);
            }
            
            // 方法2: 備用CSS選擇器搜尋
            console.log('🔄 XPath方法失敗，嘗試CSS選擇器...');
            try {
              const actressLinks = document.querySelectorAll('h6 div a, .actress-name a, [href*="/models/"]');
              for (let i = 0; i < actressLinks.length; i++) {
                const link = actressLinks[i];
                if (link && link.href && link.href.includes('/models/')) {
                  const href = link.href.toString();
                  const name = (link.innerText || link.textContent || '未知女優').toString();
                  console.log('✅ 找到女優連結 (CSS):', href);
                  console.log('🎭 女優名稱:', name);
                  return '{"success":true,"url":"' + href + '","name":"' + name + '","method":"css"}';
                }
              }
            } catch (cssError) {
              console.log('CSS 選擇器執行失敗:', cssError);
            }
            
            // 方法3: 通用搜尋所有包含 models 的連結
            console.log('🔄 CSS方法失敗，進行通用搜尋...');
            try {
              const allLinks = document.querySelectorAll('a[href*="/models/"]');
              if (allLinks.length > 0) {
                const link = allLinks[0];
                const href = link.href.toString();
                const name = (link.innerText || link.textContent || '未知女優').toString();
                console.log('✅ 找到女優連結 (通用):', href);
                console.log('🎭 女優名稱:', name);
                return '{"success":true,"url":"' + href + '","name":"' + name + '","method":"general"}';
              }
            } catch (generalError) {
              console.log('通用搜尋執行失敗:', generalError);
            }
            
            console.log('❌ 沒有找到女優連結');
            console.log('📄 頁面HTML摘要:', document.title);
            return '{"success":false,"error":"未找到女優連結"}';
            
          } catch (error) {
            console.log('❌ 整體執行失敗:', error);
            return '{"success":false,"error":"JavaScript執行異常"}';
          }
        })();
      ''');

      print('🔍 JavaScript返回結果: $result');
      print('🔍 結果類型: ${result.runtimeType}');
      
      // 安全解析JSON結果
      final Map<String, dynamic> data;
      try {
        String resultString = result.toString();
        data = jsonDecode(resultString);
      } catch (parseError) {
        print('❌ JSON解析失敗: $parseError');
        print('🐛 原始結果: $result');
        return null;
      }
      
      if (data['success'] == true) {
        final actressUrl = data['url']?.toString() ?? '';
        final actressName = data['name']?.toString() ?? '未知女優';
        final method = data['method']?.toString() ?? 'unknown';
        print('🎯 成功找到女優: $actressName');
        print('🔗 女優頁面: $actressUrl');
        print('📋 抓取方法: $method');
        return actressUrl;
      } else {
        print('❌ 抓取失敗: ${data['error'] ?? '未知錯誤'}');
      }
    } catch (e) {
      print('❌ 提取女優連結時發生異常: $e');
    }
    return null;
  }

  // 提取女優作品列表
  Future<List<Map<String, dynamic>>> _extractActressVideos() async {
    try {
      // 等待頁面完全加載
      await Future.delayed(const Duration(seconds: 4));
      
      final result = await _webViewController.runJavaScriptReturningResult('''
        (function() {
          console.log('🎬 開始抓取女優作品列表...');
          console.log('📄 當前頁面:', window.location.href);
          console.log('📝 頁面標題:', document.title);
          
          const videos = [];
          let foundCount = 0;
          
          // 方法1: 使用 .video-img-box 選擇器 (主要方法)
          console.log('🔍 方法1: 搜尋 .video-img-box 元素...');
          const videoElements1 = Array.from(document.querySelectorAll('.video-img-box'));
          console.log('📊 找到', videoElements1.length, '個 .video-img-box 元素');
          
          for (let i = 0; i < Math.min(videoElements1.length, 20); i++) {
            const element = videoElements1[i];
            const titleElement = element.querySelector('.detail .title a, .title a, a[title]');
            const imgElement = element.querySelector('img');
            
            if (titleElement) {
              const video = {
                id: 'actress_rec_' + Date.now() + '_' + foundCount,
                title: (titleElement.innerText || titleElement.textContent || titleElement.getAttribute('title') || '未知標題').trim(),
                detail_url: titleElement.href || '',
                img_url: imgElement?.getAttribute('data-src') || imgElement?.getAttribute('src') || imgElement?.dataset?.src || '',
                type: 'real',
                source: 'actress_recommendation'
              };
              
              if (video.title && video.detail_url) {
                videos.push(video);
                foundCount++;
                console.log('✅ 影片', foundCount, ':', video.title);
              }
            }
          }
          
          // 方法2: 如果第一種方法沒找到足夠影片，嘗試其他選擇器
          if (videos.length < 5) {
            console.log('🔍 方法2: 搜尋其他影片元素...');
            const videoElements2 = Array.from(document.querySelectorAll('.thumb, .video-block, .item, [class*="video"]'));
            console.log('📊 找到', videoElements2.length, '個其他影片元素');
            
            for (let i = 0; i < Math.min(videoElements2.length, 20 - videos.length); i++) {
              const element = videoElements2[i];
              const titleElement = element.querySelector('a[title], .title a, h3 a, h4 a, .video-title a');
              const imgElement = element.querySelector('img');
              
              if (titleElement && !videos.some(v => v.detail_url === titleElement.href)) {
                const video = {
                  id: 'actress_rec_alt_' + Date.now() + '_' + foundCount,
                  title: (titleElement.innerText || titleElement.textContent || titleElement.getAttribute('title') || '未知標題').trim(),
                  detail_url: titleElement.href || '',
                  img_url: imgElement?.getAttribute('data-src') || imgElement?.getAttribute('src') || '',
                  type: 'real',
                  source: 'actress_recommendation_alt'
                };
                
                if (video.title && video.detail_url) {
                  videos.push(video);
                  foundCount++;
                  console.log('✅ 補充影片', foundCount, ':', video.title);
                }
              }
            }
          }
          
          console.log('🎯 總共成功抓取', videos.length, '個女優作品');
          
          // 確保最多20個影片
          const finalVideos = videos.slice(0, 20);
          
          return JSON.stringify({ 
            success: true, 
            videos: finalVideos,
            total: finalVideos.length,
            pageUrl: window.location.href,
            pageTitle: document.title
          });
        })();
      ''');

      final data = jsonDecode(result.toString());
      if (data['success'] == true) {
        List<dynamic> videos = data['videos'];
        final total = data['total'] ?? videos.length;
        final pageUrl = data['pageUrl'] ?? '';
        final pageTitle = data['pageTitle'] ?? '';
        
        print('🎉 女優作品抓取成功!');
        print('📊 總數: $total 個影片');
        print('📄 來源頁面: $pageTitle');
        print('🔗 頁面URL: $pageUrl');
        
        final videoList = videos.map((v) => Map<String, dynamic>.from(v)).toList();
        
        // 記錄前幾個影片的標題以便調試
        for (int i = 0; i < math.min(3, videoList.length); i++) {
          print('🎬 影片 ${i+1}: ${videoList[i]['title']}');
        }
        
        return videoList;
      } else {
        print('❌ 女優作品抓取失敗');
      }
    } catch (e) {
      print('❌ 提取女優作品列表時發生異常: $e');
    }
    return [];
  }

  // 載入隨機真人影片推薦（僅使用雲端數據）
  Future<void> _loadRandomRealRecommendations() async {
    if (!_isFirebaseAvailable || _dbRef == null) {
      print('⚠️ Firebase不可用，無法載入推薦影片');
      setState(() {
        _recommendedVideos = [];
        _isLoadingRecommendations = false;
      });
      return;
    }
    
    try {
      final realSnapshot = await _dbRef!.get();
      List<Map<String, dynamic>> allVideos = [];

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

      // 過濾掉目前播放的影片，隨機選取推薦影片
      allVideos.removeWhere((video) => video['title'] == widget.title);
      allVideos.shuffle();

      setState(() {
        _recommendedVideos = allVideos.take(20).toList();
        _isLoadingRecommendations = false;
      });
    } catch (e) {
      print('載入隨機真人影片推薦失敗: $e');
      setState(() {
        _isLoadingRecommendations = false;
      });
    }
  }

  // 載入隨機動畫推薦（僅使用雲端數據）
  Future<void> _loadRandomAnimeRecommendations() async {
    if (!_isFirebaseAvailable || _animeDbRef == null) {
      print('⚠️ Firebase不可用，無法載入動畫推薦');
      setState(() {
        _recommendedVideos = [];
        _isLoadingRecommendations = false;
      });
      return;
    }
    
    try {
      final animeSnapshot = await _animeDbRef!.get();
      List<Map<String, dynamic>> allVideos = [];

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

      // 過濾掉目前播放的影片，隨機選取推薦影片
      allVideos.removeWhere((video) => video['title'] == widget.title);
      allVideos.shuffle();

      setState(() {
        _recommendedVideos = allVideos.take(20).toList();
        _isLoadingRecommendations = false;
      });
    } catch (e) {
      print('載入隨機動畫推薦失敗: $e');
      setState(() {
        _isLoadingRecommendations = false;
      });
    }
  }

  void _initializePlayer() async {
    try {
      print('🎬 開始初始化播放器...');
      print('🔗 播放URL: ${widget.url}');
      print('📺 影片標題: ${widget.title}');
      print('🎭 是否為動畫: ${widget.isAnime}');
      
      // 檢查URL是否有效
      if (widget.url.isEmpty) {
        throw Exception('播放URL為空');
      }
      
      final uri = Uri.parse(widget.url);
      print('📋 解析後的URI: $uri');
      
      _controller = VideoPlayerController.networkUrl(uri);
      await _controller.initialize();
      
      if (mounted) {
        setState(() {
          _initialized = true;
          _isLoading = false;
        });
        await _controller.setPlaybackSpeed(_playbackSpeed);
        await _controller.play();
        print('✅ 播放器初始化成功並開始播放');
      }
    } catch (e) {
      print('❌ 播放器初始化失敗: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放器初始化失敗: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
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

  void _seekBackward10() {
    final newPosition =
        _controller.value.position - const Duration(seconds: 10);
    _controller
        .seekTo(newPosition < Duration.zero ? Duration.zero : newPosition);
    _showControlsTemporarily();
  }

  void _seekForward10() {
    final newPosition =
        _controller.value.position + const Duration(seconds: 10);
    final duration = _controller.value.duration;
    _controller.seekTo(newPosition > duration ? duration : newPosition);
    _showControlsTemporarily();
  }

  void _startContinuousSeek(bool forward) {
    _isLongPress = true;
    _continuousSeekTimer?.cancel();
    _continuousSeekTimer =
        Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_isLongPress) {
        if (forward) {
          _seekForward10();
        } else {
          _seekBackward10();
        }
      } else {
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.shortestSide < 600;

    return Scaffold(
      backgroundColor: Colors.black,
      body: RawKeyboardListener(
        focusNode: _playerFocusNode,
        autofocus: true,
        onKey: (RawKeyEvent event) {
          if (event is RawKeyDownEvent) {
            _keyDownTime[event.logicalKey] = DateTime.now();
            if (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.goBack) {
              Navigator.pop(context);
            } else if (event.logicalKey == LogicalKeyboardKey.space ||
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
            } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              if (!_isLongPress) {
                _seekBackward10();
              }
              _startContinuousSeek(false);
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              if (!_isLongPress) {
                _seekForward10();
              }
              _startContinuousSeek(true);
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
        child: isMobile ? _buildMobilePlayer() : _buildTVLayoutPlayer(),
      ),
    );
  }

  // 檢測是否為手機裝置
  bool _isMobile() {
    final data = MediaQuery.of(context);
    return data.size.shortestSide < 600;
  }

  // 手機版播放器（支援全螢幕和推薦模式）
  Widget _buildMobilePlayer() {
    return Stack(
      children: [
        // 主要播放區域
        GestureDetector(
          onTap: () {
            setState(() {
              _showControls = !_showControls;
            });
            if (_showControls) {
              _hideControlsAfterDelay();
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
              if (_showControls) _buildMobileControls(),
            ],
          ),
        ),

        // 推薦影片區域（在暫停狀態下顯示在最下方）
        if (_initialized && !_controller.value.isPlaying && _recommendedVideos.isNotEmpty)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildPausedRecommendedVideos(),
          ),
      ],
    );
  }

  // 暫停狀態下的推薦影片區域
  Widget _buildPausedRecommendedVideos() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.8),
            Colors.black.withOpacity(0.95),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題區域
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.queue_play_next,
                  color: widget.isAnime ? Colors.pink : Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isAnime ? '推薦動畫' : '推薦影片',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_isLoadingRecommendations)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.isAnime ? Colors.pink : Colors.blue,
                    ),
                  ),
              ],
            ),
          ),

          // 橫向滾動的推薦影片列表
          Expanded(
            child: _isLoadingRecommendations
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _recommendedVideos.length > 20 ? 20 : _recommendedVideos.length,
                    itemBuilder: (context, index) {
                      final video = _recommendedVideos[index];
                      return _buildHorizontalRecommendedVideoCard(video, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // 橫向推薦影片卡片（五個半寬度）
  Widget _buildHorizontalRecommendedVideoCard(Map<String, dynamic> video, int index) {
    final screenWidth = MediaQuery.of(context).size.width;
    // 計算卡片寬度：螢幕寬度除以5.5，再減去間距
    final cardWidth = (screenWidth - 24 - (4 * 8)) / 5.5; // 24是左右padding，4*8是卡片間距
    
    final isAnimeVideo =
        video['detail_url']?.toString().contains('hanime1.me') ?? false;

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: InkWell(
        onTap: () => _playRecommendedVideo(video),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 縮圖區域
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                  color: Colors.grey.shade800,
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(8)),
                      child: video['img_url']?.isNotEmpty == true
                          ? Image.network(
                              video['img_url'],
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildPlaceholderThumbnail(isAnimeVideo);
                              },
                            )
                          : _buildPlaceholderThumbnail(isAnimeVideo),
                    ),

                    // 播放圖示覆蓋
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8)),
                          color: Colors.black.withOpacity(0.4),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),

                    // 類型標籤
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: isAnimeVideo ? Colors.pink : Colors.blue,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          isAnimeVideo ? '動畫' : '真人',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    // 編號標籤 (顯示在左上角)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 標題區域
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  video['title'] ?? '未知標題',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderThumbnail(bool isAnime) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey.shade800,
            Colors.grey.shade900,
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isAnime ? Icons.animation : Icons.video_library,
              size: 24,
              color: Colors.white.withOpacity(0.5),
            ),
            const SizedBox(height: 4),
            Text(
              isAnime ? '動畫' : '真人',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _playRecommendedVideo(Map<String, dynamic> video) async {
    try {
      final detailUrl = video['detail_url'] as String?;
      if (detailUrl == null || detailUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('沒有找到影片詳細頁面')),
        );
        return;
      }

      // 顯示載入指示器
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // 載入影片詳細頁面
      await _webViewController.loadRequest(Uri.parse(detailUrl));
      await Future.delayed(const Duration(seconds: 5)); // 增加等待時間

      String? playUrl;
      bool isAnime = detailUrl.contains('hanime1.me');

      // 根據影片類型使用對應的爬蟲提取播放網址
      if (isAnime) {
        // 使用 AnimeCrawler 邏輯提取播放網址
        playUrl = await _extractAnimePlayUrl();
      } else {
        // 使用 RealCrawler 邏輯提取播放網址
        playUrl = await _extractRealPlayUrl();
      }

      // 關閉載入指示器
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (playUrl != null && playUrl.isNotEmpty && mounted) {
        final String finalPlayUrl = playUrl!; // 確保 playUrl 不是 null，使用非空斷言
        print('🎯 成功提取播放URL: $finalPlayUrl');
        print('🚀 準備導航到播放器頁面...');
        
        // 導覽到新的播放器頁面
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              title: video['title'] as String? ?? '未知標題',
              url: finalPlayUrl,
              isAnime: isAnime,
            ),
          ),
        );
      } else if (mounted) {
        // 如果無法提取播放網址，詢問是否在外部瀏覽器開啟
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('無法自動播放'),
              content: const Text('無法自動提取播放地址。\n\n是否要在外部瀏覽器開啟頁面？'),
              actions: <Widget>[
                TextButton(
                  child: const Text('取消'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: const Text('開啟瀏覽器'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    final uri = Uri.parse(detailUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // 關閉載入指示器
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失敗: $e')),
        );
      }
    }
  }

  Future<String?> _extractRealPlayUrl() async {
    try {
      // 增加等待時間，確保頁面完全載入
      await Future.delayed(const Duration(seconds: 2));

      final result = await _webViewController.runJavaScriptReturningResult('''
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
          
          // 方法3: 搜尋 script 標籤中的播放地址 (增強版)
          const scripts = Array.from(document.scripts);
          for (let script of scripts) {
            const content = script.innerText || script.innerHTML || '';
            
            // 搜尋更多可能的模式
            const patterns = [
              /var\\s+hlsUrl\\s*=\\s*['"]([^'"]+)['"]/,
              /var\\s+videoUrl\\s*=\\s*['"]([^'"]+)['"]/,
              /var\\s+playUrl\\s*=\\s*['"]([^'"]+)['"]/,
              /"videoUrl"\\s*:\\s*"([^"]+)"/,
              /"playUrl"\\s*:\\s*"([^"]+)"/,
              /"src"\\s*:\\s*"([^"]+)"/,
              /source\\s*:\\s*['"]([^'"]+)['"]/,
              /src\\s*:\\s*['"]([^'"]+)['"]/,
              /'videoUrl'\\s*:\\s*'([^']+)'/,
              /'playUrl'\\s*:\\s*'([^']+)'/
            ];
            
            for (let pattern of patterns) {
              const match = content.match(pattern);
              if (match && match[1] && match[1].includes('http')) {
                console.log('在 script 中找到播放地址:', match[1]);
                return JSON.stringify({ success: true, url: match[1], source: 'script-pattern' });
              }
            }
          }
          
          // 方法4: 檢查所有 video 標籤
          const videos = document.querySelectorAll('video');
          for (let video of videos) {
            if (video.src && video.src.startsWith('http')) {
              console.log('在 video 標籤中找到 src:', video.src);
              return JSON.stringify({ success: true, url: video.src, source: 'video-tag' });
            }
            
            // 檢查 source 子標籤
            const sources = video.querySelectorAll('source');
            for (let source of sources) {
              if (source.src && source.src.startsWith('http')) {
                console.log('在 source 標籤中找到 src:', source.src);
                return JSON.stringify({ success: true, url: source.src, source: 'source-tag' });
              }
            }
          }
          
          // 方法5: 搜尋頁面中的各種影片格式 URL (增強版)
          const pageContent = document.documentElement.outerHTML;
          const urlPatterns = [
            /https?:\\/\\/[^\\s"'<>]+\\.m3u8[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]+\\.mp4[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]+\\.webm[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]+\\.mkv[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]+\\.avi[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]*\\/stream[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]*\\/video[^\\s"'<>]*/
          ];
          
          for (let pattern of urlPatterns) {
            const match = pageContent.match(pattern);
            if (match) {
              console.log('在頁面中找到影片URL:', match[0]);
              return JSON.stringify({ success: true, url: match[0], source: 'page-regex' });
            }
          }
          
          // 方法6: 檢查 iframe 中的內容
          const iframes = document.querySelectorAll('iframe');
          for (let iframe of iframes) {
            if (iframe.src && (iframe.src.includes('player') || iframe.src.includes('embed'))) {
              console.log('找到播放器 iframe:', iframe.src);
              return JSON.stringify({ success: true, url: iframe.src, source: 'iframe' });
            }
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
        print("❌ 未找到播放地址: ${data['error'] ?? '未知錯誤'}");
        // 嘗試等待更長時間再重試一次
        await Future.delayed(const Duration(seconds: 3));
        return await _retryExtractRealPlayUrl();
      }
    } catch (e) {
      print("❌ 提取播放地址時發生錯誤: $e");
      return await _retryExtractRealPlayUrl();
    }
  }

  // 新增重試方法
  Future<String?> _retryExtractRealPlayUrl() async {
    try {
      print("🔄 重試提取播放地址...");
      final result = await _webViewController.runJavaScriptReturningResult('''
        (function() {
          // 更積極的搜尋方法
          const allElements = document.querySelectorAll('*');
          
          for (let element of allElements) {
            // 搜尋所有包含 'src' 屬性的元素
            const src = element.getAttribute('src');
            if (src && (src.includes('.m3u8') || src.includes('.mp4') || src.includes('stream'))) {
              if (src.startsWith('http')) {
                console.log('在元素屬性中找到播放地址:', src);
                return JSON.stringify({ success: true, url: src, source: 'element-src' });
              }
            }
            
            // 搜尋所有包含 'data-src' 屬性的元素
            const dataSrc = element.getAttribute('data-src');
            if (dataSrc && (dataSrc.includes('.m3u8') || dataSrc.includes('.mp4'))) {
              if (dataSrc.startsWith('http')) {
                console.log('在 data-src 中找到播放地址:', dataSrc);
                return JSON.stringify({ success: true, url: dataSrc, source: 'data-src' });
              }
            }
          }
          
          return JSON.stringify({ success: false, error: '重試後仍未找到播放地址' });
        })();
      ''');

      String resultString = result.toString();
      dynamic data = jsonDecode(resultString);

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data['success'] == true) {
        print("✅ 重試成功找到播放地址: ${data['url']} (來源: ${data['source']})");
        return data['url'];
      }
    } catch (e) {
      print("❌ 重試提取播放地址時發生錯誤: $e");
    }

    return null;
  }

  Future<String?> _extractAnimePlayUrl() async {
    try {
      final result = await _webViewController.runJavaScriptReturningResult('''
        (function() {
          console.log('開始搜尋動畫播放地址...');
          
          // 搜尋各種可能的播放網址
          const pageContent = document.documentElement.outerHTML;
          
          // 方法1: 搜尋 .m3u8 URL
          const m3u8Match = pageContent.match(/https?:\\/\\/[^\\s"'<>]+\\.m3u8[^\\s"'<>]*/);
          if (m3u8Match) {
            return JSON.stringify({ success: true, url: m3u8Match[0] });
          }
          
          // 方法2: 搜尋 .mp4 URL
          const mp4Match = pageContent.match(/https?:\\/\\/[^\\s"'<>]+\\.mp4[^\\s"'<>]*/);
          if (mp4Match) {
            return JSON.stringify({ success: true, url: mp4Match[0] });
          }
          
          return JSON.stringify({ success: false });
        })();
      ''');

      final data = jsonDecode(result.toString());
      if (data['success'] == true) {
        return data['url'];
      }
    } catch (e) {
      print('提取動畫播放網址失敗: $e');
    }
    return null;
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

  // 手機版控制按鈕
  Widget _buildMobileControls() {
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
                  // 返回按鈕 - 更大的點擊區域
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 全螢幕切換按鈕
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isFullscreen = !_isFullscreen;
                      });
                      if (!_isFullscreen && _recommendedVideos.isEmpty) {
                        _loadRecommendedVideos();
                      }
                      _showControlsTemporarily();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _isFullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // 中央播放控制
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 後退10秒按鈕
                GestureDetector(
                  onTap: () {
                    final newPosition = _controller.value.position -
                        const Duration(seconds: 10);
                    _controller.seekTo(newPosition < Duration.zero
                        ? Duration.zero
                        : newPosition);
                    _showControlsTemporarily();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.replay_10,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),

                const SizedBox(width: 32),

                // 播放/暫停按鈕
                GestureDetector(
                  onTap: () {
                    if (_controller.value.isPlaying) {
                      _controller.pause();
                    } else {
                      _controller.play();
                    }
                    _showControlsTemporarily();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: (widget.isAnime ? Colors.pink : Colors.blue)
                          .withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _controller.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),

                const SizedBox(width: 32),

                // 前進10秒按鈕
                GestureDetector(
                  onTap: () {
                    final newPosition = _controller.value.position +
                        const Duration(seconds: 10);
                    final maxPosition = _controller.value.duration;
                    _controller.seekTo(
                        newPosition > maxPosition ? maxPosition : newPosition);
                    _showControlsTemporarily();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.forward_10,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ],
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

                // 次要控制行
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 播放速度控制
                    GestureDetector(
                      onTap: () {
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
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.speed,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              '${_playbackSpeed}x',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
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
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
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
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTVControls() {
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
                  // 返回按鈕 - 加大點擊區域
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
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
                    // 後退10秒按鈕 - 加大點擊區域
                    GestureDetector(
                      onTap: () {
                        final newPosition = _controller.value.position -
                            const Duration(seconds: 10);
                        _controller.seekTo(newPosition < Duration.zero
                            ? Duration.zero
                            : newPosition);
                        _showControlsTemporarily();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.replay_10,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),

                    const SizedBox(width: 24),

                    // 播放/暫停按鈕 - 加大點擊區域
                    GestureDetector(
                      onTap: () {
                        if (_controller.value.isPlaying) {
                          _controller.pause();
                        } else {
                          _controller.play();
                        }
                        _showControlsTemporarily();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: (widget.isAnime ? Colors.pink : Colors.blue)
                              .withOpacity(0.8),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _controller.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),

                    const SizedBox(width: 24),

                    // 前進10秒按鈕 - 加大點擊區域
                    GestureDetector(
                      onTap: () {
                        final newPosition = _controller.value.position +
                            const Duration(seconds: 10);
                        final maxPosition = _controller.value.duration;
                        _controller.seekTo(newPosition > maxPosition
                            ? maxPosition
                            : newPosition);
                        _showControlsTemporarily();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.forward_10,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 次要控制行
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 播放速度控制 - 加大點擊區域
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
                            horizontal: 16, vertical: 8),
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
                          horizontal: 16, vertical: 8),
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

                    // 全螢幕按鈕 - 加大點擊區域
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isFullscreen = !_isFullscreen;
                        });
                        _showControlsTemporarily();
                        // 這裡可以添加實際的全螢幕切換邏輯
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _isFullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
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

  Widget _buildTVRecommendedVideos() {
    return Container(
      color: Colors.black87,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題區域
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.queue_play_next,
                  color: widget.isAnime ? Colors.pink : Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isAnime ? '推薦動畫' : '推薦影片',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // 關閉推薦區域按鈕
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isFullscreen = true;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.fullscreen,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
                if (_isLoadingRecommendations) ...[
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.isAnime ? Colors.pink : Colors.blue,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 推薦影片列表 - TV版YouTube風格橫向滾動
          Expanded(
            child: _isLoadingRecommendations
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _recommendedVideos.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.video_library_outlined,
                              size: 48,
                              color: Colors.white.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '正在載入推薦影片...',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: _recommendedVideos.length,
                        itemBuilder: (context, index) {
                          final video = _recommendedVideos[index];
                          return _buildTVRecommendedVideoCard(video, index);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // TV版推薦影片卡片 - 橫向滾動風格
  Widget _buildTVRecommendedVideoCard(Map<String, dynamic> video, int index) {
    final isAnimeVideo =
        video['detail_url']?.toString().contains('hanime1.me') ?? false;

    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: InkWell(
        onTap: () => _playRecommendedVideo(video),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 縮圖區域
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                  color: Colors.grey.shade800,
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(8)),
                      child: video['img_url']?.isNotEmpty == true
                          ? Image.network(
                              video['img_url'],
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildPlaceholderThumbnail(isAnimeVideo);
                              },
                            )
                          : _buildPlaceholderThumbnail(isAnimeVideo),
                    ),

                    // 播放圖示覆蓋
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8)),
                          color: Colors.black.withOpacity(0.3),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),

                    // 類型標籤
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isAnimeVideo ? Colors.pink : Colors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isAnimeVideo ? '動畫' : '真人',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 標題區域
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        video['title'] ?? '未知標題',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${video['id'] ?? 'N/A'}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 10,
                      ),
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

  // TV版佈局播放器（支援暫停狀態推薦影片）
  Widget _buildTVLayoutPlayer() {
    return Stack(
      children: [
        // 主要播放區域
        GestureDetector(
          onTap: () {
            setState(() {
              _showControls = !_showControls;
            });
            if (_showControls) {
              _hideControlsAfterDelay();
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
              if (_showControls) _buildTVControls(),
            ],
          ),
        ),

        // 推薦影片區域（在暫停狀態下顯示在最下方）
        if (_initialized && !_controller.value.isPlaying && _recommendedVideos.isNotEmpty)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildTVPausedRecommendedVideos(),
          ),
      ],
    );
  }

  // TV版暫停狀態下的推薦影片區域
  Widget _buildTVPausedRecommendedVideos() {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.8),
            Colors.black.withOpacity(0.95),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題區域
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.queue_play_next,
                  color: widget.isAnime ? Colors.pink : Colors.blue,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  widget.isAnime ? '推薦動畫' : '推薦影片',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_isLoadingRecommendations)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.isAnime ? Colors.pink : Colors.blue,
                    ),
                  ),
              ],
            ),
          ),

          // 橫向滾動的推薦影片列表（TV版）
          Expanded(
            child: _isLoadingRecommendations
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _recommendedVideos.length > 20 ? 20 : _recommendedVideos.length,
                    itemBuilder: (context, index) {
                      final video = _recommendedVideos[index];
                      return _buildTVHorizontalRecommendedVideoCard(video, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // TV版橫向推薦影片卡片（五個半寬度）
  Widget _buildTVHorizontalRecommendedVideoCard(Map<String, dynamic> video, int index) {
    final screenWidth = MediaQuery.of(context).size.width;
    // TV版卡片稍大一些：螢幕寬度除以5，再減去間距
    final cardWidth = (screenWidth - 32 - (4 * 12)) / 5; // 32是左右padding，4*12是卡片間距
    
    final isAnimeVideo =
        video['detail_url']?.toString().contains('hanime1.me') ?? false;

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withOpacity(0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _playRecommendedVideo(video),
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 縮圖區域
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(10)),
                  color: Colors.grey.shade800,
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(10)),
                      child: video['img_url']?.isNotEmpty == true
                          ? Image.network(
                              video['img_url'],
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildPlaceholderThumbnail(isAnimeVideo);
                              },
                            )
                          : _buildPlaceholderThumbnail(isAnimeVideo),
                    ),

                    // 播放圖示覆蓋
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10)),
                          color: Colors.black.withOpacity(0.4),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),

                    // 類型標籤
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: isAnimeVideo ? Colors.pink : Colors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isAnimeVideo ? '動畫' : '真人',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    // 編號標籤 (顯示在左上角)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 標題區域
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  video['title'] ?? '未知標題',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
    final screenSize = MediaQuery.of(context).size;
    
    // 響應式設計 - 根據螢幕大小調整對話框大小
    final dialogWidth = math.min(screenSize.width * 0.9, 450.0);
    final maxDialogHeight = screenSize.height * 0.85;
    
    // 根據影片類型設定圖片比例
    final imageAspectRatio = widget.isAnime ? 0.7 : 1.6; // 動畫直向，真人橫向
    final imageHeight = dialogWidth / imageAspectRatio;
    
    // 計算內容區域高度
    const titleAreaHeight = 140.0; // 增加標題和按鈕區域高度
    const padding = 40.0; // 增加上下內邊距
    final totalContentHeight = imageHeight + titleAreaHeight + padding;
    
    // 確保對話框不超出螢幕，預留更多空間給按鈕
    final dialogHeight = math.min(totalContentHeight, maxDialogHeight);
    
        return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxDialogHeight,
          maxWidth: dialogWidth,
        ),
        child: Container(
          width: dialogWidth,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 圖片區域 - 動態調整高度
              Flexible(
                flex: 3,
                child: Container(
                  width: double.infinity,
                  constraints: BoxConstraints(
                    maxHeight: maxDialogHeight * 0.65, // 最大65%高度給圖片
                    minHeight: 180, // 最小高度
                  ),
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.video['img_url']?.isNotEmpty == true)
                        _buildResponsiveImage()
                      else
                        _buildPlaceholderImage(),
                      
                      // 類型標籤
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: widget.isAnime ? Colors.pink : Colors.blue,
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
                        top: 8,
                        right: 8,
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
                                        : Colors.black.withOpacity(0.6),
                                    shape: BoxShape.circle,
                                    border: hasFocus
                                        ? Border.all(color: Colors.white, width: 2)
                                        : null,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 18,
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
              
              // 詳細信息區域 - 固定底部空間
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(
                  minHeight: 100,
                  maxHeight: 120,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 標題區域 - 限制高度
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 標題
                          Flexible(
                            child: Text(
                              widget.video['title'] ?? '未知標題',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 4),
                          
                          // 影片ID
                          Text(
                            '影片 ID: ${widget.video['id'] ?? 'N/A'}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // 按鈕區域 - 固定高度
                    SizedBox(
                      height: 40, // 減少按鈕高度
                      child: Row(
                        children: [
                          // 收藏按鈕
                          Expanded(
                            child: _buildActionButton(
                              focusNode: _favoriteFocusNode,
                              onTap: () {
                                widget.onToggleFavorite();
                                setState(() {}); // 更新收藏狀態顯示
                              },
                              icon: widget.isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              label: widget.isFavorite ? '取消收藏' : '收藏',
                              color: widget.isFavorite ? Colors.red : null,
                              isPrimary: false,
                            ),
                          ),
                          
                          const SizedBox(width: 8),
                          
                          // 播放按鈕
                          Expanded(
                            flex: 2,
                            child: _buildActionButton(
                              focusNode: _playFocusNode,
                              autofocus: true,
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.onPlay();
                              },
                              icon: Icons.play_arrow,
                              label: '立即播放',
                              color: widget.isAnime ? Colors.pink : Colors.blue,
                              isPrimary: true,
                            ),
                          ),
                        ],
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

  // 響應式圖片顯示
  Widget _buildResponsiveImage() {
    return FutureBuilder<ImageInfo>(
      future: _getImageInfo(widget.video['img_url']),
      builder: (context, snapshot) {
        BoxFit imageFit = BoxFit.cover;
        
        if (snapshot.hasData && snapshot.data != null) {
          final imageInfo = snapshot.data!;
          final imageWidth = imageInfo.image.width.toDouble();
          final imageHeight = imageInfo.image.height.toDouble();
          final imageAspectRatio = imageWidth / imageHeight;
          
          // 根據圖片和容器的比例選擇合適的顯示方式
          if (widget.isAnime) {
            // 動畫：如果是橫向圖片，用 contain 保持完整
            imageFit = imageAspectRatio > 1.0 ? BoxFit.contain : BoxFit.cover;
          } else {
            // 真人：如果是直向圖片，用 contain 保持完整
            imageFit = imageAspectRatio < 1.0 ? BoxFit.contain : BoxFit.cover;
          }
        }
        
        return Image.network(
          widget.video['img_url'],
          fit: imageFit,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
        );
      },
    );
  }

  // 佔位符圖片
  Widget _buildPlaceholderImage() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey.shade800,
            Colors.grey.shade900,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.isAnime ? Icons.animation : Icons.video_library,
              size: 48,
              color: Colors.white.withOpacity(0.7),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isAnime ? '動畫影片' : '真人影片',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

     // 操作按鈕組件 - 優化尺寸和邊距
   Widget _buildActionButton({
     required FocusNode focusNode,
     required VoidCallback onTap,
     required IconData icon,
     required String label,
     Color? color,
     bool isPrimary = false,
     bool autofocus = false,
   }) {
     return Focus(
       focusNode: focusNode,
       autofocus: autofocus,
       onKey: (node, event) {
         if (event is RawKeyDownEvent) {
           if (event.logicalKey == LogicalKeyboardKey.select ||
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
           return InkWell(
             onTap: onTap,
             borderRadius: BorderRadius.circular(6),
             child: Container(
               height: 36, // 減少按鈕高度
               padding: const EdgeInsets.symmetric(horizontal: 4),
               decoration: BoxDecoration(
                 color: hasFocus
                     ? (color ?? Colors.white.withOpacity(0.2))
                     : (isPrimary
                         ? (color?.withOpacity(0.8) ?? Colors.blue.withOpacity(0.8))
                         : Colors.white.withOpacity(0.1)),
                 borderRadius: BorderRadius.circular(6),
                 border: hasFocus
                     ? Border.all(color: Colors.white, width: 2)
                     : Border.all(
                         color: Colors.white.withOpacity(0.2),
                         width: 1),
                 boxShadow: hasFocus
                     ? [
                         BoxShadow(
                           color: (color ?? Colors.blue).withOpacity(0.2),
                           blurRadius: 6,
                           spreadRadius: 1,
                           offset: const Offset(0, 2),
                         ),
                       ]
                     : null,
               ),
               child: Row(
                 mainAxisAlignment: MainAxisAlignment.center,
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   Icon(
                     icon,
                     color: Colors.white,
                     size: isPrimary ? 18 : 16,
                   ),
                   const SizedBox(width: 4),
                   Flexible(
                     child: Text(
                       label,
                       style: TextStyle(
                         color: Colors.white,
                         fontSize: isPrimary ? 14 : 12,
                         fontWeight: isPrimary ? FontWeight.bold : FontWeight.w500,
                       ),
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
   }

  // 獲取圖片信息
  Future<ImageInfo> _getImageInfo(String imageUrl) async {
    final imageProvider = NetworkImage(imageUrl);
    final stream = imageProvider.resolve(const ImageConfiguration());
    final completer = Completer<ImageInfo>();

    final listener = ImageStreamListener((ImageInfo info, bool _) {
      if (!completer.isCompleted) {
        completer.complete(info);
      }
    }, onError: (dynamic exception, StackTrace? stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(exception, stackTrace);
      }
    });

    stream.addListener(listener);

    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } finally {
      stream.removeListener(listener);
    }
  }
}
