/// This library provides [driftDatabase], a function suitable for opening
/// drift databases on Flutter apps.
library;

export 'connection/connect.dart';

import 'package:drift/drift.dart';
import 'connection/connect.dart' as connect;

/// Obtain a [QueryExecutor] to use for drift databases on the current platform.
///
/// The result of this method can be passed to [GeneratedDatabase] constructors
/// of drift databases:
///
/// ```dart
/// @DriftDatabase(...)
/// final class Database extends _$Database {
///   Database(): super(driftDatabase(name: 'my_app', web: ...));
/// }
/// ```
///
/// [name] is the name of the database to use. On native platforms, a file
/// called `$name.sqlite` in `getApplicationDocumentsDirectory()` will be used
/// for the database.
/// On the web, this name is part of the FileSystem API path or the name of the
/// IndexedDB database to use.
/// Typically, names only consist of alphanumerical characters and underscores.
QueryExecutor driftDatabase({
  required String name,
  connect.DriftWebOptions? web,
  connect.DriftNativeOptions? native,
}) {
  return connect.driftDatabase(name: name, web: web, native: native);
}
