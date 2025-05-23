import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';

import 'crawler.dart';

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

class VideoListScreen extends StatefulWidget {
  const VideoListScreen({super.key});

  @override
  State<VideoListScreen> createState() => _VideoListScreenState();
}

class _VideoListScreenState extends State<VideoListScreen> {
  List<Map<String, dynamic>> _videos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOrFetch();
  }

  Future<void> _loadOrFetch() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/video_list.json');
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString()) as List<dynamic>;
        _videos = data.map((e) => Map<String, dynamic>.from(e)).toList();
        setState(() {
          _loading = false;
        });
      } catch (_) {
        await _fetch();
      }
    } else {
      await _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
    });
    final list = await Crawler.fetchVideoList(
        'https://jable.tv/categories/chinese-subtitle/');
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/video_list.json');
    await file.writeAsString(jsonEncode(list));
    setState(() {
      _videos = list.map((e) => Map<String, dynamic>.from(e)).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video List'),
        actions: [IconButton(onPressed: _fetch, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _videos.length,
              itemBuilder: (context, index) {
                final video = _videos[index];
                return ListTile(
                  leading: Image.network(
                    video['img_url'] ?? '',
                    width: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.image),
                  ),
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
