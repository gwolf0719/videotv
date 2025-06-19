import 'package:flutter/material.dart';
import '../../../shared/models/video_model.dart';
import '../../../core/constants/app_constants.dart';
import 'video_card.dart';

class VideoGrid extends StatelessWidget {
  final List<VideoModel> videos;
  final Function(VideoModel) onVideoTap;
  final ScrollController? scrollController;
  final int crossAxisCount;
  final double childAspectRatio;
  final double spacing;

  const VideoGrid({
    super.key,
    required this.videos,
    required this.onVideoTap,
    this.scrollController,
    this.crossAxisCount = AppConstants.gridCrossAxisCount,
    this.childAspectRatio = AppConstants.gridChildAspectRatio,
    this.spacing = AppConstants.gridSpacing,
  });

  @override
  Widget build(BuildContext context) {
    if (videos.isEmpty) {
      return _buildEmptyState(context);
    }

    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        return VideoCard(
          video: video,
          onTap: () => onVideoTap(video),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.3),
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.video_library_outlined,
              size: 80,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppConstants.largePadding),
          Text(
            '尚無影片資料',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: AppConstants.smallPadding),
          Text(
            '開啟選單開始爬取影片',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class ResponsiveVideoGrid extends StatelessWidget {
  final List<VideoModel> videos;
  final Function(VideoModel) onVideoTap;
  final ScrollController? scrollController;

  const ResponsiveVideoGrid({
    super.key,
    required this.videos,
    required this.onVideoTap,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount;
        double childAspectRatio;

        // 響應式網格設計
        if (width > 1200) {
          crossAxisCount = 6;
          childAspectRatio = 0.7;
        } else if (width > 800) {
          crossAxisCount = 4;
          childAspectRatio = 0.75;
        } else if (width > 600) {
          crossAxisCount = 3;
          childAspectRatio = 0.8;
        } else {
          crossAxisCount = 2;
          childAspectRatio = 0.85;
        }

        return VideoGrid(
          videos: videos,
          onVideoTap: onVideoTap,
          scrollController: scrollController,
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
        );
      },
    );
  }
} 