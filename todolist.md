這個計畫的核心思想是：

單一資料來源 (Single Source of Truth)：VideoRepository 將成為應用程式中唯一獲取影片資料的來源。
本地優先 (Offline-First)：應用程式啟動時，所有資料都從本地 SQLite 資料庫載入，確保即使在沒有網路的情況下也能正常運作。
關注點分離 (Separation of Concerns)：
爬蟲 (Crawlers)：只負責從網站抓取資料並返回，不直接與任何資料庫互動。
本地儲存 (LocalStorageService)：只負責 SQLite 的所有讀寫操作。
倉儲 (VideoRepository)：作為中間人，協調爬蟲、本地儲存和 UI 之間的資料流。
UI (HomePage, etc.)：只與 VideoRepository 互動來獲取資料和觸發操作。
專案重構修改計畫 (Todolist)
階段一：重構資料來源與爬蟲
目標： 讓爬蟲與資料庫脫鉤，並強化本地儲存。

[ ] 1. 修改 real_crawler.dart 和 anime_crawler.dart

目的：移除對 Firebase 的直接依賴，讓爬蟲變成一個純粹的資料抓取工具。
操作：
移除 DatabaseReference dbRef、onDataUpdate 和 onLoadingChange 參數。
修改 extractVideoData 方法，使其不再寫入 Firebase，而是 return Future<List<Map<String, dynamic>>>，將抓取到的資料返回。
[ ] 2. 增強 local_storage_service.dart

目的：新增一個更有效率的儲存方法，用於增量更新，而不是每次都清空再插入。
操作：
新增一個 saveVideos(List<VideoModel> videos) 方法，使用 insert 搭配 conflictAlgorithm: ConflictAlgorithm.replace 來實現新增或更新（upsert）操作。
[ ] 3. 大幅重構 services/video_repository.dart

目的：將 VideoRepository 確立為本地資料的唯一管理者。
操作：
移除對 FirebaseService 的直接依賴。雲端同步功能可以保留，但作為一個明確的、可選的操作。
修改 initialize() 方法，使其只從 LocalStorageService 載入初始資料。
新增一個核心方法 crawlAndSaveVideos(VideoType type)，此方法將負責：
根據傳入的 type 決定使用 RealCrawler 或 AnimeCrawler。
執行爬蟲並獲取返回的影片資料 List<Map<String, dynamic>>。
將 Map 轉換為 VideoModel。
呼叫 LocalStorageService 的新方法 saveVideos 將資料存入 SQLite。
重新從 SQLite 載入所有影片，並更新記憶體中的快取 (_cachedVideos) 和對外廣播的 Stream。
修改 loadRealVideos() 和 loadAnimeVideos() 方法，使其觸發新的 crawlAndSaveVideos 流程。
階段二：整合 UI 與新資料流程
目標： 移除 UI 層對 Firebase 的依賴，並串接新的資料流。

[ ] 4. 修改 main_new.dart

目的：簡化應用程式的初始化流程。
操作：
在 _AppWrapperState 的 _initializeServices 中，移除 FirebaseService 的初始化和傳遞。
只需初始化 VideoRepository，它會在內部自行處理本地資料的載入。
[ ] 5. 修改 features/tv/pages/home_page.dart

目的：讓主頁完全透過 VideoRepository 獲取資料。
操作：
從 HomePage 的建構子和 _HomePageState 中移除 firebaseService。
確保所有資料載入（如 _loadVideos）和過濾都基於 VideoRepository 的 Stream 或快取資料。
[ ] 6. 修改 features/tv/widgets/control_panel.dart

目的：將「重新載入」按鈕的功能對應到新的爬蟲流程。
操作：
修改 _refreshData 方法，使其不再呼叫舊的 loadRealVideos 和 loadAnimeVideos。
改為呼叫 videoRepository.crawlAndSaveVideos(VideoType.real) 和 videoRepository.crawlAndSaveVideos(VideoType.anime)。
階段三：清理與驗證
目標： 移除無用程式碼，確保新架構穩定。

[ ] 7. 全專案審查

目的：尋找並移除殘留的 FirebaseService 或 FirebaseDatabase 直接呼叫。
操作：
特別檢查 main.dart (舊版入口) 和 video_player_page.dart 是否還有不必要的 Firebase 依賴。
[ ] 8. 移除 Firebase 相關套件 (可選)

目的：如果確認不再需要任何 Firebase 功能（包括雲端更新），可以徹底清理。
操作：
從 pubspec.yaml 中移除 firebase_core 和 firebase_database。
刪除 firebase_options.dart 檔案。
