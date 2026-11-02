import 'package:itaaleem/core/providers/cache_for.dart';
import 'package:itaaleem/features/subjects/data/datasources/subjects_remote_data_source.dart';
import 'package:itaaleem/features/subjects/domain/entities/subject.dart';
import 'package:flutter/foundation.dart';
import 'package:itaaleem/features/parent/data/parent_api.dart';
import 'package:itaaleem/features/settings/presentation/providers/settings_providers.dart';
import 'package:itaaleem/features/subjects/data/models/subject_json_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Real-data only — the demo ("دخول تجريبي") path never watches these,
/// rendering [dummySubjects] directly instead (see [SubjectsScreen] and
/// [SubjectDetailScreen]).
///
/// With terms on, subjects that belong only to a non-current term are left
/// out — so home, exams and assignments (all built on this list) follow the
/// center's current term. Terms off or `/subjects-by-term` failing → the
/// full list, exactly as before.
final subjectsListProvider = FutureProvider.autoDispose<List<Subject>>((
  ref,
) async {
  final all = await ref.cached(
    () => ref.read(subjectsRemoteDataSourceProvider).getSubjects(),
  );
  final hidden = hiddenTermSubjectIds(
    await ref.watch(subjectsByTermProvider.future),
  );
  if (hidden.isEmpty) return all;
  return all.where((s) => !hidden.contains(s.id)).toList();
});

/// `GET /subjects/{id}` is meant to embed this subject's own `lessons`
/// array directly, but that hasn't held up in practice (mirrors the same
/// "assumed embed doesn't actually come back" issue already found on
/// `GET /centers?code=` and the content list endpoints) — when it comes
/// back empty despite [Subject.lessonsCount] being non-zero, fall back to
/// the dedicated `GET /lessons?subject_id=` call (already used by the home
/// tab) instead of just trusting the empty embed.
final subjectDetailsProvider = FutureProvider.autoDispose.family<Subject, int>((
  ref,
  id,
) async {
  // Cached only 1 min: this carries each lesson's `is_accessible` (lock
  // state), which the center can change from the dashboard at any time.
  return ref.cached(() async {
    final dataSource = ref.read(subjectsRemoteDataSourceProvider);
    final subject = await dataSource.getSubjectDetails(id);
    if (kDebugMode) {
      final card = subject.accessCard;
      debugPrint(
        card == null
            ? '[access_card] MISSING from GET /subjects/$id — no activation card'
            : '[access_card] subject $id: show=${card.show} '
                  'activation=${card.activationEnabled} '
                  'purchase=${card.purchaseEnabled} '
                  'request_status=${card.requestStatus}',
      );
    }
    // An embed shorter than `lessons_count` may be leaving out the paid
    // lessons — fetch the full list in that case too.
    if (subject.lessons.length >= subject.lessonsCount) {
      return subject;
    }
    if (kDebugMode) {
      debugPrint(
        '[subjectDetailsProvider] subject $id: lessonsCount=${subject.lessonsCount} '
        'but embedded lessons=[] — falling back to GET /lessons?subject_id=$id',
      );
    }
    try {
      final lessons = await dataSource.getLessons(subjectId: id);
      if (lessons.length <= subject.lessons.length) return subject;
      return subject.withLessons(lessons);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[subjectDetailsProvider] lessons fallback for $id failed: $e',
        );
      }
      return subject;
    }
  }, duration: const Duration(minutes: 1));
});

/// A subject's files (`GET /attachments?subject_id=`), keyed by subject id.
final attachmentsProvider = FutureProvider.autoDispose
    .family<List<SubjectAttachment>, int>((ref, subjectId) {
      return ref.cached(
        () => ref
            .read(subjectsRemoteDataSourceProvider)
            .getAttachments(subjectId),
      );
    });

