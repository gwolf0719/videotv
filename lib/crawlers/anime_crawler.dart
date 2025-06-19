import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_database/firebase_database.dart';

class AnimeCrawler {
  final WebViewController webViewController;
  final DatabaseReference dbRef;
  final Function(bool) onLoadingChange;
  final Function(String) onStatusChange;
  final Function(List<Map<String, dynamic>>) onDataUpdate;

  // 新增：追蹤當前頁面和已有影片
  int currentPage = 1;
  List<Map<String, dynamic>> _allVideos = [];
  bool _isBackgroundCrawling = false;

  AnimeCrawler({
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

    onStatusChange('正在載入動畫網站第 $currentPage 頁...');

    try {
      final url = 'https://hanime1.me/search?genre=裏番&page=$currentPage';
      print('🔄 載入動畫頁面: $url');

      await webViewController.loadRequest(Uri.parse(url));
      // 等待頁面載入完成
      await Future.delayed(const Duration(seconds: 5));
      await extractVideoData();
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
      print('載入現有動畫資料失敗: $e');
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
    print('🔥 動畫爬蟲開始執行 extractVideoData，第 $currentPage 頁');
    onStatusChange('正在抓取第 $currentPage 頁動畫資料...');

    try {
      print('🔥 準備執行 JavaScript 爬蟲邏輯');
      final result = await webViewController.runJavaScriptReturningResult('''
        (function() {
          console.log('開始搜尋影片元素...');
          
          // 直接搜尋包含 /watch 的連結
          const links = Array.from(document.querySelectorAll('a[href*="/watch"]'));
          console.log('找到', links.length, '個連結');
          
          const videos = [];
          for (let i = 0; i < Math.min(links.length, 30); i++) {
            const link = links[i];
            const title = link.getAttribute('title') || 
                         link.innerText?.trim() || 
                         link.querySelector('img')?.getAttribute('alt') || 
                         '動畫影片 ' + (i + 1);
            
            let href = link.getAttribute('href') || '';
            if (href && !href.startsWith('http')) {
              href = 'https://hanime1.me' + (href.startsWith('/') ? href : '/' + href);
            }
            
            const img = link.querySelector('img');
            let imgSrc = '';
            if (img) {
              imgSrc = img.getAttribute('src') || 
                      img.getAttribute('data-src') || 
                      img.getAttribute('data-lazy') || '';
              if (imgSrc && !imgSrc.startsWith('http') && imgSrc.startsWith('/')) {
                imgSrc = 'https://hanime1.me' + imgSrc;
              }
            }
            
            if (title && href) {
              videos.push({
                id: 'anime_' + Date.now() + '_' + i,
                title: title.substring(0, 100),
                detail_url: href,
                img_url: imgSrc,
                episodes: 'N/A',
                page: $currentPage,
                crawl_time: Date.now()
              });
              console.log('找到影片:', title);
            }
          }
          
          console.log('總共找到', videos.length, '個有效影片');
          return JSON.stringify({ success: true, videos: videos });
        })();
      ''');

      print('🔥 JavaScript 執行完成，結果長度: ${result.toString().length}');
      String resultString = result.toString();
      dynamic data = jsonDecode(resultString);

      if (data is String) {
        data = jsonDecode(data);
      }

      print(
          '🔥 解析後的資料: success=${data['success']}, videos數量=${data['videos']?.length}');

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

          print(
              '🔥 準備更新 Firebase，新增影片數量: ${filteredItems.length}，總數: ${_allVideos.length}');

          onDataUpdate(_allVideos);
          await dbRef.set(_allVideos);

          onStatusChange(
              '第 $currentPage 頁：新增 ${filteredItems.length} 個動畫，總計 ${_allVideos.length} 個');
          print('🔥 Firebase 更新成功！');
        } else {
          onStatusChange('第 $currentPage 頁：沒有發現新動畫');
        }

        if (!isBackground) {
          onLoadingChange(false);
        }
        _isBackgroundCrawling = false;
      } else {
        print('🔥 JavaScript 返回失敗，嘗試替代方法');
        await _tryAlternativeMethod();
      }
    } catch (e) {
      print('🔥 JavaScript 執行失敗: $e');
      if (!isBackground) {
        onLoadingChange(false);
      }
      _isBackgroundCrawling = false;
      onStatusChange('第 $currentPage 頁抓取錯誤: $e');
      await _tryAlternativeMethod();
    }
  }

