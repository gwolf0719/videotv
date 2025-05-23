import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class VideoItem {
  final String title;
  final String imgUrl;
  final String detailUrl;
  final String? m3u8Url;
  final String? keyUrl;

  VideoItem({
    required this.title,
    required this.imgUrl,
    required this.detailUrl,
    this.m3u8Url,
    this.keyUrl,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'img_url': imgUrl,
        'detail_url': detailUrl,
        'video': m3u8Url,
        'key_url': keyUrl,
      };
}

class Crawler {
  final String url;
  final int maxCount;

  Crawler({
    this.url = 'https://jable.tv/categories/chinese-subtitle/',
    this.maxCount = 25,
  });

  Future<List<VideoItem>> fetchVideoList() async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw Exception('Failed to load page');
    }
    final document = parser.parse(res.body);
    final items = document.querySelectorAll('.video-img-box');
    final videos = <VideoItem>[];

    for (final item in items.take(maxCount)) {
      try {
        final img = item.querySelector('img');
        final imgUrl = img?.attributes['data-src'] ?? img?.attributes['src'] ?? '';
        final titleElem = item.querySelector('.detail .title a');
        final title = titleElem?.text.trim() ?? '';
        final detailUrl = titleElem?.attributes['href'] ?? '';
        final m3u8 = await fetchVideoDetail(detailUrl);
        videos.add(VideoItem(
          title: title,
          imgUrl: imgUrl,
          detailUrl: detailUrl,
          m3u8Url: m3u8['m3u8Url'],
          keyUrl: m3u8['keyUrl'],
        ));
      } catch (_) {
        // ignore single item errors
      }
    }
    return videos;
  }

  Future<Map<String, String?>> fetchVideoDetail(String detailUrl) async {
    final res = await http.get(Uri.parse(detailUrl));
    if (res.statusCode != 200) return {};
    final document = parser.parse(res.body);
    final scripts = document.getElementsByTagName('script');
    String? m3u8Url;
    String? keyUrl;
    for (final script in scripts) {
      final text = script.text;
      if (text.contains('.m3u8')) {
        final match =
            RegExp(r"(https?://[^'\"\s]+\.m3u8)").firstMatch(text);
        if (match != null) {
          m3u8Url = match.group(1);
          break;
        }
      }
    }
    if (m3u8Url != null) {
      final res = await http.get(Uri.parse(m3u8Url!));
      if (res.statusCode == 200) {
        final match = RegExp(r'#EXT-X-KEY:METHOD=AES-128,URI="([^"]+)"')
            .firstMatch(res.body);
        if (match != null) {
          keyUrl = match.group(1);
          if (keyUrl != null && !keyUrl!.startsWith('http')) {
            keyUrl = Uri.parse(m3u8Url!).resolve(keyUrl!).toString();
          }
        }
      }
    }
    return {'m3u8Url': m3u8Url, 'keyUrl': keyUrl};
  }

  Future<File> run() async {
    final list = await fetchVideoList();
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'video_list.json'));
    await file.writeAsString(jsonEncode(list.map((v) => v.toJson()).toList()),
        flush: true);
    return file;
  }
}
