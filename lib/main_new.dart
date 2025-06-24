import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'services/video_repository.dart';
import 'features/tv/pages/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(const VideoTVApp());
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
  } catch (e) {
    // 忽略錯誤
  }
}

class VideoTVApp extends StatelessWidget {
  const VideoTVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VideoTV',
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
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      // 初始化 VideoRepository
      _videoRepository = VideoRepository();
      
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
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                '正在初始化...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                '初始化失敗',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isInitialized = false;
                    _errorMessage = null;
                  });
                  _initializeServices();
                },
                child: const Text('重試'),
              ),
            ],
          ),
        ),
      );
    }

    return HomePage(
      videoRepository: _videoRepository,
    );
  }
} 