Map<String, List<String>> groupAppointmentTimes(Iterable<String> times) {
  final groups = <String, List<String>>{
    'Sabah': [],
    'Öğle': [],
    'Akşam': [],
  };

  for (final time in times) {
    final hour = int.tryParse(time.split(':').first);
    if (hour == null || hour < 0 || hour > 23) continue;
    final group = hour < 12
        ? 'Sabah'
        : hour < 18
            ? 'Öğle'
            : 'Akşam';
    groups[group]!.add(time);
  }

  groups.removeWhere((_, slots) => slots.isEmpty);
  return groups;
}
