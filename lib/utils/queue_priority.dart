import 'package:cloud_firestore/cloud_firestore.dart';

const Duration queueAgingProtection = Duration(minutes: 10);

int queueQuestionWeight(dynamic value) {
  if (value is int) return value.clamp(1, 4).toInt();
  if (value is num) return value.toInt().clamp(1, 4).toInt();

  final parsed = int.tryParse('$value');
  return (parsed ?? 1).clamp(1, 4).toInt();
}

DateTime? queueCreatedAt(dynamic value) {
  if (value is Timestamp) return value.toDate();
  return null;
}

int compareQueuePriority(
  Map<String, dynamic> first,
  Map<String, dynamic> second, {
  DateTime? now,
}) {
  final referenceNow = now ?? DateTime.now();
  final firstCreatedAt = queueCreatedAt(first['createdAt']);
  final secondCreatedAt = queueCreatedAt(second['createdAt']);
  final firstAged = firstCreatedAt != null &&
      referenceNow.difference(firstCreatedAt) >= queueAgingProtection;
  final secondAged = secondCreatedAt != null &&
      referenceNow.difference(secondCreatedAt) >= queueAgingProtection;

  if (firstAged != secondAged) {
    return firstAged ? -1 : 1;
  }

  if (!firstAged && !secondAged) {
    final questionCompare = queueQuestionWeight(first['questionCount'])
        .compareTo(queueQuestionWeight(second['questionCount']));
    if (questionCompare != 0) return questionCompare;
  }

  if (firstCreatedAt == null && secondCreatedAt == null) return 0;
  if (firstCreatedAt == null) return 1;
  if (secondCreatedAt == null) return -1;

  return firstCreatedAt.compareTo(secondCreatedAt);
}
