import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late TabController _tabController;

  String _teacherStatus = 'available';
  String? _teacherName;
  String? _teacherSubject;

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
    _loadTeacherInfo();
    _loadTodaySolvedCount();
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
        return 'Gelmedi';
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status == 'available'
              ? 'Durumunuz müsait olarak güncellendi'
              : status == 'break'
                  ? 'Durumunuz molada olarak güncellendi'
                  : 'Durumunuz gelmedi olarak güncellendi',
        ),
      ),
    );
  }

  Future<void> _showStatusChangeDialog(String value) async {
    if (_teacherStatus == value) return;

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
    if (_teacherStatus != 'available') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Müsait değilken öğrenci ekleyemezsiniz')),
      );
      return;
    }

    String? selectedStudentId;
    String? selectedStudentName;

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
                    DropdownButtonFormField<String>(
                      value: selectedStudentId,
                      dropdownColor: const Color(0xFF06312E),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Öğrenci Seç',
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: availableStudents.map((doc) {
                        final data = doc.data();
                        final name = data['name'] ?? data['email'] ?? 'Öğrenci';

                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text(name),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;

                        final selectedDoc = availableStudents.firstWhere(
                          (doc) => doc.id == value,
                        );

                        final data = selectedDoc.data();

                        setDialogState(() {
                          selectedStudentId = selectedDoc.id;
                          selectedStudentName =
                              data['name'] ?? data['email'] ?? 'Öğrenci';
                        });
                      },
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
        final isManual = data['isManual'] == true;

        _startActiveQuestionTimer(
          queueId: doc.id,
          startedAt: startedAt,
          estimatedMinutes: estimatedMinutes,
          extraMinutes: extraMinutes,
        );

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withOpacity(0.16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.support_agent,
                      color: Colors.greenAccent,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Aktif Soru',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          data['studentName'] ?? 'Öğrenci',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          data['subject'] ?? 'Ders',
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _miniTimeBox(
                      title: 'Soru',
                      value: '$questionCount',
                      icon: Icons.menu_book,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _miniTimeBox(
                      title: 'Tahmini',
                      value: '${estimatedMinutes + extraMinutes} dk',
                      icon: Icons.timer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _miniTimeBox(
                      title: 'Geçen',
                      value: _formatElapsed(_elapsedSeconds),
                      icon: Icons.access_time,
                    ),
                  ),
                ],
              ),
              if (isManual) ...[
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Öğretmen tarafından eklendi',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () async {
  final confirm = await _confirmAction(
    title: 'Soru çözüldü mü?',
    message: 'Bu öğrencinin sorusunu çözüldü olarak işaretlemek istiyor musunuz?',
    confirmText: 'Çözüldü',
  );

  if (confirm) {
    await _markAsSolved(doc.id);
  }
},
                  icon: const Icon(Icons.check),
                  label: const Text(
                    'Çözüldü',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                 onPressed: () async {
  final confirm = await _confirmAction(
    title: 'Soru iptal edilsin mi?',
    message: 'Bu aktif soruyu iptal etmek istiyor musunuz?',
    confirmText: 'İptal Et',
  );

  if (confirm) {
    await _cancelQueue(doc.id);
  }
},
                  icon: const Icon(Icons.close),
                  label: const Text('İptal Et'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
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
                            await _firestore
                                .collection('queues')
                                .doc(doc.id)
                                .update({
                              'status': 'in_progress',
                              'startedAt': Timestamp.now(),
                            });
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
                  'Gelmedi',
                  Icons.person_off,
                  Colors.red,
                  'absent',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddStudentButton() {
    return IconButton(
      icon: Icon(
        Icons.person_add,
        color: _teacherStatus == 'available' ? Colors.white : Colors.grey,
      ),
      tooltip: _teacherStatus == 'available'
          ? 'Öğrenci Ekle'
          : 'Öğretmen müsait değil',
      onPressed: _teacherStatus == 'available' ? _showAddStudentDialog : null,
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
                onTap: _teacherStatus == 'available'
                    ? _showAddStudentDialog
                    : null,
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