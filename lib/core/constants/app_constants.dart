// 應用程式常數定義
class AppConstants {
  // 顏色定義
  static const int backgroundColor = 0xFF0A0A0F;
  static const int cardBackgroundColor = 0xFF1A1A2E;
  static const int dialogBackgroundColor = 0xFF16213E;
  static const int primaryColor = 0xFF6750A4;
  static const int secondaryColor = 0xFFFF6B9D;
  static const int tertiaryColor = 0xFF4ECDC4;
  
  // 尺寸定義
  static const double defaultBorderRadius = 8.0;
  static const double cardBorderRadius = 12.0;
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  static const double controlPanelWidth = 300.0;
  
  // 動畫時間
  static const Duration cardAnimationDuration = Duration(milliseconds: 200);
  static const Duration pageTransitionDuration = Duration(milliseconds: 300);
  static const int shortAnimationDuration = 200;
  static const int mediumAnimationDuration = 300;
  static const int longAnimationDuration = 500;
  
  // 網格設定
  static const int minGridColumns = 2;
  static const int maxGridColumns = 6;
  static const double cardAspectRatio = 16 / 9;
  
  // Firebase 節點名稱
  static const String videosNode = 'videos';
  static const String animeVideosNode = 'anime_videos';
  static const String favoritesNode = 'favorites';
  static const String latestVersionNode = 'latest_version_info';
  static const String realVideosNode = 'realVideos';
  static const String appInfoNode = 'appInfo';
  
  // 文字大小
  static const double titleFontSize = 24.0;
  static const double subtitleFontSize = 18.0;
  static const double bodyFontSize = 16.0;
  static const double captionFontSize = 14.0;
  
  // 顏色常數
  static const int cardColor = 0xFF1E1E1E;
  static const int focusedCardColor = 0xFF2A2A2A;
  static const int realVideoColor = 0xFF4CAF50;
  static const int animeVideoColor = 0xFF2196F3;
  
  // 其他常數
  static const int maxCacheSize = 1000;
  static const Duration cacheExpiry = Duration(hours: 24);
  
  // 應用程式資訊
  static const String appName = 'VideoTV';
  static const String appVersion = '1.1.0';
  
  // URL 常數
  static const String updateCheckUrl = 'https://api.github.com/repos/username/videotv/releases/latest';
  
  // 私有建構子，確保這是一個純靜態類別
  AppConstants._();
}

// 應用程式字串常數
class AppStrings {
  static const String appTitle = 'VideoTV';
  static const String loadingMessage = '正在處理中...';
  static const String noDataMessage = '尚無影片資料';
  static const String noDataSubtitle = '開啟選單開始爬取影片';
  static const String favoriteVideos = '收藏影片';
  static const String allVideos = '全部影片';
  static const String realVideos = '真人影片爬蟲';
  static const String animeVideos = '動畫影片爬蟲';
  static const String settings = '設定';
  static const String checkUpdate = '檢查更新';
  static const String about = '關於應用程式';
  
  // 私有建構子
  AppStrings._();
}

// 資產路徑常數
class AppAssets {
  // 圖標路徑
  static const String appIcon = 'assets/icon/foreground.png';
  static const String backgroundIcon = 'assets/icon/background.png';
  
  // 私有建構子
  AppAssets._();
} 