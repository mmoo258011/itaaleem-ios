import 'package:itaaleem/core/utils/result.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/courses/data/datasources/courses_remote_data_source.dart';
import 'package:itaaleem/features/courses/data/repositories/courses_repository_impl.dart';
import 'package:itaaleem/features/courses/domain/entities/available_course.dart';
import 'package:itaaleem/features/courses/domain/entities/course.dart';
import 'package:itaaleem/features/courses/domain/entities/course_details.dart';
import 'package:itaaleem/features/courses/domain/entities/lecture_details.dart';
import 'package:itaaleem/features/courses/domain/usecases/get_available_courses_usecase.dart';
import 'package:itaaleem/features/courses/domain/usecases/get_course_details_usecase.dart';
import 'package:itaaleem/features/courses/domain/usecases/get_course_exams_usecase.dart';
import 'package:itaaleem/features/courses/domain/usecases/get_courses_usecase.dart';
import 'package:itaaleem/features/courses/domain/usecases/get_lecture_details_usecase.dart';
import 'package:itaaleem/features/courses/domain/usecases/get_lecture_playback_usecase.dart';
import 'package:itaaleem/features/courses/domain/usecases/get_lecture_progress_usecase.dart';
import 'package:itaaleem/features/courses/domain/usecases/post_lecture_progress_usecase.dart';
import 'package:itaaleem/features/courses/domain/usecases/post_pdf_progress_usecase.dart';
import 'package:itaaleem/features/courses/domain/usecases/request_enrollment_usecase.dart';
import 'package:itaaleem/features/teachers/domain/entities/teacher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final getCoursesUseCaseProvider = Provider<GetCoursesUseCase>((ref) {
  return GetCoursesUseCase(ref.watch(coursesRepositoryProvider));
});

final getCourseDetailsUseCaseProvider = Provider<GetCourseDetailsUseCase>((
  ref,
) {
  return GetCourseDetailsUseCase(ref.watch(coursesRepositoryProvider));
});

final getCourseExamsUseCaseProvider = Provider<GetCourseExamsUseCase>((ref) {
  return GetCourseExamsUseCase(ref.watch(coursesRepositoryProvider));
});

final getAvailableCoursesUseCaseProvider = Provider<GetAvailableCoursesUseCase>(
  (ref) {
    return GetAvailableCoursesUseCase(ref.watch(coursesRepositoryProvider));
  },
);

final requestEnrollmentUseCaseProvider = Provider<RequestEnrollmentUseCase>((
  ref,
) {
  return RequestEnrollmentUseCase(ref.watch(coursesRepositoryProvider));
});

final getLectureDetailsUseCaseProvider = Provider<GetLectureDetailsUseCase>((
  ref,
) {
  return GetLectureDetailsUseCase(ref.watch(coursesRepositoryProvider));
});

final getLecturePlaybackUseCaseProvider = Provider<GetLecturePlaybackUseCase>((
  ref,
) {
  return GetLecturePlaybackUseCase(ref.watch(coursesRepositoryProvider));
});

final getLectureProgressUseCaseProvider = Provider<GetLectureProgressUseCase>((
  ref,
) {
  return GetLectureProgressUseCase(ref.watch(coursesRepositoryProvider));
});

final postLectureProgressUseCaseProvider = Provider<PostLectureProgressUseCase>(
  (ref) {
    return PostLectureProgressUseCase(ref.watch(coursesRepositoryProvider));
  },
);

final postPdfProgressUseCaseProvider = Provider<PostPdfProgressUseCase>((ref) {
  return PostPdfProgressUseCase(ref.watch(coursesRepositoryProvider));
});

/// The student's enrolled courses (`GET /courses`). Plain `FutureProvider`
/// — no codegen, no manual notifier needed since this is a simple
/// fetch-and-cache case; screens call `ref.invalidate(coursesProvider)` to
/// refresh (e.g. pull-to-refresh, or after redeeming an activation code).
final coursesProvider = FutureProvider<List<Course>>((ref) async {
  // Demo session: never hits the network — no enrolled courses, same as a
  // freshly-joined real student, which the "المواد" tab already renders
  // as a clean empty state rather than an error.
  final isDemo = ref.watch(isDemoSessionProvider);
  if (isDemo) return const [];

  final useCase = ref.watch(getCoursesUseCaseProvider);
  final result = await useCase();
  return switch (result) {
    Ok<List<Course>>(:final value) => value,
    Err<List<Course>>(:final failure) => throw failure,
  };
});

