import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:another_iptv_player/database/drift_flutter.dart';
import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/live_stream.dart';
import 'package:another_iptv_player/models/series.dart';
import 'package:another_iptv_player/models/vod_streams.dart';
import 'package:another_iptv_player/models/server_info.dart';
import 'package:another_iptv_player/models/user_info.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/category_type.dart';
import '../models/m3u_item.dart';
import '../models/m3u_series.dart';
import '../models/playlist_model.dart';
import '../models/favorite.dart';

part 'database.g.dart';

@DataClassName('PlaylistData')
class Playlists extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get type => text()();

  TextColumn get url => text().nullable()();

  TextColumn get username => text().nullable()();

  TextColumn get password => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoriesData')
class Categories extends Table {
  TextColumn get categoryId => text()();

  TextColumn get categoryName => text()();

  IntColumn get parentId => integer().withDefault(const Constant(0))();

  TextColumn get playlistId => text()();

  TextColumn get type => text()(); // 'live', 'vod', 'series'
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {categoryId, playlistId, type};
}

@DataClassName('UserInfosData')
class UserInfos extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get playlistId => text()();

  TextColumn get username => text()();

  TextColumn get password => text()();

  TextColumn get message => text()();

  IntColumn get auth => integer()();

  TextColumn get status => text()();

  TextColumn get expDate => text()();

  TextColumn get isTrial => text()();

  TextColumn get activeCons => text()();

  TextColumn get createdAt => text()();

  TextColumn get maxConnections => text()();

  TextColumn get allowedOutputFormats => text()();
}

@DataClassName('ServerInfosData')
class ServerInfos extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get playlistId => text()();

  TextColumn get url => text()();

  TextColumn get port => text()();

  TextColumn get httpsPort => text()();

  TextColumn get serverProtocol => text()();

  TextColumn get rtmpPort => text()();

  TextColumn get timezone => text()();

  IntColumn get timestampNow => integer()();

  TextColumn get timeNow => text()();
}

@DataClassName('LiveStreamsData')
class LiveStreams extends Table {
  TextColumn get streamId => text()();

  TextColumn get name => text()();

  TextColumn get streamIcon => text()();

  TextColumn get categoryId => text()();

  TextColumn get epgChannelId => text()();

  TextColumn get playlistId => text()(); // Ekstra property
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {streamId, playlistId};
}

@DataClassName('VodStreamsData')
class VodStreams extends Table {
  TextColumn get streamId => text()();

  TextColumn get name => text()();

  TextColumn get streamIcon => text()();

  TextColumn get categoryId => text()();

  TextColumn get rating => text()();

  RealColumn get rating5based => real()();

  TextColumn get containerExtension => text()();

  TextColumn get playlistId => text()(); // Ekstra property
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {streamId, playlistId};
}

@DataClassName('SeriesStreamsData')
class SeriesStreams extends Table {
  TextColumn get seriesId => text()();

  TextColumn get name => text()();

  TextColumn get cover => text().nullable()();

  TextColumn get plot => text().nullable()();

  TextColumn get cast => text().nullable()();

  TextColumn get director => text().nullable()();

  TextColumn get genre => text().nullable()();

  TextColumn get releaseDate => text().nullable()();

  TextColumn get rating => text().nullable()();

  RealColumn get rating5based => real().nullable()();

  TextColumn get youtubeTrailer => text().nullable()();

  TextColumn get episodeRunTime => text().nullable()();

  TextColumn get categoryId => text().nullable()();

  TextColumn get playlistId => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  TextColumn get lastModified => text().nullable()();

  TextColumn get backdropPath => text().nullable()();

  @override
  Set<Column> get primaryKey => {seriesId, playlistId};
}

@DataClassName('SeriesInfosData')
class SeriesInfos extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get seriesId => text()();

  TextColumn get name => text()();

  TextColumn get cover => text().nullable()();

  TextColumn get plot => text().nullable()();

  TextColumn get cast => text().nullable()();

  TextColumn get director => text().nullable()();

  TextColumn get genre => text().nullable()();

  TextColumn get releaseDate => text().nullable()();

  TextColumn get lastModified => text().nullable()();

  TextColumn get rating => text().nullable()();

  IntColumn get rating5based => integer().nullable()();

  TextColumn get backdropPath => text().nullable()();

  TextColumn get youtubeTrailer => text().nullable()();

  TextColumn get episodeRunTime => text().nullable()();

  TextColumn get categoryId => text().nullable()();

  TextColumn get playlistId => text()();
}

@DataClassName('SeasonsData')
class Seasons extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get seriesId => text()();

  TextColumn get airDate => text().nullable()();

  IntColumn get episodeCount => integer().nullable()();

  IntColumn get seasonId => integer()();

  TextColumn get name => text()();

  TextColumn get overview => text().nullable()();

  IntColumn get seasonNumber => integer()();

  IntColumn get voteAverage => integer().nullable()();

  TextColumn get cover => text().nullable()();

  TextColumn get coverBig => text().nullable()();

  TextColumn get playlistId => text()();
}

