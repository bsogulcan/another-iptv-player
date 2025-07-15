import 'package:flutter/material.dart';
import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/api_configuration_model.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/repositories/iptv_repository.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';

import 'episode_screen.dart';

class SeriesScreen extends StatefulWidget {
  final ContentItem contentItem;

  const SeriesScreen({super.key, required this.contentItem});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  late IptvRepository _repository;
  SeriesInfosData? seriesInfo;
  List<SeasonsData> seasons = [];
  List<EpisodesData> episodes = [];
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _initializeRepository();
    _loadSeriesDetails();
  }

  void _initializeRepository() {
    _repository = IptvRepository(
      ApiConfig(
        baseUrl: AppState.currentPlaylist!.url!,
        username: AppState.currentPlaylist!.username!,
        password: AppState.currentPlaylist!.password!,
      ),
      AppState.currentPlaylist!.id,
    );
  }

  Future<void> _loadSeriesDetails() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final seriesId = widget.contentItem.id;

      final seriesResponse = await _repository.getSeriesInfo(seriesId);

      if (seriesResponse != null) {
        setState(() {
          seriesInfo = seriesResponse.seriesInfo;
          seasons = seriesResponse.seasons;
          episodes = seriesResponse.episodes;
          isLoading = false;
        });
      } else {
        setState(() {
          error = context.loc.preparing_series_exception_1;
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = context.loc.preparing_series_exception_2(e.toString());
        isLoading = false;
      });
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
                            Text(
                              seriesInfo?.name ?? widget.contentItem.name,
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
                            if (seriesInfo?.genre != null ||
                                widget.contentItem.seriesStream?.genre !=
                                    null) ...[
                              const SizedBox(height: 8),
                              Text(
                                seriesInfo?.genre ??
                                    widget.contentItem.seriesStream?.genre ??
                                    '',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 14,
                                  shadows: const [
                                    Shadow(
                                      offset: Offset(0, 1),
                                      blurRadius: 3,
                                      color: Colors.black54,
                                    ),
                                  ],
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
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
          // Rating Bölümü
          _buildRatingSection(),
          const SizedBox(height: 20),

          // Sezonlar Bölümü
          _buildSeasonsSection(),
          const SizedBox(height: 24),

          // Dizi Bilgileri
          _buildSeriesDetails(),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildRatingSection() {
    final rating = seriesInfo?.rating5based ?? 0;
    final ratingText =
        widget.contentItem.seriesStream?.rating5based?.toStringAsFixed(1) ??
        '0.0';

    return Row(
      children: [
        ...List.generate(5, (index) {
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              index < rating.round()
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: Colors.amber,
              size: 24,
            ),
          );
        }),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$ratingText/5',
            style: TextStyle(
              color: Colors.amber.shade700,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ],
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

  Widget _buildSeasonCard(SeasonsData season, int index) {
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
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.play_circle_outline,
                        size: 20,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        season.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  context.loc.episode_count(
                    (season.episodeCount ?? 0).toString(),
                  ),
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                if (season.airDate != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    season.airDate!,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeriesDetails() {
    final details = <Map<String, dynamic>>[];

    // Açıklama
    final plot = seriesInfo?.plot ?? widget.contentItem.seriesStream?.plot;
    if (plot != null && plot.isNotEmpty) {
      details.add({
        'icon': Icons.description,
        'title': context.loc.description,
        'value': plot,
      });
    }

    // Çıkış Tarihi
    final releaseDate =
        seriesInfo?.releaseDate ?? widget.contentItem.seriesStream?.releaseDate;
    details.add({
      'icon': Icons.calendar_today,
      'title': context.loc.release_date,
      'value': releaseDate ?? context.loc.not_found_in_category,
    });

    // Tür
    final genre = seriesInfo?.genre ?? widget.contentItem.seriesStream?.genre;
    if (genre != null && genre.isNotEmpty) {
      details.add({
        'icon': Icons.movie,
        'title': context.loc.genre,
        'value': genre,
      });
    }

    // Oyuncular
    final cast = seriesInfo?.cast ?? widget.contentItem.seriesStream?.cast;
    if (cast != null && cast.isNotEmpty) {
      details.add({
        'icon': Icons.people,
        'title': context.loc.cast,
        'value': cast,
      });
    }

    // Bölüm Süresi
    final episodeRunTime =
        seriesInfo?.episodeRunTime ??
        widget.contentItem.seriesStream?.episodeRunTime;
    if (episodeRunTime != null && episodeRunTime.isNotEmpty) {
      details.add({
        'icon': Icons.access_time,
        'title': context.loc.episode_duration,
        'value': '$episodeRunTime dakika',
      });
    }

    // Kategori ID
    final categoryId =
        seriesInfo?.categoryId ?? widget.contentItem.seriesStream?.categoryId;
    details.add({
      'icon': Icons.category,
      'title': context.loc.category_id,
      'value': categoryId ?? context.loc.not_found_in_category,
    });

    // Dizi ID
    final seriesIdValue =
        seriesInfo?.seriesId ??
        widget.contentItem.seriesStream?.seriesId.toString() ??
        widget.contentItem.id.toString();
    details.add({
      'icon': Icons.tag,
      'title': context.loc.series_id,
      'value': seriesIdValue,
    });

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

  void _showSeasonEpisodes(SeasonsData season) async {
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
                          season.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        context.loc.episode_count(
                          (season.episodeCount ?? 0).toString(),
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
                  child: FutureBuilder<List<EpisodesData>>(
                    future: _repository.getSeriesEpisodesBySeason(
                      seriesInfo?.seriesId ?? widget.contentItem.id.toString(),
                      season.seasonNumber,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final episodes = snapshot.data ?? [];
                      if (episodes.isEmpty) {
                        return Center(
                          child: Text(context.loc.not_found_in_category),
                        );
                      }

                      return ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: episodes.length,
                        itemBuilder: (context, index) {
                          final episode = episodes[index];
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

  Widget _buildEpisodeCard(EpisodesData episode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EpisodeScreen(
                seriesInfo: seriesInfo,
                seasons: seasons,
                episodes: episodes,
                contentItem: ContentItem(
                  episode.episodeId,
                  episode.title,
                  episode.movieImage ?? "",
                  ContentType.series,
                  containerExtension: episode.containerExtension,
                  season: episode.season,
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
                child:
                    episode.movieImage != null && episode.movieImage!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          episode.movieImage!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Text(
                                '${episode.episodeNum}',
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
                          '${episode.episodeNum}',
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
                      episode.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),

                    // Süre bilgisi
                    if (episode.duration != null &&
                        episode.duration!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        context.loc.duration(episode.duration!),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],

                    // Plot
                    if (episode.plot != null && episode.plot!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        episode.plot!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (episode.rating != null && episode.rating! > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 12),
                          const SizedBox(width: 2),
                          Text(
                            episode.rating!.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.amber.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Icon(
                    Icons.play_circle_outline,
                    color: Theme.of(context).primaryColor,
                    size: 24,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage() {
    final apiCover = seriesInfo?.cover;
    final apiBackdrop = seriesInfo?.backdropPath;

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
                      'Görsel yükleniyor...',
                      // Bu string için de localization ekleyebiliriz
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
              'Görsel Bulunamadı',
              // Bu string için de localization ekleyebiliriz
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              seriesInfo?.name ?? widget.contentItem.name,
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
