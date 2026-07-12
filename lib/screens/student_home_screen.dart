import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  _StudentHomeScreenState createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _studentName;
  String? _selectedSubject;
  String? _selectedTeacherId;
  String? _selectedTeacherName;
  List<Map<String, dynamic>> _teachersForSubject = [];

bool _isInStudySession = false;
  bool _isLoadingTeachers = false;
  bool _isInQueue = false;
  bool _isZumreOpenNow = false;
  bool _isLunchNow = false;
  bool _useSmartTeacherSelection = true;
  String _zumreMessage = 'Zümre saati kontrol ediliyor...';
  String? _currentQueueId;
  String? _currentTeacherName;
  int _queuePosition = 0;
  int _selectedQuestionCount = 1;
  String _nextZumreText = '';

int _estimatedMinutesForQuestionCount(int count) {
  switch (count) {
    case 1:
      return 4;
    case 2:
      return 7;
    case 3:
      return 10;
    default:
      return 13;
  }
}
  int _cooldownUntil = 0;
  int _remainingCooldownSeconds = 0;

  Timer? _cooldownTimer;
  StreamSubscription<DocumentSnapshot>? _queueSubscription;

  @override
void initState() {
  super.initState();
  _loadStudentInfo();
  _findAndListenActiveQueue();
  _checkZumreAvailability();
}
String _normalizeSubject(dynamic value) {
  return value
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');
}

