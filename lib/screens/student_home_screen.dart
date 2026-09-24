import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../utils/queue_priority.dart';

class _TeacherChoice {
  const _TeacherChoice({
    required this.id,
    required this.name,
    required this.subjects,
  });

  final String id;
  final String name;
  final List<String> subjects;
}

class _SubjectOption {
  const _SubjectOption(this.name, this.icon, this.color);

  final String name;
  final IconData icon;
  final Color color;
}

class _AppointmentSlot {
  const _AppointmentSlot({
    required this.start,
    required this.end,
    required this.scheduledStart,
    required this.scheduledEnd,
  });

  final String start;
  final String end;
  final String scheduledStart;
  final String scheduledEnd;
}

class _AppointmentTeacherOption {
  const _AppointmentTeacherOption({
    required this.id,
    required this.name,
    required this.slots,
  });

  final String id;
  final String name;
  final List<_AppointmentSlot> slots;
}

class _AppointmentAvailabilityResult {
  const _AppointmentAvailabilityResult({
    required this.teachers,
    this.message,
  });

  final List<_AppointmentTeacherOption> teachers;
  final String? message;
}

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  static const List<_SubjectOption> _subjectOptions = [
    _SubjectOption(
      'MATEMATİK',
      Icons.calculate,
      Color.fromARGB(162, 235, 39, 147),
    ),
    _SubjectOption('FİZİK', Icons.biotech, Color(0xFF0099FF)),
    _SubjectOption('KİMYA', Icons.science, Color(0xFFFF8A00)),
    _SubjectOption('BİYOLOJİ', Icons.eco, Color(0xFF00C878)),
    _SubjectOption('TÜRKÇE', Icons.menu_book, Color(0xFFE91E63)),
    _SubjectOption('TARİH', Icons.history_edu, Color(0xFFFFC107)),
    _SubjectOption('COĞRAFYA', Icons.public, Color(0xFF00BCD4)),
    _SubjectOption(
        'GEOMETRİ', Icons.square_foot, Color.fromARGB(255, 139, 176, 39)),
  ];

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  String? _studentName;
  String? _selectedSubject;

  Map<String, String>? _guidanceAppointment;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _guidanceAppointmentSubscription;

  bool _isInStudySession = false;
  bool _isInQueue = false;
  bool _isZumreOpenNow = false;
  bool _isLunchNow = false;
  bool _isRoutingQueue = false;
  String _zumreMessage = 'Zümre saati kontrol ediliyor...';
  String? _currentQueueId;
  String? _currentTeacherName;
  String? _selectedTeacherId;
  String? _selectedTeacherName;
  int _queuePosition = 0;
  int? _estimatedWaitMinutes;
  int _selectedQuestionCount = 1;
  String _zumreSlotText = '';
  String _nextZumreText = '';
  int? _zumreRemainingMinutes;
  bool _didShowVerifiedNoShowWarning = false;
  static const int _appointmentPlanningDayCount = 7;
  static const int _appointmentPlanningMaxOffsetDays = 7;

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

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  int _queueEstimatedMinutes(Map<String, dynamic> data) {
    final estimated = _toInt(data['estimatedMinutes']);
    if (estimated > 0) return estimated;

    return _estimatedMinutesForQuestionCount(
      _toInt(data['questionCount'], fallback: 1),
    );
  }

  int _activeQueueRemainingMinutes(Map<String, dynamic> data) {
    final totalMinutes =
        _queueEstimatedMinutes(data) + _toInt(data['extraMinutes']);
    final startedAt = data['startedAt'];

    if (startedAt is! Timestamp) {
      return totalMinutes;
    }

    final elapsedSeconds =
        DateTime.now().difference(startedAt.toDate()).inSeconds;
    final remainingSeconds = (totalMinutes * 60) - elapsedSeconds;

    if (remainingSeconds <= 0) return 0;
    return (remainingSeconds / 60).ceil();
  }

  String _normalizeSubjectText(Object? value) {
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

  List<String> _teacherSubjects(Map<String, dynamic> data) {
    final subjects = <String>[];
    final rawSubjects = data['subjects'];

    if (rawSubjects is List) {
      subjects.addAll(rawSubjects.map((item) => item.toString()));
    } else if (rawSubjects is String) {
      subjects.addAll(rawSubjects.split(RegExp(r'[,;/|]')));
    }

    final branch = data['branch']?.toString();
    final subject = data['subject']?.toString();

    if (branch != null && branch.trim().isNotEmpty) {
      subjects.add(branch);
    }

    if (subject != null && subject.trim().isNotEmpty) {
      subjects.add(subject);
    }

    final seen = <String>{};
    return subjects.map((item) => item.trim()).where((item) {
      if (item.isEmpty) return false;
      return seen.add(_normalizeSubjectText(item));
    }).toList();
  }

  bool _teacherMatchesSelectedSubject(Map<String, dynamic> data) {
    final selectedSubject = _selectedSubject;
    if (selectedSubject == null || selectedSubject.trim().isEmpty) {
      return false;
    }

    final normalizedSelected = _normalizeSubjectText(selectedSubject);
    return _teacherSubjects(data).any(
      (subject) => _normalizeSubjectText(subject) == normalizedSelected,
    );
  }

  String _teacherDisplayName(Map<String, dynamic> data) {
    final name = data['fullName'] ?? data['name'] ?? data['email'];
    final value = name?.toString().trim() ?? '';
    return value.isEmpty ? 'Öğretmen' : value;
  }

  Future<List<_TeacherChoice>> _loadAvailableTeacherChoices() async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'teacher')
        .where('teacherStatus', isEqualTo: 'available')
        .get();

    final teachers = snapshot.docs
        .where((doc) => _teacherMatchesSelectedSubject(doc.data()))
        .map((doc) {
      final data = doc.data();
      return _TeacherChoice(
        id: doc.id,
        name: _teacherDisplayName(data),
        subjects: _teacherSubjects(data),
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return teachers;
  }

  DateTime _istanbulNow() => DateTime.now().toUtc().add(
        const Duration(hours: 3),
      );

  String _dateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  bool _hasPlanningTimeRemainingToday(int questionCount) {
    if (_isInstitutionBlockingZumre || _cachedZumreSlots.isEmpty) {
      return false;
    }

    final now = _istanbulNow();
    final nowMinutes = now.hour * 60 + now.minute;
    final duration = _estimatedMinutesForQuestionCount(questionCount);

    for (final slot in _cachedZumreSlots) {
      final startMin = _timeToMinutes('${slot['start']}');
      final endMin = _timeToMinutes('${slot['end']}');
      if (endMin <= startMin) continue;

      final nextStart =
          nowMinutes < startMin ? startMin : (((nowMinutes ~/ 5) + 1) * 5);

      if (nextStart + duration <= endMin) {
        return true;
      }
    }

    return false;
  }

  List<String> _planningDateKeys({
    int questionCount = 1,
  }) {
    final today = _istanbulNow();
    final startOffset = _hasPlanningTimeRemainingToday(questionCount) ? 0 : 1;

    return List.generate(_appointmentPlanningDayCount, (index) {
      final dayOffset = startOffset + index;
      return _dateKey(
        DateTime(today.year, today.month, today.day + dayOffset),
      );
    });
  }

  List<String> _upcomingAppointmentDateKeys() {
    final today = _istanbulNow();

    return List.generate(_appointmentPlanningMaxOffsetDays + 1, (index) {
      return _dateKey(DateTime(today.year, today.month, today.day + index));
    });
  }

  DateTime _parseDateKey(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length != 3) return _istanbulNow();

    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return _istanbulNow();
    }

    return DateTime(year, month, day);
  }

  DateTime _appointmentDateTimeInIstanbul(Object? value) {
    if (value is Timestamp) {
      return value.toDate().toUtc().add(const Duration(hours: 3));
    }

    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toUtc().add(const Duration(hours: 3));
      }
    }

    return _istanbulNow();
  }

  String _formatPlanningDay(String dateKey) {
    const weekdays = [
      'Pzt',
      'Sal',
      'Çar',
      'Per',
      'Cum',
      'Cmt',
      'Paz',
    ];
    const months = [
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
    ];

    final date = _parseDateKey(dateKey);
    final todayKey = _dateKey(_istanbulNow());
    if (dateKey == todayKey) return 'Bugün';

    return '${weekdays[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
  }

  String _formatAppointmentDate(Object? value) {
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    final date = _appointmentDateTimeInIstanbul(value);
    return '${date.day} ${months[date.month - 1]}';
  }

  String _formatAppointmentClock(Object? value) {
    final date = _appointmentDateTimeInIstanbul(value);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  _AppointmentSlot _appointmentSlotFromMap(Map<String, dynamic> data) {
    return _AppointmentSlot(
      start: data['start']?.toString() ?? '',
      end: data['end']?.toString() ?? '',
      scheduledStart: data['scheduledStart']?.toString() ?? '',
      scheduledEnd: data['scheduledEnd']?.toString() ?? '',
    );
  }

  Future<_AppointmentAvailabilityResult> _loadAppointmentAvailability({
    required String subject,
    required int questionCount,
    required String dateKey,
  }) async {
    final callable = _functions.httpsCallable('getAppointmentAvailability');
    final response = await callable.call<Map<String, dynamic>>({
      'subject': subject,
      'questionCount': questionCount,
      'dateKey': dateKey,
    });
    final data = response.data;
    final rawTeachers = data['teachers'];
    final teachers = <_AppointmentTeacherOption>[];

    if (rawTeachers is List) {
      for (final rawTeacher in rawTeachers) {
        if (rawTeacher is! Map) continue;

        final teacherMap = Map<String, dynamic>.from(rawTeacher);
        final rawSlots = teacherMap['slots'];
        final slots = <_AppointmentSlot>[];

        if (rawSlots is List) {
          for (final rawSlot in rawSlots) {
            if (rawSlot is Map) {
              slots.add(_appointmentSlotFromMap(
                Map<String, dynamic>.from(rawSlot),
              ));
            }
          }
        }

        if (slots.isEmpty) continue;

        teachers.add(
          _AppointmentTeacherOption(
            id: teacherMap['teacherId']?.toString() ?? '',
            name: teacherMap['teacherName']?.toString() ?? 'Öğretmen',
            slots: slots,
          ),
        );
      }
    }

    teachers.sort((a, b) => a.name.compareTo(b.name));
    return _AppointmentAvailabilityResult(
      teachers: teachers.where((teacher) => teacher.id.isNotEmpty).toList(),
      message: data['message']?.toString(),
    );
  }

  String _appointmentErrorMessage(
    FirebaseFunctionsException error,
    String fallback,
  ) {
    final message = error.message?.trim();
    if (message == null || message.isEmpty) return fallback;

    final technicalMessages = {
      'internal',
      'unknown',
      'deadline-exceeded',
      'unavailable',
    };

    if (technicalMessages.contains(message.toLowerCase())) {
      return fallback;
    }

    return message;
  }

  String _newAppointmentIdempotencyKey(String userId) {
    return '$userId-${DateTime.now().microsecondsSinceEpoch}';
  }

  bool _appointmentIsFuture(Object? value) {
    if (value is Timestamp) {
      return value.toDate().isAfter(DateTime.now());
    }

    if (value is String) {
      final parsed = DateTime.tryParse(value);
      return parsed != null && parsed.isAfter(DateTime.now());
    }

    return false;
  }

  Future<void> _cancelAppointment(String appointmentId) async {
    final confirm = await _studentConfirmDialog(
      title: 'Planlı zümre iptal edilsin mi?',
      message: 'Planlı zümrenizi iptal etmek istediğinize emin misiniz?',
      confirmText: 'İptal Et',
      icon: Icons.event_busy_rounded,
      color: Colors.orangeAccent,
    );

    if (!confirm || !mounted) return;

    try {
      final callable = _functions.httpsCallable('cancelAppointment');
      await callable.call<Map<String, dynamic>>({
        'appointmentId': appointmentId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Planlı zümre iptal edildi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Planlı zümre şu anda iptal edilemedi.'),
        ),
      );
    }
  }

  int _cooldownUntil = 0;
  int _remainingCooldownSeconds = 0;

  Timer? _cooldownTimer;
  Timer? _zumrePillTimer;
  StreamSubscription? _queueSubscription;
  StreamSubscription<DocumentSnapshot>? _studentSubscription;
  StreamSubscription<DocumentSnapshot>? _runtimeStateSubscription;
  List<Map<String, dynamic>> _cachedZumreSlots = [];
  bool _cachedZumreIsWeekend = false;
  bool _isInstitutionBlockingZumre = false;
  static const Duration _runtimeStateMaxAge = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    _listenStudentInfo();
    _findAndListenActiveQueue();
    _listenRuntimeScheduleState();
    _listenGuidanceAppointment();
    _zumrePillTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshZumrePillFromCache(),
    );
  }

  int _timeToMinutes(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return 0;

    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;

    return hour * 60 + minute;
  }

  String _dayKey(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'monday';
      case DateTime.tuesday:
        return 'tuesday';
      case DateTime.wednesday:
        return 'wednesday';
      case DateTime.thursday:
        return 'thursday';
      case DateTime.friday:
        return 'friday';
      case DateTime.saturday:
        return 'saturday';
      case DateTime.sunday:
        return 'sunday';
      default:
        return 'monday';
    }
  }

  List<Map<String, dynamic>> _scheduleSlotsFromRaw(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map>().map((slot) {
      return {
        'start': '${slot['start']}',
        'end': '${slot['end']}',
      };
    }).toList();
  }

  Map<String, dynamic> _dailyScheduleFromData(
    Map<String, dynamic> data,
    DateTime now,
  ) {
    final weeklySchedule = data['weeklySchedule'];
    final dayKey = _dayKey(now);
    final daily = weeklySchedule is Map ? weeklySchedule[dayKey] : null;

    if (daily is Map) {
      return {
        'closed': daily['closed'] == true,
        'zumreSlots': _scheduleSlotsFromRaw(daily['zumreSlots']),
      };
    }

    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    return {
      'closed': false,
      'zumreSlots': _scheduleSlotsFromRaw(
        isWeekend ? data['weekendSlots'] : data['weekdaySlots'],
      ),
    };
  }

  bool _isFreshRuntimeState(Map<String, dynamic>? data) {
    if (data == null ||
        data['isZumreOpen'] is! bool ||
        data['isLunchBreak'] is! bool ||
        data['updatedAt'] is! Timestamp) {
      return false;
    }

    final updatedAt = (data['updatedAt'] as Timestamp).toDate();
    final age = DateTime.now().difference(updatedAt);

    return age >= Duration.zero && age <= _runtimeStateMaxAge;
  }

  String _todayDateKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  String? _institutionBlockMessage(Map<String, dynamic>? data) {
    if (data == null) return null;

    final mode = '${data['institutionMode'] ?? 'active'}';
    if (mode == 'closed' && data['closedDate'] == _todayDateKey()) {
      return 'Kurum bugün kapalıdır.';
    }

    final examEndsAt = data['examEndsAt'];
    if (mode == 'exam' &&
        examEndsAt is Timestamp &&
        examEndsAt.toDate().isAfter(DateTime.now())) {
      return 'Deneme modu aktif. Zümre sırası geçici olarak kapalı.';
    }

    return null;
  }

  Map<String, dynamic>? _runtimeZumreState(Map<String, dynamic>? data) {
    final institutionMessage = _institutionBlockMessage(data);
    if (institutionMessage != null) {
      return {
        'isZumreOpen': false,
        'isLunchBreak': false,
        'message': institutionMessage,
      };
    }

    if (!_isFreshRuntimeState(data)) return null;

    return {
      'isZumreOpen': data!['isZumreOpen'] == true,
      'isLunchBreak': data['isLunchBreak'] == true,
      'message': null,
    };
  }

  void _listenRuntimeScheduleState() {
    _runtimeStateSubscription?.cancel();
    _guidanceAppointmentSubscription?.cancel();
    _runtimeStateSubscription = _firestore
        .collection('settings')
        .doc('runtimeState')
        .snapshots()
        .listen((snapshot) async {
      await _checkLocalZumreAvailability(runtimeData: snapshot.data());
    }, onError: (_) async {
      await _checkLocalZumreAvailability();
    });
  }

  Map<String, dynamic> _zumreUiStateFromSlots(
    DateTime now,
    List<Map<String, dynamic>> slots,
    bool isWeekend,
  ) {
    final nowMinutes = now.hour * 60 + now.minute;
    var slotText = '';
    var nextZumreText = '';
    int? remainingMinutes;
    var isZumreOpen = false;

    for (final slot in slots) {
      final start = '${slot['start']}';
      final end = '${slot['end']}';
      final startMin = _timeToMinutes(start);
      final endMin = _timeToMinutes(end);

      if (endMin <= startMin) continue;

      if (nowMinutes >= startMin && nowMinutes < endMin) {
        isZumreOpen = true;
        slotText = '$start - $end';
        remainingMinutes = endMin - nowMinutes;
        break;
      }
    }

    if (!isZumreOpen && slots.isNotEmpty) {
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
        nextZumreText = 'Sonraki zümre: ${futureSlots.first['start']}';
      } else {
        nextZumreText = isWeekend
            ? 'Bugünkü zümre tamamlandı'
            : 'Yarın zümre ${slots.first['start']}';
      }
    }

    return {
      'isZumreOpen': isZumreOpen,
      'slotText': slotText,
      'nextZumreText': nextZumreText,
      'remainingMinutes': remainingMinutes,
    };
  }

  void _refreshZumrePillFromCache() {
    if (_isInstitutionBlockingZumre) return;
    if (_cachedZumreSlots.isEmpty || !mounted) return;

    final uiState = _zumreUiStateFromSlots(
      DateTime.now(),
      _cachedZumreSlots,
      _cachedZumreIsWeekend,
    );
    final isOpen = uiState['isZumreOpen'] == true;
    final remainingMinutes = uiState['remainingMinutes'];

    setState(() {
      _isZumreOpenNow = isOpen;
      _zumreSlotText = isOpen ? uiState['slotText']?.toString() ?? '' : '';
      _nextZumreText = isOpen ? '' : uiState['nextZumreText']?.toString() ?? '';
      _zumreRemainingMinutes =
          isOpen && remainingMinutes is int ? remainingMinutes : null;
    });
  }

  Future<bool> _checkLocalZumreAvailability({
    Map<String, dynamic>? runtimeData,
  }) async {
    final now = DateTime.now();
    final doc =
        await _firestore.collection('settings').doc('zumreSchedule').get();

    final data = doc.data() ?? {};
    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    final dailySchedule = _dailyScheduleFromData(data, now);
    final isClosedDay = dailySchedule['closed'] == true;
    final slots = isClosedDay
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(dailySchedule['zumreSlots']);
    _cachedZumreSlots = slots;
    _cachedZumreIsWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

    final zumreUiState = _zumreUiStateFromSlots(now, slots, isWeekend);
    final isZumreOpen = zumreUiState['isZumreOpen'] == true;

    var effectiveZumreOpen = isZumreOpen;
    var effectiveLunch = false;
    String? runtimeMessage;

    try {
      final runtimeState = runtimeData != null
          ? _runtimeZumreState(runtimeData)
          : _runtimeZumreState(
              (await _firestore
                      .collection('settings')
                      .doc('runtimeState')
                      .get())
                  .data(),
            );

      if (runtimeState != null) {
        effectiveZumreOpen = runtimeState['isZumreOpen'] ?? isZumreOpen;
        effectiveLunch = runtimeState['isLunchBreak'] ?? false;
        runtimeMessage = runtimeState['message']?.toString();
      }
    } catch (_) {}

    String message;

    if (runtimeMessage != null) {
      message = runtimeMessage;
    } else if (effectiveLunch) {
      message = 'Şu an öğle arası. Zümre sırası geçici olarak kapalı.';
    } else if (!effectiveZumreOpen) {
      message = 'Şu an zümre saati aktif değil.';
    } else {
      message = 'Zümre saati aktif. Sıra alabilirsiniz.';
    }

    if (!mounted) return false;

    setState(() {
      final remainingMinutes = zumreUiState['remainingMinutes'];

      _isInstitutionBlockingZumre = runtimeMessage != null;
      _isZumreOpenNow = effectiveZumreOpen;
      _isLunchNow = effectiveLunch;
      _zumreMessage = message;
      _zumreSlotText =
          effectiveZumreOpen ? zumreUiState['slotText']?.toString() ?? '' : '';
      _nextZumreText = effectiveZumreOpen
          ? ''
          : zumreUiState['nextZumreText']?.toString() ?? '';
      _zumreRemainingMinutes = effectiveZumreOpen && remainingMinutes is int
          ? remainingMinutes
          : null;
    });

    return true;
  }

  @override
  void dispose() {
    _queueSubscription?.cancel();
    _cooldownTimer?.cancel();
    _zumrePillTimer?.cancel();
    _studentSubscription?.cancel();
    _runtimeStateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _findAndListenActiveQueue() async {
    final userId = _auth.currentUser!.uid;

    try {
      final snapshot = await _firestore
          .collection('queues')
          .where('studentId', isEqualTo: userId)
          .where(
            'status',
            whereIn: ['waiting', 'in_progress'],
          )
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        if (!mounted) return;

        setState(() {
          _isInQueue = false;
          _currentQueueId = null;
          _currentTeacherName = null;
          _queuePosition = 0;
          _estimatedWaitMinutes = null;
        });

        return;
      }

      final queueDoc = snapshot.docs.first;
      final data = queueDoc.data();

      if (!mounted) return;

      setState(() {
        _isInQueue = true;
        _currentQueueId = queueDoc.id;
      });

      final teacherName = data['teacherName']?.toString();

      if (teacherName != null && teacherName.isNotEmpty) {
        setState(() {
          _currentTeacherName = teacherName;
        });
      } else if (data['teacherId'] != null) {
        await _getCurrentTeacherName(
          data['teacherId'].toString(),
        );
      }

      await _listenToQueue(queueDoc.id);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Aktif sıra kontrol edilemedi: $e'),
        ),
      );
    }
  }

  void _listenStudentInfo() {
    final user = _auth.currentUser!;
    _studentSubscription?.cancel();
    _studentSubscription =
        _firestore.collection('users').doc(user.uid).snapshots().listen((doc) {
      if (!doc.exists || !mounted) return;

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
      } else if (_cooldownUntil != 0 || _remainingCooldownSeconds != 0) {
        _cooldownTimer?.cancel();

        if (mounted) {
          setState(() {
            _cooldownUntil = 0;
            _remainingCooldownSeconds = 0;
          });
        }
      }
    });
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

  Future<void> _listenToQueue(String queueId) async {
    _queueSubscription?.cancel();

    final initialQueueDoc =
        await _firestore.collection('queues').doc(queueId).get();

    if (!initialQueueDoc.exists) {
      if (!mounted) return;

      setState(() {
        _isInQueue = false;
        _currentQueueId = null;
        _currentTeacherName = null;
        _queuePosition = 0;
        _estimatedWaitMinutes = null;
      });
      return;
    }

    final teacherId = initialQueueDoc.data()?['teacherId']?.toString();
    if (teacherId == null || teacherId.isEmpty) return;

    _queueSubscription = _firestore
        .collection('queues')
        .where('teacherId', isEqualTo: teacherId)
        .where('status', whereIn: ['waiting', 'in_progress'])
        .snapshots()
        .listen((snapshot) async {
          final docs = snapshot.docs.toList();
          final currentQueueDocs = docs.where((doc) => doc.id == queueId);

          if (currentQueueDocs.isEmpty) {
            await _queueSubscription?.cancel();
            _queueSubscription = null;

            if (!mounted) return;

            setState(() {
              _isInQueue = false;
              _currentQueueId = null;
              _currentTeacherName = null;
              _queuePosition = 0;
              _estimatedWaitMinutes = null;
            });
            return;
          }

          final currentQueueDoc = currentQueueDocs.first;
          final data = currentQueueDoc.data();
          final status = data['status'];
          final teacherNameFromQueue = data['teacherName']?.toString();

          if (teacherNameFromQueue != null && teacherNameFromQueue.isNotEmpty) {
            _currentTeacherName = teacherNameFromQueue;
          } else {
            await _getCurrentTeacherName(teacherId);
          }

          if (!mounted) return;

          if (status == 'in_progress') {
            setState(() {
              _isInQueue = true;
              _currentQueueId = queueId;
              _queuePosition = 0;
              _estimatedWaitMinutes = null;
            });
            return;
          }

          if (status != 'waiting') {
            setState(() {
              _isInQueue = false;
              _currentQueueId = null;
              _currentTeacherName = null;
              _queuePosition = 0;
              _estimatedWaitMinutes = null;
            });
            return;
          }

          QueryDocumentSnapshot<Map<String, dynamic>>? activeDoc;

          for (final doc in docs) {
            if (doc.data()['status'] == 'in_progress') {
              activeDoc = doc;
              break;
            }
          }

          final waitingDocs =
              docs.where((doc) => doc.data()['status'] == 'waiting').toList();

          waitingDocs.sort((a, b) => compareQueuePriority(a.data(), b.data()));

          int position = 1;
          var estimatedWaitMinutes = activeDoc == null
              ? 0
              : _activeQueueRemainingMinutes(activeDoc.data());

          for (final doc in waitingDocs) {
            if (doc.id == queueId) break;
            final queueData = doc.data();
            estimatedWaitMinutes += _queueEstimatedMinutes(queueData) +
                _toInt(queueData['extraMinutes']);
            position++;
          }

          setState(() {
            _isInQueue = true;
            _currentQueueId = queueId;
            _queuePosition = position;
            _estimatedWaitMinutes = estimatedWaitMinutes;
          });
        });
  }

  Future<void> _joinQueue() async {
    if (_isRoutingQueue) return;

    if (_remainingCooldownSeconds > 0 ||
        DateTime.now().millisecondsSinceEpoch < _cooldownUntil) {
      return;
    }

    if (_selectedSubject == null || _selectedSubject!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen bir ders seçin.'),
        ),
      );
      return;
    }

    if (!_isZumreOpenNow || _isLunchNow) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_zumreMessage)),
      );
      return;
    }

    if (_isInStudySession) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Şu anda etütte görünüyorsunuz. Etüt bitince zümre sırası alabilirsiniz.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isRoutingQueue = true;
    });

    try {
      final callable = _functions.httpsCallable('routeQueueRequest');
      final response = await callable.call<Map<String, dynamic>>({
        'subject': _selectedSubject,
        'questionCount': _selectedQuestionCount,
        if (_selectedTeacherId != null) 'teacherId': _selectedTeacherId,
      });
      final data = response.data;
      final queueId = data['queueId']?.toString();

      if (queueId == null || queueId.isEmpty) {
        throw Exception('Sıra kaydı oluşturulamadı.');
      }

      if (mounted) {
        setState(() {
          _isInQueue = true;
          _currentQueueId = queueId;
          _currentTeacherName =
              data['teacherName']?.toString() ?? _selectedTeacherName;
          _queuePosition = 1;
          _estimatedWaitMinutes = null;
        });
      }

      if (!mounted) return;
      await _listenToQueue(queueId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sıranız alındı! Lütfen bekleyin.')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Sıra alınamadı.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sıra alınamadı: $e'),
          ),
        );
      }

      return;
    } finally {
      if (mounted) {
        setState(() {
          _isRoutingQueue = false;
        });
      }
    }
  }

  Future<bool> _studentConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    required IconData icon,
    required Color color,
  }) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 26),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF12103F),
                      Color(0xFF261369),
                      Color(0xFF071A3A),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.white24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: color.withValues(alpha: 0.35)),
                      ),
                      child: Icon(icon, color: color, size: 30),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.35,
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
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('Vazgeç'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pop(ctx, true),
                            icon: Icon(icon, size: 18),
                            label: Text(confirmText),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: color,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
  }

  Future<bool> _confirmLogout({
    required Color color,
  }) async {
    return _studentConfirmDialog(
      title: 'Çıkış Yap',
      message: 'Oturumu kapatmak istediğinize emin misiniz?',
      confirmText: 'Çıkış Yap',
      icon: Icons.logout_rounded,
      color: color,
    );
  }

  Future<void> _cancelQueue() async {
    if (_currentQueueId == null) return;

    final confirm = await _studentConfirmDialog(
      title: 'Sıranızı iptal ediyorsunuz',
      message:
          'İptal ederseniz 2 dakika yeni sıra alamazsınız. Devam etmek istiyor musunuz?',
      confirmText: 'Evet',
      icon: Icons.timer_off_rounded,
      color: Colors.orangeAccent,
    );

    if (confirm == true) {
      try {
        final cooldownDate = DateTime.now().add(const Duration(minutes: 2));

        await _firestore.collection('queues').doc(_currentQueueId).update({
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .update({
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
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İptal sırasında hata: $e')),
        );
      }
    }
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
    final remaining = _zumreRemainingMinutes;
    final text = active
        ? remaining != null && remaining <= 5 && remaining > 0
            ? 'Bitime $remaining dk'
            : _zumreSlotText.isEmpty
                ? 'Zümre Aktif'
                : 'Zümre Aktif • $_zumreSlotText'
        : _nextZumreText.isEmpty
            ? 'Zümre Kapalı'
            : _nextZumreText;
    final color = active ? Colors.greenAccent : Colors.orangeAccent;

    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.circle : Icons.schedule_rounded,
            color: color,
            size: active ? 8 : 14,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectGrid({bool fillHeight = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const crossAxisSpacing = 8.0;
        const mainAxisSpacing = 8.0;
        const minItemHeight = 48.0;
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;
        final itemWidth = (availableWidth - crossAxisSpacing) / 2;
        final rawItemHeight = fillHeight && availableHeight.isFinite
            ? (availableHeight - (mainAxisSpacing * 3)) / 4
            : itemWidth / (availableWidth < 390 ? 2.5 : 2.35);
        final shouldScroll = fillHeight && rawItemHeight < minItemHeight;
        final itemHeight =
            shouldScroll ? minItemHeight : rawItemHeight.clamp(1.0, 120.0);
        final aspectRatio = itemHeight > 0
            ? itemWidth / itemHeight
            : availableWidth < 390
                ? 2.5
                : 2.35;

        return GridView.count(
          shrinkWrap: !fillHeight,
          padding: EdgeInsets.zero,
          physics: shouldScroll
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: crossAxisSpacing,
          mainAxisSpacing: mainAxisSpacing,
          childAspectRatio: aspectRatio,
          children: _subjectOptions
              .map((subject) => _subjectCard(
                    subject.name,
                    subject.icon,
                    subject.color,
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildQuestionCountSelector() {
    final options = [1, 2, 3, 4];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kaç soru çözdüreceksin?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: options.map((questionCount) {
              final selected = _selectedQuestionCount == questionCount;
              final label = questionCount == 4 ? '4+' : '$questionCount';

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setState(() {
                        _selectedQuestionCount = questionCount;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF6C3DFF)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected
                              ? Colors.white.withValues(alpha: 0.55)
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
          const SizedBox(height: 8),
          Text(
            'Tahmini çözüm süresi: ~${_estimatedMinutesForQuestionCount(_selectedQuestionCount)} dk',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherSelector() {
    final hasManualTeacher = _selectedTeacherId != null;
    final canSelectTeacher = _isZumreOpenNow && !_isLunchNow;
    final subtitle = !canSelectTeacher
        ? 'Zümre kapalıyken öğretmen seçilemez'
        : hasManualTeacher
            ? '${_selectedTeacherName ?? 'Seçili öğretmen'} seçildi'
            : 'En uygun öğretmene yönlendir (önerilen)';

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: canSelectTeacher ? _showTeacherPickerDialog : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (hasManualTeacher ? Colors.greenAccent : Colors.amber)
                    .withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasManualTeacher
                    ? Icons.person_pin_rounded
                    : Icons.auto_awesome_rounded,
                color: canSelectTeacher
                    ? hasManualTeacher
                        ? Colors.greenAccent
                        : Colors.amber
                    : Colors.white54,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Öğretmen Seç',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: canSelectTeacher ? Colors.white70 : Colors.white38,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTeacherPickerDialog() async {
    if (_selectedSubject == null || _selectedSubject!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce bir ders seçin.')),
      );
      return;
    }

    String? dialogTeacherId = _selectedTeacherId;
    String? dialogTeacherName = _selectedTeacherName;
    final teachersFuture = _loadAvailableTeacherChoices();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              child: Container(
                constraints:
                    const BoxConstraints(maxWidth: 520, maxHeight: 620),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF12103F),
                      Color(0xFF261369),
                      Color(0xFF071A3A),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.support_agent_rounded,
                            color: Colors.greenAccent,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Öğretmen Seç',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'İstersen en uygun öğretmene yönlendirebiliriz.',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: FutureBuilder<List<_TeacherChoice>>(
                        future: teachersFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(28),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            );
                          }

                          final teachers = snapshot.data ?? [];
                          final hasAvailableTeachers = teachers.isNotEmpty;

                          return SingleChildScrollView(
                            child: Column(
                              children: [
                                _teacherOptionTile(
                                  selected: hasAvailableTeachers &&
                                      dialogTeacherId == null,
                                  icon: Icons.auto_awesome_rounded,
                                  title: 'En Uygun Öğretmene Yönlendir',
                                  subtitle: hasAvailableTeachers
                                      ? 'Önerilen'
                                      : 'Müsait öğretmen yok',
                                  color: Colors.amber,
                                  enabled: hasAvailableTeachers,
                                  onTap: hasAvailableTeachers
                                      ? () {
                                          setDialogState(() {
                                            dialogTeacherId = null;
                                            dialogTeacherName = null;
                                          });
                                        }
                                      : null,
                                ),
                                const SizedBox(height: 8),
                                if (teachers.isEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.10),
                                      ),
                                    ),
                                    child: const Text(
                                      'Bu ders için şu anda listelenebilecek müsait öğretmen yok.',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        height: 1.35,
                                      ),
                                    ),
                                  )
                                else
                                  ...teachers.map(
                                    (teacher) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _teacherOptionTile(
                                        selected: dialogTeacherId == teacher.id,
                                        icon: Icons.person_rounded,
                                        title: teacher.name,
                                        subtitle: teacher.subjects.isEmpty
                                            ? 'Branş bilgisi yok'
                                            : teacher.subjects.join(' • '),
                                        color: Colors.greenAccent,
                                        onTap: () {
                                          setDialogState(() {
                                            dialogTeacherId = teacher.id;
                                            dialogTeacherName = teacher.name;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    FutureBuilder<List<_TeacherChoice>>(
                      future: teachersFuture,
                      builder: (context, snapshot) {
                        final hasAvailableTeachers =
                            (snapshot.data ?? []).isNotEmpty;
                        final canApplySelection =
                            !_isRoutingQueue && hasAvailableTeachers;

                        return SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: canApplySelection
                                ? () {
                                    setState(() {
                                      _selectedTeacherId = dialogTeacherId;
                                      _selectedTeacherName = dialogTeacherName;
                                    });
                                    Navigator.pop(ctx);
                                  }
                                : null,
                            icon: const Icon(Icons.add_rounded),
                            label: Text(
                              hasAvailableTeachers
                                  ? dialogTeacherId == null
                                      ? 'En Uygun Öğretmen'
                                      : 'Seçimi Uygula'
                                  : 'Müsait Öğretmen Yok',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  Colors.white.withValues(alpha: 0.14),
                              disabledForegroundColor: Colors.white54,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        );
                      },
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

  void _listenGuidanceAppointment() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _guidanceAppointmentSubscription = _firestore
        .collection('guidanceAppointments')
        .where('studentId', isEqualTo: uid)
        .snapshots()
        .listen((snapshot) {
      final active = snapshot.docs.where((doc) {
        final status = doc.data()['status'];
        return status != 'cancelled' && status != 'completed' && status != 'no_show';
      }).toList();
      active.sort((a, b) {
        final at = a.data()['createdAt'] as Timestamp?;
        final bt = b.data()['createdAt'] as Timestamp?;
        return (bt?.millisecondsSinceEpoch ?? 0).compareTo(at?.millisecondsSinceEpoch ?? 0);
      });
      if (!mounted) return;
      setState(() {
        if (active.isEmpty) {
          _guidanceAppointment = null;
        } else {
          final d = active.first.data();
          _guidanceAppointment = {
            'id': active.first.id,
            'counselor': '${d['counselorName'] ?? 'Rehberlik Servisi'}',
            'reason': '${d['reason'] ?? ''}',
            'day': '${d['dayLabel'] ?? ''}',
            'time': '${d['time'] ?? ''}',
            'status': _guidanceStatusLabel('${d['status'] ?? 'pending'}'),
          };
        }
      });
    });
  }

  String _guidanceStatusLabel(String status) {
    switch (status) {
      case 'approved': return 'Onaylandı';
      case 'in_progress': return 'Görüşmede';
      case 'completed': return 'Tamamlandı';
      case 'cancelled': return 'İptal Edildi';
      case 'no_show': return 'Gelmedi';
      default: return 'Onay Bekliyor';
    }
  }

  Future<void> _showGuidanceAppointmentDemo() async {
    final counselorSnapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'guidance')
        .get();
    final counselors = counselorSnapshot.docs
        .map((d) => {
              'id': d.id,
              'name': '${d.data()['fullName'] ?? d.data()['name'] ?? 'Rehberlik Servisi'}',
            })
        .toList();
    if (!mounted) return;
    if (counselors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şu anda kayıtlı rehberlikçi bulunmuyor.')),
      );
      return;
    }
    const reasons = [
      'Akademik takip',
      'Sınav / hedef planlama',
      'Ders çalışma düzeni',
      'Motivasyon',
      'Genel görüşme',
    ];
    const days = [
      'Yarın • 26 Eyl',
      'Pazartesi • 28 Eyl',
      'Salı • 29 Eyl',
    ];
    const times = ['10:20', '11:10', '13:40', '14:30', '15:20'];

    String? counselor;
    String? counselorId;
    String? reason;
    String? day;
    String? time;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final ready =
              counselor != null && reason != null && day != null && time != null;
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF081D3A), Color(0xFF123A61), Color(0xFF071A3A)],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.forum_rounded,
                            color: Colors.cyanAccent, size: 25),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Rehberlik Randevusu',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.bold)),
                            SizedBox(height: 3),
                            Text('Görüşme için rehberlikçi, konu ve saat seçin.',
                                style: TextStyle(
                                    color: Colors.white60, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _planningSectionTitle('Rehberlikçi'),
                          ...counselors.map((item) { final name = item['name']!; return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  onTap: () => setDialogState(() { counselor = name; counselorId = item['id']; }),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: counselor == name
                                          ? Colors.cyanAccent.withValues(alpha: 0.12)
                                          : Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: counselor == name
                                            ? Colors.cyanAccent.withValues(alpha: 0.65)
                                            : Colors.white12,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor:
                                              Colors.white.withValues(alpha: 0.10),
                                          child: const Icon(Icons.person_rounded,
                                              color: Colors.white70, size: 20),
                                        ),
                                        const SizedBox(width: 11),
                                        Expanded(
                                          child: Text(name,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600)),
                                        ),
                                        Icon(
                                          counselor == name
                                              ? Icons.check_circle_rounded
                                              : Icons.chevron_right_rounded,
                                          color: counselor == name
                                              ? Colors.cyanAccent
                                              : Colors.white38,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ); }),
                          const SizedBox(height: 8),
                          _planningSectionTitle('Görüşme Konusu'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: reasons
                                .map((item) => _planningChoiceChip(
                                      label: item,
                                      selected: reason == item,
                                      enabled: true,
                                      onTap: () =>
                                          setDialogState(() => reason = item),
                                      color: Colors.cyanAccent,
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 16),
                          _planningSectionTitle('Tarih'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: days
                                .map((item) => _planningChoiceChip(
                                      label: item,
                                      selected: day == item,
                                      enabled: true,
                                      onTap: () => setDialogState(() {
                                        day = item;
                                        time = null;
                                      }),
                                      color: Colors.cyanAccent,
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 16),
                          _planningSectionTitle('Uygun Saatler'),
                          if (day == null)
                            _planningInfoBox('Önce bir tarih seçin.')
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: times
                                  .map((item) => _planningChoiceChip(
                                        label: item,
                                        selected: time == item,
                                        enabled: true,
                                        centered: true,
                                        onTap: () =>
                                            setDialogState(() => time = item),
                                        color: Colors.cyanAccent,
                                      ))
                                  .toList(),
                            ),
                          const SizedBox(height: 14),
                          _planningInfoBox(
                            'Randevu talebiniz rehberlik birimine iletilecektir. Görüşme saatiniz rehberlikçi tarafından gerektiğinde güncellenebilir.',
                            color: Colors.cyanAccent,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: ready
                          ? () async {
                              final uid = _auth.currentUser!.uid;
                              await _firestore.collection('guidanceAppointments').add({
                                'studentId': uid,
                                'studentName': _studentName ?? 'Öğrenci',
                                'counselorId': counselorId,
                                'counselorName': counselor,
                                'reason': reason,
                                'dayLabel': day,
                                'time': time,
                                'status': 'pending',
                                'createdAt': FieldValue.serverTimestamp(),
                                'updatedAt': FieldValue.serverTimestamp(),
                              });
                              if (!mounted) return;
                              setState(() {
                                _guidanceAppointment = {
                                  'counselor': counselor!,
                                  'reason': reason!,
                                  'day': day!,
                                  'time': time!,
                                  'status': 'Onay Bekliyor',
                                };
                              });
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Randevu talebiniz oluşturuldu: $counselor • $day • $time',
                                  ),
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.event_available_rounded),
                      label: const Text('Randevu Talebi Oluştur',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00A6C7),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            Colors.white.withValues(alpha: 0.14),
                        disabledForegroundColor: Colors.white54,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showPlanAppointmentDialog() async {
    final user = _auth.currentUser;
    if (user == null) return;

    var dateKeys = _planningDateKeys(questionCount: _selectedQuestionCount);
    String selectedDateKey = dateKeys.first;
    String selectedSubject = _selectedSubject ?? _subjectOptions.first.name;
    int selectedQuestionCount = _selectedQuestionCount;
    List<_AppointmentTeacherOption> teachers = [];
    String? availabilityMessage;
    String? availabilityError;
    String? selectedTeacherId;
    String? selectedTeacherName;
    _AppointmentSlot? selectedSlot;
    bool isLoadingAvailability = false;
    bool isCreating = false;
    bool didRequestInitialAvailability = false;
    String? bookingIdempotencyKey;
    int requestVersion = 0;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> refreshAvailability() async {
              if (!dateKeys.contains(selectedDateKey)) {
                selectedDateKey = dateKeys.first;
              }

              final version = ++requestVersion;
              setDialogState(() {
                isLoadingAvailability = true;
                availabilityError = null;
                availabilityMessage = null;
                selectedTeacherId = null;
                selectedTeacherName = null;
                selectedSlot = null;
              });

              try {
                final result = await _loadAppointmentAvailability(
                  subject: selectedSubject,
                  questionCount: selectedQuestionCount,
                  dateKey: selectedDateKey,
                );

                if (!context.mounted || version != requestVersion) return;

                setDialogState(() {
                  teachers = result.teachers;
                  availabilityMessage = result.message;
                  isLoadingAvailability = false;
                });
              } on FirebaseFunctionsException catch (e) {
                if (!context.mounted || version != requestVersion) return;

                setDialogState(() {
                  teachers = [];
                  availabilityError = _appointmentErrorMessage(
                    e,
                    'Müsait saatler şu anda yüklenemedi. Lütfen tekrar deneyin.',
                  );
                  isLoadingAvailability = false;
                });
              } catch (e) {
                if (!context.mounted || version != requestVersion) return;

                setDialogState(() {
                  teachers = [];
                  availabilityError =
                      'Müsait saatler şu anda yüklenemedi. Lütfen tekrar deneyin.';
                  isLoadingAvailability = false;
                });
              }
            }

            Future<void> createAppointment() async {
              final teacherId = selectedTeacherId;
              final slot = selectedSlot;
              if (teacherId == null || slot == null || isCreating) return;

              setDialogState(() {
                isCreating = true;
              });

              try {
                final callable = _functions.httpsCallable('createAppointment');
                bookingIdempotencyKey ??=
                    _newAppointmentIdempotencyKey(user.uid);
                await callable.call<Map<String, dynamic>>({
                  'subject': selectedSubject,
                  'questionCount': selectedQuestionCount,
                  'teacherId': teacherId,
                  'scheduledStart': slot.scheduledStart,
                  'idempotencyKey': bookingIdempotencyKey,
                });

                if (!context.mounted) return;
                Navigator.pop(ctx);

                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Planlı zümre oluşturuldu: $selectedSubject • '
                      '${selectedTeacherName ?? 'Öğretmen'} • ${slot.start}',
                    ),
                  ),
                );
              } on FirebaseFunctionsException catch (e) {
                if (!context.mounted) return;
                setDialogState(() {
                  isCreating = false;
                  availabilityError = _appointmentErrorMessage(
                    e,
                    'Planlı zümre şu anda oluşturulamadı. Lütfen tekrar deneyin.',
                  );
                  selectedSlot = null;
                });
                if (e.code == 'already-exists' ||
                    e.code == 'resource-exhausted' ||
                    e.code == 'failed-precondition') {
                  await refreshAvailability();
                }
              } catch (e) {
                if (!context.mounted) return;
                setDialogState(() {
                  isCreating = false;
                  availabilityError =
                      'Planlı zümre şu anda oluşturulamadı. Lütfen tekrar deneyin.';
                  selectedSlot = null;
                });
              }
            }

            if (!didRequestInitialAvailability) {
              didRequestInitialAvailability = true;
              Future.microtask(refreshAvailability);
            }

            final canCreate = selectedTeacherId != null &&
                selectedSlot != null &&
                !isCreating;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              child: Container(
                constraints:
                    const BoxConstraints(maxWidth: 560, maxHeight: 720),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF12103F),
                      Color(0xFF261369),
                      Color(0xFF071A3A),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.event_available_rounded,
                            color: Colors.amber,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Zümre Planla',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Uygun öğretmen ve saat seçin.',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed:
                              isCreating ? null : () => Navigator.pop(ctx),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _planningSectionTitle('Gün'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: dateKeys.map((dateKey) {
                                return _planningChoiceChip(
                                  label: _formatPlanningDay(dateKey),
                                  selected: selectedDateKey == dateKey,
                                  enabled:
                                      !isLoadingAvailability && !isCreating,
                                  onTap: () {
                                    if (selectedDateKey == dateKey) return;
                                    selectedDateKey = dateKey;
                                    bookingIdempotencyKey = null;
                                    refreshAvailability();
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 14),
                            _planningSectionTitle('Ders'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _subjectOptions.map((subject) {
                                return _planningChoiceChip(
                                  label: subject.name,
                                  selected: selectedSubject == subject.name,
                                  enabled:
                                      !isLoadingAvailability && !isCreating,
                                  onTap: () {
                                    if (selectedSubject == subject.name) {
                                      return;
                                    }
                                    selectedSubject = subject.name;
                                    bookingIdempotencyKey = null;
                                    refreshAvailability();
                                  },
                                  color: subject.color,
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 14),
                            _planningSectionTitle('Soru'),
                            Row(
                              children: [1, 2, 3, 4].map((questionCount) {
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 7),
                                    child: _planningChoiceChip(
                                      label: questionCount == 4
                                          ? '4+'
                                          : '$questionCount',
                                      selected: selectedQuestionCount ==
                                          questionCount,
                                      enabled:
                                          !isLoadingAvailability && !isCreating,
                                      centered: true,
                                      onTap: () {
                                        if (selectedQuestionCount ==
                                            questionCount) {
                                          return;
                                        }
                                        selectedQuestionCount = questionCount;
                                        dateKeys = _planningDateKeys(
                                          questionCount: selectedQuestionCount,
                                        );
                                        bookingIdempotencyKey = null;
                                        refreshAvailability();
                                      },
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tahmini süre: ~${_estimatedMinutesForQuestionCount(selectedQuestionCount)} dk',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _planningSectionTitle('Öğretmen ve Saat'),
                            if (isLoadingAvailability)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 26),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            else if (availabilityError != null)
                              _planningInfoBox(
                                availabilityError!,
                                color: Colors.orangeAccent,
                              )
                            else if (teachers.isEmpty)
                              _planningInfoBox(
                                availabilityMessage ??
                                    'Bu seçim için uygun randevu saati yok.',
                              )
                            else
                              ...teachers.map((teacher) {
                                final teacherSelected =
                                    selectedTeacherId == teacher.id;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 9),
                                  child: _planningTeacherTile(
                                    teacher: teacher,
                                    selected: teacherSelected,
                                    selectedSlot:
                                        teacherSelected ? selectedSlot : null,
                                    onTeacherTap: () {
                                      setDialogState(() {
                                        selectedTeacherId = teacher.id;
                                        selectedTeacherName = teacher.name;
                                        selectedSlot = teacher.slots.first;
                                        bookingIdempotencyKey = null;
                                      });
                                    },
                                    onSlotTap: (slot) {
                                      setDialogState(() {
                                        selectedTeacherId = teacher.id;
                                        selectedTeacherName = teacher.name;
                                        selectedSlot = slot;
                                        bookingIdempotencyKey = null;
                                      });
                                    },
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: canCreate ? createAppointment : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C3DFF),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              Colors.white.withValues(alpha: 0.14),
                          disabledForegroundColor: Colors.white54,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: isCreating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Planlı Zümre Oluştur',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
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

  Widget _planningSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _planningChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color color = const Color(0xFF6C3DFF),
    bool centered = false,
    bool enabled = true,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 38),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: !enabled
              ? Colors.white.withValues(alpha: 0.05)
              : selected
                  ? color.withValues(alpha: 0.75)
                  : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.55)
                : Colors.white24,
          ),
        ),
        child: Align(
          alignment: centered ? Alignment.center : Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _planningInfoBox(String text, {Color color = Colors.white70}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12.5,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _planningTeacherTile({
    required _AppointmentTeacherOption teacher,
    required bool selected,
    required _AppointmentSlot? selectedSlot,
    required VoidCallback onTeacherTap,
    required ValueChanged<_AppointmentSlot> onSlotTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected
            ? Colors.greenAccent.withValues(alpha: 0.13)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? Colors.greenAccent.withValues(alpha: 0.55)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTeacherTap,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.greenAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        teacher.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${teacher.slots.length} uygun saat',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? Colors.greenAccent : Colors.white38,
                ),
              ],
            ),
          ),
          if (selected) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: teacher.slots.map((slot) {
                return _planningChoiceChip(
                  label: '${slot.start}-${slot.end}',
                  selected: selectedSlot?.scheduledStart == slot.scheduledStart,
                  onTap: () => onSlotTap(slot),
                  color: Colors.greenAccent,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _teacherOptionTile({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    final effectiveColor = enabled ? color : Colors.white54;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected && enabled
              ? color.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected && enabled
                ? color.withValues(alpha: 0.75)
                : Colors.white12,
            width: selected && enabled ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: effectiveColor.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: effectiveColor),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled ? Colors.white : Colors.white54,
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled ? Colors.white60 : Colors.white38,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: selected && enabled ? 1 : 0,
              child: const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
              ),
            ),
          ],
        ),
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
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.26)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? Colors.white : color, size: 26),
            const SizedBox(height: 5),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
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
        color: Colors.orange.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.orangeAccent.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
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
              color: Colors.orange.withValues(alpha: 0.20),
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

  Stream<QuerySnapshot<Map<String, dynamic>>>? _verifiedNoShowWarningStream() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return null;

    final historyStart = DateTime.now().subtract(const Duration(days: 14));
    return _firestore
        .collection('appointments')
        .where('studentId', isEqualTo: userId)
        .where('status', isEqualTo: 'no_show')
        .where('noShowVerificationStatus', isEqualTo: 'verified')
        .where(
          'noShowVerifiedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(historyStart),
        )
        .orderBy('noShowVerifiedAt', descending: true)
        .snapshots();
  }

  bool _isVerifiedNoShowPopupEligible(Map<String, dynamic> data) {
    final verifiedAt = data['noShowVerifiedAt'];
    if (verifiedAt is! Timestamp) return false;

    final age = DateTime.now().difference(verifiedAt.toDate());
    return !age.isNegative && age <= const Duration(days: 7);
  }

  Future<void> _showVerifiedNoShowWarningDialog(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (!mounted || docs.isEmpty) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17123F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Planlı Zümre Katılım Uyarısı',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  docs.length == 1
                      ? 'Planladığınız zümre saatinde öğretmeniniz sizin için zaman ayırmasına rağmen katılım sağlamadığınız tespit edildi. Planlı zümrelere zamanında katılmanız beklenmektedir. Tekrarlanan katılmama durumları rehberlik birimi ve veli ile paylaşılabilir.'
                      : '${docs.length} planlı zümre katılım uyarınız bulunuyor. Planlı zümrelere zamanında katılmanız beklenmektedir. Tekrarlanan katılmama durumları rehberlik birimi ve veli ile paylaşılabilir.',
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                ...docs.take(5).map((doc) {
                  final data = doc.data();
                  final start = data['scheduledStart'];
                  final teacher = data['teacherName']?.toString() ?? 'Öğretmen';
                  final subject = data['subject']?.toString() ?? 'Ders';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      '${_formatAppointmentDate(start)} '
                      '${_formatAppointmentClock(start)} • $subject • $teacher',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C3DFF),
                foregroundColor: Colors.white,
              ),
              child: const Text('Anladım'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showVerifiedNoShowHistoryDialog(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF17123F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Planlı Zümre Bildirimleri',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (docs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Son 14 gün içinde bildirim bulunmuyor.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                else
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: docs.map((doc) {
                          final data = doc.data();
                          final start = data['scheduledStart'];
                          final teacher =
                              data['teacherName']?.toString() ?? 'Öğretmen';
                          final subject = data['subject']?.toString() ?? 'Ders';

                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_formatAppointmentDate(start)} '
                                  '${_formatAppointmentClock(start)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$subject • $teacher',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                const Text(
                                  'Katılım sağlanmadı',
                                  style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVerifiedNoShowBell() {
    final stream = _verifiedNoShowWarningStream();
    if (stream == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final popupDocs = docs
            .where((doc) => _isVerifiedNoShowPopupEligible(doc.data()))
            .toList();

        if (!_didShowVerifiedNoShowWarning && popupDocs.isNotEmpty) {
          _didShowVerifiedNoShowWarning = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showVerifiedNoShowWarningDialog(popupDocs);
          });
        }

        final hasBadge = docs.isNotEmpty;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Planlı Zümre Bildirimleri',
              onPressed: () => _showVerifiedNoShowHistoryDialog(docs),
              icon: const Icon(
                Icons.notifications_none_rounded,
                color: Colors.white,
              ),
            ),
            if (hasBadge)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Colors.orangeAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildUpcomingAppointmentsSection() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return const SizedBox.shrink();

    final dateKeys = _upcomingAppointmentDateKeys();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('appointments')
          .where('studentId', isEqualTo: userId)
          .where('status', isEqualTo: 'scheduled')
          .where('dateKey', whereIn: dateKeys)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final appointments = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aStart = _appointmentDateTimeInIstanbul(
              a.data()['scheduledStart'],
            );
            final bStart = _appointmentDateTimeInIstanbul(
              b.data()['scheduledStart'],
            );
            return aStart.compareTo(bStart);
          });

        if (appointments.isEmpty) return const SizedBox.shrink();

        final first = appointments.first.data();
        final count = appointments.length;
        final subject = first['subject']?.toString() ?? 'Ders';
        final teacher = first['teacherName']?.toString() ?? 'Öğretmen';
        final start = first['scheduledStart'];
        final summary = count == 1
            ? '$subject • ${_formatAppointmentClock(start)}'
            : '$count planlı zümre • sıradaki ${_formatAppointmentClock(start)}';

        return Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _showUpcomingAppointmentsSheet(appointments),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_available_rounded,
                      color: Colors.amber.shade300,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Planlı',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        count == 1 ? '$summary • $teacher' : summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white54,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showUpcomingAppointmentsSheet(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> appointments,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF171039),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        final maxHeight = MediaQuery.of(ctx).size.height * 0.70;

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.event_available_rounded,
                        color: Colors.amber.shade300,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Planlı Zümreler',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: appointments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final doc = appointments[index];
                        final data = doc.data();
                        final subject = data['subject']?.toString() ?? 'Ders';
                        final teacher =
                            data['teacherName']?.toString() ?? 'Öğretmen';
                        final start = data['scheduledStart'];
                        final questionCount = _toInt(
                          data['questionCount'],
                          fallback: 1,
                        );
                        final questionLabel = questionCount == 4
                            ? '4+ soru'
                            : '$questionCount soru';
                        final canCancel = _appointmentIsFuture(start);

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      subject,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      teacher,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12.5,
                                        height: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${_formatAppointmentDate(start)} · '
                                      '${_formatAppointmentClock(start)} · '
                                      '$questionLabel',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (canCancel) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'İptal Et',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.orangeAccent,
                                  ),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _cancelAppointment(doc.id);
                                  },
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHomeView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 820;
        return Padding(
          padding: EdgeInsets.fromLTRB(18, compact ? 8 : 12, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeCard(),
              SizedBox(height: compact ? 8 : 10),
              _buildCooldownCard(),
              _buildUpcomingAppointmentsSection(),
              SizedBox(height: compact ? 6 : 8),
              _buildGuidanceAppointmentDemoCard(),
              SizedBox(height: compact ? 6 : 8),
              if (_isInStudySession) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.orangeAccent.withValues(alpha: 0.25),
                    ),
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
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: compact ? 6 : 8),
              Expanded(child: _buildSubjectGrid(fillHeight: true)),
              SizedBox(height: compact ? 8 : 10),
              _buildQuestionCountSelector(),
              SizedBox(height: compact ? 8 : 9),
              _buildTeacherSelector(),
              SizedBox(height: compact ? 8 : 10),
              _buildQueueActions(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.12),
            const Color(0xFF6C3DFF).withValues(alpha: 0.22),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
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
                              fontSize: 23,
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
              _buildVerifiedNoShowBell(),
              IconButton(
                tooltip: 'Çıkış Yap',
                onPressed: () async {
                  final logout = await _confirmLogout(
                    color: Colors.indigo,
                  );

                  if (!logout) return;

                  await _auth.signOut();
                },
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

  Future<void> _showGuidanceAppointmentDetails() async {
    final appointment = _guidanceAppointment;
    if (appointment == null) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF081D3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(children: [
          Icon(Icons.event_available_rounded, color: Colors.cyanAccent),
          SizedBox(width: 10),
          Expanded(child: Text('Rehberlik Randevusu', style: TextStyle(color: Colors.white))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _guidanceDetailRow(Icons.person_rounded, 'Rehberlikçi', appointment['counselor']!),
            _guidanceDetailRow(Icons.chat_bubble_outline_rounded, 'Görüşme konusu', appointment['reason']!),
            _guidanceDetailRow(Icons.calendar_today_rounded, 'Tarih', appointment['day']!),
            _guidanceDetailRow(Icons.schedule_rounded, 'Saat', appointment['time']!),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.28)),
              ),
              child: const Row(children: [
                Icon(Icons.hourglass_top_rounded, color: Colors.amberAccent, size: 19),
                SizedBox(width: 8),
                Text('Onay Bekliyor', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final cancel = await showDialog<bool>(
                context: ctx,
                builder: (confirmCtx) => AlertDialog(
                  title: const Text('Randevu iptal edilsin mi?'),
                  content: const Text('Oluşturduğunuz rehberlik randevu talebi iptal edilecektir.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(confirmCtx, false), child: const Text('Vazgeç')),
                    TextButton(onPressed: () => Navigator.pop(confirmCtx, true), child: const Text('Randevuyu İptal Et')),
                  ],
                ),
              );
              if (cancel == true && mounted) {
                final id = appointment['id'];
                if (id != null) {
                  await _firestore.collection('guidanceAppointments').doc(id).update({
                    'status': 'cancelled',
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                }
                if (!mounted) return;
                setState(() => _guidanceAppointment = null);
                if (ctx.mounted) Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Rehberlik randevunuz iptal edildi.')),
                );
              }
            },
            icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
            label: const Text('İptal Et', style: TextStyle(color: Colors.redAccent)),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
        ],
      ),
    );
  }

  Widget _guidanceDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Colors.cyanAccent, size: 19),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ])),
      ]),
    );
  }

  Widget _buildGuidanceAppointmentDemoCard() {
    return InkWell(
      onTap: _guidanceAppointment == null
          ? _showGuidanceAppointmentDemo
          : _showGuidanceAppointmentDetails,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF00A6C7).withValues(alpha: 0.18),
              Colors.white.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.cyanAccent.withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.forum_rounded, color: Colors.cyanAccent, size: 23),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rehberlik Randevusu',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text(
                    _guidanceAppointment == null
                        ? 'Rehberlikçini seç, uygun gün ve saati planla.'
                        : '${_guidanceAppointment!['day']} • ${_guidanceAppointment!['time']} • ${_guidanceAppointment!['status']}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Icon(
              _guidanceAppointment == null ? Icons.arrow_forward_ios_rounded : Icons.visibility_outlined,
              color: _guidanceAppointment == null ? Colors.white38 : Colors.cyanAccent,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueActions() {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: _buildJoinQueueButton(),
        ),
        const SizedBox(width: 9),
        Expanded(
          flex: 4,
          child: _buildPlanAppointmentButton(),
        ),
      ],
    );
  }

  Widget _buildPlanAppointmentButton() {
    return SizedBox(
      height: 54,
      child: OutlinedButton.icon(
        onPressed: _isRoutingQueue ? null : _showPlanAppointmentDialog,
        icon: const Icon(Icons.event_available_rounded, size: 19),
        label: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Zümre Planla',
            maxLines: 1,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.amber.shade200,
          disabledForegroundColor: Colors.white38,
          side: BorderSide(
            color: Colors.amber.shade200.withValues(alpha: 0.60),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: Colors.white.withValues(alpha: 0.06),
        ),
      ),
    );
  }

  Widget _buildJoinQueueButton() {
    final canJoinQueue = _selectedSubject != null &&
        _remainingCooldownSeconds <= 0 &&
        _isZumreOpenNow &&
        !_isLunchNow &&
        !_isInStudySession &&
        !_isRoutingQueue;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: canJoinQueue ? _joinQueue : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6C3DFF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: _isRoutingQueue
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Sıranız hazırlanıyor...',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              : const Text(
                  'Sıra Al',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
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
            ? Colors.greenAccent.withValues(alpha: 0.12)
            : Colors.orangeAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (_isZumreOpenNow && !_isLunchNow)
              ? Colors.greenAccent.withValues(alpha: 0.30)
              : Colors.orangeAccent.withValues(alpha: 0.30),
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
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: isTeacherWorking
                    ? Colors.green.withValues(alpha: 0.18)
                    : Colors.blue.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isTeacherWorking ? Icons.support_agent : Icons.hourglass_top,
                color:
                    isTeacherWorking ? Colors.greenAccent : Colors.blueAccent,
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
                  : 'Bekleme sıranız: $_queuePosition',
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
                  color: Colors.white.withValues(alpha: 0.10),
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
                color: Colors.white.withValues(alpha: 0.08),
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
                        : '~${_estimatedWaitMinutes ?? 0} dk',
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
                  isTeacherWorking ? 'İptal Edilemez' : 'Sırayı İptal Et',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.12),
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
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
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
          ]),
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
          child: _isInQueue ? _buildQueueView() : _buildHomeView(),
        ),
      ),
    );
  }
}
