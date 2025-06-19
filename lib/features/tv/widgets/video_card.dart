import 'package:flutter/material.dart';
import '../../../shared/models/video_model.dart';
import '../../../core/constants/app_constants.dart';
import '../pages/video_player_page.dart';

class VideoCard extends StatefulWidget {
  final VideoModel video;
  final VoidCallback? onTap;
  final bool isFocused;

  const VideoCard({
    super.key,
    required this.video,
    this.onTap,
    this.isFocused = false,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: AppConstants.cardAnimationDuration,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _elevationAnimation = Tween<double>(
      begin: 2.0,
      end: 8.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(VideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFocused != oldWidget.isFocused) {
      if (widget.isFocused) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  void _handleTap() {
    if (widget.onTap != null) {
      widget.onTap!();
    } else {
      // 導航到影片播放頁面
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoPlayerPage(video: widget.video),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Card(
            elevation: _elevationAnimation.value,
            color: widget.isFocused 
                ? AppConstants.focusedCardColor 
                : AppConstants.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.cardBorderRadius),
              side: widget.isFocused
                  ? const BorderSide(
                      color: AppConstants.primaryColor,
                      width: 2,
                    )
                  : BorderSide.none,
            ),
            child: InkWell(
              onTap: _handleTap,
              borderRadius: BorderRadius.circular(AppConstants.cardBorderRadius),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 影片縮圖
                  Expanded(
                    flex: 3,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppConstants.cardBorderRadius),
                        ),
                        color: Colors.grey[800],
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppConstants.cardBorderRadius),
                        ),
                        child: widget.video.thumbnailUrl != null &&
                                widget.video.thumbnailUrl!.isNotEmpty
                            ? Image.network(
                                widget.video.thumbnailUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return _buildPlaceholder();
                                },
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded /
                                              loadingProgress.expectedTotalBytes!
                                          : null,
                                      valueColor: const AlwaysStoppedAnimation<Color>(
                                        AppConstants.primaryColor,
                                      ),
                                    ),
                                  );
                                },
                              )
                            : _buildPlaceholder(),
                      ),
                    ),
                  ),
                  
                  // 影片資訊
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(AppConstants.smallPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 標題
                          Text(
                            widget.video.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: widget.isFocused ? Colors.white : null,
                            ),
                          ),
                          
                          const Spacer(),
                          
                          // 類型標籤
                          if (widget.video.type != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: widget.video.type == VideoType.real
                                    ? AppConstants.realVideoColor
                                    : AppConstants.animeVideoColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.video.type == VideoType.real ? '真人' : '動漫',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_outline,
              size: 40,
              color: Colors.grey,
            ),
            SizedBox(height: 8),
            Text(
              '無縮圖',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 