bool _teacherHasSubject(
  Map<String, dynamic> data,
  String subject,
) {
  final targetSubject = _normalizeSubject(subject);
  final teacherSubjects = <String>[];

  final rawSubjects = data['subjects'];

  if (rawSubjects is List) {
    teacherSubjects.addAll(
      rawSubjects
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty),
    );
  } else if (rawSubjects is String && rawSubjects.trim().isNotEmpty) {
    teacherSubjects.addAll(
      rawSubjects
          .split(RegExp(r'[,;/|]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty),
    );
  }

  final branch = data['branch']?.toString().trim() ?? '';
  final legacySubject = data['subject']?.toString().trim() ?? '';

  if (branch.isNotEmpty) {
    teacherSubjects.add(branch);
  }

  if (legacySubject.isNotEmpty) {
    teacherSubjects.add(legacySubject);
  }

  return teacherSubjects.any(
    (teacherSubject) =>
        _normalizeSubject(teacherSubject) == targetSubject,
  );
}
int _timeToMinutes(String time) {
  final parts = time.split(':');
  if (parts.length != 2) return 0;

  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = int.tryParse(parts[1]) ?? 0;

  return hour * 60 + minute;
}

bool _isNowInSlots(DateTime now, List<Map<String, dynamic>> slots) {
  final nowMinutes = now.hour * 60 + now.minute;

  for (final slot in slots) {
    final start = _timeToMinutes('${slot['start']}');
    final end = _timeToMinutes('${slot['end']}');

    if (nowMinutes >= start && nowMinutes < end) {
      return true;
    }
  }

  return false;
}
Future<Map<String, dynamic>?> _findBestAvailableTeacher(
  String subject,
) async {
  final teachersSnapshot = await _firestore
      .collection('users')
      .where('role', isEqualTo: 'teacher')
      .get();

  final availableTeachers = teachersSnapshot.docs.where((doc) {
    final data = doc.data();

    final status =
        data['teacherStatus']?.toString().trim() ?? 'absent';

    if (status != 'available') {
      return false;
    }

    return _teacherHasSubject(data, subject);
  }).toList();

  if (availableTeachers.isEmpty) {
    return null;
  }

  final now = DateTime.now();
  final todayStart = DateTime(
    now.year,
    now.month,
    now.day,
  );

  final queuesSnapshot = await _firestore
      .collection('queues')
      .where(
        'status',
        whereIn: ['waiting', 'in_progress'],
      )
      .get();

  final todayCompletedSnapshot = await _firestore
      .collection('queues')
      .where('status', isEqualTo: 'completed')
      .where(
        'completedAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
      )
      .get();

  final Map<String, int> teacherScore = {
    for (final teacher in availableTeachers) teacher.id: 0,
  };

  for (final queue in queuesSnapshot.docs) {
    final data = queue.data();
    final teacherId = data['teacherId']?.toString();
    final status = data['status']?.toString();

    if (teacherId == null ||
        !teacherScore.containsKey(teacherId)) {
      continue;
    }

    if (status == 'in_progress') {
      teacherScore[teacherId] =
          (teacherScore[teacherId] ?? 0) + 3;
    } else if (status == 'waiting') {
      teacherScore[teacherId] =
          (teacherScore[teacherId] ?? 0) + 1;
    }
  }

  final Map<String, int> todaySolved = {};

  for (final queue in todayCompletedSnapshot.docs) {
    final teacherId =
        queue.data()['teacherId']?.toString();

    if (teacherId == null ||
        !teacherScore.containsKey(teacherId)) {
      continue;
    }

    todaySolved[teacherId] =
        (todaySolved[teacherId] ?? 0) + 1;
  }

  for (final entry in todaySolved.entries) {
    teacherScore[entry.key] =
        (teacherScore[entry.key] ?? 0) +
            (entry.value ~/ 10);
  }

  final teachers = availableTeachers.toList();

  teachers.shuffle();

  teachers.sort((a, b) {
    final aScore = teacherScore[a.id] ?? 0;
    final bScore = teacherScore[b.id] ?? 0;

    return aScore.compareTo(bScore);
  });

  final bestTeacher = teachers.first;
  final data = bestTeacher.data();

  return {
    'id': bestTeacher.id,
    'name': data['fullName'] ??
        data['name'] ??
        data['email'] ??
        'Öğretmen',
    'score': teacherScore[bestTeacher.id] ?? 0,
  };
}

Future<void> _checkZumreAvailability() async {
  final now = DateTime.now();
  final isWeekend =
      now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

  final doc =
      await _firestore.collection('settings').doc('zumreSchedule').get();

  final data = doc.data() ?? {};

  final rawSlots = isWeekend
      ? List.from(data['weekendSlots'] ?? [])
      : List.from(data['weekdaySlots'] ?? []);

  final slots = rawSlots.map((e) => Map<String, dynamic>.from(e)).toList();

  final lunch = Map<String, dynamic>.from(data['lunchBreak'] ?? {});

  final isZumreOpen = _isNowInSlots(now, slots);

  bool isLunch = false;
  if (lunch.isNotEmpty) {
    isLunch = _isNowInSlots(now, [
      {
        'start': lunch['start'] ?? '12:20',
        'end': lunch['end'] ?? '13:00',
      }
    ]);
  }

  String message;
  String nextZumreText = '';

if (!isZumreOpen && slots.isNotEmpty) {
  final nowMinutes = now.hour * 60 + now.minute;

  final futureSlots = slots.where((slot) {
    final start = _timeToMinutes('${slot['start']}');
    return start > nowMinutes;
  }).toList();

  if (futureSlots.isNotEmpty) {
    futureSlots.sort((a, b) {
      final aStart = _timeToMinutes('${a['start']}');
      final bStart = _timeToMinutes('${b['start']}');
      return aStart.compareTo(bStart);
    });

nextZumreText = '${futureSlots.first['start']}';  } else {
    nextZumreText = isWeekend
        ? 'Bugünkü zümre tamamlandı'
        : 'Yarın zümre ${slots.first['start']}\'te başlıyor';
  }
}

  if (isLunch) {
    message = 'Şu an öğle arası. Zümre sırası geçici olarak kapalı.';
  } else if (!isZumreOpen) {
    message = 'Şu an zümre saati aktif değil.';
  } else {
    message = 'Zümre saati aktif. Sıra alabilirsiniz.';
  }

  if (!mounted) return;

  setState(() {
    _isZumreOpenNow = isZumreOpen;
    _isLunchNow = isLunch;
    _zumreMessage = message;
    _nextZumreText = nextZumreText;
  });
}

  @override
  @override
void dispose() {
  _queueSubscription?.cancel();
  _cooldownTimer?.cancel();
  super.dispose();
}
  Future<void> _findAndListenActiveQueue() async {
  final userId = _auth.currentUser!.uid;

  final userDoc = await _firestore.collection('users').doc(userId).get();

  final activeQueueId = userDoc.data()?['activeQueueId'];

  if (activeQueueId != null && activeQueueId.toString().isNotEmpty) {
    final queueDoc =
        await _firestore.collection('queues').doc(activeQueueId).get();

    if (queueDoc.exists) {
      final data = queueDoc.data()!;
      final status = data['status'];

      if (status == 'waiting' ||
          status == 'in_progress' ||
          status == 'completed') {
        if (mounted && status != 'completed') {
          setState(() {
            _isInQueue = true;
            _currentQueueId = activeQueueId;
          });
        }

        if (data['teacherId'] != null) {
          _getCurrentTeacherName(data['teacherId']);
        }
        

        _listenToQueue(activeQueueId);
        return;
      }
    }
  }

  if (mounted) {
    setState(() {
      _isInQueue = false;
      _currentQueueId = null;
      _currentTeacherName = null;
      _queuePosition = 0;
    });
  }
}

  Future<void> _loadStudentInfo() async {
    final user = _auth.currentUser!;
    final doc = await _firestore.collection('users').doc(user.uid).get();

    if (doc.exists && mounted) {
      final data = doc.data();

      setState(() {
        _studentName = data?['name'] ?? data?['email'] ?? 'Öğrenci';
        _isInStudySession = data?['isInStudySession'] == true;
      });

      final cooldownTimestamp = data?['cooldownUntil'] as Timestamp?;

      if (cooldownTimestamp != null) {
        final cooldownMs = cooldownTimestamp.toDate().millisecondsSinceEpoch;
        final nowMs = DateTime.now().millisecondsSinceEpoch;

        if (cooldownMs > nowMs) {
          setState(() {
            _cooldownUntil = cooldownMs;
            _remainingCooldownSeconds =
                ((_cooldownUntil - nowMs) / 1000).ceil();
          });

          _startCooldownTimer();
        }
      }
    }
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();

    _cooldownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) async {
        final now = DateTime.now().millisecondsSinceEpoch;
        final remaining = ((_cooldownUntil - now) / 1000).ceil();

        if (remaining <= 0) {
          timer.cancel();

          if (mounted) {
            setState(() {
              _remainingCooldownSeconds = 0;
              _cooldownUntil = 0;
            });
          }

          await _firestore
              .collection('users')
              .doc(_auth.currentUser!.uid)
              .update({
            'cooldownUntil': FieldValue.delete(),
          });

          return;
        }

        if (mounted) {
          setState(() {
            _remainingCooldownSeconds = remaining;
          });
        }
      },
    );
  }

  Future<void> _getCurrentTeacherName(String? teacherId) async {
    if (teacherId == null || teacherId.trim().isEmpty) return;

    final teacherDoc =
        await _firestore.collection('users').doc(teacherId).get();

    if (teacherDoc.exists && mounted) {
      final data = teacherDoc.data();

      setState(() {
        _currentTeacherName = data?['name'] ?? data?['email'] ?? 'Öğretmen';
      });
    }
  }

