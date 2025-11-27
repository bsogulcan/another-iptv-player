import 'dart:async';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/services/event_bus.dart';
import 'package:another_iptv_player/services/player_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/content_type.dart';

class VideoInfoWidget extends StatefulWidget {
  const VideoInfoWidget({super.key});

  @override
  State<VideoInfoWidget> createState() => _VideoInfoWidgetState();

  // Static metod: Overlay'i dışarıdan kapatmak için
  static void hideOverlay() {
    _VideoInfoWidgetState.hideOverlay();
  }
}

class _VideoInfoWidgetState extends State<VideoInfoWidget> {
  static OverlayEntry? _globalOverlayEntry;
  static StreamSubscription? _globalToggleSubscription;
  static BuildContext? _globalContext;

  // Static metod: Overlay'i dışarıdan kapatmak için
  static void hideOverlay() {
    _globalOverlayEntry?.remove();
    _globalOverlayEntry = null;
    PlayerState.showVideoInfo = false;
  }

  @override
  void initState() {
    super.initState();

    // Context'i güncelle
    _globalContext = context;

    // Event listener'ı sadece bir kez oluştur
    if (_globalToggleSubscription == null) {
      _globalToggleSubscription = EventBus()
          .on<bool>('toggle_video_info')
          .listen((bool show) {
            if (show) {
              if (_globalContext != null) {
                _showVideoInfo(_globalContext!);
              }
            } else {
              _hideVideoInfo();
            }
          });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Context'i her build'de güncelle
    _globalContext = context;

    return IconButton(
      tooltip: 'Video Bilgileri',
      icon: const Icon(Icons.info_outline, color: Colors.white),
      onPressed: () {
        if (_globalOverlayEntry == null) {
          _showVideoInfo(context);
        } else {
          _hideVideoInfo();
        }
      },
    );
  }

  void _showVideoInfo(BuildContext context) {
    if (_globalOverlayEntry != null) return;

    final currentContent = PlayerState.currentContent;
    if (currentContent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video bilgisi bulunamadı'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Overlay'i oluşturmadan önce context'i kontrol et
    final overlayContext = _globalContext ?? context;

    // Overlay'i güvenli bir şekilde al
    OverlayState? overlay;
    try {
      overlay = Overlay.of(overlayContext, rootOverlay: true);
    } catch (e) {
      // Overlay bulunamazsa bir sonraki frame'de tekrar dene
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_globalOverlayEntry == null) {
          _showVideoInfo(overlayContext);
        }
      });
      return;
    }

    final screenWidth = MediaQuery.of(overlayContext).size.width;
    final panelWidth = (screenWidth / 3).clamp(200.0, 400.0);

    _globalOverlayEntry = OverlayEntry(
      opaque: false,
      maintainState: true,
      builder: (context) => _buildOverlay(context, currentContent, panelWidth),
    );

