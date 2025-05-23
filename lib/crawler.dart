import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

Future<List<Map<String, String>>> crawlVideos({int maxCount = 25}) async {
  const url = 'https://jable.tv/categories/chinese-subtitle/';
  final resp = await http.get(Uri.parse(url));
  if (resp.statusCode != 200) return [];
  final doc = parser.parse(resp.body);
  final items = doc.querySelectorAll('.video-img-box');
  List<Map<String, String>> results = [];
  for (var item in items) {
    try {
      final img = item.querySelector('img');
      final imgUrl = img?.attributes['data-src'] ?? img?.attributes['src'] ?? '';
      final titleElem = item.querySelector('.detail .title a');
      final title = titleElem?.text.trim() ?? '';
      final detailUrl = titleElem?.attributes['href'] ?? '';
      final detail = await _fetchVideoDetail(detailUrl);
      results.add({
        'img_url': imgUrl,
        'title': title,
        'detail_url': detailUrl,
        'video': detail['m3u8_url'] ?? '',
        'key_url': detail['key_url'] ?? '',
      });
      if (results.length >= maxCount) break;
    } catch (e) {
      // ignore individual errors
    }
  }
  return results;
}

Future<Map<String, String>> _fetchVideoDetail(String url) async {
  final resp = await http.get(Uri.parse(url));
  if (resp.statusCode != 200) return {};
  final doc = parser.parse(resp.body);
  String? m3u8Url;
  String? keyUrl;
  for (var script in doc.getElementsByTagName('script')) {
    final text = script.text;
    final match = RegExp(r'(https?://[^\'"\s]+\.m3u8)').firstMatch(text);
    if (match != null) {
      m3u8Url = match.group(1);
      break;
    }
  }
  if (m3u8Url != null) {
    try {
      final res = await http.get(Uri.parse(m3u8Url!));
      if (res.statusCode == 200) {
        final keyMatch = RegExp(r'#EXT-X-KEY:METHOD=AES-128,URI="([^"]+)"')
            .firstMatch(res.body);
        if (keyMatch != null) {
          keyUrl = keyMatch.group(1);
          if (keyUrl != null && !keyUrl!.startsWith('http')) {
            keyUrl = Uri.parse(m3u8Url!).resolve(keyUrl!).toString();
          }
        }
      }
    } catch (_) {}
  }
  return {'m3u8_url': m3u8Url ?? '', 'key_url': keyUrl ?? ''};
}

Future<File> saveVideoList(List<Map<String, String>> list) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'video_list.json'));
  await file.writeAsString(jsonEncode(list));
  return file;
}

Future<List<Map<String, String>>> loadVideoList() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'video_list.json'));
  if (await file.exists()) {
    final data = jsonDecode(await file.readAsString()) as List<dynamic>;
    return data.map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v.toString()))).toList();
  }
  return [];
}