void _listenToQueue(String queueId) {
  _queueSubscription?.cancel();

  _queueSubscription =
      _firestore.collection('queues').doc(queueId).snapshots().listen(
    (snapshot) async {
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final status = data['status'];

      if (status == 'waiting') {
        if (mounted) {
          setState(() {
            _isInQueue = true;
            _currentQueueId = queueId;
          });
        }

        await _updatePosition(queueId);
        return;
      }

      if (status == 'in_progress') {
        final teacherNameFromQueue = data['teacherName'];

        if (mounted) {
          setState(() {
            _isInQueue = true;
            _currentQueueId = queueId;
            _queuePosition = 0;

            if (teacherNameFromQueue != null) {
              _currentTeacherName = teacherNameFromQueue;
            }
          });
        }

        if (data['teacherId'] != null) {
          _getCurrentTeacherName(data['teacherId']);
        }


        return;
      }

      if (status == 'completed') {
await _firestore.collection('users').doc(_auth.currentUser!.uid).update({
    'activeQueueId': FieldValue.delete(),
  });
  

  if (mounted) {
    setState(() {
      _isInQueue = false;
      _currentQueueId = null;
      _currentTeacherName = null;
      _queuePosition = 0;
      
    });
  }

  await _queueSubscription?.cancel();
  _queueSubscription = null;

  Future.delayed(const Duration(milliseconds: 400), () {
    if (mounted) {
      _showRatingDialog(queueId);
    }
  });

  return;
}

      if (status == 'cancelled') {

        if (mounted) {
          setState(() {
            _isInQueue = false;
            _currentQueueId = null;
            _currentTeacherName = null;
            _queuePosition = 0;
          });
        }

        await _queueSubscription?.cancel();
        _queueSubscription = null;
        return;
      }
    },
  );
}

  Future<void> _updatePosition(String queueId) async {
    final queueDoc =
        await _firestore.collection('queues').doc(queueId).get();

    if (!queueDoc.exists) return;

    final teacherId = queueDoc.data()!['teacherId'];

    final waitingQueues = await _firestore
        .collection('queues')
        .where('teacherId', isEqualTo: teacherId)
        .where('status', isEqualTo: 'waiting')
        .get();

    final docs = waitingQueues.docs.toList();

    docs.sort((a, b) {
      final aTime = a.data()['createdAt'] as Timestamp?;
      final bTime = b.data()['createdAt'] as Timestamp?;

      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;

      return aTime.compareTo(bTime);
    });

    int position = 1;

    for (var doc in docs) {
      if (doc.id == queueId) break;
      position++;
    }

    if (mounted) {
      setState(() {
        _queuePosition = position;
      });
    }
  }
