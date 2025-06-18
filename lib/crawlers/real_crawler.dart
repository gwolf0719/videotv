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
      // 增加等待時間，確保頁面完全載入
      await Future.delayed(const Duration(seconds: 5));

      final result = await webViewController.runJavaScriptReturningResult('''
        (function() {
          console.log('開始搜尋播放地址...');
          
          // 方法1: 檢查全域變數 hlsUrl
          if (typeof window.hlsUrl !== 'undefined' && window.hlsUrl) {
            console.log('找到 hlsUrl:', window.hlsUrl);
            return JSON.stringify({ success: true, url: window.hlsUrl, source: 'hlsUrl' });
          }
          
          // 方法2: 檢查其他常見的全域變數
          const globalVars = [
            'videoUrl', 'playUrl', 'streamUrl', 'mp4Url', 'video_url', 'play_url',
            'sourceUrl', 'mediaUrl', 'videoSrc', 'src', 'videoSource'
          ];
          for (let varName of globalVars) {
            if (typeof window[varName] !== 'undefined' && window[varName]) {
              console.log('找到全域變數', varName + ':', window[varName]);
              return JSON.stringify({ success: true, url: window[varName], source: varName });
            }
          }
          
          // 方法3: 搜尋 script 標籤中的播放地址 (增強版)
          const scripts = Array.from(document.scripts);
          for (let script of scripts) {
            const content = script.innerText || script.innerHTML || '';
            
            // 搜尋更多可能的模式
            const patterns = [
              /var\\s+hlsUrl\\s*=\\s*['"]([^'"]+)['"]/,
              /var\\s+videoUrl\\s*=\\s*['"]([^'"]+)['"]/,
              /var\\s+playUrl\\s*=\\s*['"]([^'"]+)['"]/,
              /"videoUrl"\\s*:\\s*"([^"]+)"/,
              /"playUrl"\\s*:\\s*"([^"]+)"/,
              /"src"\\s*:\\s*"([^"]+)"/,
              /source\\s*:\\s*['"]([^'"]+)['"]/,
              /src\\s*:\\s*['"]([^'"]+)['"]/,
              /'videoUrl'\\s*:\\s*'([^']+)'/,
              /'playUrl'\\s*:\\s*'([^']+)'/
            ];
            
            for (let pattern of patterns) {
              const match = content.match(pattern);
              if (match && match[1] && match[1].includes('http')) {
                console.log('在 script 中找到播放地址:', match[1]);
                return JSON.stringify({ success: true, url: match[1], source: 'script-pattern' });
              }
            }
          }
          
          // 方法4: 檢查所有 video 標籤
          const videos = document.querySelectorAll('video');
          for (let video of videos) {
            if (video.src && video.src.startsWith('http')) {
              console.log('在 video 標籤中找到 src:', video.src);
              return JSON.stringify({ success: true, url: video.src, source: 'video-tag' });
            }
            
            // 檢查 source 子標籤
            const sources = video.querySelectorAll('source');
            for (let source of sources) {
              if (source.src && source.src.startsWith('http')) {
                console.log('在 source 標籤中找到 src:', source.src);
                return JSON.stringify({ success: true, url: source.src, source: 'source-tag' });
              }
            }
          }
          
          // 方法5: 搜尋頁面中的各種影片格式 URL (增強版)
          const pageContent = document.documentElement.outerHTML;
          const urlPatterns = [
            /https?:\\/\\/[^\\s"'<>]+\\.m3u8[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]+\\.mp4[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]+\\.webm[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]+\\.mkv[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]+\\.avi[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]*\\/stream[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]*\\/video[^\\s"'<>]*/
          ];
          
          for (let pattern of urlPatterns) {
            const match = pageContent.match(pattern);
            if (match) {
              console.log('在頁面中找到影片URL:', match[0]);
              return JSON.stringify({ success: true, url: match[0], source: 'page-regex' });
            }
          }
          
          // 方法6: 檢查 iframe 中的內容
          const iframes = document.querySelectorAll('iframe');
          for (let iframe of iframes) {
            if (iframe.src && (iframe.src.includes('player') || iframe.src.includes('embed'))) {
              console.log('找到播放器 iframe:', iframe.src);
              return JSON.stringify({ success: true, url: iframe.src, source: 'iframe' });
            }
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
        // 嘗試等待更長時間再重試一次
        await Future.delayed(const Duration(seconds: 3));
        return await _retryExtractPlayUrl();
      }
    } catch (e) {
      print("❌ 提取播放地址時發生錯誤: $e");
      return await _retryExtractPlayUrl();
    }
  }

  // 新增重試方法
  Future<String?> _retryExtractPlayUrl() async {
    try {
      print("🔄 重試提取播放地址...");
      final result = await webViewController.runJavaScriptReturningResult('''
        (function() {
          // 更積極的搜尋方法
          const allElements = document.querySelectorAll('*');
          
          for (let element of allElements) {
            // 搜尋所有包含 'src' 屬性的元素
            const src = element.getAttribute('src');
            if (src && (src.includes('.m3u8') || src.includes('.mp4') || src.includes('stream'))) {
              if (src.startsWith('http')) {
                console.log('在元素屬性中找到播放地址:', src);
                return JSON.stringify({ success: true, url: src, source: 'element-src' });
              }
            }
            
            // 搜尋所有包含 'data-src' 屬性的元素
            const dataSrc = element.getAttribute('data-src');
            if (dataSrc && (dataSrc.includes('.m3u8') || dataSrc.includes('.mp4'))) {
              if (dataSrc.startsWith('http')) {
                console.log('在 data-src 中找到播放地址:', dataSrc);
                return JSON.stringify({ success: true, url: dataSrc, source: 'data-src' });
              }
            }
          }
          
          return JSON.stringify({ success: false, error: '重試後仍未找到播放地址' });
        })();
      ''');

      String resultString = result.toString();
      dynamic data = jsonDecode(resultString);

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data['success'] == true) {
        print("✅ 重試成功找到播放地址: ${data['url']} (來源: ${data['source']})");
        return data['url'];
      }
    } catch (e) {
      print("❌ 重試提取播放地址時發生錯誤: $e");
    }

    return null;
  }
}
