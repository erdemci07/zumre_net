import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}
class _TimeTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length > 4) {
      digits = digits.substring(0, 4);
    }

    final buffer = StringBuffer();

    for (int i = 0; i < digits.length; i++) {
      if (i == 2) buffer.write(':');
      buffer.write(digits[i]);
    }

    final formatted = buffer.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
class _TeacherHomeScreenState extends State<TeacherHomeScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late TabController _tabController;

  String _teacherStatus = 'available';
  String? _teacherName;
  String? _teacherSubject;
  Map<String, List<Map<String, String>>> _weeklyAvailability = {};
  bool _isZumreOpenNow = false;
  bool _isTeacherWorkingNow = false;
  bool _isLunchNow = false;
  String _scheduleMessage = 'Kontrol ediliyor...';
  bool _availabilityOverride = false;

  int _todaySolved = 0;

  Timer? _activeQuestionTimer;
  String? _activeTimerQueueId;
  int? _activeTimerLimitMinutes;
  String? _warnedQueueKey;
  bool _isTimeDialogOpen = false;
  int _elapsedSeconds = 0;

@override
void initState() {
  super.initState();
  _tabController = TabController(length: 2, vsync: this);
  _initTeacherPage();
}

Future<void> _initTeacherPage() async {
  await _loadTeacherInfo();
  await _loadTeacherAvailability();
  await _loadTodaySolvedCount();
  await _checkScheduleAvailability();
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

bool _isNowInSlots(
  DateTime now,
  List<Map<String, dynamic>> slots,
) {
  final nowMinutes = now.hour * 60 + now.minute;

  for (final slot in slots) {
    final start = _timeToMinutes('${slot['start']}');
    final end = _timeToMinutes('${slot['end']}');

    if (end <= start) {
  continue;
}

if (nowMinutes >= start && nowMinutes <= end) {
  return true;
}
  }

  return false;
}

  @override
  void dispose() {
    _tabController.dispose();
    _activeQuestionTimer?.cancel();
    super.dispose();
  }

  String _formatElapsed(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

 void _resetActiveQuestionTimer() {
  _activeQuestionTimer?.cancel();
  _activeQuestionTimer = null;
  _activeTimerQueueId = null;
  _activeTimerLimitMinutes = null;
  _warnedQueueKey = null;
  _isTimeDialogOpen = false;
  _elapsedSeconds = 0;
}

  void _startActiveQuestionTimer({
    required String queueId,
    required Timestamp? startedAt,
    required int estimatedMinutes,
    required int extraMinutes,
  }) {
    if (startedAt == null) return;

    final totalMinutes = estimatedMinutes + extraMinutes;

    if (_activeTimerQueueId == queueId &&
        _activeTimerLimitMinutes == totalMinutes) {
      return;
    }

    _activeTimerQueueId = queueId;
    _activeTimerLimitMinutes = totalMinutes;

    _activeQuestionTimer?.cancel();

    final initialElapsed =
        DateTime.now().difference(startedAt.toDate()).inSeconds;
        _elapsedSeconds = initialElapsed;

    _activeQuestionTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        final elapsed =
            DateTime.now().difference(startedAt.toDate()).inSeconds;

        if (mounted) {
          setState(() {
            _elapsedSeconds = elapsed;
          });
        }

        final totalLimitSeconds = totalMinutes * 60;
        final warningKey = '$queueId-$totalMinutes';

        if (elapsed >= totalLimitSeconds &&
            _warnedQueueKey != warningKey &&
            !_isTimeDialogOpen) {
          _warnedQueueKey = warningKey;
          _showTimeExceededDialog(queueId);
        }
      },
    );
  }
 Future<bool> _confirmAction({
  required String title,
  required String message,
  required String confirmText,
  IconData icon = Icons.help_outline,
  Color color = Colors.green,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF06312E),
                Color(0xFF008A5C),
              ],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: color.withOpacity(0.18),
                child: Icon(icon, color: color, size: 36),
              ),
              const SizedBox(height: 16),
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
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Vazgeç'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(confirmText),
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

  return result == true;
}
Future<void> _checkScheduleAvailability() async {
  final now = DateTime.now();
  final todayKey = _dayKey(now);
  final isWeekend =
      now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

  final settingsDoc =
      await _firestore.collection('settings').doc('zumreSchedule').get();

  final settings = settingsDoc.data() ?? {};

  final rawZumreSlots = isWeekend
      ? List.from(settings['weekendSlots'] ?? [])
      : List.from(settings['weekdaySlots'] ?? []);

  final zumreSlots = rawZumreSlots
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  final lunch = Map<String, dynamic>.from(settings['lunchBreak'] ?? {});

  final teacherSlots = (_weeklyAvailability[todayKey] ?? [])
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  final isZumreOpen = _isNowInSlots(now, zumreSlots);
  final isTeacherWorking = _isNowInSlots(now, teacherSlots);

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

  if (!isZumreOpen) {
    message = 'Şu an zümre saati aktif değil.';
  } else if (isLunch) {
    message = 'Şu an öğle arası.';
} else if (!isTeacherWorking && !_availabilityOverride) {
  message = 'Bugün çalışma programınıza göre kurumda değilsiniz.';
} else if (_teacherStatus == 'absent') {
    message = 'Kurumda değil olarak görünüyorsunuz.';
  } else if (_teacherStatus == 'break') {
    message = 'Şu an moladasınız.';
  } else {
    message = 'Zümre saati aktif. Öğrenci ekleyebilirsiniz.';
  }

  if (!mounted) return;

if (!isTeacherWorking && !_availabilityOverride && _teacherStatus != 'absent') {
  final uid = _auth.currentUser!.uid;

  await _firestore.collection('users').doc(uid).update({
    'teacherStatus': 'absent',
  });
}

if (!mounted) return;

setState(() {
  _isZumreOpenNow = isZumreOpen;
  _isTeacherWorkingNow = isTeacherWorking;
  _isLunchNow = isLunch;
  _scheduleMessage = message;

  if (!isTeacherWorking && !_availabilityOverride) {
    _teacherStatus = 'absent';
  }
});
}

