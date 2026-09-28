const educationLevels = {'LGS', 'YKS'};

const lgsSubjects = [
  'TÜRKÇE',
  'MATEMATİK',
  'FEN BİLİMLERİ',
  'T.C. İNKILAP TARİHİ VE ATATÜRKÇÜLÜK',
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

  final className = data['className']?.toString().trim() ?? '';
  final match = RegExp(r'(^|\D)(8|9|10|11|12)(\D|$)').firstMatch(className);
  if (match == null) return null;
  return match.group(2) == '8' ? 'LGS' : 'YKS';
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
  if (scopes.isEmpty || educationLevel == null) return true;
  return scopes.any(
    (scope) =>
        scope['level'] == educationLevel &&
        normalizeEducationSubject(scope['subject']) ==
            normalizeEducationSubject(subject),
  );
}
