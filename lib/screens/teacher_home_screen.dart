import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';

import '../utils/queue_priority.dart';

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

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  String _teacherStatus = 'available';
  String? _teacherName;
  String? _teacherSubject;
  Map<String, List<Map<String, String>>> _weeklyAvailability = {};
  bool _isZumreOpenNow = false;
  bool _isTeacherWorkingNow = false;
  bool _isLunchNow = false;
  bool _isInstitutionBlockingZumre = false;
  String _zumreSlotText = '';
  String _nextZumreText = '';
  int? _zumreRemainingMinutes;
  String _scheduleMessage = 'Kontrol ediliyor...';
  String? _manualAbsentDate;
  Timestamp? _breakUntil;
  int _remainingBreakMinutes = 0;

  int _todaySolved = 0;

  Timer? _activeQuestionTimer;
  Timer? _zumrePillTimer;
  Timer? _breakCountdownTimer;
  String? _activeTimerQueueId;
  int? _activeTimerLimitMinutes;
  String? _warnedQueueKey;
  bool _isTimeDialogOpen = false;
  int _elapsedSeconds = 0;
  final Set<String> _transferringQueueIds = {};
  StreamSubscription<DocumentSnapshot>? _teacherSubscription;
  StreamSubscription<DocumentSnapshot>? _runtimeStateSubscription;
  List<Map<String, dynamic>> _cachedZumreSlots = [];
  bool _cachedZumreIsWeekend = false;
  static const Duration _runtimeStateMaxAge = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    _initTeacherPage();
  }

  Future<void> _initTeacherPage() async {
    _listenTeacherInfo();
    await _loadTeacherAvailability();
    await _loadTodaySolvedCount();
    _listenRuntimeScheduleState();
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

  String _todayDateKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  bool _hasManualAbsentOverrideToday([String? dateKey]) {
    return (dateKey ?? _manualAbsentDate) == _todayDateKey();
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

      if (nowMinutes >= start && nowMinutes < end) {
        return true;
      }
    }

    return false;
  }

  List<Map<String, dynamic>> _availabilitySlotsFromData(
    Map<String, dynamic> data,
    DateTime now,
  ) {
    final rawAvailability = data['weeklyAvailability'];
    if (rawAvailability is! Map) return [];

    final rawSlots = rawAvailability[_dayKey(now)];
    if (rawSlots is! List) return [];

    return rawSlots
        .whereType<Map>()
        .map((slot) => Map<String, dynamic>.from(slot))
        .toList();
  }

  bool _isTeacherScheduledFromData(Map<String, dynamic> data, DateTime now) {
    return _isNowInSlots(now, _availabilitySlotsFromData(data, now));
  }

  String _resolveBaseTeacherStatus(Map<String, dynamic> data) {
    if (_hasManualAbsentOverrideToday(data['manualAbsentDate']?.toString())) {
      return 'absent';
    }

    return _isTeacherScheduledFromData(data, DateTime.now())
        ? 'available'
        : 'absent';
  }

  String _resolveEffectiveTeacherStatus({
    required Map<String, List<Map<String, String>>> weeklyAvailability,
    required String currentStatus,
    required String? manualAbsentDate,
    required Timestamp? breakUntil,
  }) {
    if (currentStatus == 'studyGuard') {
      return 'studyGuard';
    }

    if (_hasManualAbsentOverrideToday(manualAbsentDate)) {
      return 'absent';
    }

    if (breakUntil != null && breakUntil.toDate().isAfter(DateTime.now())) {
      return 'break';
    }

    final now = DateTime.now();
    final slots = (weeklyAvailability[_dayKey(now)] ?? [])
        .map((slot) => Map<String, dynamic>.from(slot))
        .toList();

    return _isNowInSlots(now, slots) ? 'available' : 'absent';
  }

  int _breakRemainingMinutes(Timestamp? breakUntil) {
    if (breakUntil == null) return 0;

    final seconds = breakUntil.toDate().difference(DateTime.now()).inSeconds;
    if (seconds <= 0) return 0;

    return (seconds / 60).ceil();
  }

  bool _sameTimestamp(Timestamp? first, Timestamp? second) {
    if (first == null || second == null) return false;

    return first.toDate().millisecondsSinceEpoch ==
        second.toDate().millisecondsSinceEpoch;
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

  String? _institutionBlockMessage(Map<String, dynamic>? data) {
    if (data == null) return null;

    final mode = '${data['institutionMode'] ?? 'active'}';
    if (mode == 'closed' && data['closedDate'] == _todayDateKey()) {
      return 'Kurum Kapalı';
    }

    final examEndsAt = data['examEndsAt'];
    if (mode == 'exam' &&
        examEndsAt is Timestamp &&
        examEndsAt.toDate().isAfter(DateTime.now())) {
      return 'Deneme modu aktif.';
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
    _runtimeStateSubscription = _firestore
        .collection('settings')
        .doc('runtimeState')
        .snapshots()
        .listen((_) async {
      await _checkScheduleAvailability();
    }, onError: (_) async {
      await _checkScheduleAvailability();
    });
  }

  @override
  void dispose() {
    _activeQuestionTimer?.cancel();
    _zumrePillTimer?.cancel();
    _breakCountdownTimer?.cancel();
    _teacherSubscription?.cancel();
    _runtimeStateSubscription?.cancel();
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
        nextZumreText = 'Sonraki: ${futureSlots.first['start']}';
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
        final elapsed = DateTime.now().difference(startedAt.toDate()).inSeconds;

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
                  backgroundColor: color.withValues(alpha: 0.18),
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

    final zumreSlots =
        rawZumreSlots.map((e) => Map<String, dynamic>.from(e)).toList();
    _cachedZumreSlots = zumreSlots;
    _cachedZumreIsWeekend = isWeekend;

    final lunch = Map<String, dynamic>.from(settings['lunchBreak'] ?? {});

    final teacherSlots = (_weeklyAvailability[todayKey] ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final zumreUiState = _zumreUiStateFromSlots(now, zumreSlots, isWeekend);
    final isZumreOpen = zumreUiState['isZumreOpen'] == true;
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

    var effectiveZumreOpen = isZumreOpen;
    var effectiveLunch = isLunch;
    String? runtimeMessage;

    try {
      final runtimeDoc =
          await _firestore.collection('settings').doc('runtimeState').get();
      final runtimeState = _runtimeZumreState(runtimeDoc.data());

      if (runtimeState != null) {
        effectiveZumreOpen = runtimeState['isZumreOpen'] ?? isZumreOpen;
        effectiveLunch = runtimeState['isLunchBreak'] ?? isLunch;
        runtimeMessage = runtimeState['message']?.toString();
      }
    } catch (_) {}

    String message;

    if (runtimeMessage != null) {
      message = runtimeMessage;
    } else if (!effectiveZumreOpen) {
      message = 'Şu an zümre saati aktif değil.';
    } else if (effectiveLunch) {
      message = 'Şu an öğle arası.';
    } else if (!isTeacherWorking) {
      message = 'Bugün çalışma programınıza göre kurumda değilsiniz.';
    } else if (_teacherStatus == 'absent') {
      message = 'Kurumda değil olarak görünüyorsunuz.';
    } else if (_teacherStatus == 'break') {
      message = 'Şu an moladasınız.';
    } else {
      message = 'Zümre saati aktif. Öğrenci ekleyebilirsiniz.';
    }

    if (!mounted) return;

    final remainingMinutes = zumreUiState['remainingMinutes'];

    setState(() {
      _isInstitutionBlockingZumre = runtimeMessage != null;
      _isZumreOpenNow = effectiveZumreOpen;
      _isTeacherWorkingNow = isTeacherWorking;
      _isLunchNow = effectiveLunch;
      _zumreSlotText =
          effectiveZumreOpen ? zumreUiState['slotText']?.toString() ?? '' : '';
      _nextZumreText = effectiveZumreOpen
          ? ''
          : zumreUiState['nextZumreText']?.toString() ?? '';
      _zumreRemainingMinutes = effectiveZumreOpen && remainingMinutes is int
          ? remainingMinutes
          : null;
      _scheduleMessage = message;
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
                            color: Colors.white.withValues(alpha: 0.08),
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

                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Padding(
                                              padding: EdgeInsets.only(
                                                  left: 14, bottom: 6),
                                              child: Text(
                                                'Başlangıç',
                                                style: TextStyle(
                                                  color: Colors.white60,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            TextFormField(
                                              initialValue: slot['start'],
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                                LengthLimitingTextInputFormatter(
                                                    4),
                                                _TimeTextInputFormatter(),
                                              ],
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 17,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: '09:00',
                                                hintStyle: const TextStyle(
                                                    color: Colors.white38),
                                                filled: true,
                                                fillColor: Colors.white
                                                    .withValues(alpha: 0.09),
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 17,
                                                ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  borderSide: BorderSide.none,
                                                ),
                                                enabledBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  borderSide: BorderSide(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.08),
                                                  ),
                                                ),
                                                focusedBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  borderSide: const BorderSide(
                                                    color: Colors.greenAccent,
                                                    width: 1.3,
                                                  ),
                                                ),
                                              ),
                                              onChanged: (value) {
                                                slot['start'] = value;
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Padding(
                                              padding: EdgeInsets.only(
                                                  left: 14, bottom: 6),
                                              child: Text(
                                                'Bitiş',
                                                style: TextStyle(
                                                  color: Colors.white60,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            TextFormField(
                                              initialValue: slot['end'],
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                                LengthLimitingTextInputFormatter(
                                                    4),
                                                _TimeTextInputFormatter(),
                                              ],
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 17,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: '17:00',
                                                hintStyle: const TextStyle(
                                                    color: Colors.white38),
                                                filled: true,
                                                fillColor: Colors.white
                                                    .withValues(alpha: 0.09),
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 17,
                                                ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  borderSide: BorderSide.none,
                                                ),
                                                enabledBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  borderSide: BorderSide(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.08),
                                                  ),
                                                ),
                                                focusedBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  borderSide: const BorderSide(
                                                    color: Colors.greenAccent,
                                                    width: 1.3,
                                                  ),
                                                ),
                                              ),
                                              onChanged: (value) {
                                                slot['end'] = value;
                                              },
                                            ),
                                          ],
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
                                final nextStatus =
                                    _resolveEffectiveTeacherStatus(
                                  weeklyAvailability: temp,
                                  currentStatus: _teacherStatus,
                                  manualAbsentDate: _manualAbsentDate,
                                  breakUntil: _breakUntil,
                                );
                                final updateData = <String, dynamic>{
                                  'weeklyAvailability': temp,
                                  'updatedAt': FieldValue.serverTimestamp(),
                                };

                                if (nextStatus != 'studyGuard') {
                                  updateData['teacherStatus'] = nextStatus;
                                }

                                if (_breakUntil != null &&
                                    !_breakUntil!
                                        .toDate()
                                        .isAfter(DateTime.now())) {
                                  updateData['breakUntil'] =
                                      FieldValue.delete();
                                }

                                await _firestore
                                    .collection('users')
                                    .doc(uid)
                                    .update(updateData);

                                if (!mounted) return;

                                setState(() {
                                  _weeklyAvailability = temp;
                                  if (nextStatus != 'studyGuard') {
                                    _teacherStatus = nextStatus;
                                  }
                                });
                                await _checkScheduleAvailability();
                                if (!mounted) return;

                                if (ctx.mounted) Navigator.pop(ctx);

                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Kurum saatleriniz güncellendi'),
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
                    color: Colors.orange.withValues(alpha: 0.18),
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
        return _remainingBreakMinutes > 0
            ? 'Molada · $_remainingBreakMinutes dk'
            : 'Molada';
      case 'absent':
        return 'Kurumda Değil';
      case 'studyGuard':
        return 'Etüt Nöbetçisi';
      default:
        return 'Etütte';
    }
  }

  void _configureBreakCountdown() {
    _breakCountdownTimer?.cancel();
    _breakCountdownTimer = null;

    final currentBreakUntil = _breakUntil;
    if (_teacherStatus != 'break' || currentBreakUntil == null) {
      if (_remainingBreakMinutes != 0 && mounted) {
        setState(() {
          _remainingBreakMinutes = 0;
        });
      } else {
        _remainingBreakMinutes = 0;
      }
      return;
    }

    void tick() {
      final remaining = _breakRemainingMinutes(currentBreakUntil);

      if (mounted) {
        setState(() {
          _remainingBreakMinutes = remaining;
        });
      } else {
        _remainingBreakMinutes = remaining;
      }

      if (remaining <= 0) {
        _breakCountdownTimer?.cancel();
        _breakCountdownTimer = null;
        _finishBreakIfStillCurrent(currentBreakUntil);
      }
    }

    tick();
    _breakCountdownTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (_teacherStatus != 'break' ||
            !_sameTimestamp(_breakUntil, currentBreakUntil)) {
          _breakCountdownTimer?.cancel();
          _breakCountdownTimer = null;
          return;
        }

        tick();
      },
    );
  }

  Future<void> _finishBreakIfStillCurrent(Timestamp expectedBreakUntil) async {
    try {
      final uid = _auth.currentUser!.uid;
      final teacherRef = _firestore.collection('users').doc(uid);
      final doc = await teacherRef.get();
      final data = doc.data();

      if (data == null || data['teacherStatus'] != 'break') return;

      final currentBreakUntil = data['breakUntil'];
      if (currentBreakUntil is! Timestamp ||
          !_sameTimestamp(currentBreakUntil, expectedBreakUntil)) {
        return;
      }

      await teacherRef.update({
        'teacherStatus': _resolveBaseTeacherStatus(data),
        'breakUntil': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  void _listenTeacherInfo() {
    final uid = _auth.currentUser!.uid;
    _teacherSubscription?.cancel();
    _teacherSubscription =
        _firestore.collection('users').doc(uid).snapshots().listen((doc) {
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
        _manualAbsentDate = data?['manualAbsentDate']?.toString();
        _breakUntil = data?['breakUntil'] is Timestamp
            ? data!['breakUntil'] as Timestamp
            : null;
      });

      _configureBreakCountdown();
      _checkScheduleAvailability();
    });
  }

  Future<void> _updateTeacherStatus(
    String status, {
    int? breakMinutes,
  }) async {
    final uid = _auth.currentUser!.uid;
    final targetStatus =
        status == 'available' && !_isTeacherWorkingNow ? 'absent' : status;
    final updateData = <String, dynamic>{
      'teacherStatus': targetStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (status == 'available') {
      updateData['manualAbsentDate'] = FieldValue.delete();
      updateData['breakUntil'] = FieldValue.delete();
    } else if (status == 'absent') {
      updateData['manualAbsentDate'] = _todayDateKey();
      updateData['breakUntil'] = FieldValue.delete();
    } else if (status == 'break') {
      final minutes = breakMinutes ?? 5;
      updateData['manualAbsentDate'] = FieldValue.delete();
      updateData['breakUntil'] = Timestamp.fromDate(
        DateTime.now().add(Duration(minutes: minutes)),
      );
    }

    await _firestore.collection('users').doc(uid).update(updateData);

    if (!mounted) return;

    setState(() {
      _teacherStatus = targetStatus;
      if (status == 'absent') {
        _manualAbsentDate = _todayDateKey();
        _breakUntil = null;
      } else if (status == 'available') {
        _manualAbsentDate = null;
        _breakUntil = null;
      } else if (status == 'break') {
        _manualAbsentDate = null;
        _breakUntil = updateData['breakUntil'] as Timestamp?;
      }
    });
    _configureBreakCountdown();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status == 'available'
              ? targetStatus == 'available'
                  ? 'Durumunuz müsait olarak güncellendi'
                  : 'Çalışma programınıza göre kurumda değilsiniz.'
              : status == 'break'
                  ? 'Durumunuz molada olarak güncellendi'
                  : 'Durumunuz kurumda değil olarak güncellendi',
        ),
      ),
    );
  }

  Future<int?> _showBreakDurationDialog() {
    return showDialog<int>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
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
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
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
                    color: Colors.orangeAccent.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.free_breakfast_rounded,
                    color: Colors.orangeAccent,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Mola süresi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Ne kadar süre molada görüneceksiniz?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    for (final minutes in const [5, 10, 15]) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, minutes),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Text('$minutes dk'),
                        ),
                      ),
                      if (minutes != 15) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text('İptal'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showStatusChangeDialog(String value) async {
    if (_teacherStatus == value && value != 'break') return;
    await _checkScheduleAvailability();

    if (value == 'break') {
      final minutes = await _showBreakDurationDialog();
      if (minutes == null) return;

      await _updateTeacherStatus(value, breakMinutes: minutes);
      return;
    }

    final confirm = await _confirmAction(
      title: 'Durum değiştirilsin mi?',
      message: '${_statusText(_teacherStatus)} durumundan '
          '${_statusText(value)} durumuna geçmek istiyor musunuz?',
      confirmText: 'Onayla',
      icon: Icons.swap_horiz_rounded,
      color: value == 'available'
          ? const Color.fromARGB(255, 84, 189, 138)
          : value == 'absent'
              ? Colors.redAccent
              : Colors.orangeAccent,
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
    if (!mounted) return;

    final canAddStudent =
        _teacherStatus == 'available' && _isZumreOpenNow && !_isLunchNow;

    if (!canAddStudent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_scheduleMessage)),
      );
      return;
    }
    String? selectedStudentId;
    String? selectedStudentName;
    String searchText = '';
    final studentsStream = _firestore
        .collection('users')
        .where('role', isEqualTo: 'student')
        .snapshots();
    final activeQueuesStream = _firestore
        .collection('queues')
        .where('status', whereIn: ['waiting', 'in_progress']).snapshots();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                            color: Colors.greenAccent.withValues(alpha: 0.18),
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
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.10),
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
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: studentsStream,
                        builder: (context, studentsSnapshot) {
                          if (studentsSnapshot.hasError) {
                            return Text(
                              'Öğrenciler yüklenemedi: ${studentsSnapshot.error}',
                              style: const TextStyle(color: Colors.redAccent),
                            );
                          }

                          if (!studentsSnapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          return StreamBuilder<QuerySnapshot>(
                            stream: activeQueuesStream,
                            builder: (context, queuesSnapshot) {
                              if (queuesSnapshot.hasError) {
                                return Text(
                                  'Sıra bilgisi yüklenemedi: ${queuesSnapshot.error}',
                                  style:
                                      const TextStyle(color: Colors.redAccent),
                                );
                              }

                              if (!queuesSnapshot.hasData) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }

                              final activeStudentIds = queuesSnapshot.data!.docs
                                  .map((doc) => (doc.data()
                                      as Map<String, dynamic>)['studentId'])
                                  .where((id) => id != null)
                                  .toSet();
                              final now = DateTime.now();
                              final filteredStudents =
                                  studentsSnapshot.data!.docs.where((doc) {
                                final data = doc.data() as Map<String, dynamic>;

                                final cooldownUntil =
                                    data['cooldownUntil'] as Timestamp?;
                                final isInCooldown = cooldownUntil != null &&
                                    cooldownUntil.toDate().isAfter(now);
                                final isInActiveQueue =
                                    activeStudentIds.contains(doc.id);
                                final isInStudySession =
                                    data['isInStudySession'] == true;

                                if (isInActiveQueue ||
                                    isInCooldown ||
                                    isInStudySession) {
                                  return false;
                                }

                                final name = (data['fullName'] ??
                                        data['name'] ??
                                        data['email'] ??
                                        '')
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

                              final selectedStillVisible =
                                  selectedStudentId == null ||
                                      filteredStudents.any(
                                          (doc) => doc.id == selectedStudentId);

                              if (!selectedStillVisible) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setDialogState(() {
                                    selectedStudentId = null;
                                    selectedStudentName = null;
                                  });
                                });
                              }

                              if (filteredStudents.isEmpty) {
                                return const Center(
                                  child: Text(
                                    'Öğrenci bulunamadı',
                                    style: TextStyle(color: Colors.white60),
                                  ),
                                );
                              }

                              return ListView.builder(
                                itemCount: filteredStudents.length,
                                itemBuilder: (context, index) {
                                  final doc = filteredStudents[index];
                                  final data =
                                      doc.data() as Map<String, dynamic>;

                                  final fullName = data['fullName'] ??
                                      data['name'] ??
                                      data['email'] ??
                                      'Öğrenci';

                                  final className = data['className'] ?? '';
                                  final department = data['department'] ?? '';
                                  final selected = selectedStudentId == doc.id;

                                  return ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Colors.green,
                                      child: Icon(
                                        Icons.person,
                                        color: Colors.white,
                                      ),
                                    ),
                                    title: Text(
                                      fullName,
                                      style:
                                          const TextStyle(color: Colors.white),
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
                              );
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
                                  final selectedId = selectedStudentId;

                                  if (selectedId == null) return;

                                  await _checkScheduleAvailability();
                                  if (!mounted) return;

                                  if (_teacherStatus != 'available' ||
                                      !_isZumreOpenNow ||
                                      _isLunchNow) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      SnackBar(content: Text(_scheduleMessage)),
                                    );
                                    return;
                                  }

                                  final teacherDoc = await _firestore
                                      .collection('users')
                                      .doc(teacherId)
                                      .get();
                                  if (!mounted) return;
                                  final teacherData = teacherDoc.data() ?? {};

                                  if (!teacherDoc.exists ||
                                      teacherData['teacherStatus']
                                              ?.toString()
                                              .trim() !=
                                          'available') {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Durumunuz müsait değil. Öğrenci sıraya eklenemedi.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  final selectedStudentDoc = await _firestore
                                      .collection('users')
                                      .doc(selectedId)
                                      .get();
                                  if (!mounted) return;
                                  final selectedStudentData =
                                      selectedStudentDoc.data() ?? {};

                                  if (selectedStudentData['isInStudySession'] ==
                                      true) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Bu öğrenci şu anda etütte görünüyor.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  final selectedActiveQueue = await _firestore
                                      .collection('queues')
                                      .where('studentId', isEqualTo: selectedId)
                                      .where(
                                        'status',
                                        whereIn: ['waiting', 'in_progress'],
                                      )
                                      .limit(1)
                                      .get();
                                  if (!mounted) return;

                                  if (selectedActiveQueue.docs.isNotEmpty) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Bu öğrencinin zaten aktif zümre sırası var.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  final activeSnapshot = await _firestore
                                      .collection('queues')
                                      .where('teacherId', isEqualTo: teacherId)
                                      .where('status', isEqualTo: 'in_progress')
                                      .get();
                                  if (!mounted) return;

                                  final hasActiveQuestion =
                                      activeSnapshot.docs.isNotEmpty;

                                  await _firestore.collection('queues').add({
                                    'studentId': selectedId,
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

                                  if (!mounted) return;
                                  if (ctx.mounted) Navigator.pop(ctx);

                                  ScaffoldMessenger.of(this.context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Öğrenci sıraya eklendi'),
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(this.context).showSnackBar(
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
                              Colors.white.withValues(alpha: 0.15),
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

    waitingQueues.sort((a, b) => compareQueuePriority(a.data(), b.data()));

    final nextQueue = waitingQueues.first;

    await _firestore.collection('queues').doc(nextQueue.id).update({
      'status': 'in_progress',
      'startedAt': Timestamp.now(),
    });
  }

  Future<void> _startWaitingQueueSafely({
    required QueryDocumentSnapshot queueDoc,
    required int queueIndex,
  }) async {
    final teacherId = _auth.currentUser!.uid;
    final queueData = queueDoc.data() as Map<String, dynamic>;

    final targetStudentName =
        queueData['studentName']?.toString() ?? 'Bu öğrenci';

    try {
      final activeSnapshot = await _firestore
          .collection('queues')
          .where('teacherId', isEqualTo: teacherId)
          .where('status', isEqualTo: 'in_progress')
          .limit(1)
          .get();

      QueryDocumentSnapshot? activeQueue;

      if (activeSnapshot.docs.isNotEmpty) {
        activeQueue = activeSnapshot.docs.first;

        if (activeQueue.id == queueDoc.id) {
          return;
        }

        final activeData = activeQueue.data() as Map<String, dynamic>;

        final activeStudentName =
            activeData['studentName']?.toString() ?? 'Mevcut öğrenci';

        final finishCurrent = await _confirmAction(
          title: 'Aktif soru bulunuyor',
          message:
              '$activeStudentName isimli öğrencinin sorusu hâlâ çözülüyor. '
              '$targetStudentName isimli öğrenciyi başlatmak için mevcut soru '
              'çözüldü olarak işaretlenecek. Devam etmek istiyor musunuz?',
          confirmText: 'Bitir ve Başlat',
          icon: Icons.warning_amber_rounded,
          color: Colors.orangeAccent,
        );

        if (!finishCurrent) return;
      }

      if (queueIndex > 0) {
        final skipCount = queueIndex;

        final continueOutOfOrder = await _confirmAction(
          title: 'Sıra önceliği uyarısı',
          message: '$targetStudentName isimli öğrencinin önünde '
              '$skipCount öğrenci bulunuyor. Buna rağmen bu öğrencinin '
              'sorusunu önce başlatmak istiyor musunuz?',
          confirmText: 'Yine de Başlat',
          icon: Icons.low_priority_rounded,
          color: Colors.orangeAccent,
        );

        if (!continueOutOfOrder) return;
      }

      final batch = _firestore.batch();

      if (activeQueue != null) {
        batch.update(activeQueue.reference, {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      batch.update(queueDoc.reference, {
        'status': 'in_progress',
        'startedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      _resetActiveQuestionTimer();

      if (!mounted) return;

      if (activeQueue != null) {
        setState(() {
          _todaySolved++;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$targetStudentName isimli öğrencinin sorusu başlatıldı.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Soru başlatılamadı: $e'),
        ),
      );
    }
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Soru çözüldü olarak işaretlendi')),
      );
    } catch (e) {
      if (!mounted) return;
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sıra iptal edildi')),
      );
    } catch (e) {
      if (!mounted) return;
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
    if (_transferringQueueIds.contains(queueId)) return;

    setState(() {
      _transferringQueueIds.add(queueId);
    });

    try {
      final confirm = await _confirmAction(
        title: 'Soru devredilsin mi?',
        message: '$studentName isimli öğrencinin sorusu $subject branşındaki '
            'en uygun müsait öğretmene devredilecek.',
        confirmText: 'Devret',
        icon: Icons.swap_horiz_rounded,
        color: Colors.green,
      );

      if (!confirm) return;

      final callable = _functions.httpsCallable('routeQueueTransfer');
      final response = await callable.call<Map<String, dynamic>>({
        'queueId': queueId,
      });

      final selectedTeacherName =
          response.data['teacherName']?.toString() ?? 'uygun öğretmen';

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Soru $selectedTeacherName isimli öğretmene devredildi.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Soru devredilemedi: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _transferringQueueIds.remove(queueId);
        });
      }
    }
  }

  Future<bool> _confirmLogout({
    required Color color,
  }) async {
    return _confirmAction(
      title: 'Çıkış Yap',
      message: 'Oturumu kapatmak istediğinize emin misiniz?',
      confirmText: 'Çıkış Yap',
      icon: Icons.logout_rounded,
      color: color,
    );
  }

  Widget _miniTimeBox({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
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
                      color: Colors.greenAccent.withValues(alpha: 0.16),
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
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12),
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
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
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

        queues.sort(
          (a, b) => compareQueuePriority(
            a.data() as Map<String, dynamic>,
            b.data() as Map<String, dynamic>,
          ),
        );

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
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
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
                            await _startWaitingQueueSafely(
                              queueDoc: doc,
                              queueIndex: queues.indexOf(doc),
                            );
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
                            side:
                                const BorderSide(color: Colors.lightBlueAccent),
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
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

  Widget _statusButton(
    String text,
    IconData icon,
    Color color,
    String value,
  ) {
    final selected = _teacherStatus == value;
    final tapEnabled = !(selected && value == 'break');

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: tapEnabled
          ? () {
              _showStatusChangeDialog(value);
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.08),
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
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
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

  Widget _zumreStatusChip() {
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
      constraints: const BoxConstraints(
        maxWidth: 190,
      ),
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
              Colors.white.withValues(alpha: 0.12),
              Colors.green.withValues(alpha: 0.20),
            ],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.25)),
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
                        color: Colors.greenAccent.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.greenAccent.withValues(alpha: 0.35),
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
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _teacherName ?? 'Öğretmen',
                              maxLines: 1,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
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
                              _zumreStatusChip(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final solved = Container(
                  constraints: const BoxConstraints(
                    minWidth: 60,
                    maxWidth: 82,
                    minHeight: 60,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.greenAccent.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bar_chart_rounded,
                        color: Colors.greenAccent,
                        size: 18,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_todaySolved',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Bugün çözülen',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(child: info),
                    const SizedBox(width: 10),
                    Column(
                      children: [
                        solved,
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.12),
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
                    final logout = await _confirmLogout(
                      color: Colors.green,
                    );

                    if (!logout) return;

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
              ? Colors.white.withValues(alpha: 0.05)
              : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: disabled ? Colors.white12 : color.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: disabled
                    ? Colors.white.withValues(alpha: 0.08)
                    : color.withValues(alpha: 0.18),
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
          child: _buildWaitingQueues(),
        ),
      ),
    );
  }
}
