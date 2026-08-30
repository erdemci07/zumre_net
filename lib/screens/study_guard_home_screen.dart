import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class StudyGuardHomeScreen extends StatefulWidget {
  const StudyGuardHomeScreen({super.key});

  @override
  State<StudyGuardHomeScreen> createState() => _StudyGuardHomeScreenState();
}

class _StudyGuardHomeScreenState extends State<StudyGuardHomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _staffName;
  String? _staffRole;
  String? _selectedDutyTeacherId=null;
String? _selectedDutyTeacherName=null;
String _activeStudySlotText = 'Etüt saati';


  String? _activeSessionId;

  bool _isStudyOpenNow = false;
String _studyScheduleMessage = 'Etüt saatleri yönetici panelindeki programa göre otomatik takip edilir.';
  Timer? _elapsedTimer;
  Timer? _scheduleTimer;
final Set<String> _removingStudentIds = {};
  bool _isProcessing = false;
  StreamSubscription<DocumentSnapshot>? _runtimeStateSubscription;
  StreamSubscription<DocumentSnapshot>? _scheduleSubscription;
  Map<String, dynamic>? _cachedScheduleData;
  bool? _lastLocalStudyOpen;
  static const Duration _runtimeStateMaxAge = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    _initPage();
  }

Future<void> _initPage() async {
  await _loadStaffInfo();
  await _checkStudySchedule();
  _listenZumreSchedule();
  _listenRuntimeScheduleState();

  _scheduleTimer = Timer.periodic(
    const Duration(seconds: 5),
    (_) => _applyLocalStudyScheduleFromCache(runSessionSideEffects: true),
  );
}

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _scheduleTimer?.cancel();
    _runtimeStateSubscription?.cancel();
    _scheduleSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadStaffInfo() async {
    final uid = _auth.currentUser!.uid;

    final doc = await _firestore.collection('users').doc(uid).get();
    final data = doc.data() ?? {};

    if (!mounted) return;

    setState(() {
      _staffName =
          data['fullName'] ?? data['name'] ?? data['email'] ?? 'Etüt Görevlisi';
      _staffRole = data['role'];
      _selectedDutyTeacherId = data['dutyTeacherId'] as String?;
      _selectedDutyTeacherName = data['dutyTeacherName'] as String?;
    });
  }

  int _timeToMinutes(String time) {
    final parts = time.split(':');

    if (parts.length != 2) return 0;

    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;

    return hour * 60 + minute;
  }

List<String> _teacherSubjectsFromData(Map<String, dynamic> data) {
  final subjects = <String>[];

  void addSubject(dynamic value) {
    final subject = value?.toString().trim() ?? '';
    if (subject.isNotEmpty && !subjects.contains(subject)) {
      subjects.add(subject);
    }
  }

  final rawSubjects = data['subjects'];

  if (rawSubjects is List) {
    for (final item in rawSubjects) {
      addSubject(item);
    }
  } else if (rawSubjects is String && rawSubjects.trim().isNotEmpty) {
    for (final item in rawSubjects.split(RegExp(r'[,;/|]'))) {
      addSubject(item);
    }
  }

  addSubject(data['branch']);
  addSubject(data['subject']);

  return subjects;
}

bool _isNowInSlots(
  DateTime now,
  List<Map<String, dynamic>> slots,
) {
  final nowMinutes = now.hour * 60 + now.minute;

  for (final slot in slots) {
    final start = _timeToMinutes('${slot['start']}');
    final end = _timeToMinutes('${slot['end']}');

    if (end <= start) continue;

    if (nowMinutes >= start && nowMinutes < end) {
      return true;
    }
  }

  return false;
}

bool _isFreshRuntimeState(Map<String, dynamic>? data) {
  if (data == null ||
      data['isStudyOpen'] is! bool ||
      data['updatedAt'] is! Timestamp) {
    return false;
  }

  final updatedAt = (data['updatedAt'] as Timestamp).toDate();
  final age = DateTime.now().difference(updatedAt);

  return age >= Duration.zero && age <= _runtimeStateMaxAge;
}

Map<String, dynamic>? _localStudyScheduleState() {
  final data = _cachedScheduleData;
  if (data == null) return null;

  final now = DateTime.now();
  final isWeekend =
      now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
  final rawSlots = isWeekend
      ? List.from(data['weekendStudySlots'] ?? [])
      : List.from(data['weekdayStudySlots'] ?? []);
  final slots = rawSlots.map((e) => Map<String, dynamic>.from(e)).toList();
  final isOpen = _isNowInSlots(now, slots);

  var slotText = 'Etüt saati';

  for (final slot in slots) {
    final start = '${slot['start']}';
    final end = '${slot['end']}';
    final startMin = _timeToMinutes(start);
    final endMin = _timeToMinutes(end);
    final nowMin = now.hour * 60 + now.minute;

    if (endMin > startMin && nowMin >= startMin && nowMin < endMin) {
      slotText = '$start - $end';
      break;
    }
  }

  final message = slots.isEmpty
      ? isWeekend
          ? 'Hafta sonu etüt saati tanımlı değil.'
          : 'Hafta içi etüt saati tanımlı değil.'
      : isOpen
          ? 'Etüt saati aktif. Yoklama alabilirsiniz.'
          : 'Şu an etüt saati aktif değil.';

  return {
    'isOpen': isOpen,
    'slotText': slotText,
    'message': message,
  };
}

