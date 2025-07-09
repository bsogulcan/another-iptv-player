export 'unsupported.dart'
    if (dart.library.js_interop) 'web.dart'
    if (dart.library.ffi) 'native.dart';

export 'package:drift/src/web/wasm_setup/types.dart';
// ignore: implementation_imports
import 'package:drift/src/web/wasm_setup/types.dart';

/// Web-specific options used to open drift databases.
///
/// These options are ignored when drift is opened on native platforms.
final class DriftWebOptions {
  /// A uri pointing to the compiled sqlite3 WebAssembly module.
  ///
  /// If you have placed the module into your `web/` folder, you can simply use
  /// a relative url: `Uri.parse('sqlite3.wasm')`
  final Uri sqlite3Wasm;

  /// A uri pointing to the compiled drift worker.
  ///
  /// If you have placed the worker into your `web/` folder, you can simply use
  /// a relative url: `Uri.parse('drift_worker.js')`
  final Uri driftWorker;

  /// A method invoked when opening a database on the web, giving you access to
  /// the [WasmDatabaseResult] obtained before opening the database.
  ///
  /// The result provides insights about available browser features and how they
  /// impacted the database implementation (e.g. OPFS, IndexedDB) chosen.
  final void Function(WasmDatabaseResult)? onResult;

  /// Create web-specific drift options.
  DriftWebOptions({
    required this.sqlite3Wasm,
    required this.driftWorker,
    this.onResult,
  });
}

/// Options used to open drift databases on native platforms (outside of the
/// web).
final class DriftNativeOptions {
  /// Whether two isolates opening a drift database with the name should be
  /// connected to a shared database instance.
  ///
  /// When using a shared instance, stream queries synchronize across the two
  /// isolates. Also, drift then manages concurrent access to the database,
  /// preventing "database is locked" errors due to concurrent transactions.
  /// Note that this uses an `IsolateNameServer` to discover drift databases, so
  /// this feature does not work across databases opened by independent Flutter
  /// engines.
  ///
  /// A downside is a minor performance overhead caused by sending table updates
  /// across isolates.
  ///
  /// This option is not enabled by default, but recommended if a drift database
  /// may be used on multiple isolates.
  final bool shareAcrossIsolates;

  /// An optional callback returning a custom database path to be used by drift.
  ///
  /// By default, drift uses the `getApplicationDocumentsDirectory()` function
  /// from `package:path_provider` as a base directory and uses a file named
  /// `$name.sqlite` to store the database.
  ///
  /// This function, which can be asynchronous for convenience, allows using
  /// a custom database path in another directory.
  ///
  /// At most one of [databasePath] or [databaseDirectory] may be used. Using
  /// [databasePath] allows more control over the file name, while
  /// [databaseDirectory] can be used to select another directory from
  /// `path_provider` more easily.
  final Future<String> Function()? databasePath;

  /// An optional function returning either a string or a `Directory` that will
  /// be used as a directory to store the database.
  ///
  /// By default, drift will use `getApplicationDocumentsDirectory()` function
  /// from `package:path_provider` as a directory an `$name.sqlite` as a file
  /// name in that directory.
  ///
  /// At most one of [databasePath] or [databaseDirectory] may be used. Using
  /// [databasePath] allows more control over the file name, while
  /// [databaseDirectory] can be used to select another directory from
  /// `path_provider` more easily.
  final Future<Object> Function()? databaseDirectory;

  /// An optional callback returning a temporary directory.
  ///
  /// For larger queries, sqlite3 might store intermediate results in memory.
  /// By default, sqlite3 will attempt to store these results in `/tmp/`. On
  /// some platforms, the global `/tmp/` directory is inaccessible to sandboxed
  /// application, which then causes issues with sqlite3.
  /// For this reason, `drift_flutter` will configure sqlite3 to store these
  /// results in an application-defined temporary directory.
  ///
  /// When not set, `drift_flutter` defaults to `getTemporaryDirectory()` from
  /// `package:path_provider`.
  ///
  /// If the function returns `null`, the temporary directory for sqlite3 will
  /// not be changed by `drift_flutter`.
  final Future<String?> Function()? tempDirectoryPath;

  /// Create drift options effective when opening drift databases on native
  /// platforms.
  const DriftNativeOptions({
    this.shareAcrossIsolates = false,
    this.databasePath,
    this.databaseDirectory,
    this.tempDirectoryPath,
  }) : assert(
         databasePath == null || databaseDirectory == null,
         'databasePath and databaseDirectory must not both be set.',
       );
}
