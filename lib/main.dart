import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
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
  List<Map<String, dynamic>> _items = [];
  bool _loadingDetail = false;

  @override
  void initState() {
    super.initState();
    initWebView();
  }

  void initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            await Future.delayed(const Duration(seconds: 3));
            if (_loadingDetail) {
              final detailResult =
                  await _webViewController.runJavaScriptReturningResult(r'''
  (async function() {
    const scripts = Array.from(document.scripts);
    let m3u8 = null;
    for (let script of scripts) {
      const text = script.innerText;
      if (text.includes('.m3u8')) {
        const match = text.match(/(https?:\\/\\/[^\"'\s]+\\.m3u8)/);
        if (match) {
          m3u8 = match[1];
          break;
        }
      }
    }
    return JSON.stringify({ m3u8_url: m3u8 });
  })();
''');

              final map = jsonDecode(detailResult as String) as Map<String, dynamic>;
              final url = map['m3u8_url'] as String?;
              _loadingDetail = false;

              if (url != null && mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerScreen(url: url),
                  ),
                );
              }

              await _webViewController.loadRequest(
                Uri.parse('https://jable.tv/categories/chinese-subtitle/'),
              );
            } else {
              final result =
                  await _webViewController.runJavaScriptReturningResult(r'''
  (function() {
    const items = Array.from(document.querySelectorAll('.video-img-box')).slice(0, 25);
    return JSON.stringify(items.map(item => {
      const img = item.querySelector('img')?.getAttribute('data-src') || item.querySelector('img')?.getAttribute('src');
      const title = item.querySelector('.detail .title a')?.innerText.trim();
      const detailUrl = item.querySelector('.detail .title a')?.href;
      return { title: title, img_url: img, detail_url: detailUrl };
    }));
  })();
''');
              setState(() {
                _items = List<Map<String, dynamic>>.from(
                  jsonDecode(result as String) as List<dynamic>,
                );
              });
            }
          },
        ),
      )
      ..loadRequest(
        Uri.parse('https://jable.tv/categories/chinese-subtitle/'),
      );
  }

  Widget buildInvisibleWebView() {
    return SizedBox(
      width: 1,
      height: 1,
      child: WebViewWidget(controller: _webViewController),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video List')),
      body: Stack(
        children: [
          buildInvisibleWebView(),
          ListView.builder(
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              return ListTile(
                leading: item['img_url'] != null
                    ? Image.network(
                        item['img_url'],
                        width: 100,
                        fit: BoxFit.cover,
                      )
                    : null,
                title: Text(item['title'] ?? ''),
                onTap: () {
                  final detail = item['detail_url'];
                  if (detail != null) {
                    _loadingDetail = true;
                    _webViewController.loadRequest(Uri.parse(detail));
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String url;
  const VideoPlayerScreen({super.key, required this.url});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.url)
      ..initialize().then((_) {
        setState(() {
          _initialized = true;
        });
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Player')),
      body: Center(
        child: _initialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