    overlay.insert(_globalOverlayEntry!);
    PlayerState.showVideoInfo = true;
  }

  void _hideVideoInfo() {
    _globalOverlayEntry?.remove();
    _globalOverlayEntry = null;
    PlayerState.showVideoInfo = false;
  }

  Widget _buildOverlay(
    BuildContext context,
    ContentItem currentContent,
    double panelWidth,
  ) {
    // Overlay'in hala açık olduğundan emin ol
    if (_globalOverlayEntry == null) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.3),
        child: Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.black.withOpacity(0.95),
            elevation: 8,
            child: Container(
              width: panelWidth,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.95),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[800]!, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Video Bilgileri',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: _hideVideoInfo,
                        ),
                      ],
                    ),
                  ),
                  // Info content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow(
                            context,
                            'İsim',
                            currentContent.name,
                            Icons.title,
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            context,
                            'İçerik Tipi',
                            _getContentTypeDisplayName(
                              currentContent.contentType,
                            ),
                            Icons.category,
                          ),
                          if (currentContent.containerExtension != null &&
                              currentContent.containerExtension!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              context,
                              'Format',
                              currentContent.containerExtension!.toUpperCase(),
                              Icons.extension,
                            ),
                          ],
                          if (currentContent.description != null &&
                              currentContent.description!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              context,
                              'Açıklama',
                              currentContent.description!,
                              Icons.description,
                              isMultiline: true,
                            ),
                          ],
                          if (currentContent.duration != null) ...[
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              context,
                              'Süre',
                              _formatDuration(currentContent.duration),
                              Icons.access_time,
                            ),
                          ],
                          if (currentContent.vodStream != null) ...[
                            if (currentContent.vodStream!.rating.isNotEmpty &&
                                currentContent.vodStream!.rating != '0') ...[
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                context,
                                'Değerlendirme',
                                currentContent.vodStream!.rating,
                                Icons.star,
                              ),
                            ],
                            if (currentContent.vodStream!.genre != null &&
                                currentContent
                                    .vodStream!
                                    .genre!
                                    .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                context,
                                'Tür',
                                currentContent.vodStream!.genre!,
                                Icons.movie,
                              ),
                            ],
                            if (currentContent.vodStream!.createdAt != null) ...[
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                context,
                                'Eklenme Tarihi',
                                DateFormat('dd.MM.yyyy HH:mm').format(
                                  currentContent.vodStream!.createdAt!,
                                ),
                                Icons.calendar_today,
                              ),
                            ],
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              context,
                              'Stream ID',
                              currentContent.vodStream!.streamId,
                              Icons.fingerprint,
                              isCopyable: true,
                            ),
                          ],
                          if (currentContent.seriesStream != null) ...[
                            if (currentContent.seriesStream!.plot != null &&
                                currentContent
                                    .seriesStream!
                                    .plot!
                                    .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                context,
                                'Konu',
                                currentContent.seriesStream!.plot!,
                                Icons.article,
                                isMultiline: true,
                              ),
                            ],
                            if (currentContent.seriesStream!.cast != null &&
                                currentContent
                                    .seriesStream!
                                    .cast!
                                    .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                context,
                                'Oyuncular',
                                currentContent.seriesStream!.cast!,
                                Icons.people,
                              ),
                            ],
                            if (currentContent.seriesStream!.director != null &&
                                currentContent
                                    .seriesStream!
                                    .director!
                                    .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                context,
                                'Yönetmen',
                                currentContent.seriesStream!.director!,
                                Icons.person,
                              ),
                            ],
                            if (currentContent.seriesStream!.genre != null &&
                                currentContent
                                    .seriesStream!
                                    .genre!
                                    .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                context,
                                'Tür',
                                currentContent.seriesStream!.genre!,
                                Icons.movie,
                              ),
                            ],
                            if (currentContent.seriesStream!.releaseDate !=
                                    null &&
                                currentContent
                                    .seriesStream!
                                    .releaseDate!
                                    .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                context,
                                'Yayın Tarihi',
                                currentContent.seriesStream!.releaseDate!,
                                Icons.calendar_today,
                              ),
                            ],
                            if (currentContent.seriesStream!.rating != null &&
                                currentContent
                                    .seriesStream!
                                    .rating!
                                    .isNotEmpty &&
                                currentContent.seriesStream!.rating != '0') ...[
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                context,
                                'Değerlendirme',
                                currentContent.seriesStream!.rating!,
                                Icons.star,
                              ),
                            ],
                            if (currentContent.seriesStream!.episodeRunTime !=
                                    null &&
                                currentContent
                                    .seriesStream!
                                    .episodeRunTime!
                                    .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                context,
                                'Bölüm Süresi',
                                '${currentContent.seriesStream!.episodeRunTime} dk',
                                Icons.timer,
                              ),
                            ],
                            if (currentContent.seriesStream!.lastModified !=
                                    null &&
                                currentContent
                                    .seriesStream!
                                    .lastModified!
                                    .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                context,
                                'Son Güncelleme',
                                _formatTimestamp(
                                  currentContent.seriesStream!.lastModified!,
                                ),
                                Icons.update,
                              ),
                            ],
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              context,
                              'Series ID',
                              currentContent.seriesStream!.seriesId,
                              Icons.fingerprint,
                              isCopyable: true,
                            ),
                          ],
                          if (currentContent.liveStream != null &&
                              currentContent
                                  .liveStream!
                                  .epgChannelId
                                  .isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              context,
                              'EPG Kanal ID',
                              currentContent.liveStream!.epgChannelId,
                              Icons.live_tv,
                            ),
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              context,
                              'Stream ID',
                              currentContent.liveStream!.streamId,
                              Icons.fingerprint,
                              isCopyable: true,
                            ),
                          ],
                          if (currentContent.m3uItem != null &&
                              currentContent.m3uItem!.groupTitle != null &&
                              currentContent.m3uItem!.groupTitle!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              context,
                              'Kategori',
                              currentContent.m3uItem!.groupTitle!,
                              Icons.folder,
                            ),
                          ],
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            context,
                            'URL',
                            currentContent.url,
                            Icons.link,
                            isCopyable: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getContentTypeDisplayName(ContentType contentType) {
    switch (contentType) {
      case ContentType.liveStream:
        return 'Canlı Yayın';
      case ContentType.vod:
        return 'Film';
      case ContentType.series:
        return 'Dizi';
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return 'Bilinmiyor';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}s ${minutes}dk ${seconds}sn';
    } else if (minutes > 0) {
      return '${minutes}dk ${seconds}sn';
    } else {
      return '${seconds}sn';
    }
  }

  String _formatTimestamp(String timestamp) {
    if (timestamp.isEmpty) return '';
    try {
      // Try parsing as integer (Unix timestamp in seconds)
      final seconds = int.tryParse(timestamp);
      if (seconds != null) {
        final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
        return DateFormat('dd.MM.yyyy HH:mm').format(date);
      }
      return timestamp;
    } catch (e) {
      return timestamp;
    }
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    bool isMultiline = false,
    bool isCopyable = false,
  }) {
    const textColor = Colors.white;
    const secondaryTextColor = Colors.grey;
    final dividerColor = Colors.grey[800]!;
    const primaryColor = Colors.blue;

    return InkWell(
      onTap: isCopyable
          ? () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('URL panoya kopyalandı'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: dividerColor, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: secondaryTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(fontSize: 14, color: textColor),
                    maxLines: isMultiline ? null : 2,
                    overflow: isMultiline
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isCopyable)
              Icon(Icons.copy, size: 18, color: secondaryTextColor),
          ],
        ),
      ),
    );
  }
}
