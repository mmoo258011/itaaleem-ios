import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/utils/result.dart';
import 'package:itaaleem/features/courses/data/datasources/courses_remote_data_source.dart';
import 'package:itaaleem/features/courses/domain/entities/available_course.dart';
import 'package:itaaleem/features/courses/domain/entities/course.dart';
import 'package:itaaleem/features/courses/domain/entities/course_details.dart';
import 'package:itaaleem/features/courses/domain/entities/lecture_details.dart';
import 'package:itaaleem/features/courses/domain/repositories/courses_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CoursesRepositoryImpl implements CoursesRepository {
  CoursesRepositoryImpl(this._remoteDataSource);

  final CoursesRemoteDataSource _remoteDataSource;

  @override
  Future<Result<List<Course>>> getCourses() async {
    try {
      final courses = await _remoteDataSource.getCourses();
      return Ok(courses);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Result<CourseDetails>> getCourseDetails(int id) async {
    try {
      final details = await _remoteDataSource.getCourseDetails(id);
      return Ok(details);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Result<List<CourseExam>>> getCourseExams(int courseId) async {
    try {
      final exams = await _remoteDataSource.getCourseExams(courseId);
      return Ok(exams);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Result<List<AvailableCourse>>> getAvailableCourses() async {
    try {
      final courses = await _remoteDataSource.getAvailableCourses();
      return Ok(courses);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Result<LectureDetails>> getLectureDetails(int id) async {
    try {
      final details = await _remoteDataSource.getLectureDetails(id);
      return Ok(details);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Result<LecturePlaybackInfo>> getLecturePlayback(int lectureId) async {
    try {
      final info = await _remoteDataSource.getLecturePlayback(lectureId);
      return Ok(info);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Result<LectureProgress>> getLectureProgress(int lectureId) async {
    try {
      final progress = await _remoteDataSource.getLectureProgress(lectureId);
      return Ok(progress);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Result<void>> postLectureProgress(
    int lectureId, {
    required int positionSeconds,
    required int durationSeconds,
    required double progressPercentage,
  }) async {
    try {
      await _remoteDataSource.postLectureProgress(
        lectureId,
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds,
        progressPercentage: progressPercentage,
      );
      return const Ok(null);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Result<void>> postPdfProgress(
    int pdfId, {
    required int lastPage,
    required double readPercentage,
  }) async {
    try {
      await _remoteDataSource.postPdfProgress(
        pdfId,
        lastPage: lastPage,
        readPercentage: readPercentage,
      );
      return const Ok(null);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Result<String>> requestEnrollment(int courseId) async {
    try {
      final message = await _remoteDataSource.requestEnrollment(courseId);
      return Ok(message);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  Failure _failureOf(DioException e) {
    final error = e.error;
    if (error is Failure) return error;
    return const NetworkFailure('تعذر الاتصال بالسيرفر، تحقق من الإنترنت');
  }
}

final coursesRepositoryProvider = Provider<CoursesRepository>((ref) {
  final remoteDataSource = ref.watch(coursesRemoteDataSourceProvider);
  return CoursesRepositoryImpl(remoteDataSource);
});
