import 'class_name_display.dart';
import 'user_management_filters.dart';

class GuidanceStudentGroup {
  const GuidanceStudentGroup({
    required this.key,
    required this.label,
    required this.students,
  });

  final String key;
  final String label;
  final List<Map<String, dynamic>> students;
}

List<GuidanceStudentGroup> groupGuidanceStudents(
  Iterable<Map<String, dynamic>> students, {
  String query = '',
}) {
  final normalizedQuery = userManagementSearchKey(query);
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final student in students) {
    final name = [student['fullName'], student['name'], student['surname']]
        .whereType<Object>()
        .join(' ');
    final classLabel = formatStudentClassDisplay(
      className: student['className'],
      branch: student['branch'],
      department: student['department'],
    );
    if (normalizedQuery.isNotEmpty &&
        !userManagementSearchKey('$name $classLabel')
            .contains(normalizedQuery)) {
      continue;
    }
    final className = student['className']?.toString().trim() ?? '';
    final branch = student['branch']?.toString().trim() ?? '';
    final department = student['department']?.toString().trim() ?? '';
    final key = '$className\u0000$branch\u0000$department';
    groups.putIfAbsent(key, () => []).add(student);
  }

  final result = groups.entries.map((entry) {
    final first = entry.value.first;
    final label = formatStudentClassDisplay(
      className: first['className'],
      branch: first['branch'],
      department: first['department'],
    );
    final sorted = [...entry.value]
      ..sort((a, b) => _studentName(a).compareTo(_studentName(b)));
    return GuidanceStudentGroup(
      key: entry.key,
      label: label.isEmpty ? 'Sınıf bilgisi yok' : label,
      students: sorted,
    );
  }).toList()
    ..sort((a, b) => a.label.compareTo(b.label));
  return result;
}

String guidanceStudentName(Map<String, dynamic> student) =>
    _studentName(student);

String _studentName(Map<String, dynamic> student) {
  final fullName = student['fullName']?.toString().trim() ?? '';
  if (fullName.isNotEmpty) return fullName;
  return [student['name'], student['surname']]
      .map((value) => value?.toString().trim() ?? '')
      .where((value) => value.isNotEmpty)
      .join(' ');
}
