import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'services/firebase_service.dart';
import 'services/video_repository.dart';
import 'features/tv/pages/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("✅ Firebase 初始化成功");
  } catch (e) {
    print("❌ Firebase 初始化失敗: $e");
  }
  
  runApp(const VideoTVApp());
}

class VideoTVApp extends StatelessWidget {
  const VideoTVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.darkTheme,
      home: const AppWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppWrapper extends StatefulWidget {
  const AppWrapper({super.key});

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> {
  late VideoRepository _videoRepository;
  late FirebaseService _firebaseService;
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      // 初始化 Firebase 服務
      _firebaseService = FirebaseService();
      await _firebaseService.initialize();
      
      // 初始化 VideoRepository
      final dbRef = FirebaseDatabase.instance.ref();
      _videoRepository = VideoRepository(dbRef);
      
      // 載入初始資料
      await Future.wait([
        _videoRepository.loadRealVideos(),
        _videoRepository.loadAnimeVideos(),
      ]);
      
      setState(() {
        _isInitialized = true;
      });
      
      print("✅ 所有服務初始化完成");
    } catch (e) {
      print("❌ 服務初始化失敗: $e");
      setState(() {
        _errorMessage = e.toString();
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _videoRepository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return _buildLoadingScreen();
    }

    if (_errorMessage != null) {
      return _buildErrorScreen();
    }

    return HomePage(
      videoRepository: _videoRepository,
      firebaseService: _firebaseService,
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(AppConstants.primaryColor).withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.tv,
                color: Color(AppConstants.primaryColor),
                size: 64,
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(
              color: Color(AppConstants.primaryColor),
              strokeWidth: 3,
            ),
            const SizedBox(height: 24),
            Text(
              '正在初始化 ${AppConstants.appName}...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: AppConstants.bodyFontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '請稍候片刻',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: AppConstants.smallFontSize,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 64,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '初始化失敗',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.grey.withOpacity(0.3),
                  ),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: AppConstants.smallFontSize,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isInitialized = false;
                        _errorMessage = null;
                      });
                      _initializeServices();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('重試'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(AppConstants.primaryColor),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: () => _showVersionInfo(),
                    icon: const Icon(Icons.info),
                    label: const Text('版本資訊'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white30),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showVersionInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      Fluttertoast.showToast(
        msg: '${AppConstants.appName} v${info.version}+${info.buildNumber}',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.black87,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: '${AppConstants.appName} ${AppConstants.appVersion}',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.black87,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    }
  }
} 