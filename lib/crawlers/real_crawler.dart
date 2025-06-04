import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_database/firebase_database.dart';

class RealCrawler {
  final WebViewController webViewController;
  final DatabaseReference dbRef;
  final Function(bool) onLoadingChange;
  final Function(String) onStatusChange;
  final Function(List<Map<String, dynamic>>) onDataUpdate;

  // 新增：追蹤當前頁面和已有影片
  int currentPage = 1; // 改為公開變數
  List<Map<String, dynamic>> _allVideos = [];
  bool _isBackgroundCrawling = false;

  RealCrawler({
    required this.webViewController,
    required this.dbRef,
    required this.onLoadingChange,
    required this.onStatusChange,
    required this.onDataUpdate,
  });

  Future<void> startCrawling({bool isBackgroundUpdate = false}) async {
    if (!isBackgroundUpdate) {
      onLoadingChange(true);
      currentPage = 1;
      // 載入現有資料
      await _loadExistingData();
    } else {
      _isBackgroundCrawling = true;
    }

    onStatusChange('正在載入網站第 $currentPage 頁...');

    try {
      await webViewController.loadRequest(
        Uri.parse('https://jable.tv/categories/chinese-subtitle/$currentPage/'),
      );
    } catch (e) {
      if (!isBackgroundUpdate) {
        onLoadingChange(false);
      }
      _isBackgroundCrawling = false;
      onStatusChange('載入失敗: $e');
    }
  }

  // 新增：載入現有資料
  Future<void> _loadExistingData() async {
    try {
      final snapshot = await dbRef.get();
      if (snapshot.exists) {
        final data = snapshot.value;
        if (data is List) {
          _allVideos = data
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
        } else if (data is Map) {
          _allVideos = data.values
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (e) {
      print('載入現有資料失敗: $e');
      _allVideos = [];
    }
  }

  // 新增：背景爬取下一頁
  Future<void> crawlNextPageInBackground() async {
    if (_isBackgroundCrawling) return;

    currentPage++;
    await startCrawling(isBackgroundUpdate: true);
  }

  Future<void> extractVideoData() async {
    final isBackground = _isBackgroundCrawling;
    onStatusChange('正在抓取第 $currentPage 頁影片資料...');

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
              id: 'real_' + Date.now() + '_' + i, // 使用時間戳避免重複ID
              title: titleElement?.innerText?.trim() || '未知標題',
              detail_url: titleElement?.href || '',
              img_url: imgElement?.getAttribute('data-src') || imgElement?.getAttribute('src') || '',
              page: $currentPage,
              crawl_time: Date.now()
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
        List<dynamic> newVideos = data['videos'];
        final newItems =
            newVideos.map((v) => Map<String, dynamic>.from(v)).toList();

        // 過濾重複的影片（根據標題和URL）
        final filteredItems = <Map<String, dynamic>>[];
        for (final newItem in newItems) {
          final isDuplicate = _allVideos.any((existing) =>
              existing['title'] == newItem['title'] &&
              existing['detail_url'] == newItem['detail_url']);
          if (!isDuplicate) {
            filteredItems.add(newItem);
          }
        }

        if (filteredItems.isNotEmpty) {
          // 將新影片添加到前面（累進更新）
          _allVideos.insertAll(0, filteredItems);

          // 限制總數量，避免過多資料
          if (_allVideos.length > 200) {
            _allVideos = _allVideos.take(200).toList();
          }

          onDataUpdate(_allVideos);
          await dbRef.set(_allVideos);

          onStatusChange(
              '第 $currentPage 頁：新增 ${filteredItems.length} 個影片，總計 ${_allVideos.length} 個');
        } else {
          onStatusChange('第 $currentPage 頁：沒有發現新影片');
        }

        if (!isBackground) {
          onLoadingChange(false);
        }
        _isBackgroundCrawling = false;
      } else {
        throw Exception('抓取失敗');
      }
    } catch (e) {
      if (!isBackground) {
        onLoadingChange(false);
      }
      _isBackgroundCrawling = false;
      onStatusChange('第 $currentPage 頁抓取錯誤: $e');
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
