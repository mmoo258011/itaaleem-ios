import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/utils/youtube_utils.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/video/data/offline/encryption_manager.dart';
import 'package:itaaleem/core/storage/backup_exclusion.dart';
import 'package:itaaleem/features/video/data/offline/offline_database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One instantaneous speed sample, for the "المحمّلات" screen's live
/// "X MB/s" readout — everything else the UI needs (status, percentage,
/// bytes downloaded so far) is read straight off the reactive
/// `OfflineVideos` row via `OfflineDatabase.watchByLessonId`/`watchAll`.
typedef DownloadSpeedSample = ({int lessonId, double bytesPerSecond});

class InsufficientStorageException implements Exception {
  const InsufficientStorageException();

  @override
  String toString() => 'لا توجد مساحة كافية على الجهاز';
}

class DemoModeDownloadException implements Exception {
  const DemoModeDownloadException();

  @override
  String toString() => 'التحميل غير متاح في وضع العرض التجريبي';
}

/// Downloads a lecture's video for offline playback: resolves the lesson's
/// own `video_url` into a downloadable file URL (a YouTube link → its
/// progressive muxed stream via `youtube_explode_dart`; any other URL is used
/// as is — no `download-token` endpoint involved), streams the bytes with
/// Dio, and encrypts them (AES-256-CTR, see [EncryptionManager]) in fixed-
/// size chunks on the way to disk — the plain video is never written
/// unencrypted anywhere.
///
/// Only one active transfer per lesson at a time; [pauseDownload] and
/// [cancelDownload] both cancel that transfer, distinguished only by
/// whether the lesson id is in [_pausing] at the moment the cancellation is
/// observed (so the right status/byte-offset gets persisted). A paused
/// download's `OfflineVideos.encryptedSize` is kept exactly equal to
/// however many *whole* chunks have been flushed to disk — the byte offset
/// [resumeDownload] later requests via `Range: bytes={offset}-` — which
/// only works because CTR-mode ciphertext is always exactly the same
/// length as the plaintext it came from, so that offset means the same
/// thing on both sides of the encryption.
class OfflineDownloadManager {
  OfflineDownloadManager({
    required EncryptionManager encryption,
    required OfflineDatabase db,
    required bool Function() isDemo,
  }) : _encryption = encryption,
       _db = db,
       _isDemo = isDemo;

  final EncryptionManager _encryption;
  final OfflineDatabase _db;
  final bool Function() _isDemo;

  /// A separate, interceptor-free client for the raw video bytes — the
  /// download URL is often a different (CDN) host than the API, and it
  /// must never receive our API's bearer token; whatever auth it needs
  /// comes back as explicit `headers` on the download-token response.
  final Dio _streamDio = Dio();

  final Map<int, CancelToken> _activeCancelTokens = {};
  final Set<int> _pausing = {};

  final _speedController = StreamController<DownloadSpeedSample>.broadcast();
  Stream<DownloadSpeedSample> get downloadSpeedStream =>
      _speedController.stream;

  void dispose() {
    for (final token in _activeCancelTokens.values) {
      token.cancel('disposed');
    }
    _speedController.close();
  }

