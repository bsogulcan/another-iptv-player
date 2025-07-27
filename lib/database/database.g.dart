// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $PlaylistsTable extends Playlists
    with TableInfo<$PlaylistsTable, PlaylistData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _passwordMeta = const VerificationMeta(
    'password',
  );
  @override
  late final GeneratedColumn<String> password = GeneratedColumn<String>(
    'password',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    type,
    url,
    username,
    password,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('password')) {
      context.handle(
        _passwordMeta,
        password.isAcceptableOrUnknown(data['password']!, _passwordMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaylistData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      ),
      password: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PlaylistsTable createAlias(String alias) {
    return $PlaylistsTable(attachedDatabase, alias);
  }
}

class PlaylistData extends DataClass implements Insertable<PlaylistData> {
  final String id;
  final String name;
  final String type;
  final String? url;
  final String? username;
  final String? password;
  final DateTime createdAt;
  const PlaylistData({
    required this.id,
    required this.name,
    required this.type,
    this.url,
    this.username,
    this.password,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    if (!nullToAbsent || username != null) {
      map['username'] = Variable<String>(username);
    }
    if (!nullToAbsent || password != null) {
      map['password'] = Variable<String>(password);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PlaylistsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      username: username == null && nullToAbsent
          ? const Value.absent()
          : Value(username),
      password: password == null && nullToAbsent
          ? const Value.absent()
          : Value(password),
      createdAt: Value(createdAt),
    );
  }

  factory PlaylistData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      url: serializer.fromJson<String?>(json['url']),
      username: serializer.fromJson<String?>(json['username']),
      password: serializer.fromJson<String?>(json['password']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'url': serializer.toJson<String?>(url),
      'username': serializer.toJson<String?>(username),
      'password': serializer.toJson<String?>(password),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PlaylistData copyWith({
    String? id,
    String? name,
    String? type,
    Value<String?> url = const Value.absent(),
    Value<String?> username = const Value.absent(),
    Value<String?> password = const Value.absent(),
    DateTime? createdAt,
  }) => PlaylistData(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    url: url.present ? url.value : this.url,
    username: username.present ? username.value : this.username,
    password: password.present ? password.value : this.password,
    createdAt: createdAt ?? this.createdAt,
  );
  PlaylistData copyWithCompanion(PlaylistsCompanion data) {
    return PlaylistData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      url: data.url.present ? data.url.value : this.url,
      username: data.username.present ? data.username.value : this.username,
      password: data.password.present ? data.password.value : this.password,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('url: $url, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, type, url, username, password, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistData &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.url == this.url &&
          other.username == this.username &&
          other.password == this.password &&
          other.createdAt == this.createdAt);
}

class PlaylistsCompanion extends UpdateCompanion<PlaylistData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> type;
  final Value<String?> url;
  final Value<String?> username;
  final Value<String?> password;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PlaylistsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.url = const Value.absent(),
    this.username = const Value.absent(),
    this.password = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistsCompanion.insert({
    required String id,
    required String name,
    required String type,
    this.url = const Value.absent(),
    this.username = const Value.absent(),
    this.password = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       type = Value(type),
       createdAt = Value(createdAt);
  static Insertable<PlaylistData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? url,
    Expression<String>? username,
    Expression<String>? password,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (url != null) 'url': url,
      if (username != null) 'username': username,
      if (password != null) 'password': password,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? type,
    Value<String?>? url,
    Value<String?>? username,
    Value<String?>? password,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return PlaylistsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (password.present) {
      map['password'] = Variable<String>(password.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('url: $url, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, CategoriesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryNameMeta = const VerificationMeta(
    'categoryName',
  );
  @override
  late final GeneratedColumn<String> categoryName = GeneratedColumn<String>(
    'category_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<int> parentId = GeneratedColumn<int>(
    'parent_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    categoryId,
    categoryName,
    parentId,
    playlistId,
    type,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<CategoriesData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('category_name')) {
      context.handle(
        _categoryNameMeta,
        categoryName.isAcceptableOrUnknown(
          data['category_name']!,
          _categoryNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_categoryNameMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {categoryId, playlistId, type};
  @override
  CategoriesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoriesData(
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      categoryName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_name'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parent_id'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class CategoriesData extends DataClass implements Insertable<CategoriesData> {
  final String categoryId;
  final String categoryName;
  final int parentId;
  final String playlistId;
  final String type;
  final DateTime createdAt;
  final DateTime updatedAt;
  const CategoriesData({
    required this.categoryId,
    required this.categoryName,
    required this.parentId,
    required this.playlistId,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['category_id'] = Variable<String>(categoryId);
    map['category_name'] = Variable<String>(categoryName);
    map['parent_id'] = Variable<int>(parentId);
    map['playlist_id'] = Variable<String>(playlistId);
    map['type'] = Variable<String>(type);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      categoryId: Value(categoryId),
      categoryName: Value(categoryName),
      parentId: Value(parentId),
      playlistId: Value(playlistId),
      type: Value(type),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CategoriesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoriesData(
      categoryId: serializer.fromJson<String>(json['categoryId']),
      categoryName: serializer.fromJson<String>(json['categoryName']),
      parentId: serializer.fromJson<int>(json['parentId']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      type: serializer.fromJson<String>(json['type']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'categoryId': serializer.toJson<String>(categoryId),
      'categoryName': serializer.toJson<String>(categoryName),
      'parentId': serializer.toJson<int>(parentId),
      'playlistId': serializer.toJson<String>(playlistId),
      'type': serializer.toJson<String>(type),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CategoriesData copyWith({
    String? categoryId,
    String? categoryName,
    int? parentId,
    String? playlistId,
    String? type,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CategoriesData(
    categoryId: categoryId ?? this.categoryId,
    categoryName: categoryName ?? this.categoryName,
    parentId: parentId ?? this.parentId,
    playlistId: playlistId ?? this.playlistId,
    type: type ?? this.type,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CategoriesData copyWithCompanion(CategoriesCompanion data) {
    return CategoriesData(
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      categoryName: data.categoryName.present
          ? data.categoryName.value
          : this.categoryName,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      type: data.type.present ? data.type.value : this.type,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesData(')
          ..write('categoryId: $categoryId, ')
          ..write('categoryName: $categoryName, ')
          ..write('parentId: $parentId, ')
          ..write('playlistId: $playlistId, ')
          ..write('type: $type, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    categoryId,
    categoryName,
    parentId,
    playlistId,
    type,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoriesData &&
          other.categoryId == this.categoryId &&
          other.categoryName == this.categoryName &&
          other.parentId == this.parentId &&
          other.playlistId == this.playlistId &&
          other.type == this.type &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CategoriesCompanion extends UpdateCompanion<CategoriesData> {
  final Value<String> categoryId;
  final Value<String> categoryName;
  final Value<int> parentId;
  final Value<String> playlistId;
  final Value<String> type;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.categoryId = const Value.absent(),
    this.categoryName = const Value.absent(),
    this.parentId = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.type = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String categoryId,
    required String categoryName,
    this.parentId = const Value.absent(),
    required String playlistId,
    required String type,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : categoryId = Value(categoryId),
       categoryName = Value(categoryName),
       playlistId = Value(playlistId),
       type = Value(type);
  static Insertable<CategoriesData> custom({
    Expression<String>? categoryId,
    Expression<String>? categoryName,
    Expression<int>? parentId,
    Expression<String>? playlistId,
    Expression<String>? type,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (categoryId != null) 'category_id': categoryId,
      if (categoryName != null) 'category_name': categoryName,
      if (parentId != null) 'parent_id': parentId,
      if (playlistId != null) 'playlist_id': playlistId,
      if (type != null) 'type': type,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? categoryId,
    Value<String>? categoryName,
    Value<int>? parentId,
    Value<String>? playlistId,
    Value<String>? type,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      parentId: parentId ?? this.parentId,
      playlistId: playlistId ?? this.playlistId,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (categoryName.present) {
      map['category_name'] = Variable<String>(categoryName.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<int>(parentId.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('categoryId: $categoryId, ')
          ..write('categoryName: $categoryName, ')
          ..write('parentId: $parentId, ')
          ..write('playlistId: $playlistId, ')
          ..write('type: $type, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserInfosTable extends UserInfos
    with TableInfo<$UserInfosTable, UserInfosData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserInfosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _passwordMeta = const VerificationMeta(
    'password',
  );
  @override
  late final GeneratedColumn<String> password = GeneratedColumn<String>(
    'password',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authMeta = const VerificationMeta('auth');
  @override
  late final GeneratedColumn<int> auth = GeneratedColumn<int>(
    'auth',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expDateMeta = const VerificationMeta(
    'expDate',
  );
  @override
  late final GeneratedColumn<String> expDate = GeneratedColumn<String>(
    'exp_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isTrialMeta = const VerificationMeta(
    'isTrial',
  );
  @override
  late final GeneratedColumn<String> isTrial = GeneratedColumn<String>(
    'is_trial',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeConsMeta = const VerificationMeta(
    'activeCons',
  );
  @override
  late final GeneratedColumn<String> activeCons = GeneratedColumn<String>(
    'active_cons',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maxConnectionsMeta = const VerificationMeta(
    'maxConnections',
  );
  @override
  late final GeneratedColumn<String> maxConnections = GeneratedColumn<String>(
    'max_connections',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _allowedOutputFormatsMeta =
      const VerificationMeta('allowedOutputFormats');
  @override
  late final GeneratedColumn<String> allowedOutputFormats =
      GeneratedColumn<String>(
        'allowed_output_formats',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    playlistId,
    username,
    password,
    message,
    auth,
    status,
    expDate,
    isTrial,
    activeCons,
    createdAt,
    maxConnections,
    allowedOutputFormats,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_infos';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserInfosData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('password')) {
      context.handle(
        _passwordMeta,
        password.isAcceptableOrUnknown(data['password']!, _passwordMeta),
      );
    } else if (isInserting) {
      context.missing(_passwordMeta);
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    } else if (isInserting) {
      context.missing(_messageMeta);
    }
    if (data.containsKey('auth')) {
      context.handle(
        _authMeta,
        auth.isAcceptableOrUnknown(data['auth']!, _authMeta),
      );
    } else if (isInserting) {
      context.missing(_authMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('exp_date')) {
      context.handle(
        _expDateMeta,
        expDate.isAcceptableOrUnknown(data['exp_date']!, _expDateMeta),
      );
    } else if (isInserting) {
      context.missing(_expDateMeta);
    }
    if (data.containsKey('is_trial')) {
      context.handle(
        _isTrialMeta,
        isTrial.isAcceptableOrUnknown(data['is_trial']!, _isTrialMeta),
      );
    } else if (isInserting) {
      context.missing(_isTrialMeta);
    }
    if (data.containsKey('active_cons')) {
      context.handle(
        _activeConsMeta,
        activeCons.isAcceptableOrUnknown(data['active_cons']!, _activeConsMeta),
      );
    } else if (isInserting) {
      context.missing(_activeConsMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('max_connections')) {
      context.handle(
        _maxConnectionsMeta,
        maxConnections.isAcceptableOrUnknown(
          data['max_connections']!,
          _maxConnectionsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_maxConnectionsMeta);
    }
    if (data.containsKey('allowed_output_formats')) {
      context.handle(
        _allowedOutputFormatsMeta,
        allowedOutputFormats.isAcceptableOrUnknown(
          data['allowed_output_formats']!,
          _allowedOutputFormatsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_allowedOutputFormatsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserInfosData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserInfosData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      password: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      )!,
      auth: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}auth'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      expDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exp_date'],
      )!,
      isTrial: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}is_trial'],
      )!,
      activeCons: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}active_cons'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      maxConnections: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}max_connections'],
      )!,
      allowedOutputFormats: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}allowed_output_formats'],
      )!,
    );
  }

  @override
  $UserInfosTable createAlias(String alias) {
    return $UserInfosTable(attachedDatabase, alias);
  }
}

class UserInfosData extends DataClass implements Insertable<UserInfosData> {
  final int id;
  final String playlistId;
  final String username;
  final String password;
  final String message;
  final int auth;
  final String status;
  final String expDate;
  final String isTrial;
  final String activeCons;
  final String createdAt;
  final String maxConnections;
  final String allowedOutputFormats;
  const UserInfosData({
    required this.id,
    required this.playlistId,
    required this.username,
    required this.password,
    required this.message,
    required this.auth,
    required this.status,
    required this.expDate,
    required this.isTrial,
    required this.activeCons,
    required this.createdAt,
    required this.maxConnections,
    required this.allowedOutputFormats,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['playlist_id'] = Variable<String>(playlistId);
    map['username'] = Variable<String>(username);
    map['password'] = Variable<String>(password);
    map['message'] = Variable<String>(message);
    map['auth'] = Variable<int>(auth);
    map['status'] = Variable<String>(status);
    map['exp_date'] = Variable<String>(expDate);
    map['is_trial'] = Variable<String>(isTrial);
    map['active_cons'] = Variable<String>(activeCons);
    map['created_at'] = Variable<String>(createdAt);
    map['max_connections'] = Variable<String>(maxConnections);
    map['allowed_output_formats'] = Variable<String>(allowedOutputFormats);
    return map;
  }

  UserInfosCompanion toCompanion(bool nullToAbsent) {
    return UserInfosCompanion(
      id: Value(id),
      playlistId: Value(playlistId),
      username: Value(username),
      password: Value(password),
      message: Value(message),
      auth: Value(auth),
      status: Value(status),
      expDate: Value(expDate),
      isTrial: Value(isTrial),
      activeCons: Value(activeCons),
      createdAt: Value(createdAt),
      maxConnections: Value(maxConnections),
      allowedOutputFormats: Value(allowedOutputFormats),
    );
  }

  factory UserInfosData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserInfosData(
      id: serializer.fromJson<int>(json['id']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      username: serializer.fromJson<String>(json['username']),
      password: serializer.fromJson<String>(json['password']),
      message: serializer.fromJson<String>(json['message']),
      auth: serializer.fromJson<int>(json['auth']),
      status: serializer.fromJson<String>(json['status']),
      expDate: serializer.fromJson<String>(json['expDate']),
      isTrial: serializer.fromJson<String>(json['isTrial']),
      activeCons: serializer.fromJson<String>(json['activeCons']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      maxConnections: serializer.fromJson<String>(json['maxConnections']),
      allowedOutputFormats: serializer.fromJson<String>(
        json['allowedOutputFormats'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'playlistId': serializer.toJson<String>(playlistId),
      'username': serializer.toJson<String>(username),
      'password': serializer.toJson<String>(password),
      'message': serializer.toJson<String>(message),
      'auth': serializer.toJson<int>(auth),
      'status': serializer.toJson<String>(status),
      'expDate': serializer.toJson<String>(expDate),
      'isTrial': serializer.toJson<String>(isTrial),
      'activeCons': serializer.toJson<String>(activeCons),
      'createdAt': serializer.toJson<String>(createdAt),
      'maxConnections': serializer.toJson<String>(maxConnections),
      'allowedOutputFormats': serializer.toJson<String>(allowedOutputFormats),
    };
  }

  UserInfosData copyWith({
    int? id,
    String? playlistId,
    String? username,
    String? password,
    String? message,
    int? auth,
    String? status,
    String? expDate,
    String? isTrial,
    String? activeCons,
    String? createdAt,
    String? maxConnections,
    String? allowedOutputFormats,
  }) => UserInfosData(
    id: id ?? this.id,
    playlistId: playlistId ?? this.playlistId,
    username: username ?? this.username,
    password: password ?? this.password,
    message: message ?? this.message,
    auth: auth ?? this.auth,
    status: status ?? this.status,
    expDate: expDate ?? this.expDate,
    isTrial: isTrial ?? this.isTrial,
    activeCons: activeCons ?? this.activeCons,
    createdAt: createdAt ?? this.createdAt,
    maxConnections: maxConnections ?? this.maxConnections,
    allowedOutputFormats: allowedOutputFormats ?? this.allowedOutputFormats,
  );
  UserInfosData copyWithCompanion(UserInfosCompanion data) {
    return UserInfosData(
      id: data.id.present ? data.id.value : this.id,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      username: data.username.present ? data.username.value : this.username,
      password: data.password.present ? data.password.value : this.password,
      message: data.message.present ? data.message.value : this.message,
      auth: data.auth.present ? data.auth.value : this.auth,
      status: data.status.present ? data.status.value : this.status,
      expDate: data.expDate.present ? data.expDate.value : this.expDate,
      isTrial: data.isTrial.present ? data.isTrial.value : this.isTrial,
      activeCons: data.activeCons.present
          ? data.activeCons.value
          : this.activeCons,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      maxConnections: data.maxConnections.present
          ? data.maxConnections.value
          : this.maxConnections,
      allowedOutputFormats: data.allowedOutputFormats.present
          ? data.allowedOutputFormats.value
          : this.allowedOutputFormats,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserInfosData(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('message: $message, ')
          ..write('auth: $auth, ')
          ..write('status: $status, ')
          ..write('expDate: $expDate, ')
          ..write('isTrial: $isTrial, ')
          ..write('activeCons: $activeCons, ')
          ..write('createdAt: $createdAt, ')
          ..write('maxConnections: $maxConnections, ')
          ..write('allowedOutputFormats: $allowedOutputFormats')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    playlistId,
    username,
    password,
    message,
    auth,
    status,
    expDate,
    isTrial,
    activeCons,
    createdAt,
    maxConnections,
    allowedOutputFormats,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserInfosData &&
          other.id == this.id &&
          other.playlistId == this.playlistId &&
          other.username == this.username &&
          other.password == this.password &&
          other.message == this.message &&
          other.auth == this.auth &&
          other.status == this.status &&
          other.expDate == this.expDate &&
          other.isTrial == this.isTrial &&
          other.activeCons == this.activeCons &&
          other.createdAt == this.createdAt &&
          other.maxConnections == this.maxConnections &&
          other.allowedOutputFormats == this.allowedOutputFormats);
}

class UserInfosCompanion extends UpdateCompanion<UserInfosData> {
  final Value<int> id;
  final Value<String> playlistId;
  final Value<String> username;
  final Value<String> password;
  final Value<String> message;
  final Value<int> auth;
  final Value<String> status;
  final Value<String> expDate;
  final Value<String> isTrial;
  final Value<String> activeCons;
  final Value<String> createdAt;
  final Value<String> maxConnections;
  final Value<String> allowedOutputFormats;
  const UserInfosCompanion({
    this.id = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.username = const Value.absent(),
    this.password = const Value.absent(),
    this.message = const Value.absent(),
    this.auth = const Value.absent(),
    this.status = const Value.absent(),
    this.expDate = const Value.absent(),
    this.isTrial = const Value.absent(),
    this.activeCons = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.maxConnections = const Value.absent(),
    this.allowedOutputFormats = const Value.absent(),
  });
  UserInfosCompanion.insert({
    this.id = const Value.absent(),
    required String playlistId,
    required String username,
    required String password,
    required String message,
    required int auth,
    required String status,
    required String expDate,
    required String isTrial,
    required String activeCons,
    required String createdAt,
    required String maxConnections,
    required String allowedOutputFormats,
  }) : playlistId = Value(playlistId),
       username = Value(username),
       password = Value(password),
       message = Value(message),
       auth = Value(auth),
       status = Value(status),
       expDate = Value(expDate),
       isTrial = Value(isTrial),
       activeCons = Value(activeCons),
       createdAt = Value(createdAt),
       maxConnections = Value(maxConnections),
       allowedOutputFormats = Value(allowedOutputFormats);
  static Insertable<UserInfosData> custom({
    Expression<int>? id,
    Expression<String>? playlistId,
    Expression<String>? username,
    Expression<String>? password,
    Expression<String>? message,
    Expression<int>? auth,
    Expression<String>? status,
    Expression<String>? expDate,
    Expression<String>? isTrial,
    Expression<String>? activeCons,
    Expression<String>? createdAt,
    Expression<String>? maxConnections,
    Expression<String>? allowedOutputFormats,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (playlistId != null) 'playlist_id': playlistId,
      if (username != null) 'username': username,
      if (password != null) 'password': password,
      if (message != null) 'message': message,
      if (auth != null) 'auth': auth,
      if (status != null) 'status': status,
      if (expDate != null) 'exp_date': expDate,
      if (isTrial != null) 'is_trial': isTrial,
      if (activeCons != null) 'active_cons': activeCons,
      if (createdAt != null) 'created_at': createdAt,
      if (maxConnections != null) 'max_connections': maxConnections,
      if (allowedOutputFormats != null)
        'allowed_output_formats': allowedOutputFormats,
    });
  }

  UserInfosCompanion copyWith({
    Value<int>? id,
    Value<String>? playlistId,
    Value<String>? username,
    Value<String>? password,
    Value<String>? message,
    Value<int>? auth,
    Value<String>? status,
    Value<String>? expDate,
    Value<String>? isTrial,
    Value<String>? activeCons,
    Value<String>? createdAt,
    Value<String>? maxConnections,
    Value<String>? allowedOutputFormats,
  }) {
    return UserInfosCompanion(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      username: username ?? this.username,
      password: password ?? this.password,
      message: message ?? this.message,
      auth: auth ?? this.auth,
      status: status ?? this.status,
      expDate: expDate ?? this.expDate,
      isTrial: isTrial ?? this.isTrial,
      activeCons: activeCons ?? this.activeCons,
      createdAt: createdAt ?? this.createdAt,
      maxConnections: maxConnections ?? this.maxConnections,
      allowedOutputFormats: allowedOutputFormats ?? this.allowedOutputFormats,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (password.present) {
      map['password'] = Variable<String>(password.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (auth.present) {
      map['auth'] = Variable<int>(auth.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (expDate.present) {
      map['exp_date'] = Variable<String>(expDate.value);
    }
    if (isTrial.present) {
      map['is_trial'] = Variable<String>(isTrial.value);
    }
    if (activeCons.present) {
      map['active_cons'] = Variable<String>(activeCons.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (maxConnections.present) {
      map['max_connections'] = Variable<String>(maxConnections.value);
    }
    if (allowedOutputFormats.present) {
      map['allowed_output_formats'] = Variable<String>(
        allowedOutputFormats.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserInfosCompanion(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('message: $message, ')
          ..write('auth: $auth, ')
          ..write('status: $status, ')
          ..write('expDate: $expDate, ')
          ..write('isTrial: $isTrial, ')
          ..write('activeCons: $activeCons, ')
          ..write('createdAt: $createdAt, ')
          ..write('maxConnections: $maxConnections, ')
          ..write('allowedOutputFormats: $allowedOutputFormats')
          ..write(')'))
        .toString();
  }
}

class $ServerInfosTable extends ServerInfos
    with TableInfo<$ServerInfosTable, ServerInfosData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServerInfosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<String> port = GeneratedColumn<String>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _httpsPortMeta = const VerificationMeta(
    'httpsPort',
  );
  @override
  late final GeneratedColumn<String> httpsPort = GeneratedColumn<String>(
    'https_port',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverProtocolMeta = const VerificationMeta(
    'serverProtocol',
  );
  @override
  late final GeneratedColumn<String> serverProtocol = GeneratedColumn<String>(
    'server_protocol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rtmpPortMeta = const VerificationMeta(
    'rtmpPort',
  );
  @override
  late final GeneratedColumn<String> rtmpPort = GeneratedColumn<String>(
    'rtmp_port',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timezoneMeta = const VerificationMeta(
    'timezone',
  );
  @override
  late final GeneratedColumn<String> timezone = GeneratedColumn<String>(
    'timezone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampNowMeta = const VerificationMeta(
    'timestampNow',
  );
  @override
  late final GeneratedColumn<int> timestampNow = GeneratedColumn<int>(
    'timestamp_now',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeNowMeta = const VerificationMeta(
    'timeNow',
  );
  @override
  late final GeneratedColumn<String> timeNow = GeneratedColumn<String>(
    'time_now',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    playlistId,
    url,
    port,
    httpsPort,
    serverProtocol,
    rtmpPort,
    timezone,
    timestampNow,
    timeNow,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'server_infos';
  @override
  VerificationContext validateIntegrity(
    Insertable<ServerInfosData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('https_port')) {
      context.handle(
        _httpsPortMeta,
        httpsPort.isAcceptableOrUnknown(data['https_port']!, _httpsPortMeta),
      );
    } else if (isInserting) {
      context.missing(_httpsPortMeta);
    }
    if (data.containsKey('server_protocol')) {
      context.handle(
        _serverProtocolMeta,
        serverProtocol.isAcceptableOrUnknown(
          data['server_protocol']!,
          _serverProtocolMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverProtocolMeta);
    }
    if (data.containsKey('rtmp_port')) {
      context.handle(
        _rtmpPortMeta,
        rtmpPort.isAcceptableOrUnknown(data['rtmp_port']!, _rtmpPortMeta),
      );
    } else if (isInserting) {
      context.missing(_rtmpPortMeta);
    }
    if (data.containsKey('timezone')) {
      context.handle(
        _timezoneMeta,
        timezone.isAcceptableOrUnknown(data['timezone']!, _timezoneMeta),
      );
    } else if (isInserting) {
      context.missing(_timezoneMeta);
    }
    if (data.containsKey('timestamp_now')) {
      context.handle(
        _timestampNowMeta,
        timestampNow.isAcceptableOrUnknown(
          data['timestamp_now']!,
          _timestampNowMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timestampNowMeta);
    }
    if (data.containsKey('time_now')) {
      context.handle(
        _timeNowMeta,
        timeNow.isAcceptableOrUnknown(data['time_now']!, _timeNowMeta),
      );
    } else if (isInserting) {
      context.missing(_timeNowMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ServerInfosData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ServerInfosData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}port'],
      )!,
      httpsPort: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}https_port'],
      )!,
      serverProtocol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_protocol'],
      )!,
      rtmpPort: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rtmp_port'],
      )!,
      timezone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone'],
      )!,
      timestampNow: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp_now'],
      )!,
      timeNow: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_now'],
      )!,
    );
  }

  @override
  $ServerInfosTable createAlias(String alias) {
    return $ServerInfosTable(attachedDatabase, alias);
  }
}

class ServerInfosData extends DataClass implements Insertable<ServerInfosData> {
  final int id;
  final String playlistId;
  final String url;
  final String port;
  final String httpsPort;
  final String serverProtocol;
  final String rtmpPort;
  final String timezone;
  final int timestampNow;
  final String timeNow;
  const ServerInfosData({
    required this.id,
    required this.playlistId,
    required this.url,
    required this.port,
    required this.httpsPort,
    required this.serverProtocol,
    required this.rtmpPort,
    required this.timezone,
    required this.timestampNow,
    required this.timeNow,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['playlist_id'] = Variable<String>(playlistId);
    map['url'] = Variable<String>(url);
    map['port'] = Variable<String>(port);
    map['https_port'] = Variable<String>(httpsPort);
    map['server_protocol'] = Variable<String>(serverProtocol);
    map['rtmp_port'] = Variable<String>(rtmpPort);
    map['timezone'] = Variable<String>(timezone);
    map['timestamp_now'] = Variable<int>(timestampNow);
    map['time_now'] = Variable<String>(timeNow);
    return map;
  }

  ServerInfosCompanion toCompanion(bool nullToAbsent) {
    return ServerInfosCompanion(
      id: Value(id),
      playlistId: Value(playlistId),
      url: Value(url),
      port: Value(port),
      httpsPort: Value(httpsPort),
      serverProtocol: Value(serverProtocol),
      rtmpPort: Value(rtmpPort),
      timezone: Value(timezone),
      timestampNow: Value(timestampNow),
      timeNow: Value(timeNow),
    );
  }

  factory ServerInfosData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ServerInfosData(
      id: serializer.fromJson<int>(json['id']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      url: serializer.fromJson<String>(json['url']),
      port: serializer.fromJson<String>(json['port']),
      httpsPort: serializer.fromJson<String>(json['httpsPort']),
      serverProtocol: serializer.fromJson<String>(json['serverProtocol']),
      rtmpPort: serializer.fromJson<String>(json['rtmpPort']),
      timezone: serializer.fromJson<String>(json['timezone']),
      timestampNow: serializer.fromJson<int>(json['timestampNow']),
      timeNow: serializer.fromJson<String>(json['timeNow']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'playlistId': serializer.toJson<String>(playlistId),
      'url': serializer.toJson<String>(url),
      'port': serializer.toJson<String>(port),
      'httpsPort': serializer.toJson<String>(httpsPort),
      'serverProtocol': serializer.toJson<String>(serverProtocol),
      'rtmpPort': serializer.toJson<String>(rtmpPort),
      'timezone': serializer.toJson<String>(timezone),
      'timestampNow': serializer.toJson<int>(timestampNow),
      'timeNow': serializer.toJson<String>(timeNow),
    };
  }

  ServerInfosData copyWith({
    int? id,
    String? playlistId,
    String? url,
    String? port,
    String? httpsPort,
    String? serverProtocol,
    String? rtmpPort,
    String? timezone,
    int? timestampNow,
    String? timeNow,
  }) => ServerInfosData(
    id: id ?? this.id,
    playlistId: playlistId ?? this.playlistId,
    url: url ?? this.url,
    port: port ?? this.port,
    httpsPort: httpsPort ?? this.httpsPort,
    serverProtocol: serverProtocol ?? this.serverProtocol,
    rtmpPort: rtmpPort ?? this.rtmpPort,
    timezone: timezone ?? this.timezone,
    timestampNow: timestampNow ?? this.timestampNow,
    timeNow: timeNow ?? this.timeNow,
  );
  ServerInfosData copyWithCompanion(ServerInfosCompanion data) {
    return ServerInfosData(
      id: data.id.present ? data.id.value : this.id,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      url: data.url.present ? data.url.value : this.url,
      port: data.port.present ? data.port.value : this.port,
      httpsPort: data.httpsPort.present ? data.httpsPort.value : this.httpsPort,
      serverProtocol: data.serverProtocol.present
          ? data.serverProtocol.value
          : this.serverProtocol,
      rtmpPort: data.rtmpPort.present ? data.rtmpPort.value : this.rtmpPort,
      timezone: data.timezone.present ? data.timezone.value : this.timezone,
      timestampNow: data.timestampNow.present
          ? data.timestampNow.value
          : this.timestampNow,
      timeNow: data.timeNow.present ? data.timeNow.value : this.timeNow,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ServerInfosData(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('url: $url, ')
          ..write('port: $port, ')
          ..write('httpsPort: $httpsPort, ')
          ..write('serverProtocol: $serverProtocol, ')
          ..write('rtmpPort: $rtmpPort, ')
          ..write('timezone: $timezone, ')
          ..write('timestampNow: $timestampNow, ')
          ..write('timeNow: $timeNow')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    playlistId,
    url,
    port,
    httpsPort,
    serverProtocol,
    rtmpPort,
    timezone,
    timestampNow,
    timeNow,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServerInfosData &&
          other.id == this.id &&
          other.playlistId == this.playlistId &&
          other.url == this.url &&
          other.port == this.port &&
          other.httpsPort == this.httpsPort &&
          other.serverProtocol == this.serverProtocol &&
          other.rtmpPort == this.rtmpPort &&
          other.timezone == this.timezone &&
          other.timestampNow == this.timestampNow &&
          other.timeNow == this.timeNow);
}

class ServerInfosCompanion extends UpdateCompanion<ServerInfosData> {
  final Value<int> id;
  final Value<String> playlistId;
  final Value<String> url;
  final Value<String> port;
  final Value<String> httpsPort;
  final Value<String> serverProtocol;
  final Value<String> rtmpPort;
  final Value<String> timezone;
  final Value<int> timestampNow;
  final Value<String> timeNow;
  const ServerInfosCompanion({
    this.id = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.url = const Value.absent(),
    this.port = const Value.absent(),
    this.httpsPort = const Value.absent(),
    this.serverProtocol = const Value.absent(),
    this.rtmpPort = const Value.absent(),
    this.timezone = const Value.absent(),
    this.timestampNow = const Value.absent(),
    this.timeNow = const Value.absent(),
  });
  ServerInfosCompanion.insert({
    this.id = const Value.absent(),
    required String playlistId,
    required String url,
    required String port,
    required String httpsPort,
    required String serverProtocol,
    required String rtmpPort,
    required String timezone,
    required int timestampNow,
    required String timeNow,
  }) : playlistId = Value(playlistId),
       url = Value(url),
       port = Value(port),
       httpsPort = Value(httpsPort),
       serverProtocol = Value(serverProtocol),
       rtmpPort = Value(rtmpPort),
       timezone = Value(timezone),
       timestampNow = Value(timestampNow),
       timeNow = Value(timeNow);
  static Insertable<ServerInfosData> custom({
    Expression<int>? id,
    Expression<String>? playlistId,
    Expression<String>? url,
    Expression<String>? port,
    Expression<String>? httpsPort,
    Expression<String>? serverProtocol,
    Expression<String>? rtmpPort,
    Expression<String>? timezone,
    Expression<int>? timestampNow,
    Expression<String>? timeNow,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (playlistId != null) 'playlist_id': playlistId,
      if (url != null) 'url': url,
      if (port != null) 'port': port,
      if (httpsPort != null) 'https_port': httpsPort,
      if (serverProtocol != null) 'server_protocol': serverProtocol,
      if (rtmpPort != null) 'rtmp_port': rtmpPort,
      if (timezone != null) 'timezone': timezone,
      if (timestampNow != null) 'timestamp_now': timestampNow,
      if (timeNow != null) 'time_now': timeNow,
    });
  }

  ServerInfosCompanion copyWith({
    Value<int>? id,
    Value<String>? playlistId,
    Value<String>? url,
    Value<String>? port,
    Value<String>? httpsPort,
    Value<String>? serverProtocol,
    Value<String>? rtmpPort,
    Value<String>? timezone,
    Value<int>? timestampNow,
    Value<String>? timeNow,
  }) {
    return ServerInfosCompanion(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      url: url ?? this.url,
      port: port ?? this.port,
      httpsPort: httpsPort ?? this.httpsPort,
      serverProtocol: serverProtocol ?? this.serverProtocol,
      rtmpPort: rtmpPort ?? this.rtmpPort,
      timezone: timezone ?? this.timezone,
      timestampNow: timestampNow ?? this.timestampNow,
      timeNow: timeNow ?? this.timeNow,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (port.present) {
      map['port'] = Variable<String>(port.value);
    }
    if (httpsPort.present) {
      map['https_port'] = Variable<String>(httpsPort.value);
    }
    if (serverProtocol.present) {
      map['server_protocol'] = Variable<String>(serverProtocol.value);
    }
    if (rtmpPort.present) {
      map['rtmp_port'] = Variable<String>(rtmpPort.value);
    }
    if (timezone.present) {
      map['timezone'] = Variable<String>(timezone.value);
    }
    if (timestampNow.present) {
      map['timestamp_now'] = Variable<int>(timestampNow.value);
    }
    if (timeNow.present) {
      map['time_now'] = Variable<String>(timeNow.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServerInfosCompanion(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('url: $url, ')
          ..write('port: $port, ')
          ..write('httpsPort: $httpsPort, ')
          ..write('serverProtocol: $serverProtocol, ')
          ..write('rtmpPort: $rtmpPort, ')
          ..write('timezone: $timezone, ')
          ..write('timestampNow: $timestampNow, ')
          ..write('timeNow: $timeNow')
          ..write(')'))
        .toString();
  }
}

class $LiveStreamsTable extends LiveStreams
    with TableInfo<$LiveStreamsTable, LiveStreamsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LiveStreamsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _streamIdMeta = const VerificationMeta(
    'streamId',
  );
  @override
  late final GeneratedColumn<String> streamId = GeneratedColumn<String>(
    'stream_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _streamIconMeta = const VerificationMeta(
    'streamIcon',
  );
  @override
  late final GeneratedColumn<String> streamIcon = GeneratedColumn<String>(
    'stream_icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _epgChannelIdMeta = const VerificationMeta(
    'epgChannelId',
  );
  @override
  late final GeneratedColumn<String> epgChannelId = GeneratedColumn<String>(
    'epg_channel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    streamId,
    name,
    streamIcon,
    categoryId,
    epgChannelId,
    playlistId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'live_streams';
  @override
  VerificationContext validateIntegrity(
    Insertable<LiveStreamsData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('stream_id')) {
      context.handle(
        _streamIdMeta,
        streamId.isAcceptableOrUnknown(data['stream_id']!, _streamIdMeta),
      );
    } else if (isInserting) {
      context.missing(_streamIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('stream_icon')) {
      context.handle(
        _streamIconMeta,
        streamIcon.isAcceptableOrUnknown(data['stream_icon']!, _streamIconMeta),
      );
    } else if (isInserting) {
      context.missing(_streamIconMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('epg_channel_id')) {
      context.handle(
        _epgChannelIdMeta,
        epgChannelId.isAcceptableOrUnknown(
          data['epg_channel_id']!,
          _epgChannelIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_epgChannelIdMeta);
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {streamId, playlistId};
  @override
  LiveStreamsData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LiveStreamsData(
      streamId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      streamIcon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream_icon'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      epgChannelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}epg_channel_id'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $LiveStreamsTable createAlias(String alias) {
    return $LiveStreamsTable(attachedDatabase, alias);
  }
}

class LiveStreamsData extends DataClass implements Insertable<LiveStreamsData> {
  final String streamId;
  final String name;
  final String streamIcon;
  final String categoryId;
  final String epgChannelId;
  final String playlistId;
  final DateTime createdAt;
  const LiveStreamsData({
    required this.streamId,
    required this.name,
    required this.streamIcon,
    required this.categoryId,
    required this.epgChannelId,
    required this.playlistId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['stream_id'] = Variable<String>(streamId);
    map['name'] = Variable<String>(name);
    map['stream_icon'] = Variable<String>(streamIcon);
    map['category_id'] = Variable<String>(categoryId);
    map['epg_channel_id'] = Variable<String>(epgChannelId);
    map['playlist_id'] = Variable<String>(playlistId);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LiveStreamsCompanion toCompanion(bool nullToAbsent) {
    return LiveStreamsCompanion(
      streamId: Value(streamId),
      name: Value(name),
      streamIcon: Value(streamIcon),
      categoryId: Value(categoryId),
      epgChannelId: Value(epgChannelId),
      playlistId: Value(playlistId),
      createdAt: Value(createdAt),
    );
  }

  factory LiveStreamsData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LiveStreamsData(
      streamId: serializer.fromJson<String>(json['streamId']),
      name: serializer.fromJson<String>(json['name']),
      streamIcon: serializer.fromJson<String>(json['streamIcon']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      epgChannelId: serializer.fromJson<String>(json['epgChannelId']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'streamId': serializer.toJson<String>(streamId),
      'name': serializer.toJson<String>(name),
      'streamIcon': serializer.toJson<String>(streamIcon),
      'categoryId': serializer.toJson<String>(categoryId),
      'epgChannelId': serializer.toJson<String>(epgChannelId),
      'playlistId': serializer.toJson<String>(playlistId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  LiveStreamsData copyWith({
    String? streamId,
    String? name,
    String? streamIcon,
    String? categoryId,
    String? epgChannelId,
    String? playlistId,
    DateTime? createdAt,
  }) => LiveStreamsData(
    streamId: streamId ?? this.streamId,
    name: name ?? this.name,
    streamIcon: streamIcon ?? this.streamIcon,
    categoryId: categoryId ?? this.categoryId,
    epgChannelId: epgChannelId ?? this.epgChannelId,
    playlistId: playlistId ?? this.playlistId,
    createdAt: createdAt ?? this.createdAt,
  );
  LiveStreamsData copyWithCompanion(LiveStreamsCompanion data) {
    return LiveStreamsData(
      streamId: data.streamId.present ? data.streamId.value : this.streamId,
      name: data.name.present ? data.name.value : this.name,
      streamIcon: data.streamIcon.present
          ? data.streamIcon.value
          : this.streamIcon,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      epgChannelId: data.epgChannelId.present
          ? data.epgChannelId.value
          : this.epgChannelId,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LiveStreamsData(')
          ..write('streamId: $streamId, ')
          ..write('name: $name, ')
          ..write('streamIcon: $streamIcon, ')
          ..write('categoryId: $categoryId, ')
          ..write('epgChannelId: $epgChannelId, ')
          ..write('playlistId: $playlistId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    streamId,
    name,
    streamIcon,
    categoryId,
    epgChannelId,
    playlistId,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LiveStreamsData &&
          other.streamId == this.streamId &&
          other.name == this.name &&
          other.streamIcon == this.streamIcon &&
          other.categoryId == this.categoryId &&
          other.epgChannelId == this.epgChannelId &&
          other.playlistId == this.playlistId &&
          other.createdAt == this.createdAt);
}

class LiveStreamsCompanion extends UpdateCompanion<LiveStreamsData> {
  final Value<String> streamId;
  final Value<String> name;
  final Value<String> streamIcon;
  final Value<String> categoryId;
  final Value<String> epgChannelId;
  final Value<String> playlistId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LiveStreamsCompanion({
    this.streamId = const Value.absent(),
    this.name = const Value.absent(),
    this.streamIcon = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.epgChannelId = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LiveStreamsCompanion.insert({
    required String streamId,
    required String name,
    required String streamIcon,
    required String categoryId,
    required String epgChannelId,
    required String playlistId,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : streamId = Value(streamId),
       name = Value(name),
       streamIcon = Value(streamIcon),
       categoryId = Value(categoryId),
       epgChannelId = Value(epgChannelId),
       playlistId = Value(playlistId);
  static Insertable<LiveStreamsData> custom({
    Expression<String>? streamId,
    Expression<String>? name,
    Expression<String>? streamIcon,
    Expression<String>? categoryId,
    Expression<String>? epgChannelId,
    Expression<String>? playlistId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (streamId != null) 'stream_id': streamId,
      if (name != null) 'name': name,
      if (streamIcon != null) 'stream_icon': streamIcon,
      if (categoryId != null) 'category_id': categoryId,
      if (epgChannelId != null) 'epg_channel_id': epgChannelId,
      if (playlistId != null) 'playlist_id': playlistId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LiveStreamsCompanion copyWith({
    Value<String>? streamId,
    Value<String>? name,
    Value<String>? streamIcon,
    Value<String>? categoryId,
    Value<String>? epgChannelId,
    Value<String>? playlistId,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return LiveStreamsCompanion(
      streamId: streamId ?? this.streamId,
      name: name ?? this.name,
      streamIcon: streamIcon ?? this.streamIcon,
      categoryId: categoryId ?? this.categoryId,
      epgChannelId: epgChannelId ?? this.epgChannelId,
      playlistId: playlistId ?? this.playlistId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (streamId.present) {
      map['stream_id'] = Variable<String>(streamId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (streamIcon.present) {
      map['stream_icon'] = Variable<String>(streamIcon.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (epgChannelId.present) {
      map['epg_channel_id'] = Variable<String>(epgChannelId.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LiveStreamsCompanion(')
          ..write('streamId: $streamId, ')
          ..write('name: $name, ')
          ..write('streamIcon: $streamIcon, ')
          ..write('categoryId: $categoryId, ')
          ..write('epgChannelId: $epgChannelId, ')
          ..write('playlistId: $playlistId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VodStreamsTable extends VodStreams
    with TableInfo<$VodStreamsTable, VodStreamsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VodStreamsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _streamIdMeta = const VerificationMeta(
    'streamId',
  );
  @override
  late final GeneratedColumn<String> streamId = GeneratedColumn<String>(
    'stream_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _streamIconMeta = const VerificationMeta(
    'streamIcon',
  );
  @override
  late final GeneratedColumn<String> streamIcon = GeneratedColumn<String>(
    'stream_icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<String> rating = GeneratedColumn<String>(
    'rating',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rating5basedMeta = const VerificationMeta(
    'rating5based',
  );
  @override
  late final GeneratedColumn<double> rating5based = GeneratedColumn<double>(
    'rating5based',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _containerExtensionMeta =
      const VerificationMeta('containerExtension');
  @override
  late final GeneratedColumn<String> containerExtension =
      GeneratedColumn<String>(
        'container_extension',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    streamId,
    name,
    streamIcon,
    categoryId,
    rating,
    rating5based,
    containerExtension,
    playlistId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vod_streams';
  @override
  VerificationContext validateIntegrity(
    Insertable<VodStreamsData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('stream_id')) {
      context.handle(
        _streamIdMeta,
        streamId.isAcceptableOrUnknown(data['stream_id']!, _streamIdMeta),
      );
    } else if (isInserting) {
      context.missing(_streamIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('stream_icon')) {
      context.handle(
        _streamIconMeta,
        streamIcon.isAcceptableOrUnknown(data['stream_icon']!, _streamIconMeta),
      );
    } else if (isInserting) {
      context.missing(_streamIconMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    } else if (isInserting) {
      context.missing(_ratingMeta);
    }
    if (data.containsKey('rating5based')) {
      context.handle(
        _rating5basedMeta,
        rating5based.isAcceptableOrUnknown(
          data['rating5based']!,
          _rating5basedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rating5basedMeta);
    }
    if (data.containsKey('container_extension')) {
      context.handle(
        _containerExtensionMeta,
        containerExtension.isAcceptableOrUnknown(
          data['container_extension']!,
          _containerExtensionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_containerExtensionMeta);
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {streamId, playlistId};
  @override
  VodStreamsData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VodStreamsData(
      streamId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      streamIcon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream_icon'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rating'],
      )!,
      rating5based: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rating5based'],
      )!,
      containerExtension: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}container_extension'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $VodStreamsTable createAlias(String alias) {
    return $VodStreamsTable(attachedDatabase, alias);
  }
}

class VodStreamsData extends DataClass implements Insertable<VodStreamsData> {
  final String streamId;
  final String name;
  final String streamIcon;
  final String categoryId;
  final String rating;
  final double rating5based;
  final String containerExtension;
  final String playlistId;
  final DateTime createdAt;
  const VodStreamsData({
    required this.streamId,
    required this.name,
    required this.streamIcon,
    required this.categoryId,
    required this.rating,
    required this.rating5based,
    required this.containerExtension,
    required this.playlistId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['stream_id'] = Variable<String>(streamId);
    map['name'] = Variable<String>(name);
    map['stream_icon'] = Variable<String>(streamIcon);
    map['category_id'] = Variable<String>(categoryId);
    map['rating'] = Variable<String>(rating);
    map['rating5based'] = Variable<double>(rating5based);
    map['container_extension'] = Variable<String>(containerExtension);
    map['playlist_id'] = Variable<String>(playlistId);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  VodStreamsCompanion toCompanion(bool nullToAbsent) {
    return VodStreamsCompanion(
      streamId: Value(streamId),
      name: Value(name),
      streamIcon: Value(streamIcon),
      categoryId: Value(categoryId),
      rating: Value(rating),
      rating5based: Value(rating5based),
      containerExtension: Value(containerExtension),
      playlistId: Value(playlistId),
      createdAt: Value(createdAt),
    );
  }

  factory VodStreamsData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VodStreamsData(
      streamId: serializer.fromJson<String>(json['streamId']),
      name: serializer.fromJson<String>(json['name']),
      streamIcon: serializer.fromJson<String>(json['streamIcon']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      rating: serializer.fromJson<String>(json['rating']),
      rating5based: serializer.fromJson<double>(json['rating5based']),
      containerExtension: serializer.fromJson<String>(
        json['containerExtension'],
      ),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'streamId': serializer.toJson<String>(streamId),
      'name': serializer.toJson<String>(name),
      'streamIcon': serializer.toJson<String>(streamIcon),
      'categoryId': serializer.toJson<String>(categoryId),
      'rating': serializer.toJson<String>(rating),
      'rating5based': serializer.toJson<double>(rating5based),
      'containerExtension': serializer.toJson<String>(containerExtension),
      'playlistId': serializer.toJson<String>(playlistId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  VodStreamsData copyWith({
    String? streamId,
    String? name,
    String? streamIcon,
    String? categoryId,
    String? rating,
    double? rating5based,
    String? containerExtension,
    String? playlistId,
    DateTime? createdAt,
  }) => VodStreamsData(
    streamId: streamId ?? this.streamId,
    name: name ?? this.name,
    streamIcon: streamIcon ?? this.streamIcon,
    categoryId: categoryId ?? this.categoryId,
    rating: rating ?? this.rating,
    rating5based: rating5based ?? this.rating5based,
    containerExtension: containerExtension ?? this.containerExtension,
    playlistId: playlistId ?? this.playlistId,
    createdAt: createdAt ?? this.createdAt,
  );
  VodStreamsData copyWithCompanion(VodStreamsCompanion data) {
    return VodStreamsData(
      streamId: data.streamId.present ? data.streamId.value : this.streamId,
      name: data.name.present ? data.name.value : this.name,
      streamIcon: data.streamIcon.present
          ? data.streamIcon.value
          : this.streamIcon,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      rating: data.rating.present ? data.rating.value : this.rating,
      rating5based: data.rating5based.present
          ? data.rating5based.value
          : this.rating5based,
      containerExtension: data.containerExtension.present
          ? data.containerExtension.value
          : this.containerExtension,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VodStreamsData(')
          ..write('streamId: $streamId, ')
          ..write('name: $name, ')
          ..write('streamIcon: $streamIcon, ')
          ..write('categoryId: $categoryId, ')
          ..write('rating: $rating, ')
          ..write('rating5based: $rating5based, ')
          ..write('containerExtension: $containerExtension, ')
          ..write('playlistId: $playlistId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    streamId,
    name,
    streamIcon,
    categoryId,
    rating,
    rating5based,
    containerExtension,
    playlistId,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VodStreamsData &&
          other.streamId == this.streamId &&
          other.name == this.name &&
          other.streamIcon == this.streamIcon &&
          other.categoryId == this.categoryId &&
          other.rating == this.rating &&
          other.rating5based == this.rating5based &&
          other.containerExtension == this.containerExtension &&
          other.playlistId == this.playlistId &&
          other.createdAt == this.createdAt);
}

class VodStreamsCompanion extends UpdateCompanion<VodStreamsData> {
  final Value<String> streamId;
  final Value<String> name;
  final Value<String> streamIcon;
  final Value<String> categoryId;
  final Value<String> rating;
  final Value<double> rating5based;
  final Value<String> containerExtension;
  final Value<String> playlistId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const VodStreamsCompanion({
    this.streamId = const Value.absent(),
    this.name = const Value.absent(),
    this.streamIcon = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.rating = const Value.absent(),
    this.rating5based = const Value.absent(),
    this.containerExtension = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VodStreamsCompanion.insert({
    required String streamId,
    required String name,
    required String streamIcon,
    required String categoryId,
    required String rating,
    required double rating5based,
    required String containerExtension,
    required String playlistId,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : streamId = Value(streamId),
       name = Value(name),
       streamIcon = Value(streamIcon),
       categoryId = Value(categoryId),
       rating = Value(rating),
       rating5based = Value(rating5based),
       containerExtension = Value(containerExtension),
       playlistId = Value(playlistId);
  static Insertable<VodStreamsData> custom({
    Expression<String>? streamId,
    Expression<String>? name,
    Expression<String>? streamIcon,
    Expression<String>? categoryId,
    Expression<String>? rating,
    Expression<double>? rating5based,
    Expression<String>? containerExtension,
    Expression<String>? playlistId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (streamId != null) 'stream_id': streamId,
      if (name != null) 'name': name,
      if (streamIcon != null) 'stream_icon': streamIcon,
      if (categoryId != null) 'category_id': categoryId,
      if (rating != null) 'rating': rating,
      if (rating5based != null) 'rating5based': rating5based,
      if (containerExtension != null) 'container_extension': containerExtension,
      if (playlistId != null) 'playlist_id': playlistId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VodStreamsCompanion copyWith({
    Value<String>? streamId,
    Value<String>? name,
    Value<String>? streamIcon,
    Value<String>? categoryId,
    Value<String>? rating,
    Value<double>? rating5based,
    Value<String>? containerExtension,
    Value<String>? playlistId,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return VodStreamsCompanion(
      streamId: streamId ?? this.streamId,
      name: name ?? this.name,
      streamIcon: streamIcon ?? this.streamIcon,
      categoryId: categoryId ?? this.categoryId,
      rating: rating ?? this.rating,
      rating5based: rating5based ?? this.rating5based,
      containerExtension: containerExtension ?? this.containerExtension,
      playlistId: playlistId ?? this.playlistId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (streamId.present) {
      map['stream_id'] = Variable<String>(streamId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (streamIcon.present) {
      map['stream_icon'] = Variable<String>(streamIcon.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (rating.present) {
      map['rating'] = Variable<String>(rating.value);
    }
    if (rating5based.present) {
      map['rating5based'] = Variable<double>(rating5based.value);
    }
    if (containerExtension.present) {
      map['container_extension'] = Variable<String>(containerExtension.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VodStreamsCompanion(')
          ..write('streamId: $streamId, ')
          ..write('name: $name, ')
          ..write('streamIcon: $streamIcon, ')
          ..write('categoryId: $categoryId, ')
          ..write('rating: $rating, ')
          ..write('rating5based: $rating5based, ')
          ..write('containerExtension: $containerExtension, ')
          ..write('playlistId: $playlistId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SeriesStreamsTable extends SeriesStreams
    with TableInfo<$SeriesStreamsTable, SeriesStreamsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeriesStreamsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverMeta = const VerificationMeta('cover');
  @override
  late final GeneratedColumn<String> cover = GeneratedColumn<String>(
    'cover',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plotMeta = const VerificationMeta('plot');
  @override
  late final GeneratedColumn<String> plot = GeneratedColumn<String>(
    'plot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _castMeta = const VerificationMeta('cast');
  @override
  late final GeneratedColumn<String> cast = GeneratedColumn<String>(
    'cast',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _directorMeta = const VerificationMeta(
    'director',
  );
  @override
  late final GeneratedColumn<String> director = GeneratedColumn<String>(
    'director',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _releaseDateMeta = const VerificationMeta(
    'releaseDate',
  );
  @override
  late final GeneratedColumn<String> releaseDate = GeneratedColumn<String>(
    'release_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<String> rating = GeneratedColumn<String>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rating5basedMeta = const VerificationMeta(
    'rating5based',
  );
  @override
  late final GeneratedColumn<double> rating5based = GeneratedColumn<double>(
    'rating5based',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _youtubeTrailerMeta = const VerificationMeta(
    'youtubeTrailer',
  );
  @override
  late final GeneratedColumn<String> youtubeTrailer = GeneratedColumn<String>(
    'youtube_trailer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _episodeRunTimeMeta = const VerificationMeta(
    'episodeRunTime',
  );
  @override
  late final GeneratedColumn<String> episodeRunTime = GeneratedColumn<String>(
    'episode_run_time',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _lastModifiedMeta = const VerificationMeta(
    'lastModified',
  );
  @override
  late final GeneratedColumn<String> lastModified = GeneratedColumn<String>(
    'last_modified',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backdropPathMeta = const VerificationMeta(
    'backdropPath',
  );
  @override
  late final GeneratedColumn<String> backdropPath = GeneratedColumn<String>(
    'backdrop_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    seriesId,
    name,
    cover,
    plot,
    cast,
    director,
    genre,
    releaseDate,
    rating,
    rating5based,
    youtubeTrailer,
    episodeRunTime,
    categoryId,
    playlistId,
    createdAt,
    lastModified,
    backdropPath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'series_streams';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeriesStreamsData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('cover')) {
      context.handle(
        _coverMeta,
        cover.isAcceptableOrUnknown(data['cover']!, _coverMeta),
      );
    }
    if (data.containsKey('plot')) {
      context.handle(
        _plotMeta,
        plot.isAcceptableOrUnknown(data['plot']!, _plotMeta),
      );
    }
    if (data.containsKey('cast')) {
      context.handle(
        _castMeta,
        cast.isAcceptableOrUnknown(data['cast']!, _castMeta),
      );
    }
    if (data.containsKey('director')) {
      context.handle(
        _directorMeta,
        director.isAcceptableOrUnknown(data['director']!, _directorMeta),
      );
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    if (data.containsKey('release_date')) {
      context.handle(
        _releaseDateMeta,
        releaseDate.isAcceptableOrUnknown(
          data['release_date']!,
          _releaseDateMeta,
        ),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('rating5based')) {
      context.handle(
        _rating5basedMeta,
        rating5based.isAcceptableOrUnknown(
          data['rating5based']!,
          _rating5basedMeta,
        ),
      );
    }
    if (data.containsKey('youtube_trailer')) {
      context.handle(
        _youtubeTrailerMeta,
        youtubeTrailer.isAcceptableOrUnknown(
          data['youtube_trailer']!,
          _youtubeTrailerMeta,
        ),
      );
    }
    if (data.containsKey('episode_run_time')) {
      context.handle(
        _episodeRunTimeMeta,
        episodeRunTime.isAcceptableOrUnknown(
          data['episode_run_time']!,
          _episodeRunTimeMeta,
        ),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('last_modified')) {
      context.handle(
        _lastModifiedMeta,
        lastModified.isAcceptableOrUnknown(
          data['last_modified']!,
          _lastModifiedMeta,
        ),
      );
    }
    if (data.containsKey('backdrop_path')) {
      context.handle(
        _backdropPathMeta,
        backdropPath.isAcceptableOrUnknown(
          data['backdrop_path']!,
          _backdropPathMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seriesId, playlistId};
  @override
  SeriesStreamsData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeriesStreamsData(
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      cover: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover'],
      ),
      plot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plot'],
      ),
      cast: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cast'],
      ),
      director: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}director'],
      ),
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      ),
      releaseDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}release_date'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rating'],
      ),
      rating5based: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rating5based'],
      ),
      youtubeTrailer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}youtube_trailer'],
      ),
      episodeRunTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}episode_run_time'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastModified: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_modified'],
      ),
      backdropPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backdrop_path'],
      ),
    );
  }

  @override
  $SeriesStreamsTable createAlias(String alias) {
    return $SeriesStreamsTable(attachedDatabase, alias);
  }
}

class SeriesStreamsData extends DataClass
    implements Insertable<SeriesStreamsData> {
  final String seriesId;
  final String name;
  final String? cover;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? releaseDate;
  final String? rating;
  final double? rating5based;
  final String? youtubeTrailer;
  final String? episodeRunTime;
  final String? categoryId;
  final String playlistId;
  final DateTime createdAt;
  final String? lastModified;
  final String? backdropPath;
  const SeriesStreamsData({
    required this.seriesId,
    required this.name,
    this.cover,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.rating,
    this.rating5based,
    this.youtubeTrailer,
    this.episodeRunTime,
    this.categoryId,
    required this.playlistId,
    required this.createdAt,
    this.lastModified,
    this.backdropPath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['series_id'] = Variable<String>(seriesId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || cover != null) {
      map['cover'] = Variable<String>(cover);
    }
    if (!nullToAbsent || plot != null) {
      map['plot'] = Variable<String>(plot);
    }
    if (!nullToAbsent || cast != null) {
      map['cast'] = Variable<String>(cast);
    }
    if (!nullToAbsent || director != null) {
      map['director'] = Variable<String>(director);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    if (!nullToAbsent || releaseDate != null) {
      map['release_date'] = Variable<String>(releaseDate);
    }
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<String>(rating);
    }
    if (!nullToAbsent || rating5based != null) {
      map['rating5based'] = Variable<double>(rating5based);
    }
    if (!nullToAbsent || youtubeTrailer != null) {
      map['youtube_trailer'] = Variable<String>(youtubeTrailer);
    }
    if (!nullToAbsent || episodeRunTime != null) {
      map['episode_run_time'] = Variable<String>(episodeRunTime);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    map['playlist_id'] = Variable<String>(playlistId);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastModified != null) {
      map['last_modified'] = Variable<String>(lastModified);
    }
    if (!nullToAbsent || backdropPath != null) {
      map['backdrop_path'] = Variable<String>(backdropPath);
    }
    return map;
  }

  SeriesStreamsCompanion toCompanion(bool nullToAbsent) {
    return SeriesStreamsCompanion(
      seriesId: Value(seriesId),
      name: Value(name),
      cover: cover == null && nullToAbsent
          ? const Value.absent()
          : Value(cover),
      plot: plot == null && nullToAbsent ? const Value.absent() : Value(plot),
      cast: cast == null && nullToAbsent ? const Value.absent() : Value(cast),
      director: director == null && nullToAbsent
          ? const Value.absent()
          : Value(director),
      genre: genre == null && nullToAbsent
          ? const Value.absent()
          : Value(genre),
      releaseDate: releaseDate == null && nullToAbsent
          ? const Value.absent()
          : Value(releaseDate),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
      rating5based: rating5based == null && nullToAbsent
          ? const Value.absent()
          : Value(rating5based),
      youtubeTrailer: youtubeTrailer == null && nullToAbsent
          ? const Value.absent()
          : Value(youtubeTrailer),
      episodeRunTime: episodeRunTime == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeRunTime),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      playlistId: Value(playlistId),
      createdAt: Value(createdAt),
      lastModified: lastModified == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModified),
      backdropPath: backdropPath == null && nullToAbsent
          ? const Value.absent()
          : Value(backdropPath),
    );
  }

  factory SeriesStreamsData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeriesStreamsData(
      seriesId: serializer.fromJson<String>(json['seriesId']),
      name: serializer.fromJson<String>(json['name']),
      cover: serializer.fromJson<String?>(json['cover']),
      plot: serializer.fromJson<String?>(json['plot']),
      cast: serializer.fromJson<String?>(json['cast']),
      director: serializer.fromJson<String?>(json['director']),
      genre: serializer.fromJson<String?>(json['genre']),
      releaseDate: serializer.fromJson<String?>(json['releaseDate']),
      rating: serializer.fromJson<String?>(json['rating']),
      rating5based: serializer.fromJson<double?>(json['rating5based']),
      youtubeTrailer: serializer.fromJson<String?>(json['youtubeTrailer']),
      episodeRunTime: serializer.fromJson<String?>(json['episodeRunTime']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastModified: serializer.fromJson<String?>(json['lastModified']),
      backdropPath: serializer.fromJson<String?>(json['backdropPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seriesId': serializer.toJson<String>(seriesId),
      'name': serializer.toJson<String>(name),
      'cover': serializer.toJson<String?>(cover),
      'plot': serializer.toJson<String?>(plot),
      'cast': serializer.toJson<String?>(cast),
      'director': serializer.toJson<String?>(director),
      'genre': serializer.toJson<String?>(genre),
      'releaseDate': serializer.toJson<String?>(releaseDate),
      'rating': serializer.toJson<String?>(rating),
      'rating5based': serializer.toJson<double?>(rating5based),
      'youtubeTrailer': serializer.toJson<String?>(youtubeTrailer),
      'episodeRunTime': serializer.toJson<String?>(episodeRunTime),
      'categoryId': serializer.toJson<String?>(categoryId),
      'playlistId': serializer.toJson<String>(playlistId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastModified': serializer.toJson<String?>(lastModified),
      'backdropPath': serializer.toJson<String?>(backdropPath),
    };
  }

  SeriesStreamsData copyWith({
    String? seriesId,
    String? name,
    Value<String?> cover = const Value.absent(),
    Value<String?> plot = const Value.absent(),
    Value<String?> cast = const Value.absent(),
    Value<String?> director = const Value.absent(),
    Value<String?> genre = const Value.absent(),
    Value<String?> releaseDate = const Value.absent(),
    Value<String?> rating = const Value.absent(),
    Value<double?> rating5based = const Value.absent(),
    Value<String?> youtubeTrailer = const Value.absent(),
    Value<String?> episodeRunTime = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    String? playlistId,
    DateTime? createdAt,
    Value<String?> lastModified = const Value.absent(),
    Value<String?> backdropPath = const Value.absent(),
  }) => SeriesStreamsData(
    seriesId: seriesId ?? this.seriesId,
    name: name ?? this.name,
    cover: cover.present ? cover.value : this.cover,
    plot: plot.present ? plot.value : this.plot,
    cast: cast.present ? cast.value : this.cast,
    director: director.present ? director.value : this.director,
    genre: genre.present ? genre.value : this.genre,
    releaseDate: releaseDate.present ? releaseDate.value : this.releaseDate,
    rating: rating.present ? rating.value : this.rating,
    rating5based: rating5based.present ? rating5based.value : this.rating5based,
    youtubeTrailer: youtubeTrailer.present
        ? youtubeTrailer.value
        : this.youtubeTrailer,
    episodeRunTime: episodeRunTime.present
        ? episodeRunTime.value
        : this.episodeRunTime,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    playlistId: playlistId ?? this.playlistId,
    createdAt: createdAt ?? this.createdAt,
    lastModified: lastModified.present ? lastModified.value : this.lastModified,
    backdropPath: backdropPath.present ? backdropPath.value : this.backdropPath,
  );
  SeriesStreamsData copyWithCompanion(SeriesStreamsCompanion data) {
    return SeriesStreamsData(
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      name: data.name.present ? data.name.value : this.name,
      cover: data.cover.present ? data.cover.value : this.cover,
      plot: data.plot.present ? data.plot.value : this.plot,
      cast: data.cast.present ? data.cast.value : this.cast,
      director: data.director.present ? data.director.value : this.director,
      genre: data.genre.present ? data.genre.value : this.genre,
      releaseDate: data.releaseDate.present
          ? data.releaseDate.value
          : this.releaseDate,
      rating: data.rating.present ? data.rating.value : this.rating,
      rating5based: data.rating5based.present
          ? data.rating5based.value
          : this.rating5based,
      youtubeTrailer: data.youtubeTrailer.present
          ? data.youtubeTrailer.value
          : this.youtubeTrailer,
      episodeRunTime: data.episodeRunTime.present
          ? data.episodeRunTime.value
          : this.episodeRunTime,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      backdropPath: data.backdropPath.present
          ? data.backdropPath.value
          : this.backdropPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeriesStreamsData(')
          ..write('seriesId: $seriesId, ')
          ..write('name: $name, ')
          ..write('cover: $cover, ')
          ..write('plot: $plot, ')
          ..write('cast: $cast, ')
          ..write('director: $director, ')
          ..write('genre: $genre, ')
          ..write('releaseDate: $releaseDate, ')
          ..write('rating: $rating, ')
          ..write('rating5based: $rating5based, ')
          ..write('youtubeTrailer: $youtubeTrailer, ')
          ..write('episodeRunTime: $episodeRunTime, ')
          ..write('categoryId: $categoryId, ')
          ..write('playlistId: $playlistId, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('backdropPath: $backdropPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    seriesId,
    name,
    cover,
    plot,
    cast,
    director,
    genre,
    releaseDate,
    rating,
    rating5based,
    youtubeTrailer,
    episodeRunTime,
    categoryId,
    playlistId,
    createdAt,
    lastModified,
    backdropPath,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeriesStreamsData &&
          other.seriesId == this.seriesId &&
          other.name == this.name &&
          other.cover == this.cover &&
          other.plot == this.plot &&
          other.cast == this.cast &&
          other.director == this.director &&
          other.genre == this.genre &&
          other.releaseDate == this.releaseDate &&
          other.rating == this.rating &&
          other.rating5based == this.rating5based &&
          other.youtubeTrailer == this.youtubeTrailer &&
          other.episodeRunTime == this.episodeRunTime &&
          other.categoryId == this.categoryId &&
          other.playlistId == this.playlistId &&
          other.createdAt == this.createdAt &&
          other.lastModified == this.lastModified &&
          other.backdropPath == this.backdropPath);
}

class SeriesStreamsCompanion extends UpdateCompanion<SeriesStreamsData> {
  final Value<String> seriesId;
  final Value<String> name;
  final Value<String?> cover;
  final Value<String?> plot;
  final Value<String?> cast;
  final Value<String?> director;
  final Value<String?> genre;
  final Value<String?> releaseDate;
  final Value<String?> rating;
  final Value<double?> rating5based;
  final Value<String?> youtubeTrailer;
  final Value<String?> episodeRunTime;
  final Value<String?> categoryId;
  final Value<String> playlistId;
  final Value<DateTime> createdAt;
  final Value<String?> lastModified;
  final Value<String?> backdropPath;
  final Value<int> rowid;
  const SeriesStreamsCompanion({
    this.seriesId = const Value.absent(),
    this.name = const Value.absent(),
    this.cover = const Value.absent(),
    this.plot = const Value.absent(),
    this.cast = const Value.absent(),
    this.director = const Value.absent(),
    this.genre = const Value.absent(),
    this.releaseDate = const Value.absent(),
    this.rating = const Value.absent(),
    this.rating5based = const Value.absent(),
    this.youtubeTrailer = const Value.absent(),
    this.episodeRunTime = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.backdropPath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SeriesStreamsCompanion.insert({
    required String seriesId,
    required String name,
    this.cover = const Value.absent(),
    this.plot = const Value.absent(),
    this.cast = const Value.absent(),
    this.director = const Value.absent(),
    this.genre = const Value.absent(),
    this.releaseDate = const Value.absent(),
    this.rating = const Value.absent(),
    this.rating5based = const Value.absent(),
    this.youtubeTrailer = const Value.absent(),
    this.episodeRunTime = const Value.absent(),
    this.categoryId = const Value.absent(),
    required String playlistId,
    this.createdAt = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.backdropPath = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : seriesId = Value(seriesId),
       name = Value(name),
       playlistId = Value(playlistId);
  static Insertable<SeriesStreamsData> custom({
    Expression<String>? seriesId,
    Expression<String>? name,
    Expression<String>? cover,
    Expression<String>? plot,
    Expression<String>? cast,
    Expression<String>? director,
    Expression<String>? genre,
    Expression<String>? releaseDate,
    Expression<String>? rating,
    Expression<double>? rating5based,
    Expression<String>? youtubeTrailer,
    Expression<String>? episodeRunTime,
    Expression<String>? categoryId,
    Expression<String>? playlistId,
    Expression<DateTime>? createdAt,
    Expression<String>? lastModified,
    Expression<String>? backdropPath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (seriesId != null) 'series_id': seriesId,
      if (name != null) 'name': name,
      if (cover != null) 'cover': cover,
      if (plot != null) 'plot': plot,
      if (cast != null) 'cast': cast,
      if (director != null) 'director': director,
      if (genre != null) 'genre': genre,
      if (releaseDate != null) 'release_date': releaseDate,
      if (rating != null) 'rating': rating,
      if (rating5based != null) 'rating5based': rating5based,
      if (youtubeTrailer != null) 'youtube_trailer': youtubeTrailer,
      if (episodeRunTime != null) 'episode_run_time': episodeRunTime,
      if (categoryId != null) 'category_id': categoryId,
      if (playlistId != null) 'playlist_id': playlistId,
      if (createdAt != null) 'created_at': createdAt,
      if (lastModified != null) 'last_modified': lastModified,
      if (backdropPath != null) 'backdrop_path': backdropPath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SeriesStreamsCompanion copyWith({
    Value<String>? seriesId,
    Value<String>? name,
    Value<String?>? cover,
    Value<String?>? plot,
    Value<String?>? cast,
    Value<String?>? director,
    Value<String?>? genre,
    Value<String?>? releaseDate,
    Value<String?>? rating,
    Value<double?>? rating5based,
    Value<String?>? youtubeTrailer,
    Value<String?>? episodeRunTime,
    Value<String?>? categoryId,
    Value<String>? playlistId,
    Value<DateTime>? createdAt,
    Value<String?>? lastModified,
    Value<String?>? backdropPath,
    Value<int>? rowid,
  }) {
    return SeriesStreamsCompanion(
      seriesId: seriesId ?? this.seriesId,
      name: name ?? this.name,
      cover: cover ?? this.cover,
      plot: plot ?? this.plot,
      cast: cast ?? this.cast,
      director: director ?? this.director,
      genre: genre ?? this.genre,
      releaseDate: releaseDate ?? this.releaseDate,
      rating: rating ?? this.rating,
      rating5based: rating5based ?? this.rating5based,
      youtubeTrailer: youtubeTrailer ?? this.youtubeTrailer,
      episodeRunTime: episodeRunTime ?? this.episodeRunTime,
      categoryId: categoryId ?? this.categoryId,
      playlistId: playlistId ?? this.playlistId,
      createdAt: createdAt ?? this.createdAt,
      lastModified: lastModified ?? this.lastModified,
      backdropPath: backdropPath ?? this.backdropPath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (cover.present) {
      map['cover'] = Variable<String>(cover.value);
    }
    if (plot.present) {
      map['plot'] = Variable<String>(plot.value);
    }
    if (cast.present) {
      map['cast'] = Variable<String>(cast.value);
    }
    if (director.present) {
      map['director'] = Variable<String>(director.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (releaseDate.present) {
      map['release_date'] = Variable<String>(releaseDate.value);
    }
    if (rating.present) {
      map['rating'] = Variable<String>(rating.value);
    }
    if (rating5based.present) {
      map['rating5based'] = Variable<double>(rating5based.value);
    }
    if (youtubeTrailer.present) {
      map['youtube_trailer'] = Variable<String>(youtubeTrailer.value);
    }
    if (episodeRunTime.present) {
      map['episode_run_time'] = Variable<String>(episodeRunTime.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<String>(lastModified.value);
    }
    if (backdropPath.present) {
      map['backdrop_path'] = Variable<String>(backdropPath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeriesStreamsCompanion(')
          ..write('seriesId: $seriesId, ')
          ..write('name: $name, ')
          ..write('cover: $cover, ')
          ..write('plot: $plot, ')
          ..write('cast: $cast, ')
          ..write('director: $director, ')
          ..write('genre: $genre, ')
          ..write('releaseDate: $releaseDate, ')
          ..write('rating: $rating, ')
          ..write('rating5based: $rating5based, ')
          ..write('youtubeTrailer: $youtubeTrailer, ')
          ..write('episodeRunTime: $episodeRunTime, ')
          ..write('categoryId: $categoryId, ')
          ..write('playlistId: $playlistId, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('backdropPath: $backdropPath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SeriesInfosTable extends SeriesInfos
    with TableInfo<$SeriesInfosTable, SeriesInfosData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeriesInfosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverMeta = const VerificationMeta('cover');
  @override
  late final GeneratedColumn<String> cover = GeneratedColumn<String>(
    'cover',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plotMeta = const VerificationMeta('plot');
  @override
  late final GeneratedColumn<String> plot = GeneratedColumn<String>(
    'plot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _castMeta = const VerificationMeta('cast');
  @override
  late final GeneratedColumn<String> cast = GeneratedColumn<String>(
    'cast',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _directorMeta = const VerificationMeta(
    'director',
  );
  @override
  late final GeneratedColumn<String> director = GeneratedColumn<String>(
    'director',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _releaseDateMeta = const VerificationMeta(
    'releaseDate',
  );
  @override
  late final GeneratedColumn<String> releaseDate = GeneratedColumn<String>(
    'release_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastModifiedMeta = const VerificationMeta(
    'lastModified',
  );
  @override
  late final GeneratedColumn<String> lastModified = GeneratedColumn<String>(
    'last_modified',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<String> rating = GeneratedColumn<String>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rating5basedMeta = const VerificationMeta(
    'rating5based',
  );
  @override
  late final GeneratedColumn<int> rating5based = GeneratedColumn<int>(
    'rating5based',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backdropPathMeta = const VerificationMeta(
    'backdropPath',
  );
  @override
  late final GeneratedColumn<String> backdropPath = GeneratedColumn<String>(
    'backdrop_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _youtubeTrailerMeta = const VerificationMeta(
    'youtubeTrailer',
  );
  @override
  late final GeneratedColumn<String> youtubeTrailer = GeneratedColumn<String>(
    'youtube_trailer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _episodeRunTimeMeta = const VerificationMeta(
    'episodeRunTime',
  );
  @override
  late final GeneratedColumn<String> episodeRunTime = GeneratedColumn<String>(
    'episode_run_time',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    seriesId,
    name,
    cover,
    plot,
    cast,
    director,
    genre,
    releaseDate,
    lastModified,
    rating,
    rating5based,
    backdropPath,
    youtubeTrailer,
    episodeRunTime,
    categoryId,
    playlistId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'series_infos';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeriesInfosData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('cover')) {
      context.handle(
        _coverMeta,
        cover.isAcceptableOrUnknown(data['cover']!, _coverMeta),
      );
    }
    if (data.containsKey('plot')) {
      context.handle(
        _plotMeta,
        plot.isAcceptableOrUnknown(data['plot']!, _plotMeta),
      );
    }
    if (data.containsKey('cast')) {
      context.handle(
        _castMeta,
        cast.isAcceptableOrUnknown(data['cast']!, _castMeta),
      );
    }
    if (data.containsKey('director')) {
      context.handle(
        _directorMeta,
        director.isAcceptableOrUnknown(data['director']!, _directorMeta),
      );
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    if (data.containsKey('release_date')) {
      context.handle(
        _releaseDateMeta,
        releaseDate.isAcceptableOrUnknown(
          data['release_date']!,
          _releaseDateMeta,
        ),
      );
    }
    if (data.containsKey('last_modified')) {
      context.handle(
        _lastModifiedMeta,
        lastModified.isAcceptableOrUnknown(
          data['last_modified']!,
          _lastModifiedMeta,
        ),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('rating5based')) {
      context.handle(
        _rating5basedMeta,
        rating5based.isAcceptableOrUnknown(
          data['rating5based']!,
          _rating5basedMeta,
        ),
      );
    }
    if (data.containsKey('backdrop_path')) {
      context.handle(
        _backdropPathMeta,
        backdropPath.isAcceptableOrUnknown(
          data['backdrop_path']!,
          _backdropPathMeta,
        ),
      );
    }
    if (data.containsKey('youtube_trailer')) {
      context.handle(
        _youtubeTrailerMeta,
        youtubeTrailer.isAcceptableOrUnknown(
          data['youtube_trailer']!,
          _youtubeTrailerMeta,
        ),
      );
    }
    if (data.containsKey('episode_run_time')) {
      context.handle(
        _episodeRunTimeMeta,
        episodeRunTime.isAcceptableOrUnknown(
          data['episode_run_time']!,
          _episodeRunTimeMeta,
        ),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SeriesInfosData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeriesInfosData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      cover: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover'],
      ),
      plot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plot'],
      ),
      cast: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cast'],
      ),
      director: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}director'],
      ),
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      ),
      releaseDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}release_date'],
      ),
      lastModified: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_modified'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rating'],
      ),
      rating5based: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating5based'],
      ),
      backdropPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backdrop_path'],
      ),
      youtubeTrailer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}youtube_trailer'],
      ),
      episodeRunTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}episode_run_time'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
    );
  }

  @override
  $SeriesInfosTable createAlias(String alias) {
    return $SeriesInfosTable(attachedDatabase, alias);
  }
}

class SeriesInfosData extends DataClass implements Insertable<SeriesInfosData> {
  final int id;
  final String seriesId;
  final String name;
  final String? cover;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? releaseDate;
  final String? lastModified;
  final String? rating;
  final int? rating5based;
  final String? backdropPath;
  final String? youtubeTrailer;
  final String? episodeRunTime;
  final String? categoryId;
  final String playlistId;
  const SeriesInfosData({
    required this.id,
    required this.seriesId,
    required this.name,
    this.cover,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.lastModified,
    this.rating,
    this.rating5based,
    this.backdropPath,
    this.youtubeTrailer,
    this.episodeRunTime,
    this.categoryId,
    required this.playlistId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['series_id'] = Variable<String>(seriesId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || cover != null) {
      map['cover'] = Variable<String>(cover);
    }
    if (!nullToAbsent || plot != null) {
      map['plot'] = Variable<String>(plot);
    }
    if (!nullToAbsent || cast != null) {
      map['cast'] = Variable<String>(cast);
    }
    if (!nullToAbsent || director != null) {
      map['director'] = Variable<String>(director);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    if (!nullToAbsent || releaseDate != null) {
      map['release_date'] = Variable<String>(releaseDate);
    }
    if (!nullToAbsent || lastModified != null) {
      map['last_modified'] = Variable<String>(lastModified);
    }
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<String>(rating);
    }
    if (!nullToAbsent || rating5based != null) {
      map['rating5based'] = Variable<int>(rating5based);
    }
    if (!nullToAbsent || backdropPath != null) {
      map['backdrop_path'] = Variable<String>(backdropPath);
    }
    if (!nullToAbsent || youtubeTrailer != null) {
      map['youtube_trailer'] = Variable<String>(youtubeTrailer);
    }
    if (!nullToAbsent || episodeRunTime != null) {
      map['episode_run_time'] = Variable<String>(episodeRunTime);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    map['playlist_id'] = Variable<String>(playlistId);
    return map;
  }

  SeriesInfosCompanion toCompanion(bool nullToAbsent) {
    return SeriesInfosCompanion(
      id: Value(id),
      seriesId: Value(seriesId),
      name: Value(name),
      cover: cover == null && nullToAbsent
          ? const Value.absent()
          : Value(cover),
      plot: plot == null && nullToAbsent ? const Value.absent() : Value(plot),
      cast: cast == null && nullToAbsent ? const Value.absent() : Value(cast),
      director: director == null && nullToAbsent
          ? const Value.absent()
          : Value(director),
      genre: genre == null && nullToAbsent
          ? const Value.absent()
          : Value(genre),
      releaseDate: releaseDate == null && nullToAbsent
          ? const Value.absent()
          : Value(releaseDate),
      lastModified: lastModified == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModified),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
      rating5based: rating5based == null && nullToAbsent
          ? const Value.absent()
          : Value(rating5based),
      backdropPath: backdropPath == null && nullToAbsent
          ? const Value.absent()
          : Value(backdropPath),
      youtubeTrailer: youtubeTrailer == null && nullToAbsent
          ? const Value.absent()
          : Value(youtubeTrailer),
      episodeRunTime: episodeRunTime == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeRunTime),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      playlistId: Value(playlistId),
    );
  }

  factory SeriesInfosData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeriesInfosData(
      id: serializer.fromJson<int>(json['id']),
      seriesId: serializer.fromJson<String>(json['seriesId']),
      name: serializer.fromJson<String>(json['name']),
      cover: serializer.fromJson<String?>(json['cover']),
      plot: serializer.fromJson<String?>(json['plot']),
      cast: serializer.fromJson<String?>(json['cast']),
      director: serializer.fromJson<String?>(json['director']),
      genre: serializer.fromJson<String?>(json['genre']),
      releaseDate: serializer.fromJson<String?>(json['releaseDate']),
      lastModified: serializer.fromJson<String?>(json['lastModified']),
      rating: serializer.fromJson<String?>(json['rating']),
      rating5based: serializer.fromJson<int?>(json['rating5based']),
      backdropPath: serializer.fromJson<String?>(json['backdropPath']),
      youtubeTrailer: serializer.fromJson<String?>(json['youtubeTrailer']),
      episodeRunTime: serializer.fromJson<String?>(json['episodeRunTime']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'seriesId': serializer.toJson<String>(seriesId),
      'name': serializer.toJson<String>(name),
      'cover': serializer.toJson<String?>(cover),
      'plot': serializer.toJson<String?>(plot),
      'cast': serializer.toJson<String?>(cast),
      'director': serializer.toJson<String?>(director),
      'genre': serializer.toJson<String?>(genre),
      'releaseDate': serializer.toJson<String?>(releaseDate),
      'lastModified': serializer.toJson<String?>(lastModified),
      'rating': serializer.toJson<String?>(rating),
      'rating5based': serializer.toJson<int?>(rating5based),
      'backdropPath': serializer.toJson<String?>(backdropPath),
      'youtubeTrailer': serializer.toJson<String?>(youtubeTrailer),
      'episodeRunTime': serializer.toJson<String?>(episodeRunTime),
      'categoryId': serializer.toJson<String?>(categoryId),
      'playlistId': serializer.toJson<String>(playlistId),
    };
  }

  SeriesInfosData copyWith({
    int? id,
    String? seriesId,
    String? name,
    Value<String?> cover = const Value.absent(),
    Value<String?> plot = const Value.absent(),
    Value<String?> cast = const Value.absent(),
    Value<String?> director = const Value.absent(),
    Value<String?> genre = const Value.absent(),
    Value<String?> releaseDate = const Value.absent(),
    Value<String?> lastModified = const Value.absent(),
    Value<String?> rating = const Value.absent(),
    Value<int?> rating5based = const Value.absent(),
    Value<String?> backdropPath = const Value.absent(),
    Value<String?> youtubeTrailer = const Value.absent(),
    Value<String?> episodeRunTime = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    String? playlistId,
  }) => SeriesInfosData(
    id: id ?? this.id,
    seriesId: seriesId ?? this.seriesId,
    name: name ?? this.name,
    cover: cover.present ? cover.value : this.cover,
    plot: plot.present ? plot.value : this.plot,
    cast: cast.present ? cast.value : this.cast,
    director: director.present ? director.value : this.director,
    genre: genre.present ? genre.value : this.genre,
    releaseDate: releaseDate.present ? releaseDate.value : this.releaseDate,
    lastModified: lastModified.present ? lastModified.value : this.lastModified,
    rating: rating.present ? rating.value : this.rating,
    rating5based: rating5based.present ? rating5based.value : this.rating5based,
    backdropPath: backdropPath.present ? backdropPath.value : this.backdropPath,
    youtubeTrailer: youtubeTrailer.present
        ? youtubeTrailer.value
        : this.youtubeTrailer,
    episodeRunTime: episodeRunTime.present
        ? episodeRunTime.value
        : this.episodeRunTime,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    playlistId: playlistId ?? this.playlistId,
  );
  SeriesInfosData copyWithCompanion(SeriesInfosCompanion data) {
    return SeriesInfosData(
      id: data.id.present ? data.id.value : this.id,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      name: data.name.present ? data.name.value : this.name,
      cover: data.cover.present ? data.cover.value : this.cover,
      plot: data.plot.present ? data.plot.value : this.plot,
      cast: data.cast.present ? data.cast.value : this.cast,
      director: data.director.present ? data.director.value : this.director,
      genre: data.genre.present ? data.genre.value : this.genre,
      releaseDate: data.releaseDate.present
          ? data.releaseDate.value
          : this.releaseDate,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      rating: data.rating.present ? data.rating.value : this.rating,
      rating5based: data.rating5based.present
          ? data.rating5based.value
          : this.rating5based,
      backdropPath: data.backdropPath.present
          ? data.backdropPath.value
          : this.backdropPath,
      youtubeTrailer: data.youtubeTrailer.present
          ? data.youtubeTrailer.value
          : this.youtubeTrailer,
      episodeRunTime: data.episodeRunTime.present
          ? data.episodeRunTime.value
          : this.episodeRunTime,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeriesInfosData(')
          ..write('id: $id, ')
          ..write('seriesId: $seriesId, ')
          ..write('name: $name, ')
          ..write('cover: $cover, ')
          ..write('plot: $plot, ')
          ..write('cast: $cast, ')
          ..write('director: $director, ')
          ..write('genre: $genre, ')
          ..write('releaseDate: $releaseDate, ')
          ..write('lastModified: $lastModified, ')
          ..write('rating: $rating, ')
          ..write('rating5based: $rating5based, ')
          ..write('backdropPath: $backdropPath, ')
          ..write('youtubeTrailer: $youtubeTrailer, ')
          ..write('episodeRunTime: $episodeRunTime, ')
          ..write('categoryId: $categoryId, ')
          ..write('playlistId: $playlistId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    seriesId,
    name,
    cover,
    plot,
    cast,
    director,
    genre,
    releaseDate,
    lastModified,
    rating,
    rating5based,
    backdropPath,
    youtubeTrailer,
    episodeRunTime,
    categoryId,
    playlistId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeriesInfosData &&
          other.id == this.id &&
          other.seriesId == this.seriesId &&
          other.name == this.name &&
          other.cover == this.cover &&
          other.plot == this.plot &&
          other.cast == this.cast &&
          other.director == this.director &&
          other.genre == this.genre &&
          other.releaseDate == this.releaseDate &&
          other.lastModified == this.lastModified &&
          other.rating == this.rating &&
          other.rating5based == this.rating5based &&
          other.backdropPath == this.backdropPath &&
          other.youtubeTrailer == this.youtubeTrailer &&
          other.episodeRunTime == this.episodeRunTime &&
          other.categoryId == this.categoryId &&
          other.playlistId == this.playlistId);
}

class SeriesInfosCompanion extends UpdateCompanion<SeriesInfosData> {
  final Value<int> id;
  final Value<String> seriesId;
  final Value<String> name;
  final Value<String?> cover;
  final Value<String?> plot;
  final Value<String?> cast;
  final Value<String?> director;
  final Value<String?> genre;
  final Value<String?> releaseDate;
  final Value<String?> lastModified;
  final Value<String?> rating;
  final Value<int?> rating5based;
  final Value<String?> backdropPath;
  final Value<String?> youtubeTrailer;
  final Value<String?> episodeRunTime;
  final Value<String?> categoryId;
  final Value<String> playlistId;
  const SeriesInfosCompanion({
    this.id = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.name = const Value.absent(),
    this.cover = const Value.absent(),
    this.plot = const Value.absent(),
    this.cast = const Value.absent(),
    this.director = const Value.absent(),
    this.genre = const Value.absent(),
    this.releaseDate = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.rating = const Value.absent(),
    this.rating5based = const Value.absent(),
    this.backdropPath = const Value.absent(),
    this.youtubeTrailer = const Value.absent(),
    this.episodeRunTime = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.playlistId = const Value.absent(),
  });
  SeriesInfosCompanion.insert({
    this.id = const Value.absent(),
    required String seriesId,
    required String name,
    this.cover = const Value.absent(),
    this.plot = const Value.absent(),
    this.cast = const Value.absent(),
    this.director = const Value.absent(),
    this.genre = const Value.absent(),
    this.releaseDate = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.rating = const Value.absent(),
    this.rating5based = const Value.absent(),
    this.backdropPath = const Value.absent(),
    this.youtubeTrailer = const Value.absent(),
    this.episodeRunTime = const Value.absent(),
    this.categoryId = const Value.absent(),
    required String playlistId,
  }) : seriesId = Value(seriesId),
       name = Value(name),
       playlistId = Value(playlistId);
  static Insertable<SeriesInfosData> custom({
    Expression<int>? id,
    Expression<String>? seriesId,
    Expression<String>? name,
    Expression<String>? cover,
    Expression<String>? plot,
    Expression<String>? cast,
    Expression<String>? director,
    Expression<String>? genre,
    Expression<String>? releaseDate,
    Expression<String>? lastModified,
    Expression<String>? rating,
    Expression<int>? rating5based,
    Expression<String>? backdropPath,
    Expression<String>? youtubeTrailer,
    Expression<String>? episodeRunTime,
    Expression<String>? categoryId,
    Expression<String>? playlistId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (seriesId != null) 'series_id': seriesId,
      if (name != null) 'name': name,
      if (cover != null) 'cover': cover,
      if (plot != null) 'plot': plot,
      if (cast != null) 'cast': cast,
      if (director != null) 'director': director,
      if (genre != null) 'genre': genre,
      if (releaseDate != null) 'release_date': releaseDate,
      if (lastModified != null) 'last_modified': lastModified,
      if (rating != null) 'rating': rating,
      if (rating5based != null) 'rating5based': rating5based,
      if (backdropPath != null) 'backdrop_path': backdropPath,
      if (youtubeTrailer != null) 'youtube_trailer': youtubeTrailer,
      if (episodeRunTime != null) 'episode_run_time': episodeRunTime,
      if (categoryId != null) 'category_id': categoryId,
      if (playlistId != null) 'playlist_id': playlistId,
    });
  }

  SeriesInfosCompanion copyWith({
    Value<int>? id,
    Value<String>? seriesId,
    Value<String>? name,
    Value<String?>? cover,
    Value<String?>? plot,
    Value<String?>? cast,
    Value<String?>? director,
    Value<String?>? genre,
    Value<String?>? releaseDate,
    Value<String?>? lastModified,
    Value<String?>? rating,
    Value<int?>? rating5based,
    Value<String?>? backdropPath,
    Value<String?>? youtubeTrailer,
    Value<String?>? episodeRunTime,
    Value<String?>? categoryId,
    Value<String>? playlistId,
  }) {
    return SeriesInfosCompanion(
      id: id ?? this.id,
      seriesId: seriesId ?? this.seriesId,
      name: name ?? this.name,
      cover: cover ?? this.cover,
      plot: plot ?? this.plot,
      cast: cast ?? this.cast,
      director: director ?? this.director,
      genre: genre ?? this.genre,
      releaseDate: releaseDate ?? this.releaseDate,
      lastModified: lastModified ?? this.lastModified,
      rating: rating ?? this.rating,
      rating5based: rating5based ?? this.rating5based,
      backdropPath: backdropPath ?? this.backdropPath,
      youtubeTrailer: youtubeTrailer ?? this.youtubeTrailer,
      episodeRunTime: episodeRunTime ?? this.episodeRunTime,
      categoryId: categoryId ?? this.categoryId,
      playlistId: playlistId ?? this.playlistId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (cover.present) {
      map['cover'] = Variable<String>(cover.value);
    }
    if (plot.present) {
      map['plot'] = Variable<String>(plot.value);
    }
    if (cast.present) {
      map['cast'] = Variable<String>(cast.value);
    }
    if (director.present) {
      map['director'] = Variable<String>(director.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (releaseDate.present) {
      map['release_date'] = Variable<String>(releaseDate.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<String>(lastModified.value);
    }
    if (rating.present) {
      map['rating'] = Variable<String>(rating.value);
    }
    if (rating5based.present) {
      map['rating5based'] = Variable<int>(rating5based.value);
    }
    if (backdropPath.present) {
      map['backdrop_path'] = Variable<String>(backdropPath.value);
    }
    if (youtubeTrailer.present) {
      map['youtube_trailer'] = Variable<String>(youtubeTrailer.value);
    }
    if (episodeRunTime.present) {
      map['episode_run_time'] = Variable<String>(episodeRunTime.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeriesInfosCompanion(')
          ..write('id: $id, ')
          ..write('seriesId: $seriesId, ')
          ..write('name: $name, ')
          ..write('cover: $cover, ')
          ..write('plot: $plot, ')
          ..write('cast: $cast, ')
          ..write('director: $director, ')
          ..write('genre: $genre, ')
          ..write('releaseDate: $releaseDate, ')
          ..write('lastModified: $lastModified, ')
          ..write('rating: $rating, ')
          ..write('rating5based: $rating5based, ')
          ..write('backdropPath: $backdropPath, ')
          ..write('youtubeTrailer: $youtubeTrailer, ')
          ..write('episodeRunTime: $episodeRunTime, ')
          ..write('categoryId: $categoryId, ')
          ..write('playlistId: $playlistId')
          ..write(')'))
        .toString();
  }
}

class $SeasonsTable extends Seasons with TableInfo<$SeasonsTable, SeasonsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeasonsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _airDateMeta = const VerificationMeta(
    'airDate',
  );
  @override
  late final GeneratedColumn<String> airDate = GeneratedColumn<String>(
    'air_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _episodeCountMeta = const VerificationMeta(
    'episodeCount',
  );
  @override
  late final GeneratedColumn<int> episodeCount = GeneratedColumn<int>(
    'episode_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seasonIdMeta = const VerificationMeta(
    'seasonId',
  );
  @override
  late final GeneratedColumn<int> seasonId = GeneratedColumn<int>(
    'season_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _overviewMeta = const VerificationMeta(
    'overview',
  );
  @override
  late final GeneratedColumn<String> overview = GeneratedColumn<String>(
    'overview',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seasonNumberMeta = const VerificationMeta(
    'seasonNumber',
  );
  @override
  late final GeneratedColumn<int> seasonNumber = GeneratedColumn<int>(
    'season_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _voteAverageMeta = const VerificationMeta(
    'voteAverage',
  );
  @override
  late final GeneratedColumn<int> voteAverage = GeneratedColumn<int>(
    'vote_average',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverMeta = const VerificationMeta('cover');
  @override
  late final GeneratedColumn<String> cover = GeneratedColumn<String>(
    'cover',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverBigMeta = const VerificationMeta(
    'coverBig',
  );
  @override
  late final GeneratedColumn<String> coverBig = GeneratedColumn<String>(
    'cover_big',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    seriesId,
    airDate,
    episodeCount,
    seasonId,
    name,
    overview,
    seasonNumber,
    voteAverage,
    cover,
    coverBig,
    playlistId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'seasons';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeasonsData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('air_date')) {
      context.handle(
        _airDateMeta,
        airDate.isAcceptableOrUnknown(data['air_date']!, _airDateMeta),
      );
    }
    if (data.containsKey('episode_count')) {
      context.handle(
        _episodeCountMeta,
        episodeCount.isAcceptableOrUnknown(
          data['episode_count']!,
          _episodeCountMeta,
        ),
      );
    }
    if (data.containsKey('season_id')) {
      context.handle(
        _seasonIdMeta,
        seasonId.isAcceptableOrUnknown(data['season_id']!, _seasonIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('overview')) {
      context.handle(
        _overviewMeta,
        overview.isAcceptableOrUnknown(data['overview']!, _overviewMeta),
      );
    }
    if (data.containsKey('season_number')) {
      context.handle(
        _seasonNumberMeta,
        seasonNumber.isAcceptableOrUnknown(
          data['season_number']!,
          _seasonNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_seasonNumberMeta);
    }
    if (data.containsKey('vote_average')) {
      context.handle(
        _voteAverageMeta,
        voteAverage.isAcceptableOrUnknown(
          data['vote_average']!,
          _voteAverageMeta,
        ),
      );
    }
    if (data.containsKey('cover')) {
      context.handle(
        _coverMeta,
        cover.isAcceptableOrUnknown(data['cover']!, _coverMeta),
      );
    }
    if (data.containsKey('cover_big')) {
      context.handle(
        _coverBigMeta,
        coverBig.isAcceptableOrUnknown(data['cover_big']!, _coverBigMeta),
      );
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SeasonsData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeasonsData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      )!,
      airDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}air_date'],
      ),
      episodeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_count'],
      ),
      seasonId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      overview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}overview'],
      ),
      seasonNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season_number'],
      )!,
      voteAverage: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}vote_average'],
      ),
      cover: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover'],
      ),
      coverBig: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_big'],
      ),
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
    );
  }

  @override
  $SeasonsTable createAlias(String alias) {
    return $SeasonsTable(attachedDatabase, alias);
  }
}

class SeasonsData extends DataClass implements Insertable<SeasonsData> {
  final int id;
  final String seriesId;
  final String? airDate;
  final int? episodeCount;
  final int seasonId;
  final String name;
  final String? overview;
  final int seasonNumber;
  final int? voteAverage;
  final String? cover;
  final String? coverBig;
  final String playlistId;
  const SeasonsData({
    required this.id,
    required this.seriesId,
    this.airDate,
    this.episodeCount,
    required this.seasonId,
    required this.name,
    this.overview,
    required this.seasonNumber,
    this.voteAverage,
    this.cover,
    this.coverBig,
    required this.playlistId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['series_id'] = Variable<String>(seriesId);
    if (!nullToAbsent || airDate != null) {
      map['air_date'] = Variable<String>(airDate);
    }
    if (!nullToAbsent || episodeCount != null) {
      map['episode_count'] = Variable<int>(episodeCount);
    }
    map['season_id'] = Variable<int>(seasonId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || overview != null) {
      map['overview'] = Variable<String>(overview);
    }
    map['season_number'] = Variable<int>(seasonNumber);
    if (!nullToAbsent || voteAverage != null) {
      map['vote_average'] = Variable<int>(voteAverage);
    }
    if (!nullToAbsent || cover != null) {
      map['cover'] = Variable<String>(cover);
    }
    if (!nullToAbsent || coverBig != null) {
      map['cover_big'] = Variable<String>(coverBig);
    }
    map['playlist_id'] = Variable<String>(playlistId);
    return map;
  }

  SeasonsCompanion toCompanion(bool nullToAbsent) {
    return SeasonsCompanion(
      id: Value(id),
      seriesId: Value(seriesId),
      airDate: airDate == null && nullToAbsent
          ? const Value.absent()
          : Value(airDate),
      episodeCount: episodeCount == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeCount),
      seasonId: Value(seasonId),
      name: Value(name),
      overview: overview == null && nullToAbsent
          ? const Value.absent()
          : Value(overview),
      seasonNumber: Value(seasonNumber),
      voteAverage: voteAverage == null && nullToAbsent
          ? const Value.absent()
          : Value(voteAverage),
      cover: cover == null && nullToAbsent
          ? const Value.absent()
          : Value(cover),
      coverBig: coverBig == null && nullToAbsent
          ? const Value.absent()
          : Value(coverBig),
      playlistId: Value(playlistId),
    );
  }

  factory SeasonsData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeasonsData(
      id: serializer.fromJson<int>(json['id']),
      seriesId: serializer.fromJson<String>(json['seriesId']),
      airDate: serializer.fromJson<String?>(json['airDate']),
      episodeCount: serializer.fromJson<int?>(json['episodeCount']),
      seasonId: serializer.fromJson<int>(json['seasonId']),
      name: serializer.fromJson<String>(json['name']),
      overview: serializer.fromJson<String?>(json['overview']),
      seasonNumber: serializer.fromJson<int>(json['seasonNumber']),
      voteAverage: serializer.fromJson<int?>(json['voteAverage']),
      cover: serializer.fromJson<String?>(json['cover']),
      coverBig: serializer.fromJson<String?>(json['coverBig']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'seriesId': serializer.toJson<String>(seriesId),
      'airDate': serializer.toJson<String?>(airDate),
      'episodeCount': serializer.toJson<int?>(episodeCount),
      'seasonId': serializer.toJson<int>(seasonId),
      'name': serializer.toJson<String>(name),
      'overview': serializer.toJson<String?>(overview),
      'seasonNumber': serializer.toJson<int>(seasonNumber),
      'voteAverage': serializer.toJson<int?>(voteAverage),
      'cover': serializer.toJson<String?>(cover),
      'coverBig': serializer.toJson<String?>(coverBig),
      'playlistId': serializer.toJson<String>(playlistId),
    };
  }

  SeasonsData copyWith({
    int? id,
    String? seriesId,
    Value<String?> airDate = const Value.absent(),
    Value<int?> episodeCount = const Value.absent(),
    int? seasonId,
    String? name,
    Value<String?> overview = const Value.absent(),
    int? seasonNumber,
    Value<int?> voteAverage = const Value.absent(),
    Value<String?> cover = const Value.absent(),
    Value<String?> coverBig = const Value.absent(),
    String? playlistId,
  }) => SeasonsData(
    id: id ?? this.id,
    seriesId: seriesId ?? this.seriesId,
    airDate: airDate.present ? airDate.value : this.airDate,
    episodeCount: episodeCount.present ? episodeCount.value : this.episodeCount,
    seasonId: seasonId ?? this.seasonId,
    name: name ?? this.name,
    overview: overview.present ? overview.value : this.overview,
    seasonNumber: seasonNumber ?? this.seasonNumber,
    voteAverage: voteAverage.present ? voteAverage.value : this.voteAverage,
    cover: cover.present ? cover.value : this.cover,
    coverBig: coverBig.present ? coverBig.value : this.coverBig,
    playlistId: playlistId ?? this.playlistId,
  );
  SeasonsData copyWithCompanion(SeasonsCompanion data) {
    return SeasonsData(
      id: data.id.present ? data.id.value : this.id,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      airDate: data.airDate.present ? data.airDate.value : this.airDate,
      episodeCount: data.episodeCount.present
          ? data.episodeCount.value
          : this.episodeCount,
      seasonId: data.seasonId.present ? data.seasonId.value : this.seasonId,
      name: data.name.present ? data.name.value : this.name,
      overview: data.overview.present ? data.overview.value : this.overview,
      seasonNumber: data.seasonNumber.present
          ? data.seasonNumber.value
          : this.seasonNumber,
      voteAverage: data.voteAverage.present
          ? data.voteAverage.value
          : this.voteAverage,
      cover: data.cover.present ? data.cover.value : this.cover,
      coverBig: data.coverBig.present ? data.coverBig.value : this.coverBig,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeasonsData(')
          ..write('id: $id, ')
          ..write('seriesId: $seriesId, ')
          ..write('airDate: $airDate, ')
          ..write('episodeCount: $episodeCount, ')
          ..write('seasonId: $seasonId, ')
          ..write('name: $name, ')
          ..write('overview: $overview, ')
          ..write('seasonNumber: $seasonNumber, ')
          ..write('voteAverage: $voteAverage, ')
          ..write('cover: $cover, ')
          ..write('coverBig: $coverBig, ')
          ..write('playlistId: $playlistId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    seriesId,
    airDate,
    episodeCount,
    seasonId,
    name,
    overview,
    seasonNumber,
    voteAverage,
    cover,
    coverBig,
    playlistId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeasonsData &&
          other.id == this.id &&
          other.seriesId == this.seriesId &&
          other.airDate == this.airDate &&
          other.episodeCount == this.episodeCount &&
          other.seasonId == this.seasonId &&
          other.name == this.name &&
          other.overview == this.overview &&
          other.seasonNumber == this.seasonNumber &&
          other.voteAverage == this.voteAverage &&
          other.cover == this.cover &&
          other.coverBig == this.coverBig &&
          other.playlistId == this.playlistId);
}

class SeasonsCompanion extends UpdateCompanion<SeasonsData> {
  final Value<int> id;
  final Value<String> seriesId;
  final Value<String?> airDate;
  final Value<int?> episodeCount;
  final Value<int> seasonId;
  final Value<String> name;
  final Value<String?> overview;
  final Value<int> seasonNumber;
  final Value<int?> voteAverage;
  final Value<String?> cover;
  final Value<String?> coverBig;
  final Value<String> playlistId;
  const SeasonsCompanion({
    this.id = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.airDate = const Value.absent(),
    this.episodeCount = const Value.absent(),
    this.seasonId = const Value.absent(),
    this.name = const Value.absent(),
    this.overview = const Value.absent(),
    this.seasonNumber = const Value.absent(),
    this.voteAverage = const Value.absent(),
    this.cover = const Value.absent(),
    this.coverBig = const Value.absent(),
    this.playlistId = const Value.absent(),
  });
  SeasonsCompanion.insert({
    this.id = const Value.absent(),
    required String seriesId,
    this.airDate = const Value.absent(),
    this.episodeCount = const Value.absent(),
    required int seasonId,
    required String name,
    this.overview = const Value.absent(),
    required int seasonNumber,
    this.voteAverage = const Value.absent(),
    this.cover = const Value.absent(),
    this.coverBig = const Value.absent(),
    required String playlistId,
  }) : seriesId = Value(seriesId),
       seasonId = Value(seasonId),
       name = Value(name),
       seasonNumber = Value(seasonNumber),
       playlistId = Value(playlistId);
  static Insertable<SeasonsData> custom({
    Expression<int>? id,
    Expression<String>? seriesId,
    Expression<String>? airDate,
    Expression<int>? episodeCount,
    Expression<int>? seasonId,
    Expression<String>? name,
    Expression<String>? overview,
    Expression<int>? seasonNumber,
    Expression<int>? voteAverage,
    Expression<String>? cover,
    Expression<String>? coverBig,
    Expression<String>? playlistId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (seriesId != null) 'series_id': seriesId,
      if (airDate != null) 'air_date': airDate,
      if (episodeCount != null) 'episode_count': episodeCount,
      if (seasonId != null) 'season_id': seasonId,
      if (name != null) 'name': name,
      if (overview != null) 'overview': overview,
      if (seasonNumber != null) 'season_number': seasonNumber,
      if (voteAverage != null) 'vote_average': voteAverage,
      if (cover != null) 'cover': cover,
      if (coverBig != null) 'cover_big': coverBig,
      if (playlistId != null) 'playlist_id': playlistId,
    });
  }

  SeasonsCompanion copyWith({
    Value<int>? id,
    Value<String>? seriesId,
    Value<String?>? airDate,
    Value<int?>? episodeCount,
    Value<int>? seasonId,
    Value<String>? name,
    Value<String?>? overview,
    Value<int>? seasonNumber,
    Value<int?>? voteAverage,
    Value<String?>? cover,
    Value<String?>? coverBig,
    Value<String>? playlistId,
  }) {
    return SeasonsCompanion(
      id: id ?? this.id,
      seriesId: seriesId ?? this.seriesId,
      airDate: airDate ?? this.airDate,
      episodeCount: episodeCount ?? this.episodeCount,
      seasonId: seasonId ?? this.seasonId,
      name: name ?? this.name,
      overview: overview ?? this.overview,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      voteAverage: voteAverage ?? this.voteAverage,
      cover: cover ?? this.cover,
      coverBig: coverBig ?? this.coverBig,
      playlistId: playlistId ?? this.playlistId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (airDate.present) {
      map['air_date'] = Variable<String>(airDate.value);
    }
    if (episodeCount.present) {
      map['episode_count'] = Variable<int>(episodeCount.value);
    }
    if (seasonId.present) {
      map['season_id'] = Variable<int>(seasonId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (overview.present) {
      map['overview'] = Variable<String>(overview.value);
    }
    if (seasonNumber.present) {
      map['season_number'] = Variable<int>(seasonNumber.value);
    }
    if (voteAverage.present) {
      map['vote_average'] = Variable<int>(voteAverage.value);
    }
    if (cover.present) {
      map['cover'] = Variable<String>(cover.value);
    }
    if (coverBig.present) {
      map['cover_big'] = Variable<String>(coverBig.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeasonsCompanion(')
          ..write('id: $id, ')
          ..write('seriesId: $seriesId, ')
          ..write('airDate: $airDate, ')
          ..write('episodeCount: $episodeCount, ')
          ..write('seasonId: $seasonId, ')
          ..write('name: $name, ')
          ..write('overview: $overview, ')
          ..write('seasonNumber: $seasonNumber, ')
          ..write('voteAverage: $voteAverage, ')
          ..write('cover: $cover, ')
          ..write('coverBig: $coverBig, ')
          ..write('playlistId: $playlistId')
          ..write(')'))
        .toString();
  }
}

class $EpisodesTable extends Episodes
    with TableInfo<$EpisodesTable, EpisodesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EpisodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _episodeIdMeta = const VerificationMeta(
    'episodeId',
  );
  @override
  late final GeneratedColumn<String> episodeId = GeneratedColumn<String>(
    'episode_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _episodeNumMeta = const VerificationMeta(
    'episodeNum',
  );
  @override
  late final GeneratedColumn<int> episodeNum = GeneratedColumn<int>(
    'episode_num',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _containerExtensionMeta =
      const VerificationMeta('containerExtension');
  @override
  late final GeneratedColumn<String> containerExtension =
      GeneratedColumn<String>(
        'container_extension',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _seasonMeta = const VerificationMeta('season');
  @override
  late final GeneratedColumn<int> season = GeneratedColumn<int>(
    'season',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customSidMeta = const VerificationMeta(
    'customSid',
  );
  @override
  late final GeneratedColumn<String> customSid = GeneratedColumn<String>(
    'custom_sid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedMeta = const VerificationMeta('added');
  @override
  late final GeneratedColumn<String> added = GeneratedColumn<String>(
    'added',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _directSourceMeta = const VerificationMeta(
    'directSource',
  );
  @override
  late final GeneratedColumn<String> directSource = GeneratedColumn<String>(
    'direct_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tmdbIdMeta = const VerificationMeta('tmdbId');
  @override
  late final GeneratedColumn<int> tmdbId = GeneratedColumn<int>(
    'tmdb_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _releasedateMeta = const VerificationMeta(
    'releasedate',
  );
  @override
  late final GeneratedColumn<String> releasedate = GeneratedColumn<String>(
    'releasedate',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plotMeta = const VerificationMeta('plot');
  @override
  late final GeneratedColumn<String> plot = GeneratedColumn<String>(
    'plot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationSecsMeta = const VerificationMeta(
    'durationSecs',
  );
  @override
  late final GeneratedColumn<int> durationSecs = GeneratedColumn<int>(
    'duration_secs',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMeta = const VerificationMeta(
    'duration',
  );
  @override
  late final GeneratedColumn<String> duration = GeneratedColumn<String>(
    'duration',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _movieImageMeta = const VerificationMeta(
    'movieImage',
  );
  @override
  late final GeneratedColumn<String> movieImage = GeneratedColumn<String>(
    'movie_image',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bitrateMeta = const VerificationMeta(
    'bitrate',
  );
  @override
  late final GeneratedColumn<int> bitrate = GeneratedColumn<int>(
    'bitrate',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<double> rating = GeneratedColumn<double>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    seriesId,
    episodeId,
    episodeNum,
    title,
    containerExtension,
    season,
    customSid,
    added,
    directSource,
    playlistId,
    tmdbId,
    releasedate,
    plot,
    durationSecs,
    duration,
    movieImage,
    bitrate,
    rating,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'episodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<EpisodesData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('episode_id')) {
      context.handle(
        _episodeIdMeta,
        episodeId.isAcceptableOrUnknown(data['episode_id']!, _episodeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_episodeIdMeta);
    }
    if (data.containsKey('episode_num')) {
      context.handle(
        _episodeNumMeta,
        episodeNum.isAcceptableOrUnknown(data['episode_num']!, _episodeNumMeta),
      );
    } else if (isInserting) {
      context.missing(_episodeNumMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('container_extension')) {
      context.handle(
        _containerExtensionMeta,
        containerExtension.isAcceptableOrUnknown(
          data['container_extension']!,
          _containerExtensionMeta,
        ),
      );
    }
    if (data.containsKey('season')) {
      context.handle(
        _seasonMeta,
        season.isAcceptableOrUnknown(data['season']!, _seasonMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonMeta);
    }
    if (data.containsKey('custom_sid')) {
      context.handle(
        _customSidMeta,
        customSid.isAcceptableOrUnknown(data['custom_sid']!, _customSidMeta),
      );
    }
    if (data.containsKey('added')) {
      context.handle(
        _addedMeta,
        added.isAcceptableOrUnknown(data['added']!, _addedMeta),
      );
    }
    if (data.containsKey('direct_source')) {
      context.handle(
        _directSourceMeta,
        directSource.isAcceptableOrUnknown(
          data['direct_source']!,
          _directSourceMeta,
        ),
      );
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('tmdb_id')) {
      context.handle(
        _tmdbIdMeta,
        tmdbId.isAcceptableOrUnknown(data['tmdb_id']!, _tmdbIdMeta),
      );
    }
    if (data.containsKey('releasedate')) {
      context.handle(
        _releasedateMeta,
        releasedate.isAcceptableOrUnknown(
          data['releasedate']!,
          _releasedateMeta,
        ),
      );
    }
    if (data.containsKey('plot')) {
      context.handle(
        _plotMeta,
        plot.isAcceptableOrUnknown(data['plot']!, _plotMeta),
      );
    }
    if (data.containsKey('duration_secs')) {
      context.handle(
        _durationSecsMeta,
        durationSecs.isAcceptableOrUnknown(
          data['duration_secs']!,
          _durationSecsMeta,
        ),
      );
    }
    if (data.containsKey('duration')) {
      context.handle(
        _durationMeta,
        duration.isAcceptableOrUnknown(data['duration']!, _durationMeta),
      );
    }
    if (data.containsKey('movie_image')) {
      context.handle(
        _movieImageMeta,
        movieImage.isAcceptableOrUnknown(data['movie_image']!, _movieImageMeta),
      );
    }
    if (data.containsKey('bitrate')) {
      context.handle(
        _bitrateMeta,
        bitrate.isAcceptableOrUnknown(data['bitrate']!, _bitrateMeta),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EpisodesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EpisodesData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      )!,
      episodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}episode_id'],
      )!,
      episodeNum: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_num'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      containerExtension: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}container_extension'],
      ),
      season: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season'],
      )!,
      customSid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_sid'],
      ),
      added: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}added'],
      ),
      directSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direct_source'],
      ),
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      tmdbId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tmdb_id'],
      ),
      releasedate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}releasedate'],
      ),
      plot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plot'],
      ),
      durationSecs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_secs'],
      ),
      duration: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}duration'],
      ),
      movieImage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}movie_image'],
      ),
      bitrate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bitrate'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rating'],
      ),
    );
  }

  @override
  $EpisodesTable createAlias(String alias) {
    return $EpisodesTable(attachedDatabase, alias);
  }
}

class EpisodesData extends DataClass implements Insertable<EpisodesData> {
  final int id;
  final String seriesId;
  final String episodeId;
  final int episodeNum;
  final String title;
  final String? containerExtension;
  final int season;
  final String? customSid;
  final String? added;
  final String? directSource;
  final String playlistId;
  final int? tmdbId;
  final String? releasedate;
  final String? plot;
  final int? durationSecs;
  final String? duration;
  final String? movieImage;
  final int? bitrate;
  final double? rating;
  const EpisodesData({
    required this.id,
    required this.seriesId,
    required this.episodeId,
    required this.episodeNum,
    required this.title,
    this.containerExtension,
    required this.season,
    this.customSid,
    this.added,
    this.directSource,
    required this.playlistId,
    this.tmdbId,
    this.releasedate,
    this.plot,
    this.durationSecs,
    this.duration,
    this.movieImage,
    this.bitrate,
    this.rating,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['series_id'] = Variable<String>(seriesId);
    map['episode_id'] = Variable<String>(episodeId);
    map['episode_num'] = Variable<int>(episodeNum);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || containerExtension != null) {
      map['container_extension'] = Variable<String>(containerExtension);
    }
    map['season'] = Variable<int>(season);
    if (!nullToAbsent || customSid != null) {
      map['custom_sid'] = Variable<String>(customSid);
    }
    if (!nullToAbsent || added != null) {
      map['added'] = Variable<String>(added);
    }
    if (!nullToAbsent || directSource != null) {
      map['direct_source'] = Variable<String>(directSource);
    }
    map['playlist_id'] = Variable<String>(playlistId);
    if (!nullToAbsent || tmdbId != null) {
      map['tmdb_id'] = Variable<int>(tmdbId);
    }
    if (!nullToAbsent || releasedate != null) {
      map['releasedate'] = Variable<String>(releasedate);
    }
    if (!nullToAbsent || plot != null) {
      map['plot'] = Variable<String>(plot);
    }
    if (!nullToAbsent || durationSecs != null) {
      map['duration_secs'] = Variable<int>(durationSecs);
    }
    if (!nullToAbsent || duration != null) {
      map['duration'] = Variable<String>(duration);
    }
    if (!nullToAbsent || movieImage != null) {
      map['movie_image'] = Variable<String>(movieImage);
    }
    if (!nullToAbsent || bitrate != null) {
      map['bitrate'] = Variable<int>(bitrate);
    }
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<double>(rating);
    }
    return map;
  }

  EpisodesCompanion toCompanion(bool nullToAbsent) {
    return EpisodesCompanion(
      id: Value(id),
      seriesId: Value(seriesId),
      episodeId: Value(episodeId),
      episodeNum: Value(episodeNum),
      title: Value(title),
      containerExtension: containerExtension == null && nullToAbsent
          ? const Value.absent()
          : Value(containerExtension),
      season: Value(season),
      customSid: customSid == null && nullToAbsent
          ? const Value.absent()
          : Value(customSid),
      added: added == null && nullToAbsent
          ? const Value.absent()
          : Value(added),
      directSource: directSource == null && nullToAbsent
          ? const Value.absent()
          : Value(directSource),
      playlistId: Value(playlistId),
      tmdbId: tmdbId == null && nullToAbsent
          ? const Value.absent()
          : Value(tmdbId),
      releasedate: releasedate == null && nullToAbsent
          ? const Value.absent()
          : Value(releasedate),
      plot: plot == null && nullToAbsent ? const Value.absent() : Value(plot),
      durationSecs: durationSecs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationSecs),
      duration: duration == null && nullToAbsent
          ? const Value.absent()
          : Value(duration),
      movieImage: movieImage == null && nullToAbsent
          ? const Value.absent()
          : Value(movieImage),
      bitrate: bitrate == null && nullToAbsent
          ? const Value.absent()
          : Value(bitrate),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
    );
  }

  factory EpisodesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EpisodesData(
      id: serializer.fromJson<int>(json['id']),
      seriesId: serializer.fromJson<String>(json['seriesId']),
      episodeId: serializer.fromJson<String>(json['episodeId']),
      episodeNum: serializer.fromJson<int>(json['episodeNum']),
      title: serializer.fromJson<String>(json['title']),
      containerExtension: serializer.fromJson<String?>(
        json['containerExtension'],
      ),
      season: serializer.fromJson<int>(json['season']),
      customSid: serializer.fromJson<String?>(json['customSid']),
      added: serializer.fromJson<String?>(json['added']),
      directSource: serializer.fromJson<String?>(json['directSource']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      tmdbId: serializer.fromJson<int?>(json['tmdbId']),
      releasedate: serializer.fromJson<String?>(json['releasedate']),
      plot: serializer.fromJson<String?>(json['plot']),
      durationSecs: serializer.fromJson<int?>(json['durationSecs']),
      duration: serializer.fromJson<String?>(json['duration']),
      movieImage: serializer.fromJson<String?>(json['movieImage']),
      bitrate: serializer.fromJson<int?>(json['bitrate']),
      rating: serializer.fromJson<double?>(json['rating']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'seriesId': serializer.toJson<String>(seriesId),
      'episodeId': serializer.toJson<String>(episodeId),
      'episodeNum': serializer.toJson<int>(episodeNum),
      'title': serializer.toJson<String>(title),
      'containerExtension': serializer.toJson<String?>(containerExtension),
      'season': serializer.toJson<int>(season),
      'customSid': serializer.toJson<String?>(customSid),
      'added': serializer.toJson<String?>(added),
      'directSource': serializer.toJson<String?>(directSource),
      'playlistId': serializer.toJson<String>(playlistId),
      'tmdbId': serializer.toJson<int?>(tmdbId),
      'releasedate': serializer.toJson<String?>(releasedate),
      'plot': serializer.toJson<String?>(plot),
      'durationSecs': serializer.toJson<int?>(durationSecs),
      'duration': serializer.toJson<String?>(duration),
      'movieImage': serializer.toJson<String?>(movieImage),
      'bitrate': serializer.toJson<int?>(bitrate),
      'rating': serializer.toJson<double?>(rating),
    };
  }

  EpisodesData copyWith({
    int? id,
    String? seriesId,
    String? episodeId,
    int? episodeNum,
    String? title,
    Value<String?> containerExtension = const Value.absent(),
    int? season,
    Value<String?> customSid = const Value.absent(),
    Value<String?> added = const Value.absent(),
    Value<String?> directSource = const Value.absent(),
    String? playlistId,
    Value<int?> tmdbId = const Value.absent(),
    Value<String?> releasedate = const Value.absent(),
    Value<String?> plot = const Value.absent(),
    Value<int?> durationSecs = const Value.absent(),
    Value<String?> duration = const Value.absent(),
    Value<String?> movieImage = const Value.absent(),
    Value<int?> bitrate = const Value.absent(),
    Value<double?> rating = const Value.absent(),
  }) => EpisodesData(
    id: id ?? this.id,
    seriesId: seriesId ?? this.seriesId,
    episodeId: episodeId ?? this.episodeId,
    episodeNum: episodeNum ?? this.episodeNum,
    title: title ?? this.title,
    containerExtension: containerExtension.present
        ? containerExtension.value
        : this.containerExtension,
    season: season ?? this.season,
    customSid: customSid.present ? customSid.value : this.customSid,
    added: added.present ? added.value : this.added,
    directSource: directSource.present ? directSource.value : this.directSource,
    playlistId: playlistId ?? this.playlistId,
    tmdbId: tmdbId.present ? tmdbId.value : this.tmdbId,
    releasedate: releasedate.present ? releasedate.value : this.releasedate,
    plot: plot.present ? plot.value : this.plot,
    durationSecs: durationSecs.present ? durationSecs.value : this.durationSecs,
    duration: duration.present ? duration.value : this.duration,
    movieImage: movieImage.present ? movieImage.value : this.movieImage,
    bitrate: bitrate.present ? bitrate.value : this.bitrate,
    rating: rating.present ? rating.value : this.rating,
  );
  EpisodesData copyWithCompanion(EpisodesCompanion data) {
    return EpisodesData(
      id: data.id.present ? data.id.value : this.id,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      episodeId: data.episodeId.present ? data.episodeId.value : this.episodeId,
      episodeNum: data.episodeNum.present
          ? data.episodeNum.value
          : this.episodeNum,
      title: data.title.present ? data.title.value : this.title,
      containerExtension: data.containerExtension.present
          ? data.containerExtension.value
          : this.containerExtension,
      season: data.season.present ? data.season.value : this.season,
      customSid: data.customSid.present ? data.customSid.value : this.customSid,
      added: data.added.present ? data.added.value : this.added,
      directSource: data.directSource.present
          ? data.directSource.value
          : this.directSource,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      tmdbId: data.tmdbId.present ? data.tmdbId.value : this.tmdbId,
      releasedate: data.releasedate.present
          ? data.releasedate.value
          : this.releasedate,
      plot: data.plot.present ? data.plot.value : this.plot,
      durationSecs: data.durationSecs.present
          ? data.durationSecs.value
          : this.durationSecs,
      duration: data.duration.present ? data.duration.value : this.duration,
      movieImage: data.movieImage.present
          ? data.movieImage.value
          : this.movieImage,
      bitrate: data.bitrate.present ? data.bitrate.value : this.bitrate,
      rating: data.rating.present ? data.rating.value : this.rating,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EpisodesData(')
          ..write('id: $id, ')
          ..write('seriesId: $seriesId, ')
          ..write('episodeId: $episodeId, ')
          ..write('episodeNum: $episodeNum, ')
          ..write('title: $title, ')
          ..write('containerExtension: $containerExtension, ')
          ..write('season: $season, ')
          ..write('customSid: $customSid, ')
          ..write('added: $added, ')
          ..write('directSource: $directSource, ')
          ..write('playlistId: $playlistId, ')
          ..write('tmdbId: $tmdbId, ')
          ..write('releasedate: $releasedate, ')
          ..write('plot: $plot, ')
          ..write('durationSecs: $durationSecs, ')
          ..write('duration: $duration, ')
          ..write('movieImage: $movieImage, ')
          ..write('bitrate: $bitrate, ')
          ..write('rating: $rating')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    seriesId,
    episodeId,
    episodeNum,
    title,
    containerExtension,
    season,
    customSid,
    added,
    directSource,
    playlistId,
    tmdbId,
    releasedate,
    plot,
    durationSecs,
    duration,
    movieImage,
    bitrate,
    rating,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EpisodesData &&
          other.id == this.id &&
          other.seriesId == this.seriesId &&
          other.episodeId == this.episodeId &&
          other.episodeNum == this.episodeNum &&
          other.title == this.title &&
          other.containerExtension == this.containerExtension &&
          other.season == this.season &&
          other.customSid == this.customSid &&
          other.added == this.added &&
          other.directSource == this.directSource &&
          other.playlistId == this.playlistId &&
          other.tmdbId == this.tmdbId &&
          other.releasedate == this.releasedate &&
          other.plot == this.plot &&
          other.durationSecs == this.durationSecs &&
          other.duration == this.duration &&
          other.movieImage == this.movieImage &&
          other.bitrate == this.bitrate &&
          other.rating == this.rating);
}

class EpisodesCompanion extends UpdateCompanion<EpisodesData> {
  final Value<int> id;
  final Value<String> seriesId;
  final Value<String> episodeId;
  final Value<int> episodeNum;
  final Value<String> title;
  final Value<String?> containerExtension;
  final Value<int> season;
  final Value<String?> customSid;
  final Value<String?> added;
  final Value<String?> directSource;
  final Value<String> playlistId;
  final Value<int?> tmdbId;
  final Value<String?> releasedate;
  final Value<String?> plot;
  final Value<int?> durationSecs;
  final Value<String?> duration;
  final Value<String?> movieImage;
  final Value<int?> bitrate;
  final Value<double?> rating;
  const EpisodesCompanion({
    this.id = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.episodeId = const Value.absent(),
    this.episodeNum = const Value.absent(),
    this.title = const Value.absent(),
    this.containerExtension = const Value.absent(),
    this.season = const Value.absent(),
    this.customSid = const Value.absent(),
    this.added = const Value.absent(),
    this.directSource = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.tmdbId = const Value.absent(),
    this.releasedate = const Value.absent(),
    this.plot = const Value.absent(),
    this.durationSecs = const Value.absent(),
    this.duration = const Value.absent(),
    this.movieImage = const Value.absent(),
    this.bitrate = const Value.absent(),
    this.rating = const Value.absent(),
  });
  EpisodesCompanion.insert({
    this.id = const Value.absent(),
    required String seriesId,
    required String episodeId,
    required int episodeNum,
    required String title,
    this.containerExtension = const Value.absent(),
    required int season,
    this.customSid = const Value.absent(),
    this.added = const Value.absent(),
    this.directSource = const Value.absent(),
    required String playlistId,
    this.tmdbId = const Value.absent(),
    this.releasedate = const Value.absent(),
    this.plot = const Value.absent(),
    this.durationSecs = const Value.absent(),
    this.duration = const Value.absent(),
    this.movieImage = const Value.absent(),
    this.bitrate = const Value.absent(),
    this.rating = const Value.absent(),
  }) : seriesId = Value(seriesId),
       episodeId = Value(episodeId),
       episodeNum = Value(episodeNum),
       title = Value(title),
       season = Value(season),
       playlistId = Value(playlistId);
  static Insertable<EpisodesData> custom({
    Expression<int>? id,
    Expression<String>? seriesId,
    Expression<String>? episodeId,
    Expression<int>? episodeNum,
    Expression<String>? title,
    Expression<String>? containerExtension,
    Expression<int>? season,
    Expression<String>? customSid,
    Expression<String>? added,
    Expression<String>? directSource,
    Expression<String>? playlistId,
    Expression<int>? tmdbId,
    Expression<String>? releasedate,
    Expression<String>? plot,
    Expression<int>? durationSecs,
    Expression<String>? duration,
    Expression<String>? movieImage,
    Expression<int>? bitrate,
    Expression<double>? rating,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (seriesId != null) 'series_id': seriesId,
      if (episodeId != null) 'episode_id': episodeId,
      if (episodeNum != null) 'episode_num': episodeNum,
      if (title != null) 'title': title,
      if (containerExtension != null) 'container_extension': containerExtension,
      if (season != null) 'season': season,
      if (customSid != null) 'custom_sid': customSid,
      if (added != null) 'added': added,
      if (directSource != null) 'direct_source': directSource,
      if (playlistId != null) 'playlist_id': playlistId,
      if (tmdbId != null) 'tmdb_id': tmdbId,
      if (releasedate != null) 'releasedate': releasedate,
      if (plot != null) 'plot': plot,
      if (durationSecs != null) 'duration_secs': durationSecs,
      if (duration != null) 'duration': duration,
      if (movieImage != null) 'movie_image': movieImage,
      if (bitrate != null) 'bitrate': bitrate,
      if (rating != null) 'rating': rating,
    });
  }

  EpisodesCompanion copyWith({
    Value<int>? id,
    Value<String>? seriesId,
    Value<String>? episodeId,
    Value<int>? episodeNum,
    Value<String>? title,
    Value<String?>? containerExtension,
    Value<int>? season,
    Value<String?>? customSid,
    Value<String?>? added,
    Value<String?>? directSource,
    Value<String>? playlistId,
    Value<int?>? tmdbId,
    Value<String?>? releasedate,
    Value<String?>? plot,
    Value<int?>? durationSecs,
    Value<String?>? duration,
    Value<String?>? movieImage,
    Value<int?>? bitrate,
    Value<double?>? rating,
  }) {
    return EpisodesCompanion(
      id: id ?? this.id,
      seriesId: seriesId ?? this.seriesId,
      episodeId: episodeId ?? this.episodeId,
      episodeNum: episodeNum ?? this.episodeNum,
      title: title ?? this.title,
      containerExtension: containerExtension ?? this.containerExtension,
      season: season ?? this.season,
      customSid: customSid ?? this.customSid,
      added: added ?? this.added,
      directSource: directSource ?? this.directSource,
      playlistId: playlistId ?? this.playlistId,
      tmdbId: tmdbId ?? this.tmdbId,
      releasedate: releasedate ?? this.releasedate,
      plot: plot ?? this.plot,
      durationSecs: durationSecs ?? this.durationSecs,
      duration: duration ?? this.duration,
      movieImage: movieImage ?? this.movieImage,
      bitrate: bitrate ?? this.bitrate,
      rating: rating ?? this.rating,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (episodeId.present) {
      map['episode_id'] = Variable<String>(episodeId.value);
    }
    if (episodeNum.present) {
      map['episode_num'] = Variable<int>(episodeNum.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (containerExtension.present) {
      map['container_extension'] = Variable<String>(containerExtension.value);
    }
    if (season.present) {
      map['season'] = Variable<int>(season.value);
    }
    if (customSid.present) {
      map['custom_sid'] = Variable<String>(customSid.value);
    }
    if (added.present) {
      map['added'] = Variable<String>(added.value);
    }
    if (directSource.present) {
      map['direct_source'] = Variable<String>(directSource.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (tmdbId.present) {
      map['tmdb_id'] = Variable<int>(tmdbId.value);
    }
    if (releasedate.present) {
      map['releasedate'] = Variable<String>(releasedate.value);
    }
    if (plot.present) {
      map['plot'] = Variable<String>(plot.value);
    }
    if (durationSecs.present) {
      map['duration_secs'] = Variable<int>(durationSecs.value);
    }
    if (duration.present) {
      map['duration'] = Variable<String>(duration.value);
    }
    if (movieImage.present) {
      map['movie_image'] = Variable<String>(movieImage.value);
    }
    if (bitrate.present) {
      map['bitrate'] = Variable<int>(bitrate.value);
    }
    if (rating.present) {
      map['rating'] = Variable<double>(rating.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EpisodesCompanion(')
          ..write('id: $id, ')
          ..write('seriesId: $seriesId, ')
          ..write('episodeId: $episodeId, ')
          ..write('episodeNum: $episodeNum, ')
          ..write('title: $title, ')
          ..write('containerExtension: $containerExtension, ')
          ..write('season: $season, ')
          ..write('customSid: $customSid, ')
          ..write('added: $added, ')
          ..write('directSource: $directSource, ')
          ..write('playlistId: $playlistId, ')
          ..write('tmdbId: $tmdbId, ')
          ..write('releasedate: $releasedate, ')
          ..write('plot: $plot, ')
          ..write('durationSecs: $durationSecs, ')
          ..write('duration: $duration, ')
          ..write('movieImage: $movieImage, ')
          ..write('bitrate: $bitrate, ')
          ..write('rating: $rating')
          ..write(')'))
        .toString();
  }
}

class $WatchHistoriesTable extends WatchHistories
    with TableInfo<$WatchHistoriesTable, WatchHistoriesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchHistoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ContentType, int> contentType =
      GeneratedColumn<int>(
        'content_type',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<ContentType>($WatchHistoriesTable.$convertercontentType);
  static const VerificationMeta _streamIdMeta = const VerificationMeta(
    'streamId',
  );
  @override
  late final GeneratedColumn<String> streamId = GeneratedColumn<String>(
    'stream_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _watchDurationMeta = const VerificationMeta(
    'watchDuration',
  );
  @override
  late final GeneratedColumn<int> watchDuration = GeneratedColumn<int>(
    'watch_duration',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalDurationMeta = const VerificationMeta(
    'totalDuration',
  );
  @override
  late final GeneratedColumn<int> totalDuration = GeneratedColumn<int>(
    'total_duration',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastWatchedMeta = const VerificationMeta(
    'lastWatched',
  );
  @override
  late final GeneratedColumn<DateTime> lastWatched = GeneratedColumn<DateTime>(
    'last_watched',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imagePathMeta = const VerificationMeta(
    'imagePath',
  );
  @override
  late final GeneratedColumn<String> imagePath = GeneratedColumn<String>(
    'image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    playlistId,
    contentType,
    streamId,
    seriesId,
    watchDuration,
    totalDuration,
    lastWatched,
    imagePath,
    title,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watch_histories';
  @override
  VerificationContext validateIntegrity(
    Insertable<WatchHistoriesData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('stream_id')) {
      context.handle(
        _streamIdMeta,
        streamId.isAcceptableOrUnknown(data['stream_id']!, _streamIdMeta),
      );
    } else if (isInserting) {
      context.missing(_streamIdMeta);
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    }
    if (data.containsKey('watch_duration')) {
      context.handle(
        _watchDurationMeta,
        watchDuration.isAcceptableOrUnknown(
          data['watch_duration']!,
          _watchDurationMeta,
        ),
      );
    }
    if (data.containsKey('total_duration')) {
      context.handle(
        _totalDurationMeta,
        totalDuration.isAcceptableOrUnknown(
          data['total_duration']!,
          _totalDurationMeta,
        ),
      );
    }
    if (data.containsKey('last_watched')) {
      context.handle(
        _lastWatchedMeta,
        lastWatched.isAcceptableOrUnknown(
          data['last_watched']!,
          _lastWatchedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastWatchedMeta);
    }
    if (data.containsKey('image_path')) {
      context.handle(
        _imagePathMeta,
        imagePath.isAcceptableOrUnknown(data['image_path']!, _imagePathMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {playlistId, streamId};
  @override
  WatchHistoriesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchHistoriesData(
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      contentType: $WatchHistoriesTable.$convertercontentType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}content_type'],
        )!,
      ),
      streamId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream_id'],
      )!,
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      ),
      watchDuration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}watch_duration'],
      ),
      totalDuration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_duration'],
      ),
      lastWatched: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_watched'],
      )!,
      imagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_path'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
    );
  }

  @override
  $WatchHistoriesTable createAlias(String alias) {
    return $WatchHistoriesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ContentType, int, int> $convertercontentType =
      const EnumIndexConverter<ContentType>(ContentType.values);
}

class WatchHistoriesData extends DataClass
    implements Insertable<WatchHistoriesData> {
  final String playlistId;
  final ContentType contentType;
  final String streamId;
  final String? seriesId;
  final int? watchDuration;
  final int? totalDuration;
  final DateTime lastWatched;
  final String? imagePath;
  final String title;
  const WatchHistoriesData({
    required this.playlistId,
    required this.contentType,
    required this.streamId,
    this.seriesId,
    this.watchDuration,
    this.totalDuration,
    required this.lastWatched,
    this.imagePath,
    required this.title,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['playlist_id'] = Variable<String>(playlistId);
    {
      map['content_type'] = Variable<int>(
        $WatchHistoriesTable.$convertercontentType.toSql(contentType),
      );
    }
    map['stream_id'] = Variable<String>(streamId);
    if (!nullToAbsent || seriesId != null) {
      map['series_id'] = Variable<String>(seriesId);
    }
    if (!nullToAbsent || watchDuration != null) {
      map['watch_duration'] = Variable<int>(watchDuration);
    }
    if (!nullToAbsent || totalDuration != null) {
      map['total_duration'] = Variable<int>(totalDuration);
    }
    map['last_watched'] = Variable<DateTime>(lastWatched);
    if (!nullToAbsent || imagePath != null) {
      map['image_path'] = Variable<String>(imagePath);
    }
    map['title'] = Variable<String>(title);
    return map;
  }

  WatchHistoriesCompanion toCompanion(bool nullToAbsent) {
    return WatchHistoriesCompanion(
      playlistId: Value(playlistId),
      contentType: Value(contentType),
      streamId: Value(streamId),
      seriesId: seriesId == null && nullToAbsent
          ? const Value.absent()
          : Value(seriesId),
      watchDuration: watchDuration == null && nullToAbsent
          ? const Value.absent()
          : Value(watchDuration),
      totalDuration: totalDuration == null && nullToAbsent
          ? const Value.absent()
          : Value(totalDuration),
      lastWatched: Value(lastWatched),
      imagePath: imagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(imagePath),
      title: Value(title),
    );
  }

  factory WatchHistoriesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchHistoriesData(
      playlistId: serializer.fromJson<String>(json['playlistId']),
      contentType: $WatchHistoriesTable.$convertercontentType.fromJson(
        serializer.fromJson<int>(json['contentType']),
      ),
      streamId: serializer.fromJson<String>(json['streamId']),
      seriesId: serializer.fromJson<String?>(json['seriesId']),
      watchDuration: serializer.fromJson<int?>(json['watchDuration']),
      totalDuration: serializer.fromJson<int?>(json['totalDuration']),
      lastWatched: serializer.fromJson<DateTime>(json['lastWatched']),
      imagePath: serializer.fromJson<String?>(json['imagePath']),
      title: serializer.fromJson<String>(json['title']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'playlistId': serializer.toJson<String>(playlistId),
      'contentType': serializer.toJson<int>(
        $WatchHistoriesTable.$convertercontentType.toJson(contentType),
      ),
      'streamId': serializer.toJson<String>(streamId),
      'seriesId': serializer.toJson<String?>(seriesId),
      'watchDuration': serializer.toJson<int?>(watchDuration),
      'totalDuration': serializer.toJson<int?>(totalDuration),
      'lastWatched': serializer.toJson<DateTime>(lastWatched),
      'imagePath': serializer.toJson<String?>(imagePath),
      'title': serializer.toJson<String>(title),
    };
  }

  WatchHistoriesData copyWith({
    String? playlistId,
    ContentType? contentType,
    String? streamId,
    Value<String?> seriesId = const Value.absent(),
    Value<int?> watchDuration = const Value.absent(),
    Value<int?> totalDuration = const Value.absent(),
    DateTime? lastWatched,
    Value<String?> imagePath = const Value.absent(),
    String? title,
  }) => WatchHistoriesData(
    playlistId: playlistId ?? this.playlistId,
    contentType: contentType ?? this.contentType,
    streamId: streamId ?? this.streamId,
    seriesId: seriesId.present ? seriesId.value : this.seriesId,
    watchDuration: watchDuration.present
        ? watchDuration.value
        : this.watchDuration,
    totalDuration: totalDuration.present
        ? totalDuration.value
        : this.totalDuration,
    lastWatched: lastWatched ?? this.lastWatched,
    imagePath: imagePath.present ? imagePath.value : this.imagePath,
    title: title ?? this.title,
  );
  WatchHistoriesData copyWithCompanion(WatchHistoriesCompanion data) {
    return WatchHistoriesData(
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      streamId: data.streamId.present ? data.streamId.value : this.streamId,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      watchDuration: data.watchDuration.present
          ? data.watchDuration.value
          : this.watchDuration,
      totalDuration: data.totalDuration.present
          ? data.totalDuration.value
          : this.totalDuration,
      lastWatched: data.lastWatched.present
          ? data.lastWatched.value
          : this.lastWatched,
      imagePath: data.imagePath.present ? data.imagePath.value : this.imagePath,
      title: data.title.present ? data.title.value : this.title,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchHistoriesData(')
          ..write('playlistId: $playlistId, ')
          ..write('contentType: $contentType, ')
          ..write('streamId: $streamId, ')
          ..write('seriesId: $seriesId, ')
          ..write('watchDuration: $watchDuration, ')
          ..write('totalDuration: $totalDuration, ')
          ..write('lastWatched: $lastWatched, ')
          ..write('imagePath: $imagePath, ')
          ..write('title: $title')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    playlistId,
    contentType,
    streamId,
    seriesId,
    watchDuration,
    totalDuration,
    lastWatched,
    imagePath,
    title,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchHistoriesData &&
          other.playlistId == this.playlistId &&
          other.contentType == this.contentType &&
          other.streamId == this.streamId &&
          other.seriesId == this.seriesId &&
          other.watchDuration == this.watchDuration &&
          other.totalDuration == this.totalDuration &&
          other.lastWatched == this.lastWatched &&
          other.imagePath == this.imagePath &&
          other.title == this.title);
}

class WatchHistoriesCompanion extends UpdateCompanion<WatchHistoriesData> {
  final Value<String> playlistId;
  final Value<ContentType> contentType;
  final Value<String> streamId;
  final Value<String?> seriesId;
  final Value<int?> watchDuration;
  final Value<int?> totalDuration;
  final Value<DateTime> lastWatched;
  final Value<String?> imagePath;
  final Value<String> title;
  final Value<int> rowid;
  const WatchHistoriesCompanion({
    this.playlistId = const Value.absent(),
    this.contentType = const Value.absent(),
    this.streamId = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.watchDuration = const Value.absent(),
    this.totalDuration = const Value.absent(),
    this.lastWatched = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.title = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchHistoriesCompanion.insert({
    required String playlistId,
    required ContentType contentType,
    required String streamId,
    this.seriesId = const Value.absent(),
    this.watchDuration = const Value.absent(),
    this.totalDuration = const Value.absent(),
    required DateTime lastWatched,
    this.imagePath = const Value.absent(),
    required String title,
    this.rowid = const Value.absent(),
  }) : playlistId = Value(playlistId),
       contentType = Value(contentType),
       streamId = Value(streamId),
       lastWatched = Value(lastWatched),
       title = Value(title);
  static Insertable<WatchHistoriesData> custom({
    Expression<String>? playlistId,
    Expression<int>? contentType,
    Expression<String>? streamId,
    Expression<String>? seriesId,
    Expression<int>? watchDuration,
    Expression<int>? totalDuration,
    Expression<DateTime>? lastWatched,
    Expression<String>? imagePath,
    Expression<String>? title,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (playlistId != null) 'playlist_id': playlistId,
      if (contentType != null) 'content_type': contentType,
      if (streamId != null) 'stream_id': streamId,
      if (seriesId != null) 'series_id': seriesId,
      if (watchDuration != null) 'watch_duration': watchDuration,
      if (totalDuration != null) 'total_duration': totalDuration,
      if (lastWatched != null) 'last_watched': lastWatched,
      if (imagePath != null) 'image_path': imagePath,
      if (title != null) 'title': title,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchHistoriesCompanion copyWith({
    Value<String>? playlistId,
    Value<ContentType>? contentType,
    Value<String>? streamId,
    Value<String?>? seriesId,
    Value<int?>? watchDuration,
    Value<int?>? totalDuration,
    Value<DateTime>? lastWatched,
    Value<String?>? imagePath,
    Value<String>? title,
    Value<int>? rowid,
  }) {
    return WatchHistoriesCompanion(
      playlistId: playlistId ?? this.playlistId,
      contentType: contentType ?? this.contentType,
      streamId: streamId ?? this.streamId,
      seriesId: seriesId ?? this.seriesId,
      watchDuration: watchDuration ?? this.watchDuration,
      totalDuration: totalDuration ?? this.totalDuration,
      lastWatched: lastWatched ?? this.lastWatched,
      imagePath: imagePath ?? this.imagePath,
      title: title ?? this.title,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<int>(
        $WatchHistoriesTable.$convertercontentType.toSql(contentType.value),
      );
    }
    if (streamId.present) {
      map['stream_id'] = Variable<String>(streamId.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (watchDuration.present) {
      map['watch_duration'] = Variable<int>(watchDuration.value);
    }
    if (totalDuration.present) {
      map['total_duration'] = Variable<int>(totalDuration.value);
    }
    if (lastWatched.present) {
      map['last_watched'] = Variable<DateTime>(lastWatched.value);
    }
    if (imagePath.present) {
      map['image_path'] = Variable<String>(imagePath.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchHistoriesCompanion(')
          ..write('playlistId: $playlistId, ')
          ..write('contentType: $contentType, ')
          ..write('streamId: $streamId, ')
          ..write('seriesId: $seriesId, ')
          ..write('watchDuration: $watchDuration, ')
          ..write('totalDuration: $totalDuration, ')
          ..write('lastWatched: $lastWatched, ')
          ..write('imagePath: $imagePath, ')
          ..write('title: $title, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $M3uItemsTable extends M3uItems
    with TableInfo<$M3uItemsTable, M3uItemData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $M3uItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tvgIdMeta = const VerificationMeta('tvgId');
  @override
  late final GeneratedColumn<String> tvgId = GeneratedColumn<String>(
    'tvg_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tvgNameMeta = const VerificationMeta(
    'tvgName',
  );
  @override
  late final GeneratedColumn<String> tvgName = GeneratedColumn<String>(
    'tvg_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tvgLogoMeta = const VerificationMeta(
    'tvgLogo',
  );
  @override
  late final GeneratedColumn<String> tvgLogo = GeneratedColumn<String>(
    'tvg_logo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tvgUrlMeta = const VerificationMeta('tvgUrl');
  @override
  late final GeneratedColumn<String> tvgUrl = GeneratedColumn<String>(
    'tvg_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tvgRecMeta = const VerificationMeta('tvgRec');
  @override
  late final GeneratedColumn<String> tvgRec = GeneratedColumn<String>(
    'tvg_rec',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tvgShiftMeta = const VerificationMeta(
    'tvgShift',
  );
  @override
  late final GeneratedColumn<String> tvgShift = GeneratedColumn<String>(
    'tvg_shift',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _groupTitleMeta = const VerificationMeta(
    'groupTitle',
  );
  @override
  late final GeneratedColumn<String> groupTitle = GeneratedColumn<String>(
    'group_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _groupNameMeta = const VerificationMeta(
    'groupName',
  );
  @override
  late final GeneratedColumn<String> groupName = GeneratedColumn<String>(
    'group_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userAgentMeta = const VerificationMeta(
    'userAgent',
  );
  @override
  late final GeneratedColumn<String> userAgent = GeneratedColumn<String>(
    'user_agent',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _referrerMeta = const VerificationMeta(
    'referrer',
  );
  @override
  late final GeneratedColumn<String> referrer = GeneratedColumn<String>(
    'referrer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<int> contentType = GeneratedColumn<int>(
    'content_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    playlistId,
    url,
    name,
    tvgId,
    tvgName,
    tvgLogo,
    tvgUrl,
    tvgRec,
    tvgShift,
    groupTitle,
    groupName,
    userAgent,
    referrer,
    categoryId,
    contentType,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'm3u_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<M3uItemData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('tvg_id')) {
      context.handle(
        _tvgIdMeta,
        tvgId.isAcceptableOrUnknown(data['tvg_id']!, _tvgIdMeta),
      );
    }
    if (data.containsKey('tvg_name')) {
      context.handle(
        _tvgNameMeta,
        tvgName.isAcceptableOrUnknown(data['tvg_name']!, _tvgNameMeta),
      );
    }
    if (data.containsKey('tvg_logo')) {
      context.handle(
        _tvgLogoMeta,
        tvgLogo.isAcceptableOrUnknown(data['tvg_logo']!, _tvgLogoMeta),
      );
    }
    if (data.containsKey('tvg_url')) {
      context.handle(
        _tvgUrlMeta,
        tvgUrl.isAcceptableOrUnknown(data['tvg_url']!, _tvgUrlMeta),
      );
    }
    if (data.containsKey('tvg_rec')) {
      context.handle(
        _tvgRecMeta,
        tvgRec.isAcceptableOrUnknown(data['tvg_rec']!, _tvgRecMeta),
      );
    }
    if (data.containsKey('tvg_shift')) {
      context.handle(
        _tvgShiftMeta,
        tvgShift.isAcceptableOrUnknown(data['tvg_shift']!, _tvgShiftMeta),
      );
    }
    if (data.containsKey('group_title')) {
      context.handle(
        _groupTitleMeta,
        groupTitle.isAcceptableOrUnknown(data['group_title']!, _groupTitleMeta),
      );
    }
    if (data.containsKey('group_name')) {
      context.handle(
        _groupNameMeta,
        groupName.isAcceptableOrUnknown(data['group_name']!, _groupNameMeta),
      );
    }
    if (data.containsKey('user_agent')) {
      context.handle(
        _userAgentMeta,
        userAgent.isAcceptableOrUnknown(data['user_agent']!, _userAgentMeta),
      );
    }
    if (data.containsKey('referrer')) {
      context.handle(
        _referrerMeta,
        referrer.isAcceptableOrUnknown(data['referrer']!, _referrerMeta),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentTypeMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  M3uItemData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return M3uItemData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      tvgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tvg_id'],
      ),
      tvgName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tvg_name'],
      ),
      tvgLogo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tvg_logo'],
      ),
      tvgUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tvg_url'],
      ),
      tvgRec: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tvg_rec'],
      ),
      tvgShift: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tvg_shift'],
      ),
      groupTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_title'],
      ),
      groupName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_name'],
      ),
      userAgent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_agent'],
      ),
      referrer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}referrer'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}content_type'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $M3uItemsTable createAlias(String alias) {
    return $M3uItemsTable(attachedDatabase, alias);
  }
}

class M3uItemData extends DataClass implements Insertable<M3uItemData> {
  final String id;
  final String playlistId;
  final String url;
  final String? name;
  final String? tvgId;
  final String? tvgName;
  final String? tvgLogo;
  final String? tvgUrl;
  final String? tvgRec;
  final String? tvgShift;
  final String? groupTitle;
  final String? groupName;
  final String? userAgent;
  final String? referrer;
  final String? categoryId;
  final int contentType;
  final DateTime createdAt;
  final DateTime updatedAt;
  const M3uItemData({
    required this.id,
    required this.playlistId,
    required this.url,
    this.name,
    this.tvgId,
    this.tvgName,
    this.tvgLogo,
    this.tvgUrl,
    this.tvgRec,
    this.tvgShift,
    this.groupTitle,
    this.groupName,
    this.userAgent,
    this.referrer,
    this.categoryId,
    required this.contentType,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['playlist_id'] = Variable<String>(playlistId);
    map['url'] = Variable<String>(url);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || tvgId != null) {
      map['tvg_id'] = Variable<String>(tvgId);
    }
    if (!nullToAbsent || tvgName != null) {
      map['tvg_name'] = Variable<String>(tvgName);
    }
    if (!nullToAbsent || tvgLogo != null) {
      map['tvg_logo'] = Variable<String>(tvgLogo);
    }
    if (!nullToAbsent || tvgUrl != null) {
      map['tvg_url'] = Variable<String>(tvgUrl);
    }
    if (!nullToAbsent || tvgRec != null) {
      map['tvg_rec'] = Variable<String>(tvgRec);
    }
    if (!nullToAbsent || tvgShift != null) {
      map['tvg_shift'] = Variable<String>(tvgShift);
    }
    if (!nullToAbsent || groupTitle != null) {
      map['group_title'] = Variable<String>(groupTitle);
    }
    if (!nullToAbsent || groupName != null) {
      map['group_name'] = Variable<String>(groupName);
    }
    if (!nullToAbsent || userAgent != null) {
      map['user_agent'] = Variable<String>(userAgent);
    }
    if (!nullToAbsent || referrer != null) {
      map['referrer'] = Variable<String>(referrer);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    map['content_type'] = Variable<int>(contentType);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  M3uItemsCompanion toCompanion(bool nullToAbsent) {
    return M3uItemsCompanion(
      id: Value(id),
      playlistId: Value(playlistId),
      url: Value(url),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      tvgId: tvgId == null && nullToAbsent
          ? const Value.absent()
          : Value(tvgId),
      tvgName: tvgName == null && nullToAbsent
          ? const Value.absent()
          : Value(tvgName),
      tvgLogo: tvgLogo == null && nullToAbsent
          ? const Value.absent()
          : Value(tvgLogo),
      tvgUrl: tvgUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(tvgUrl),
      tvgRec: tvgRec == null && nullToAbsent
          ? const Value.absent()
          : Value(tvgRec),
      tvgShift: tvgShift == null && nullToAbsent
          ? const Value.absent()
          : Value(tvgShift),
      groupTitle: groupTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(groupTitle),
      groupName: groupName == null && nullToAbsent
          ? const Value.absent()
          : Value(groupName),
      userAgent: userAgent == null && nullToAbsent
          ? const Value.absent()
          : Value(userAgent),
      referrer: referrer == null && nullToAbsent
          ? const Value.absent()
          : Value(referrer),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      contentType: Value(contentType),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory M3uItemData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return M3uItemData(
      id: serializer.fromJson<String>(json['id']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      url: serializer.fromJson<String>(json['url']),
      name: serializer.fromJson<String?>(json['name']),
      tvgId: serializer.fromJson<String?>(json['tvgId']),
      tvgName: serializer.fromJson<String?>(json['tvgName']),
      tvgLogo: serializer.fromJson<String?>(json['tvgLogo']),
      tvgUrl: serializer.fromJson<String?>(json['tvgUrl']),
      tvgRec: serializer.fromJson<String?>(json['tvgRec']),
      tvgShift: serializer.fromJson<String?>(json['tvgShift']),
      groupTitle: serializer.fromJson<String?>(json['groupTitle']),
      groupName: serializer.fromJson<String?>(json['groupName']),
      userAgent: serializer.fromJson<String?>(json['userAgent']),
      referrer: serializer.fromJson<String?>(json['referrer']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      contentType: serializer.fromJson<int>(json['contentType']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'playlistId': serializer.toJson<String>(playlistId),
      'url': serializer.toJson<String>(url),
      'name': serializer.toJson<String?>(name),
      'tvgId': serializer.toJson<String?>(tvgId),
      'tvgName': serializer.toJson<String?>(tvgName),
      'tvgLogo': serializer.toJson<String?>(tvgLogo),
      'tvgUrl': serializer.toJson<String?>(tvgUrl),
      'tvgRec': serializer.toJson<String?>(tvgRec),
      'tvgShift': serializer.toJson<String?>(tvgShift),
      'groupTitle': serializer.toJson<String?>(groupTitle),
      'groupName': serializer.toJson<String?>(groupName),
      'userAgent': serializer.toJson<String?>(userAgent),
      'referrer': serializer.toJson<String?>(referrer),
      'categoryId': serializer.toJson<String?>(categoryId),
      'contentType': serializer.toJson<int>(contentType),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  M3uItemData copyWith({
    String? id,
    String? playlistId,
    String? url,
    Value<String?> name = const Value.absent(),
    Value<String?> tvgId = const Value.absent(),
    Value<String?> tvgName = const Value.absent(),
    Value<String?> tvgLogo = const Value.absent(),
    Value<String?> tvgUrl = const Value.absent(),
    Value<String?> tvgRec = const Value.absent(),
    Value<String?> tvgShift = const Value.absent(),
    Value<String?> groupTitle = const Value.absent(),
    Value<String?> groupName = const Value.absent(),
    Value<String?> userAgent = const Value.absent(),
    Value<String?> referrer = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    int? contentType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => M3uItemData(
    id: id ?? this.id,
    playlistId: playlistId ?? this.playlistId,
    url: url ?? this.url,
    name: name.present ? name.value : this.name,
    tvgId: tvgId.present ? tvgId.value : this.tvgId,
    tvgName: tvgName.present ? tvgName.value : this.tvgName,
    tvgLogo: tvgLogo.present ? tvgLogo.value : this.tvgLogo,
    tvgUrl: tvgUrl.present ? tvgUrl.value : this.tvgUrl,
    tvgRec: tvgRec.present ? tvgRec.value : this.tvgRec,
    tvgShift: tvgShift.present ? tvgShift.value : this.tvgShift,
    groupTitle: groupTitle.present ? groupTitle.value : this.groupTitle,
    groupName: groupName.present ? groupName.value : this.groupName,
    userAgent: userAgent.present ? userAgent.value : this.userAgent,
    referrer: referrer.present ? referrer.value : this.referrer,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    contentType: contentType ?? this.contentType,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  M3uItemData copyWithCompanion(M3uItemsCompanion data) {
    return M3uItemData(
      id: data.id.present ? data.id.value : this.id,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      url: data.url.present ? data.url.value : this.url,
      name: data.name.present ? data.name.value : this.name,
      tvgId: data.tvgId.present ? data.tvgId.value : this.tvgId,
      tvgName: data.tvgName.present ? data.tvgName.value : this.tvgName,
      tvgLogo: data.tvgLogo.present ? data.tvgLogo.value : this.tvgLogo,
      tvgUrl: data.tvgUrl.present ? data.tvgUrl.value : this.tvgUrl,
      tvgRec: data.tvgRec.present ? data.tvgRec.value : this.tvgRec,
      tvgShift: data.tvgShift.present ? data.tvgShift.value : this.tvgShift,
      groupTitle: data.groupTitle.present
          ? data.groupTitle.value
          : this.groupTitle,
      groupName: data.groupName.present ? data.groupName.value : this.groupName,
      userAgent: data.userAgent.present ? data.userAgent.value : this.userAgent,
      referrer: data.referrer.present ? data.referrer.value : this.referrer,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('M3uItemData(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('url: $url, ')
          ..write('name: $name, ')
          ..write('tvgId: $tvgId, ')
          ..write('tvgName: $tvgName, ')
          ..write('tvgLogo: $tvgLogo, ')
          ..write('tvgUrl: $tvgUrl, ')
          ..write('tvgRec: $tvgRec, ')
          ..write('tvgShift: $tvgShift, ')
          ..write('groupTitle: $groupTitle, ')
          ..write('groupName: $groupName, ')
          ..write('userAgent: $userAgent, ')
          ..write('referrer: $referrer, ')
          ..write('categoryId: $categoryId, ')
          ..write('contentType: $contentType, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    playlistId,
    url,
    name,
    tvgId,
    tvgName,
    tvgLogo,
    tvgUrl,
    tvgRec,
    tvgShift,
    groupTitle,
    groupName,
    userAgent,
    referrer,
    categoryId,
    contentType,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is M3uItemData &&
          other.id == this.id &&
          other.playlistId == this.playlistId &&
          other.url == this.url &&
          other.name == this.name &&
          other.tvgId == this.tvgId &&
          other.tvgName == this.tvgName &&
          other.tvgLogo == this.tvgLogo &&
          other.tvgUrl == this.tvgUrl &&
          other.tvgRec == this.tvgRec &&
          other.tvgShift == this.tvgShift &&
          other.groupTitle == this.groupTitle &&
          other.groupName == this.groupName &&
          other.userAgent == this.userAgent &&
          other.referrer == this.referrer &&
          other.categoryId == this.categoryId &&
          other.contentType == this.contentType &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class M3uItemsCompanion extends UpdateCompanion<M3uItemData> {
  final Value<String> id;
  final Value<String> playlistId;
  final Value<String> url;
  final Value<String?> name;
  final Value<String?> tvgId;
  final Value<String?> tvgName;
  final Value<String?> tvgLogo;
  final Value<String?> tvgUrl;
  final Value<String?> tvgRec;
  final Value<String?> tvgShift;
  final Value<String?> groupTitle;
  final Value<String?> groupName;
  final Value<String?> userAgent;
  final Value<String?> referrer;
  final Value<String?> categoryId;
  final Value<int> contentType;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const M3uItemsCompanion({
    this.id = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.url = const Value.absent(),
    this.name = const Value.absent(),
    this.tvgId = const Value.absent(),
    this.tvgName = const Value.absent(),
    this.tvgLogo = const Value.absent(),
    this.tvgUrl = const Value.absent(),
    this.tvgRec = const Value.absent(),
    this.tvgShift = const Value.absent(),
    this.groupTitle = const Value.absent(),
    this.groupName = const Value.absent(),
    this.userAgent = const Value.absent(),
    this.referrer = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.contentType = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  M3uItemsCompanion.insert({
    required String id,
    required String playlistId,
    required String url,
    this.name = const Value.absent(),
    this.tvgId = const Value.absent(),
    this.tvgName = const Value.absent(),
    this.tvgLogo = const Value.absent(),
    this.tvgUrl = const Value.absent(),
    this.tvgRec = const Value.absent(),
    this.tvgShift = const Value.absent(),
    this.groupTitle = const Value.absent(),
    this.groupName = const Value.absent(),
    this.userAgent = const Value.absent(),
    this.referrer = const Value.absent(),
    this.categoryId = const Value.absent(),
    required int contentType,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       playlistId = Value(playlistId),
       url = Value(url),
       contentType = Value(contentType);
  static Insertable<M3uItemData> custom({
    Expression<String>? id,
    Expression<String>? playlistId,
    Expression<String>? url,
    Expression<String>? name,
    Expression<String>? tvgId,
    Expression<String>? tvgName,
    Expression<String>? tvgLogo,
    Expression<String>? tvgUrl,
    Expression<String>? tvgRec,
    Expression<String>? tvgShift,
    Expression<String>? groupTitle,
    Expression<String>? groupName,
    Expression<String>? userAgent,
    Expression<String>? referrer,
    Expression<String>? categoryId,
    Expression<int>? contentType,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (playlistId != null) 'playlist_id': playlistId,
      if (url != null) 'url': url,
      if (name != null) 'name': name,
      if (tvgId != null) 'tvg_id': tvgId,
      if (tvgName != null) 'tvg_name': tvgName,
      if (tvgLogo != null) 'tvg_logo': tvgLogo,
      if (tvgUrl != null) 'tvg_url': tvgUrl,
      if (tvgRec != null) 'tvg_rec': tvgRec,
      if (tvgShift != null) 'tvg_shift': tvgShift,
      if (groupTitle != null) 'group_title': groupTitle,
      if (groupName != null) 'group_name': groupName,
      if (userAgent != null) 'user_agent': userAgent,
      if (referrer != null) 'referrer': referrer,
      if (categoryId != null) 'category_id': categoryId,
      if (contentType != null) 'content_type': contentType,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  M3uItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? playlistId,
    Value<String>? url,
    Value<String?>? name,
    Value<String?>? tvgId,
    Value<String?>? tvgName,
    Value<String?>? tvgLogo,
    Value<String?>? tvgUrl,
    Value<String?>? tvgRec,
    Value<String?>? tvgShift,
    Value<String?>? groupTitle,
    Value<String?>? groupName,
    Value<String?>? userAgent,
    Value<String?>? referrer,
    Value<String?>? categoryId,
    Value<int>? contentType,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return M3uItemsCompanion(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      url: url ?? this.url,
      name: name ?? this.name,
      tvgId: tvgId ?? this.tvgId,
      tvgName: tvgName ?? this.tvgName,
      tvgLogo: tvgLogo ?? this.tvgLogo,
      tvgUrl: tvgUrl ?? this.tvgUrl,
      tvgRec: tvgRec ?? this.tvgRec,
      tvgShift: tvgShift ?? this.tvgShift,
      groupTitle: groupTitle ?? this.groupTitle,
      groupName: groupName ?? this.groupName,
      userAgent: userAgent ?? this.userAgent,
      referrer: referrer ?? this.referrer,
      categoryId: categoryId ?? this.categoryId,
      contentType: contentType ?? this.contentType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (tvgId.present) {
      map['tvg_id'] = Variable<String>(tvgId.value);
    }
    if (tvgName.present) {
      map['tvg_name'] = Variable<String>(tvgName.value);
    }
    if (tvgLogo.present) {
      map['tvg_logo'] = Variable<String>(tvgLogo.value);
    }
    if (tvgUrl.present) {
      map['tvg_url'] = Variable<String>(tvgUrl.value);
    }
    if (tvgRec.present) {
      map['tvg_rec'] = Variable<String>(tvgRec.value);
    }
    if (tvgShift.present) {
      map['tvg_shift'] = Variable<String>(tvgShift.value);
    }
    if (groupTitle.present) {
      map['group_title'] = Variable<String>(groupTitle.value);
    }
    if (groupName.present) {
      map['group_name'] = Variable<String>(groupName.value);
    }
    if (userAgent.present) {
      map['user_agent'] = Variable<String>(userAgent.value);
    }
    if (referrer.present) {
      map['referrer'] = Variable<String>(referrer.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<int>(contentType.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('M3uItemsCompanion(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('url: $url, ')
          ..write('name: $name, ')
          ..write('tvgId: $tvgId, ')
          ..write('tvgName: $tvgName, ')
          ..write('tvgLogo: $tvgLogo, ')
          ..write('tvgUrl: $tvgUrl, ')
          ..write('tvgRec: $tvgRec, ')
          ..write('tvgShift: $tvgShift, ')
          ..write('groupTitle: $groupTitle, ')
          ..write('groupName: $groupName, ')
          ..write('userAgent: $userAgent, ')
          ..write('referrer: $referrer, ')
          ..write('categoryId: $categoryId, ')
          ..write('contentType: $contentType, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $M3uSeriesTable extends M3uSeries
    with TableInfo<$M3uSeriesTable, M3uSeriesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $M3uSeriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverMeta = const VerificationMeta('cover');
  @override
  late final GeneratedColumn<String> cover = GeneratedColumn<String>(
    'cover',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    playlistId,
    seriesId,
    name,
    categoryId,
    cover,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'm3u_series';
  @override
  VerificationContext validateIntegrity(
    Insertable<M3uSeriesData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('cover')) {
      context.handle(
        _coverMeta,
        cover.isAcceptableOrUnknown(data['cover']!, _coverMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {playlistId, seriesId};
  @override
  M3uSeriesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return M3uSeriesData(
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      cover: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover'],
      ),
    );
  }

  @override
  $M3uSeriesTable createAlias(String alias) {
    return $M3uSeriesTable(attachedDatabase, alias);
  }
}

class M3uSeriesData extends DataClass implements Insertable<M3uSeriesData> {
  final String playlistId;
  final String seriesId;
  final String name;
  final String? categoryId;
  final String? cover;
  const M3uSeriesData({
    required this.playlistId,
    required this.seriesId,
    required this.name,
    this.categoryId,
    this.cover,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['playlist_id'] = Variable<String>(playlistId);
    map['series_id'] = Variable<String>(seriesId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || cover != null) {
      map['cover'] = Variable<String>(cover);
    }
    return map;
  }

  M3uSeriesCompanion toCompanion(bool nullToAbsent) {
    return M3uSeriesCompanion(
      playlistId: Value(playlistId),
      seriesId: Value(seriesId),
      name: Value(name),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      cover: cover == null && nullToAbsent
          ? const Value.absent()
          : Value(cover),
    );
  }

  factory M3uSeriesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return M3uSeriesData(
      playlistId: serializer.fromJson<String>(json['playlistId']),
      seriesId: serializer.fromJson<String>(json['seriesId']),
      name: serializer.fromJson<String>(json['name']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      cover: serializer.fromJson<String?>(json['cover']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'playlistId': serializer.toJson<String>(playlistId),
      'seriesId': serializer.toJson<String>(seriesId),
      'name': serializer.toJson<String>(name),
      'categoryId': serializer.toJson<String?>(categoryId),
      'cover': serializer.toJson<String?>(cover),
    };
  }

  M3uSeriesData copyWith({
    String? playlistId,
    String? seriesId,
    String? name,
    Value<String?> categoryId = const Value.absent(),
    Value<String?> cover = const Value.absent(),
  }) => M3uSeriesData(
    playlistId: playlistId ?? this.playlistId,
    seriesId: seriesId ?? this.seriesId,
    name: name ?? this.name,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    cover: cover.present ? cover.value : this.cover,
  );
  M3uSeriesData copyWithCompanion(M3uSeriesCompanion data) {
    return M3uSeriesData(
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      name: data.name.present ? data.name.value : this.name,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      cover: data.cover.present ? data.cover.value : this.cover,
    );
  }

  @override
  String toString() {
    return (StringBuffer('M3uSeriesData(')
          ..write('playlistId: $playlistId, ')
          ..write('seriesId: $seriesId, ')
          ..write('name: $name, ')
          ..write('categoryId: $categoryId, ')
          ..write('cover: $cover')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(playlistId, seriesId, name, categoryId, cover);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is M3uSeriesData &&
          other.playlistId == this.playlistId &&
          other.seriesId == this.seriesId &&
          other.name == this.name &&
          other.categoryId == this.categoryId &&
          other.cover == this.cover);
}

class M3uSeriesCompanion extends UpdateCompanion<M3uSeriesData> {
  final Value<String> playlistId;
  final Value<String> seriesId;
  final Value<String> name;
  final Value<String?> categoryId;
  final Value<String?> cover;
  final Value<int> rowid;
  const M3uSeriesCompanion({
    this.playlistId = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.name = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.cover = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  M3uSeriesCompanion.insert({
    required String playlistId,
    required String seriesId,
    required String name,
    this.categoryId = const Value.absent(),
    this.cover = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : playlistId = Value(playlistId),
       seriesId = Value(seriesId),
       name = Value(name);
  static Insertable<M3uSeriesData> custom({
    Expression<String>? playlistId,
    Expression<String>? seriesId,
    Expression<String>? name,
    Expression<String>? categoryId,
    Expression<String>? cover,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (playlistId != null) 'playlist_id': playlistId,
      if (seriesId != null) 'series_id': seriesId,
      if (name != null) 'name': name,
      if (categoryId != null) 'category_id': categoryId,
      if (cover != null) 'cover': cover,
      if (rowid != null) 'rowid': rowid,
    });
  }

  M3uSeriesCompanion copyWith({
    Value<String>? playlistId,
    Value<String>? seriesId,
    Value<String>? name,
    Value<String?>? categoryId,
    Value<String?>? cover,
    Value<int>? rowid,
  }) {
    return M3uSeriesCompanion(
      playlistId: playlistId ?? this.playlistId,
      seriesId: seriesId ?? this.seriesId,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      cover: cover ?? this.cover,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (cover.present) {
      map['cover'] = Variable<String>(cover.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('M3uSeriesCompanion(')
          ..write('playlistId: $playlistId, ')
          ..write('seriesId: $seriesId, ')
          ..write('name: $name, ')
          ..write('categoryId: $categoryId, ')
          ..write('cover: $cover, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $M3uEpisodesTable extends M3uEpisodes
    with TableInfo<$M3uEpisodesTable, M3uEpisodesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $M3uEpisodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seasonNumberMeta = const VerificationMeta(
    'seasonNumber',
  );
  @override
  late final GeneratedColumn<int> seasonNumber = GeneratedColumn<int>(
    'season_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _episodeNumberMeta = const VerificationMeta(
    'episodeNumber',
  );
  @override
  late final GeneratedColumn<int> episodeNumber = GeneratedColumn<int>(
    'episode_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverMeta = const VerificationMeta('cover');
  @override
  late final GeneratedColumn<String> cover = GeneratedColumn<String>(
    'cover',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    playlistId,
    seriesId,
    seasonNumber,
    episodeNumber,
    name,
    url,
    categoryId,
    cover,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'm3u_episodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<M3uEpisodesData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('season_number')) {
      context.handle(
        _seasonNumberMeta,
        seasonNumber.isAcceptableOrUnknown(
          data['season_number']!,
          _seasonNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_seasonNumberMeta);
    }
    if (data.containsKey('episode_number')) {
      context.handle(
        _episodeNumberMeta,
        episodeNumber.isAcceptableOrUnknown(
          data['episode_number']!,
          _episodeNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_episodeNumberMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('cover')) {
      context.handle(
        _coverMeta,
        cover.isAcceptableOrUnknown(data['cover']!, _coverMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    playlistId,
    seriesId,
    seasonNumber,
    episodeNumber,
  };
  @override
  M3uEpisodesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return M3uEpisodesData(
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      )!,
      seasonNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season_number'],
      )!,
      episodeNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_number'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      cover: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover'],
      ),
    );
  }

  @override
  $M3uEpisodesTable createAlias(String alias) {
    return $M3uEpisodesTable(attachedDatabase, alias);
  }
}

class M3uEpisodesData extends DataClass implements Insertable<M3uEpisodesData> {
  final String playlistId;
  final String seriesId;
  final int seasonNumber;
  final int episodeNumber;
  final String name;
  final String url;
  final String? categoryId;
  final String? cover;
  const M3uEpisodesData({
    required this.playlistId,
    required this.seriesId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.name,
    required this.url,
    this.categoryId,
    this.cover,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['playlist_id'] = Variable<String>(playlistId);
    map['series_id'] = Variable<String>(seriesId);
    map['season_number'] = Variable<int>(seasonNumber);
    map['episode_number'] = Variable<int>(episodeNumber);
    map['name'] = Variable<String>(name);
    map['url'] = Variable<String>(url);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || cover != null) {
      map['cover'] = Variable<String>(cover);
    }
    return map;
  }

  M3uEpisodesCompanion toCompanion(bool nullToAbsent) {
    return M3uEpisodesCompanion(
      playlistId: Value(playlistId),
      seriesId: Value(seriesId),
      seasonNumber: Value(seasonNumber),
      episodeNumber: Value(episodeNumber),
      name: Value(name),
      url: Value(url),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      cover: cover == null && nullToAbsent
          ? const Value.absent()
          : Value(cover),
    );
  }

  factory M3uEpisodesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return M3uEpisodesData(
      playlistId: serializer.fromJson<String>(json['playlistId']),
      seriesId: serializer.fromJson<String>(json['seriesId']),
      seasonNumber: serializer.fromJson<int>(json['seasonNumber']),
      episodeNumber: serializer.fromJson<int>(json['episodeNumber']),
      name: serializer.fromJson<String>(json['name']),
      url: serializer.fromJson<String>(json['url']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      cover: serializer.fromJson<String?>(json['cover']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'playlistId': serializer.toJson<String>(playlistId),
      'seriesId': serializer.toJson<String>(seriesId),
      'seasonNumber': serializer.toJson<int>(seasonNumber),
      'episodeNumber': serializer.toJson<int>(episodeNumber),
      'name': serializer.toJson<String>(name),
      'url': serializer.toJson<String>(url),
      'categoryId': serializer.toJson<String?>(categoryId),
      'cover': serializer.toJson<String?>(cover),
    };
  }

  M3uEpisodesData copyWith({
    String? playlistId,
    String? seriesId,
    int? seasonNumber,
    int? episodeNumber,
    String? name,
    String? url,
    Value<String?> categoryId = const Value.absent(),
    Value<String?> cover = const Value.absent(),
  }) => M3uEpisodesData(
    playlistId: playlistId ?? this.playlistId,
    seriesId: seriesId ?? this.seriesId,
    seasonNumber: seasonNumber ?? this.seasonNumber,
    episodeNumber: episodeNumber ?? this.episodeNumber,
    name: name ?? this.name,
    url: url ?? this.url,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    cover: cover.present ? cover.value : this.cover,
  );
  M3uEpisodesData copyWithCompanion(M3uEpisodesCompanion data) {
    return M3uEpisodesData(
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      seasonNumber: data.seasonNumber.present
          ? data.seasonNumber.value
          : this.seasonNumber,
      episodeNumber: data.episodeNumber.present
          ? data.episodeNumber.value
          : this.episodeNumber,
      name: data.name.present ? data.name.value : this.name,
      url: data.url.present ? data.url.value : this.url,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      cover: data.cover.present ? data.cover.value : this.cover,
    );
  }

  @override
  String toString() {
    return (StringBuffer('M3uEpisodesData(')
          ..write('playlistId: $playlistId, ')
          ..write('seriesId: $seriesId, ')
          ..write('seasonNumber: $seasonNumber, ')
          ..write('episodeNumber: $episodeNumber, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('categoryId: $categoryId, ')
          ..write('cover: $cover')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    playlistId,
    seriesId,
    seasonNumber,
    episodeNumber,
    name,
    url,
    categoryId,
    cover,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is M3uEpisodesData &&
          other.playlistId == this.playlistId &&
          other.seriesId == this.seriesId &&
          other.seasonNumber == this.seasonNumber &&
          other.episodeNumber == this.episodeNumber &&
          other.name == this.name &&
          other.url == this.url &&
          other.categoryId == this.categoryId &&
          other.cover == this.cover);
}

class M3uEpisodesCompanion extends UpdateCompanion<M3uEpisodesData> {
  final Value<String> playlistId;
  final Value<String> seriesId;
  final Value<int> seasonNumber;
  final Value<int> episodeNumber;
  final Value<String> name;
  final Value<String> url;
  final Value<String?> categoryId;
  final Value<String?> cover;
  final Value<int> rowid;
  const M3uEpisodesCompanion({
    this.playlistId = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.seasonNumber = const Value.absent(),
    this.episodeNumber = const Value.absent(),
    this.name = const Value.absent(),
    this.url = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.cover = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  M3uEpisodesCompanion.insert({
    required String playlistId,
    required String seriesId,
    required int seasonNumber,
    required int episodeNumber,
    required String name,
    required String url,
    this.categoryId = const Value.absent(),
    this.cover = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : playlistId = Value(playlistId),
       seriesId = Value(seriesId),
       seasonNumber = Value(seasonNumber),
       episodeNumber = Value(episodeNumber),
       name = Value(name),
       url = Value(url);
  static Insertable<M3uEpisodesData> custom({
    Expression<String>? playlistId,
    Expression<String>? seriesId,
    Expression<int>? seasonNumber,
    Expression<int>? episodeNumber,
    Expression<String>? name,
    Expression<String>? url,
    Expression<String>? categoryId,
    Expression<String>? cover,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (playlistId != null) 'playlist_id': playlistId,
      if (seriesId != null) 'series_id': seriesId,
      if (seasonNumber != null) 'season_number': seasonNumber,
      if (episodeNumber != null) 'episode_number': episodeNumber,
      if (name != null) 'name': name,
      if (url != null) 'url': url,
      if (categoryId != null) 'category_id': categoryId,
      if (cover != null) 'cover': cover,
      if (rowid != null) 'rowid': rowid,
    });
  }

  M3uEpisodesCompanion copyWith({
    Value<String>? playlistId,
    Value<String>? seriesId,
    Value<int>? seasonNumber,
    Value<int>? episodeNumber,
    Value<String>? name,
    Value<String>? url,
    Value<String?>? categoryId,
    Value<String?>? cover,
    Value<int>? rowid,
  }) {
    return M3uEpisodesCompanion(
      playlistId: playlistId ?? this.playlistId,
      seriesId: seriesId ?? this.seriesId,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      name: name ?? this.name,
      url: url ?? this.url,
      categoryId: categoryId ?? this.categoryId,
      cover: cover ?? this.cover,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (seasonNumber.present) {
      map['season_number'] = Variable<int>(seasonNumber.value);
    }
    if (episodeNumber.present) {
      map['episode_number'] = Variable<int>(episodeNumber.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (cover.present) {
      map['cover'] = Variable<String>(cover.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('M3uEpisodesCompanion(')
          ..write('playlistId: $playlistId, ')
          ..write('seriesId: $seriesId, ')
          ..write('seasonNumber: $seasonNumber, ')
          ..write('episodeNumber: $episodeNumber, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('categoryId: $categoryId, ')
          ..write('cover: $cover, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FavoritesTable extends Favorites
    with TableInfo<$FavoritesTable, FavoritesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoritesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<int> contentType = GeneratedColumn<int>(
    'content_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _streamIdMeta = const VerificationMeta(
    'streamId',
  );
  @override
  late final GeneratedColumn<String> streamId = GeneratedColumn<String>(
    'stream_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _episodeIdMeta = const VerificationMeta(
    'episodeId',
  );
  @override
  late final GeneratedColumn<String> episodeId = GeneratedColumn<String>(
    'episode_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _m3uItemIdMeta = const VerificationMeta(
    'm3uItemId',
  );
  @override
  late final GeneratedColumn<String> m3uItemId = GeneratedColumn<String>(
    'm3u_item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imagePathMeta = const VerificationMeta(
    'imagePath',
  );
  @override
  late final GeneratedColumn<String> imagePath = GeneratedColumn<String>(
    'image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    playlistId,
    contentType,
    streamId,
    episodeId,
    m3uItemId,
    name,
    imagePath,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorites';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoritesData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentTypeMeta);
    }
    if (data.containsKey('stream_id')) {
      context.handle(
        _streamIdMeta,
        streamId.isAcceptableOrUnknown(data['stream_id']!, _streamIdMeta),
      );
    } else if (isInserting) {
      context.missing(_streamIdMeta);
    }
    if (data.containsKey('episode_id')) {
      context.handle(
        _episodeIdMeta,
        episodeId.isAcceptableOrUnknown(data['episode_id']!, _episodeIdMeta),
      );
    }
    if (data.containsKey('m3u_item_id')) {
      context.handle(
        _m3uItemIdMeta,
        m3uItemId.isAcceptableOrUnknown(data['m3u_item_id']!, _m3uItemIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('image_path')) {
      context.handle(
        _imagePathMeta,
        imagePath.isAcceptableOrUnknown(data['image_path']!, _imagePathMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FavoritesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoritesData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}content_type'],
      )!,
      streamId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream_id'],
      )!,
      episodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}episode_id'],
      ),
      m3uItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}m3u_item_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      imagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FavoritesTable createAlias(String alias) {
    return $FavoritesTable(attachedDatabase, alias);
  }
}

class FavoritesData extends DataClass implements Insertable<FavoritesData> {
  final String id;
  final String playlistId;
  final int contentType;
  final String streamId;
  final String? episodeId;
  final String? m3uItemId;
  final String name;
  final String? imagePath;
  final DateTime createdAt;
  final DateTime updatedAt;
  const FavoritesData({
    required this.id,
    required this.playlistId,
    required this.contentType,
    required this.streamId,
    this.episodeId,
    this.m3uItemId,
    required this.name,
    this.imagePath,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['playlist_id'] = Variable<String>(playlistId);
    map['content_type'] = Variable<int>(contentType);
    map['stream_id'] = Variable<String>(streamId);
    if (!nullToAbsent || episodeId != null) {
      map['episode_id'] = Variable<String>(episodeId);
    }
    if (!nullToAbsent || m3uItemId != null) {
      map['m3u_item_id'] = Variable<String>(m3uItemId);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || imagePath != null) {
      map['image_path'] = Variable<String>(imagePath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  FavoritesCompanion toCompanion(bool nullToAbsent) {
    return FavoritesCompanion(
      id: Value(id),
      playlistId: Value(playlistId),
      contentType: Value(contentType),
      streamId: Value(streamId),
      episodeId: episodeId == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeId),
      m3uItemId: m3uItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(m3uItemId),
      name: Value(name),
      imagePath: imagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(imagePath),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory FavoritesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoritesData(
      id: serializer.fromJson<String>(json['id']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      contentType: serializer.fromJson<int>(json['contentType']),
      streamId: serializer.fromJson<String>(json['streamId']),
      episodeId: serializer.fromJson<String?>(json['episodeId']),
      m3uItemId: serializer.fromJson<String?>(json['m3uItemId']),
      name: serializer.fromJson<String>(json['name']),
      imagePath: serializer.fromJson<String?>(json['imagePath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'playlistId': serializer.toJson<String>(playlistId),
      'contentType': serializer.toJson<int>(contentType),
      'streamId': serializer.toJson<String>(streamId),
      'episodeId': serializer.toJson<String?>(episodeId),
      'm3uItemId': serializer.toJson<String?>(m3uItemId),
      'name': serializer.toJson<String>(name),
      'imagePath': serializer.toJson<String?>(imagePath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  FavoritesData copyWith({
    String? id,
    String? playlistId,
    int? contentType,
    String? streamId,
    Value<String?> episodeId = const Value.absent(),
    Value<String?> m3uItemId = const Value.absent(),
    String? name,
    Value<String?> imagePath = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => FavoritesData(
    id: id ?? this.id,
    playlistId: playlistId ?? this.playlistId,
    contentType: contentType ?? this.contentType,
    streamId: streamId ?? this.streamId,
    episodeId: episodeId.present ? episodeId.value : this.episodeId,
    m3uItemId: m3uItemId.present ? m3uItemId.value : this.m3uItemId,
    name: name ?? this.name,
    imagePath: imagePath.present ? imagePath.value : this.imagePath,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  FavoritesData copyWithCompanion(FavoritesCompanion data) {
    return FavoritesData(
      id: data.id.present ? data.id.value : this.id,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      streamId: data.streamId.present ? data.streamId.value : this.streamId,
      episodeId: data.episodeId.present ? data.episodeId.value : this.episodeId,
      m3uItemId: data.m3uItemId.present ? data.m3uItemId.value : this.m3uItemId,
      name: data.name.present ? data.name.value : this.name,
      imagePath: data.imagePath.present ? data.imagePath.value : this.imagePath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoritesData(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('contentType: $contentType, ')
          ..write('streamId: $streamId, ')
          ..write('episodeId: $episodeId, ')
          ..write('m3uItemId: $m3uItemId, ')
          ..write('name: $name, ')
          ..write('imagePath: $imagePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    playlistId,
    contentType,
    streamId,
    episodeId,
    m3uItemId,
    name,
    imagePath,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoritesData &&
          other.id == this.id &&
          other.playlistId == this.playlistId &&
          other.contentType == this.contentType &&
          other.streamId == this.streamId &&
          other.episodeId == this.episodeId &&
          other.m3uItemId == this.m3uItemId &&
          other.name == this.name &&
          other.imagePath == this.imagePath &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class FavoritesCompanion extends UpdateCompanion<FavoritesData> {
  final Value<String> id;
  final Value<String> playlistId;
  final Value<int> contentType;
  final Value<String> streamId;
  final Value<String?> episodeId;
  final Value<String?> m3uItemId;
  final Value<String> name;
  final Value<String?> imagePath;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const FavoritesCompanion({
    this.id = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.contentType = const Value.absent(),
    this.streamId = const Value.absent(),
    this.episodeId = const Value.absent(),
    this.m3uItemId = const Value.absent(),
    this.name = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoritesCompanion.insert({
    required String id,
    required String playlistId,
    required int contentType,
    required String streamId,
    this.episodeId = const Value.absent(),
    this.m3uItemId = const Value.absent(),
    required String name,
    this.imagePath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       playlistId = Value(playlistId),
       contentType = Value(contentType),
       streamId = Value(streamId),
       name = Value(name);
  static Insertable<FavoritesData> custom({
    Expression<String>? id,
    Expression<String>? playlistId,
    Expression<int>? contentType,
    Expression<String>? streamId,
    Expression<String>? episodeId,
    Expression<String>? m3uItemId,
    Expression<String>? name,
    Expression<String>? imagePath,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (playlistId != null) 'playlist_id': playlistId,
      if (contentType != null) 'content_type': contentType,
      if (streamId != null) 'stream_id': streamId,
      if (episodeId != null) 'episode_id': episodeId,
      if (m3uItemId != null) 'm3u_item_id': m3uItemId,
      if (name != null) 'name': name,
      if (imagePath != null) 'image_path': imagePath,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoritesCompanion copyWith({
    Value<String>? id,
    Value<String>? playlistId,
    Value<int>? contentType,
    Value<String>? streamId,
    Value<String?>? episodeId,
    Value<String?>? m3uItemId,
    Value<String>? name,
    Value<String?>? imagePath,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return FavoritesCompanion(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      contentType: contentType ?? this.contentType,
      streamId: streamId ?? this.streamId,
      episodeId: episodeId ?? this.episodeId,
      m3uItemId: m3uItemId ?? this.m3uItemId,
      name: name ?? this.name,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<int>(contentType.value);
    }
    if (streamId.present) {
      map['stream_id'] = Variable<String>(streamId.value);
    }
    if (episodeId.present) {
      map['episode_id'] = Variable<String>(episodeId.value);
    }
    if (m3uItemId.present) {
      map['m3u_item_id'] = Variable<String>(m3uItemId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (imagePath.present) {
      map['image_path'] = Variable<String>(imagePath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoritesCompanion(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('contentType: $contentType, ')
          ..write('streamId: $streamId, ')
          ..write('episodeId: $episodeId, ')
          ..write('m3uItemId: $m3uItemId, ')
          ..write('name: $name, ')
          ..write('imagePath: $imagePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PlaylistsTable playlists = $PlaylistsTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $UserInfosTable userInfos = $UserInfosTable(this);
  late final $ServerInfosTable serverInfos = $ServerInfosTable(this);
  late final $LiveStreamsTable liveStreams = $LiveStreamsTable(this);
  late final $VodStreamsTable vodStreams = $VodStreamsTable(this);
  late final $SeriesStreamsTable seriesStreams = $SeriesStreamsTable(this);
  late final $SeriesInfosTable seriesInfos = $SeriesInfosTable(this);
  late final $SeasonsTable seasons = $SeasonsTable(this);
  late final $EpisodesTable episodes = $EpisodesTable(this);
  late final $WatchHistoriesTable watchHistories = $WatchHistoriesTable(this);
  late final $M3uItemsTable m3uItems = $M3uItemsTable(this);
  late final $M3uSeriesTable m3uSeries = $M3uSeriesTable(this);
  late final $M3uEpisodesTable m3uEpisodes = $M3uEpisodesTable(this);
  late final $FavoritesTable favorites = $FavoritesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    playlists,
    categories,
    userInfos,
    serverInfos,
    liveStreams,
    vodStreams,
    seriesStreams,
    seriesInfos,
    seasons,
    episodes,
    watchHistories,
    m3uItems,
    m3uSeries,
    m3uEpisodes,
    favorites,
  ];
}

typedef $$PlaylistsTableCreateCompanionBuilder =
    PlaylistsCompanion Function({
      required String id,
      required String name,
      required String type,
      Value<String?> url,
      Value<String?> username,
      Value<String?> password,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$PlaylistsTableUpdateCompanionBuilder =
    PlaylistsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> type,
      Value<String?> url,
      Value<String?> username,
      Value<String?> password,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$PlaylistsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get password =>
      $composableBuilder(column: $table.password, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PlaylistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistsTable,
          PlaylistData,
          $$PlaylistsTableFilterComposer,
          $$PlaylistsTableOrderingComposer,
          $$PlaylistsTableAnnotationComposer,
          $$PlaylistsTableCreateCompanionBuilder,
          $$PlaylistsTableUpdateCompanionBuilder,
          (
            PlaylistData,
            BaseReferences<_$AppDatabase, $PlaylistsTable, PlaylistData>,
          ),
          PlaylistData,
          PrefetchHooks Function()
        > {
  $$PlaylistsTableTableManager(_$AppDatabase db, $PlaylistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<String?> password = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion(
                id: id,
                name: name,
                type: type,
                url: url,
                username: username,
                password: password,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String type,
                Value<String?> url = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<String?> password = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion.insert(
                id: id,
                name: name,
                type: type,
                url: url,
                username: username,
                password: password,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistsTable,
      PlaylistData,
      $$PlaylistsTableFilterComposer,
      $$PlaylistsTableOrderingComposer,
      $$PlaylistsTableAnnotationComposer,
      $$PlaylistsTableCreateCompanionBuilder,
      $$PlaylistsTableUpdateCompanionBuilder,
      (
        PlaylistData,
        BaseReferences<_$AppDatabase, $PlaylistsTable, PlaylistData>,
      ),
      PlaylistData,
      PrefetchHooks Function()
    >;
typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      required String categoryId,
      required String categoryName,
      Value<int> parentId,
      required String playlistId,
      required String type,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<String> categoryId,
      Value<String> categoryName,
      Value<int> parentId,
      Value<String> playlistId,
      Value<String> type,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryName => $composableBuilder(
    column: $table.categoryName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryName => $composableBuilder(
    column: $table.categoryName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get categoryName => $composableBuilder(
    column: $table.categoryName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          CategoriesData,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (
            CategoriesData,
            BaseReferences<_$AppDatabase, $CategoriesTable, CategoriesData>,
          ),
          CategoriesData,
          PrefetchHooks Function()
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> categoryId = const Value.absent(),
                Value<String> categoryName = const Value.absent(),
                Value<int> parentId = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                categoryId: categoryId,
                categoryName: categoryName,
                parentId: parentId,
                playlistId: playlistId,
                type: type,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String categoryId,
                required String categoryName,
                Value<int> parentId = const Value.absent(),
                required String playlistId,
                required String type,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                categoryId: categoryId,
                categoryName: categoryName,
                parentId: parentId,
                playlistId: playlistId,
                type: type,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      CategoriesData,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (
        CategoriesData,
        BaseReferences<_$AppDatabase, $CategoriesTable, CategoriesData>,
      ),
      CategoriesData,
      PrefetchHooks Function()
    >;
typedef $$UserInfosTableCreateCompanionBuilder =
    UserInfosCompanion Function({
      Value<int> id,
      required String playlistId,
      required String username,
      required String password,
      required String message,
      required int auth,
      required String status,
      required String expDate,
      required String isTrial,
      required String activeCons,
      required String createdAt,
      required String maxConnections,
      required String allowedOutputFormats,
    });
typedef $$UserInfosTableUpdateCompanionBuilder =
    UserInfosCompanion Function({
      Value<int> id,
      Value<String> playlistId,
      Value<String> username,
      Value<String> password,
      Value<String> message,
      Value<int> auth,
      Value<String> status,
      Value<String> expDate,
      Value<String> isTrial,
      Value<String> activeCons,
      Value<String> createdAt,
      Value<String> maxConnections,
      Value<String> allowedOutputFormats,
    });

class $$UserInfosTableFilterComposer
    extends Composer<_$AppDatabase, $UserInfosTable> {
  $$UserInfosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get auth => $composableBuilder(
    column: $table.auth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expDate => $composableBuilder(
    column: $table.expDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get isTrial => $composableBuilder(
    column: $table.isTrial,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activeCons => $composableBuilder(
    column: $table.activeCons,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get maxConnections => $composableBuilder(
    column: $table.maxConnections,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get allowedOutputFormats => $composableBuilder(
    column: $table.allowedOutputFormats,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserInfosTableOrderingComposer
    extends Composer<_$AppDatabase, $UserInfosTable> {
  $$UserInfosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get auth => $composableBuilder(
    column: $table.auth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expDate => $composableBuilder(
    column: $table.expDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get isTrial => $composableBuilder(
    column: $table.isTrial,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activeCons => $composableBuilder(
    column: $table.activeCons,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get maxConnections => $composableBuilder(
    column: $table.maxConnections,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get allowedOutputFormats => $composableBuilder(
    column: $table.allowedOutputFormats,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserInfosTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserInfosTable> {
  $$UserInfosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get password =>
      $composableBuilder(column: $table.password, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<int> get auth =>
      $composableBuilder(column: $table.auth, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get expDate =>
      $composableBuilder(column: $table.expDate, builder: (column) => column);

  GeneratedColumn<String> get isTrial =>
      $composableBuilder(column: $table.isTrial, builder: (column) => column);

  GeneratedColumn<String> get activeCons => $composableBuilder(
    column: $table.activeCons,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get maxConnections => $composableBuilder(
    column: $table.maxConnections,
    builder: (column) => column,
  );

  GeneratedColumn<String> get allowedOutputFormats => $composableBuilder(
    column: $table.allowedOutputFormats,
    builder: (column) => column,
  );
}

class $$UserInfosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserInfosTable,
          UserInfosData,
          $$UserInfosTableFilterComposer,
          $$UserInfosTableOrderingComposer,
          $$UserInfosTableAnnotationComposer,
          $$UserInfosTableCreateCompanionBuilder,
          $$UserInfosTableUpdateCompanionBuilder,
          (
            UserInfosData,
            BaseReferences<_$AppDatabase, $UserInfosTable, UserInfosData>,
          ),
          UserInfosData,
          PrefetchHooks Function()
        > {
  $$UserInfosTableTableManager(_$AppDatabase db, $UserInfosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserInfosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserInfosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserInfosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> password = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<int> auth = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> expDate = const Value.absent(),
                Value<String> isTrial = const Value.absent(),
                Value<String> activeCons = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> maxConnections = const Value.absent(),
                Value<String> allowedOutputFormats = const Value.absent(),
              }) => UserInfosCompanion(
                id: id,
                playlistId: playlistId,
                username: username,
                password: password,
                message: message,
                auth: auth,
                status: status,
                expDate: expDate,
                isTrial: isTrial,
                activeCons: activeCons,
                createdAt: createdAt,
                maxConnections: maxConnections,
                allowedOutputFormats: allowedOutputFormats,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String playlistId,
                required String username,
                required String password,
                required String message,
                required int auth,
                required String status,
                required String expDate,
                required String isTrial,
                required String activeCons,
                required String createdAt,
                required String maxConnections,
                required String allowedOutputFormats,
              }) => UserInfosCompanion.insert(
                id: id,
                playlistId: playlistId,
                username: username,
                password: password,
                message: message,
                auth: auth,
                status: status,
                expDate: expDate,
                isTrial: isTrial,
                activeCons: activeCons,
                createdAt: createdAt,
                maxConnections: maxConnections,
                allowedOutputFormats: allowedOutputFormats,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserInfosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserInfosTable,
      UserInfosData,
      $$UserInfosTableFilterComposer,
      $$UserInfosTableOrderingComposer,
      $$UserInfosTableAnnotationComposer,
      $$UserInfosTableCreateCompanionBuilder,
      $$UserInfosTableUpdateCompanionBuilder,
      (
        UserInfosData,
        BaseReferences<_$AppDatabase, $UserInfosTable, UserInfosData>,
      ),
      UserInfosData,
      PrefetchHooks Function()
    >;
typedef $$ServerInfosTableCreateCompanionBuilder =
    ServerInfosCompanion Function({
      Value<int> id,
      required String playlistId,
      required String url,
      required String port,
      required String httpsPort,
      required String serverProtocol,
      required String rtmpPort,
      required String timezone,
      required int timestampNow,
      required String timeNow,
    });
typedef $$ServerInfosTableUpdateCompanionBuilder =
    ServerInfosCompanion Function({
      Value<int> id,
      Value<String> playlistId,
      Value<String> url,
      Value<String> port,
      Value<String> httpsPort,
      Value<String> serverProtocol,
      Value<String> rtmpPort,
      Value<String> timezone,
      Value<int> timestampNow,
      Value<String> timeNow,
    });

class $$ServerInfosTableFilterComposer
    extends Composer<_$AppDatabase, $ServerInfosTable> {
  $$ServerInfosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get httpsPort => $composableBuilder(
    column: $table.httpsPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverProtocol => $composableBuilder(
    column: $table.serverProtocol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rtmpPort => $composableBuilder(
    column: $table.rtmpPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestampNow => $composableBuilder(
    column: $table.timestampNow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeNow => $composableBuilder(
    column: $table.timeNow,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ServerInfosTableOrderingComposer
    extends Composer<_$AppDatabase, $ServerInfosTable> {
  $$ServerInfosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get httpsPort => $composableBuilder(
    column: $table.httpsPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverProtocol => $composableBuilder(
    column: $table.serverProtocol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rtmpPort => $composableBuilder(
    column: $table.rtmpPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestampNow => $composableBuilder(
    column: $table.timestampNow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeNow => $composableBuilder(
    column: $table.timeNow,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ServerInfosTableAnnotationComposer
    extends Composer<_$AppDatabase, $ServerInfosTable> {
  $$ServerInfosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get httpsPort =>
      $composableBuilder(column: $table.httpsPort, builder: (column) => column);

  GeneratedColumn<String> get serverProtocol => $composableBuilder(
    column: $table.serverProtocol,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rtmpPort =>
      $composableBuilder(column: $table.rtmpPort, builder: (column) => column);

  GeneratedColumn<String> get timezone =>
      $composableBuilder(column: $table.timezone, builder: (column) => column);

  GeneratedColumn<int> get timestampNow => $composableBuilder(
    column: $table.timestampNow,
    builder: (column) => column,
  );

  GeneratedColumn<String> get timeNow =>
      $composableBuilder(column: $table.timeNow, builder: (column) => column);
}

class $$ServerInfosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ServerInfosTable,
          ServerInfosData,
          $$ServerInfosTableFilterComposer,
          $$ServerInfosTableOrderingComposer,
          $$ServerInfosTableAnnotationComposer,
          $$ServerInfosTableCreateCompanionBuilder,
          $$ServerInfosTableUpdateCompanionBuilder,
          (
            ServerInfosData,
            BaseReferences<_$AppDatabase, $ServerInfosTable, ServerInfosData>,
          ),
          ServerInfosData,
          PrefetchHooks Function()
        > {
  $$ServerInfosTableTableManager(_$AppDatabase db, $ServerInfosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ServerInfosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ServerInfosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ServerInfosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> port = const Value.absent(),
                Value<String> httpsPort = const Value.absent(),
                Value<String> serverProtocol = const Value.absent(),
                Value<String> rtmpPort = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                Value<int> timestampNow = const Value.absent(),
                Value<String> timeNow = const Value.absent(),
              }) => ServerInfosCompanion(
                id: id,
                playlistId: playlistId,
                url: url,
                port: port,
                httpsPort: httpsPort,
                serverProtocol: serverProtocol,
                rtmpPort: rtmpPort,
                timezone: timezone,
                timestampNow: timestampNow,
                timeNow: timeNow,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String playlistId,
                required String url,
                required String port,
                required String httpsPort,
                required String serverProtocol,
                required String rtmpPort,
                required String timezone,
                required int timestampNow,
                required String timeNow,
              }) => ServerInfosCompanion.insert(
                id: id,
                playlistId: playlistId,
                url: url,
                port: port,
                httpsPort: httpsPort,
                serverProtocol: serverProtocol,
                rtmpPort: rtmpPort,
                timezone: timezone,
                timestampNow: timestampNow,
                timeNow: timeNow,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ServerInfosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ServerInfosTable,
      ServerInfosData,
      $$ServerInfosTableFilterComposer,
      $$ServerInfosTableOrderingComposer,
      $$ServerInfosTableAnnotationComposer,
      $$ServerInfosTableCreateCompanionBuilder,
      $$ServerInfosTableUpdateCompanionBuilder,
      (
        ServerInfosData,
        BaseReferences<_$AppDatabase, $ServerInfosTable, ServerInfosData>,
      ),
      ServerInfosData,
      PrefetchHooks Function()
    >;
typedef $$LiveStreamsTableCreateCompanionBuilder =
    LiveStreamsCompanion Function({
      required String streamId,
      required String name,
      required String streamIcon,
      required String categoryId,
      required String epgChannelId,
      required String playlistId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$LiveStreamsTableUpdateCompanionBuilder =
    LiveStreamsCompanion Function({
      Value<String> streamId,
      Value<String> name,
      Value<String> streamIcon,
      Value<String> categoryId,
      Value<String> epgChannelId,
      Value<String> playlistId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$LiveStreamsTableFilterComposer
    extends Composer<_$AppDatabase, $LiveStreamsTable> {
  $$LiveStreamsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get streamIcon => $composableBuilder(
    column: $table.streamIcon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get epgChannelId => $composableBuilder(
    column: $table.epgChannelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LiveStreamsTableOrderingComposer
    extends Composer<_$AppDatabase, $LiveStreamsTable> {
  $$LiveStreamsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get streamIcon => $composableBuilder(
    column: $table.streamIcon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get epgChannelId => $composableBuilder(
    column: $table.epgChannelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LiveStreamsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LiveStreamsTable> {
  $$LiveStreamsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get streamId =>
      $composableBuilder(column: $table.streamId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get streamIcon => $composableBuilder(
    column: $table.streamIcon,
    builder: (column) => column,
  );

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get epgChannelId => $composableBuilder(
    column: $table.epgChannelId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$LiveStreamsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LiveStreamsTable,
          LiveStreamsData,
          $$LiveStreamsTableFilterComposer,
          $$LiveStreamsTableOrderingComposer,
          $$LiveStreamsTableAnnotationComposer,
          $$LiveStreamsTableCreateCompanionBuilder,
          $$LiveStreamsTableUpdateCompanionBuilder,
          (
            LiveStreamsData,
            BaseReferences<_$AppDatabase, $LiveStreamsTable, LiveStreamsData>,
          ),
          LiveStreamsData,
          PrefetchHooks Function()
        > {
  $$LiveStreamsTableTableManager(_$AppDatabase db, $LiveStreamsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LiveStreamsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LiveStreamsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LiveStreamsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> streamId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> streamIcon = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<String> epgChannelId = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LiveStreamsCompanion(
                streamId: streamId,
                name: name,
                streamIcon: streamIcon,
                categoryId: categoryId,
                epgChannelId: epgChannelId,
                playlistId: playlistId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String streamId,
                required String name,
                required String streamIcon,
                required String categoryId,
                required String epgChannelId,
                required String playlistId,
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LiveStreamsCompanion.insert(
                streamId: streamId,
                name: name,
                streamIcon: streamIcon,
                categoryId: categoryId,
                epgChannelId: epgChannelId,
                playlistId: playlistId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LiveStreamsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LiveStreamsTable,
      LiveStreamsData,
      $$LiveStreamsTableFilterComposer,
      $$LiveStreamsTableOrderingComposer,
      $$LiveStreamsTableAnnotationComposer,
      $$LiveStreamsTableCreateCompanionBuilder,
      $$LiveStreamsTableUpdateCompanionBuilder,
      (
        LiveStreamsData,
        BaseReferences<_$AppDatabase, $LiveStreamsTable, LiveStreamsData>,
      ),
      LiveStreamsData,
      PrefetchHooks Function()
    >;
typedef $$VodStreamsTableCreateCompanionBuilder =
    VodStreamsCompanion Function({
      required String streamId,
      required String name,
      required String streamIcon,
      required String categoryId,
      required String rating,
      required double rating5based,
      required String containerExtension,
      required String playlistId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$VodStreamsTableUpdateCompanionBuilder =
    VodStreamsCompanion Function({
      Value<String> streamId,
      Value<String> name,
      Value<String> streamIcon,
      Value<String> categoryId,
      Value<String> rating,
      Value<double> rating5based,
      Value<String> containerExtension,
      Value<String> playlistId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$VodStreamsTableFilterComposer
    extends Composer<_$AppDatabase, $VodStreamsTable> {
  $$VodStreamsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get streamIcon => $composableBuilder(
    column: $table.streamIcon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rating5based => $composableBuilder(
    column: $table.rating5based,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get containerExtension => $composableBuilder(
    column: $table.containerExtension,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VodStreamsTableOrderingComposer
    extends Composer<_$AppDatabase, $VodStreamsTable> {
  $$VodStreamsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get streamIcon => $composableBuilder(
    column: $table.streamIcon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rating5based => $composableBuilder(
    column: $table.rating5based,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get containerExtension => $composableBuilder(
    column: $table.containerExtension,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VodStreamsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VodStreamsTable> {
  $$VodStreamsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get streamId =>
      $composableBuilder(column: $table.streamId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get streamIcon => $composableBuilder(
    column: $table.streamIcon,
    builder: (column) => column,
  );

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<double> get rating5based => $composableBuilder(
    column: $table.rating5based,
    builder: (column) => column,
  );

  GeneratedColumn<String> get containerExtension => $composableBuilder(
    column: $table.containerExtension,
    builder: (column) => column,
  );

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$VodStreamsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VodStreamsTable,
          VodStreamsData,
          $$VodStreamsTableFilterComposer,
          $$VodStreamsTableOrderingComposer,
          $$VodStreamsTableAnnotationComposer,
          $$VodStreamsTableCreateCompanionBuilder,
          $$VodStreamsTableUpdateCompanionBuilder,
          (
            VodStreamsData,
            BaseReferences<_$AppDatabase, $VodStreamsTable, VodStreamsData>,
          ),
          VodStreamsData,
          PrefetchHooks Function()
        > {
  $$VodStreamsTableTableManager(_$AppDatabase db, $VodStreamsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VodStreamsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VodStreamsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VodStreamsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> streamId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> streamIcon = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<String> rating = const Value.absent(),
                Value<double> rating5based = const Value.absent(),
                Value<String> containerExtension = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VodStreamsCompanion(
                streamId: streamId,
                name: name,
                streamIcon: streamIcon,
                categoryId: categoryId,
                rating: rating,
                rating5based: rating5based,
                containerExtension: containerExtension,
                playlistId: playlistId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String streamId,
                required String name,
                required String streamIcon,
                required String categoryId,
                required String rating,
                required double rating5based,
                required String containerExtension,
                required String playlistId,
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VodStreamsCompanion.insert(
                streamId: streamId,
                name: name,
                streamIcon: streamIcon,
                categoryId: categoryId,
                rating: rating,
                rating5based: rating5based,
                containerExtension: containerExtension,
                playlistId: playlistId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VodStreamsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VodStreamsTable,
      VodStreamsData,
      $$VodStreamsTableFilterComposer,
      $$VodStreamsTableOrderingComposer,
      $$VodStreamsTableAnnotationComposer,
      $$VodStreamsTableCreateCompanionBuilder,
      $$VodStreamsTableUpdateCompanionBuilder,
      (
        VodStreamsData,
        BaseReferences<_$AppDatabase, $VodStreamsTable, VodStreamsData>,
      ),
      VodStreamsData,
      PrefetchHooks Function()
    >;
typedef $$SeriesStreamsTableCreateCompanionBuilder =
    SeriesStreamsCompanion Function({
      required String seriesId,
      required String name,
      Value<String?> cover,
      Value<String?> plot,
      Value<String?> cast,
      Value<String?> director,
      Value<String?> genre,
      Value<String?> releaseDate,
      Value<String?> rating,
      Value<double?> rating5based,
      Value<String?> youtubeTrailer,
      Value<String?> episodeRunTime,
      Value<String?> categoryId,
      required String playlistId,
      Value<DateTime> createdAt,
      Value<String?> lastModified,
      Value<String?> backdropPath,
      Value<int> rowid,
    });
typedef $$SeriesStreamsTableUpdateCompanionBuilder =
    SeriesStreamsCompanion Function({
      Value<String> seriesId,
      Value<String> name,
      Value<String?> cover,
      Value<String?> plot,
      Value<String?> cast,
      Value<String?> director,
      Value<String?> genre,
      Value<String?> releaseDate,
      Value<String?> rating,
      Value<double?> rating5based,
      Value<String?> youtubeTrailer,
      Value<String?> episodeRunTime,
      Value<String?> categoryId,
      Value<String> playlistId,
      Value<DateTime> createdAt,
      Value<String?> lastModified,
      Value<String?> backdropPath,
      Value<int> rowid,
    });

class $$SeriesStreamsTableFilterComposer
    extends Composer<_$AppDatabase, $SeriesStreamsTable> {
  $$SeriesStreamsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cover => $composableBuilder(
    column: $table.cover,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plot => $composableBuilder(
    column: $table.plot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cast => $composableBuilder(
    column: $table.cast,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get director => $composableBuilder(
    column: $table.director,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get releaseDate => $composableBuilder(
    column: $table.releaseDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rating5based => $composableBuilder(
    column: $table.rating5based,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get youtubeTrailer => $composableBuilder(
    column: $table.youtubeTrailer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get episodeRunTime => $composableBuilder(
    column: $table.episodeRunTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeriesStreamsTableOrderingComposer
    extends Composer<_$AppDatabase, $SeriesStreamsTable> {
  $$SeriesStreamsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cover => $composableBuilder(
    column: $table.cover,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plot => $composableBuilder(
    column: $table.plot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cast => $composableBuilder(
    column: $table.cast,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get director => $composableBuilder(
    column: $table.director,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get releaseDate => $composableBuilder(
    column: $table.releaseDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rating5based => $composableBuilder(
    column: $table.rating5based,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get youtubeTrailer => $composableBuilder(
    column: $table.youtubeTrailer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get episodeRunTime => $composableBuilder(
    column: $table.episodeRunTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeriesStreamsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SeriesStreamsTable> {
  $$SeriesStreamsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get cover =>
      $composableBuilder(column: $table.cover, builder: (column) => column);

  GeneratedColumn<String> get plot =>
      $composableBuilder(column: $table.plot, builder: (column) => column);

  GeneratedColumn<String> get cast =>
      $composableBuilder(column: $table.cast, builder: (column) => column);

  GeneratedColumn<String> get director =>
      $composableBuilder(column: $table.director, builder: (column) => column);

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<String> get releaseDate => $composableBuilder(
    column: $table.releaseDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<double> get rating5based => $composableBuilder(
    column: $table.rating5based,
    builder: (column) => column,
  );

  GeneratedColumn<String> get youtubeTrailer => $composableBuilder(
    column: $table.youtubeTrailer,
    builder: (column) => column,
  );

  GeneratedColumn<String> get episodeRunTime => $composableBuilder(
    column: $table.episodeRunTime,
    builder: (column) => column,
  );

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => column,
  );

  GeneratedColumn<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => column,
  );
}

class $$SeriesStreamsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SeriesStreamsTable,
          SeriesStreamsData,
          $$SeriesStreamsTableFilterComposer,
          $$SeriesStreamsTableOrderingComposer,
          $$SeriesStreamsTableAnnotationComposer,
          $$SeriesStreamsTableCreateCompanionBuilder,
          $$SeriesStreamsTableUpdateCompanionBuilder,
          (
            SeriesStreamsData,
            BaseReferences<
              _$AppDatabase,
              $SeriesStreamsTable,
              SeriesStreamsData
            >,
          ),
          SeriesStreamsData,
          PrefetchHooks Function()
        > {
  $$SeriesStreamsTableTableManager(_$AppDatabase db, $SeriesStreamsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeriesStreamsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeriesStreamsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeriesStreamsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> seriesId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> cover = const Value.absent(),
                Value<String?> plot = const Value.absent(),
                Value<String?> cast = const Value.absent(),
                Value<String?> director = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<String?> releaseDate = const Value.absent(),
                Value<String?> rating = const Value.absent(),
                Value<double?> rating5based = const Value.absent(),
                Value<String?> youtubeTrailer = const Value.absent(),
                Value<String?> episodeRunTime = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> lastModified = const Value.absent(),
                Value<String?> backdropPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SeriesStreamsCompanion(
                seriesId: seriesId,
                name: name,
                cover: cover,
                plot: plot,
                cast: cast,
                director: director,
                genre: genre,
                releaseDate: releaseDate,
                rating: rating,
                rating5based: rating5based,
                youtubeTrailer: youtubeTrailer,
                episodeRunTime: episodeRunTime,
                categoryId: categoryId,
                playlistId: playlistId,
                createdAt: createdAt,
                lastModified: lastModified,
                backdropPath: backdropPath,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String seriesId,
                required String name,
                Value<String?> cover = const Value.absent(),
                Value<String?> plot = const Value.absent(),
                Value<String?> cast = const Value.absent(),
                Value<String?> director = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<String?> releaseDate = const Value.absent(),
                Value<String?> rating = const Value.absent(),
                Value<double?> rating5based = const Value.absent(),
                Value<String?> youtubeTrailer = const Value.absent(),
                Value<String?> episodeRunTime = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                required String playlistId,
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> lastModified = const Value.absent(),
                Value<String?> backdropPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SeriesStreamsCompanion.insert(
                seriesId: seriesId,
                name: name,
                cover: cover,
                plot: plot,
                cast: cast,
                director: director,
                genre: genre,
                releaseDate: releaseDate,
                rating: rating,
                rating5based: rating5based,
                youtubeTrailer: youtubeTrailer,
                episodeRunTime: episodeRunTime,
                categoryId: categoryId,
                playlistId: playlistId,
                createdAt: createdAt,
                lastModified: lastModified,
                backdropPath: backdropPath,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeriesStreamsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SeriesStreamsTable,
      SeriesStreamsData,
      $$SeriesStreamsTableFilterComposer,
      $$SeriesStreamsTableOrderingComposer,
      $$SeriesStreamsTableAnnotationComposer,
      $$SeriesStreamsTableCreateCompanionBuilder,
      $$SeriesStreamsTableUpdateCompanionBuilder,
      (
        SeriesStreamsData,
        BaseReferences<_$AppDatabase, $SeriesStreamsTable, SeriesStreamsData>,
      ),
      SeriesStreamsData,
      PrefetchHooks Function()
    >;
typedef $$SeriesInfosTableCreateCompanionBuilder =
    SeriesInfosCompanion Function({
      Value<int> id,
      required String seriesId,
      required String name,
      Value<String?> cover,
      Value<String?> plot,
      Value<String?> cast,
      Value<String?> director,
      Value<String?> genre,
      Value<String?> releaseDate,
      Value<String?> lastModified,
      Value<String?> rating,
      Value<int?> rating5based,
      Value<String?> backdropPath,
      Value<String?> youtubeTrailer,
      Value<String?> episodeRunTime,
      Value<String?> categoryId,
      required String playlistId,
    });
typedef $$SeriesInfosTableUpdateCompanionBuilder =
    SeriesInfosCompanion Function({
      Value<int> id,
      Value<String> seriesId,
      Value<String> name,
      Value<String?> cover,
      Value<String?> plot,
      Value<String?> cast,
      Value<String?> director,
      Value<String?> genre,
      Value<String?> releaseDate,
      Value<String?> lastModified,
      Value<String?> rating,
      Value<int?> rating5based,
      Value<String?> backdropPath,
      Value<String?> youtubeTrailer,
      Value<String?> episodeRunTime,
      Value<String?> categoryId,
      Value<String> playlistId,
    });

class $$SeriesInfosTableFilterComposer
    extends Composer<_$AppDatabase, $SeriesInfosTable> {
  $$SeriesInfosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cover => $composableBuilder(
    column: $table.cover,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plot => $composableBuilder(
    column: $table.plot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cast => $composableBuilder(
    column: $table.cast,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get director => $composableBuilder(
    column: $table.director,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get releaseDate => $composableBuilder(
    column: $table.releaseDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rating5based => $composableBuilder(
    column: $table.rating5based,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get youtubeTrailer => $composableBuilder(
    column: $table.youtubeTrailer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get episodeRunTime => $composableBuilder(
    column: $table.episodeRunTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeriesInfosTableOrderingComposer
    extends Composer<_$AppDatabase, $SeriesInfosTable> {
  $$SeriesInfosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cover => $composableBuilder(
    column: $table.cover,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plot => $composableBuilder(
    column: $table.plot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cast => $composableBuilder(
    column: $table.cast,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get director => $composableBuilder(
    column: $table.director,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get releaseDate => $composableBuilder(
    column: $table.releaseDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rating5based => $composableBuilder(
    column: $table.rating5based,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get youtubeTrailer => $composableBuilder(
    column: $table.youtubeTrailer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get episodeRunTime => $composableBuilder(
    column: $table.episodeRunTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeriesInfosTableAnnotationComposer
    extends Composer<_$AppDatabase, $SeriesInfosTable> {
  $$SeriesInfosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get cover =>
      $composableBuilder(column: $table.cover, builder: (column) => column);

  GeneratedColumn<String> get plot =>
      $composableBuilder(column: $table.plot, builder: (column) => column);

  GeneratedColumn<String> get cast =>
      $composableBuilder(column: $table.cast, builder: (column) => column);

  GeneratedColumn<String> get director =>
      $composableBuilder(column: $table.director, builder: (column) => column);

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<String> get releaseDate => $composableBuilder(
    column: $table.releaseDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<int> get rating5based => $composableBuilder(
    column: $table.rating5based,
    builder: (column) => column,
  );

  GeneratedColumn<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get youtubeTrailer => $composableBuilder(
    column: $table.youtubeTrailer,
    builder: (column) => column,
  );

  GeneratedColumn<String> get episodeRunTime => $composableBuilder(
    column: $table.episodeRunTime,
    builder: (column) => column,
  );

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );
}

class $$SeriesInfosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SeriesInfosTable,
          SeriesInfosData,
          $$SeriesInfosTableFilterComposer,
          $$SeriesInfosTableOrderingComposer,
          $$SeriesInfosTableAnnotationComposer,
          $$SeriesInfosTableCreateCompanionBuilder,
          $$SeriesInfosTableUpdateCompanionBuilder,
          (
            SeriesInfosData,
            BaseReferences<_$AppDatabase, $SeriesInfosTable, SeriesInfosData>,
          ),
          SeriesInfosData,
          PrefetchHooks Function()
        > {
  $$SeriesInfosTableTableManager(_$AppDatabase db, $SeriesInfosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeriesInfosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeriesInfosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeriesInfosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> seriesId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> cover = const Value.absent(),
                Value<String?> plot = const Value.absent(),
                Value<String?> cast = const Value.absent(),
                Value<String?> director = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<String?> releaseDate = const Value.absent(),
                Value<String?> lastModified = const Value.absent(),
                Value<String?> rating = const Value.absent(),
                Value<int?> rating5based = const Value.absent(),
                Value<String?> backdropPath = const Value.absent(),
                Value<String?> youtubeTrailer = const Value.absent(),
                Value<String?> episodeRunTime = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
              }) => SeriesInfosCompanion(
                id: id,
                seriesId: seriesId,
                name: name,
                cover: cover,
                plot: plot,
                cast: cast,
                director: director,
                genre: genre,
                releaseDate: releaseDate,
                lastModified: lastModified,
                rating: rating,
                rating5based: rating5based,
                backdropPath: backdropPath,
                youtubeTrailer: youtubeTrailer,
                episodeRunTime: episodeRunTime,
                categoryId: categoryId,
                playlistId: playlistId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String seriesId,
                required String name,
                Value<String?> cover = const Value.absent(),
                Value<String?> plot = const Value.absent(),
                Value<String?> cast = const Value.absent(),
                Value<String?> director = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<String?> releaseDate = const Value.absent(),
                Value<String?> lastModified = const Value.absent(),
                Value<String?> rating = const Value.absent(),
                Value<int?> rating5based = const Value.absent(),
                Value<String?> backdropPath = const Value.absent(),
                Value<String?> youtubeTrailer = const Value.absent(),
                Value<String?> episodeRunTime = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                required String playlistId,
              }) => SeriesInfosCompanion.insert(
                id: id,
                seriesId: seriesId,
                name: name,
                cover: cover,
                plot: plot,
                cast: cast,
                director: director,
                genre: genre,
                releaseDate: releaseDate,
                lastModified: lastModified,
                rating: rating,
                rating5based: rating5based,
                backdropPath: backdropPath,
                youtubeTrailer: youtubeTrailer,
                episodeRunTime: episodeRunTime,
                categoryId: categoryId,
                playlistId: playlistId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeriesInfosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SeriesInfosTable,
      SeriesInfosData,
      $$SeriesInfosTableFilterComposer,
      $$SeriesInfosTableOrderingComposer,
      $$SeriesInfosTableAnnotationComposer,
      $$SeriesInfosTableCreateCompanionBuilder,
      $$SeriesInfosTableUpdateCompanionBuilder,
      (
        SeriesInfosData,
        BaseReferences<_$AppDatabase, $SeriesInfosTable, SeriesInfosData>,
      ),
      SeriesInfosData,
      PrefetchHooks Function()
    >;
typedef $$SeasonsTableCreateCompanionBuilder =
    SeasonsCompanion Function({
      Value<int> id,
      required String seriesId,
      Value<String?> airDate,
      Value<int?> episodeCount,
      required int seasonId,
      required String name,
      Value<String?> overview,
      required int seasonNumber,
      Value<int?> voteAverage,
      Value<String?> cover,
      Value<String?> coverBig,
      required String playlistId,
    });
typedef $$SeasonsTableUpdateCompanionBuilder =
    SeasonsCompanion Function({
      Value<int> id,
      Value<String> seriesId,
      Value<String?> airDate,
      Value<int?> episodeCount,
      Value<int> seasonId,
      Value<String> name,
      Value<String?> overview,
      Value<int> seasonNumber,
      Value<int?> voteAverage,
      Value<String?> cover,
      Value<String?> coverBig,
      Value<String> playlistId,
    });

class $$SeasonsTableFilterComposer
    extends Composer<_$AppDatabase, $SeasonsTable> {
  $$SeasonsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get airDate => $composableBuilder(
    column: $table.airDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episodeCount => $composableBuilder(
    column: $table.episodeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seasonId => $composableBuilder(
    column: $table.seasonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get overview => $composableBuilder(
    column: $table.overview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get voteAverage => $composableBuilder(
    column: $table.voteAverage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cover => $composableBuilder(
    column: $table.cover,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverBig => $composableBuilder(
    column: $table.coverBig,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeasonsTableOrderingComposer
    extends Composer<_$AppDatabase, $SeasonsTable> {
  $$SeasonsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get airDate => $composableBuilder(
    column: $table.airDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episodeCount => $composableBuilder(
    column: $table.episodeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seasonId => $composableBuilder(
    column: $table.seasonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get overview => $composableBuilder(
    column: $table.overview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get voteAverage => $composableBuilder(
    column: $table.voteAverage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cover => $composableBuilder(
    column: $table.cover,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverBig => $composableBuilder(
    column: $table.coverBig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeasonsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SeasonsTable> {
  $$SeasonsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<String> get airDate =>
      $composableBuilder(column: $table.airDate, builder: (column) => column);

  GeneratedColumn<int> get episodeCount => $composableBuilder(
    column: $table.episodeCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get seasonId =>
      $composableBuilder(column: $table.seasonId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get overview =>
      $composableBuilder(column: $table.overview, builder: (column) => column);

  GeneratedColumn<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get voteAverage => $composableBuilder(
    column: $table.voteAverage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cover =>
      $composableBuilder(column: $table.cover, builder: (column) => column);

  GeneratedColumn<String> get coverBig =>
      $composableBuilder(column: $table.coverBig, builder: (column) => column);

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );
}

class $$SeasonsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SeasonsTable,
          SeasonsData,
          $$SeasonsTableFilterComposer,
          $$SeasonsTableOrderingComposer,
          $$SeasonsTableAnnotationComposer,
          $$SeasonsTableCreateCompanionBuilder,
          $$SeasonsTableUpdateCompanionBuilder,
          (
            SeasonsData,
            BaseReferences<_$AppDatabase, $SeasonsTable, SeasonsData>,
          ),
          SeasonsData,
          PrefetchHooks Function()
        > {
  $$SeasonsTableTableManager(_$AppDatabase db, $SeasonsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeasonsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeasonsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeasonsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> seriesId = const Value.absent(),
                Value<String?> airDate = const Value.absent(),
                Value<int?> episodeCount = const Value.absent(),
                Value<int> seasonId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> overview = const Value.absent(),
                Value<int> seasonNumber = const Value.absent(),
                Value<int?> voteAverage = const Value.absent(),
                Value<String?> cover = const Value.absent(),
                Value<String?> coverBig = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
              }) => SeasonsCompanion(
                id: id,
                seriesId: seriesId,
                airDate: airDate,
                episodeCount: episodeCount,
                seasonId: seasonId,
                name: name,
                overview: overview,
                seasonNumber: seasonNumber,
                voteAverage: voteAverage,
                cover: cover,
                coverBig: coverBig,
                playlistId: playlistId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String seriesId,
                Value<String?> airDate = const Value.absent(),
                Value<int?> episodeCount = const Value.absent(),
                required int seasonId,
                required String name,
                Value<String?> overview = const Value.absent(),
                required int seasonNumber,
                Value<int?> voteAverage = const Value.absent(),
                Value<String?> cover = const Value.absent(),
                Value<String?> coverBig = const Value.absent(),
                required String playlistId,
              }) => SeasonsCompanion.insert(
                id: id,
                seriesId: seriesId,
                airDate: airDate,
                episodeCount: episodeCount,
                seasonId: seasonId,
                name: name,
                overview: overview,
                seasonNumber: seasonNumber,
                voteAverage: voteAverage,
                cover: cover,
                coverBig: coverBig,
                playlistId: playlistId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeasonsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SeasonsTable,
      SeasonsData,
      $$SeasonsTableFilterComposer,
      $$SeasonsTableOrderingComposer,
      $$SeasonsTableAnnotationComposer,
      $$SeasonsTableCreateCompanionBuilder,
      $$SeasonsTableUpdateCompanionBuilder,
      (SeasonsData, BaseReferences<_$AppDatabase, $SeasonsTable, SeasonsData>),
      SeasonsData,
      PrefetchHooks Function()
    >;
typedef $$EpisodesTableCreateCompanionBuilder =
    EpisodesCompanion Function({
      Value<int> id,
      required String seriesId,
      required String episodeId,
      required int episodeNum,
      required String title,
      Value<String?> containerExtension,
      required int season,
      Value<String?> customSid,
      Value<String?> added,
      Value<String?> directSource,
      required String playlistId,
      Value<int?> tmdbId,
      Value<String?> releasedate,
      Value<String?> plot,
      Value<int?> durationSecs,
      Value<String?> duration,
      Value<String?> movieImage,
      Value<int?> bitrate,
      Value<double?> rating,
    });
typedef $$EpisodesTableUpdateCompanionBuilder =
    EpisodesCompanion Function({
      Value<int> id,
      Value<String> seriesId,
      Value<String> episodeId,
      Value<int> episodeNum,
      Value<String> title,
      Value<String?> containerExtension,
      Value<int> season,
      Value<String?> customSid,
      Value<String?> added,
      Value<String?> directSource,
      Value<String> playlistId,
      Value<int?> tmdbId,
      Value<String?> releasedate,
      Value<String?> plot,
      Value<int?> durationSecs,
      Value<String?> duration,
      Value<String?> movieImage,
      Value<int?> bitrate,
      Value<double?> rating,
    });

class $$EpisodesTableFilterComposer
    extends Composer<_$AppDatabase, $EpisodesTable> {
  $$EpisodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get episodeId => $composableBuilder(
    column: $table.episodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episodeNum => $composableBuilder(
    column: $table.episodeNum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get containerExtension => $composableBuilder(
    column: $table.containerExtension,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customSid => $composableBuilder(
    column: $table.customSid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get added => $composableBuilder(
    column: $table.added,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get directSource => $composableBuilder(
    column: $table.directSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tmdbId => $composableBuilder(
    column: $table.tmdbId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get releasedate => $composableBuilder(
    column: $table.releasedate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plot => $composableBuilder(
    column: $table.plot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSecs => $composableBuilder(
    column: $table.durationSecs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get movieImage => $composableBuilder(
    column: $table.movieImage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bitrate => $composableBuilder(
    column: $table.bitrate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EpisodesTableOrderingComposer
    extends Composer<_$AppDatabase, $EpisodesTable> {
  $$EpisodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get episodeId => $composableBuilder(
    column: $table.episodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episodeNum => $composableBuilder(
    column: $table.episodeNum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get containerExtension => $composableBuilder(
    column: $table.containerExtension,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customSid => $composableBuilder(
    column: $table.customSid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get added => $composableBuilder(
    column: $table.added,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get directSource => $composableBuilder(
    column: $table.directSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tmdbId => $composableBuilder(
    column: $table.tmdbId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get releasedate => $composableBuilder(
    column: $table.releasedate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plot => $composableBuilder(
    column: $table.plot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSecs => $composableBuilder(
    column: $table.durationSecs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get movieImage => $composableBuilder(
    column: $table.movieImage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bitrate => $composableBuilder(
    column: $table.bitrate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EpisodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EpisodesTable> {
  $$EpisodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<String> get episodeId =>
      $composableBuilder(column: $table.episodeId, builder: (column) => column);

  GeneratedColumn<int> get episodeNum => $composableBuilder(
    column: $table.episodeNum,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get containerExtension => $composableBuilder(
    column: $table.containerExtension,
    builder: (column) => column,
  );

  GeneratedColumn<int> get season =>
      $composableBuilder(column: $table.season, builder: (column) => column);

  GeneratedColumn<String> get customSid =>
      $composableBuilder(column: $table.customSid, builder: (column) => column);

  GeneratedColumn<String> get added =>
      $composableBuilder(column: $table.added, builder: (column) => column);

  GeneratedColumn<String> get directSource => $composableBuilder(
    column: $table.directSource,
    builder: (column) => column,
  );

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tmdbId =>
      $composableBuilder(column: $table.tmdbId, builder: (column) => column);

  GeneratedColumn<String> get releasedate => $composableBuilder(
    column: $table.releasedate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get plot =>
      $composableBuilder(column: $table.plot, builder: (column) => column);

  GeneratedColumn<int> get durationSecs => $composableBuilder(
    column: $table.durationSecs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get duration =>
      $composableBuilder(column: $table.duration, builder: (column) => column);

  GeneratedColumn<String> get movieImage => $composableBuilder(
    column: $table.movieImage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bitrate =>
      $composableBuilder(column: $table.bitrate, builder: (column) => column);

  GeneratedColumn<double> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);
}

class $$EpisodesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EpisodesTable,
          EpisodesData,
          $$EpisodesTableFilterComposer,
          $$EpisodesTableOrderingComposer,
          $$EpisodesTableAnnotationComposer,
          $$EpisodesTableCreateCompanionBuilder,
          $$EpisodesTableUpdateCompanionBuilder,
          (
            EpisodesData,
            BaseReferences<_$AppDatabase, $EpisodesTable, EpisodesData>,
          ),
          EpisodesData,
          PrefetchHooks Function()
        > {
  $$EpisodesTableTableManager(_$AppDatabase db, $EpisodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EpisodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EpisodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EpisodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> seriesId = const Value.absent(),
                Value<String> episodeId = const Value.absent(),
                Value<int> episodeNum = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> containerExtension = const Value.absent(),
                Value<int> season = const Value.absent(),
                Value<String?> customSid = const Value.absent(),
                Value<String?> added = const Value.absent(),
                Value<String?> directSource = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
                Value<int?> tmdbId = const Value.absent(),
                Value<String?> releasedate = const Value.absent(),
                Value<String?> plot = const Value.absent(),
                Value<int?> durationSecs = const Value.absent(),
                Value<String?> duration = const Value.absent(),
                Value<String?> movieImage = const Value.absent(),
                Value<int?> bitrate = const Value.absent(),
                Value<double?> rating = const Value.absent(),
              }) => EpisodesCompanion(
                id: id,
                seriesId: seriesId,
                episodeId: episodeId,
                episodeNum: episodeNum,
                title: title,
                containerExtension: containerExtension,
                season: season,
                customSid: customSid,
                added: added,
                directSource: directSource,
                playlistId: playlistId,
                tmdbId: tmdbId,
                releasedate: releasedate,
                plot: plot,
                durationSecs: durationSecs,
                duration: duration,
                movieImage: movieImage,
                bitrate: bitrate,
                rating: rating,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String seriesId,
                required String episodeId,
                required int episodeNum,
                required String title,
                Value<String?> containerExtension = const Value.absent(),
                required int season,
                Value<String?> customSid = const Value.absent(),
                Value<String?> added = const Value.absent(),
                Value<String?> directSource = const Value.absent(),
                required String playlistId,
                Value<int?> tmdbId = const Value.absent(),
                Value<String?> releasedate = const Value.absent(),
                Value<String?> plot = const Value.absent(),
                Value<int?> durationSecs = const Value.absent(),
                Value<String?> duration = const Value.absent(),
                Value<String?> movieImage = const Value.absent(),
                Value<int?> bitrate = const Value.absent(),
                Value<double?> rating = const Value.absent(),
              }) => EpisodesCompanion.insert(
                id: id,
                seriesId: seriesId,
                episodeId: episodeId,
                episodeNum: episodeNum,
                title: title,
                containerExtension: containerExtension,
                season: season,
                customSid: customSid,
                added: added,
                directSource: directSource,
                playlistId: playlistId,
                tmdbId: tmdbId,
                releasedate: releasedate,
                plot: plot,
                durationSecs: durationSecs,
                duration: duration,
                movieImage: movieImage,
                bitrate: bitrate,
                rating: rating,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EpisodesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EpisodesTable,
      EpisodesData,
      $$EpisodesTableFilterComposer,
      $$EpisodesTableOrderingComposer,
      $$EpisodesTableAnnotationComposer,
      $$EpisodesTableCreateCompanionBuilder,
      $$EpisodesTableUpdateCompanionBuilder,
      (
        EpisodesData,
        BaseReferences<_$AppDatabase, $EpisodesTable, EpisodesData>,
      ),
      EpisodesData,
      PrefetchHooks Function()
    >;
typedef $$WatchHistoriesTableCreateCompanionBuilder =
    WatchHistoriesCompanion Function({
      required String playlistId,
      required ContentType contentType,
      required String streamId,
      Value<String?> seriesId,
      Value<int?> watchDuration,
      Value<int?> totalDuration,
      required DateTime lastWatched,
      Value<String?> imagePath,
      required String title,
      Value<int> rowid,
    });
typedef $$WatchHistoriesTableUpdateCompanionBuilder =
    WatchHistoriesCompanion Function({
      Value<String> playlistId,
      Value<ContentType> contentType,
      Value<String> streamId,
      Value<String?> seriesId,
      Value<int?> watchDuration,
      Value<int?> totalDuration,
      Value<DateTime> lastWatched,
      Value<String?> imagePath,
      Value<String> title,
      Value<int> rowid,
    });

class $$WatchHistoriesTableFilterComposer
    extends Composer<_$AppDatabase, $WatchHistoriesTable> {
  $$WatchHistoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ContentType, ContentType, int>
  get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get watchDuration => $composableBuilder(
    column: $table.watchDuration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalDuration => $composableBuilder(
    column: $table.totalDuration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastWatched => $composableBuilder(
    column: $table.lastWatched,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WatchHistoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchHistoriesTable> {
  $$WatchHistoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get watchDuration => $composableBuilder(
    column: $table.watchDuration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalDuration => $composableBuilder(
    column: $table.totalDuration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastWatched => $composableBuilder(
    column: $table.lastWatched,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WatchHistoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchHistoriesTable> {
  $$WatchHistoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<ContentType, int> get contentType =>
      $composableBuilder(
        column: $table.contentType,
        builder: (column) => column,
      );

  GeneratedColumn<String> get streamId =>
      $composableBuilder(column: $table.streamId, builder: (column) => column);

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<int> get watchDuration => $composableBuilder(
    column: $table.watchDuration,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalDuration => $composableBuilder(
    column: $table.totalDuration,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastWatched => $composableBuilder(
    column: $table.lastWatched,
    builder: (column) => column,
  );

  GeneratedColumn<String> get imagePath =>
      $composableBuilder(column: $table.imagePath, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);
}

class $$WatchHistoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WatchHistoriesTable,
          WatchHistoriesData,
          $$WatchHistoriesTableFilterComposer,
          $$WatchHistoriesTableOrderingComposer,
          $$WatchHistoriesTableAnnotationComposer,
          $$WatchHistoriesTableCreateCompanionBuilder,
          $$WatchHistoriesTableUpdateCompanionBuilder,
          (
            WatchHistoriesData,
            BaseReferences<
              _$AppDatabase,
              $WatchHistoriesTable,
              WatchHistoriesData
            >,
          ),
          WatchHistoriesData,
          PrefetchHooks Function()
        > {
  $$WatchHistoriesTableTableManager(
    _$AppDatabase db,
    $WatchHistoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchHistoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchHistoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchHistoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> playlistId = const Value.absent(),
                Value<ContentType> contentType = const Value.absent(),
                Value<String> streamId = const Value.absent(),
                Value<String?> seriesId = const Value.absent(),
                Value<int?> watchDuration = const Value.absent(),
                Value<int?> totalDuration = const Value.absent(),
                Value<DateTime> lastWatched = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WatchHistoriesCompanion(
                playlistId: playlistId,
                contentType: contentType,
                streamId: streamId,
                seriesId: seriesId,
                watchDuration: watchDuration,
                totalDuration: totalDuration,
                lastWatched: lastWatched,
                imagePath: imagePath,
                title: title,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String playlistId,
                required ContentType contentType,
                required String streamId,
                Value<String?> seriesId = const Value.absent(),
                Value<int?> watchDuration = const Value.absent(),
                Value<int?> totalDuration = const Value.absent(),
                required DateTime lastWatched,
                Value<String?> imagePath = const Value.absent(),
                required String title,
                Value<int> rowid = const Value.absent(),
              }) => WatchHistoriesCompanion.insert(
                playlistId: playlistId,
                contentType: contentType,
                streamId: streamId,
                seriesId: seriesId,
                watchDuration: watchDuration,
                totalDuration: totalDuration,
                lastWatched: lastWatched,
                imagePath: imagePath,
                title: title,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WatchHistoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WatchHistoriesTable,
      WatchHistoriesData,
      $$WatchHistoriesTableFilterComposer,
      $$WatchHistoriesTableOrderingComposer,
      $$WatchHistoriesTableAnnotationComposer,
      $$WatchHistoriesTableCreateCompanionBuilder,
      $$WatchHistoriesTableUpdateCompanionBuilder,
      (
        WatchHistoriesData,
        BaseReferences<_$AppDatabase, $WatchHistoriesTable, WatchHistoriesData>,
      ),
      WatchHistoriesData,
      PrefetchHooks Function()
    >;
typedef $$M3uItemsTableCreateCompanionBuilder =
    M3uItemsCompanion Function({
      required String id,
      required String playlistId,
      required String url,
      Value<String?> name,
      Value<String?> tvgId,
      Value<String?> tvgName,
      Value<String?> tvgLogo,
      Value<String?> tvgUrl,
      Value<String?> tvgRec,
      Value<String?> tvgShift,
      Value<String?> groupTitle,
      Value<String?> groupName,
      Value<String?> userAgent,
      Value<String?> referrer,
      Value<String?> categoryId,
      required int contentType,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$M3uItemsTableUpdateCompanionBuilder =
    M3uItemsCompanion Function({
      Value<String> id,
      Value<String> playlistId,
      Value<String> url,
      Value<String?> name,
      Value<String?> tvgId,
      Value<String?> tvgName,
      Value<String?> tvgLogo,
      Value<String?> tvgUrl,
      Value<String?> tvgRec,
      Value<String?> tvgShift,
      Value<String?> groupTitle,
      Value<String?> groupName,
      Value<String?> userAgent,
      Value<String?> referrer,
      Value<String?> categoryId,
      Value<int> contentType,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$M3uItemsTableFilterComposer
    extends Composer<_$AppDatabase, $M3uItemsTable> {
  $$M3uItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tvgId => $composableBuilder(
    column: $table.tvgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tvgName => $composableBuilder(
    column: $table.tvgName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tvgLogo => $composableBuilder(
    column: $table.tvgLogo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tvgUrl => $composableBuilder(
    column: $table.tvgUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tvgRec => $composableBuilder(
    column: $table.tvgRec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tvgShift => $composableBuilder(
    column: $table.tvgShift,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupTitle => $composableBuilder(
    column: $table.groupTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userAgent => $composableBuilder(
    column: $table.userAgent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referrer => $composableBuilder(
    column: $table.referrer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$M3uItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $M3uItemsTable> {
  $$M3uItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tvgId => $composableBuilder(
    column: $table.tvgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tvgName => $composableBuilder(
    column: $table.tvgName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tvgLogo => $composableBuilder(
    column: $table.tvgLogo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tvgUrl => $composableBuilder(
    column: $table.tvgUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tvgRec => $composableBuilder(
    column: $table.tvgRec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tvgShift => $composableBuilder(
    column: $table.tvgShift,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupTitle => $composableBuilder(
    column: $table.groupTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userAgent => $composableBuilder(
    column: $table.userAgent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referrer => $composableBuilder(
    column: $table.referrer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$M3uItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $M3uItemsTable> {
  $$M3uItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get tvgId =>
      $composableBuilder(column: $table.tvgId, builder: (column) => column);

  GeneratedColumn<String> get tvgName =>
      $composableBuilder(column: $table.tvgName, builder: (column) => column);

  GeneratedColumn<String> get tvgLogo =>
      $composableBuilder(column: $table.tvgLogo, builder: (column) => column);

  GeneratedColumn<String> get tvgUrl =>
      $composableBuilder(column: $table.tvgUrl, builder: (column) => column);

  GeneratedColumn<String> get tvgRec =>
      $composableBuilder(column: $table.tvgRec, builder: (column) => column);

  GeneratedColumn<String> get tvgShift =>
      $composableBuilder(column: $table.tvgShift, builder: (column) => column);

  GeneratedColumn<String> get groupTitle => $composableBuilder(
    column: $table.groupTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupName =>
      $composableBuilder(column: $table.groupName, builder: (column) => column);

  GeneratedColumn<String> get userAgent =>
      $composableBuilder(column: $table.userAgent, builder: (column) => column);

  GeneratedColumn<String> get referrer =>
      $composableBuilder(column: $table.referrer, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$M3uItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $M3uItemsTable,
          M3uItemData,
          $$M3uItemsTableFilterComposer,
          $$M3uItemsTableOrderingComposer,
          $$M3uItemsTableAnnotationComposer,
          $$M3uItemsTableCreateCompanionBuilder,
          $$M3uItemsTableUpdateCompanionBuilder,
          (
            M3uItemData,
            BaseReferences<_$AppDatabase, $M3uItemsTable, M3uItemData>,
          ),
          M3uItemData,
          PrefetchHooks Function()
        > {
  $$M3uItemsTableTableManager(_$AppDatabase db, $M3uItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$M3uItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$M3uItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$M3uItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String?> tvgId = const Value.absent(),
                Value<String?> tvgName = const Value.absent(),
                Value<String?> tvgLogo = const Value.absent(),
                Value<String?> tvgUrl = const Value.absent(),
                Value<String?> tvgRec = const Value.absent(),
                Value<String?> tvgShift = const Value.absent(),
                Value<String?> groupTitle = const Value.absent(),
                Value<String?> groupName = const Value.absent(),
                Value<String?> userAgent = const Value.absent(),
                Value<String?> referrer = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<int> contentType = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => M3uItemsCompanion(
                id: id,
                playlistId: playlistId,
                url: url,
                name: name,
                tvgId: tvgId,
                tvgName: tvgName,
                tvgLogo: tvgLogo,
                tvgUrl: tvgUrl,
                tvgRec: tvgRec,
                tvgShift: tvgShift,
                groupTitle: groupTitle,
                groupName: groupName,
                userAgent: userAgent,
                referrer: referrer,
                categoryId: categoryId,
                contentType: contentType,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String playlistId,
                required String url,
                Value<String?> name = const Value.absent(),
                Value<String?> tvgId = const Value.absent(),
                Value<String?> tvgName = const Value.absent(),
                Value<String?> tvgLogo = const Value.absent(),
                Value<String?> tvgUrl = const Value.absent(),
                Value<String?> tvgRec = const Value.absent(),
                Value<String?> tvgShift = const Value.absent(),
                Value<String?> groupTitle = const Value.absent(),
                Value<String?> groupName = const Value.absent(),
                Value<String?> userAgent = const Value.absent(),
                Value<String?> referrer = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                required int contentType,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => M3uItemsCompanion.insert(
                id: id,
                playlistId: playlistId,
                url: url,
                name: name,
                tvgId: tvgId,
                tvgName: tvgName,
                tvgLogo: tvgLogo,
                tvgUrl: tvgUrl,
                tvgRec: tvgRec,
                tvgShift: tvgShift,
                groupTitle: groupTitle,
                groupName: groupName,
                userAgent: userAgent,
                referrer: referrer,
                categoryId: categoryId,
                contentType: contentType,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$M3uItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $M3uItemsTable,
      M3uItemData,
      $$M3uItemsTableFilterComposer,
      $$M3uItemsTableOrderingComposer,
      $$M3uItemsTableAnnotationComposer,
      $$M3uItemsTableCreateCompanionBuilder,
      $$M3uItemsTableUpdateCompanionBuilder,
      (M3uItemData, BaseReferences<_$AppDatabase, $M3uItemsTable, M3uItemData>),
      M3uItemData,
      PrefetchHooks Function()
    >;
typedef $$M3uSeriesTableCreateCompanionBuilder =
    M3uSeriesCompanion Function({
      required String playlistId,
      required String seriesId,
      required String name,
      Value<String?> categoryId,
      Value<String?> cover,
      Value<int> rowid,
    });
typedef $$M3uSeriesTableUpdateCompanionBuilder =
    M3uSeriesCompanion Function({
      Value<String> playlistId,
      Value<String> seriesId,
      Value<String> name,
      Value<String?> categoryId,
      Value<String?> cover,
      Value<int> rowid,
    });

class $$M3uSeriesTableFilterComposer
    extends Composer<_$AppDatabase, $M3uSeriesTable> {
  $$M3uSeriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cover => $composableBuilder(
    column: $table.cover,
    builder: (column) => ColumnFilters(column),
  );
}

class $$M3uSeriesTableOrderingComposer
    extends Composer<_$AppDatabase, $M3uSeriesTable> {
  $$M3uSeriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cover => $composableBuilder(
    column: $table.cover,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$M3uSeriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $M3uSeriesTable> {
  $$M3uSeriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cover =>
      $composableBuilder(column: $table.cover, builder: (column) => column);
}

class $$M3uSeriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $M3uSeriesTable,
          M3uSeriesData,
          $$M3uSeriesTableFilterComposer,
          $$M3uSeriesTableOrderingComposer,
          $$M3uSeriesTableAnnotationComposer,
          $$M3uSeriesTableCreateCompanionBuilder,
          $$M3uSeriesTableUpdateCompanionBuilder,
          (
            M3uSeriesData,
            BaseReferences<_$AppDatabase, $M3uSeriesTable, M3uSeriesData>,
          ),
          M3uSeriesData,
          PrefetchHooks Function()
        > {
  $$M3uSeriesTableTableManager(_$AppDatabase db, $M3uSeriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$M3uSeriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$M3uSeriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$M3uSeriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> playlistId = const Value.absent(),
                Value<String> seriesId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> cover = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => M3uSeriesCompanion(
                playlistId: playlistId,
                seriesId: seriesId,
                name: name,
                categoryId: categoryId,
                cover: cover,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String playlistId,
                required String seriesId,
                required String name,
                Value<String?> categoryId = const Value.absent(),
                Value<String?> cover = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => M3uSeriesCompanion.insert(
                playlistId: playlistId,
                seriesId: seriesId,
                name: name,
                categoryId: categoryId,
                cover: cover,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$M3uSeriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $M3uSeriesTable,
      M3uSeriesData,
      $$M3uSeriesTableFilterComposer,
      $$M3uSeriesTableOrderingComposer,
      $$M3uSeriesTableAnnotationComposer,
      $$M3uSeriesTableCreateCompanionBuilder,
      $$M3uSeriesTableUpdateCompanionBuilder,
      (
        M3uSeriesData,
        BaseReferences<_$AppDatabase, $M3uSeriesTable, M3uSeriesData>,
      ),
      M3uSeriesData,
      PrefetchHooks Function()
    >;
typedef $$M3uEpisodesTableCreateCompanionBuilder =
    M3uEpisodesCompanion Function({
      required String playlistId,
      required String seriesId,
      required int seasonNumber,
      required int episodeNumber,
      required String name,
      required String url,
      Value<String?> categoryId,
      Value<String?> cover,
      Value<int> rowid,
    });
typedef $$M3uEpisodesTableUpdateCompanionBuilder =
    M3uEpisodesCompanion Function({
      Value<String> playlistId,
      Value<String> seriesId,
      Value<int> seasonNumber,
      Value<int> episodeNumber,
      Value<String> name,
      Value<String> url,
      Value<String?> categoryId,
      Value<String?> cover,
      Value<int> rowid,
    });

class $$M3uEpisodesTableFilterComposer
    extends Composer<_$AppDatabase, $M3uEpisodesTable> {
  $$M3uEpisodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cover => $composableBuilder(
    column: $table.cover,
    builder: (column) => ColumnFilters(column),
  );
}

class $$M3uEpisodesTableOrderingComposer
    extends Composer<_$AppDatabase, $M3uEpisodesTable> {
  $$M3uEpisodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cover => $composableBuilder(
    column: $table.cover,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$M3uEpisodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $M3uEpisodesTable> {
  $$M3uEpisodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cover =>
      $composableBuilder(column: $table.cover, builder: (column) => column);
}

class $$M3uEpisodesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $M3uEpisodesTable,
          M3uEpisodesData,
          $$M3uEpisodesTableFilterComposer,
          $$M3uEpisodesTableOrderingComposer,
          $$M3uEpisodesTableAnnotationComposer,
          $$M3uEpisodesTableCreateCompanionBuilder,
          $$M3uEpisodesTableUpdateCompanionBuilder,
          (
            M3uEpisodesData,
            BaseReferences<_$AppDatabase, $M3uEpisodesTable, M3uEpisodesData>,
          ),
          M3uEpisodesData,
          PrefetchHooks Function()
        > {
  $$M3uEpisodesTableTableManager(_$AppDatabase db, $M3uEpisodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$M3uEpisodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$M3uEpisodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$M3uEpisodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> playlistId = const Value.absent(),
                Value<String> seriesId = const Value.absent(),
                Value<int> seasonNumber = const Value.absent(),
                Value<int> episodeNumber = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> cover = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => M3uEpisodesCompanion(
                playlistId: playlistId,
                seriesId: seriesId,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                name: name,
                url: url,
                categoryId: categoryId,
                cover: cover,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String playlistId,
                required String seriesId,
                required int seasonNumber,
                required int episodeNumber,
                required String name,
                required String url,
                Value<String?> categoryId = const Value.absent(),
                Value<String?> cover = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => M3uEpisodesCompanion.insert(
                playlistId: playlistId,
                seriesId: seriesId,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                name: name,
                url: url,
                categoryId: categoryId,
                cover: cover,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$M3uEpisodesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $M3uEpisodesTable,
      M3uEpisodesData,
      $$M3uEpisodesTableFilterComposer,
      $$M3uEpisodesTableOrderingComposer,
      $$M3uEpisodesTableAnnotationComposer,
      $$M3uEpisodesTableCreateCompanionBuilder,
      $$M3uEpisodesTableUpdateCompanionBuilder,
      (
        M3uEpisodesData,
        BaseReferences<_$AppDatabase, $M3uEpisodesTable, M3uEpisodesData>,
      ),
      M3uEpisodesData,
      PrefetchHooks Function()
    >;
typedef $$FavoritesTableCreateCompanionBuilder =
    FavoritesCompanion Function({
      required String id,
      required String playlistId,
      required int contentType,
      required String streamId,
      Value<String?> episodeId,
      Value<String?> m3uItemId,
      required String name,
      Value<String?> imagePath,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$FavoritesTableUpdateCompanionBuilder =
    FavoritesCompanion Function({
      Value<String> id,
      Value<String> playlistId,
      Value<int> contentType,
      Value<String> streamId,
      Value<String?> episodeId,
      Value<String?> m3uItemId,
      Value<String> name,
      Value<String?> imagePath,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$FavoritesTableFilterComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get episodeId => $composableBuilder(
    column: $table.episodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get m3uItemId => $composableBuilder(
    column: $table.m3uItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavoritesTableOrderingComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get episodeId => $composableBuilder(
    column: $table.episodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get m3uItemId => $composableBuilder(
    column: $table.m3uItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavoritesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get streamId =>
      $composableBuilder(column: $table.streamId, builder: (column) => column);

  GeneratedColumn<String> get episodeId =>
      $composableBuilder(column: $table.episodeId, builder: (column) => column);

  GeneratedColumn<String> get m3uItemId =>
      $composableBuilder(column: $table.m3uItemId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get imagePath =>
      $composableBuilder(column: $table.imagePath, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$FavoritesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FavoritesTable,
          FavoritesData,
          $$FavoritesTableFilterComposer,
          $$FavoritesTableOrderingComposer,
          $$FavoritesTableAnnotationComposer,
          $$FavoritesTableCreateCompanionBuilder,
          $$FavoritesTableUpdateCompanionBuilder,
          (
            FavoritesData,
            BaseReferences<_$AppDatabase, $FavoritesTable, FavoritesData>,
          ),
          FavoritesData,
          PrefetchHooks Function()
        > {
  $$FavoritesTableTableManager(_$AppDatabase db, $FavoritesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoritesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoritesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoritesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
                Value<int> contentType = const Value.absent(),
                Value<String> streamId = const Value.absent(),
                Value<String?> episodeId = const Value.absent(),
                Value<String?> m3uItemId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoritesCompanion(
                id: id,
                playlistId: playlistId,
                contentType: contentType,
                streamId: streamId,
                episodeId: episodeId,
                m3uItemId: m3uItemId,
                name: name,
                imagePath: imagePath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String playlistId,
                required int contentType,
                required String streamId,
                Value<String?> episodeId = const Value.absent(),
                Value<String?> m3uItemId = const Value.absent(),
                required String name,
                Value<String?> imagePath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoritesCompanion.insert(
                id: id,
                playlistId: playlistId,
                contentType: contentType,
                streamId: streamId,
                episodeId: episodeId,
                m3uItemId: m3uItemId,
                name: name,
                imagePath: imagePath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoritesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FavoritesTable,
      FavoritesData,
      $$FavoritesTableFilterComposer,
      $$FavoritesTableOrderingComposer,
      $$FavoritesTableAnnotationComposer,
      $$FavoritesTableCreateCompanionBuilder,
      $$FavoritesTableUpdateCompanionBuilder,
      (
        FavoritesData,
        BaseReferences<_$AppDatabase, $FavoritesTable, FavoritesData>,
      ),
      FavoritesData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PlaylistsTableTableManager get playlists =>
      $$PlaylistsTableTableManager(_db, _db.playlists);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$UserInfosTableTableManager get userInfos =>
      $$UserInfosTableTableManager(_db, _db.userInfos);
  $$ServerInfosTableTableManager get serverInfos =>
      $$ServerInfosTableTableManager(_db, _db.serverInfos);
  $$LiveStreamsTableTableManager get liveStreams =>
      $$LiveStreamsTableTableManager(_db, _db.liveStreams);
  $$VodStreamsTableTableManager get vodStreams =>
      $$VodStreamsTableTableManager(_db, _db.vodStreams);
  $$SeriesStreamsTableTableManager get seriesStreams =>
      $$SeriesStreamsTableTableManager(_db, _db.seriesStreams);
  $$SeriesInfosTableTableManager get seriesInfos =>
      $$SeriesInfosTableTableManager(_db, _db.seriesInfos);
  $$SeasonsTableTableManager get seasons =>
      $$SeasonsTableTableManager(_db, _db.seasons);
  $$EpisodesTableTableManager get episodes =>
      $$EpisodesTableTableManager(_db, _db.episodes);
  $$WatchHistoriesTableTableManager get watchHistories =>
      $$WatchHistoriesTableTableManager(_db, _db.watchHistories);
  $$M3uItemsTableTableManager get m3uItems =>
      $$M3uItemsTableTableManager(_db, _db.m3uItems);
  $$M3uSeriesTableTableManager get m3uSeries =>
      $$M3uSeriesTableTableManager(_db, _db.m3uSeries);
  $$M3uEpisodesTableTableManager get m3uEpisodes =>
      $$M3uEpisodesTableTableManager(_db, _db.m3uEpisodes);
  $$FavoritesTableTableManager get favorites =>
      $$FavoritesTableTableManager(_db, _db.favorites);
}
