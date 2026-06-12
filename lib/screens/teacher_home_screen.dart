import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  _TeacherHomeScreenState createState() => _TeacherHomeScreenState();
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
    super.dispose();
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

    if (doc.exists) {
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
  }

  Future<void> _updateTeacherStatus(String status) async {
    final uid = _auth.currentUser!.uid;

    await _firestore.collection('users').doc(uid).update({
      'teacherStatus': status,
    });

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

      for (var doc in snapshot.docs) {
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
    } catch (e) {
      print(e);
    }
  }

  Future<void> _showAddStudentDialog() async {
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

    final availableStudents = studentsSnapshot.docs.where((doc) {
      return !activeStudentIds.contains(doc.id);
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
            return AlertDialog(
              title: const Text('Öğrenciyi Aktif Soruya Ekle'),
              content: DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Öğrenci Seç'),
                initialValue: selectedStudentId,
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedStudentId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Lütfen öğrenci seçin')),
                      );
                      return;
                    }

                    try {
                      final teacherId = _auth.currentUser!.uid;

                      final activeSnapshot = await _firestore
                          .collection('queues')
                          .where('teacherId', isEqualTo: teacherId)
                          .where('status', isEqualTo: 'in_progress')
                          .get();

                      final bool hasActiveQuestion =
                          activeSnapshot.docs.isNotEmpty;

                      await _firestore.collection('queues').add({
                        'studentId': selectedStudentId,
                        'studentName': selectedStudentName,
                        'teacherId': teacherId,
                        'teacherName': _teacherName ?? 'Öğretmen',
                        'subject': _teacherSubject ?? 'Ders',
                        'status': hasActiveQuestion ? 'waiting' : 'in_progress',
                        'isManual': true,
                        'createdAt': FieldValue.serverTimestamp(),
                        'startedAt':
                            hasActiveQuestion ? null : FieldValue.serverTimestamp(),
                      });

                      Navigator.pop(ctx);

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Öğrenci sıraya eklendi')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Hata: $e')),
                      );
                    }
                  },
                  child: const Text('Ekle'),
                ),
              ],
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
      'startedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _markAsSolved(String queueId) async {
    try {
      await _firestore.collection('queues').doc(queueId).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      });

      await _takeNextWaitingQueue();
      _loadTodaySolvedCount();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Soru çözüldü olarak işaretlendi')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  Future<void> _cancelQueue(String queueId) async {
    try {
      await _firestore.collection('queues').doc(queueId).update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
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

  Widget _buildStatusButton({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final bool isSelected = _teacherStatus == value;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
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
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? color : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? color : Colors.grey,
                size: 24,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? color : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
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
          return Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Aktif soru hatası: ${snapshot.error}'),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const SizedBox();
        }

        final activeQueues = snapshot.data!.docs;

        if (activeQueues.isEmpty) {
          return const Card(
            margin: EdgeInsets.all(12),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 8),
                  Expanded(child: Text('Şu anda aktif sorunuz yok')),
                ],
              ),
            ),
          );
        }

        final doc = activeQueues.first;
        final data = doc.data() as Map<String, dynamic>;
        final isManual = data['isManual'] == true;

        return Card(
          color: Colors.green.shade50,
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Aktif Soru',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${data['studentName'] ?? 'Öğrenci'} - ${data['subject'] ?? 'Ders'}',
                  style: const TextStyle(fontSize: 16),
                ),
                if (isManual)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Öğretmen tarafından eklendi',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _markAsSolved(doc.id),
                        icon: const Icon(Icons.check),
                        label: const Text('Çözüldü'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () => _cancelQueue(doc.id),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWaitingQueues() {
    final teacherId = _auth.currentUser!.uid;

    return Column(
      children: [
        _buildActiveQuestion(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('queues')
                .where('teacherId', isEqualTo: teacherId)
                .where('status', isEqualTo: 'waiting')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Hata: ${snapshot.error}'));
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
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
                return const Center(child: Text('Bekleyen soru yok'));
              }

              return ListView.builder(
                itemCount: queues.length,
                itemBuilder: (context, index) {
                  final doc = queues[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final isManual = data['isManual'] == true;

                  return Card(
                    color: isManual ? Colors.orange.shade50 : null,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isManual ? Colors.orange : Colors.blue,
                        child: Icon(
                          isManual ? Icons.person_add : Icons.person,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(
                        '${data['studentName'] ?? 'Öğrenci'} - ${data['subject'] ?? 'Ders'}',
                      ),
                      subtitle: Text(
                        isManual
                            ? 'Öğretmen tarafından sıraya eklendi'
                            : 'Durum: Bekliyor',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              await _firestore
                                  .collection('queues')
                                  .doc(doc.id)
                                  .update({
                                'status': 'in_progress',
                                'startedAt': FieldValue.serverTimestamp(),
                              });
                            },
                            child: const Text('Başlat'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _cancelQueue(doc.id),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
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
          return Center(child: Text('Hata: ${snapshot.error}'));
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
          return const Center(child: Text('Henüz değerlendirme yapılmamış'));
        }

        return ListView.builder(
          itemCount: queues.length,
          itemBuilder: (context, index) {
            final doc = queues[index];
            final data = doc.data() as Map<String, dynamic>;

            final rating = data['rating'] ?? 0;
            final comment = data['comment'] ?? '';
            final studentName = data['studentName'] ?? 'Öğrenci';
            final subject = data['subject'] ?? 'Ders';

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$studentName - $subject',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Row(
                          children: List.generate(
                            5,
                            (i) => Icon(
                              i < rating ? Icons.star : Icons.star_border,
                              color: Colors.orange,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (comment.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '"$comment"',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUnavailableInfo() {
    if (_teacherStatus == 'available') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: _teacherStatus == 'break' ? Colors.orange : Colors.red,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _teacherStatus == 'break'
                  ? 'Molada olduğunuz için yeni öğrenci ekleyemezsiniz.'
                  : 'Gelmedi durumundayken yeni öğrenci ekleyemezsiniz.',
              style: TextStyle(
                fontSize: 13,
                color: _teacherStatus == 'break' ? Colors.orange : Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Şu Anki Durumunuz',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatusButton(
                  label: 'Müsait',
                  value: 'available',
                  icon: Icons.check_circle,
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                _buildStatusButton(
                  label: 'Molada',
                  value: 'break',
                  icon: Icons.coffee,
                  color: Colors.orange,
                ),
                const SizedBox(width: 8),
                _buildStatusButton(
                  label: 'Gelmedi',
                  value: 'absent',
                  icon: Icons.cancel,
                  color: Colors.red,
                ),
              ],
            ),
            _buildUnavailableInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildAddStudentButton() {
    return IconButton(
      icon: Icon(
        Icons.person_add,
        color: _teacherStatus == 'available' ? null : Colors.grey,
      ),
      tooltip: _teacherStatus == 'available'
          ? 'Öğrenci Ekle'
          : 'Öğretmen müsait değil',
      onPressed:
          _teacherStatus == 'available' ? _showAddStudentDialog : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
title: LayoutBuilder(
  builder: (context, constraints) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        'Hoşgeldin, ${_teacherName ?? "Öğretmen"}',
        maxLines: 1,
        overflow: TextOverflow.visible,
      ),
    );
  },
),        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Bekleyen Sorular'),
            Tab(text: 'Değerlendirmeler'),
          ],
        ),
        actions: [
          _buildAddStudentButton(),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _auth.signOut();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusCard(),
          if (_teacherSubject != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Branş: $_teacherSubject',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildWaitingQueues(),
                _buildMyRatings(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}