Future<void> _loadTeachersForSubject(String subject) async {
  if (subject.trim().isEmpty) return;

  if (mounted) {
    setState(() {
      _isLoadingTeachers = true;
      _teachersForSubject = [];
      _selectedTeacherId = null;
      _selectedTeacherName = null;
      _useSmartTeacherSelection = true;
    });
  }

  try {
    // Önce bütün öğretmenleri alıyoruz.
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'teacher')
        .get();

    final teachers = <Map<String, dynamic>>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();

      final status =
          data['teacherStatus']?.toString().trim() ?? '';

      // Yalnızca müsait öğretmen
      if (status != 'available') {
        continue;
      }

      if (!_teacherHasSubject(data, subject)) {
        continue;
      }

      teachers.add({
        'id': doc.id,
        'name': data['fullName'] ??
            data['name'] ??
            data['email'] ??
            'Öğretmen',
      });
    }

    teachers.sort(
      (a, b) => a['name']
          .toString()
          .compareTo(b['name'].toString()),
    );

    if (!mounted) return;

    setState(() {
      _teachersForSubject = teachers;
    });

    if (!mounted) return;

  } finally {
    if (mounted) {
      setState(() {
        _isLoadingTeachers = false;
      });
    }
  }
}

  Future<void> _joinQueue() async {
    if (_remainingCooldownSeconds > 0 ||
        DateTime.now().millisecondsSinceEpoch < _cooldownUntil) {
      return;
    }
String? finalTeacherId = _selectedTeacherId;
String? finalTeacherName = _selectedTeacherName;

if (_useSmartTeacherSelection) {
  _showSmartTeacherLoadingDialog();

  try {
    final bestTeacher =
        await _findBestAvailableTeacher(_selectedSubject!);

    if (bestTeacher == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Şu an müsait öğretmen bulunamadı.'),
        ),
      );
      return;
    }

    finalTeacherId = bestTeacher['id'];
    finalTeacherName = bestTeacher['name'];
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sıra alınamadı: $e')),
    );
  } finally {
    _hideSmartTeacherLoadingDialog();
  }
}
final studentDoc = await _firestore
    .collection('users')
    .doc(_auth.currentUser!.uid)
    .get();

final studentData = studentDoc.data() ?? {};

if (studentData['isInStudySession'] == true) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Şu anda etütte görünüyorsunuz. Etüt bitince zümre sırası alabilirsiniz.',
      ),
    ),
  );
  return;
}
if (_selectedSubject == null ||
    _selectedSubject!.trim().isEmpty) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Lütfen bir ders seçin.'),
    ),
  );
  return;
}

if (!_useSmartTeacherSelection &&
    (_selectedTeacherId == null ||
        _selectedTeacherId!.trim().isEmpty)) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Lütfen bir öğretmen seçin.'),
    ),
  );
  return;
}

