const educationLevels = {'LGS', 'YKS'};

const lgsSubjects = [
  'TÜRKÇE',
  'MATEMATİK',
  'FEN BİLİMLERİ',
  'T.C. İNKILAP TARİHİ',
  'DİN KÜLTÜRÜ VE AHLAK BİLGİSİ',
  'İNGİLİZCE',
];

const yksSubjects = [
  'MATEMATİK',
  'FİZİK',
  'KİMYA',
  'BİYOLOJİ',
  'TÜRKÇE',
  'TARİH',
  'COĞRAFYA',
  'GEOMETRİ',
];

String? validEducationLevel(Object? value) {
  final level = value?.toString().trim().toUpperCase();
  return educationLevels.contains(level) ? level : null;
}

String normalizeEducationSubject(Object? value) => value
    .toString()
    .trim()
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ş', 's')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c');

String? inferredStudentEducationLevel(Map<String, dynamic> data) {
  final explicit = validEducationLevel(data['educationLevel']);
  if (explicit != null) return explicit;

  // Öğrenci kayıtları farklı kaynaklardan geldiği için sınıf bilgisi
  // className dışında branch/department gibi alanlarda da bulunabiliyor.
  // Öğretmen kapsamındaki gibi tek bir normalize edilmiş scope üret.
  final classText = [
    data['className'],
    data['class'],
    data['grade'],
    data['branch'],
    data['department'],
  ].where((value) => value != null).join(' ').trim().toUpperCase();

  if (RegExp(r'(^|\W)MEZUN(?=\W|$)').hasMatch(classText)) return 'YKS';

  final gradeMatch =
      RegExp(r'(^|\D)(1[0-2]|[5-9])(?=\D|$)').firstMatch(classText);
  final grade = int.tryParse(gradeMatch?.group(2) ?? '');
  if (grade != null && grade >= 5 && grade <= 8) return 'LGS';
  if (grade != null && grade >= 9 && grade <= 12) return 'YKS';
  return null;
}

List<String> educationLevelsFromData(Map<String, dynamic> data) {
  final levels = <String>[];
  final rawLevels = data['educationLevels'];

  if (rawLevels is List) {
    for (final rawLevel in rawLevels) {
      final level = validEducationLevel(rawLevel);
      if (level != null && !levels.contains(level)) {
        levels.add(level);
      }
    }
  }

  final singleLevel = validEducationLevel(data['educationLevel']);
  if (singleLevel != null && !levels.contains(singleLevel)) {
    levels.add(singleLevel);
  }

  return levels;
}

List<Map<String, String>> teachingScopesFromData(Map<String, dynamic> data) {
  final rawScopes = data['teachingScopes'];
  if (rawScopes is! List) return const [];

  final scopes = <Map<String, String>>[];
  final seen = <String>{};
  for (final rawScope in rawScopes) {
    if (rawScope is! Map) continue;
    final level = validEducationLevel(rawScope['level']);
    final subject = rawScope['subject']?.toString().trim() ?? '';
    if (level == null || subject.isEmpty) continue;
    final key = '$level|${normalizeEducationSubject(subject)}';
    if (seen.add(key)) scopes.add({'level': level, 'subject': subject});
  }
  return scopes;
}

bool teacherMatchesEducationScope(
  Map<String, dynamic> teacher, {
  required String subject,
  String? educationLevel,
}) {
  final scopes = teachingScopesFromData(teacher);
  if (scopes.isEmpty) return true;
  if (educationLevel == null) return false;
  return scopes.any(
    (scope) =>
        scope['level'] == educationLevel &&
        normalizeEducationSubject(scope['subject']) ==
            normalizeEducationSubject(subject),
  );
}

const timeSlotScopes = {'LGS', 'YKS', 'BOTH'};

String timeSlotScopeFromData(Map<Object?, Object?> data) {
  final scope = data['educationLevel']?.toString().trim().toUpperCase() ??
      data['scope']?.toString().trim().toUpperCase() ??
      '';
  return timeSlotScopes.contains(scope) ? scope : 'BOTH';
}

/// Institution schedules predate education-level scoping. Those legacy
/// entries are the existing YKS schedule; LGS slots must always be explicit.
String institutionScheduleScopeFromData(Map<Object?, Object?> data) {
  return timeSlotScopeFromData(data) == 'LGS' ? 'LGS' : 'YKS';
}

bool institutionScheduleSlotMatchesEducationLevel(
  Map<Object?, Object?> data,
  String? educationLevel,
) {
  return educationLevel != null &&
      institutionScheduleScopeFromData(data) == educationLevel;
}

bool timeSlotMatchesEducationLevel(
  Map<Object?, Object?> data,
  String? educationLevel,
) {
  final scope = timeSlotScopeFromData(data);
  return scope == 'BOTH' || (educationLevel != null && scope == educationLevel);
}

bool timeSlotMatchesManagementFilter(
  Map<Object?, Object?> data,
  String scopeFilter,
) {
  if (scopeFilter == 'ALL') return true;
  return timeSlotMatchesEducationLevel(data, scopeFilter);
}

bool teacherCanUseTimeSlotScope(
  Map<String, dynamic> teacher,
  String scope,
) {
  if (scope == 'BOTH') {
    final scopes = teachingScopesFromData(teacher);
    if (scopes.isEmpty) return true;
    final levels = scopes.map((item) => item['level']).toSet();
    return levels.contains('LGS') && levels.contains('YKS');
  }

  if (!educationLevels.contains(scope)) return false;
  final scopes = teachingScopesFromData(teacher);
  return scopes.isEmpty || scopes.any((item) => item['level'] == scope);
}

bool timeIntervalsOverlap({
  required String firstStart,
  required String firstEnd,
  required String secondStart,
  required String secondEnd,
}) {
  int? minutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  final aStart = minutes(firstStart);
  final aEnd = minutes(firstEnd);
  final bStart = minutes(secondStart);
  final bEnd = minutes(secondEnd);
  if (aStart == null || aEnd == null || bStart == null || bEnd == null) {
    return false;
  }
  return aStart < bEnd && bStart < aEnd;
}
