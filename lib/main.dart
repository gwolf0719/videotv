import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';

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
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/video_list.json');
    if (await file.exists()) {
      final text = await file.readAsString();
      setState(() {
        _videos = jsonDecode(text);
      });
    }
  }

  Future<void> _fetchVideos() async {
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/video_list.json';
    setState(() => _loading = true);
    final process = await Process.start('python3', ['crawler.py', filePath]);
    await stdout.addStream(process.stdout);
    await stderr.addStream(process.stderr);
    await process.exitCode;
    await _loadVideos();
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video List'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _fetchVideos,
            icon: const Icon(Icons.refresh),
          ),
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
                      ? Image.network(video['img_url'], width: 100, fit: BoxFit.cover)
                      : null,
                  title: Text(video['title'] ?? ''),
                  onTap: () {
                    final url = video['m3u8_url'] ?? video['url'];
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoPlayerScreen(url: url),
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