Future<bool> _applyLocalStudyScheduleFromCache({
  required bool runSessionSideEffects,
}) async {
  final state = _localStudyScheduleState();
  if (state == null) return false;

  final isOpen = state['isOpen'] == true;
  final previousOpen = _lastLocalStudyOpen;
  _lastLocalStudyOpen = isOpen;

  if (mounted) {
    setState(() {
      _isStudyOpenNow = isOpen;
      _activeStudySlotText = state['slotText']?.toString() ?? 'Etüt saati';
      _studyScheduleMessage = state['message']?.toString() ??
          'Etüt saatleri yönetici panelindeki programa göre otomatik takip edilir.';
    });
  }

  if (runSessionSideEffects &&
      (previousOpen == null || previousOpen != isOpen)) {
    if (isOpen) {
      await _ensureActiveSession();
    } else {
      await _finishStudySessionSilently(autoEnded: true);
    }
  }

  return true;
}

void _listenZumreSchedule() {
  _scheduleSubscription?.cancel();
  _scheduleSubscription = _firestore
      .collection('settings')
      .doc('zumreSchedule')
      .snapshots()
      .listen((snapshot) async {
    if (!snapshot.exists) {
      _cachedScheduleData = null;
      if (!mounted) return;
      setState(() {
        _isStudyOpenNow = false;
        _activeStudySlotText = 'Etüt saati';
        _studyScheduleMessage =
            'Etüt saatleri henüz yönetici tarafından ayarlanmamış.';
      });
      return;
    }

    _cachedScheduleData = snapshot.data() ?? {};
    await _applyLocalStudyScheduleFromCache(runSessionSideEffects: true);
  }, onError: (_) {});
}

Future<bool> _applyRuntimeStudyState(Map<String, dynamic>? data) async {
  if (!_isFreshRuntimeState(data)) return false;
  if (_cachedScheduleData != null) {
    return _applyLocalStudyScheduleFromCache(runSessionSideEffects: true);
  }

  final isOpen = data!['isStudyOpen'] == true;

  if (!mounted) return true;

  setState(() {
    _isStudyOpenNow = isOpen;
    _activeStudySlotText = 'Etüt saati';
    _studyScheduleMessage = isOpen
        ? 'Etüt saati aktif. Yoklama alabilirsiniz.'
        : 'Şu an etüt saati aktif değil.';
  });

  if (isOpen) {
    await _ensureActiveSession();
  } else {
    await _finishStudySessionSilently(autoEnded: true);
  }

  return true;
}

void _listenRuntimeScheduleState() {
  _runtimeStateSubscription?.cancel();
  _runtimeStateSubscription = _firestore
      .collection('settings')
      .doc('runtimeState')
      .snapshots()
      .listen((snapshot) async {
    final applied = await _applyRuntimeStudyState(snapshot.data());

    if (!applied) {
      await _checkLocalStudySchedule();
    }
  }, onError: (_) async {
    await _checkLocalStudySchedule();
  });
}

Future<void> _checkStudySchedule() async {
  if (await _applyLocalStudyScheduleFromCache(runSessionSideEffects: true)) {
    return;
  }

  try {
    final runtimeDoc =
        await _firestore.collection('settings').doc('runtimeState').get();

    if (await _applyRuntimeStudyState(runtimeDoc.data())) {
      return;
    }
  } catch (_) {}

  await _checkLocalStudySchedule();
}

