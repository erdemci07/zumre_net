import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StudentHomeScreen extends StatefulWidget {
  @override
  _StudentHomeScreenState createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _studentName;
  String? _selectedSubject;
  String? _selectedTeacherId;
  List<Map<String, dynamic>> _teachersForSubject = [];

  bool _isLoadingTeachers = false;
  bool _isInQueue = false;

  String? _currentQueueId;
  String? _currentTeacherName;

  int _queuePosition = 0;
  int _cooldownUntil = 0;
  int _remainingCooldownSeconds = 0;

  Timer? _cooldownTimer;
  StreamSubscription<DocumentSnapshot>? _queueSubscription;
  StreamSubscription<QuerySnapshot>? _myQueueWatcher;

  final List<String> _subjects = [
    'Matematik',
    'Fizik',
    'Kimya',
    'Biyoloji',
    'Türkçe',
    'Tarih',
    'Coğrafya',
    'Geometri',
  ];

  @override
  void initState() {
    super.initState();
    _loadStudentInfo();
    _listenForMyQueue();
  }

  @override
  void dispose() {
    _queueSubscription?.cancel();
    _myQueueWatcher?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStudentInfo() async {
    final user = _auth.currentUser!;
    final doc = await _firestore.collection('users').doc(user.uid).get();

    if (doc.exists && mounted) {
      final data = doc.data();

      setState(() {
        _studentName = data?['name'] ?? data?['email'] ?? 'Öğrenci';
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

  void _listenForMyQueue() {
    final userId = _auth.currentUser!.uid;

    _myQueueWatcher?.cancel();

    _myQueueWatcher = _firestore
        .collection('queues')
        .where('studentId', isEqualTo: userId)
        .where('status', whereIn: ['waiting', 'in_progress'])
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isEmpty) {
  if (mounted) {
    setState(() {
      _isInQueue = false;
      _currentQueueId = null;
      _currentTeacherName = null;
      _queuePosition = 0;
    });
  }

  return;
}

      final doc = snapshot.docs.first;
      final data = doc.data();

      if (mounted) {
        setState(() {
          _isInQueue = true;
          _currentQueueId = doc.id;
        });
      }

      _listenToQueue(doc.id);

      final teacherId = data['teacherId'];
      if (teacherId != null) {
        _getCurrentTeacherName(teacherId);
      }
    });
  }

  Future<void> _getCurrentTeacherName(String teacherId) async {
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
    if (_currentQueueId == queueId && _queueSubscription != null) return;

    _queueSubscription?.cancel();

    _queueSubscription =
        _firestore.collection('queues').doc(queueId).snapshots().listen(
      (snapshot) async {
        if (!snapshot.exists) return;

        final data = snapshot.data()!;
        final status = data['status'];

  if (status == 'completed') {
  if (mounted) {
    setState(() {
      _isInQueue = false;
      _currentQueueId = null;
      _queuePosition = 0;
    });
  }

  _showRatingDialog(queueId);

  _queueSubscription?.cancel();
  _queueSubscription = null;
} else if (status == 'cancelled') {
          if (mounted) {
            setState(() {
              _isInQueue = false;
              _currentQueueId = null;
              _currentTeacherName = null;
              _queuePosition = 0;
            });
          }

          _queueSubscription?.cancel();
          _queueSubscription = null;
        } else if (status == 'in_progress') {
          final teacherNameFromQueue = data['teacherName'];

          if (mounted) {
            setState(() {
              _queuePosition = 0;

              if (teacherNameFromQueue != null) {
                _currentTeacherName = teacherNameFromQueue;
              }
            });
          }

          if (data['teacherId'] != null) {
            _getCurrentTeacherName(data['teacherId']);
          }
        } else if (status == 'waiting') {
          await _updatePosition(queueId);
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
    if (subject.isEmpty) return;

    setState(() {
      _isLoadingTeachers = true;
      _teachersForSubject = [];
      _selectedTeacherId = null;
    });

    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'teacher')
          .where('subjects', arrayContains: subject)
          .get();

final teachers = snapshot.docs
    .where((doc) {
      final data = doc.data();
      final status = data['teacherStatus'] ?? 'available';

      return status == 'available';
    })
    .map((doc) {
      final data = doc.data();

      return {
        'id': doc.id,
        'name': data['name'] ?? data['email'] ?? 'Öğretmen',
      };
    })
    .toList();

      if (mounted) {
        setState(() {
          _teachersForSubject = teachers;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Öğretmenler yüklenemedi: $e')),
      );
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

    if (_selectedSubject == null ||
        _selectedSubject!.isEmpty ||
        (_teachersForSubject.isEmpty &&
            (_selectedTeacherId == null || _selectedTeacherId!.isEmpty))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir ders ve öğretmen seçin')),
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

    String teacherId;

    if (_selectedTeacherId != null && _selectedTeacherId!.isNotEmpty) {
      teacherId = _selectedTeacherId!;
    } else {
      final teachersSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'teacher')
          .where('subjects', arrayContains: _selectedSubject)
          .get();
          final availableTeachers = teachersSnapshot.docs.where((doc) {
  final data = doc.data();
  final status = data['teacherStatus'] ?? 'available';

  return status == 'available';
}).toList();

      if (availableTeachers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_selectedSubject} dersi için uygun öğretmen bulunamadı',
            ),
          ),
        );
        return;
      }

   final randomIndex =
    DateTime.now().millisecondsSinceEpoch % availableTeachers.length;

teacherId = availableTeachers[randomIndex].id;
    }

    try {
      final newQueue = {
        'studentId': userId,
        'teacherId': teacherId,
        'subject': _selectedSubject,
        'status': 'waiting',
        'studentName': _studentName,
        'createdAt': FieldValue.serverTimestamp(),
      };

      final docRef = await _firestore.collection('queues').add(newQueue);

      if (mounted) {
        setState(() {
          _isInQueue = true;
          _currentQueueId = docRef.id;
          _queuePosition = 1;
        });
      }

      _listenToQueue(docRef.id);
      _getCurrentTeacherName(teacherId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sıranız alındı! Lütfen bekleyin.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sıra alınamadı: $e')),
      );
    }
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

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(24, 16, 8, 0),

            title: Row(
              children: [
                const Expanded(
                  child: Text('Sorunuz çözüldü!'),
                ),

                if (showCloseButton)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Kapat',
                    onPressed: () {
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),

            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Öğretmeni puanlayın'),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    5,
                    (i) => IconButton(
                      icon: Icon(
                        i < rating
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.orange,
                      ),
                      onPressed: () {
                        setStateDialog(() {
                          rating = i + 1;
                        });
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Yorum (isteğe bağlı)',
                  ),
                  onChanged: (val) {
                    comment = val;
                  },
                ),
              ],
            ),

            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    await _firestore
                        .collection('queues')
                        .doc(queueId)
                        .update({
                      'rating': rating,
                      'comment': comment,
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
                child: const Text('Gönder'),
              ),
            ],
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

  Widget _buildCooldownCard() {
    if (_remainingCooldownSeconds <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tekrar sıra almak için ${_formatCooldown(_remainingCooldownSeconds)} bekleyiniz lütfen.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canJoinQueue = _selectedSubject != null &&
        (_teachersForSubject.isNotEmpty || _selectedTeacherId != null) &&
        _remainingCooldownSeconds <= 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Hoşgeldin, ${_studentName ?? 'Öğrenci'}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _auth.signOut();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: _isInQueue
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.hourglass_top,
                    size: 64,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _queuePosition == 0
                        ? 'Öğretmen sorunuzla ilgileniyor...'
                        : 'Önünüzde $_queuePosition kişi var.',
                    style: const TextStyle(fontSize: 18),
                  ),
                  if (_currentTeacherName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Öğretmen: $_currentTeacherName',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: _queuePosition == 0 ? null : _cancelQueue,
                    icon: const Icon(Icons.cancel),
                    label: const Text('Sırayı İptal Et'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildCooldownCard(),

                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Ders Seçin'),
                    items: _subjects.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(s),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedSubject = value;
                        _selectedTeacherId = null;
                      });

                      if (value != null) {
                        _loadTeachersForSubject(value);
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  if (_selectedSubject != null) ...[
                    if (_isLoadingTeachers)
                      const Center(child: CircularProgressIndicator())
                    else if (_teachersForSubject.isEmpty)
                      const Text(
                        'Bu dersi veren öğretmen bulunamadı',
                        style: TextStyle(color: Colors.red),
                      )
                    else
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Öğretmen Seç (isteğe bağlı)',
                        ),
                        hint: const Text('Rastgele'),
                        items: _teachersForSubject.map((t) {
                          return DropdownMenuItem<String>(
                            value: t['id'],
                            child: Text(t['name']),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedTeacherId = val;
                          });
                        },
                      ),
                  ],

                  const SizedBox(height: 32),

                  ElevatedButton.icon(
                    onPressed: canJoinQueue ? _joinQueue : null,
                    icon: const Icon(Icons.queue),
                    label: const Text('Sıra Al'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}