/// One lesson's files only — key is `(subjectId, lessonId)`.
final lessonAttachmentsProvider = FutureProvider.autoDispose
    .family<List<SubjectAttachment>, (int, int)>((ref, key) {
      return ref.cached(
        () => ref
            .read(subjectsRemoteDataSourceProvider)
            .getAttachments(key.$1, lessonId: key.$2),
      );
    });

/// Home screen's "آخر المحاضرات": the first subject's lessons (capped at
/// 4) — there's no single endpoint for "latest lessons across every
/// subject", so this is the closest real approximation, per the task spec.
final homeLessonsProvider = FutureProvider.autoDispose<List<SubjectLesson>>((
  ref,
) async {
  return ref.cached(() async {
    final subjects = await ref.watch(subjectsListProvider.future);
    if (subjects.isEmpty) return const [];
    return ref
        .read(subjectsRemoteDataSourceProvider)
        .getLessons(subjectId: subjects.first.id, limit: 4);
  });
});

/// Watched by the screens that list subjects: once the list is in, the
/// first few subjects' details start loading in the background (and stay
/// cached via [subjectDetailsProvider]'s TTL), so opening one is instant.
/// Capped so a long list doesn't fire a burst of requests.
final prefetchFirstSubjectProvider = Provider.autoDispose<void>((ref) {
  final subjects = ref.watch(subjectsListProvider).valueOrNull;
  if (subjects == null || subjects.isEmpty) return;
  for (final subject in subjects.take(_prefetchCount)) {
    ref.listen(subjectDetailsProvider(subject.id), (_, _) {});
  }
});

const _prefetchCount = 3;

/// One group of `GET /subjects-by-term`, in the server's order.
class TermGroup {
  const TermGroup({
    required this.id,
    required this.name,
    required this.isCurrent,
    required this.subjects,
  });

  /// `null` for the trailing "عام" group.
  final int? id;
  final String name;
  final bool isCurrent;
  final List<Subject> subjects;
}

/// The groups to show: the current term(s) plus the no-term "عام" group.
/// When the server marks no term as current, every group stays (nothing is
/// hidden on a guess).
List<TermGroup> visibleTermGroups(List<TermGroup> terms) {
  if (!terms.any((t) => t.isCurrent)) return terms;
  return terms.where((t) => t.isCurrent || t.id == null).toList();
}

/// Ids of subjects found only in hidden (non-current) terms — a subject that
/// also sits in a visible group stays.
Set<int> hiddenTermSubjectIds(List<TermGroup>? terms) {
  if (terms == null) return const {};
  final visible = visibleTermGroups(terms);
  final shown = {
    for (final t in visible)
      for (final s in t.subjects) s.id,
  };
  return {
    for (final t in terms)
      if (!visible.contains(t))
        for (final s in t.subjects)
          if (!shown.contains(s.id)) s.id,
  };
}

/// Subjects grouped by term — only when `settings.terms_enabled`. `null`
/// means "use the plain `GET /subjects` list": the switch is off, or the
/// call failed in any way (403 for a center without terms included), with
/// nothing shown to the student.
final subjectsByTermProvider = FutureProvider.autoDispose<List<TermGroup>?>((
  ref,
) async {
  bool enabled;
  try {
    enabled = (await ref.watch(appSettingsProvider.future)).termsEnabled;
  } catch (_) {
    enabled = false;
  }
  if (!enabled) return null;
  return ref.cached(() async {
    try {
      final raw = await ref.read(studentExtrasApiProvider).getSubjectsByTerm();
      return [
        for (final t in raw)
          TermGroup(
            id: t['id'] is num ? (t['id'] as num).toInt() : null,
            name: t['name'] is String ? t['name'] as String : '',
            isCurrent: t['is_current'] == true,
            subjects: [
              for (final s
                  in (t['subjects'] is List ? t['subjects'] as List : const []))
                if (s is Map<String, dynamic>) subjectFromJson(s),
            ],
          ),
      ];
    } catch (e) {
      if (kDebugMode) debugPrint('>>> subjects-by-term fallback: $e');
      return null;
    }
  });
});