Future<void> _checkLocalStudySchedule() async {
  try {
    final now = DateTime.now();
    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

    final doc =
        await _firestore.collection('settings').doc('zumreSchedule').get();

    if (!doc.exists) {
      if (!mounted) return;
      setState(() {
        _isStudyOpenNow = false;
        _studyScheduleMessage =
            'Etüt saatleri henüz yönetici tarafından ayarlanmamış.';
      });
      return;
    }

    final data = doc.data() ?? {};
    _cachedScheduleData = data;

    final rawSlots = isWeekend
        ? List.from(data['weekendStudySlots'] ?? [])
        : List.from(data['weekdayStudySlots'] ?? []);

    final slots = rawSlots
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final isOpen = _isNowInSlots(now, slots);
    
    String slotText = 'Etüt saati';

for (final slot in slots) {
  final start = '${slot['start']}';
  final end = '${slot['end']}';

  final startMin = _timeToMinutes(start);
  final endMin = _timeToMinutes(end);
  final nowMin = now.hour * 60 + now.minute;

  if (endMin > startMin &&
      nowMin >= startMin &&
      nowMin < endMin) {
    slotText = '$start - $end';
    break;
  }
}

    if (!mounted) return;

    setState(() {
      _isStudyOpenNow = isOpen;
      _activeStudySlotText = slotText;

      if (slots.isEmpty) {
        _studyScheduleMessage = isWeekend
            ? 'Hafta sonu etüt saati tanımlı değil.'
            : 'Hafta içi etüt saati tanımlı değil.';
      } else {
        _studyScheduleMessage = isOpen
            ? 'Etüt saati aktif. Yoklama alabilirsiniz.'
            : 'Şu an etüt saati aktif değil.';
      }
    });

    _lastLocalStudyOpen = isOpen;

    if (isOpen) {
      await _ensureActiveSession();
    } else {
      await _finishStudySessionSilently(autoEnded: true);
    }
  } catch (e) {
    if (!mounted) return;

    setState(() {
      _isStudyOpenNow = false;
      _studyScheduleMessage = 'Etüt saati kontrol edilemedi: $e';
    });
  }
}
Future<void> _ensureActiveSession() async {
  if (!_isStudyOpenNow) return;
  if (_activeSessionId != null) return;

  final uid = _auth.currentUser!.uid;

  final snapshot = await _firestore
      .collection('studySessions')
      .where('staffId', isEqualTo: uid)
      .where('status', isEqualTo: 'active')
      .limit(1)
      .get();

  if (snapshot.docs.isNotEmpty) {
    final doc = snapshot.docs.first;
    final data = doc.data();

    if (!mounted) return;

    setState(() {
      _activeSessionId = doc.id;
      _selectedDutyTeacherId =
          data['dutyTeacherId']?.toString();
      _selectedDutyTeacherName =
          data['dutyTeacherName']?.toString();
    });

    return; // Bu satır kritik
  }

  await _startStudySession();
}

  Future<void> _startStudySession() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final uid = _auth.currentUser!.uid;

final docRef = await _firestore.collection('studySessions').add({
  'staffId': uid,
  'staffName': _staffName ?? 'Etüt Görevlisi',
  'staffRole': _staffRole ?? '',
  'status': 'active',
  'startedAt': Timestamp.now(),
  'endedAt': null,
  'studentCount': 0,
  'activeStudentCount': 0,
  'dutyTeacherId': null,
  'dutyTeacherName': null,
  'dutyTeacherPreviousStatus': null,
  'createdAt': FieldValue.serverTimestamp(),
});
      if (!mounted) return;

      setState(() {
        _activeSessionId = docRef.id;
      });
    } catch (e) {
      _showSnack('Etüt oturumu başlatılamadı: $e');
    } finally {
      if (mounted) {
        setState(() {
          _studyScheduleMessage = _isStudyOpenNow
              ? 'Etüt saati aktif. Yoklama alabilirsiniz.'
              : 'Şu an etüt saati aktif değil.';
          _isProcessing = false;
        });
      }
    }
  }