if (!_useSmartTeacherSelection &&
    (_selectedTeacherId == null ||
        _selectedTeacherId!.trim().isEmpty)) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Lütfen bir öğretmen seçin.'),
    ),
  );
  return;
}

    final userId = _auth.currentUser!.uid;

    final existing = await _firestore
        .collection('queues')
        .where('studentId', isEqualTo: userId)
        .where('status', whereIn: ['waiting', 'in_progress'])
        .get();

    if (existing.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zaten aktif bir sıranız var')),
      );
      return;
    }
if (finalTeacherId == null ||
    finalTeacherId.trim().isEmpty) {
  final fallbackTeacher =
      await _findBestAvailableTeacher(_selectedSubject!);

  if (fallbackTeacher == null) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$_selectedSubject dersi için şu an müsait öğretmen bulunamadı.',
        ),
      ),
    );
    return;
  }

  finalTeacherId = fallbackTeacher['id']?.toString();
  finalTeacherName =
      fallbackTeacher['name']?.toString() ?? 'Öğretmen';
}

    try {
      final newQueue = {
        'teacherName': finalTeacherName,
        'studentId': userId,
        'teacherId': finalTeacherId,
        'subject': _selectedSubject,
        'status': 'waiting',
        'studentName': _studentName,
        'questionCount': _selectedQuestionCount,
'estimatedMinutes': _estimatedMinutesForQuestionCount(_selectedQuestionCount),
'extraMinutes': 0,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await _checkZumreAvailability();

if (!_isZumreOpenNow || _isLunchNow) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_zumreMessage)),
  );
  return;
}

      final docRef = await _firestore.collection('queues').add(newQueue);
      await _firestore.collection('users').doc(userId).update({
  'activeQueueId': docRef.id,
});

      if (mounted) {
        setState(() {
          _isInQueue = true;
          _currentQueueId = docRef.id;
          _queuePosition = 1;
        });
      }

      _listenToQueue(docRef.id);
      _getCurrentTeacherName(finalTeacherId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sıranız alındı! Lütfen bekleyin.')),
      );
} catch (e) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Öğretmen belirlenemedi: $e'),
      ),
    );
  }

  return;
} finally {
}
  }
