**整體應用程式目的：**

"VideoTV" 應用程式設計為一個影片瀏覽和播放平台，主要針對電視使用。它允許使用者：
* 從外部網站擷取（爬取）「真人」和「裏番動畫」內容的影片資訊（標題、圖片、串流網址）。
* 使用 Firebase 即時資料庫儲存和擷取這些影片資訊。
* 以網格佈局瀏覽已擷取的影片。
* 檢視影片詳細資訊。
* 使用原生影片播放器播放影片。
* 管理喜愛的影片清單。
* 從 Firebase 檢查並下載應用程式更新（APK）。

**核心元件與服務：**

1.  **Firebase 整合 (`firebase_options.dart`, `main.dart`):**
    * **初始化：** 應用程式使用 `Firebase.initializeApp` 並根據 `DefaultFirebaseOptions.currentPlatform` 中的設定初始化 Firebase。
    * **資料庫結構：**
        * `videos`: 儲存由 `RealCrawler` 爬取的「真人」影片元數據。
        * `anime_videos`: 儲存由 `AnimeCrawler` 爬取的「動畫」影片元數據。
        * `favorites`: 儲存使用者標記為喜愛的影片清單。
        * `latest_version_info`: 儲存最新應用程式版本的資訊（`latest_version`, `apk_url`），用於更新機制。

2.  **網路爬蟲 (`real_crawler.dart`, `anime_crawler.dart`):**
    * **目的：** 這些類別負責使用隱藏的 `WebViewController` 從特定網站擷取影片資料。
    * **機制：**
        * 它們將目標網址載入到 `WebViewController` 中。
        * 頁面載入完成後，它們執行 JavaScript 程式碼 (`runJavaScriptReturningResult`) 來解析 HTML，擷取影片元數據（標題、詳細頁面網址、圖片網址），有時也擷取直接的影片串流網址。
        * 新的影片資料會與 Firebase 中的現有資料進行比較以避免重複，然後儲存回 Firebase。
        * 它們管理分頁功能，以便爬取網站的多個頁面。
    * **`RealCrawler`**:
        * 目標網站為 `jable.tv/categories/chinese-subtitle/`。
        * 透過尋找具有 `.video-img-box` 類別的元素來擷取影片資訊。
        * 嘗試在影片詳細頁面上尋找直接播放網址（例如 `hlsUrl` 或 M3U8 連結）。
    * **`AnimeCrawler`**:
        * 目標網站為 `hanime1.me/search?genre=%E8%A3%8F%E7%95%AA`。
        * 透過尋找 `a[href*="/watch"]` 連結來擷取影片資訊，如果主要 JavaScript 失敗，則有多種備用方法，包括使用預留位置測試資料。
        * 由於目標網站的潛在複雜性，它採用更廣泛的搜尋方法來尋找播放網址，包括尋找各種全域 JavaScript 變數、常見的影片 HTML 標籤（`<video>`、`<source>`）、針對影片檔案副檔名（M3U8、MP4、WEBM）的正規表示式比對，以及檢查 `<iframe>` 元素。它還包括一個用於檢查頁面結構的偵錯功能，並可在最後手段時傳回測試網址。

