import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';

class Crawler {
  /// Fetches the video list from [url] and returns a list of maps with
  /// thumbnail, title, detail page, m3u8 url and key url.
  static Future<List<Map<String, String?>>> fetchVideoList(String url,
      {int maxCount = 25}) async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      return [];
    }
    final document = parser.parse(res.body);
    final items = document.getElementsByClassName('video-img-box');
    final List<Map<String, String?>> list = [];
    for (final item in items.take(maxCount)) {
      try {
        final img = item.getElementsByTagName('img').first;
        final imgUrl = img.attributes['data-src'] ?? img.attributes['src'] ?? '';
        final titleElem = item.querySelector('.detail .title a');
        if (titleElem == null) continue;
        final title = titleElem.text.trim();
        final detailUrl = titleElem.attributes['href'] ?? '';
        final video = await _fetchVideoDetailM3u8(detailUrl);
        list.add({
          'img_url': imgUrl,
          'title': title,
          'detail_url': detailUrl,
          'video': video['m3u8_url'],
          'key_url': video['key_url'],
        });
      } catch (_) {}
    }
    return list;
  }

  static Future<Map<String, String?>> _fetchVideoDetailM3u8(String url) async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      return {"m3u8_url": null, "key_url": null};
    }
    final doc = parser.parse(res.body);
    String? m3u8Url;
    String? keyUrl;
    for (final script in doc.getElementsByTagName('script')) {
      final text = script.text;
      final match = RegExp(r'(https?:\\/\\/[^\'"\s]+\.m3u8)').firstMatch(text);
      if (match != null) {
        m3u8Url = match.group(1)?.replaceAll('\\/', '/');
        break;
      }
    }
    if (m3u8Url != null) {
      try {
        final m3u8Res = await http.get(Uri.parse(m3u8Url));
        if (m3u8Res.statusCode == 200) {
          final keyMatch = RegExp(r'#EXT-X-KEY:METHOD=AES-128,URI="([^"]+)"')
              .firstMatch(m3u8Res.body);
          if (keyMatch != null) {
            keyUrl = keyMatch.group(1);
            if (keyUrl != null && !keyUrl!.startsWith('http')) {
              keyUrl = Uri.parse(m3u8Url).resolve(keyUrl!).toString();
            }
          }
        }
      } catch (_) {}
    }
    return {"m3u8_url": m3u8Url, "key_url": keyUrl};
  }
}