Future<bool> _confirmLogout({
  required Color color,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.logout_rounded,
                  color: color,
                ),
                const SizedBox(width: 10),
                const Text("Çıkış Yap"),
              ],
            ),
            content: const Text(
              "Oturumu kapatmak istediğinize emin misiniz?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Vazgeç"),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.logout),
                label: const Text("Çıkış Yap"),
              ),
            ],
          );
        },
      ) ??
      false;
}
  Future<void> _cancelQueue() async {
    if (_currentQueueId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sıranızı iptal ediyorsunuz'),
        content: const Text(
          'İptal ederseniz 2 dakika yeni sıra alamazsınız. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hayır'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final cooldownDate = DateTime.now().add(const Duration(minutes: 2));

        await _firestore.collection('queues').doc(_currentQueueId).update({
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
        });

        await _firestore.collection('users').doc(_auth.currentUser!.uid).update({
          'cooldownUntil': Timestamp.fromDate(cooldownDate),
        });

        if (mounted) {
          setState(() {
            _isInQueue = false;
            _cooldownUntil = cooldownDate.millisecondsSinceEpoch;
            _remainingCooldownSeconds = 120;
            _currentQueueId = null;
            _currentTeacherName = null;
            _queuePosition = 0;
          });
        }

        _startCooldownTimer();

        _queueSubscription?.cancel();
        _queueSubscription = null;
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İptal sırasında hata: $e')),
        );
      }
    }
  }
  void _showSmartTeacherLoadingDialog() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF1A1240),
              Color(0xFF2B1768),
            ],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white24),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF7C4DFF)),
            SizedBox(width: 18),
            Expanded(
              child: Text(
                'En uygun öğretmen belirleniyor...\nLütfen bekleyin.',
                style: TextStyle(
                  color: Colors.white70,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _hideSmartTeacherLoadingDialog() {
  if (mounted && Navigator.canPop(context)) {
    Navigator.pop(context);
  }
}
  void _showRatingDialog(String queueId) {
  int rating = 5;
  String comment = '';

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      bool showCloseButton = false;

      return StatefulBuilder(
        builder: (context, setStateDialog) {
          if (!showCloseButton) {
            Future.delayed(const Duration(seconds: 2), () {
              if (ctx.mounted) {
                setStateDialog(() {
                  showCloseButton = true;
                });
              }
            });
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF071A3A),
                    Color(0xFF30106B),
                  ],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Sorunuz çözüldü!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (showCloseButton)
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white70,
                          ),
                          onPressed: () async {
                            await _firestore
                                .collection('queues')
                                .doc(queueId)
                                .update({
                              'ratingPopupClosed': true,
                            });

                            Navigator.pop(ctx);
                          },
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: Colors.greenAccent,
                      size: 42,
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    'Öğretmeni puanlayın',
                    style: TextStyle(color: Colors.white70),
                  ),

                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      5,
                      (i) => IconButton(
                        icon: Icon(
                          i < rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 30,
                        ),
                        onPressed: () {
                          setStateDialog(() {
                            rating = i + 1;
                          });
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Yorum (isteğe bağlı)',
                      labelStyle: const TextStyle(color: Colors.white60),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) {
                      comment = val;
                    },
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          await _firestore
                              .collection('queues')
                              .doc(queueId)
                              .update({
                            'rating': rating,
                            'comment': comment,
                            'ratingPopupClosed': true,
                          });

                          Navigator.pop(ctx);

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Teşekkürler! Değerlendirmeniz kaydedildi.',
                              ),
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Değerlendirme kaydedilemedi: $e',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.send),
                      label: const Text('Değerlendirmeyi Gönder'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C3DFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
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

  String _formatCooldown(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;

    if (minutes > 0) {
      return '$minutes dk $remainingSeconds sn';
    }

    return '$remainingSeconds sn';
  }
Widget _compactZumreInfoBadge() {
  final active = _isZumreOpenNow && !_isLunchNow;

  if (active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.greenAccent.withOpacity(0.35),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: Colors.greenAccent,
          ),
          SizedBox(width: 5),
          Text(
            'Zümre Aktif',
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.orangeAccent.withOpacity(0.14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: Colors.orangeAccent.withOpacity(0.35),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.schedule_rounded,
          size: 14,
          color: Colors.orangeAccent,
        ),
        const SizedBox(width: 5),
        Text(
          _nextZumreText.isEmpty
    ? 'Zümre Kapalı'
    : 'Sonraki: $_nextZumreText',
          style: const TextStyle(
            color: Colors.orangeAccent,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}
  Widget _buildSubjectGrid() {
  return GridView.count(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 2,
    crossAxisSpacing: 9,
    mainAxisSpacing: 9,
    childAspectRatio: 1.8,
    children: [
      _subjectCard('MATEMATİK', Icons.calculate, const Color(0xFF6C3DFF)),
      _subjectCard('FİZİK', Icons.biotech, const Color(0xFF0099FF)),
      _subjectCard('KİMYA', Icons.science, const Color(0xFFFF8A00)),
      _subjectCard('BİYOLOJİ', Icons.eco, const Color(0xFF00C878)),
      _subjectCard('TÜRKÇE', Icons.menu_book, const Color(0xFFE91E63)),
      _subjectCard('TARİH', Icons.history_edu, const Color(0xFFFFC107)),
      _subjectCard('COĞRAFYA', Icons.public, const Color(0xFF00BCD4)),
      _subjectCard('GEOMETRİ', Icons.square_foot, const Color(0xFF9C27B0)),
    ],
  );
}
Widget _buildQuestionCountSelector() {
  final options = [1, 2, 3, 4];

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withOpacity(0.14)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Kaç soru çözdüreceksin?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: options.map((count) {
            final selected = _selectedQuestionCount == count;
            final label = count == 4 ? '4+' : '$count';

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    setState(() {
                      _selectedQuestionCount = count;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF6C3DFF)
                          : Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? Colors.white.withOpacity(0.55)
                            : Colors.white24,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        Text(
          'Tahmini çözüm süresi: ~${_estimatedMinutesForQuestionCount(_selectedQuestionCount)} dk',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );
}


Widget _subjectCard(String title, IconData icon, Color color) {
  final selected = _selectedSubject == title;

  return InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: () {
setState(() {
  _selectedSubject = title;
  _selectedTeacherId = null;
  _selectedTeacherName = null;
  _teachersForSubject = [];
  _useSmartTeacherSelection = true;
});

      _loadTeachersForSubject(title);
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.26) : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? color : Colors.white24,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: selected ? Colors.white : color, size: 30),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildCooldownCard() {
  if (_remainingCooldownSeconds <= 0) {
    return const SizedBox.shrink();
  }

  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.orange.withOpacity(0.16),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: Colors.orangeAccent.withOpacity(0.45),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.16),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.20),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.timer,
            color: Colors.orangeAccent,
            size: 28,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kısa bir bekleme süresi',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tekrar sıra almak için ${_formatCooldown(_remainingCooldownSeconds)} bekleyiniz.',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
  Widget _buildHomeView() {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        _buildWelcomeCard(),

        const SizedBox(height: 24),

        _buildCooldownCard(),

        const SizedBox(height: 12),

        if (_isInStudySession) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.25)),
            ),
            child: const Text(
              'Şu anda etütte görünüyorsunuz. Etüt bitince zümre sırası alabilirsiniz.',
              style: TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ),
        ],

        const Text(
          "Ders Seç",
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 14),

        _buildSubjectGrid(),

        const SizedBox(height: 24),
        const SizedBox(height: 18),
_buildQuestionCountSelector(),

        _buildTeacherSelector(),

        const SizedBox(height: 24),

        _buildJoinQueueButton(),
      ],
    ),
  );
}
Widget _buildWelcomeCard() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.12),
          const Color(0xFF6C3DFF).withOpacity(0.22),
        ],
      ),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withOpacity(0.18)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.22),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: const Color(0xFF6C3DFF).withOpacity(0.22),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.18)),
              ),
              child: const Icon(
                Icons.school,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(width: 16),
    Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Merhaba 👋',
        style: TextStyle(
          color: Colors.white60,
          fontSize: 14,
        ),
      ),
      const SizedBox(height: 4),

      Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
   FittedBox(
  fit: BoxFit.scaleDown,
  alignment: Alignment.centerLeft,
  child: Text(
    _studentName ?? 'Öğrenci',
    maxLines: 1,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 25,
      fontWeight: FontWeight.bold,
    ),
  ),
),

          _compactZumreInfoBadge(),
        ],
      ),

      const SizedBox(height: 6),

      const Text(
        'Dersini seç, sıranı al ve öğretmenine ulaş.',
        style: TextStyle(
          color: Colors.white60,
          fontSize: 12,
        ),
      ),
    ],
  ),
),
            IconButton(
              tooltip: 'Çıkış Yap',
              onPressed: () async {
final logout = await _confirmLogout(
  color: Colors.indigo,
);

if (!logout) return;

await _auth.signOut();              },
              icon: const Icon(
                Icons.logout,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
Widget _buildTeacherSelector() {
  if (_selectedSubject == null) {
    return const SizedBox();
  }

  if (_isLoadingTeachers) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

 return Container(
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    color: Colors.white.withOpacity(0.08),
    borderRadius: BorderRadius.circular(24),
  ),
  child: DropdownButtonFormField<String>(
    value: _useSmartTeacherSelection ? 'smart' : _selectedTeacherId,
    dropdownColor: const Color(0xFF1A1F3A),
    style: const TextStyle(color: Colors.white),
    decoration: const InputDecoration(
      labelText: 'Öğretmen Seç',
      labelStyle: TextStyle(color: Colors.white70),
    ),
    items: [
      const DropdownMenuItem<String>(
        value: 'smart',
        child: Text('✨ En Uygun Öğretmene Yönlendir'),
      ),

      ..._teachersForSubject.map<DropdownMenuItem<String>>((teacher) {
        return DropdownMenuItem<String>(
          value: teacher['id'].toString(),
          child: Text(
  (teacher['name'] ?? 'Öğretmen').toString(),
),
        );
      }),
    ],

    onChanged: (value) {
      setState(() {
        if (value == 'smart') {
          _useSmartTeacherSelection = true;
          _selectedTeacherId = null;
          _selectedTeacherName = null;
          return;
        }

        _useSmartTeacherSelection = false;
        _selectedTeacherId = value;

        final teacher = _teachersForSubject.firstWhere(
          (t) => t['id'] == value,
        );

        _selectedTeacherName =
    (teacher['name'] ?? 'Öğretmen').toString();
      });
    },
  ),
);
}

Widget _buildJoinQueueButton() {
  final canJoinQueue =
      _selectedSubject != null &&
      _remainingCooldownSeconds <= 0 &&
      _isZumreOpenNow &&
      !_isLunchNow &&
      !_isInStudySession;

  return SizedBox(
    width: double.infinity,
    height: 58,
    child: ElevatedButton.icon(
      onPressed: canJoinQueue ? _joinQueue : null,
      icon: const Icon(Icons.flash_on),
      label: const Text(
        "Sıra Al",
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF6C3DFF),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    ),
  );
}

Widget _buildQueueView() {
  final bool isTeacherWorking = _queuePosition == 0;
Container(
  width: double.infinity,
  margin: const EdgeInsets.only(bottom: 12),
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: (_isZumreOpenNow && !_isLunchNow)
        ? Colors.greenAccent.withOpacity(0.12)
        : Colors.orangeAccent.withOpacity(0.12),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(
      color: (_isZumreOpenNow && !_isLunchNow)
          ? Colors.greenAccent.withOpacity(0.30)
          : Colors.orangeAccent.withOpacity(0.30),
    ),
  ),
  child: Row(
    children: [
      Icon(
        (_isZumreOpenNow && !_isLunchNow)
            ? Icons.check_circle
            : Icons.info_outline,
        color: (_isZumreOpenNow && !_isLunchNow)
            ? Colors.greenAccent
            : Colors.orangeAccent,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          _zumreMessage,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  ),
);

return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: Colors.white.withOpacity(0.18),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: isTeacherWorking
                    ? Colors.green.withOpacity(0.18)
                    : Colors.blue.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isTeacherWorking
                    ? Icons.support_agent
                    : Icons.hourglass_top,
                color: isTeacherWorking ? Colors.greenAccent : Colors.blueAccent,
                size: 44,
              ),
            ),

            const SizedBox(height: 22),

            Text(
              isTeacherWorking
                  ? 'Öğretmen sorunuzla ilgileniyor'
                  : 'Sıranız beklemede',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              isTeacherWorking
                  ? 'Lütfen öğretmenin yönlendirmesini bekleyin.'
                  : 'Önünüzde $_queuePosition kişi var.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
              ),
            ),

            if (_currentTeacherName != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.person,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Öğretmen: $_currentTeacherName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              
            ],

            const SizedBox(height: 24),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Text(
                    'Tahmini Bekleme',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isTeacherWorking
                        ? 'Şu an ilgileniliyor'
                        : '~${_queuePosition * 3} dk',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 26),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: isTeacherWorking ? null : _cancelQueue,
                icon: const Icon(Icons.cancel),
                label: Text(
                  isTeacherWorking
                      ? 'İptal Edilemez'
                      : 'Sırayı İptal Et',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  disabledBackgroundColor: Colors.white.withOpacity(0.12),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white54,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
            if (!isTeacherWorking) ...[
  const SizedBox(height: 14),

  Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(
      horizontal: 14,
      vertical: 10,
    ),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: Colors.white.withOpacity(0.08),
      ),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '💡',
          style: TextStyle(fontSize: 16),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Sıranız gelene kadar çözemediğiniz soruları ve takıldığınız noktaları hazırlayın. Böylece öğretmeniniz size daha hızlı yardımcı olabilir.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  ),

  const SizedBox(height: 14),
]
          ]
        ),
      ),
    ),
  );
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  toolbarHeight: 0,
),
  body: Container(
  decoration: const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF071A3A),
        Color(0xFF30106B),
        Color(0xFF050814),
      ],
    ),
  ),
  child: SafeArea(
    child: _isInQueue
        ? _buildQueueView()
        : _buildHomeView(),
  ),
),
    );
  }
}