import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? queueCreatedAt(dynamic value) {
  if (value is Timestamp) return value.toDate();
  return null;
}

int compareQueuePriority(
  Map<String, dynamic> first,
  Map<String, dynamic> second,
) {
  final firstCreatedAt = queueCreatedAt(first['createdAt']);
  final secondCreatedAt = queueCreatedAt(second['createdAt']);

  if (firstCreatedAt == null && secondCreatedAt == null) return 0;
  if (firstCreatedAt == null) return 1;
  if (secondCreatedAt == null) return -1;

  return firstCreatedAt.compareTo(secondCreatedAt);
}