  Future<void> startDownload(
    int lessonId, {
    required String sourceUrl,
    String quality = '720p',
    String subjectName = '',
    String lessonTitle = '',
  }) async {
    if (_isDemo()) throw const DemoModeDownloadException();
    if (_activeCancelTokens.containsKey(lessonId)) return;

    final cancelToken = CancelToken();
    _activeCancelTokens[lessonId] = cancelToken;

    try {
      final path = await _filePathFor(lessonId);
      final iv = _encryption.generateIv();

      await _db.upsert(
        OfflineVideosCompanion.insert(
          lessonId: lessonId,
          subjectName: Value(subjectName),
          lessonTitle: Value(lessonTitle),
          sourceUrl: Value(sourceUrl),
          quality: Value(quality),
          localPath: Value(path),
          encryptionIv: Value(iv),
          downloadStatus: const Value('downloading'),
          downloadProgress: const Value(0),
          encryptedSize: const Value(0),
          lastError: const Value(null),
        ),
      );

      await _downloadFrom(
        lessonId: lessonId,
        sourceUrl: sourceUrl,
        iv: iv,
        path: path,
        resumeFromBytes: 0,
        cancelToken: cancelToken,
      );
    } catch (e, stackTrace) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      if (kDebugMode) {
        debugPrint(
          '[OfflineDownloadManager] startDownload($lessonId) failed: ${_describe(e)}\n$stackTrace',
        );
      }
      await _db.updateByLessonId(
        lessonId,
        (base) => base.copyWith(
          downloadStatus: const Value('failed'),
          lastError: Value(_friendlyError(e)),
        ),
      );
    } finally {
      _activeCancelTokens.remove(lessonId);
      _pausing.remove(lessonId);
    }
  }

  /// The lesson is already downloaded: its row is `completed` and the
  /// encrypted file is on disk with the size recorded. A missing or short
  /// file means it has to be downloaded again.
  Future<bool> isFullyDownloaded(int lessonId) async {
    final row = await _db.getByLessonId(lessonId);
    if (row == null || row.downloadStatus != 'completed') return false;
    final file = File(row.localPath);
    if (!await file.exists()) return false;
    return row.encryptedSize > 0 && await file.length() >= row.encryptedSize;
  }

  Future<void> resumeDownload(int lessonId) async {
    if (_isDemo()) throw const DemoModeDownloadException();
    if (_activeCancelTokens.containsKey(lessonId)) return;
    final row = await _db.getByLessonId(lessonId);
    if (row == null || row.downloadStatus != 'paused') return;

    final cancelToken = CancelToken();
    _activeCancelTokens[lessonId] = cancelToken;

    try {
      await _db.updateByLessonId(
        lessonId,
        (base) => base.copyWith(downloadStatus: const Value('downloading')),
      );
      await _downloadFrom(
        lessonId: lessonId,
        sourceUrl: row.sourceUrl,
        iv: row.encryptionIv,
        path: row.localPath,
        resumeFromBytes: row.encryptedSize,
        cancelToken: cancelToken,
      );
    } catch (e, stackTrace) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      if (kDebugMode) {
        debugPrint(
          '[OfflineDownloadManager] resumeDownload($lessonId) failed: ${_describe(e)}\n$stackTrace',
        );
      }
      await _db.updateByLessonId(
        lessonId,
        (base) => base.copyWith(
          downloadStatus: const Value('failed'),
          lastError: Value(_friendlyError(e)),
        ),
      );
    } finally {
      _activeCancelTokens.remove(lessonId);
      _pausing.remove(lessonId);
    }
  }

  void pauseDownload(int lessonId) {
    final token = _activeCancelTokens[lessonId];
    if (token == null) return;
    _pausing.add(lessonId);
    token.cancel('paused');
  }

  Future<void> cancelDownload(int lessonId) async {
    final token = _activeCancelTokens[lessonId];
    if (token != null) {
      _pausing.remove(lessonId);
      token.cancel('cancelled');
      return; // The rest is handled where the cancellation is observed.
    }
    // Nothing in flight (already paused/failed) — clean up right away.
    await _deleteFile(lessonId);
    await _db.updateByLessonId(
      lessonId,
      (base) => base.copyWith(
        downloadStatus: const Value('cancelled'),
        downloadProgress: const Value(0),
      ),
    );
  }

  Future<void> deleteDownload(int lessonId) async {
    final token = _activeCancelTokens[lessonId];
    token?.cancel('deleted');
    await _deleteFile(lessonId);
    await _db.deleteByLessonId(lessonId);
  }

  /// Logout: cancels every download, deletes every encrypted file and row,
  /// and the AES key itself — nothing of the previous account survives.
  Future<void> deleteAllForLogout() async {
    for (final token in _activeCancelTokens.values) {
      token.cancel('logout');
    }
    _activeCancelTokens.clear();
    _pausing.clear();
    try {
      final dir = await _offlineDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    for (final row in await _db.getAll()) {
      final path = row.localPath;
      if (path.isNotEmpty) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      await _db.deleteByLessonId(row.lessonId);
    }
    await _encryption.deleteKey();
  }

  Future<void> retryDownload(int lessonId) async {
    if (_isDemo()) throw const DemoModeDownloadException();
    final row = await _db.getByLessonId(lessonId);
    if (row == null) return;
    await _deleteFile(lessonId);
    await startDownload(
      lessonId,
      sourceUrl: row.sourceUrl,
      quality: row.quality,
      subjectName: row.subjectName,
      lessonTitle: row.lessonTitle,
    );
  }

  Future<List<OfflineVideo>> getDownloadedLessons() async {
    final all = await _db.getAll();
    return all.where((v) => v.downloadStatus == 'completed').toList();
  }

  Future<String?> getDownloadStatus(int lessonId) async {
    final row = await _db.getByLessonId(lessonId);
    return row?.downloadStatus;
  }

  Future<int> getStorageUsed() => _db.totalEncryptedSize();

  /// Best-effort free-space check: reserves [requiredBytes] via
  /// `RandomAccessFile.truncate` on a throwaway file in the same directory
  /// downloads are written to, which fails synchronously on most
  /// filesystems if there truly isn't room — there's no disk-free-space
  /// plugin in this project to ask more directly. With no [requiredBytes]
  /// given, checks a conservative flat 200 MB.
  Future<bool> checkStorage([int? requiredBytes]) async {
    try {
      final dir = await _offlineDir();
      final probe = File(p.join(dir.path, '.storage_probe'));
      final raf = await probe.open(mode: FileMode.write);
      await raf.truncate(requiredBytes ?? 200 * 1024 * 1024);
      await raf.close();
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- Internals ----------------------------------------------------------

  Future<void> _downloadFrom({
    required int lessonId,
    required String sourceUrl,
    required String iv,
    required String path,
    required int resumeFromBytes,
    required CancelToken cancelToken,
  }) async {
    final source = await _openSource(sourceUrl, resumeFromBytes, cancelToken);

    if (resumeFromBytes > 0 && !source.honoredRange) {
      // The server ignored our Range request — restarting in place would
      // silently corrupt the file (full content appended after what's
      // already there), so start clean instead.
      if (kDebugMode) {
        debugPrint(
          '[OfflineDownloadManager] lesson $lessonId: server ignored Range '
          '— restarting from scratch',
        );
      }
      return _downloadFrom(
        lessonId: lessonId,
        sourceUrl: sourceUrl,
        iv: iv,
        path: path,
        resumeFromBytes: 0,
        cancelToken: cancelToken,
      );
    }

    final total = source.total;
    if (resumeFromBytes == 0 && total != null && !await checkStorage(total)) {
      throw const InsufficientStorageException();
    }

    final file = File(path);
    if (resumeFromBytes == 0 && await file.exists()) await file.delete();
    final raf = await file.open(
      mode: resumeFromBytes > 0 ? FileMode.append : FileMode.write,
    );

    var chunkIndex = resumeFromBytes ~/ EncryptionManager.chunkSize;
    final buffer = BytesBuilder(copy: false);
    var lastSample = DateTime.now();
    var bytesSinceLastSample = 0;
    var cancelled = false;

    try {
      await for (final data in source.stream) {
        buffer.add(data);
        bytesSinceLastSample += data.length;

        while (buffer.length >= EncryptionManager.chunkSize) {
          final pending = buffer.takeBytes();
          final chunkBytes = Uint8List.sublistView(
            pending,
            0,
            EncryptionManager.chunkSize,
          );
          final iv2 = _encryption.chunkIvFor(iv, chunkIndex).base64;
          final encrypted = await _encryption.encryptChunk(chunkBytes, iv2);
          await raf.writeFrom(encrypted);
          chunkIndex++;
          final remainder = pending.length > EncryptionManager.chunkSize
              ? Uint8List.sublistView(pending, EncryptionManager.chunkSize)
              : null;
          if (remainder != null && remainder.isNotEmpty) buffer.add(remainder);
        }

        final now = DateTime.now();
        final elapsedMs = now.difference(lastSample).inMilliseconds;
        if (elapsedMs >= 500) {
          _speedController.add((
            lessonId: lessonId,
            bytesPerSecond: bytesSinceLastSample / (elapsedMs / 1000),
          ));
          bytesSinceLastSample = 0;
          lastSample = now;

          final flushed = chunkIndex * EncryptionManager.chunkSize;
          await _db.updateByLessonId(
            lessonId,
            (base) => base.copyWith(
              encryptedSize: Value(flushed),
              downloadProgress: Value(
                total != null ? (flushed / total).clamp(0.0, 1.0) : 0.0,
              ),
            ),
          );
        }
      }

      // The file's true final chunk, expected to be shorter than
      // [EncryptionManager.chunkSize] — only ever reached on a real
      // stream completion, never on pause/cancel.
      if (buffer.length > 0) {
        final tail = buffer.takeBytes();
        final iv2 = _encryption.chunkIvFor(iv, chunkIndex).base64;
        final encrypted = await _encryption.encryptChunk(tail, iv2);
        await raf.writeFrom(encrypted);
      }
      await raf.close();

      final finalSize = await File(path).length();
      await _db.updateByLessonId(
        lessonId,
        (base) => base.copyWith(
          downloadStatus: const Value('completed'),
          downloadProgress: const Value(1),
          downloadedAt: Value(DateTime.now()),
          encryptedSize: Value(finalSize),
          lastError: const Value(null),
        ),
      );
    } catch (e) {
      cancelled = e is DioException && CancelToken.isCancel(e);
      await raf.close();
      if (!cancelled) rethrow;

      // Pause/cancel: only whole flushed chunks count as "downloaded" —
      // anything still sitting in [buffer] was never written to disk.
      final flushed = chunkIndex * EncryptionManager.chunkSize;
      final wasPause = _pausing.remove(lessonId);
      await _db.updateByLessonId(
        lessonId,
        (base) => base.copyWith(
          downloadStatus: Value(wasPause ? 'paused' : 'cancelled'),
          encryptedSize: Value(flushed),
          downloadProgress: Value(
            total != null ? (flushed / total).clamp(0.0, 1.0) : 0.0,
          ),
        ),
      );
      if (!wasPause) await _deleteFile(lessonId);
    }
  }

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Mobile Safari/537.36';

  /// Opens the bytes to download, starting at [resumeFromBytes]. A YouTube
  /// link becomes its best progressive muxed (audio+video) stream — HLS
  /// playlists can't be saved as one file; any other URL is downloaded as is.
  Future<_ByteSource> _openSource(
    String sourceUrl,
    int resumeFromBytes,
    CancelToken cancelToken,
  ) async {
    if (sourceUrl.isEmpty) throw const _NoVideoSourceException();
    if (!isYouTubeUrl(sourceUrl)) {
      return _openDirect(
        ApiEndpoints.mediaUrl(sourceUrl) ?? sourceUrl,
        resumeFromBytes,
        cancelToken,
      );
    }
    final youtubeId = extractYouTubeId(sourceUrl);
    if (youtubeId == null) throw const _NoVideoSourceException();

    final client = yt_explode.YoutubeExplode();
    yt_explode.MuxedStreamInfo info;
    try {
      final manifest = await client.videos.streamsClient.getManifest(youtubeId);
      if (manifest.muxed.isEmpty) throw const _NoVideoSourceException();
      info = manifest.muxed.withHighestBitrate();
    } finally {
      client.close();
    }
    return _ByteSource(
      stream: _youtubeChunks(info, resumeFromBytes, cancelToken),
      total: info.size.totalBytes,
      honoredRange: true,
    );
  }

  Future<_ByteSource> _openDirect(
    String url,
    int resumeFromBytes,
    CancelToken cancelToken,
  ) async {
    final response = await _streamDio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'User-Agent': _userAgent,
          if (resumeFromBytes > 0) 'Range': 'bytes=$resumeFromBytes-',
        },
      ),
      cancelToken: cancelToken,
    );
    return _ByteSource(
      stream: response.data!.stream,
      total: _parseTotalBytes(response, resumeFromBytes),
      honoredRange: resumeFromBytes == 0 || response.statusCode == 206,
    );
  }

  /// googlevideo URLs reject one big plain GET — `youtube_explode_dart`'s own
  /// downloader fetches them in ranged chunks (`range=from-to` as a *query
  /// parameter*, ~10 MB at a time when throttled) with browser-like headers,
  /// so this does the same (and, unlike its `streamsClient.get`, can start at
  /// an arbitrary byte offset to resume).
  Stream<List<int>> _youtubeChunks(
    yt_explode.MuxedStreamInfo info,
    int from,
    CancelToken cancelToken,
  ) async* {
    final url = info.url;
    final total = info.size.totalBytes;
    final isAndroidClient = url.queryParameters['c'] == 'ANDROID';
    var position = from;

    while (position < total) {
      final to = (info.isThrottled ? position + 10379935 : total) - 1;
      final last = to < total - 1 ? to : total - 1;
      var attempt = 0;
      while (position <= last) {
        try {
          final requestUrl = isAndroidClient
              ? url
              : url.replace(
                  queryParameters: {
                    ...url.queryParameters,
                    'range': '$position-$last',
                  },
                );
          final response = await _streamDio.getUri<ResponseBody>(
            requestUrl,
            options: Options(
              responseType: ResponseType.stream,
              headers: {
                ..._youtubeHeaders,
                if (isAndroidClient) 'Range': 'bytes=$position-$last',
              },
            ),
            cancelToken: cancelToken,
          );
          await for (final data in response.data!.stream) {
            position += data.length;
            yield data;
          }
        } on DioException catch (e) {
          if (CancelToken.isCancel(e) || ++attempt > 3) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }
  }

  static const _youtubeHeaders = {
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36',
    'cookie': 'CONSENT=YES+cb',
    'accept-language': 'en-US,en;q=0.5',
  };

  /// Short, log-friendly description (a `DioException`'s own `toString` is
  /// huge).
  String _describe(Object error) {
    if (error is DioException) {
      return 'DioException(${error.type.name}, status=${error.response?.statusCode}, '
          'host=${error.requestOptions.uri.host}, message=${error.message})';
    }
    return error.toString();
  }

  String _friendlyError(Object error) {
    if (error is InsufficientStorageException) return error.toString();
    if (error is _NoVideoSourceException)
      return 'لا يوجد فيديو قابل للتحميل لهذه المحاضرة';
    if (error is DioException) {
      return 'فشل التحميل';
    }
    return 'تعذر تحميل الفيديو — حاول مرة أخرى';
  }

  int? _parseTotalBytes(Response<ResponseBody> response, int resumeFromBytes) {
    if (response.statusCode == 206) {
      final range = response.headers.value('content-range');
      final match = range == null ? null : RegExp(r'/(\d+)$').firstMatch(range);
      if (match != null) return int.tryParse(match.group(1)!);
    }
    final len = response.headers.value('content-length');
    final contentLength = len == null ? null : int.tryParse(len);
    if (contentLength != null) return resumeFromBytes + contentLength;
    return null;
  }

  Future<void> _deleteFile(int lessonId) async {
    final row = await _db.getByLessonId(lessonId);
    final path = row?.localPath;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<Directory> _offlineDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'offline_videos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    if (!_backupExcluded) {
      _backupExcluded = await excludeFromBackup(dir.path);
    }
    return dir;
  }

  bool _backupExcluded = false;

  Future<String> _filePathFor(int lessonId) async {
    final dir = await _offlineDir();
    return p.join(dir.path, 'lesson_$lessonId.enc');
  }
}

class _ByteSource {
  const _ByteSource({
    required this.stream,
    required this.total,
    required this.honoredRange,
  });

  final Stream<List<int>> stream;

  /// Whole file size in bytes, if known.
  final int? total;

  /// False when a resume was requested but the server sent the whole file.
  final bool honoredRange;
}

class _NoVideoSourceException implements Exception {
  const _NoVideoSourceException();
}

final offlineDownloadManagerProvider = Provider<OfflineDownloadManager>((ref) {
  final manager = OfflineDownloadManager(
    encryption: ref.watch(encryptionManagerProvider),
    db: ref.watch(offlineDatabaseProvider),
    isDemo: () => ref.read(authControllerProvider).valueOrNull?.isDemo ?? false,
  );
  ref.onDispose(manager.dispose);
  return manager;
});