Future<void> _showAvailabilityDialog() async {
  final days = {
    'monday': 'Pazartesi',
    'tuesday': 'Salı',
    'wednesday': 'Çarşamba',
    'thursday': 'Perşembe',
    'friday': 'Cuma',
    'saturday': 'Cumartesi',
    'sunday': 'Pazar',
  };

  final temp = <String, List<Map<String, String>>>{};

  for (final key in days.keys) {
    temp[key] = List<Map<String, String>>.from(
      (_weeklyAvailability[key] ?? []).map(
        (e) => {
          'start': e['start'] ?? '09:00',
          'end': e['end'] ?? '17:00',
        },
      ),
    );
  }

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.all(22),
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
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Kurumda Bulunduğum Saatler',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Hangi gün ve saat aralıklarında kurumda olduğunuzu belirtin.',
                      style: TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 18),

                    ...days.entries.map((day) {
                      final slots = temp[day.key] ?? [];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    day.value,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setDialogState(() {
                                      temp[day.key]!.add({
                                        'start': '09:00',
                                        'end': '17:00',
                                      });
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.add_circle,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                              ],
                            ),
                            if (slots.isEmpty)
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Bu gün kurumda değilim.',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              )
                            else
                              ...List.generate(slots.length, (index) {
                                final slot = slots[index];

                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _teacherTimeField(
                                          label: 'Başlangıç',
                                          initialValue: slot['start'] ?? '09:00',
                                          onChanged: (value) {
                                            setDialogState(() {
                                              slot['start'] = value;
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _teacherTimeField(
                                          label: 'Bitiş',
                                          initialValue: slot['end'] ?? '10:00',
                                          onChanged: (value) {
                                            setDialogState(() {
                                              slot['end'] = value;
                                            });
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          setDialogState(() {
                                            temp[day.key]!.removeAt(index);
                                          });
                                        },
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Vazgeç'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final uid = _auth.currentUser!.uid;

                              await _firestore.collection('users').doc(uid).update({
                                'weeklyAvailability': temp,
                                'updatedAt': FieldValue.serverTimestamp(),
                              });

                              if (!mounted) return;

                              setState(() {
                                _weeklyAvailability = temp;
                              });
                              await _checkScheduleAvailability();

                              if (ctx.mounted) Navigator.pop(ctx);

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Kurum saatleriniz güncellendi'),
                                ),
                              );
                            },
                            child: const Text('Kaydet'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
Future<void> _loadTeacherAvailability() async {
  final uid = _auth.currentUser!.uid;
  final doc = await _firestore.collection('users').doc(uid).get();

  final data = doc.data();
  final raw = Map<String, dynamic>.from(data?['weeklyAvailability'] ?? {});

  final parsed = <String, List<Map<String, String>>>{};

  for (final entry in raw.entries) {
    final list = List.from(entry.value ?? []);
    parsed[entry.key] = list.map((e) {
      final item = Map<String, dynamic>.from(e);
      return {
        'start': '${item['start']}',
        'end': '${item['end']}',
      };
    }).toList();
  }

  if (!mounted) return;

  setState(() {
    _weeklyAvailability = parsed;
  });
}

  Future<void> _showTimeExceededDialog(String queueId) async {
    if (!mounted) return;

    _isTimeDialogOpen = true;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF06312E),
                  Color(0xFF008A5C),
                ],
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.timer_off,
                    color: Colors.orangeAccent,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tahmini süre doldu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Süre ekleyebilir veya soruyu çözüldü olarak işaretleyebilirsiniz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await _addExtraMinute(queueId, 1);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                        ),
                        child: const Text('+1 dk'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await _addExtraMinute(queueId, 3);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                        ),
                        child: const Text('+3 dk'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _markAsSolved(queueId);
                    },
                    
                    icon: const Icon(Icons.check),
                    label: const Text('Çözüldü'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    
                  ),
                ),
              ],
            ),
          ),
        );
      },
      
    );
    
    

    _isTimeDialogOpen = false;
  }

  Future<void> _addExtraMinute(String queueId, int minute) async {
    await _firestore.collection('queues').doc(queueId).update({
      'extraMinutes': FieldValue.increment(minute),
    });

    _activeTimerQueueId = null;
    _activeTimerLimitMinutes = null;
    _warnedQueueKey = null;
  }

  String _statusText(String status) {
    switch (status) {
      case 'available':
        return 'Müsait';
      case 'break':
        return 'Molada';
      case 'absent':
        return 'Kurumda Değil';
      default:
        return 'Bilinmeyen';
    }
  }

  Future<void> _loadTeacherInfo() async {
    final uid = _auth.currentUser!.uid;
    final doc = await _firestore.collection('users').doc(uid).get();

    if (!doc.exists || !mounted) return;

    final data = doc.data();

    String? subject;
    if (data?['subjects'] is List && data!['subjects'].isNotEmpty) {
      subject = data['subjects'][0];
    } else if (data?['subject'] != null) {
      subject = data?['subject'];
    }

    setState(() {
      _teacherName = data?['name'] ?? data?['email'] ?? 'Öğretmen';
      _teacherSubject = subject ?? 'Ders';
      _teacherStatus = data?['teacherStatus'] ?? 'available';
    });
  }

  Future<void> _updateTeacherStatus(String status) async {
    final uid = _auth.currentUser!.uid;

    await _firestore.collection('users').doc(uid).update({
      'teacherStatus': status,
    });

    if (!mounted) return;

    setState(() {
      _teacherStatus = status;
    });
    if (status != 'available') {
  _availabilityOverride = false;
}

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status == 'available'
              ? 'Durumunuz müsait olarak güncellendi'
              : status == 'break'
                  ? 'Durumunuz molada olarak güncellendi'
                  : 'Durumunuz kurumda değil olarak güncellendi',
        ),
      ),
    );
  }

  Future<void> _showStatusChangeDialog(String value) async {
    if (_teacherStatus == value) return;
    await _checkScheduleAvailability();

if (value == 'available' && !_isTeacherWorkingNow) {
  final override = await _confirmAction(
    title: 'Program dışında görünüyorsunuz',
    message:
        'Bugünkü çalışma programınıza göre kurumda değilsiniz. Buna rağmen durumunuzu müsait olarak değiştirmek istiyor musunuz?',
    confirmText: 'Müsait Yap',
    icon: Icons.warning_amber_rounded,
    color: Colors.orangeAccent,
  );

  if (!override) return;

  setState(() {
    _availabilityOverride = true;
  });
}

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Durum değiştirilsin mi?'),
        content: Text(
          '${_statusText(_teacherStatus)} durumundan '
          '${_statusText(value)} durumuna geçmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _updateTeacherStatus(value);
    }
  }

  Future<void> _loadTodaySolvedCount() async {
    try {
      final uid = _auth.currentUser!.uid;

      final snapshot = await _firestore
          .collection('queues')
          .where('teacherId', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .get();

      final today = DateTime.now();
      int count = 0;

      for (final doc in snapshot.docs) {
        final completedAt = doc.data()['completedAt'] as Timestamp?;

        if (completedAt != null) {
          final date = completedAt.toDate();

          if (date.year == today.year &&
              date.month == today.month &&
              date.day == today.day) {
            count++;
          }
        }
      }

      if (mounted) {
        setState(() {
          _todaySolved = count;
        });
      }
    } catch (_) {}
  }

  Future<void> _showAddStudentDialog() async {
    await _checkScheduleAvailability();

final canAddStudent =
    _teacherStatus == 'available' &&
    _isZumreOpenNow &&
    _isTeacherWorkingNow &&
    !_isLunchNow;

if (!canAddStudent) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_scheduleMessage)),
  );
  return;
}
    String? selectedStudentId;
    String? selectedStudentName;
    String searchText = '';

    final studentsSnapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'student')
        .get();

    final activeQueuesSnapshot = await _firestore
        .collection('queues')
        .where('status', whereIn: ['waiting', 'in_progress'])
        .get();

    final activeStudentIds = activeQueuesSnapshot.docs
        .map((doc) => doc.data()['studentId'])
        .where((id) => id != null)
        .toSet();

    final now = DateTime.now();

    final availableStudents = studentsSnapshot.docs.where((doc) {
      final data = doc.data();
      final cooldownUntil = data['cooldownUntil'] as Timestamp?;
      final isInCooldown =
          cooldownUntil != null && cooldownUntil.toDate().isAfter(now);

      final isInActiveQueue = activeStudentIds.contains(doc.id);

      return !isInActiveQueue && !isInCooldown;
    }).toList();

    if (availableStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Müsait kayıtlı öğrenci bulunamadı')),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          
          builder: (context, setDialogState) {
            final filteredStudents = availableStudents.where((doc) {
  final data = doc.data();
  final name = (data['fullName'] ?? data['name'] ?? data['email'] ?? '')
      .toString()
      .toLowerCase();

  final username = (data['username'] ?? '')
      .toString()
      .toLowerCase();

  final query = searchText.toLowerCase().trim();

  return query.isEmpty ||
      name.contains(query) ||
      username.contains(query);
}).toList();
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(22),
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
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withOpacity(0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_add,
                            color: Colors.greenAccent,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Öğrenci Ekle',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Sırada olmayan kayıtlı öğrencilerden birini seçin.',
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                    const SizedBox(height: 18),
                    TextField(
  style: const TextStyle(color: Colors.white),
  decoration: InputDecoration(
    hintText: 'Öğrenci ara...',
    hintStyle: const TextStyle(color: Colors.white54),
    prefixIcon: const Icon(Icons.search, color: Colors.white70),
    filled: true,
    fillColor: Colors.white.withOpacity(0.10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    ),
  ),
  onChanged: (value) {
    setDialogState(() {
      searchText = value;
      selectedStudentId = null;
      selectedStudentName = null;
    });
  },
),

const SizedBox(height: 12),
                    Container(
  height: 320,
  decoration: BoxDecoration(
    color: Colors.white.withOpacity(0.08),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: Colors.white12),
  ),
  child: filteredStudents.isEmpty
      ? const Center(
          child: Text(
            'Öğrenci bulunamadı',
            style: TextStyle(color: Colors.white60),
          ),
        )
      : ListView.builder(
          itemCount: filteredStudents.length,
          itemBuilder: (context, index) {
            final doc = filteredStudents[index];
            final data = doc.data();

            final fullName =
                data['fullName'] ??
                data['name'] ??
                data['email'] ??
                'Öğrenci';

            final className = data['className'] ?? '';
            final department = data['department'] ?? '';
            final selected = selectedStudentId == doc.id;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green,
                child: const Icon(
                  Icons.person,
                  color: Colors.white,
                ),
              ),
              title: Text(
                fullName,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                '$className • $department',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                ),
              ),
              trailing: selected
                  ? const Icon(
                      Icons.check_circle,
                      color: Colors.greenAccent,
                    )
                  : null,
              selected: selected,
              onTap: () {
                setDialogState(() {
                  selectedStudentId = doc.id;
                  selectedStudentName = fullName;
                });
              },
            );
          },
        ),
      ),
      const SizedBox(height: 22),
      SizedBox(
        width: double.infinity,
        height: 54,
                      child: ElevatedButton.icon(
                        onPressed: selectedStudentId == null
                            ? null
                            : () async {
                                try {
                                  final teacherId = _auth.currentUser!.uid;

                                  final activeSnapshot = await _firestore
                                      .collection('queues')
                                      .where('teacherId', isEqualTo: teacherId)
                                      .where('status', isEqualTo: 'in_progress')
                                      .get();

                                  final hasActiveQuestion =
                                      activeSnapshot.docs.isNotEmpty;

                                  final docRef = await _firestore
                                      .collection('queues')
                                      .add({
                                    'studentId': selectedStudentId,
                                    'studentName': selectedStudentName,
                                    'teacherId': teacherId,
                                    'teacherName': _teacherName ?? 'Öğretmen',
                                    'subject': _teacherSubject ?? 'Ders',
                                    'status': hasActiveQuestion
                                        ? 'waiting'
                                        : 'in_progress',
                                    'isManual': true,
                                    'questionCount': 1,
                                    'estimatedMinutes': 4,
                                    'extraMinutes': 0,
                                    'createdAt': Timestamp.now(),
                                    'startedAt': hasActiveQuestion
                                        ? null
                                        : Timestamp.now(),
                                  });

                                  await _firestore
                                      .collection('users')
                                      .doc(selectedStudentId)
                                      .update({
                                    'activeQueueId': docRef.id,
                                  });

                                  if (ctx.mounted) Navigator.pop(ctx);

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Öğrenci sıraya eklendi'),
                                    ),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Hata: $e')),
                                  );
                                }
                              },
                        icon: const Icon(Icons.add),
                        label: const Text(
                          'Sıraya Ekle',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              Colors.white.withOpacity(0.15),
                          disabledForegroundColor: Colors.white54,
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

  Future<void> _takeNextWaitingQueue() async {
    final uid = _auth.currentUser!.uid;

    final snapshot = await _firestore
        .collection('queues')
        .where('teacherId', isEqualTo: uid)
        .where('status', isEqualTo: 'waiting')
        .get();

    if (snapshot.docs.isEmpty) return;

    final waitingQueues = snapshot.docs.toList();

    waitingQueues.sort((a, b) {
      final aTime = a.data()['createdAt'] as Timestamp?;
      final bTime = b.data()['createdAt'] as Timestamp?;

      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;

      return aTime.compareTo(bTime);
    });

    final nextQueue = waitingQueues.first;

    await _firestore.collection('queues').doc(nextQueue.id).update({
      'status': 'in_progress',
      'startedAt': Timestamp.now(),
    });
  }

  Future<void> _markAsSolved(String queueId) async {
    try {
      _resetActiveQuestionTimer();

      await _firestore.collection('queues').doc(queueId).update({
        'status': 'completed',
        'completedAt': Timestamp.now(),
      });

      if (mounted) {
        setState(() {
          _todaySolved++;
        });
      }

      await Future.delayed(const Duration(milliseconds: 400));
      await _takeNextWaitingQueue();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Soru çözüldü olarak işaretlendi')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Çözüldü işlemi başarısız: $e')),
      );
    }
  }

  Future<void> _cancelQueue(String queueId) async {
    try {
      _resetActiveQuestionTimer();

      await _firestore.collection('queues').doc(queueId).update({
        'status': 'cancelled',
        'cancelledAt': Timestamp.now(),
      });

      await _takeNextWaitingQueue();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sıra iptal edildi')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }
  Future<void> _showTransferDialog({
  required String queueId,
  required String subject,
  required String studentName,
}) async {
  final currentTeacherId = _auth.currentUser!.uid;

  final teachersSnapshot = await _firestore
      .collection('users')
      .where('role', isEqualTo: 'teacher')
      .where('teacherStatus', isEqualTo: 'available')
      .where('subjects', arrayContains: subject)
      .get();

  final availableTeachers = teachersSnapshot.docs
      .where((doc) => doc.id != currentTeacherId)
      .toList();

  if (availableTeachers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Devredilebilecek müsait öğretmen bulunamadı.'),
      ),
    );
    return;
  }

  await showDialog(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(22),
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
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.lightBlueAccent.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.swap_horiz_rounded,
                      color: Colors.lightBlueAccent,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Öğrenciyi Devret',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$studentName isimli öğrenciyi aynı branştaki müsait bir öğretmene devredebilirsiniz.',
                  style: const TextStyle(color: Colors.white70, height: 1.35),
                ),
              ),

              const SizedBox(height: 16),

              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: availableTeachers.length,
                  itemBuilder: (context, index) {
                    final teacherDoc = availableTeachers[index];
                    final teacherData = teacherDoc.data();

                    final teacherName =
                        teacherData['fullName'] ??
                        teacherData['name'] ??
                        teacherData['email'] ??
                        'Öğretmen';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.09),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.green,
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(
                          '$teacherName',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          subject,
                          style: const TextStyle(color: Colors.white60),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: Colors.white70,
                        ),
                        onTap: () async {
                          final confirm = await _confirmAction(
                            title: 'Devretme onayı',
                            message:
                                '$studentName isimli öğrenci $teacherName öğretmenine devredilsin mi?',
                            confirmText: 'Devret',
                            icon: Icons.swap_horiz_rounded,
                            color: Colors.lightBlueAccent,
                          );

                          if (!confirm) return;

                          await _resetAndTransferQueue(
                            queueId: queueId,
                            newTeacherId: teacherDoc.id,
                            newTeacherName: '$teacherName',
                          );

                          if (ctx.mounted) Navigator.pop(ctx);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Öğrenci $teacherName öğretmenine devredildi.',
                              ),
                            ),
                          );
                        },
                      ),
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
}
Future<void> _resetAndTransferQueue({
  required String queueId,
  required String newTeacherId,
  required String newTeacherName,
}) async {
  _resetActiveQuestionTimer();

  final currentTeacherId = _auth.currentUser!.uid;

  await _firestore.collection('queues').doc(queueId).update({
    'teacherId': newTeacherId,
    'teacherName': newTeacherName,
    'status': 'waiting',
    'startedAt': null,
    'transferredAt': Timestamp.now(),
    'transferredFromTeacherId': currentTeacherId,
    'transferredFromTeacherName': _teacherName ?? 'Öğretmen',
  });

  await _takeNextWaitingQueue();
}

  Widget _miniTimeBox({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.greenAccent, size: 20),
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
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
  Widget _teacherTimeField({
  required String label,
  required String initialValue,
  required void Function(String value) onChanged,
}) {
  return TextFormField(
    initialValue: initialValue,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(4),
      _TimeTextInputFormatter(),
    ],
    style: const TextStyle(color: Colors.white),
    onChanged: onChanged,
  );
}

  Widget _buildActiveQuestion() {
    final teacherId = _auth.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('queues')
          .where('teacherId', isEqualTo: teacherId)
          .where('status', isEqualTo: 'in_progress')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          _resetActiveQuestionTimer();
          return _glassInfoCard(
            icon: Icons.error_outline,
            title: 'Aktif soru yüklenemedi',
            subtitle: '${snapshot.error}',
            iconColor: Colors.redAccent,
          );
        }

        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final activeQueues = snapshot.data!.docs;

        if (activeQueues.isEmpty) {
          _resetActiveQuestionTimer();

          return _glassInfoCard(
            icon: Icons.task_alt,
            title: 'Şu anda aktif sorunuz yok',
            subtitle:
                'Yeni öğrenci ekleyebilir veya bekleyen sıradan başlatabilirsiniz.',
            iconColor: Colors.greenAccent,
          );
        }

        final doc = activeQueues.first;
        final data = doc.data() as Map<String, dynamic>;

        final questionCount = _toInt(data['questionCount'], fallback: 1);
        final estimatedMinutes = _toInt(data['estimatedMinutes'], fallback: 4);
        final extraMinutes = _toInt(data['extraMinutes']);
        final startedAt = data['startedAt'] as Timestamp?;

        _startActiveQuestionTimer(
          queueId: doc.id,
          startedAt: startedAt,
          estimatedMinutes: estimatedMinutes,
          extraMinutes: extraMinutes,
        );

       return Container(
  width: double.infinity,
  margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    color: Colors.white.withOpacity(0.10),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: Colors.white.withOpacity(0.15)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.greenAccent.withOpacity(0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.support_agent,
              color: Colors.greenAccent,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Aktif Soru',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  data['studentName'] ?? 'Öğrenci',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  data['subject'] ?? 'Ders',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),

      const SizedBox(height: 14),

      Row(
        children: [
          Expanded(
            child: _miniTimeBox(
              title: 'Soru',
              value: '$questionCount',
              icon: Icons.menu_book,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _miniTimeBox(
              title: 'Tahmini',
              value: '${estimatedMinutes + extraMinutes} dk',
              icon: Icons.timer,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _miniTimeBox(
              title: 'Geçen',
              value: _formatElapsed(_elapsedSeconds),
              icon: Icons.access_time,
            ),
          ),
        ],
      ),

      const SizedBox(height: 16),

      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () async {
                final confirm = await _confirmAction(
                  title: 'Soru çözüldü mü?',
                  message:
                      'Bu öğrencinin sorusunu çözüldü olarak işaretlemek istiyor musunuz?',
                  confirmText: 'Çözüldü',
                );

                if (confirm) {
                  await _markAsSolved(doc.id);
                }
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Çözüldü'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _compactQueueAction(
            icon: Icons.swap_horiz_rounded,
            color: Colors.lightBlueAccent,
            tooltip: 'Devret',
            onTap: () async {
              await _showTransferDialog(
                queueId: doc.id,
                subject: data['subject'] ?? 'Ders',
                studentName: data['studentName'] ?? 'Öğrenci',
              );
            },
          ),
          _compactQueueAction(
            icon: Icons.close_rounded,
            color: Colors.redAccent,
            tooltip: 'İptal',
            onTap: () async {
              final confirm = await _confirmAction(
                title: 'Soru iptal edilsin mi?',
                message: 'Bu aktif soruyu iptal etmek istiyor musunuz?',
                confirmText: 'İptal Et',
              );

              if (confirm) {
                await _cancelQueue(doc.id);
              }
            },
          ),
        ],
      ),
    ],
  ),
);
      },
    );
  }

  Widget _glassInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingQueueList() {
    final teacherId = _auth.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('queues')
          .where('teacherId', isEqualTo: teacherId)
          .where('status', isEqualTo: 'waiting')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _glassInfoCard(
            icon: Icons.error_outline,
            title: 'Bekleyenler yüklenemedi',
            subtitle: '${snapshot.error}',
            iconColor: Colors.redAccent,
          );
        }

        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final queues = snapshot.data!.docs;

        queues.sort((a, b) {
          final aTime =
              (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          final bTime =
              (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;

          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;

          return aTime.compareTo(bTime);
        });

        if (queues.isEmpty) {
          return _glassInfoCard(
            icon: Icons.people_outline,
            title: 'Bekleyen öğrenci yok',
            subtitle: 'Sıraya yeni öğrenci geldiğinde burada görünecek.',
            iconColor: Colors.white70,
          );
        }

        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Bekleyen Öğrenciler',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            ...queues.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final isManual = data['isManual'] == true;
              final questionCount = _toInt(data['questionCount'], fallback: 1);
              final estimatedMinutes =
                  _toInt(data['estimatedMinutes'], fallback: 4);
              final extraMinutes = _toInt(data['extraMinutes']);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withOpacity(0.14)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: isManual ? Colors.orange : Colors.green,
                      child: Icon(
                        isManual ? Icons.person_add : Icons.person,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['studentName'] ?? 'Öğrenci',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${data['subject'] ?? 'Ders'} • $questionCount soru • ${estimatedMinutes + extraMinutes} dk',
                            style: const TextStyle(color: Colors.white60),
                          ),
                          if (isManual)
                            const Text(
                              'Öğretmen tarafından eklendi',
                              style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            print('Başlat butonuna basıldı: ${doc.id}');
                            await _firestore
                                .collection('queues')
                                .doc(doc.id)
                                .update({
                              'status': 'in_progress',
                              'startedAt': Timestamp.now(),
                            });
                            print('Soru başlatıldı: ${doc.id}');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(80, 38),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Başlat'),
                        ),
                      IconButton(
  icon: const Icon(
    Icons.delete_outline_rounded,
    color: Colors.redAccent,
  ),
  
  tooltip: 'Sırayı İptal Et',
  onPressed: () async {
    final confirm = await _confirmAction(
      title: 'Bekleyen öğrenci iptal edilsin mi?',
      message:
          '${data['studentName']} isimli öğrencinin sırasını iptal etmek istediğinize emin misiniz?',
      confirmText: 'İptal Et',
    );

    if (confirm) {
      await _cancelQueue(doc.id);
    }
  },
),
const SizedBox(height: 6),

OutlinedButton.icon(
  onPressed: () async {
    await _showTransferDialog(
      queueId: doc.id,
      subject: data['subject'] ?? 'Ders',
      studentName: data['studentName'] ?? 'Öğrenci',
    );
  },
  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
  label: const Text('Devret'),
  style: OutlinedButton.styleFrom(
    foregroundColor: Colors.lightBlueAccent,
    side: const BorderSide(color: Colors.lightBlueAccent),
    minimumSize: const Size(80, 34),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    ),
  ),
),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
Widget _compactQueueAction({
  required IconData icon,
  required Color color,
  required String tooltip,
  required VoidCallback onTap,
}) {
  return Container(
    width: 34,
    height: 34,
    margin: const EdgeInsets.only(left: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: IconButton(
      padding: EdgeInsets.zero,
      tooltip: tooltip,
      icon: Icon(icon, color: color, size: 18),
      onPressed: onTap,
    ),
  );
}

  Widget _buildWaitingQueues() {
  return ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.only(bottom: 32),
    children: [
      _buildTeacherHeader(),
      _buildStatusCard(),
      _buildActiveQuestion(),
      _buildWaitingQueueList(),
    ],
  );
}
Widget _buildRatingsPage() {
  return ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.only(bottom: 32),
    children: [
      _buildTeacherHeader(),
      _buildStatusCard(),
      SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: _buildMyRatings(),
      ),
    ],
  );
}

  Widget _buildMyRatings() {
    final teacherId = _auth.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('queues')
          .where('teacherId', isEqualTo: teacherId)
          .where('status', isEqualTo: 'completed')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _glassInfoCard(
            icon: Icons.error_outline,
            title: 'Değerlendirmeler yüklenemedi',
            subtitle: '${snapshot.error}',
            iconColor: Colors.redAccent,
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final queues = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['rating'] != null;
        }).toList();

        queues.sort((a, b) {
          final aTime =
              (a.data() as Map<String, dynamic>)['completedAt'] as Timestamp?;
          final bTime =
              (b.data() as Map<String, dynamic>)['completedAt'] as Timestamp?;

          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;

          return bTime.compareTo(aTime);
        });

        if (queues.isEmpty) {
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 28),
            child: _glassInfoCard(
              icon: Icons.star_border,
              title: 'Henüz değerlendirme yok',
              subtitle:
                  'Öğrenciler soru çözüldükten sonra puan verince burada görünecek.',
              iconColor: Colors.amber,
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          itemCount: queues.length,
          itemBuilder: (context, index) {
            final doc = queues[index];
            final data = doc.data() as Map<String, dynamic>;

            final rating = _toInt(data['rating']);
            final comment = data['comment'] ?? '';
            final studentName = data['studentName'] ?? 'Öğrenci';
            final subject = data['subject'] ?? 'Ders';

            final completedAt = data['completedAt'] as Timestamp?;
            final dateText = completedAt == null
                ? ''
                : '${completedAt.toDate().day}.${completedAt.toDate().month}.${completedAt.toDate().year}';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.star,
                          color: Colors.amber,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              studentName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            Text(
                              subject,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (dateText.isNotEmpty)
                        Text(
                          dateText,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 24,
                      ),
                    ),
                  ),
                  if (comment.toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        '"$comment"',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontStyle: FontStyle.italic,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _statusButton(
    String text,
    IconData icon,
    Color color,
    String value,
  ) {
    final selected = _teacherStatus == value;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        _showStatusChangeDialog(value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(0.25)
              : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withOpacity(0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Durumum',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _teacherStatus == 'available'
                        ? Colors.green
                        : _teacherStatus == 'break'
                            ? Colors.orange
                            : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _statusText(_teacherStatus),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _statusButton(
                  'Müsait',
                  Icons.check_circle,
                  Colors.green,
                  'available',
                ),
                _statusButton(
                  'Molada',
                  Icons.free_breakfast,
                  Colors.orange,
                  'break',
                ),
                _statusButton(
                  'Kurumda Değil',
                  Icons.person_off,
                  Colors.red,
                  'absent',
                ),
              ],
            ),
            const SizedBox(height: 22),

_headerActionButton(
  icon: Icons.event_available_rounded,
  title: 'Çalışma Programınız',
  subtitle: 'Kurumda bulunduğunuz gün ve saatleri düzenleyin',
  color: Colors.lightBlueAccent,
  onTap: _showAvailabilityDialog,
),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherHeader() {
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.12),
            Colors.green.withOpacity(0.20),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 380;

              final info = Row(
                children: [
                  Container(
                    width: isNarrow ? 54 : 62,
                    height: isNarrow ? 54 : 62,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withOpacity(0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.greenAccent.withOpacity(0.35),
                      ),
                    ),
                    child: Icon(
                      Icons.school,
                      color: Colors.greenAccent,
                      size: isNarrow ? 28 : 32,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hoş geldiniz',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _teacherName ?? 'Öğretmen',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isNarrow ? 22 : 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            'Branş: ${_teacherSubject ?? "Ders"}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final solved = Container(
                width: isNarrow ? double.infinity : 96,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.greenAccent.withOpacity(0.28),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.bar_chart_rounded,
                      color: Colors.greenAccent,
                      size: 22,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_todaySolved',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'çözüm',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );

              if (isNarrow) {
                return Column(
                  children: [
                    info,
                    const SizedBox(height: 12),
                    solved,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 12),
                  solved,
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          Container(
            height: 1,
            color: Colors.white.withOpacity(0.12),
          ),

          const SizedBox(height: 14),

          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 360;

              final addButton = _headerActionButton(
                icon: Icons.person_add,
                title: 'Öğrenci Ekle',
                subtitle: 'Sıraya ekle',
                    color: Colors.greenAccent,
                    onTap: _showAddStudentDialog,
              );
              final logoutButton = _headerActionButton(
                icon: Icons.logout,
                title: 'Çıkış Yap',
                subtitle: 'Hesaptan çık',
                color: Colors.redAccent,
                onTap: () async {
                  await _auth.signOut();
                },
              );

              if (isNarrow) {
                return Column(
                  children: [
                    addButton,
                    const SizedBox(height: 10),
                    logoutButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: addButton),
                  const SizedBox(width: 10),
                  Expanded(child: logoutButton),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
Widget _headerActionButton({
  required IconData icon,
  required String title,
  required String subtitle,
  required Color color,
  required VoidCallback? onTap,
}) {
  final bool disabled = onTap == null;

  return InkWell(
    borderRadius: BorderRadius.circular(22),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: disabled
            ? Colors.white.withOpacity(0.05)
            : color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: disabled ? Colors.white12 : color.withOpacity(0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: disabled
                  ? Colors.white.withOpacity(0.08)
                  : color.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: disabled ? Colors.white38 : color,
              size: 24,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: disabled ? Colors.white38 : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  disabled ? 'Müsait değil' : subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: disabled ? Colors.white30 : Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  toolbarHeight: 0,
  bottom: TabBar(
    controller: _tabController,
    indicatorColor: Colors.greenAccent,
    labelColor: Colors.greenAccent,
    unselectedLabelColor: Colors.white60,
    tabs: const [
      Tab(
        icon: Icon(Icons.list_alt),
        text: 'Bekleyen Sorular',
      ),
      Tab(
        icon: Icon(Icons.star),
        text: 'Değerlendirmeler',
      ),
    ],
  ),
),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF06312E),
              Color(0xFF008A5C),
              Color(0xFF061B26),
            ],
          ),
        ),
        child: SafeArea(
  child: TabBarView(
    controller: _tabController,
    children: [
      _buildWaitingQueues(),
      _buildRatingsPage(),
    ],
  ),
),
      ),
    );
  }
}