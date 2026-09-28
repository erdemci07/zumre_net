String formatClassNameDisplay(Object? value) {
  final className = value?.toString().trim() ?? '';
  if (className.isEmpty) return '';

  final gradeMatch =
      RegExp(r'^(5|6|7|8|9|10|11|12)-(.*)$').firstMatch(className);
  if (gradeMatch != null) {
    return '${gradeMatch.group(1)}. Sınıf • ${_formatClassDetail(gradeMatch.group(2)!)}';
  }

  final graduateMatch = RegExp(r'^MEZUN-(.*)$').firstMatch(className);
  if (graduateMatch != null) {
    return 'Mezun • ${_formatClassDetail(graduateMatch.group(1)!)}';
  }

  return className;
}

String formatStudentClassDisplay({
  Object? className,
  Object? branch,
  Object? department,
}) {
  final rawClassName = className?.toString().trim() ?? '';
  final rawBranch = branch?.toString().trim() ?? '';
  final rawDepartment = department?.toString().trim() ?? '';
  final values = <String>[
    formatClassNameDisplay(rawClassName),
    if (rawBranch.isNotEmpty && rawBranch != rawClassName) rawBranch,
    if (rawDepartment.isNotEmpty) rawDepartment,
  ];
  return values.where((value) => value.isNotEmpty).join(' • ');
}

String _formatClassDetail(String value) {
  final detail = value.trim();
  final upper = detail.toUpperCase();
  if (upper.startsWith('DERSLİK ')) return 'Derslik${detail.substring(7)}';
  if (upper == 'HAFTA SONU ETÜT') return 'Hafta Sonu Etüt';
  if (upper == 'ÇALIŞMA SALONU') return 'Çalışma Salonu';
  if (upper == 'ETÜT') return 'Etüt';
  return detail;
}
