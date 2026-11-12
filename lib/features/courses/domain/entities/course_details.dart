import 'package:itaaleem/features/teachers/domain/entities/teacher.dart';

/// Full course shape from `GET /courses/{id}`: the course plus its
/// sections ("المواد") and, within each, its lectures ("الدروس").
class CourseDetails {
  const CourseDetails({
    required this.id,
    required this.title,
    required this.sections,
    this.imageUrl,
    this.description,
    this.progressPercent = 0,
    this.exams = const [],
    this.teachers = const [],
  });

  final int id;
  final String title;
  final String? imageUrl;
  final String? description;

  /// 0-100.
  final double progressPercent;
  final List<CourseSection> sections;

  /// The course's exams — each opens `GET /exams/{id}` -> "بدء الامتحان".
  final List<CourseExam> exams;

  /// This course's teachers, embedded directly in `GET /courses/{id}`
  /// (separate from — and a subset of — `GET /public/teachers`). Used by
  /// the subject/lecture screen's "مدرسو هذه المادة" section, filtered down
  /// via [Teacher.sectionIds] to the ones covering the selected section.
  final List<Teacher> teachers;
}

class CourseExam {
  const CourseExam({
    required this.id,
    required this.title,
    this.questionsCount,
    this.durationMinutes,
    this.createdAt,
    this.attempted = false,
    this.score,
    this.passed,
  });

  final int id;
  final String title;
  final int? questionsCount;
  final int? durationMinutes;
  final DateTime? createdAt;

  /// Whether the student already has an attempt on record — from
  /// `GET /courses/{id}/exams`, the server's authoritative attempt status
  /// (the exam stubs embedded in `GET /courses/{id}` don't carry this, so
  /// it defaults to `false` there).
  final bool attempted;

  /// 0-100, only meaningful when [attempted] is true.
  final double? score;

  /// Only meaningful when [attempted] is true.
  final bool? passed;
}

/// Carried via `GoRouter`'s `extra` when pushing `/lectures/:id`: the
/// lecture's title (there's no reliable one in `GET /lectures/{id}` itself,
/// see [LecturePlayerScreen]) plus its parent course's exams — there's no
/// per-lecture exam link in the API, so the same list is shown on every
/// lecture of that course.
///
/// [orderedLectures] and [currentIndex] carry the section's lecture order the
/// student navigated from, so the player screen can offer "المحاضرة
/// السابقة"/"التالية" without a second network round-trip; [courseId] and
/// [courseTitle] ride along so a locked neighbor can still open the same
/// subscribe-request sheet the lecture list itself would show.
class LectureNavArgs {
  const LectureNavArgs({
    this.title,
    this.courseExams = const [],
    this.courseId,
    this.courseTitle,
    this.orderedLectures = const [],
    this.currentIndex = -1,
    this.videoOnly = false,
  });

  final String? title;
  final List<CourseExam> courseExams;
  final int? courseId;
  final String? courseTitle;
  final List<CourseLecture> orderedLectures;
  final int currentIndex;

  /// Opened from the smart UI (`play_video`): the video only — no tabs,
  /// exams, attachments or notes (the smart UI shows those itself).
  final bool videoOnly;
}

enum LectureType { video, pdf, other }

class CourseSection {
  const CourseSection({
    required this.id,
    required this.title,
    required this.lectures,
    this.thumbnailUrl,
    this.teachers = const [],
  });

  final int id;
  final String title;
  final List<CourseLecture> lectures;

  /// Not confirmed present on `GET /courses/{id}` sections yet — parsed
  /// defensively so a card can prefer it over the parent course's image the
  /// moment the backend adds it, without a follow-up client change.
  final String? thumbnailUrl;

  /// This section's own teachers, nested directly on the section object in
  /// `GET /courses/{id}` (the `section_teacher` pivot, embedded) — the
  /// authoritative source for "مدرسو هذه المادة". [CourseDetails.teachers]
  /// (the course-level list filtered by [Teacher.sectionIds]) is only a
  /// fallback for when a section carries none of its own.
  final List<Teacher> teachers;
}

class CourseLecture {
  const CourseLecture({
    required this.id,
    required this.title,
    required this.type,
    this.durationLabel,
    this.isCompleted = false,
    this.isLocked = false,
    this.isFreePreview = false,
    this.hasVideo = false,
    this.hasPdf = false,
    this.thumbnailUrl,
    this.teacherId,
  });

  final int id;
  final String title;
  final LectureType type;
  final String? durationLabel;
  final bool isCompleted;

  /// Which of the section's teachers gave this lecture, if the API tags it
  /// — null when the API doesn't send that granularity, in which case the
  /// lecture is treated as shared/general and stays visible regardless of
  /// which teacher is toggled on the subject screen.
  final int? teacherId;

  /// The primary video's thumbnail — a YouTube `hqdefault` URL built from
  /// its video id when the API sends none of its own. Null when the
  /// lecture has no video (a PDF-only lecture falls back to a plain icon).
  final String? thumbnailUrl;

  /// Independent of [type] (which picks one icon, video taking priority) —
  /// a lecture can carry both a video and a PDF at once, and callers that
  /// show a badge per kind (rather than a single icon) need both flags.
  final bool hasVideo;
  final bool hasPdf;

  /// Requires an active enrollment (or code activation) to open —
  /// `GET /lectures/{id}` rejects locked lectures with a 403 unless
  /// [isFreePreview] is true.
  final bool isLocked;

  /// Viewable without enrollment.
  final bool isFreePreview;
}