@DataClassName('EpisodesData')
class Episodes extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get seriesId => text()();

  TextColumn get episodeId => text()();

  IntColumn get episodeNum => integer()();

  TextColumn get title => text()();

  TextColumn get containerExtension => text().nullable()();

  IntColumn get season => integer()();

  TextColumn get customSid => text().nullable()();

  TextColumn get added => text().nullable()();

  TextColumn get directSource => text().nullable()();

  TextColumn get playlistId => text()();

  // Episode Info
  IntColumn get tmdbId => integer().nullable()();

  TextColumn get releasedate => text().nullable()();

  TextColumn get plot => text().nullable()();

  IntColumn get durationSecs => integer().nullable()();

  TextColumn get duration => text().nullable()();

  TextColumn get movieImage => text().nullable()();

  IntColumn get bitrate => integer().nullable()();

  RealColumn get rating => real().nullable()();
}

@DataClassName('WatchHistoriesData')
class WatchHistories extends Table {
  TextColumn get playlistId => text()();

  IntColumn get contentType => intEnum<ContentType>()();

  TextColumn get streamId => text()();

  TextColumn get seriesId => text().nullable()();

  IntColumn get watchDuration => integer().nullable()();

  IntColumn get totalDuration => integer().nullable()();

  DateTimeColumn get lastWatched => dateTime()();

  TextColumn get imagePath => text().nullable()();

  TextColumn get title => text()();

  @override
  Set<Column> get primaryKey => {playlistId, streamId};
}

@DataClassName('M3uItemData')
class M3uItems extends Table {
  TextColumn get id => text()();

  TextColumn get playlistId => text()();

  TextColumn get url => text()();

  TextColumn get name => text().nullable()();

  TextColumn get tvgId => text().nullable()();

  TextColumn get tvgName => text().nullable()();

  TextColumn get tvgLogo => text().nullable()();

  TextColumn get tvgUrl => text().nullable()();

  TextColumn get tvgRec => text().nullable()();

  TextColumn get tvgShift => text().nullable()();

  TextColumn get groupTitle => text().nullable()();

  TextColumn get groupName => text().nullable()();

  TextColumn get userAgent => text().nullable()();

  TextColumn get referrer => text().nullable()();

  TextColumn get categoryId => text().nullable()();

  IntColumn get contentType => integer()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (LENGTH(id) > 0)',
    'CHECK (LENGTH(url) > 0)',
    'CHECK (LENGTH(playlist_id) > 0)',
  ];
}

@DataClassName('M3uSeriesData')
class M3uSeries extends Table {
  TextColumn get playlistId => text()();

  TextColumn get seriesId => text()();

  TextColumn get name => text()();

  TextColumn get categoryId => text().nullable()();

  TextColumn get cover => text().nullable()();

  @override
  Set<Column> get primaryKey => {playlistId, seriesId};
}

@DataClassName('M3uEpisodesData')
class M3uEpisodes extends Table {
  TextColumn get playlistId => text()();

  TextColumn get seriesId => text()();

  IntColumn get seasonNumber => integer()();

  IntColumn get episodeNumber => integer()();

  TextColumn get name => text()();

  TextColumn get url => text()();

  TextColumn get categoryId => text().nullable()();

  TextColumn get cover => text().nullable()();

  @override
  Set<Column> get primaryKey => {
    playlistId,
    seriesId,
    seasonNumber,
    episodeNumber,
  };
}

@DataClassName('FavoritesData')
class Favorites extends Table {
  TextColumn get id => text()();

  TextColumn get playlistId => text()();

  IntColumn get contentType => integer()();

  TextColumn get streamId => text()();

  TextColumn get episodeId => text().nullable()();

  TextColumn get m3uItemId => text().nullable()();

  TextColumn get name => text()();

