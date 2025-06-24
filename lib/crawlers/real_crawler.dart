import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';

class RealCrawler {
  final WebViewController webViewController;

  // 新增：追蹤當前頁面和已有影片
  int currentPage = 1; // 改為公開變數
  List<Map<String, dynamic>> _allVideos = [];
  bool _isBackgroundCrawling = false;

  RealCrawler({
    required this.webViewController,
  });

  Future<void> startCrawling({bool isBackgroundUpdate = false}) async {
    if (!isBackgroundUpdate) {
      currentPage = 1;
    } else {
      _isBackgroundCrawling = true;
    }

    try {
      await webViewController.loadRequest(
        Uri.parse('https://jable.tv/categories/chinese-subtitle/$currentPage/'),
      );
    } catch (e) {
      if (!isBackgroundUpdate) {
        _isBackgroundCrawling = false;
      }
    }
  }

  // 新增：背景爬取下一頁
  Future<void> crawlNextPageInBackground() async {
    if (_isBackgroundCrawling) return;

    currentPage++;
    await startCrawling(isBackgroundUpdate: true);
  }

  Future<List<Map<String, dynamic>>> extractVideoData() async {
    final isBackground = _isBackgroundCrawling;

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

      // 修復 JSON 解析問題
      String resultString = result.toString();
      
      print('🔍 JavaScript返回結果: $resultString');
      print('🔍 結果類型: ${result.runtimeType}');
      
      // 移除多餘的引號並解碼轉義字符
      if (resultString.startsWith('"') && resultString.endsWith('"')) {
        resultString = resultString.substring(1, resultString.length - 1);
        resultString = resultString.replaceAll('\\"', '"').replaceAll('\\\\', '\\');
      }

      dynamic data;
      try {
        data = jsonDecode(resultString);
      } catch (e) {
        print('❌ JSON解析失敗: $e');
        print('🐛 原始結果: $resultString');
        
        // 嘗試直接使用結果（如果它已經是 List）
        if (result is List) {
          data = result;
        } else {
          throw Exception('無法解析 JavaScript 返回的資料');
        }
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

          print('第 $currentPage 頁：新增 ${filteredItems.length} 個影片，總計 ${_allVideos.length} 個');
        } else {
          print('第 $currentPage 頁：沒有發現新影片');
        }

        if (!isBackground) {
          _isBackgroundCrawling = false;
        }
      } else {
        throw Exception('抓取失敗');
      }
    } catch (e) {
      if (!isBackground) {
        _isBackgroundCrawling = false;
      }
    }

    return _allVideos;
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
            
            // 搜尋 m3u8 檔案
            const m3u8Match = content.match(/https?:\\/\\/[^\\s"']+\\.m3u8[^\\s"']*/);
            if (m3u8Match) {
              console.log('在 script 中找到 m3u8:', m3u8Match[0]);
              return JSON.stringify({ success: true, url: m3u8Match[0], source: 'script_m3u8' });
            }
            
            // 搜尋 mp4 檔案
            const mp4Match = content.match(/https?:\\/\\/[^\\s"']+\\.mp4[^\\s"']*/);
            if (mp4Match) {
              console.log('在 script 中找到 mp4:', mp4Match[0]);
              return JSON.stringify({ success: true, url: mp4Match[0], source: 'script_mp4' });
            }
          }
          
          console.log('未找到播放地址');
          return JSON.stringify({ success: false, error: '未找到播放地址' });
        })();
      ''');

      // 修復 JSON 解析問題
      String resultString = result.toString();
      
      print('🔍 播放地址搜尋結果: $resultString');
      
      // 移除多餘的引號並解碼轉義字符
      if (resultString.startsWith('"') && resultString.endsWith('"')) {
        resultString = resultString.substring(1, resultString.length - 1);
        resultString = resultString.replaceAll('\\"', '"').replaceAll('\\\\', '\\');
      }

      dynamic data;
      try {
        data = jsonDecode(resultString);
      } catch (e) {
        print('❌ JSON解析失敗: $e');
        print('🐛 原始結果: $resultString');
        return null;
      }

      if (data['success'] == true) {
        return data['url'];
      } else {
        print('❌ 無法找到播放地址: ${data['error'] ?? '未知錯誤'}');
        return null;
      }
    } catch (e) {
      print('❌ 提取播放地址錯誤: $e');
      return null;
    }
  }

  Future<Map<String, String>?> extractActressInfo() async {
    try {
      print('🔍 正在尋找女優連結...');
      
      final result = await webViewController.runJavaScriptReturningResult('''
        (function() {
          console.log('🔍 開始搜尋女優連結...');
          
          // 方法1: 使用 XPath
          function getElementByXPath(xpath) {
            return document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
          }
          
          const xpath = '/html/body/div[3]/div/div/div[1]/section[2]/div[1]/div[1]/h6/div/a';
          console.log('📍 使用XPath:', xpath);
          
          let actressElement = getElementByXPath(xpath);
          
          if (actressElement && actressElement.href) {
            console.log('✅ 找到女優連結 (XPath):', actressElement.href);
            console.log('🎭 女優名稱:', actressElement.innerText?.trim());
            return JSON.stringify({
              success: true,
              url: actressElement.href,
              name: actressElement.innerText?.trim() || '未知女優',
              method: 'xpath'
            });
          }
          
          console.log('🔄 XPath方法失敗，嘗試CSS選擇器...');
          
          // 方法2: CSS 選擇器
          const selectors = [
            'section[2] .col-12 h6 div a',
            '.video-meta a[href*="models"]',
            'a[href*="/models/"]',
            '.actress-link'
          ];
          
          for (let selector of selectors) {
            actressElement = document.querySelector(selector);
            if (actressElement && actressElement.href) {
              console.log('✅ 找到女優連結 (CSS):', actressElement.href);
              console.log('🎭 女優名稱:', actressElement.innerText?.trim());
              return JSON.stringify({
                success: true,
                url: actressElement.href,
                name: actressElement.innerText?.trim() || '未知女優',
                method: 'css'
              });
            }
          }
          
          console.log('❌ 未找到女優連結');
          return JSON.stringify({ success: false, error: '未找到女優連結' });
        })();
      ''');

      // 修復 JSON 解析問題
      String resultString = result.toString();
      
      print('🔍 JavaScript返回結果: $resultString');
      print('🔍 結果類型: ${result.runtimeType}');
      
      // 移除多餘的引號並解碼轉義字符
      if (resultString.startsWith('"') && resultString.endsWith('"')) {
        resultString = resultString.substring(1, resultString.length - 1);
        resultString = resultString.replaceAll('\\"', '"').replaceAll('\\\\', '\\');
      }

      dynamic data;
      try {
        data = jsonDecode(resultString);
      } catch (e) {
        print('❌ JSON解析失敗: $e');
        print('🐛 原始結果: $resultString');
        print('❌ 無法找到女優連結，可能是無女優影片或頁面結構改變');
        return null;
      }

      if (data['success'] == true) {
        final actressUrl = data['url'];
        final actressName = data['name'];
        print('✅ 找到女優連結: $actressUrl');
        print('🎭 女優名稱: $actressName');
        
        return {
          'url': actressUrl,
          'name': actressName,
        };
      } else {
        print('❌ 無法找到女優連結，可能是無女優影片或頁面結構改變');
        return null;
      }
    } catch (e) {
      print('❌ 搜尋女優連結時發生錯誤: $e');
      return null;
    }
  }
}
