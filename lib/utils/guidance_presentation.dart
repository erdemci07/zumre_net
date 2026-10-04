const guidanceTerminalStatuses = {'completed', 'cancelled', 'no_show'};

String guidanceStatusValue(Object? value) {
  final status = value?.toString().trim() ?? '';
  return status.isEmpty ? 'pending' : status;
}

String guidanceStatusLabel(String status) {
  switch (guidanceStatusValue(status)) {
    case 'approved':
      return 'Geldi / Bekliyor';
    case 'in_progress':
      return 'Görüşmede';
    case 'completed':
      return 'Tamamlandı';
    case 'no_show':
      return 'Gelmedi';
    case 'cancelled':
      return 'İptal Edildi';
    default:
      return 'Randevulu';
  }
}

int guidanceTimeSortValue(Object? value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(
    value?.toString().trim() ?? '',
  );
  if (match == null) return 24 * 60;
  final hour = int.tryParse(match.group(1)!) ?? 24;
  final minute = int.tryParse(match.group(2)!) ?? 0;
  if (hour > 23 || minute > 59) return 24 * 60;
  return hour * 60 + minute;
}

String guidanceGuardianLabel(Map<String, dynamic>? student) {
  if (student == null) return '';
  return [student['guardianName'], student['guardianSurname']]
      .map((value) => value?.toString().trim() ?? '')
      .where((value) => value.isNotEmpty)
      .join(' ');
}

String guidanceParticipantLabel(Map<String, dynamic> appointment) {
  final source = appointment['source']?.toString().trim() ?? '';
  final fallback = source.startsWith('parent_public') ? 'guardian' : '';
  final raw =
      (appointment['participantType'] ?? appointment['participant'] ?? fallback)
          ?.toString()
          .trim()
          .toLowerCase();
  switch (raw) {
    case 'student':
    case 'öğrenci':
      return 'Katılımcı: Öğrenci';
    case 'guardian':
    case 'veli':
      return 'Katılımcı: Veli';
    case 'both':
    case 'student_guardian':
    case 'öğrenci_veli':
      return 'Katılımcı: Öğrenci ve veli';
    default:
      return '';
  }
}
