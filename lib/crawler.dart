import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

class VideoInfo {
  final String title;
  final String imgUrl;
  final String detailUrl;
  final String? videoUrl;
  final String? keyUrl;

  VideoInfo({
    required this.title,
    required this.imgUrl,
    required this.detailUrl,
    this.videoUrl,
    this.keyUrl,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'img_url': imgUrl,
        'detail_url': detailUrl,
        'video': videoUrl,
        'key_url': keyUrl,
      };

  static VideoInfo fromJson(Map<String, dynamic> json) => VideoInfo(
        title: json['title'] ?? '',
        imgUrl: json['img_url'] ?? '',
        detailUrl: json['detail_url'] ?? '',
        videoUrl: json['video'],
        keyUrl: json['key_url'],
      );
}

Future<List<VideoInfo>> fetchVideoList(String url, {int maxCount = 25}) async {
  final res = await http.get(Uri.parse(url));
  if (res.statusCode != 200) return [];
  final doc = parser.parse(res.body);
  final items = doc.getElementsByClassName('video-img-box');
  final videos = <VideoInfo>[];
  for (final item in items.take(maxCount)) {
    final img = item.querySelector('img');
    final imgUrl = img?.attributes['data-src'] ?? img?.attributes['src'] ?? '';
    final titleElem = item.querySelector('.detail .title a');
    final title = titleElem?.text.trim() ?? '';
    final detailUrl = titleElem?.attributes['href'] ?? '';
    final detail = await fetchVideoDetailM3u8(detailUrl);
    videos.add(VideoInfo(
      title: title,
      imgUrl: imgUrl,
      detailUrl: detailUrl,
      videoUrl: detail['m3u8_url'],
      keyUrl: detail['key_url'],
    ));
  }
  return videos;
}

Future<Map<String, String?>> fetchVideoDetailM3u8(String detailUrl) async {
  final res = await http.get(Uri.parse(detailUrl));
  if (res.statusCode != 200) return {'m3u8_url': null, 'key_url': null};
  final doc = parser.parse(res.body);
  String? m3u8Url;
  String? keyUrl;
  for (final script in doc.getElementsByTagName('script')) {
    final text = script.text;
    final match =
        RegExp(r'(https?:\\/\\/[^\'"\s]+\.m3u8)').firstMatch(text);
    if (match != null) {
      m3u8Url = match.group(1)?.replaceAll('\\/', '/');
      break;
    }
  }
  if (m3u8Url != null) {
    final res2 = await http.get(Uri.parse(m3u8Url));
    if (res2.statusCode == 200) {
      final m3u8Txt = res2.body;
      final keyMatch =
          RegExp(r'#EXT-X-KEY:METHOD=AES-128,URI="([^"]+)"').firstMatch(m3u8Txt);
      if (keyMatch != null) {
        keyUrl = keyMatch.group(1);
        if (keyUrl != null && !keyUrl!.startsWith('http')) {
          keyUrl = Uri.parse(m3u8Url).resolve(keyUrl!).toString();
        }
      }
    }
  }
  return {'m3u8_url': m3u8Url, 'key_url': keyUrl};
}

Future<String> encodeVideoList(List<VideoInfo> videos) async {
  final list = videos.map((v) => v.toJson()).toList();
  return jsonEncode(list);
}
