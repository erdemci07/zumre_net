import '../models/education_scope.dart';

String userManagementSearchKey(Object? value) => value
    .toString()
    .trim()
    .replaceAll('İ', 'I')
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ş', 's')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c');

class UserManagementFilters {
  const UserManagementFilters({
    this.role = 'all',
    this.search = '',
    this.educationLevel,
    this.className,
    this.branch,
    this.department,
    this.subject,
  });

  final String role;
  final String search;
  final String? educationLevel;
  final String? className;
  final String? branch;
  final String? department;
  final String? subject;

  bool get hasDynamicFilters =>
      educationLevel != null ||
      className != null ||
      branch != null ||
      department != null ||
      subject != null;
}

class StudentFilterOptions {
  const StudentFilterOptions({
    required this.classNames,
    required this.branches,
    required this.departments,
  });
  final List<String> classNames;
  final List<String> branches;
  final List<String> departments;
}

StudentFilterOptions cascadingStudentFilterOptions(
  Iterable<Map<String, dynamic>> users,
  UserManagementFilters filters,
) {
  Iterable<Map<String, dynamic>> matching({String? omit}) {
    final scoped = UserManagementFilters(
      role: 'student',
      search: filters.search,
      educationLevel: omit == 'educationLevel' ? null : filters.educationLevel,
      className: omit == 'className' ? null : filters.className,
      branch: omit == 'branch' ? null : filters.branch,
      department: omit == 'department' ? null : filters.department,
    );
    return users.where((user) => userMatchesManagementFilters(user, scoped));
  }

  return StudentFilterOptions(
    classNames: distinctUserValues(
        matching(omit: 'className'), (user) => user['className']),
    branches:
        distinctUserValues(matching(omit: 'branch'), (user) => user['branch']),
    departments: distinctUserValues(
        matching(omit: 'department'), (user) => user['department']),
  );
}

UserManagementFilters clearInvalidStudentFilterSelections(
  UserManagementFilters filters,
  StudentFilterOptions options,
) =>
    UserManagementFilters(
      role: filters.role,
      search: filters.search,
      educationLevel: filters.educationLevel,
      className: options.classNames.contains(filters.className)
          ? filters.className
          : null,
      branch: options.branches.contains(filters.branch) ? filters.branch : null,
      department: options.departments.contains(filters.department)
          ? filters.department
          : null,
      subject: filters.subject,
    );

List<String> distinctUserValues(
  Iterable<Map<String, dynamic>> users,
  Object? Function(Map<String, dynamic> user) selector,
) {
  final values = <String, String>{};
  for (final user in users) {
    final value = selector(user)?.toString().trim() ?? '';
    if (value.isNotEmpty) {
      values.putIfAbsent(userManagementSearchKey(value), () => value);
    }
  }
  return values.values.toList()..sort();
}

List<String> teacherEducationLevels(Map<String, dynamic> user) {
  final scopes = teachingScopesFromData(user);
  if (scopes.isNotEmpty) {
    return scopes.map((scope) => scope['level']!).toSet().toList()..sort();
  }

  final rawLevels = user['educationLevels'];
  if (rawLevels is! List) return const [];
  return rawLevels.map(validEducationLevel).whereType<String>().toSet().toList()
    ..sort();
}

List<String> teacherSubjectsFromData(Map<String, dynamic> user) {
  final values = <String>[];
  final rawSubjects = user['subjects'];
  if (rawSubjects is List) {
    values.addAll(rawSubjects.map((value) => value.toString()));
  } else if (rawSubjects is String) {
    values.addAll(rawSubjects.split(RegExp(r'[,;/|]')));
  }
  values.addAll(teachingScopesFromData(user).map((scope) => scope['subject']!));
  return values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
}

List<String> distinctTeacherSubjects(Iterable<Map<String, dynamic>> users) {
  final values = <String, String>{};
  for (final user in users) {
    for (final subject in teacherSubjectsFromData(user)) {
      values.putIfAbsent(userManagementSearchKey(subject), () => subject);
    }
  }
  return values.values.toList()..sort();
}

bool userMatchesManagementFilters(
  Map<String, dynamic> user,
  UserManagementFilters filters,
) {
  final role = user['role']?.toString() ?? '';
  if (filters.role != 'all' && role != filters.role) return false;

  final searchable = [
    user['fullName'],
    user['name'],
    user['surname'],
    user['username'],
    user['email'],
    user['className'],
    user['branch'],
    user['department'],
    ...teacherSubjectsFromData(user),
  ].where((value) => value != null).join(' ');
  final search = userManagementSearchKey(filters.search);
  if (search.isNotEmpty &&
      !userManagementSearchKey(searchable).contains(search)) {
    return false;
  }

  bool matchesValue(Object? value, String? selected) =>
      selected == null ||
      userManagementSearchKey(value) == userManagementSearchKey(selected);

  if (role == 'student') {
    return matchesValue(
            inferredStudentEducationLevel(user), filters.educationLevel) &&
        matchesValue(user['className'], filters.className) &&
        matchesValue(user['branch'], filters.branch) &&
        matchesValue(user['department'], filters.department);
  }

  if (role == 'teacher') {
    final levels = teacherEducationLevels(user);
    final matchesLevel = filters.educationLevel == null ||
        levels.contains(filters.educationLevel);
    final subject = filters.subject;
    final matchesSubject = subject == null ||
        teacherSubjectsFromData(user).any(
          (value) =>
              userManagementSearchKey(value) ==
              userManagementSearchKey(subject),
        );
    return matchesLevel && matchesSubject;
  }

  return true;
}