3.  **主要應用程式介面與邏輯 (`main.dart`):**

    * **`MyApp` (StatelessWidget):**
        * 設定 `MaterialApp`，應用程式標題為 "VideoTV"。
        * 定義了一個適合電視觀看的深色主題，包含自訂的色彩配置、卡片主題、應用程式列主題、文字主題、按鈕主題和輸入框裝飾主題。
        * 將 `MyHomePage` 設定為首頁。

    * **`_MyHomePageState` (StatefulWidget State):** 這是應用程式介面和互動邏輯的核心。

        * **初始化 (`initState`)**:
            * 透過 toast 訊息顯示應用程式版本。
            * 初始化供爬蟲使用的 `WebViewController`。
            * 預設從 Firebase 載入喜愛的影片。
            * 初始化選單中供電視遙控器導覽使用的 `FocusNode`。

        * **主要使用者操作與介面描述：**

            * **應用程式啟動與初始畫面：**
                * 應用程式啟動時會載入並顯示喜愛的影片清單 (`_loadFavoriteVideos`)。如果沒有喜愛的影片或仍在載入中，則顯示空白狀態或載入指示器。
                * Toast 訊息會顯示目前的應用程式版本。
                * 介面主要是一個影片卡片網格 (`_buildVideoGrid`)。
                * 使用 `BackgroundPatternPainter` 繪製背景圖案。

            * **導覽與控制 (電視遙控器焦點)：**
                * **返回按鈕：** 按下遙控器上的返回按鈕（或返回手勢）會開啟右側抽屜選單 (`_scaffoldKey.currentState?.openEndDrawer()`)，而不是直接結束應用程式。這由 `WillPopScope` 管理。
                * **焦點管理：** 應用程式廣泛使用 `FocusNode`，以便使用電視遙控器上的方向鍵/箭頭鍵在影片卡片和選單項目之間導覽。
                    * `_homeFocusNode`: 主畫面的主要焦點。
                    * `_menuFocusNodes`: 抽屜選單中每個項目的 `FocusNode` 陣列。
                    * 影片卡片 (`_buildVideoCard`) 和選單項目 (`_buildModernMenuTile`) 在獲得焦點時會改變外觀（例如，縮放、邊框、陰影）。
                * **選擇：** 在焦點項目上按下選擇/確認/空白鍵會觸發其操作（例如，開啟影片詳細資訊、啟動選單選項）。

            * **側邊抽屜選單 (`_buildModernDrawer`):**
                * 透過按下「返回」按鈕存取。
                * 顯示選項：
                    * **「收藏影片」：** 載入並僅顯示已收藏的影片。初始為啟用狀態。
                    * **「真人影片」：** 啟動 `_startCrawling()` 程序，使用 `RealCrawler` 從 `jable.tv` 擷取影片。
                    * **「裏番動畫」：** 啟動 `_startAnimeCrawling()` 程序，使用 `AnimeCrawler` 從 `hanime1.me` 擷取影片。
                    * **「軟體更新」：** 呼叫 `_checkForUpdate()` 以檢查 Firebase 是否有新的 APK 版本。
                    * **「退出APP」：** 呼叫 `_showExitAppDialog()` 以確認，然後使用 `SystemNavigator.pop()` 關閉應用程式。
                * 如果爬蟲正在運作，則顯示載入指示器和狀態訊息 (`_statusMessage`)。
                * 每個選單項目 (`_buildModernMenuTile`) 都可聚焦且風格適合電視。

            * **影片爬取過程：**
                * 使用者從選單中選擇「真人影片」或「裏番動畫」。
                * 顯示全螢幕載入過渡動畫 (`_buildLoadingTransition`)，並顯示類似「正在爬取真人影片...」的訊息。
                * 啟動對應的爬蟲（`_realCrawler` 或 `_animeCrawler`）。
                * 爬蟲將目標網站在隱藏的 WebView 中載入，執行 JavaScript 以擷取資料，更新 Firebase，並回呼 `_MyHomePageState` 以更新 `_items` 清單和狀態訊息。
                * 爬取完成後，載入過渡動畫會隱藏，應用程式會顯示新擷取的影片（例如，`_loadRealVideos()` 或 `_loadAnimeVideos()`）。

            * **顯示影片 (`_buildVideoGrid`, `_buildVideoCard`):**
                * 影片以 4 欄的 `GridView` 顯示。
                * 每個 `_buildVideoCard` 顯示：
                    * 影片縮圖（如果載入失敗/無網址，則顯示預留位置圖片）。
                    * 影片標題。
                    * 類型標籤（「真人」或「動畫」）。
                    * 如果影片在收藏中，則顯示紅色愛心收藏圖示。
                    * 焦點的視覺回饋（縮放、邊框、陰影、播放圖示覆蓋）。
                * 點擊/選擇卡片會呼叫 `_showVideoDetails()`。

            * **檢視影片詳細資訊 (`VideoDetailDialog`):**
                * 選擇影片卡片時會顯示此對話方塊。
                * **介面：**
                    * 顯示較大版本的影片縮圖（或預留位置圖片）。
                    * 顯示影片標題和 ID。
                    * 「加入收藏」/「取消收藏」按鈕：透過 `_toggleFavorite()` 切換影片在 Firebase 中的收藏狀態。根據 `isFavorite` 更新其自身外觀。
                    * 「立即播放」按鈕：呼叫 `_playVideoDirectly()`。
                    * 一個關閉按鈕。
                * 按鈕可供遙控器導覽聚焦，其中「立即播放」按鈕會自動聚焦。

            * **影片播放 (`_playVideoDirectly`, `VideoPlayerScreen`):**
                * 選擇「立即播放」時：
                    * 呼叫 `_playVideoDirectly()`。
                    * 顯示「正在準備播放...」的覆蓋層 (`_isVideoLoading`)。
                    * 應用程式將影片的 `detail_url` 載入到隱藏的 `WebViewController` 中。
                    * 然後呼叫相應爬蟲的 `extractPlayUrl()` 方法以取得直接的影片串流網址。
                    * 如果找到網址，則導覽至 `VideoPlayerScreen`。
                    * 如果找不到網址，則會出現一個對話方塊，詢問使用者是否要在外部瀏覽器中開啟 `detail_url`。
                * **`VideoPlayerScreen` 介面：**
                    * 使用 `VideoPlayerController` 顯示影片。
                    * **控制項 (`_buildControls`)：** 自動顯示/隱藏，或在點擊/按鍵時顯示/隱藏。
                        * 返回按鈕。
                        * 影片標題和類型標籤（「真人」/「動畫」）。
                        * 播放/暫停按鈕。
                        * 快轉/倒退 10 秒按鈕。
                        * 影片進度列（可拖曳）。
                        * 播放速度控制（循環播放速度：0.5x 到 2.0x）。
                        * 目前時間 / 總時間顯示。
                        * 全螢幕切換按鈕（僅視覺效果，未實作系統全螢幕切換）。
                    * **鍵盤控制：** 空白鍵/選擇鍵/確認鍵用於播放/暫停，左/右箭頭鍵用於快轉/倒退（支援長按以連續快轉/倒退），上/下箭頭鍵用於調整播放速度，Escape鍵/返回鍵用於結束播放器。
                    * **推薦影片：** `_buildRecommendedVideosForMobile()` 在播放器底部以水平清單顯示預留位置的推薦影片。實際的推薦邏輯尚未實作。

            * **管理收藏：**
                * **新增/移除：** 透過 `VideoDetailDialog` 中的「收藏」按鈕完成，該按鈕會呼叫 `_toggleFavorite()`。這會更新 Firebase 中的 `favorites` 路徑和本機的 `_favoriteItems` 清單。
                * **檢視：** 在抽屜選單中選擇「收藏影片」會將顯示的 `_items` 過濾為僅顯示 `_favoriteItems`。

            * **應用程式更新 (`_checkForUpdate`):**
                * 將本機應用程式版本 (`PackageInfo.fromPlatform()`) 與 Firebase `latest_version_info` 中的 `latest_version` 進行比較。
                * 如果有可用更新，則會顯示一個對話方塊，顯示目前/最新版本並提供下載選項。
                * **下載：**
                    * 使用 `Dio` 從 `apk_url`（來自 Firebase）下載 APK。
                    * 顯示 `LinearProgressIndicator` 和狀態文字以表示下載進度。
                    * 將 APK 儲存到外部儲存空間 (`getExternalStorageDirectory()`)。
                * **安裝：**
                    * 下載完成後，會出現「安裝/開啟」按鈕。
                    * 嘗試使用名為 'install_apk' 的 `MethodChannel`（適用於 Android，可能用於觸發 ACTION_INSTALL_PACKAGE intent）進行安裝。
                    * 如果方法通道失敗，則會退回使用 `OpenFile.open()` 讓系統處理 APK。

            * **錯誤處理與狀態訊息：**
                * 使用 `Fluttertoast` 顯示簡短訊息（例如，「已添加到收藏」、「版本：X.X.X」）。
                * `_statusMessage` 會更新介面（通常在抽屜選單中）以顯示爬蟲狀態。
                * 載入指示器（`_isLoading`, `_isVideoLoading`, `_isShowingLoadingTransition`）在操作期間提供視覺回饋。

        * **輔助 Widget/Painter：**
            * `BackgroundPatternPainter`: 在主畫面背景中繪製自訂的幾何圖案。

這個全面的概述應該涵蓋了您的 VideoTV 應用程式的主要操作和介面描述。核心流程包括使用側邊抽屜選單啟動爬取，在網格中瀏覽結果，檢視詳細資訊以及播放影片，所有這些都針對電視遙控器互動進行了最佳化。Firebase 作為後端，用於儲存影片元數據和管理應用程式更新。