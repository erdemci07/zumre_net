import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../utils/queue_priority.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  String? _studentName;
  String? _selectedSubject;

  bool _isInStudySession = false;
  bool _isInQueue = false;
  bool _isZumreOpenNow = false;
  bool _isLunchNow = false;
  bool _isRoutingQueue = false;
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
  StreamSubscription<DocumentSnapshot>? _studentSubscription;
  StreamSubscription<DocumentSnapshot>? _runtimeStateSubscription;
  static const Duration _runtimeStateMaxAge = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    _listenStudentInfo();
    _findAndListenActiveQueue();
    _listenRuntimeScheduleState();
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

  bool _applyRuntimeZumreState(Map<String, dynamic>? data) {
    final institutionMessage = _institutionBlockMessage(data);
    if (institutionMessage != null) {
      if (mounted) {
        setState(() {
          _isZumreOpenNow = false;
          _isLunchNow = false;
          _zumreMessage = institutionMessage;
          _nextZumreText = '';
        });
      }
      return true;
    }

    if (!_isFreshRuntimeState(data)) return false;

    final isZumreOpen = data!['isZumreOpen'] == true;
    final isLunch = data['isLunchBreak'] == true;
    final message = isLunch
        ? 'Şu an öğle arası. Zümre sırası geçici olarak kapalı.'
        : isZumreOpen
            ? 'Zümre saati aktif. Sıra alabilirsiniz.'
            : 'Şu an zümre saati aktif değil.';

    if (mounted) {
      setState(() {
        _isZumreOpenNow = isZumreOpen;
        _isLunchNow = isLunch;
        _zumreMessage = message;
        _nextZumreText = '';
      });
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
      if (!_applyRuntimeZumreState(snapshot.data())) {
        await _checkLocalZumreAvailability();
      }
    }, onError: (_) async {
      await _checkLocalZumreAvailability();
    });
  }

  Future<bool> _checkLocalZumreAvailability() async {
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

        nextZumreText = '${futureSlots.first['start']}';
      } else {
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

    if (!mounted) return false;

    setState(() {
      _isZumreOpenNow = isZumreOpen;
      _isLunchNow = isLunch;
      _zumreMessage = message;
      _nextZumreText = nextZumreText;
    });

    return true;
  }

  @override
  void dispose() {
    _queueSubscription?.cancel();
    _cooldownTimer?.cancel();
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

      _listenToQueue(queueDoc.id);
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

  void _listenToQueue(String queueId) {
    _queueSubscription?.cancel();

    _queueSubscription =
        _firestore.collection('queues').doc(queueId).snapshots().listen(
      (snapshot) async {
        if (!snapshot.exists) {
          await _queueSubscription?.cancel();
          _queueSubscription = null;

          if (!mounted) return;

          setState(() {
            _isInQueue = false;
            _currentQueueId = null;
            _currentTeacherName = null;
            _queuePosition = 0;
          });
          return;
        }

        final data = snapshot.data()!;
        final status = data['status'];

        if (status == 'waiting') {
          final teacherNameFromQueue = data['teacherName']?.toString();

          final teacherIdFromQueue = data['teacherId']?.toString();

          if (mounted) {
            setState(() {
              _isInQueue = true;
              _currentQueueId = queueId;

              if (teacherNameFromQueue != null &&
                  teacherNameFromQueue.isNotEmpty) {
                _currentTeacherName = teacherNameFromQueue;
              }
            });
          }

          if ((teacherNameFromQueue == null || teacherNameFromQueue.isEmpty) &&
              teacherIdFromQueue != null &&
              teacherIdFromQueue.isNotEmpty) {
            await _getCurrentTeacherName(teacherIdFromQueue);
          }

          await _updatePosition(queueId);
          return;
        }

        if (status == 'in_progress') {
          final teacherNameFromQueue = data['teacherName']?.toString();

          final teacherIdFromQueue = data['teacherId']?.toString();

          if (mounted) {
            setState(() {
              _isInQueue = true;
              _currentQueueId = queueId;
              _queuePosition = 0;

              if (teacherNameFromQueue != null &&
                  teacherNameFromQueue.isNotEmpty) {
                _currentTeacherName = teacherNameFromQueue;
              }
            });
          }

          if ((teacherNameFromQueue == null || teacherNameFromQueue.isEmpty) &&
              teacherIdFromQueue != null &&
              teacherIdFromQueue.isNotEmpty) {
            await _getCurrentTeacherName(teacherIdFromQueue);
          }

          return;
        }

        if (status == 'completed') {
          await _queueSubscription?.cancel();
          _queueSubscription = null;

          if (!mounted) return;

          setState(() {
            _isInQueue = false;
            _currentQueueId = null;
            _currentTeacherName = null;
            _queuePosition = 0;
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
    final queueDoc = await _firestore.collection('queues').doc(queueId).get();

    if (!queueDoc.exists) return;

    final teacherId = queueDoc.data()!['teacherId'];

    final waitingQueues = await _firestore
        .collection('queues')
        .where('teacherId', isEqualTo: teacherId)
        .where('status', isEqualTo: 'waiting')
        .get();

    final docs = waitingQueues.docs.toList();

    docs.sort((a, b) => compareQueuePriority(a.data(), b.data()));

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
          _currentTeacherName = data['teacherName']?.toString();
          _queuePosition = 1;
        });
      }

      if (!mounted) return;
      _listenToQueue(queueId);

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
                        border: Border.all(color: color.withValues(alpha: 0.35)),
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

    if (active) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.greenAccent.withValues(alpha: 0.35),
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
        color: Colors.orangeAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.orangeAccent.withValues(alpha: 0.35),
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
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
                color: Colors.orangeAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: Colors.orangeAccent.withValues(alpha: 0.25)),
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
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: const Color(0xFF6C3DFF).withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
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

  Widget _buildJoinQueueButton() {
    final canJoinQueue = _selectedSubject != null &&
        _remainingCooldownSeconds <= 0 &&
        _isZumreOpenNow &&
        !_isLunchNow &&
        !_isInStudySession &&
        !_isRoutingQueue;

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton.icon(
        onPressed: canJoinQueue ? _joinQueue : null,
        icon: _isRoutingQueue
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.auto_awesome_rounded),
        label: Text(
          _isRoutingQueue
              ? 'En uygun sıra belirleniyor...'
              : '✨ Uygun öğretmene yönlendir',
          style: const TextStyle(
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
