import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/video_model.dart';
import '../../../services/video_repository.dart';
import '../../../services/firebase_service.dart';

class ControlPanel extends StatefulWidget {
  final FocusNode focusNode;
  final VideoType currentFilter;
  final Function(VideoType) onFilterChanged;
  final bool isFocused;
  final VideoRepository videoRepository;
  final FirebaseService firebaseService;

  const ControlPanel({
    super.key,
    required this.focusNode,
    required this.currentFilter,
    required this.onFilterChanged,
    required this.isFocused,
    required this.videoRepository,
    required this.firebaseService,
  });

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  bool _isAdvancedMode = false;
  bool _isCrawling = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        border: Border(
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題
            _buildHeader(),
            const SizedBox(height: AppConstants.largePadding),

            // 篩選器
            _buildFilterSection(),
            const SizedBox(height: AppConstants.largePadding),

            // 功能按鈕
            _buildActionButtons(),
            
            // 高級功能
            if (_isAdvancedMode) ...[
              const SizedBox(height: AppConstants.largePadding),
              _buildAdvancedSection(),
            ],

            const Spacer(),

            // 底部資訊
            _buildBottomInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppConstants.appName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: AppConstants.titleFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '控制面板',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: AppConstants.smallFontSize,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '影片類型',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: AppConstants.bodyFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppConstants.smallPadding),
        _buildFilterButton(VideoType.real),
        const SizedBox(height: 8),
        _buildFilterButton(VideoType.anime),
      ],
    );
  }

  Widget _buildFilterButton(VideoType type) {
    final isSelected = widget.currentFilter == type;
    
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => widget.onFilterChanged(type),
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected 
              ? const Color(AppConstants.primaryColor)
              : Colors.white.withValues(alpha: 0.1),
          foregroundColor: Colors.white,
          elevation: isSelected ? 4 : 0,
          side: BorderSide(
            color: isSelected 
                ? const Color(AppConstants.primaryColor)
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Text(type.displayName),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '功能',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: AppConstants.bodyFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppConstants.smallPadding),
        
        // 刷新按鈕
        _buildActionButton(
          icon: Icons.refresh,
          label: '重新載入',
          onPressed: _refreshData,
        ),
        const SizedBox(height: 8),
        
        // 設定按鈕
        _buildActionButton(
          icon: Icons.settings,
          label: '設定',
          onPressed: _showSettings,
        ),
        const SizedBox(height: 8),
        
        // 高級功能切換
        _buildActionButton(
          icon: _isAdvancedMode ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          label: _isAdvancedMode ? '隱藏高級功能' : '顯示高級功能',
          onPressed: () {
            setState(() {
              _isAdvancedMode = !_isAdvancedMode;
            });
          },
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }

  Widget _buildAdvancedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '高級功能',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: AppConstants.bodyFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppConstants.smallPadding),
        
        // 爬蟲功能
        _buildActionButton(
          icon: _isCrawling ? Icons.stop : Icons.cloud_download,
          label: _isCrawling ? '停止爬取' : '開始爬取資料',
          onPressed: _isCrawling ? _stopCrawling : _startCrawling,
        ),
        const SizedBox(height: 8),
        
        // 清除快取
        _buildActionButton(
          icon: Icons.cleaning_services,
          label: '清除快取',
          onPressed: _clearCache,
        ),
        const SizedBox(height: 8),
        
        // 版本資訊
        _buildActionButton(
          icon: Icons.info,
          label: '版本資訊',
          onPressed: _showVersionInfo,
        ),
      ],
    );
  }

  Widget _buildBottomInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppConstants.smallPadding),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppConstants.defaultBorderRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Firebase 狀態',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: AppConstants.captionFontSize,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    widget.firebaseService.isAvailable 
                        ? Icons.cloud_done 
                        : Icons.cloud_off,
                    color: widget.firebaseService.isAvailable 
                        ? Colors.green 
                        : Colors.orange,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.firebaseService.isAvailable ? '已連接' : '離線模式',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: AppConstants.captionFontSize,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _refreshData() async {
    try {
      if (widget.currentFilter == VideoType.real) {
        await widget.videoRepository.loadRealVideos();
      } else {
        await widget.videoRepository.loadAnimeVideos();
      }
      
      _showToast('資料重新載入完成');
    } catch (e) {
      _showToast('重新載入失敗: $e');
    }
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(AppConstants.dialogBackgroundColor),
        title: const Text('設定', style: TextStyle(color: Colors.white)),
        content: const Text(
          '設定功能開發中...',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  void _startCrawling() async {
    setState(() {
      _isCrawling = true;
    });

    try {
      _showToast('開始爬取資料...');
      
      // 模擬爬取過程
      await Future.delayed(const Duration(seconds: 3));
      
      // 這裡可以添加實際的爬蟲邏輯
      // await _performCrawling();
      
      _showToast('資料爬取完成');
    } catch (e) {
      _showToast('爬取失敗: $e');
    } finally {
      setState(() {
        _isCrawling = false;
      });
    }
  }

  void _stopCrawling() {
    setState(() {
      _isCrawling = false;
    });
    _showToast('已停止爬取');
  }

  void _clearCache() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(AppConstants.dialogBackgroundColor),
        title: const Text('清除快取', style: TextStyle(color: Colors.white)),
        content: const Text(
          '確定要清除所有快取資料嗎？',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performClearCache();
            },
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  void _performClearCache() {
    // 這裡可以添加清除快取的邏輯
    _showToast('快取已清除');
  }

  void _showVersionInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(AppConstants.dialogBackgroundColor),
            title: const Text('版本資訊', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('應用名稱: ${info.appName}', style: const TextStyle(color: Colors.white70)),
                Text('版本: ${info.version}', style: const TextStyle(color: Colors.white70)),
                Text('建置號: ${info.buildNumber}', style: const TextStyle(color: Colors.white70)),
                Text('套件名稱: ${info.packageName}', style: const TextStyle(color: Colors.white70)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('確定'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showToast('無法獲取版本資訊');
    }
  }

  void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }
} 