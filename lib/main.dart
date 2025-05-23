import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';

import 'crawler.dart';

const targetUrl = 'https://jable.tv/categories/chinese-subtitle/';

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
  List<VideoInfo> _videos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<File> _jsonFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/video_list.json');
  }

  Future<void> _loadVideos() async {
    setState(() {
      _loading = true;
    });
    final file = await _jsonFile();
    if (await file.exists()) {
      final content = await file.readAsString();
      final data = jsonDecode(content) as List;
      _videos = data.map((e) => VideoInfo.fromJson(e)).toList();
      setState(() {
        _loading = false;
      });
    } else {
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
    });
    final videos = await fetchVideoList(targetUrl);
    final file = await _jsonFile();
    await file.writeAsString(await encodeVideoList(videos));
    setState(() {
      _videos = videos;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video List'),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _videos.length,
              itemBuilder: (context, index) {
                final video = _videos[index];
                return ListTile(
                  leading: Image.network(video.imgUrl, width: 80, fit: BoxFit.cover),
                  title: Text(video.title),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoPlayerScreen(url: video.videoUrl ?? ''),
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
