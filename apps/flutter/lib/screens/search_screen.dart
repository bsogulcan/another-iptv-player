import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/repositories/iptv_repository.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/utils/navigate_by_content_type.dart';
import 'package:another_iptv_player/utils/responsive_helper.dart';
import '../../widgets/content_card.dart';

class SearchScreen extends StatefulWidget {
  final ContentType contentType;

  const SearchScreen({super.key, required this.contentType});

  @override
  SearchScreenState createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  bool isSearching = false;
  bool isLoading = false;
  String? errorMessage;
  bool isSearched = false;
  TextEditingController searchController = TextEditingController();
  FocusNode searchFocusNode = FocusNode();
  List<ContentItem> contentItems = [];
  IptvRepository repository = AppState.xtreamCodeRepository!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      startSearch();
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  String _getSearchHint(BuildContext context) {
    switch (widget.contentType) {
      case ContentType.liveStream:
        return context.loc.search_live_stream;
      case ContentType.vod:
        return context.loc.search_movie;
      case ContentType.series:
        return context.loc.search_series;
    }
  }

  String _getScreenTitle(BuildContext context) {
    switch (widget.contentType) {
      case ContentType.liveStream:
        return context.loc.search_live_stream;
      case ContentType.vod:
        return context.loc.search_movie;
      case ContentType.series:
        return context.loc.search_series;
    }
  }

  void startSearch() {
    setState(() {
      isSearching = true;
      isSearched = true;
    });
    Future.delayed(Duration(milliseconds: 100), () {
      searchFocusNode.requestFocus();
    });
  }

  void stopSearch() {
    setState(() {
      isSearching = false;
      searchController.clear();
      contentItems = [];
    });
    searchFocusNode.unfocus();
  }

  Future<void> _performSearch(String value) async {
    if (value.isEmpty || value.trim().isEmpty) {
      setState(() {
        contentItems = [];
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
      contentItems = [];
    });

    try {
      List<ContentItem> searchResults = [];

      switch (widget.contentType) {
        case ContentType.liveStream:
          var liveStreams = await repository.searchLiveStreams(value);
          searchResults = liveStreams
              .map(
                (x) => ContentItem(
                  x.streamId,
                  x.name,
                  x.streamIcon,
                  ContentType.liveStream,
                  liveStream: x,
                ),
              )
              .toList();
          break;

        case ContentType.vod:
          var vodStreams = await repository.searchMovies(value);
          searchResults = vodStreams
              .map(
                (x) => ContentItem(
                  x.streamId,
                  x.name,
                  x.streamIcon,
                  ContentType.vod,
                  containerExtension: x.containerExtension,
                  vodStream: x,
                ),
              )
              .toList();
          break;

        case ContentType.series:
          var series = await repository.searchSeries(value);
          searchResults = series
              .map(
                (x) => ContentItem(
                  x.seriesId,
                  x.name,
                  x.cover ?? '',
                  ContentType.series,
                  seriesStream: x,
                ),
              )
              .toList();
          break;
      }

      setState(() {
        contentItems = searchResults;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: isSearching
            ? TextField(
                controller: searchController,
                focusNode: searchFocusNode,
                decoration: InputDecoration(
                  hintText: _getSearchHint(context),
                  border: InputBorder.none,
                ),
                autofocus: true,
                onChanged: _performSearch,
              )
            : SelectableText(
                _getScreenTitle(context),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
        actions: [
          if (isSearching)
            IconButton(icon: Icon(Icons.clear), onPressed: stopSearch)
          else
            IconButton(icon: Icon(Icons.search), onPressed: startSearch),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return _buildErrorState();
    }

    return _buildContentGrid(context);
  }

  Widget _buildContentGrid(BuildContext context) {
    if (contentItems.isEmpty &&
        isSearched &&
        searchController.text.isNotEmpty) {
      return _buildEmptyState();
    }

    if (contentItems.isEmpty) {
      return _buildInitialState();
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: _buildGridDelegate(context),
      itemCount: contentItems.length,
      itemBuilder: (context, index) =>
          _buildContentItem(context, index, contentItems),
    );
  }

  SliverGridDelegateWithFixedCrossAxisCount _buildGridDelegate(
    BuildContext context,
  ) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: ResponsiveHelper.getCrossAxisCount(context),
      childAspectRatio: 0.65,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
    );
  }

  Widget _buildContentItem(
    BuildContext context,
    int index,
    List<ContentItem> contentItems,
  ) {
    final contentItem = contentItems[index];

    return ContentCard(
      content: contentItem,
      width: 150,
      onTap: () => navigateByContentType(context, contentItem),
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          // Burası zaten yorum satırında
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_getEmptyStateIcon(), size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            _getEmptyStateMessage(),
            style: TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  IconData _getEmptyStateIcon() {
    switch (widget.contentType) {
      case ContentType.liveStream:
        return Icons.live_tv_outlined;
      case ContentType.vod:
        return Icons.movie_outlined;
      case ContentType.series:
        return Icons.tv_outlined;
    }
  }

  String _getEmptyStateMessage() {
    switch (widget.contentType) {
      case ContentType.liveStream:
        return context.loc.live_stream_not_found;
      case ContentType.vod:
        return context.loc.movie_not_found;
      case ContentType.series:
        return 'Dizi bulunamadı'; // Bu için localization key'ine ihtiyaç var
    }
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            '${context.loc.error_occurred}: $errorMessage',
            style: const TextStyle(fontSize: 16, color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
