import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_database/firebase_database.dart';

class RealCrawler {
  final WebViewController webViewController;
  final DatabaseReference dbRef;
  final Function(bool) onLoadingChange;
  final Function(String) onStatusChange;
  final Function(List<Map<String, dynamic>>) onDataUpdate;

  RealCrawler({
    required this.webViewController,
    required this.dbRef,
    required this.onLoadingChange,
    required this.onStatusChange,
    required this.onDataUpdate,
  });

  Future<void> startCrawling() async {
    onLoadingChange(true);
    onStatusChange('正在載入網站...');

    try {
      await webViewController.loadRequest(
        Uri.parse('https://jable.tv/categories/chinese-subtitle/'),
      );
    } catch (e) {
      onLoadingChange(false);
      onStatusChange('載入失敗: $e');
    }
  }

  Future<void> extractVideoData() async {
    onStatusChange('正在抓取影片資料...');

    try {
      final result = await webViewController.runJavaScriptReturningResult('''
        (function() {
          const items = Array.from(document.querySelectorAll('.video-img-box'));
          console.log('找到', items.length, '個影片');
          
          const videos = [];
          for (let i = 0; i < items.length; i++) {
            const item = items[i];
            const titleElement = item.querySelector('.detail .title a');
            const imgElement = item.querySelector('img');
            
            videos.push({
              id: i + 1,
              title: titleElement?.innerText?.trim() || '未知標題',
              detail_url: titleElement?.href || '',
              img_url: imgElement?.getAttribute('data-src') || imgElement?.getAttribute('src') || ''
            });
          }
          
          return JSON.stringify({ success: true, videos: videos });
        })();
      ''');

      String resultString = result.toString();
      dynamic data = jsonDecode(resultString);

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data['success'] == true) {
        List<dynamic> videos = data['videos'];
        final items = videos.map((v) => Map<String, dynamic>.from(v)).toList();
        onDataUpdate(items);
        onLoadingChange(false);
        onStatusChange('成功抓取 ${items.length} 個影片');
        await dbRef.set(items);
      } else {
        throw Exception('抓取失敗');
      }
    } catch (e) {
      onLoadingChange(false);
      onStatusChange('抓取錯誤: $e');
    }
  }

  Future<String?> extractPlayUrl() async {
    try {
      final result = await webViewController.runJavaScriptReturningResult('''
        (function() {
          console.log('開始搜尋播放地址...');
          
          // 方法1: 檢查全域變數 hlsUrl
          if (typeof window.hlsUrl !== 'undefined') {
            console.log('找到 hlsUrl:', window.hlsUrl);
            return JSON.stringify({ success: true, url: window.hlsUrl, source: 'hlsUrl' });
          }
          
          // 方法2: 搜尋 script 標籤中的 hlsUrl
          const scripts = Array.from(document.scripts);
          for (let script of scripts) {
            const content = script.innerText || script.innerHTML || '';
            const match = content.match(/var\\s+hlsUrl\\s*=\\s*['"]([^'"]+)['"]/);
            if (match && match[1]) {
              console.log('在 script 中找到 hlsUrl:', match[1]);
              return JSON.stringify({ success: true, url: match[1], source: 'script' });
            }
          }
          
          // 方法3: 搜尋頁面中的 .m3u8 URL
          const pageContent = document.documentElement.outerHTML;
          const m3u8Match = pageContent.match(/https?:\\/\\/[^\\s"'<>]+\\.m3u8[^\\s"'<>]*/);
          if (m3u8Match) {
            console.log('在頁面中找到 m3u8:', m3u8Match[0]);
            return JSON.stringify({ success: true, url: m3u8Match[0], source: 'page' });
          }
          
          console.log('沒有找到播放地址');
          return JSON.stringify({ success: false, error: '沒有找到播放地址' });
        })();
      ''');

      String resultString = result.toString();
      dynamic data = jsonDecode(resultString);

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data['success'] == true) {
        print("✅ 找到播放地址: ${data['url']} (來源: ${data['source']})");
        return data['url'];
      } else {
        print("❌ 未找到播放地址: ${data['error']}");
        return null;
      }
    } catch (e) {
      print("❌ 提取播放地址時發生錯誤: $e");
      return null;
    }
  }
}
