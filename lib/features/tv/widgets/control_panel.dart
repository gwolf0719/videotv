import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/video_model.dart';
import '../../../services/video_repository.dart';

class ControlPanel extends StatelessWidget {
  final FocusNode focusNode;
  final VideoType currentFilter;
  final Function(VideoType) onFilterChanged;
  final bool isFocused;
  final VideoRepository videoRepository;

  const ControlPanel({
    super.key,
    required this.focusNode,
    required this.currentFilter,
    required this.onFilterChanged,
    this.isFocused = false,
    required this.videoRepository,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppConstants.controlPanelWidth,
      color: Colors.black.withOpacity(0.8),
      child: Column(
        children: [
          // 標題
          Container(
            padding: const EdgeInsets.all(AppConstants.defaultPadding),
            child: Text(
              AppConstants.appName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: const Color(AppConstants.primaryColor),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          // 過濾選項
          Expanded(
            child: ListView(
              children: [
                _buildFilterTile(
                  context,
                  VideoType.real,
                  '真人影片',
                  Icons.movie,
                ),
                _buildFilterTile(
                  context,
                  VideoType.anime,
                  '動漫影片',
                  Icons.animation,
                ),
                
                const Divider(color: Colors.white24),
                
                // 功能按鈕
                _buildActionTile(
                  context,
                  '重新載入',
                  Icons.refresh,
                  () => _refreshData(),
                ),
                
                _buildActionTile(
                  context,
                  '關於',
                  Icons.info,
                  () => _showAbout(context),
                ),
              ],
            ),
          ),
          
          // 底部狀態
          Container(
            padding: const EdgeInsets.all(AppConstants.defaultPadding),
            child: Text(
              '版本 ${AppConstants.appVersion}',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTile(
    BuildContext context,
    VideoType type,
    String title,
    IconData icon,
  ) {
    final isSelected = currentFilter == type;
    
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected 
            ? const Color(AppConstants.primaryColor)
            : Colors.white70,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected 
              ? const Color(AppConstants.primaryColor)
              : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: const Color(AppConstants.primaryColor).withOpacity(0.1),
      onTap: () => onFilterChanged(type),
    );
  }

  Widget _buildActionTile(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white70),
      ),
      onTap: onTap,
    );
  }

  void _refreshData() {
    videoRepository.crawlAndSaveVideos();
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('關於 VideoTV'),
        content: Text('VideoTV ${AppConstants.appVersion}\n\n一個功能豐富的影片管理應用程式'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }
} 