  TextColumn get imagePath => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Playlists,
    Categories,
    UserInfos,
    ServerInfos,
    LiveStreams,
    VodStreams,
    SeriesStreams,
    SeriesInfos,
    Seasons,
    Episodes,
    WatchHistories,
    M3uItems,
    M3uSeries,
    M3uEpisodes,
    Favorites,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e])
    : super(
        e ??
            driftDatabase(
              name: 'another-iptv-player',
              native: const DriftNativeOptions(
                databaseDirectory: getApplicationSupportDirectory,
              ),
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
                onResult: (result) {
                  if (result.missingFeatures.isNotEmpty) {
                    debugPrint(
                      'Using ${result.chosenImplementation} due to unsupported '
                      'browser features: ${result.missingFeatures}',
                    );
                  }
                },
              ),
            ),
      );

  @override
  int get schemaVersion => 7;

  // === PLAYLIST İŞLEMLERİ ===

  // Playlist oluştur
  Future<void> insertPlaylist(Playlist playlist) async {
    await into(playlists).insert(
      PlaylistsCompanion(
        id: Value(playlist.id),
        name: Value(playlist.name),
        type: Value(playlist.type.toString()),
        url: Value(playlist.url),
        username: Value(playlist.username),
        password: Value(playlist.password),
        createdAt: Value(playlist.createdAt),
      ),
    );
  }

  // Tüm playlistleri getir
  Future<List<Playlist>> getAllPlaylists() async {
    final playlistData = await select(playlists).get();
    return playlistData.map((data) => _convertToPlaylist(data)).toList();
  }

  // ID'ye göre playlist getir
  Future<Playlist?> getPlaylistById(String id) async {
    final query = select(playlists)..where((p) => p.id.equals(id));
    final result = await query.getSingleOrNull();
    return result != null ? _convertToPlaylist(result) : null;
  }

  // Playlist sil
  Future<void> deletePlaylistById(String id) async {
    // Önce playlist'e ait kategorileri sil
    await deleteAllCategoriesByPlaylist(id);
    // Sonra playlist'i sil
    await (delete(playlists)..where((p) => p.id.equals(id))).go();
  }

  // Playlist güncelle
  Future<void> updatePlaylist(Playlist playlist) async {
    await (update(playlists)..where((p) => p.id.equals(playlist.id))).write(
      PlaylistsCompanion(
        name: Value(playlist.name),
        type: Value(playlist.type.toString()),
        url: Value(playlist.url),
        username: Value(playlist.username),
        password: Value(playlist.password),
      ),
    );
  }

  // Tip filtreleme
  Future<List<Playlist>> getPlaylistsByType(PlaylistType type) async {
    final query = select(playlists)
      ..where((p) => p.type.equals(type.toString()));
    final playlistData = await query.get();
    return playlistData.map((data) => _convertToPlaylist(data)).toList();
  }

  // === KATEGORİ İŞLEMLERİ ===

  // Kategorileri tip ve playlist'e göre getir
  Future<List<Category>> getCategoriesByTypeAndPlaylist(
    String playlistId,
    CategoryType type,
  ) async {
    final categoriesData =
        await (select(categories)..where(
              (tbl) =>
                  tbl.playlistId.equals(playlistId) &
                  tbl.type.equals(type.value),
            ))
            .get();

    return categoriesData.map((cat) => Category.fromDrift(cat)).toList();
  }

  Future<List<Category>> getCategoriesByPlaylist(String playlistId) async {
    final categoriesData = await (select(
      categories,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).get();

    return categoriesData.map((cat) => Category.fromDrift(cat)).toList();
  }

  Future<void> insertCategories(List<Category> categoryList) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(
        categories,
        categoryList.map((cat) => cat.toCompanion()).toList(),
      );
    });
  }

  // Belirli tip ve playlist'teki kategorileri sil
  Future<void> deleteCategoriesByTypeAndPlaylist(
    String playlistId,
    CategoryType type,
  ) async {
    await (delete(categories)..where(
          (tbl) =>
              tbl.playlistId.equals(playlistId) & tbl.type.equals(type.value),
        ))
        .go();
  }

  // Playlist'teki tüm kategorileri sil
  Future<void> deleteAllCategoriesByPlaylist(String playlistId) async {
    await (delete(
      categories,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  // Parent kategorileri getir
  Future<List<Category>> getParentCategories(
    String playlistId,
    CategoryType type,
  ) async {
    final categoriesData =
        await (select(categories)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    tbl.type.equals(type.value) &
                    tbl.parentId.equals(0),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.categoryName)]))
            .get();

    return categoriesData.map((cat) => Category.fromDrift(cat)).toList();
  }

  // Alt kategorileri getir
  Future<List<Category>> getSubCategories(
    String playlistId,
    CategoryType type,
    String parentId,
  ) async {
    final categoriesData =
        await (select(categories)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    tbl.type.equals(type.value) &
                    tbl.parentId.equals(int.parse(parentId)),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.categoryName)]))
            .get();

    return categoriesData.map((cat) => Category.fromDrift(cat)).toList();
  }

  // Kategori ara
  Future<List<Category>> searchCategories(
    String playlistId,
    CategoryType type,
    String query,
  ) async {
    final categoriesData =
        await (select(categories)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    tbl.type.equals(type.value) &
                    tbl.categoryName.contains(query),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.categoryName)]))
            .get();

    return categoriesData.map((cat) => Category.fromDrift(cat)).toList();
  }

  // Kategori sayısını getir
  Future<int> getCategoryCount(String playlistId, CategoryType type) async {
    final result =
        await (select(categories)..where(
              (tbl) =>
                  tbl.playlistId.equals(playlistId) &
                  tbl.type.equals(type.value),
            ))
            .get();

    return result.length;
  }

  // Tüm kategorileri getir (tüm tipler)
  Future<Map<CategoryType, List<Category>>> getAllCategoriesByPlaylist(
    String playlistId,
  ) async {
    final allCategoriesData =
        await (select(categories)
              ..where((tbl) => tbl.playlistId.equals(playlistId))
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.categoryName)]))
            .get();

    final result = <CategoryType, List<Category>>{};

    for (final type in CategoryType.values) {
      result[type] = allCategoriesData
          .where((cat) => cat.type == type.value)
          .map((cat) => Category.fromDrift(cat))
          .toList();
    }

    return result;
  }

  // Playlist'in kategori istatistiklerini getir
  Future<Map<CategoryType, int>> getCategoryStatsByPlaylist(
    String playlistId,
  ) async {
    final result = <CategoryType, int>{};

    for (final type in CategoryType.values) {
      final count = await getCategoryCount(playlistId, type);
      result[type] = count;
    }

    return result;
  }

  // Kategori ID'sine göre tek kategori getir
  Future<Category?> getCategoryById(
    String playlistId,
    String categoryId,
    CategoryType type,
  ) async {
    final query = select(categories)
      ..where(
        (tbl) =>
            tbl.playlistId.equals(playlistId) &
            tbl.categoryId.equals(categoryId) &
            tbl.type.equals(type.value),
      );

    final result = await query.getSingleOrNull();
    return result != null ? Category.fromDrift(result) : null;
  }

  // Kategori var mı kontrol et
  Future<bool> categoryExists(
    String playlistId,
    String categoryId,
    CategoryType type,
  ) async {
    final category = await getCategoryById(playlistId, categoryId, type);
    return category != null;
  }

  // === YARDIMCI METODLAR ===

  // PlaylistData'yı Playlist'e çevir
  Playlist _convertToPlaylist(PlaylistData data) {
    return Playlist(
      id: data.id,
      name: data.name,
      type: PlaylistType.values.firstWhere((e) => e.toString() == data.type),
      url: data.url,
      username: data.username,
      password: data.password,
      createdAt: data.createdAt,
    );
  }

  // === USER INFO İŞLEMLERİ ===

  // UserInfo ekleme/güncelleme (upsert)
  Future<int> insertOrUpdateUserInfo(UserInfo userInfo) async {
    final existingUser = await getUserInfoByPlaylistId(userInfo.playlistId);

    if (existingUser != null) {
      // Güncelle
      return await (update(
        userInfos,
      )..where((tbl) => tbl.playlistId.equals(userInfo.playlistId))).write(
        UserInfosCompanion(
          username: Value(userInfo.username),
          password: Value(userInfo.password),
          message: Value(userInfo.message),
          auth: Value(userInfo.auth),
          status: Value(userInfo.status),
          expDate: Value(userInfo.expDate),
          isTrial: Value(userInfo.isTrial),
          activeCons: Value(userInfo.activeCons),
          createdAt: Value(userInfo.createdAt),
          maxConnections: Value(userInfo.maxConnections),
          allowedOutputFormats: Value(userInfo.allowedOutputFormats.join(',')),
        ),
      );
    } else {
      // Yeni ekle
      return await into(userInfos).insert(
        UserInfosCompanion.insert(
          playlistId: userInfo.playlistId,
          username: userInfo.username,
          password: userInfo.password,
          message: userInfo.message,
          auth: userInfo.auth,
          status: userInfo.status,
          expDate: userInfo.expDate,
          isTrial: userInfo.isTrial,
          activeCons: userInfo.activeCons,
          createdAt: userInfo.createdAt,
          maxConnections: userInfo.maxConnections,
          allowedOutputFormats: userInfo.allowedOutputFormats.join(','),
        ),
      );
    }
  }

  // PlaylistId'ye göre UserInfo getirme
  Future<UserInfo?> getUserInfoByPlaylistId(String playlistId) async {
    final query = select(userInfos)
      ..where((tbl) => tbl.playlistId.equals(playlistId));

    final result = await query.getSingleOrNull();
    if (result == null) return null;

    return UserInfo(
      id: result.id,
      playlistId: result.playlistId,
      username: result.username,
      password: result.password,
      message: result.message,
      auth: result.auth,
      status: result.status,
      expDate: result.expDate,
      isTrial: result.isTrial,
      activeCons: result.activeCons,
      createdAt: result.createdAt,
      maxConnections: result.maxConnections,
      allowedOutputFormats: result.allowedOutputFormats.isNotEmpty
          ? result.allowedOutputFormats.split(',')
          : [],
    );
  }

  // Tüm UserInfo'ları getirme
  Future<List<UserInfo>> getAllUserInfos() async {
    final results = await select(userInfos).get();
    return results
        .map(
          (result) => UserInfo(
            id: result.id,
            playlistId: result.playlistId,
            username: result.username,
            password: result.password,
            message: result.message,
            auth: result.auth,
            status: result.status,
            expDate: result.expDate,
            isTrial: result.isTrial,
            activeCons: result.activeCons,
            createdAt: result.createdAt,
            maxConnections: result.maxConnections,
            allowedOutputFormats: result.allowedOutputFormats.isNotEmpty
                ? result.allowedOutputFormats.split(',')
                : [],
          ),
        )
        .toList();
  }

  // PlaylistId'ye göre UserInfo silme
  Future<int> deleteUserInfoByPlaylistId(String playlistId) async {
    return await (delete(
      userInfos,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  // === SERVER INFO İŞLEMLERİ ===

  // ServerInfo ekleme/güncelleme (upsert)
  Future<int> insertOrUpdateServerInfo(ServerInfo serverInfo) async {
    final existingServer = await getServerInfoByPlaylistId(
      serverInfo.playlistId,
    );

    if (existingServer != null) {
      // Güncelle
      return await (update(
        serverInfos,
      )..where((tbl) => tbl.playlistId.equals(serverInfo.playlistId))).write(
        ServerInfosCompanion(
          url: Value(serverInfo.url),
          port: Value(serverInfo.port),
          httpsPort: Value(serverInfo.httpsPort),
          serverProtocol: Value(serverInfo.serverProtocol),
          rtmpPort: Value(serverInfo.rtmpPort),
          timezone: Value(serverInfo.timezone),
          timestampNow: Value(serverInfo.timestampNow),
          timeNow: Value(serverInfo.timeNow),
        ),
      );
    } else {
      // Yeni ekle
      return await into(serverInfos).insert(
        ServerInfosCompanion.insert(
          playlistId: serverInfo.playlistId,
          url: serverInfo.url,
          port: serverInfo.port,
          httpsPort: serverInfo.httpsPort,
          serverProtocol: serverInfo.serverProtocol,
          rtmpPort: serverInfo.rtmpPort,
          timezone: serverInfo.timezone,
          timestampNow: serverInfo.timestampNow,
          timeNow: serverInfo.timeNow,
        ),
      );
    }
  }

  // PlaylistId'ye göre ServerInfo getirme
  Future<ServerInfo?> getServerInfoByPlaylistId(String playlistId) async {
    final query = select(serverInfos)
      ..where((tbl) => tbl.playlistId.equals(playlistId));

    final result = await query.getSingleOrNull();
    if (result == null) return null;

    return ServerInfo(
      id: result.id,
      playlistId: result.playlistId,
      url: result.url,
      port: result.port,
      httpsPort: result.httpsPort,
      serverProtocol: result.serverProtocol,
      rtmpPort: result.rtmpPort,
      timezone: result.timezone,
      timestampNow: result.timestampNow,
      timeNow: result.timeNow,
    );
  }

  // Tüm ServerInfo'ları getirme
  Future<List<ServerInfo>> getAllServerInfos() async {
    final results = await select(serverInfos).get();
    return results
        .map(
          (result) => ServerInfo(
            id: result.id,
            playlistId: result.playlistId,
            url: result.url,
            port: result.port,
            httpsPort: result.httpsPort,
            serverProtocol: result.serverProtocol,
            rtmpPort: result.rtmpPort,
            timezone: result.timezone,
            timestampNow: result.timestampNow,
            timeNow: result.timeNow,
          ),
        )
        .toList();
  }

  // PlaylistId'ye göre ServerInfo silme
  Future<int> deleteServerInfoByPlaylistId(String playlistId) async {
    return await (delete(
      serverInfos,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  // Live Streams
  Future<void> insertLiveStreams(List<LiveStream> liveStreams) async {
    final liveStreamsCompanions = liveStreams
        .map(
          (liveStream) => LiveStreamsCompanion(
            streamId: Value(liveStream.streamId),
            name: Value(liveStream.name),
            streamIcon: Value(liveStream.streamIcon),
            categoryId: Value(liveStream.categoryId),
            epgChannelId: Value(liveStream.epgChannelId),
            playlistId: Value(liveStream.playlistId ?? ''),
          ),
        )
        .toList();

    await batch((batch) {
      batch.insertAllOnConflictUpdate(this.liveStreams, liveStreamsCompanions);
    });
  }

  Future<List<LiveStream>> getLiveStreams(String playlistId) async {
    final rows = await (select(
      liveStreams,
    )..where((ls) => ls.playlistId.equals(playlistId))).get();

    return rows.map((row) => LiveStream.fromDriftLiveStream(row)).toList();
  }

  Future<List<LiveStream>> getLiveStreamsByCategoryId(
    String playlistId,
    String categoryId, {
    int? top,
  }) async {
    var query = select(liveStreams)
      ..where(
        (ls) =>
            ls.playlistId.equals(playlistId) & ls.categoryId.equals(categoryId),
      );

    if (top != null) {
      query = query..limit(top);
    }

    final rows = await query.get();

    return rows.map((row) => LiveStream.fromDriftLiveStream(row)).toList();
  }

  Future<void> deleteLiveStreamsByPlaylistId(String playlistId) async {
    await (delete(
      liveStreams,
    )..where((ls) => ls.playlistId.equals(playlistId))).go();
  }

  // Vod Streams
  Future<void> insertVodStreams(List<VodStream> vodStreams) async {
    final vodStreamsCompanions = vodStreams
        .map((vodStream) => vodStream.toDriftCompanion())
        .toList();

    await batch((batch) {
      batch.insertAllOnConflictUpdate(this.vodStreams, vodStreamsCompanions);
    });
  }

  Future<List<VodStream>> getVodStreamsByPlaylistId(String playlistId) async {
    final rows = await (select(
      vodStreams,
    )..where((vs) => vs.playlistId.equals(playlistId))).get();

    return rows.map((row) => VodStream.fromDriftVodStream(row)).toList();
  }

  Future<List<VodStream>> getVodStreamsByCategoryAndPlaylistId({
    required String categoryId,
    required String playlistId,
    int? top,
  }) async {
    var query = select(vodStreams)
      ..where(
        (vs) =>
            vs.categoryId.equals(categoryId) & vs.playlistId.equals(playlistId),
      );

    if (top != null) {
      query = query..limit(top);
    }

    final rows = await query.get();

    return rows.map((row) => VodStream.fromDriftVodStream(row)).toList();
  }

  Future<List<VodStream>> getVodStreamsByCategory(String categoryId) async {
    final rows = await (select(
      vodStreams,
    )..where((vs) => vs.categoryId.equals(categoryId))).get();

    return rows.map((row) => VodStream.fromDriftVodStream(row)).toList();
  }

  Future<List<VodStream>> getVodStreamsFiltered({
    String? categoryId,
    String? playlistId,
    String? searchQuery,
  }) async {
    final query = select(vodStreams);

    if (categoryId != null && playlistId != null) {
      query.where(
        (vs) =>
            vs.categoryId.equals(categoryId) & vs.playlistId.equals(playlistId),
      );
    } else if (categoryId != null) {
      query.where((vs) => vs.categoryId.equals(categoryId));
    } else if (playlistId != null) {
      query.where((vs) => vs.playlistId.equals(playlistId));
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query.where((vs) => vs.name.like('%$searchQuery%'));
    }

    final rows = await query.get();
    return rows.map((row) => VodStream.fromDriftVodStream(row)).toList();
  }

  Future<void> deleteVodStreamsByPlaylistId(String playlistId) async {
    await (delete(
      vodStreams,
    )..where((vs) => vs.playlistId.equals(playlistId))).go();
  }

  Future<void> deleteVodStreamsByCategoryAndPlaylistId({
    required String categoryId,
    required String playlistId,
  }) async {
    await (delete(vodStreams)..where(
          (vs) =>
              vs.categoryId.equals(categoryId) &
              vs.playlistId.equals(playlistId),
        ))
        .go();
  }

  Future<void> insertSeriesStreams(List<SeriesStream> seriesStreams) async {
    final seriesStreamsCompanions = seriesStreams
        .map((seriesStream) => seriesStream.toDriftCompanion())
        .toList();

    await batch((batch) {
      batch.insertAllOnConflictUpdate(
        this.seriesStreams,
        seriesStreamsCompanions,
      );
    });
  }

  Future<List<SeriesStream>> getSeriesStreamsByPlaylistId(
    String playlistId,
  ) async {
    final rows = await (select(
      seriesStreams,
    )..where((ss) => ss.playlistId.equals(playlistId))).get();

    return rows.map((row) => SeriesStream.fromDriftSeriesStream(row)).toList();
  }

  Future<List<SeriesStream>> getSeriesStreamsByCategoryAndPlaylistId({
    required String categoryId,
    required String playlistId,
    int? top,
  }) async {
    var query = select(seriesStreams)
      ..where(
        (ss) =>
            ss.categoryId.equals(categoryId) & ss.playlistId.equals(playlistId),
      );

    if (top != null) {
      query = query..limit(top);
    }

    final rows = await query.get();

    return rows.map((row) => SeriesStream.fromDriftSeriesStream(row)).toList();
  }

  Future<List<SeriesStream>> getSeriesStreamsByCategory(
    String categoryId,
  ) async {
    final rows = await (select(
      seriesStreams,
    )..where((ss) => ss.categoryId.equals(categoryId))).get();

    return rows.map((row) => SeriesStream.fromDriftSeriesStream(row)).toList();
  }

  Future<List<SeriesStream>> getSeriesStreamsFiltered({
    String? categoryId,
    String? playlistId,
    String? searchQuery,
  }) async {
    final query = select(seriesStreams);

    if (categoryId != null && playlistId != null) {
      query.where(
        (ss) =>
            ss.categoryId.equals(categoryId) & ss.playlistId.equals(playlistId),
      );
    } else if (categoryId != null) {
      query.where((ss) => ss.categoryId.equals(categoryId));
    } else if (playlistId != null) {
      query.where((ss) => ss.playlistId.equals(playlistId));
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query.where((ss) => ss.name.like('%$searchQuery%'));
    }

    final rows = await query.get();
    return rows.map((row) => SeriesStream.fromDriftSeriesStream(row)).toList();
  }

  Future<void> deleteSeriesStreamsByPlaylistId(String playlistId) async {
    await (delete(
      seriesStreams,
    )..where((ss) => ss.playlistId.equals(playlistId))).go();
  }

  Future<void> deleteSeriesStreamsByCategoryAndPlaylistId({
    required String categoryId,
    required String playlistId,
  }) async {
    await (delete(seriesStreams)..where(
          (ss) =>
              ss.categoryId.equals(categoryId) &
              ss.playlistId.equals(playlistId),
        ))
        .go();
  }

  // Series Info CRUD Operations
  Future<int> insertSeriesInfo(SeriesInfosCompanion seriesInfo) {
    return into(seriesInfos).insert(seriesInfo);
  }

  Future<SeriesInfosData?> getSeriesInfo(String seriesId, String playlistId) {
    return (select(seriesInfos)..where(
          (tbl) =>
              tbl.seriesId.equals(seriesId) & tbl.playlistId.equals(playlistId),
        ))
        .getSingleOrNull();
  }

  // Seasons CRUD Operations
  Future<int> insertSeason(SeasonsCompanion season) {
    return into(seasons).insert(season);
  }

  Future<List<SeasonsData>> getSeasonsBySeriesId(
    String seriesId,
    String playlistId,
  ) {
    return (select(seasons)..where(
          (tbl) =>
              tbl.seriesId.equals(seriesId) & tbl.playlistId.equals(playlistId),
        ))
        .get();
  }

  // Episodes CRUD Operations
  Future<int> insertEpisode(EpisodesCompanion episode) {
    return into(episodes).insert(episode);
  }

  Future<List<EpisodesData>> getEpisodesBySeriesId(
    String seriesId,
    String playlistId,
  ) {
    return (select(episodes)..where(
          (tbl) =>
              tbl.seriesId.equals(seriesId) & tbl.seriesId.equals(seriesId),
        ))
        .get();
  }

  Future<List<EpisodesData>> getEpisodesBySeason(
    String seriesId,
    int seasonNumber,
    String playlistId,
  ) {
    return (select(episodes)..where(
          (tbl) =>
              tbl.seriesId.equals(seriesId) &
              tbl.season.equals(seasonNumber) &
              tbl.seriesId.equals(seriesId),
        ))
        .get();
  }

  Future<EpisodesData?> findEpisodesById(String episodeId, String playlistId) {
    return (select(episodes)..where(
          (tbl) =>
              tbl.playlistId.equals(playlistId) &
              tbl.episodeId.equals(episodeId),
        ))
        .getSingleOrNull();
  }

  Future<VodStream?> findMovieById(String streamId, String playlistId) async {
    var vodStreamData =
        await (select(vodStreams)..where(
              (tbl) =>
                  tbl.playlistId.equals(playlistId) &
                  tbl.streamId.equals(streamId),
            ))
            .getSingleOrNull();

    return vodStreamData != null
        ? VodStream.fromDriftVodStream(vodStreamData)
        : null;
  }

  Future<LiveStream?> findLiveStreamById(
    String streamId,
    String playlistId,
  ) async {
    var liveStreamData =
        await (select(liveStreams)..where(
              (tbl) =>
                  tbl.playlistId.equals(playlistId) &
                  tbl.streamId.equals(streamId),
            ))
            .getSingleOrNull();

    return liveStreamData != null
        ? LiveStream.fromDriftLiveStream(liveStreamData)
        : null;
  }

  Future<int> clearSeriesData(String seriesId, String playlistId) async {
    await (delete(episodes)..where(
          (tbl) =>
              tbl.seriesId.equals(seriesId) & tbl.seriesId.equals(seriesId),
        ))
        .go();
    await (delete(seasons)..where(
          (tbl) =>
              tbl.seriesId.equals(seriesId) & tbl.seriesId.equals(seriesId),
        ))
        .go();
    return await (delete(seriesInfos)..where(
          (tbl) =>
              tbl.seriesId.equals(seriesId) & tbl.seriesId.equals(seriesId),
        ))
        .go();
  }

  Future<List<LiveStream>> searchLiveStreams(
    String playlistId,
    String query,
  ) async {
    final liveStreamList =
        await (select(liveStreams)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    tbl.name.contains(query),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.name)])
              ..limit(20))
            .get();

    return liveStreamList
        .map((x) => LiveStream.fromDriftLiveStream(x))
        .toList();
  }

  Future<List<VodStream>> searchMovie(String playlistId, String query) async {
    final movieList =
        await (select(vodStreams)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    tbl.name.contains(query),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.name)])
              ..limit(20))
            .get();

    return movieList.map((x) => VodStream.fromDriftVodStream(x)).toList();
  }

  Future<int> insertM3uItem(M3uItem item) {
    return into(m3uItems).insert(item.toCompanion());
  }

  Future<void> insertM3uItems(List<M3uItem> items) {
    return batch((batch) {
      batch.insertAll(m3uItems, items.map((item) => item.toCompanion()));
    });
  }

  Future<bool> updateM3uItem(M3uItem item) {
    return update(m3uItems).replace(item.toCompanion());
  }

  Future<List<M3uItem>> getM3uItemsByCategoryId(
    String playlistId,
    String categoryId, {
    int? top,
    ContentType? contentType,
  }) async {
    var query = select(m3uItems)
      ..where(
        (ls) =>
            ls.playlistId.equals(playlistId) & ls.categoryId.equals(categoryId),
      );

    if (top != null) {
      query = query..limit(top);
    }

    if (contentType != null) {
      query = query..where((x) => x.contentType.equals(contentType.index));
    }

    final rows = await query.get();

    return rows.map((row) => M3uItem.fromData(row)).toList();
  }

  Future<int> deleteM3uItem(String playlistId, String url) {
    return (delete(m3uItems)..where(
          (tbl) => tbl.playlistId.equals(playlistId) & tbl.url.equals(url),
        ))
        .go();
  }

  Future<List<M3uItem>> getM3uItemsByPlaylist(String playlistId) async {
    final data = await (select(
      m3uItems,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).get();
    return data.map((item) => M3uItem.fromData(item)).toList();
  }

  Future<M3uItem?> getM3uItemsByIdAndPlaylist(
    String playlistId,
    String id,
  ) async {
    final query = select(m3uItems)
      ..where((tbl) => tbl.id.equals(id) & tbl.playlistId.equals(playlistId));
    final data = await query.getSingleOrNull();

    if (data == null) return null;
    return M3uItem.fromData(data);
  }

  Future<M3uItem?> getM3uItemsByUrlAndPlaylist(
    String playlistId,
    String url,
  ) async {
    final query = select(m3uItems)
      ..where((tbl) => tbl.url.equals(url) & tbl.playlistId.equals(playlistId));
    final data = await query.getSingleOrNull();

    if (data == null) return null;
    return M3uItem.fromData(data);
  }

  Future<List<M3uItem>> getM3uItemsByCategory(String categoryId) async {
    final data = await (select(
      m3uItems,
    )..where((tbl) => tbl.categoryId.equals(categoryId))).get();
    return data.map((item) => M3uItem.fromData(item)).toList();
  }

  Future<List<SeriesStream>> searchSeries(
    String playlistId,
    String query,
  ) async {
    final seriesList =
        await (select(seriesStreams)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    tbl.name.contains(query),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.name)])
              ..limit(20))
            .get();

    return seriesList
        .map((x) => SeriesStream.fromDriftSeriesStream(x))
        .toList();
  }

  Future<void> insertM3uSeries(List<M3uSeriesCompanion> seriesList) async {
    await batch((batch) {
      batch.insertAll(m3uSeries, seriesList, mode: InsertMode.insertOrReplace);
    });
  }

  Future<void> insertM3uEpisodes(
    List<M3uEpisodesCompanion> episodesList,
  ) async {
    await batch((batch) {
      batch.insertAll(
        m3uEpisodes,
        episodesList,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<List<M3uSerie>> getM3uSeriesByCategoryId(
    String playlistId,
    String categoryId, {
    int? top,
  }) async {
    var query = select(m3uSeries)
      ..where(
        (ls) =>
            ls.playlistId.equals(playlistId) & ls.categoryId.equals(categoryId),
      );

    if (top != null) {
      query = query..limit(top);
    }

    final rows = await query.get();

    return rows.map((row) => M3uSerie.fromData(row)).toList();
  }

  Future<List<M3uEpisode>> getM3uEpisodesBySeriesId(
    String playlistId,
    String seriesId,
  ) async {
    var query = select(m3uEpisodes)
      ..where(
        (ls) => ls.playlistId.equals(playlistId) & ls.seriesId.equals(seriesId),
      );

    final rows = await query.get();

    return rows.map((row) => M3uEpisode.fromData(row)).toList();
  }

  Future<void> insertFavorite(Favorite favorite) async {
    await into(favorites).insert(favorite.toCompanion());
  }

  Future<void> updateFavorite(Favorite favorite) async {
    await (update(
      favorites,
    )..where((f) => f.id.equals(favorite.id))).write(favorite.toCompanion());
  }

  Future<void> deleteFavorite(String id) async {
    await (delete(favorites)..where((f) => f.id.equals(id))).go();
  }

  Future<List<Favorite>> getAllFavorites() async {
    final favoritesData = await select(favorites).get();
    return favoritesData.map((data) => Favorite.fromDrift(data)).toList();
  }

  Future<List<Favorite>> getFavoritesByPlaylist(String playlistId) async {
    final query = select(favorites)
      ..where((f) => f.playlistId.equals(playlistId))
      ..orderBy([(f) => OrderingTerm.desc(f.createdAt)]);
    final favoritesData = await query.get();
    return favoritesData.map((data) => Favorite.fromDrift(data)).toList();
  }

  Future<List<Favorite>> getFavoritesByContentType(
    String playlistId,
    ContentType contentType,
  ) async {
    final query = select(favorites)
      ..where(
        (f) =>
            f.playlistId.equals(playlistId) &
            f.contentType.equals(contentType.index),
      )
      ..orderBy([(f) => OrderingTerm.desc(f.createdAt)]);
    final favoritesData = await query.get();
    return favoritesData.map((data) => Favorite.fromDrift(data)).toList();
  }

  Future<bool> isFavorite(
    String playlistId,
    String streamId,
    ContentType contentType,
    String? episodeId,
  ) async {
    final query = select(favorites)
      ..where(
        (f) =>
            f.playlistId.equals(playlistId) &
            f.streamId.equals(streamId) &
            f.contentType.equals(contentType.index) &
            (episodeId == null
                ? f.episodeId.isNull()
                : f.episodeId.equals(episodeId)),
      );
    final result = await query.getSingleOrNull();
    return result != null;
  }

  // Favori sayısını getir
  Future<int> getFavoriteCount(String playlistId) async {
    final query = select(favorites)
      ..where((f) => f.playlistId.equals(playlistId));
    final result = await query.get();
    return result.length;
  }

  // İçerik tipine göre favori sayısını getir
  Future<int> getFavoriteCountByContentType(
    String playlistId,
    ContentType contentType,
  ) async {
    final query = select(favorites)
      ..where(
        (f) =>
            f.playlistId.equals(playlistId) &
            f.contentType.equals(contentType.index),
      );
    final result = await query.get();
    return result.length;
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from <= 2) {
        await m.createTable(categories);
        await m.createTable(userInfos);
        await m.createTable(serverInfos);
        await m.createTable(liveStreams);
        await m.createTable(vodStreams);
        await m.createTable(seriesStreams);
        // await m.addColumn(seriesStreams, seriesStreams.lastModified);
        // await m.addColumn(seriesStreams, seriesStreams.backdropPath);
        await customStatement('''
        UPDATE series_streams 
        SET last_modified = '0', backdrop_path = '[]' 
        WHERE last_modified IS NULL OR backdrop_path IS NULL
      ''');
        await m.createTable(seriesInfos);
        await m.createTable(seasons);
        await m.createTable(episodes);
        await m.createTable(watchHistories);
      }

      if (from <= 3) {
        await customStatement('''
          UPDATE playlists 
          SET type = 'PlaylistType.xtream' 
          WHERE type = 'PlaylistType.xstream'
        ''');
      }

      if (from <= 4) {
        await m.createTable(m3uItems);
      }

      if (from <= 5) {
        await m.createTable(m3uSeries);
        await m.createTable(m3uEpisodes);
      }

      if (from <= 6) {
        await m.deleteTable('m3u_items');
        await m.createTable(m3uItems);
      }

      if (from <= 7) {
        await m.createTable(favorites);
      }
    },
  );

  Future<void> deleteDatabase() async {
    await close();
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'playlists.sqlite'));

    if (await file.exists()) {
      await file.delete();
    }
  }
}
