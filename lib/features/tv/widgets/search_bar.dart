import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';

class SearchBarWidget extends StatefulWidget {
  final FocusNode focusNode;
  final Function(String) onSearchChanged;
  final bool isFocused;

  const SearchBarWidget({
    super.key,
    required this.focusNode,
    required this.onSearchChanged,
    this.isFocused = false,
  });

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      child: TextField(
        controller: _controller,
        focusNode: widget.focusNode,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: '搜尋影片...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
          prefixIcon: const Icon(Icons.search, color: Colors.white),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white),
                  onPressed: () {
                    _controller.clear();
                    widget.onSearchChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: widget.isFocused 
              ? Colors.white.withOpacity(0.15)
              : Colors.white.withOpacity(0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.defaultBorderRadius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.defaultBorderRadius),
            borderSide: const BorderSide(
              color: Color(AppConstants.primaryColor),
              width: 2,
            ),
          ),
        ),
        onChanged: (value) {
          setState(() {});
          widget.onSearchChanged(value);
        },
      ),
    );
  }
}

class SearchSuggestionsList extends StatelessWidget {
  final List<String> suggestions;
  final Function(String) onSuggestionTap;
  final double maxHeight;

  const SearchSuggestionsList({
    super.key,
    required this.suggestions,
    required this.onSuggestionTap,
    this.maxHeight = 200,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    
    final theme = Theme.of(context);
    
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppConstants.defaultBorderRadius),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: AppConstants.smallPadding),
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          return ListTile(
            dense: true,
            leading: Icon(
              Icons.history,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              size: 18,
            ),
            title: Text(
              suggestion,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            onTap: () => onSuggestionTap(suggestion),
          );
        },
      ),
    );
  }
} 