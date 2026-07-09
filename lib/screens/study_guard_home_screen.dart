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

  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initPage();
  }

  Future<void> _initPage() async {
    await _loadStaffInfo();
    await _checkStudySchedule();
    await _loadActiveSession();

    _scheduleTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkStudySchedule(),
    );
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _scheduleTimer?.cancel();
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

  Future<void> _loadActiveSession() async {
    final uid = _auth.currentUser!.uid;

    final snapshot = await _firestore
        .collection('studySessions')
        .where('staffId', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return;

    final doc = snapshot.docs.first;
    final data = doc.data();

    if (!mounted) return;

    setState(() {
      _activeSessionId = doc.id;
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

  bool _isNowInSlots(
    DateTime now,
    List<Map<String, dynamic>> slots,
  ) {
    final nowMinutes = now.hour * 60 + now.minute;

    for (final slot in slots) {
      final start = _timeToMinutes('${slot['start']}');
      final end = _timeToMinutes('${slot['end']}');

      if (end <= start) continue;

      if (nowMinutes >= start && nowMinutes <= end) {
        return true;
      }
    }

    return false;
  }

Future<void> _checkStudySchedule() async {
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

  if (endMin > startMin && nowMin >= startMin && nowMin <= endMin) {
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

    if (!mounted) return;

    setState(() {
      _activeSessionId = doc.id;
    });
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
    final studentsSnapshot = await _firestore
        .collection('studySessions')
        .doc(sessionId)
        .collection('students')
        .get();

    final batch = _firestore.batch();

    for (final doc in studentsSnapshot.docs) {
      batch.update(_firestore.collection('users').doc(doc.id), {
        'isInStudySession': false,
        'activeStudySessionId': null,
      });
    }

    batch.update(_firestore.collection('studySessions').doc(sessionId), {
      'status': 'completed',
      'endedAt': Timestamp.now(),
      'autoEnded': autoEnded,
      'dutyTeacherId': null,
      'dutyTeacherName': null,
      'studentCount': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (_selectedDutyTeacherId != null) {
      batch.update(
        _firestore.collection('users').doc(_selectedDutyTeacherId),
        {
          'teacherStatus': 'available',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    }

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
  Future<void> _addStudentToStudy(DocumentSnapshot doc) async {
    if (_activeSessionId == null) return;
    if (!_isStudyOpenNow) {
      _showSnack('Şu an etüt saati aktif değil.');
      return;
    }

    final data = doc.data() as Map<String, dynamic>;

    if (data['isInStudySession'] == true) {
      _showSnack('Bu öğrenci zaten etütte görünüyor.');
      return;
    }

    final activeQueueSnapshot = await _firestore
        .collection('queues')
        .where('studentId', isEqualTo: doc.id)
        .where('status', whereIn: ['waiting', 'in_progress'])
        .limit(1)
        .get();

    if (activeQueueSnapshot.docs.isNotEmpty) {
      _showSnack('Bu öğrencinin aktif zümre sırası var. Etüte alınamaz.');
      return;
    }

    final sessionId = _activeSessionId!;

    final sessionStudentRef = _firestore
        .collection('studySessions')
        .doc(sessionId)
        .collection('students')
        .doc(doc.id);

    final existing = await sessionStudentRef.get();

    if (existing.exists) {
      _showSnack('Bu öğrenci zaten bu etütte.');
      return;
    }

    final batch = _firestore.batch();

    batch.set(sessionStudentRef, {
      'studentId': doc.id,
      'studentName': data['fullName'] ?? data['name'] ?? 'Öğrenci',
      'className': data['className'] ?? '',
      'branch': data['branch'] ?? '',
      'department': data['department'] ?? '',
      'username': data['username'] ?? '',
      'checkedAt': Timestamp.now(),
      'status': 'present',
    });

    batch.update(_firestore.collection('users').doc(doc.id), {
      'isInStudySession': true,
      'activeStudySessionId': sessionId,
    });

    batch.update(_firestore.collection('studySessions').doc(sessionId), {
      'studentCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    if (!mounted) return;

    _showSnack('Öğrenci etüte alındı.');
  }

  Future<void> _removeStudentFromStudy(String studentId) async {
    if (_activeSessionId == null) return;

    final sessionId = _activeSessionId!;

    final batch = _firestore.batch();

    batch.update(_firestore.collection('users').doc(studentId), {
      'isInStudySession': false,
      'activeStudySessionId': null,
    });

    batch.delete(
      _firestore
          .collection('studySessions')
          .doc(sessionId)
          .collection('students')
          .doc(studentId),
    );

    batch.update(_firestore.collection('studySessions').doc(sessionId), {
      'studentCount': FieldValue.increment(-1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    _showSnack('Öğrenci etütten çıkarıldı.');
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
                Text(
                  _staffName ?? 'Etüt Görevlisi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
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
          IconButton(
  tooltip: 'Etüt Öğretmeni Seç',
  onPressed: _activeSessionId == null ? null : _showDutyTeacherDialog,
  icon: Icon(
    Icons.supervisor_account_rounded,
    color: _selectedDutyTeacherId == null
        ? Colors.white70
        : Colors.cyanAccent,
  ),
),
          IconButton(
            tooltip: 'Çıkış Yap',
            onPressed: () async => _auth.signOut(),
            icon: const Icon(Icons.logout, color: Colors.white70),
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
    final active = _activeSessionId != null;

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
                final count = snapshot.data?.docs.length ?? 0;

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

                          final hasSubjects = data['subjects'] is List &&
                              (data['subjects'] as List).isNotEmpty;

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

                              final subjects = data['subjects'] is List
                                  ? (data['subjects'] as List).join(', ')
                                  : '';

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

    // Önce eski seçili öğretmeni müsait yap
    if (_selectedDutyTeacherId != null &&
        _selectedDutyTeacherId != teacherId) {
      batch.update(
        _firestore.collection('users').doc(_selectedDutyTeacherId),
        {
          'teacherStatus': 'available',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    }

    // Yeni öğretmen seçildiyse etüt görevlisi yap
    if (teacherId != null) {
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

                          if (data['isInStudySession'] == true) return false;

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
                                onAdded: () {
                                  Navigator.pop(ctx);
                                },
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
    },
  );
}
Widget _dialogStudentTile(
  DocumentSnapshot doc, {
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
              await _addStudentToStudy(doc);
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

        final students = snapshot.data!.docs;

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
              ),
              const SizedBox(height: 12),
              ...students.map((doc) {
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
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${data['className'] ?? ''}-${data['branch'] ?? ''} • ${data['department'] ?? ''}',
                      style: const TextStyle(color: Colors.white60),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.redAccent,
                      ),
                      onPressed: _isProcessing
                          ? null
                          : () => _removeStudentFromStudy(doc.id),
                    ),
                  ),
                );
              }),
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
              _studentSearch(),
              _currentStudents(),
            ],
          ),
        ),
      ),
    );
  }
}