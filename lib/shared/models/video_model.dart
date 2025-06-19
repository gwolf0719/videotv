enum VideoType {
  real,
  anime,
}

extension VideoTypeExtension on VideoType {
  String get displayName {
    switch (this) {
      case VideoType.real:
        return '真人影片';
      case VideoType.anime:
        return '動畫影片';
    }
  }
}

class VideoModel {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final String? videoUrl; // 詳細頁面 URL
  final VideoType? type;
  final DateTime? addedAt;
  final Map<String, dynamic>? metadata;

  const VideoModel({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.videoUrl,
    this.type,
    this.addedAt,
    this.metadata,
  });

  // 顯示標題（移除多餘空白和特殊字符）
  String get displayTitle {
    return title.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  // 是否有縮圖
  bool get hasThumbnail {
    return thumbnailUrl != null && thumbnailUrl!.isNotEmpty;
  }

  // 是否有影片連結
  bool get hasVideoUrl {
    return videoUrl != null && videoUrl!.isNotEmpty;
  }

  // 兼容性：是否為動漫
  bool get isAnime {
    return type == VideoType.anime;
  }

  // 從 Map 建立實例
  factory VideoModel.fromMap(Map<String, dynamic> map) {
    return VideoModel(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      thumbnailUrl: map['thumbnailUrl']?.toString() ?? map['img_url']?.toString(),
      videoUrl: map['videoUrl']?.toString() ?? map['detail_url']?.toString(),
      type: _parseVideoType(map['type']?.toString()),
      addedAt: map['addedAt'] != null ? DateTime.tryParse(map['addedAt'].toString()) : null,
      metadata: map['metadata'] is Map<String, dynamic> ? map['metadata'] : null,
    );
  }

  // 轉換為 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
      'videoUrl': videoUrl,
      'type': type?.name,
      'addedAt': addedAt?.toIso8601String(),
      'metadata': metadata,
    };
  }

  // 解析影片類型
  static VideoType? _parseVideoType(String? typeString) {
    if (typeString == null) return null;
    
    switch (typeString.toLowerCase()) {
      case 'real':
      case '真人':
        return VideoType.real;
      case 'anime':
      case '動漫':
      case '動畫':
        return VideoType.anime;
      default:
        return null;
    }
  }

  // 複製並修改屬性
  VideoModel copyWith({
    String? id,
    String? title,
    String? thumbnailUrl,
    String? videoUrl,
    VideoType? type,
    DateTime? addedAt,
    Map<String, dynamic>? metadata,
    bool? isAnime, // 兼容性參數
  }) {
    VideoType? finalType = type ?? this.type;
    
    // 兼容性處理
    if (isAnime != null) {
      finalType = isAnime ? VideoType.anime : VideoType.real;
    }
    
    return VideoModel(
      id: id ?? this.id,
      title: title ?? this.title,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      type: finalType,
      addedAt: addedAt ?? this.addedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VideoModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'VideoModel(id: $id, title: $title, type: $type)';
  }
} 