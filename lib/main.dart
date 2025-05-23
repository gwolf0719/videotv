import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

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
      home: const VideoListScreen(),
    );
  }
}

class VideoListScreen extends StatefulWidget {
  const VideoListScreen({super.key});

  @override
  State<VideoListScreen> createState() => _VideoListScreenState();
}

class _VideoListScreenState extends State<VideoListScreen> {
  List<dynamic> _videos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchVideos();
  }

  Future<String> _jsonPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/video_list.json';
  }

  Future<void> _runCrawler() async {
    setState(() => _loading = true);
    try {
      final result = await Process.run('python3', ['crawler.py']);
      debugPrint(result.stdout);
      debugPrint(result.stderr);
      final path = await _jsonPath();
      final outFile = File('video_list.json');
      if (await outFile.exists()) {
        await outFile.copy(path);
      }
    } catch (e) {
      debugPrint('Failed to run crawler: $e');
    }
    await _loadVideos();
  }

  Future<void> _loadVideos() async {
    final path = await _jsonPath();
    final file = File(path);
    if (await file.exists()) {
      try {
        final txt = await file.readAsString();
        setState(() {
          _videos = json.decode(txt);
        });
      } catch (e) {
        debugPrint('Error reading video list: $e');
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _fetchVideos() async {
    await _runCrawler();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video List'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _runCrawler,
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _videos.length,
              itemBuilder: (context, index) {
                final video = _videos[index];
                return ListTile(
                  leading: video['img_url'] != null
                      ? Image.network(video['img_url'])
                      : null,
                  title: Text(video['title'] ?? ''),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoPlayerScreen(
                          url: video['video'] ?? '',
                        ),
                      ),
                    );
                  },
                );
              },
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
