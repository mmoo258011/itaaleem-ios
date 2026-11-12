/// The smart UI's hash route for a tapped push, from its FCM `data`
/// (string values). Same order as the web app's `notificationTarget`:
/// 1. `lesson_id` → `/lesson/{id}`
/// 2. `subject_id` with an exam (`content_type=new_exam` or `exam_id`) →
///    `/subject/{id}?tab=exams`
/// 3. `subject_id` → `/subject/{id}`
/// 4. `type=news` → `/news`
/// 5. anything else → `/notifications`
String smartHashForPush(Map<String, dynamic> data) {
  final lessonId = _id(data['lesson_id']);
  if (lessonId != null) return '/lesson/$lessonId';
  final subjectId = _id(data['subject_id']);
  if (subjectId != null) {
    final exam =
        data['content_type'] == 'new_exam' || _id(data['exam_id']) != null;
    return exam ? '/subject/$subjectId?tab=exams' : '/subject/$subjectId';
  }
  if (data['type'] == 'news') return '/news';
  return '/notifications';
}

int? _id(Object? raw) {
  final id = raw is int ? raw : int.tryParse(raw?.toString().trim() ?? '');
  return id != null && id > 0 ? id : null;
}
