import 'package:another_iptv_player/models/m3u_series.dart';
import 'package:another_iptv_player/repositories/m3u_repository.dart';
import 'package:another_iptv_player/screens/m3u/series/m3u_episode_screen.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import '../../../controllers/favorites_controller.dart';
import '../../../models/favorite.dart';

import '../../../models/content_type.dart';

class M3uSeriesScreen extends StatefulWidget {
  final ContentItem contentItem;

  const M3uSeriesScreen({super.key, required this.contentItem});

  @override
  State<M3uSeriesScreen> createState() => _M3uSeriesScreenState();
}

class _M3uSeriesScreenState extends State<M3uSeriesScreen> {
  final M3uRepository _repository = AppState.m3uRepository!;
  late FavoritesController _favoritesController;
  List<int> seasons = [];
  List<M3uEpisode> episodes = [];
  bool isLoading = true;
  String? error;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _favoritesController = FavoritesController();
    _loadSeriesDetails();
    _checkFavoriteStatus();
  }

  Future<void> _loadSeriesDetails() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final seriesId = widget.contentItem.id;

      final seriesResponse = await _repository.getM3uEpisodesBySeriesId(
        seriesId: seriesId,
      );
      if (seriesResponse != null) {
        setState(() {
          episodes = seriesResponse;
          isLoading = false;
        });
      } else {
        setState(() {
          error = context.loc.preparing_series_exception_1;
          isLoading = false;
        });
      }
      seasons = seriesResponse!.map((e) => e.seasonNumber).toSet().toList()
        ..sort();
    } catch (e) {
      setState(() {
        error = context.loc.preparing_series_exception_2(e.toString());
        isLoading = false;
      });
    }
  }

  List<M3uEpisode> getEpisodesBySeason(
    List<M3uEpisode> episodes,
    int seasonNumber,
  ) {
    return episodes.where((e) => e.seasonNumber == seasonNumber).toList();
  }

  Future<void> _checkFavoriteStatus() async {
    final isFavorite = await _favoritesController.isFavorite(
      widget.contentItem.id,
      widget.contentItem.contentType,
    );
    if (mounted) {
      setState(() {
        _isFavorite = isFavorite;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final result = await _favoritesController.toggleFavorite(
      widget.contentItem,
    );
    if (mounted) {
      setState(() {
        _isFavorite = result;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result
                ? context.loc.added_to_favorites
                : context.loc.removed_from_favorites,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            SliverAppBar(
              expandedHeight: 400.0,
              floating: false,
              pinned: false,
              snap: false,
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  children: [
                    Hero(
                      tag: widget.contentItem.id,
                      child: SizedBox(
                        width: double.infinity,
                        height: double.infinity,
                        child: _buildCoverImage(),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.0, 0.7, 1.0],
                          colors: [
                            Colors.black.withOpacity(0.1),
                            Colors.black.withOpacity(0.3),
                            Colors.black.withOpacity(0.8),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 20,
                      left: 20,
                      right: 20,
                      child: Material(
                        color: Colors.transparent,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.contentItem.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                          offset: Offset(0, 1),
                                          blurRadius: 3,
                                          color: Colors.black54,
                                        ),
                                      ],
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _toggleFavorite,
                                  icon: Icon(
                                    _isFavorite
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: _isFavorite
                                        ? Colors.red
                                        : Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ];
        },
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).scaffoldBackgroundColor.withOpacity(0.8),
                Theme.of(context).scaffoldBackgroundColor,
              ],
            ),
          ),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(context.loc.preparing_series),
          ],
        ),
      );
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              error!,
              style: TextStyle(fontSize: 16, color: Colors.red.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadSeriesDetails,
              child: Text(context.loc.try_again),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSeasonsSection(),
          const SizedBox(height: 24),
          _buildSeriesDetails(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSeasonsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.loc.season,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (seasons.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey.shade600),
                const SizedBox(width: 12),
                Text(context.loc.not_found_in_category),
              ],
            ),
          )
        else
          SizedBox(
            height: 130,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: seasons.length,
              itemBuilder: (context, index) {
                final season = seasons[index];
                return _buildSeasonCard(season, index);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSeasonCard(int season, int index) {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            _showSeasonEpisodes(season);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.loc.season_number(season.toString()),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  context.loc.episode_count(
                    getEpisodesBySeason(episodes, season).length,
                  ),
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeriesDetails() {
    final details = <Map<String, dynamic>>[];
    return Column(
      children: details
          .map(
            (detail) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildDetailCard(
                icon: detail['icon'],
                title: detail['title'],
                value: detail['value'],
              ),
            ),
          )
          .toList(),
    );
  }

  void _showSeasonEpisodes(int season) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.loc.season_number(season.toString()),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        context.loc.episode_count(
                          '${getEpisodesBySeason(episodes, season).length}',
                        ),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final filteredEpisodes = getEpisodesBySeason(
                        episodes,
                        season,
                      );

                      if (filteredEpisodes.isEmpty) {
                        return Center(
                          child: Text(context.loc.not_found_in_category),
                        );
                      }

                      return ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredEpisodes.length,
                        itemBuilder: (context, index) {
                          final episode = filteredEpisodes[index];
                          return _buildEpisodeCard(episode);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEpisodeCard(M3uEpisode episode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          Navigator.pop(context);

          var m3uItem = await _repository.getM3uItemByUrl(url: episode.url);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => M3uEpisodeScreen(
                seasons: seasons,
                episodes: episodes,
                contentItem: ContentItem(
                  m3uItem!.id,
                  episode.name,
                  episode.cover ?? "",
                  ContentType.series,
                  season: episode.seasonNumber,
                  m3uItem: m3uItem
                ),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: episode.cover != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          episode.cover!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Text(
                                '${episode.episodeNumber}',
                                style: TextStyle(
                                  color: Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    : Center(
                        child: Text(
                          '${episode.episodeNumber}',
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      episode.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage() {
    final apiCover = widget.contentItem.coverPath;
    final apiBackdrop = episodes.firstOrNull?.cover;

    final hasBackdrop =
        (apiBackdrop?.isNotEmpty == true) ||
        (widget.contentItem.seriesStream?.backdropPath?.isNotEmpty == true);
    final hasCover =
        (apiCover?.isNotEmpty == true) ||
        (widget.contentItem.seriesStream?.cover?.isNotEmpty == true);

    if (hasBackdrop || hasCover) {
      String? imageUrl;

      if (apiBackdrop?.isNotEmpty == true) {
        imageUrl = apiBackdrop;
      } else if (apiCover?.isNotEmpty == true) {
        imageUrl = apiCover;
      } else if (widget.contentItem.seriesStream?.backdropPath?.isNotEmpty ==
          true) {
        imageUrl = widget.contentItem.seriesStream!.backdropPath?[0];
      } else if (widget.contentItem.seriesStream?.cover?.isNotEmpty == true) {
        imageUrl = widget.contentItem.seriesStream!.cover;
      }

      if (imageUrl != null) {
        return Image.network(
          imageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;

            return Container(
              color: Colors.grey.withOpacity(0.2),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                          : null,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.loc.image_loading,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return _buildPlaceholder();
          },
        );
      }
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.withOpacity(0.2),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.tv, size: 64, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            Text(
              context.loc.image_not_found,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.contentItem.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: Colors.blue),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