Future<void> _finishStudySessionSilently({
  required bool autoEnded,
}) async {
  if (_isProcessing) return;

  String? sessionId = _activeSessionId;

  if (sessionId == null) {
    final uid = _auth.currentUser!.uid;

    final snapshot = await _firestore
        .collection('studySessions')
        .where('staffId', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return;

    sessionId = snapshot.docs.first.id;
  }

  setState(() {
    _isProcessing = true;
  });

  try {
    final sessionRef =
        _firestore.collection('studySessions').doc(sessionId);

    final sessionDoc = await sessionRef.get();
    final sessionData = sessionDoc.data() ?? {};

    final dutyTeacherId = sessionData['dutyTeacherId'];
    final previousStatus =
        sessionData['dutyTeacherPreviousStatus'] ?? 'available';

    final studentsSnapshot =
        await sessionRef.collection('students').get();

    final batch = _firestore.batch();

for (final doc in studentsSnapshot.docs) {
  final data = doc.data();
  final status = data['status']?.toString() ?? 'present';

  batch.update(_firestore.collection('users').doc(doc.id), {
    'isInStudySession': false,
    'activeStudySessionId': null,
  });

  if (status == 'present') {
    batch.update(doc.reference, {
      'status': 'completed',
      'checkedOutAt': Timestamp.now(),
    });
  }
}

    if (dutyTeacherId != null) {
      batch.update(
        _firestore.collection('users').doc(dutyTeacherId),
        {
          'teacherStatus': previousStatus,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    }

batch.update(sessionRef, {
  'status': 'completed',
  'endedAt': Timestamp.now(),
  'autoEnded': autoEnded,
  'activeStudentCount': 0,
  'dutyTeacherId': null,
  'dutyTeacherName': null,
  'dutyTeacherPreviousStatus': null,
  'updatedAt': FieldValue.serverTimestamp(),
});

    await batch.commit();

    if (!mounted) return;

    setState(() {
      _activeSessionId = null;
      _selectedDutyTeacherId = null;
      _selectedDutyTeacherName = null;
    });
  } catch (e) {
    _showSnack('Etüt kapatılamadı: $e');
  } finally {
    if (mounted) {
      setState(() {
        _isProcessing = false;
      });
    }
  }
}
  Future<bool> _addStudentToStudy(DocumentSnapshot doc) async {
    if (_activeSessionId == null) return false;
    if (!_isStudyOpenNow) {
      _showSnack('Şu an etüt saati aktif değil.');
      return false;
    }

    final data = doc.data() as Map<String, dynamic>;

    if (data['isInStudySession'] == true) {
      _showSnack('Bu öğrenci zaten etütte görünüyor.');
      return false;
    }

    final activeQueueSnapshot = await _firestore
        .collection('queues')
        .where('studentId', isEqualTo: doc.id)
        .where('status', whereIn: ['waiting', 'in_progress'])
        .limit(1)
        .get();

    if (activeQueueSnapshot.docs.isNotEmpty) {
      _showSnack('Bu öğrencinin aktif zümre sırası var. Etüte alınamaz.');
      return false;
    }

    final sessionId = _activeSessionId!;

    final sessionRef =
        _firestore.collection('studySessions').doc(sessionId);
    final sessionStudentRef =
        sessionRef.collection('students').doc(doc.id);
    final userRef = _firestore.collection('users').doc(doc.id);

    try {
      final wasRejoin =
          await _firestore.runTransaction<bool>((transaction) async {
        final userSnapshot = await transaction.get(userRef);
        final existingSnapshot = await transaction.get(sessionStudentRef);
        final sessionSnapshot = await transaction.get(sessionRef);

        final freshUserData = userSnapshot.data() ?? {};
        final sessionData = sessionSnapshot.data() ?? {};

        if (freshUserData['isInStudySession'] == true) {
          throw StateError('Bu öğrenci zaten etütte görünüyor.');
        }

        if (!sessionSnapshot.exists || sessionData['status'] != 'active') {
          throw StateError('Aktif etüt oturumu bulunamadı.');
        }

        if (existingSnapshot.exists) {
          final existingData = existingSnapshot.data() ?? {};
          final existingStatus =
              existingData['status']?.toString() ?? 'present';

          if (existingStatus == 'present') {
            throw StateError('Bu öğrenci zaten etütte görünüyor.');
          }

          transaction.update(sessionStudentRef, {
            'status': 'present',
            'checkedAt': FieldValue.serverTimestamp(),
            'checkedOutAt': null,
            'rejoinedAt': FieldValue.serverTimestamp(),
          });

          transaction.update(userRef, {
            'isInStudySession': true,
            'activeStudySessionId': sessionId,
          });

          transaction.update(sessionRef, {
            'activeStudentCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          return true;
        }

        transaction.set(sessionStudentRef, {
          'studentId': doc.id,
          'studentName': data['fullName'] ?? data['name'] ?? 'Öğrenci',
          'className': data['className'] ?? '',
          'branch': data['branch'] ?? '',
          'department': data['department'] ?? '',
          'username': data['username'] ?? '',
          'checkedAt': FieldValue.serverTimestamp(),
          'checkedOutAt': null,
          'status': 'present',
        });

        transaction.update(userRef, {
          'isInStudySession': true,
          'activeStudySessionId': sessionId,
        });

        transaction.update(sessionRef, {
          'studentCount': FieldValue.increment(1),
          'activeStudentCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        return false;
      });

      if (!mounted) return false;

      _showSnack(
        wasRejoin
            ? 'Öğrenci yeniden etüte alındı.'
            : 'Öğrenci etüte alındı.',
      );
      return true;
    } on StateError catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Öğrenci etüte alınamadı: $e');
    }

    return false;
  }
Future<void> _removeStudentFromStudy(
  String studentId,
  String studentName,
) async {
  if (_activeSessionId == null) return;
  if (_removingStudentIds.contains(studentId)) return;

  final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 22),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 430),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF063B3B),
                    Color(0xFF008A8A),
                    Color(0xFF05272D),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.orangeAccent.withOpacity(0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.person_remove_alt_1_rounded,
                      color: Colors.orangeAccent,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Öğrenci Etütten Çıkarılsın mı?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$studentName isimli öğrenci etütten çıkarılacak ve yeniden zümre sırası alabilecek.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Vazgeç'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: const Icon(Icons.person_remove_rounded),
                          label: const Text('Etütten Çıkar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            foregroundColor: const Color(0xFF063B3B),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ) ??
      false;

  if (!confirm) return;

  setState(() {
    _removingStudentIds.add(studentId);
  });

  try {
    final sessionId = _activeSessionId!;

    final studentRef = _firestore
        .collection('studySessions')
        .doc(sessionId)
        .collection('students')
        .doc(studentId);

    final userRef = _firestore.collection('users').doc(studentId);
    final sessionRef =
        _firestore.collection('studySessions').doc(sessionId);
    final didRemove = await _firestore.runTransaction<bool>((transaction) async {
      final studentSnapshot = await transaction.get(studentRef);
      final sessionSnapshot = await transaction.get(sessionRef);
      final studentData = studentSnapshot.data();

      if (!studentSnapshot.exists || studentData?['status'] != 'present') {
        return false;
      }

      final sessionData = sessionSnapshot.data() ?? {};
      final currentActiveCount =
          (sessionData['activeStudentCount'] as num?)?.toInt() ??
              (sessionData['studentCount'] as num?)?.toInt() ??
              0;
      final nextActiveCount =
          currentActiveCount > 0 ? currentActiveCount - 1 : 0;

      transaction.update(studentRef, {
        'status': 'left',
        'checkedOutAt': FieldValue.serverTimestamp(),
      });

      transaction.update(userRef, {
        'isInStudySession': false,
        'activeStudySessionId': null,
      });

      transaction.update(sessionRef, {
        'activeStudentCount': nextActiveCount,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF008A8A),
        content: Text(
          didRemove
              ? '$studentName etütten çıkarıldı.'
              : '$studentName zaten etütte görünmüyor.',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text('Öğrenci etütten çıkarılamadı: $e'),
      ),
    );
  } finally {
    if (mounted) {
      setState(() {
        _removingStudentIds.remove(studentId);
      });
    }
  }
}
  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
Widget _header() {
  return Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(22),
    decoration: _cardDecoration(),
    child: Row(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withOpacity(0.16),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.cyanAccent.withOpacity(0.35)),
          ),
          child: const Icon(
            Icons.fact_check_rounded,
            color: Colors.cyanAccent,
            size: 32,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hoş geldiniz',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _staffName ?? 'Etüt Görevlisi',
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Etüt yoklaması ve öğrenci takibi',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 8),
              _studyStatusBadge(),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          children: [
            Tooltip(
              message:
                  'Kurumda branş öğretmeniyseniz seçiniz. Değilseniz boş bırakınız.',
              child: InkWell(
                onTap: _activeSessionId == null ? null : _showDutyTeacherDialog,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _selectedDutyTeacherId == null
                        ? Colors.white.withOpacity(0.10)
                        : Colors.cyanAccent.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _selectedDutyTeacherId == null
                          ? Colors.white24
                          : Colors.cyanAccent.withOpacity(0.50),
                    ),
                  ),
                  child: Icon(
                    Icons.supervisor_account_rounded,
                    color: _selectedDutyTeacherId == null
                        ? Colors.white70
                        : Colors.cyanAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Öğretmen',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(width: 10),
Column(
  children: [
    Tooltip(
      message: 'Çıkış Yap',
      child: InkWell(
        onTap: () async => _auth.signOut(),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: const Icon(
            Icons.logout_rounded,
            color: Colors.white70,
          ),
        ),
      ),
    ),
    const SizedBox(height: 6),
    const Text(
      'Çıkış Yap',
      style: TextStyle(
        color: Colors.white60,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  ],
),
      ],
    ),
  );
}

  Widget _studyStatusBadge() {
    final active = _isStudyOpenNow;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active
            ? Colors.greenAccent.withOpacity(0.14)
            : Colors.orangeAccent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? Colors.greenAccent.withOpacity(0.35)
              : Colors.orangeAccent.withOpacity(0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.circle : Icons.schedule_rounded,
            size: active ? 8 : 14,
            color: active ? Colors.greenAccent : Colors.orangeAccent,
          ),
          const SizedBox(width: 6),
          Text(
            active ? 'Etüt Aktif' : 'Etüt Kapalı',
            style: TextStyle(
              color: active ? Colors.greenAccent : Colors.orangeAccent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sessionCard() {
    final active =
    _isStudyOpenNow &&
    _activeSessionId != null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            active ? 'Etüt Oturumu Aktif' : 'Etüt Oturumu Kapalı',
            style: TextStyle(
              color: active ? Colors.greenAccent : Colors.orangeAccent,
              fontWeight: FontWeight.bold,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _studyScheduleMessage,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          if (active)
            StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('studySessions')
                  .doc(_activeSessionId)
                  .collection('students')
                  .snapshots(),
              builder: (context, snapshot) {
final count = snapshot.data?.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      return (data['status']?.toString() ?? 'present') ==
          'present';
    }).length ??
    0;

                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _miniBox(
  title: 'Etüt Saati',
  value: _activeStudySlotText,
  icon: Icons.schedule_rounded,
),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _miniBox(
                            title: 'Etütte',
                            value: '$count öğrenci',
                            icon: Icons.people_alt_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.greenAccent.withOpacity(.08),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(
      color: Colors.greenAccent.withOpacity(.25),
    ),
  ),
  child: const Row(
    children: [
      Icon(
        Icons.auto_mode_rounded,
        color: Colors.greenAccent,
      ),
      SizedBox(width: 10),
      Expanded(
        child: Text(
          'Etüt oturumu yönetici tarafından belirlenen başlangıç ve bitiş saatlerine göre otomatik yönetilmektedir.',
          style: TextStyle(
            color: Colors.white70,
            height: 1.35,
          ),
        ),
      ),
    ],
  ), 
),
if (_selectedDutyTeacherName != null) ...[
  const SizedBox(height: 12),
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.cyanAccent.withOpacity(0.10),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: Colors.cyanAccent.withOpacity(0.25),
      ),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.supervisor_account_rounded,
          color: Colors.cyanAccent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Görevli öğretmen: $_selectedDutyTeacherName',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  ),
],
                  ],
                );
              },
            )
          else
            _inactiveInfoCard(),
        ],
      ),
    );
  }
Future<void> _showDutyTeacherDialog() async {
  String? tempTeacherId = _selectedDutyTeacherId;
  String? tempTeacherName = _selectedDutyTeacherName;

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 18),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF06312E),
                    Color.fromARGB(255, 0, 138, 138),
                    Color(0xFF061B26),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withOpacity(0.16),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.cyanAccent.withOpacity(0.35),
                          ),
                        ),
                        child: const Icon(
                          Icons.supervisor_account_rounded,
                          color: Colors.cyanAccent,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Etüt Görevli Öğretmeni',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Seçilen öğretmen etüt süresince zümrede görünmez.',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  if (tempTeacherName != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.cyanAccent.withOpacity(0.30),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.cyanAccent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Seçili görevli: $tempTeacherName',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setDialogState(() {
                                tempTeacherId = null;
                                tempTeacherName = null;
                              });
                            },
                            child: const Text('Kaldır'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('users')
                          .where('role', isEqualTo: 'teacher')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text(
                            'Öğretmenler yüklenemedi: ${snapshot.error}',
                            style: const TextStyle(color: Colors.redAccent),
                          );
                        }

                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          );
                        }

                        final teachers = snapshot.data!.docs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;

                          final hasSubjects =
                              _teacherSubjectsFromData(data).isNotEmpty;

                          final status = data['teacherStatus'];

                          final isSelected =
                              tempTeacherId != null && doc.id == tempTeacherId;

                          return hasSubjects &&
                              (status == 'available' ||
                                  status == 'studyGuard' && isSelected);
                        }).toList();

                        if (teachers.isEmpty) {
                          return const Center(
                            child: Text(
                              'Uygun öğretmen bulunamadı.',
                              style: TextStyle(color: Colors.white60),
                            ),
                          );
                        }

                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: ListView.builder(
                            itemCount: teachers.length,
                            itemBuilder: (context, index) {
                              final doc = teachers[index];
                              final data = doc.data() as Map<String, dynamic>;

                              final name = data['fullName'] ??
                                  data['name'] ??
                                  data['email'] ??
                                  'Öğretmen';

                              final subjects =
                                  _teacherSubjectsFromData(data).join(', ');

                              final isSelected = doc.id == tempTeacherId;

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isSelected
                                      ? Colors.cyanAccent.withOpacity(0.24)
                                      : Colors.white.withOpacity(0.12),
                                  child: Icon(
                                    isSelected
                                        ? Icons.check
                                        : Icons.person_outline,
                                    color: isSelected
                                        ? Colors.cyanAccent
                                        : Colors.white70,
                                  ),
                                ),
                                title: Text(
                                  '$name',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  subjects.isEmpty ? 'Branş bilgisi yok' : subjects,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: isSelected
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: Colors.cyanAccent,
                                      )
                                    : null,
                                onTap: () {
                                  setDialogState(() {
                                    tempTeacherId = doc.id;
                                    tempTeacherName = '$name';
                                  });
                                },
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 18),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                          child: const Text('Vazgeç'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            await _saveDutyTeacher(
                              teacherId: tempTeacherId,
                              teacherName: tempTeacherName,
                            );

                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            foregroundColor: const Color(0xFF06312E),
                          ),
                          child: const Text('Kaydet'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
Future<void> _saveDutyTeacher({
  required String? teacherId,
  required String? teacherName,
}) async {
  if (_activeSessionId == null) return;

  try {
    final sessionRef =
        _firestore.collection('studySessions').doc(_activeSessionId);

    final batch = _firestore.batch();

    if (_selectedDutyTeacherId != null &&
        _selectedDutyTeacherId != teacherId) {
      final sessionDoc = await sessionRef.get();
      final sessionData = sessionDoc.data() ?? {};
      final previousStatus =
          sessionData['dutyTeacherPreviousStatus'] ?? 'available';

      batch.update(
        _firestore.collection('users').doc(_selectedDutyTeacherId),
        {
          'teacherStatus': previousStatus,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    }

    String? previousStatus;

    // Yeni öğretmen seçildiyse mevcut durumunu sakla, sonra studyGuard yap.
    if (teacherId != null) {
      final teacherDoc =
          await _firestore.collection('users').doc(teacherId).get();

      final teacherData = teacherDoc.data() ?? {};
      previousStatus = teacherData['teacherStatus'] ?? 'available';

      batch.update(
        _firestore.collection('users').doc(teacherId),
        {
          'teacherStatus': 'studyGuard',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    }

    batch.update(sessionRef, {
      'dutyTeacherId': teacherId,
      'dutyTeacherName': teacherName,
      'dutyTeacherPreviousStatus': previousStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    if (!mounted) return;

    setState(() {
      _selectedDutyTeacherId = teacherId;
      _selectedDutyTeacherName = teacherName;
    });

    _showSnack(
      teacherName == null
          ? 'Etüt için öğretmen seçimi kaldırıldı.'
          : '$teacherName etüt görevlisi olarak seçildi.',
    );
  } catch (e) {
    _showSnack('Etüt öğretmeni kaydedilemedi: $e');
  }
}
  Widget _inactiveInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orangeAccent.withOpacity(0.22)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orangeAccent),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Etüt saati başladığında oturum otomatik açılır. Etüt saati bitiminde oturum otomatik kapanır.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniBox({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.cyanAccent),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }
  Widget _dutyTeacherReminderCard() {
  if (!_isStudyOpenNow || _activeSessionId == null) {
    return const SizedBox.shrink();
  }

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.cyanAccent.withOpacity(0.09),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.cyanAccent.withOpacity(0.22)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          color: Colors.cyanAccent,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _selectedDutyTeacherName == null
                ? 'Kurumda branş öğretmeniyseniz üstteki öğretmen ikonundan kendinizi seçiniz. Öğretmen değilseniz ya da adınız listede yoksa boş bırakabilirsiniz.'
                : 'Görevli öğretmen olarak $_selectedDutyTeacherName seçili. Gerekirse üstteki öğretmen ikonundan değiştirilebilir veya kaldırılabilirsiniz.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _studentSearch() {
  if (!_isStudyOpenNow || _activeSessionId == null) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Text(
        _isStudyOpenNow
            ? 'Etüt oturumu hazırlanıyor...'
            : _studyScheduleMessage,
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    padding: const EdgeInsets.all(18),
    decoration: _cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Öğrenci Yoklaması',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Etütte bulunan öğrencileri arama penceresinden listeye ekleyin.',
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _isProcessing ? null : _showStudentPickerDialog,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text(
              'Öğrenci Ekle',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: const Color(0xFF06312E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
Future<void> _showStudentPickerDialog() async {
  String dialogSearch = '';
  final optimisticallyHiddenStudentIds = <String>{};
  final activeQueuesStream = _firestore
      .collection('queues')
      .where('status', whereIn: ['waiting', 'in_progress'])
      .snapshots();

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 18),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF06312E),
                    Color(0xFF008A5C),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withOpacity(0.16),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.cyanAccent.withOpacity(0.35),
                          ),
                        ),
                        child: const Icon(
                          Icons.groups_rounded,
                          color: Colors.cyanAccent,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Etüte Öğrenci Ekle',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Ad, soyad, sınıf veya kullanıcı adı ile arayın.',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Öğrenci ara...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        dialogSearch = value.trim().toLowerCase();
                      });
                    },
                  ),

                  const SizedBox(height: 14),

                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: activeQueuesStream,
                      builder: (context, queueSnapshot) {
                        if (queueSnapshot.hasError) {
                          return Text(
                            'Sıra bilgisi yüklenemedi: ${queueSnapshot.error}',
                            style: const TextStyle(color: Colors.redAccent),
                          );
                        }

                        if (!queueSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          );
                        }

                        final activeQueueStudentIds = queueSnapshot.data!.docs
                            .map((doc) =>
                                (doc.data() as Map<String, dynamic>)['studentId'])
                            .where((id) => id != null)
                            .toSet();

                        return StreamBuilder<QuerySnapshot>(
                          stream: _firestore
                              .collection('users')
                              .where('role', isEqualTo: 'student')
                              .limit(500)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Text(
                                'Öğrenciler yüklenemedi: ${snapshot.error}',
                                style: const TextStyle(color: Colors.redAccent),
                              );
                            }

                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              );
                            }

                            final students = snapshot.data!.docs.where((doc) {
                              final data = doc.data() as Map<String, dynamic>;

                              if (optimisticallyHiddenStudentIds
                                  .contains(doc.id)) {
                                return false;
                              }
                              if (data['isInStudySession'] == true) return false;
                              if (activeQueueStudentIds.contains(doc.id)) {
                                return false;
                              }

                              final searchable = [
                                data['fullName'],
                                data['name'],
                                data['surname'],
                                data['username'],
                                data['className'],
                                data['branch'],
                                data['department'],
                              ].where((e) => e != null).join(' ').toLowerCase();

                              if (dialogSearch.isEmpty) return true;

                              return searchable.contains(dialogSearch);
                            }).toList();

                            if (students.isEmpty) {
                              return const Center(
                                child: Text(
                                  'Uygun öğrenci bulunamadı.',
                                  style: TextStyle(color: Colors.white60),
                                ),
                              );
                            }

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.07),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: ListView.builder(
                                itemCount: students.length,
                                itemBuilder: (context, index) {
                                  return _dialogStudentTile(
                                    students[index],
                                    onOptimisticHide: () {
                                      setDialogState(() {
                                        optimisticallyHiddenStudentIds
                                            .add(students[index].id);
                                      });
                                    },
                                    onRestore: () {
                                      setDialogState(() {
                                        optimisticallyHiddenStudentIds
                                            .remove(students[index].id);
                                      });
                                    },
                                    onAdded: () {
                                      Navigator.pop(ctx);
                                    },
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
Widget _dialogStudentTile(
  DocumentSnapshot doc, {
  required VoidCallback onOptimisticHide,
  required VoidCallback onRestore,
  required VoidCallback onAdded,
}) {
  final data = doc.data() as Map<String, dynamic>;

  final name = data['fullName'] ?? data['name'] ?? 'Öğrenci';
  final className = data['className'] ?? '';
  final branch = data['branch'] ?? '';
  final department = data['department'] ?? '';

  final classText =
      '$className${branch.toString().isNotEmpty ? '-$branch' : ''}';

  final subtitle = [
    classText,
    department,
  ].where((e) => e.toString().trim().isNotEmpty).join(' • ');

  return ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    leading: CircleAvatar(
      backgroundColor: Colors.cyanAccent.withOpacity(0.22),
      child: const Icon(Icons.person, color: Colors.cyanAccent),
    ),
    title: Text(
      '$name',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    ),
    subtitle: Text(
      subtitle.isEmpty ? 'Öğrenci bilgisi' : subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white60, fontSize: 12),
    ),
    trailing: ElevatedButton(
      onPressed: _isProcessing
          ? null
          : () async {
              onOptimisticHide();
              final added = await _addStudentToStudy(doc);

              if (added) {
                onAdded();
              } else {
                onRestore();
              }
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.cyanAccent,
        foregroundColor: const Color(0xFF06312E),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: const Text(
        'Etüte Al',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    ),
  );
}
  Widget _currentStudents() {
    if (_activeSessionId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('studySessions')
          .doc(_activeSessionId)
          .collection('students')
          .orderBy('checkedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(),
            child: Text(
              'Etüt listesi yüklenemedi: ${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        if (!snapshot.hasData) return const SizedBox.shrink();

final students = snapshot.data!.docs.where((doc) {
  final data = doc.data() as Map<String, dynamic>;
  return (data['status']?.toString() ?? 'present') == 'present';
}).toList();        

        if (students.isEmpty) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(),
            child: const Text(
              'Henüz etüte alınan öğrenci yok.',
              style: TextStyle(color: Colors.white60),
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(18),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Etütteki Öğrenciler',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),const SizedBox(height: 12),

SizedBox(
  height: 260,
  child: ListView.builder(
    itemCount: students.length,
    itemBuilder: (context, index) {
      final doc = students[index];
      final data = doc.data() as Map<String, dynamic>;

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: ListTile(
          leading: const Icon(
            Icons.check_circle,
            color: Colors.greenAccent,
          ),
          title: Text(
            data['studentName'] ?? 'Öğrenci',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white),
          ),
          subtitle: Text(
            '${data['className'] ?? ''}-${data['branch'] ?? ''} • ${data['department'] ?? ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60),
          ),
          trailing: IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.redAccent,
            ),
onPressed: _removingStudentIds.contains(doc.id)
    ? null
    : () => _removeStudentFromStudy(
          doc.id,
          data['studentName']?.toString() ?? 'Öğrenci',
        ),
          ),
        ),
      );
    },
  ),
),
            ],
          ),
        );
      },
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.10),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Colors.white.withOpacity(0.15)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.16),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06312E),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF06312E),
              Color.fromARGB(255, 0, 138, 138),
              Color(0xFF061B26),
            ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              _header(),
              _sessionCard(),
              _dutyTeacherReminderCard(),
              _studentSearch(),
              _currentStudents(),
            ],
          ),
        ),
      ),
    );
  }
}
