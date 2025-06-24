import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/video_repository.dart';
import '../widgets/video_grid.dart';
import '../widgets/control_panel.dart';
import '../widgets/search_bar.dart';
import '../../../shared/widgets/background_pattern_widget.dart';

class HomePage extends StatefulWidget {
  final VideoRepository videoRepository;

  const HomePage({
    super.key,
    required this.videoRepository,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FocusNode _gridFocusNode = FocusNode();
  final FocusNode _controlPanelFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  
  bool _isControlPanelFocused = false;
  bool _isSearchFocused = false;
  VideoType _currentFilter = VideoType.real;
  String _searchQuery = '';
  List<VideoModel> _filteredVideos = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _setupFocusListeners();
  }

  void _initializeData() {
    // 監聽影片資料變化
    widget.videoRepository.realVideosStream.listen((videos) {
      if (_currentFilter == VideoType.real) {
        setState(() {
          _filteredVideos = _filterVideos(videos);
        });
      }
    });

    widget.videoRepository.animeVideosStream.listen((videos) {
      if (_currentFilter == VideoType.anime) {
        setState(() {
          _filteredVideos = _filterVideos(videos);
        });
      }
    });

    // 載入初始資料
    _loadVideos();
  }

  void _setupFocusListeners() {
    _controlPanelFocusNode.addListener(() {
      setState(() {
        _isControlPanelFocused = _controlPanelFocusNode.hasFocus;
      });
    });

    _searchFocusNode.addListener(() {
      setState(() {
        _isSearchFocused = _searchFocusNode.hasFocus;
      });
    });
  }

  void _loadVideos() {
    setState(() {
      _isLoading = true;
    });

    List<VideoModel> videos;
    if (_currentFilter == VideoType.real) {
      videos = widget.videoRepository.getCachedRealVideos();
    } else {
      videos = widget.videoRepository.getCachedAnimeVideos();
    }

    setState(() {
      _filteredVideos = _filterVideos(videos);
      _isLoading = false;
    });
  }

  List<VideoModel> _filterVideos(List<VideoModel> videos) {
    if (_searchQuery.isEmpty) {
      return videos;
    }
    
    final query = _searchQuery.toLowerCase();
    return videos.where((video) {
      return video.title.toLowerCase().contains(query);
    }).toList();
  }

  void _onFilterChanged(VideoType filter) {
    setState(() {
      _currentFilter = filter;
      _searchQuery = '';
    });
    _loadVideos();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
    _loadVideos();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowLeft:
          if (!_isControlPanelFocused && !_isSearchFocused) {
            _controlPanelFocusNode.requestFocus();
          }
          break;
        case LogicalKeyboardKey.arrowUp:
          if (!_isSearchFocused) {
            _searchFocusNode.requestFocus();
          }
          break;
        case LogicalKeyboardKey.arrowRight:
          if (_isControlPanelFocused || _isSearchFocused) {
            _gridFocusNode.requestFocus();
          }
          break;
        case LogicalKeyboardKey.arrowDown:
          if (_isSearchFocused) {
            _gridFocusNode.requestFocus();
          }
          break;
      }
    }
  }

  @override
  void dispose() {
    _gridFocusNode.dispose();
    _controlPanelFocusNode.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 背景圖案
            const BackgroundPatternWidget(),
            
            // 主要內容
            SafeArea(
              child: Row(
                children: [
                  // 左側控制面板
                  SizedBox(
                    width: AppConstants.controlPanelWidth,
                    child: ControlPanel(
                      focusNode: _controlPanelFocusNode,
                      currentFilter: _currentFilter,
                      onFilterChanged: _onFilterChanged,
                      isFocused: _isControlPanelFocused,
                      videoRepository: widget.videoRepository,
                    ),
                  ),
                  
                  // 右側內容區域
                  Expanded(
                    child: Column(
                      children: [
                        // 搜尋列
                        SearchBarWidget(
                          focusNode: _searchFocusNode,
                          onSearchChanged: _onSearchChanged,
                          isFocused: _isSearchFocused,
                        ),
                        
                        // 影片網格
                        Expanded(
                          child: _isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: AppConstants.primaryColor,
                                  ),
                                )
                              : VideoGrid(
                                  focusNode: _gridFocusNode,
                                  videos: _filteredVideos,
                                  isFocused: !_isControlPanelFocused && !_isSearchFocused,
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} 