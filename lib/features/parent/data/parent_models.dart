/// Wire models of "متابعة ولي الأمر" — read-only, exactly the documented
/// fields.
library;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

double _double(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

String _str(Object? v) => v is String ? v : (v == null ? '' : '$v');

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

class ParentCodeInfo {
  const ParentCodeInfo({
    required this.parentCode,
    required this.linkedParentsCount,
    this.message,
  });

  final String parentCode;
  final int linkedParentsCount;

  /// `regenerate`'s confirmation text.
  final String? message;

  factory ParentCodeInfo.fromJson(Map<String, dynamic> json) => ParentCodeInfo(
    parentCode: _str(json['parent_code']),
    linkedParentsCount: _int(json['linked_parents_count']),
    message: json['message'] as String?,
  );
}

class ParentChild {
  const ParentChild({
    required this.id,
    required this.name,
    required this.course,
    required this.center,
    this.lastLoginAt,
  });

  final int id;
  final String name;
  final String course;
  final String center;
  final DateTime? lastLoginAt;

  factory ParentChild.fromJson(Map<String, dynamic> json) => ParentChild(
    id: _int(json['id']),
    name: _str(json['name']),
    course: _str(json['course']),
    center: _str(json['center']),
    lastLoginAt: _date(json['last_login_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'course': course,
    'center': center,
    'last_login_at': lastLoginAt?.toIso8601String(),
  };
}

class Guardian {
  const Guardian({
    required this.id,
    required this.name,
    required this.mobile,
    required this.children,
  });

  final int id;
  final String name;
  final String mobile;
  final List<ParentChild> children;

  factory Guardian.fromJson(Map<String, dynamic> json) {
    final list = json['children'];
    return Guardian(
      id: _int(json['id']),
      name: _str(json['name']),
      mobile: _str(json['mobile']),
      children: list is List
          ? list
                .whereType<Map<String, dynamic>>()
                .map(ParentChild.fromJson)
                .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mobile': mobile,
    'children': [for (final c in children) c.toJson()],
  };
}

class GuardianAuthResult {
  const GuardianAuthResult({required this.token, required this.guardian});

  final String token;
  final Guardian guardian;

  factory GuardianAuthResult.fromJson(Map<String, dynamic> json) =>
      GuardianAuthResult(
        token: _str(json['token']),
        guardian: Guardian.fromJson(
          (json['guardian'] as Map<String, dynamic>?) ?? const {},
        ),
      );
}

class ChildSubjectProgress {
  const ChildSubjectProgress({
    required this.id,
    required this.name,
    required this.lecturesCount,
    required this.completedLectures,
    required this.progressPercentage,
  });

  final int id;
  final String name;
  final int lecturesCount;
  final int completedLectures;

  /// 0–100.
  final double progressPercentage;

  factory ChildSubjectProgress.fromJson(Map<String, dynamic> json) =>
      ChildSubjectProgress(
        id: _int(json['id']),
        name: _str(json['name']),
        lecturesCount: _int(json['lectures_count']),
        completedLectures: _int(json['completed_lectures']),
        progressPercentage: _double(json['progress_percentage']),
      );
}

class ChildRecentLecture {
  const ChildRecentLecture({
    required this.lecture,
    required this.subject,
    this.watchedAt,
  });

  final String lecture;
  final String subject;
  final DateTime? watchedAt;

  factory ChildRecentLecture.fromJson(Map<String, dynamic> json) =>
      ChildRecentLecture(
        lecture: _str(json['lecture']),
        subject: _str(json['subject']),
        watchedAt: _date(json['watched_at']),
      );
}

class ChildExamResult {
  const ChildExamResult({
    required this.exam,
    required this.subject,
    required this.score,
    required this.total,
    required this.percentage,
    this.date,
  });

  final String exam;
  final String subject;
  final num score;
  final num total;

  /// 0–100.
  final double percentage;
  final DateTime? date;

  factory ChildExamResult.fromJson(
    Map<String, dynamic> json,
  ) => ChildExamResult(
    exam: _str(json['exam']),
    subject: _str(json['subject']),
    score: json['score'] is num ? json['score'] as num : _double(json['score']),
    total: json['total'] is num ? json['total'] as num : _double(json['total']),
    percentage: _double(json['percentage']),
    date: _date(json['date']),
  );
}

class ChildDetails {
  const ChildDetails({
    required this.child,
    required this.subjects,
    required this.recentLectures,
    required this.examResults,
  });

  final ParentChild child;
  final List<ChildSubjectProgress> subjects;
  final List<ChildRecentLecture> recentLectures;
  final List<ChildExamResult> examResults;

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) f) =>
      raw is List ? raw.whereType<Map<String, dynamic>>().map(f).toList() : [];

  factory ChildDetails.fromJson(Map<String, dynamic> json) => ChildDetails(
    child: ParentChild.fromJson(
      (json['child'] as Map<String, dynamic>?) ?? const {},
    ),
    subjects: _list(json['subjects'], ChildSubjectProgress.fromJson),
    recentLectures: _list(json['recent_lectures'], ChildRecentLecture.fromJson),
    examResults: _list(json['exam_results'], ChildExamResult.fromJson),
  );
}