/// A single course's full detail (`GET /courses/{id}`), keyed by course id.
///
/// Its `exams` are then enriched with each one's attempt status from
/// `GET /courses/{id}/exams` (`attempted`, `score`, `passed`) — fetched
/// alongside the details call and merged in here so every screen that reads
/// [CourseDetails.exams] (course details, a lecture's exams tab, the home
/// tab's subject cards) gets the attempt status for free. Falls back to the
/// plain exam stubs already embedded in `GET /courses/{id}` if that second
/// call fails, rather than failing the whole course details load over it.
final courseDetailsProvider = FutureProvider.family<CourseDetails, int>((
  ref,
  id,
) async {
  final useCase = ref.watch(getCourseDetailsUseCaseProvider);
  final examsUseCase = ref.watch(getCourseExamsUseCaseProvider);
  final detailsFuture = useCase(id);
  final examsFuture = examsUseCase(id);

  final detailsResult = await detailsFuture;
  final details = switch (detailsResult) {
    Ok<CourseDetails>(:final value) => value,
    Err<CourseDetails>(:final failure) => throw failure,
  };

  final examsResult = await examsFuture;
  final exams = switch (examsResult) {
    Ok<List<CourseExam>>(:final value) => value,
    Err<List<CourseExam>>() => details.exams,
  };

  return CourseDetails(
    id: details.id,
    title: details.title,
    sections: details.sections,
    imageUrl: details.imageUrl,
    description: details.description,
    progressPercent: details.progressPercent,
    exams: exams,
    teachers: details.teachers,
  );
});

/// The full published catalog (`GET /courses/available`), enrolled or not.
final availableCoursesProvider = FutureProvider<List<AvailableCourse>>((
  ref,
) async {
  final useCase = ref.watch(getAvailableCoursesUseCaseProvider);
  final result = await useCase();
  return switch (result) {
    Ok<List<AvailableCourse>>(:final value) => value,
    Err<List<AvailableCourse>>(:final failure) => throw failure,
  };
});

/// Fallback for "مدرسو هذه المادة" (`GET /public/teachers?course_id=...`),
/// used only when [courseDetailsProvider] carries no usable section pivot on
/// its teachers — see [CoursesRemoteDataSource.getPublicTeachers]. Kept as a
/// plain data-source call (skipping the repository/use-case layers other
/// providers here go through) since it's a narrow, one-off fallback rather
/// than a first-class feature.
final sectionTeachersFallbackProvider =
    FutureProvider.family<List<Teacher>, int>((ref, courseId) async {
      final dataSource = ref.watch(coursesRemoteDataSourceProvider);
      return dataSource.getPublicTeachers(courseId);
    });

/// A single lecture's video detail (`GET /lectures/{id}`), keyed by lecture
/// id — only succeeds for an unlocked lecture.
final lectureDetailsProvider = FutureProvider.family<LectureDetails, int>((
  ref,
  id,
) async {
  final useCase = ref.watch(getLectureDetailsUseCaseProvider);
  final result = await useCase(id);
  return switch (result) {
    Ok<LectureDetails>(:final value) => value,
    Err<LectureDetails>(:final failure) => throw failure,
  };
});

/// `GET /courses/{id}`'s lecture list has never been observed to carry a
/// `teacher_id` on any lecture (confirmed via logging — every lecture comes
/// back with only `id, title, duration_seconds, sort_order, is_free_preview,
/// is_locked, description, videos, pdfs, attachments`, no teacher linkage at
/// all). `GET /lectures/{id}` *does* send one (a nested `teacher` object),
/// so [SectionLessonsScreen]'s teacher grouping resolves each lecture's real
/// teacher through this provider instead — piggybacking on
/// [lectureDetailsProvider]'s own cache, so opening the lecture afterwards
/// is still a single fetch, not two. Resolves to `null` (never throws) for a
/// locked lecture the student hasn't unlocked yet — `GET /lectures/{id}`
/// 403s those, and there is currently no other way to learn who taught it.
final lectureTeacherIdProvider = FutureProvider.family<int?, int>((
  ref,
  lectureId,
) async {
  try {
    final details = await ref.watch(lectureDetailsProvider(lectureId).future);
    return details.teacherId;
  } catch (_) {
    return null;
  }
});
