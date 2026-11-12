import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'offline_database.g.dart';

/// One downloaded (or downloading/failed/...) lecture video.
///
/// [encryptedSize] and [downloadProgress] track the on-disk encrypted file —
/// see `encryption_manager.dart` for why the encrypted file is always
/// exactly the same size as the plain video (AES-CTR, no padding), so this
/// doubles as the plain video's size too. [encryptionIv] is the per-file
/// base IV each download's chunks derive their own IV from — never the AES
/// key itself, which lives in `FlutterSecureStorage` instead (see
/// `EncryptionManager`).
class OfflineVideos extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get lessonId => integer().unique()();

  TextColumn get subjectName => text().withDefault(const Constant(''))();

  TextColumn get lessonTitle => text().withDefault(const Constant(''))();

  /// The lesson's own `video_url` (a YouTube link or a direct file URL) —
  /// what `OfflineDownloadManager` resolves into real bytes on every
  /// start/resume/retry (YouTube stream URLs expire, so it can't be stored).
  TextColumn get sourceUrl => text().withDefault(const Constant(''))();

  /// Absolute path to the encrypted file in app-private storage.
  TextColumn get localPath => text().withDefault(const Constant(''))();

  IntColumn get encryptedSize => integer().withDefault(const Constant(0))();

  /// queued | downloading | paused | completed | failed | cancelled | expired
  TextColumn get downloadStatus =>
      text().withDefault(const Constant('queued'))();

  /// 0-1.
  RealColumn get downloadProgress => real().withDefault(const Constant(0))();

  TextColumn get quality => text().withDefault(const Constant('720p'))();

  DateTimeColumn get downloadedAt => dateTime().nullable()();

  /// The download's own validity window (subscription/enrollment-driven,
  /// not an HTTP cache expiry) — see `OfflineLicenseChecker`.
  DateTimeColumn get expiresAt => dateTime().nullable()();

  TextColumn get encryptionIv => text().withDefault(const Constant(''))();

  /// Set once a failed download's error is known, so the "المحمّلات" screen
  /// can show it next to "إعادة المحاولة" — cleared on retry.
  TextColumn get lastError => text().nullable()();

  /// Non-null exactly when offline playback has reported progress that
  /// hasn't reached the server yet — set instead of calling the network
  /// progress endpoints while there's no connection, and flushed (then
  /// cleared) by `OfflineLicenseChecker.syncPendingProgress` once it's back.
  IntColumn get pendingSyncPositionSeconds => integer().nullable()();
  IntColumn get pendingSyncDurationSeconds => integer().nullable()();
  RealColumn get pendingSyncProgressPercentage => real().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [OfflineVideos])
class OfflineDatabase extends _$OfflineDatabase {
  OfflineDatabase() : super(_openConnection());

  /// An in-memory database for tests.
  OfflineDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.addColumn(offlineVideos, offlineVideos.sourceUrl);
    },
  );

  Future<OfflineVideo?> getByLessonId(int lessonId) => (select(
    offlineVideos,
  )..where((t) => t.lessonId.equals(lessonId))).getSingleOrNull();

  Stream<OfflineVideo?> watchByLessonId(int lessonId) => (select(
    offlineVideos,
  )..where((t) => t.lessonId.equals(lessonId))).watchSingleOrNull();

  /// Every non-cancelled row, newest download first — cancelled downloads
  /// are deleted outright (see [OfflineDownloadManager.cancelDownload]), so
  /// there's nothing to filter out here in practice, but the guard is kept
  /// in case a caller ever soft-cancels instead.
  Stream<List<OfflineVideo>> watchAll() {
    final query = select(offlineVideos)
      ..where((t) => t.downloadStatus.equals('cancelled').not())
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.watch();
  }

  Future<List<OfflineVideo>> getAll() => select(offlineVideos).get();

  /// One row per lesson: a second download of the same lesson replaces its
  /// row. `insertOnConflictUpdate` only handles a clash on the primary key,
  /// so a re-download used to fail on the unique `lesson_id`.
  Future<int> upsert(OfflineVideosCompanion entry) =>
      into(offlineVideos).insert(
        entry,
        onConflict: DoUpdate((_) => entry, target: [offlineVideos.lessonId]),
      );

  Future<void> updateByLessonId(
    int lessonId,
    OfflineVideosCompanion Function(OfflineVideosCompanion base) build,
  ) async {
    final base = OfflineVideosCompanion(updatedAt: Value(DateTime.now()));
    await (update(
      offlineVideos,
    )..where((t) => t.lessonId.equals(lessonId))).write(build(base));
  }

  Future<void> deleteByLessonId(int lessonId) =>
      (delete(offlineVideos)..where((t) => t.lessonId.equals(lessonId))).go();

  /// `GET /profile` reporting no active center/subscription — every
  /// still-usable download is invalidated at once. Already-expired/failed/
  /// cancelled rows are left alone.
  Future<void> markAllExpired() =>
      (update(offlineVideos)..where(
            (t) => t.downloadStatus.isIn([
              'completed',
              'downloading',
              'paused',
              'queued',
            ]),
          ))
          .write(
            OfflineVideosCompanion(
              downloadStatus: const Value('expired'),
              updatedAt: Value(DateTime.now()),
            ),
          );

  Future<List<OfflineVideo>> getPendingSync() {
    return (select(
      offlineVideos,
    )..where((t) => t.pendingSyncPositionSeconds.isNotNull())).get();
  }

  Future<void> clearPendingSync(int lessonId) => updateByLessonId(
    lessonId,
    (base) => base.copyWith(
      pendingSyncPositionSeconds: const Value(null),
      pendingSyncDurationSeconds: const Value(null),
      pendingSyncProgressPercentage: const Value(null),
    ),
  );

  Future<int> totalEncryptedSize() async {
    final rows = await getAll();
    var total = 0;
    for (final row in rows) {
      total += row.encryptedSize;
    }
    return total;
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'offline_videos.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// One long-lived connection for the app's lifetime — closed only when the
/// provider itself is disposed (never, in practice, since nothing scopes
/// it), matching how `dioClientProvider` etc. are kept alive.
final offlineDatabaseProvider = Provider<OfflineDatabase>((ref) {
  final db = OfflineDatabase();
  ref.onDispose(db.close);
  return db;
});