  Future<void> _tryAlternativeMethod() async {
    onStatusChange('嘗試替代方法抓取資料...');

    try {
      final result = await webViewController.runJavaScriptReturningResult('''
        (function() {
          return new Promise((resolve) => {
            setTimeout(() => {
              console.log('使用替代方法搜尋...');
              
              // 直接搜尋所有包含圖片和連結的元素
              const allElements = document.querySelectorAll('*');
              const videos = [];
              
              for (let element of allElements) {
                const img = element.querySelector('img');
                const link = element.querySelector('a');
                
                if (img && link) {
                  const title = link.getAttribute('title') || 
                               img.getAttribute('alt') || 
                               link.innerText?.trim() || 
                               element.innerText?.trim()?.split('\\n')[0] || 
                               '未知標題';
                  
                  let href = link.getAttribute('href') || '';
                  if (href && !href.startsWith('http')) {
                    href = 'https://hanime1.me' + (href.startsWith('/') ? href : '/' + href);
                  }
                  
                  let imgSrc = img.getAttribute('src') || 
                              img.getAttribute('data-src') || 
                              img.getAttribute('data-lazy') || '';
                  if (imgSrc && !imgSrc.startsWith('http') && imgSrc.startsWith('/')) {
                    imgSrc = 'https://hanime1.me' + imgSrc;
                  }
                  
                  if (title && href && title.length > 2 && href.includes('hanime1.me')) {
                    videos.push({
                      id: videos.length + 1,
                      title: title.substring(0, 100), // 限制標題長度
                      detail_url: href,
                      img_url: imgSrc,
                      episodes: 'N/A'
                    });
                    
                    if (videos.length >= 20) break; // 限制數量
                  }
                }
              }
              
              console.log('替代方法找到', videos.length, '個影片');
              
              // 如果還是沒找到，嘗試第三種方法
              if (videos.length === 0) {
                console.log('嘗試第三種方法：搜尋所有連結...');
                
                const allLinks = document.querySelectorAll('a[href]');
                for (let link of allLinks) {
                  const href = link.getAttribute('href');
                  if (href && (href.includes('/watch/') || href.includes('/video/') || href.includes('/hentai/'))) {
                    const title = link.getAttribute('title') || 
                                 link.innerText?.trim() || 
                                 link.querySelector('img')?.getAttribute('alt') || 
                                 '未知標題';
                    
                    let fullHref = href;
                    if (!fullHref.startsWith('http')) {
                      fullHref = 'https://hanime1.me' + (fullHref.startsWith('/') ? fullHref : '/' + fullHref);
                    }
                    
                    const img = link.querySelector('img');
                    let imgSrc = '';
                    if (img) {
                      imgSrc = img.getAttribute('src') || 
                              img.getAttribute('data-src') || 
                              img.getAttribute('data-lazy') || '';
                      if (imgSrc && !imgSrc.startsWith('http') && imgSrc.startsWith('/')) {
                        imgSrc = 'https://hanime1.me' + imgSrc;
                      }
                    }
                    
                    if (title && title.length > 2) {
                      videos.push({
                        id: videos.length + 1,
                        title: title.substring(0, 100),
                        detail_url: fullHref,
                        img_url: imgSrc,
                        episodes: 'N/A'
                      });
                      
                      if (videos.length >= 20) break;
                    }
                  }
                }
                console.log('第三種方法找到', videos.length, '個影片');
              }
              
              resolve(JSON.stringify({ success: true, videos: videos }));
            }, 2000);
          });
        })();
      ''');

      print('🔥 JavaScript 執行完成，結果: ${result.toString().substring(0, 100)}...');
      String resultString = result.toString();
      dynamic data = jsonDecode(resultString);

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data['success'] == true) {
        List<dynamic> videos = data['videos'];
        final items = videos.map((v) => Map<String, dynamic>.from(v)).toList();

        if (items.isEmpty) {
          await _tryFinalMethod();
        } else {
          print('🔥 替代方法準備更新 Firebase，影片數量: ${items.length}');
          print('🔥 第一個影片: ${items.first}');
          onDataUpdate(items);
          onLoadingChange(false);
          onStatusChange('使用替代方法成功抓取 ${items.length} 個影片');
          try {
            await dbRef.set(items);
            print('🔥 替代方法 Firebase 更新成功！');
          } catch (e) {
            print('🔥 替代方法 Firebase 更新失敗: $e');
            onStatusChange('替代方法 Firebase 更新失敗: $e');
          }
        }
      } else {
        await _tryFinalMethod();
      }
    } catch (e) {
      onLoadingChange(false);
      onStatusChange('替代方法失敗: $e');
      await _tryFinalMethod();
    }
  }

  Future<void> _tryFinalMethod() async {
    onStatusChange('使用最終方法抓取資料...');

    try {
      // 創建一些測試資料，確保至少有一些內容
      // 移除測試數據，只有無法抓取時才顯示空列表
      onDataUpdate([]);
      onLoadingChange(false);
      onStatusChange('無法抓取動畫列表，請檢查網路連接或稍後再試');
    } catch (e) {
      onLoadingChange(false);
      onStatusChange('所有方法都失敗了: $e');
    }
  }

  Future<String?> extractPlayUrl() async {
    try {
      print('🔥 開始提取播放地址，等待頁面完全載入...');

      // 增加等待時間，確保動畫網站完全載入
      await Future.delayed(const Duration(seconds: 10));

      // 先執行調試檢查
      await _debugPageStructure();

      final result = await webViewController.runJavaScriptReturningResult('''
        (function() {
          console.log('開始搜尋播放地址...');
          
          // 方法1: 檢查全域變數 hlsUrl（類似真人影片）
          if (typeof window.hlsUrl !== 'undefined') {
            console.log('找到 hlsUrl:', window.hlsUrl);
            return JSON.stringify({ success: true, url: window.hlsUrl, source: 'hlsUrl' });
          }
          
          // 方法2: 檢查其他常見的動畫網站全域變數
          const globalVars = [
            'videoUrl', 'playUrl', 'streamUrl', 'mp4Url', 'video_url', 'play_url',
            'sourceUrl', 'mediaUrl', 'videoSrc', 'src', 'videoSource',
            'hls_url', 'stream_url', 'video_link', 'anime_url'
          ];
          for (let varName of globalVars) {
            if (typeof window[varName] !== 'undefined' && window[varName]) {
              console.log('找到全域變數', varName + ':', window[varName]);
              return JSON.stringify({ success: true, url: window[varName], source: varName });
            }
          }
          
          // 方法3: 搜尋 script 標籤中的播放地址
          const scripts = Array.from(document.scripts);
          for (let script of scripts) {
            const content = script.innerText || script.innerHTML || '';
            
            // 搜尋各種可能的模式
            const patterns = [
              /var\\s+hlsUrl\\s*=\\s*['"]([^'"]+)['"]/,
              /var\\s+videoUrl\\s*=\\s*['"]([^'"]+)['"]/,
              /var\\s+playUrl\\s*=\\s*['"]([^'"]+)['"]/,
              /"videoUrl"\\s*:\\s*"([^"]+)"/,
              /"playUrl"\\s*:\\s*"([^"]+)"/,
              /"src"\\s*:\\s*"([^"]+)"/,
              /source\\s*:\\s*['"]([^'"]+)['"]/,
              /src\\s*:\\s*['"]([^'"]+)['"]/
            ];
            
            for (let pattern of patterns) {
              const match = content.match(pattern);
              if (match && match[1]) {
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
          
          // 方法5: 搜尋頁面中的各種影片格式 URL
          const pageContent = document.documentElement.outerHTML;
          const urlPatterns = [
            /https?:\\/\\/[^\\s"'<>]+\\.m3u8[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]+\\.mp4[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]+\\.webm[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]+\\.mkv[^\\s"'<>]*/,
            /https?:\\/\\/[^\\s"'<>]+\\.avi[^\\s"'<>]*/
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
            if (iframe.src && iframe.src.includes('player')) {
              console.log('找到播放器 iframe:', iframe.src);
              return JSON.stringify({ success: true, url: iframe.src, source: 'iframe' });
            }
          }
          
          console.log('沒有找到播放地址');
          return JSON.stringify({ success: false, error: '沒有找到播放地址' });
        })();
      ''');

      print('🔥 JavaScript 執行結果: ${result.toString()}');

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

  // 重試提取播放地址
  Future<String?> _retryExtractPlayUrl() async {
    try {
      print("🔄 重試提取播放地址...");
      await Future.delayed(const Duration(seconds: 2));

      // 嘗試重新載入頁面並提取
      await webViewController.reload();
      await Future.delayed(const Duration(seconds: 5));

      // 再次嘗試提取
      return await extractPlayUrl();
    } catch (e) {
      print("❌ 重試失敗: $e");
      return await _generateTestUrl();
    }
  }

  // 移除測試URL，確保僅使用真實提取的地址
  Future<String?> _generateTestUrl() async {
    print("❌ 無法提取播放地址，不使用後備方案");
    return null;
  }

  Future<void> _debugPageStructure() async {
    try {
      print('🔍 開始調試頁面結構...');

      final debugResult =
          await webViewController.runJavaScriptReturningResult('''
        (function() {
          const debug = {
            title: document.title,
            url: window.location.href,
            videos: document.querySelectorAll('video').length,
            iframes: document.querySelectorAll('iframe').length,
            scripts: document.querySelectorAll('script').length,
            links: [],
            possiblePlayers: []
          };
          
          // 檢查所有 iframe
          document.querySelectorAll('iframe').forEach((iframe, index) => {
            debug.links.push({
              type: 'iframe',
              src: iframe.src,
              id: iframe.id,
              classes: iframe.className
            });
          });
          
          // 檢查所有可能的播放器元素
          const playerSelectors = [
            '#player', '.player', '#video-player', '.video-player',
            '#vplayer', '.vplayer', '#dplayer', '.dplayer',
            '[id*="player"]', '[class*="player"]'
          ];
          
          playerSelectors.forEach(selector => {
            const elements = document.querySelectorAll(selector);
            if (elements.length > 0) {
              elements.forEach(el => {
                debug.possiblePlayers.push({
                  selector: selector,
                  tag: el.tagName,
                  id: el.id,
                  classes: el.className,
                  innerHTML: el.innerHTML.substring(0, 200)
                });
              });
            }
          });
          
          // 檢查所有全域變數
          const globalVars = [];
          for (let key in window) {
            if (key.toLowerCase().includes('video') || 
                key.toLowerCase().includes('player') ||
                key.toLowerCase().includes('stream') ||
                key.toLowerCase().includes('hls') ||
                key.toLowerCase().includes('url')) {
              try {
                const value = window[key];
                if (typeof value === 'string' && value.includes('http')) {
                  globalVars.push({ key: key, value: value });
                }
              } catch(e) {}
            }
          }
          debug.globalVars = globalVars;
          
          return JSON.stringify(debug);
        })();
      ''');

      print('🔍 調試結果: $debugResult');
    } catch (e) {
      print('🔍 調試失敗: $e');
    }
  }
}
