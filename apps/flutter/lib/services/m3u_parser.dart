import 'dart:convert' show utf8;
import 'dart:io' show File, HttpClient;
import 'package:another_iptv_player/models/content_type.dart';
import 'package:uuid/uuid.dart';
import '../models/m3u_item.dart';

class M3uParser {

  static Future<List<M3uItem>> parseM3uFile(Map<String, String> params) async {
    return await M3uParser.parseFile(params['id']!, params['filePath']!);
  }

  static Future<List<M3uItem>> parseFile(
    String playlistId,
    String filePath,
  ) async {
    try {
      final file = File(filePath);
      final content = await file.readAsString(encoding: utf8);
      return parseM3u(playlistId, content);
    } catch (e) {
      print('M3U file parse error: $e');
      throw Exception('M3U dosyası okunamadı: ${e.toString()}');
    }
  }

  static Future<List<M3uItem>> parseM3uUrl(Map<String, String> params) async {
    return await M3uParser.parseUrl(params['id']!, params['url']!);
  }

  static Future<List<M3uItem>> parseUrl(String playlistId, String url) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception(
          'HTTP ${response.statusCode}: M3U URL\'sine erişilemedi',
        );
      }

      final content = await response.transform(utf8.decoder).join();
      client.close();
      return parseM3u(playlistId, content);
    } catch (e) {
      print('M3U URL parse error: $e');
      throw Exception('M3U URL\'si okunamadı: ${e.toString()}');
    }
  }

  static Map<String, List<M3uItem>> groupChannels(List<M3uItem> channels) {
    final grouped = <String, List<M3uItem>>{};

    for (final channel in channels) {
      final group = channel.groupTitle ?? 'Diğer';
      grouped.putIfAbsent(group, () => []).add(channel);
    }

    final sortedKeys = grouped.keys.toList()..sort();
    final sortedGrouped = <String, List<M3uItem>>{};

    for (final key in sortedKeys) {
      sortedGrouped[key] = grouped[key]!;
    }

    return sortedGrouped;
  }

  static List<M3uItem> parseM3u(String playlistId, String content) {
    final uuid = Uuid();

    final lines = content.split('\n').map((e) => e.trim()).toList();
    final List<M3uItem> items = [];

    Map<String, String?> currentMeta = {};
    String? currentName;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.startsWith('#EXTINF')) {
        final commaIndex = line.indexOf(',');
        final metadataPart = (commaIndex != -1)
            ? line.substring(0, commaIndex)
            : line;

        currentName = (commaIndex != -1)
            ? line.substring(commaIndex + 1).trim()
            : null;

        currentMeta = {
          'tvg-id': _extractAttribute(metadataPart, 'tvg-id'),
          'tvg-name': _extractAttribute(metadataPart, 'tvg-name'),
          'tvg-logo': _extractAttribute(metadataPart, 'tvg-logo'),
          'tvg-url': _extractAttribute(metadataPart, 'tvg-url'),
          'tvg-rec': _extractAttribute(metadataPart, 'tvg-rec'),
          'tvg-shift': _extractAttribute(metadataPart, 'tvg-shift'),
          'group-title': _extractAttribute(metadataPart, 'group-title'),
          'user-agent': _extractAttribute(metadataPart, 'user-agent'),
        };
      } else if (line.startsWith('#EXTGRP:')) {
        currentMeta['group-name'] = line.substring(8).trim();
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        final url = line;

        items.add(
          M3uItem(
            id: uuid.v4(),
            playlistId: playlistId,
            url: url,
            contentType: _detectContentType(url),
            name: currentName,
            tvgId: currentMeta['tvg-id'],
            tvgName: currentMeta['tvg-name'],
            tvgLogo: currentMeta['tvg-logo'],
            tvgUrl: currentMeta['tvg-url'],
            tvgRec: currentMeta['tvg-rec'],
            tvgShift: currentMeta['tvg-shift'],
            groupTitle: currentMeta['group-title'],
            groupName: currentMeta['group-name'],
            userAgent: currentMeta['user-agent'],
            referrer: null,
          ),
        );

        currentMeta.clear();
        currentName = null;
      }
    }

    return items;
  }

  static String? _extractAttribute(String line, String attribute) {
    final regex = RegExp('$attribute="(.*?)"');
    final match = regex.firstMatch(line);
    return match?.group(1);
  }

  static ContentType _detectContentType(String url) {
    final lowerUrl = url.toLowerCase();

    if (lowerUrl.contains('movie')) {
      return ContentType.vod;
    } else if (lowerUrl.contains('series')) {
      return ContentType.series;
    } else {
      return ContentType.liveStream;
    }
  }
}

class M3uTempSeries {
  final String name;
  final int seasonNumber;
  final int episodeNumber;
  final M3uItem m3uItem;

  M3uTempSeries(this.name, this.seasonNumber, this.episodeNumber, this.m3uItem);

  @override
  String toString() {
    return "$name $seasonNumber $episodeNumber";
  }
}

class SeriesParser {
  static final RegExp _seriesRegex = RegExp(
    r'^(.+?)\s+S(\d{1,2})\s+E(\d{1,3})',
    caseSensitive: false,
  );

  static final RegExp _alternativeRegex = RegExp(
    r'^(.+?)\s+Season\s+(\d{1,2})\s+Episode\s+(\d{1,3})',
    caseSensitive: false,
  );

  static M3uTempSeries? parse(M3uItem item) {
    if (item.name == null) {
      return null;
    }

    RegExpMatch? match = _seriesRegex.firstMatch(item.name!.trim());

    match ??= _alternativeRegex.firstMatch(item.name!.trim());

    if (match != null) {
      final seriesName = match.group(1)?.trim() ?? '';
      final seasonNumber = int.tryParse(match.group(2) ?? '') ?? 0;
      final episodeNumber = int.tryParse(match.group(3) ?? '') ?? 0;

      return M3uTempSeries(seriesName, seasonNumber, episodeNumber, item);
    }

    return null;
  }

  static String generateSeriesId(String playlistId, String seriesName) {
    return '${playlistId}_${seriesName.toLowerCase().replaceAll(' ', '_')}';
  }

  static String generateSeasonId(String seriesId, int seasonNumber) {
    return '${seriesId}_s${seasonNumber.toString().padLeft(2, '0')}';
  }

  static String generateEpisodeId(String seasonId, int episodeNumber) {
    return '${seasonId}_e${episodeNumber.toString().padLeft(2, '0')}';
  }
}
