import 'package:itaaleem/core/utils/result.dart';
import 'package:itaaleem/features/courses/domain/entities/available_course.dart';
import 'package:itaaleem/features/courses/domain/entities/course.dart';
import 'package:itaaleem/features/courses/domain/entities/course_details.dart';
import 'package:itaaleem/features/courses/domain/entities/lecture_details.dart';

abstract interface class CoursesRepository {
  Future<Result<List<Course>>> getCourses();

  Future<Result<CourseDetails>> getCourseDetails(int id);

  /// `GET /courses/{id}/exams` — the course's exams plus each one's attempt
  /// status (`attempted`, `score`, `passed`).
  Future<Result<List<CourseExam>>> getCourseExams(int courseId);

  /// `GET /lectures/{id}` — only succeeds for an unlocked lecture.
  Future<Result<LectureDetails>> getLectureDetails(int id);

  /// `GET /lectures/{id}/playback` — a signed streaming URL for the
  /// lecture's video.
  Future<Result<LecturePlaybackInfo>> getLecturePlayback(int lectureId);

  /// `GET /lectures/{id}/progress` — the lecture-level saved position.
  Future<Result<LectureProgress>> getLectureProgress(int lectureId);

  /// `POST /lectures/{id}/progress` — reports lecture-level playback
  /// progress.
  Future<Result<void>> postLectureProgress(
    int lectureId, {
    required int positionSeconds,
    required int durationSeconds,
    required double progressPercentage,
  });

  /// `POST /pdfs/{id}/progress` — reports how far into the PDF the student
  /// has read.
  Future<Result<void>> postPdfProgress(
    int pdfId, {
    required int lastPage,
    required double readPercentage,
  });

  /// The full published catalog, enrolled or not (`GET /courses/available`).
  Future<Result<List<AvailableCourse>>> getAvailableCourses();

  /// Requests enrollment in a course (`POST /courses/{id}/request`),
  /// creating a pending registration for admin approval. Returns the
  /// server's confirmation message.
  Future<Result<String>> requestEnrollment(int courseId);
}
