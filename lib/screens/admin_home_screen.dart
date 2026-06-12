import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  _AdminHomeScreenState createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _selectedIndex = 0; // 0: İstatistik, 1: Kullanıcı Yönetimi

  final List<Widget> _pages = [
    const StatisticsPage(),
    
    const UserManagementPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedIndex == 0 ? 'İstatistikler' : 'Kullanıcı Yönetimi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Colors.blue),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('Yönetici Paneli', style: TextStyle(color: Colors.white, fontSize: 24)),
                  const SizedBox(height: 8),
                  Text(FirebaseAuth.instance.currentUser?.email ?? '', style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('İstatistikler'),
              selected: _selectedIndex == 0,
              onTap: () {
                setState(() => _selectedIndex = 0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Kullanıcı Yönetimi'),
              selected: _selectedIndex == 1,
              onTap: () {
                setState(() => _selectedIndex = 1);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: _pages[_selectedIndex],
    );
  }
}

// ==================== 1. İSTATİSTİK SAYFASI ====================
class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  _StatisticsPageState createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, int> _subjectStats = {};
  Map<String, Map<String, int>> _dailySubjectStats = {};
  Map<String, int> _dailyStats = {};

  int _totalSolvedToday = 0;
  int _totalSolvedAll = 0;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  String _dateKey(DateTime date) {
    return '${date.day}/${date.month}';
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    Map<String, Map<String, int>> dailySubjectCount = {};

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      final last7DaysStart = todayStart.subtract(const Duration(days: 6));

      final snapshot = await _firestore
          .collection('queues')
          .where('status', isEqualTo: 'completed')
          .get();

      Map<String, int> subjectCount = {};
      Map<String, int> dailyCount = {};
      Map<String, Map<String, int>> dailySubjectCount = {};

      for (int i = 6; i >= 0; i--) {
        final day = todayStart.subtract(Duration(days: i));
        dailyCount[_dateKey(day)] = 0;
        dailySubjectCount[_dateKey(day)] = {};
      }

      int todayCount = 0;
      int allCount = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();

        final completedAt = data['completedAt'] as Timestamp?;
        if (completedAt == null) continue;

        final completedDate = completedAt.toDate();

        allCount++;

        if (completedDate.year == now.year &&
            completedDate.month == now.month &&
            completedDate.day == now.day) {
          todayCount++;

          final subject = data['subject'] as String? ?? 'Bilinmeyen';
          subjectCount[subject] = (subjectCount[subject] ?? 0) + 1;
        }

        if (completedDate.isAfter(last7DaysStart.subtract(const Duration(seconds: 1)))) {
  final key = _dateKey(completedDate);

  if (dailyCount.containsKey(key)) {
    dailyCount[key] = dailyCount[key]! + 1;

    final subject = data['subject'] as String? ?? 'Bilinmeyen';

    dailySubjectCount[key] ??= {};

    dailySubjectCount[key]![subject] =
        (dailySubjectCount[key]![subject] ?? 0) + 1;
  }
}
      }

      setState(() {
        _subjectStats = subjectCount;
        _dailyStats = dailyCount;
        _totalSolvedToday = todayCount;
        _totalSolvedAll = allCount;
        _dailySubjectStats = dailySubjectCount;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('İstatistik yüklenemedi: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadStats,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text(
                          'Bugün Toplam Çözülen Soru',
                          style: TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$_totalSolvedToday',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Card(
                  child: ListTile(
                    leading: const Icon(Icons.done_all, color: Colors.blue),
                    title: const Text('Toplam Çözülen Soru'),
                    trailing: Text(
                      '$_totalSolvedAll',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'Son 7 Günlük Çözülen Soru Grafiği',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      height: 300,
                      child: _DailySolvedBarChart(
  data: _dailyStats,
  subjectData: _dailySubjectStats,
),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'Bugünkü Ders Bazında Dağılım',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                ..._subjectStats.entries.map(
                  (entry) => Card(
                    child: ListTile(
                      title: Text(entry.key),
                      trailing: Text(
                        '${entry.value} soru',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),

                if (_subjectStats.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 32),
                    child: Center(
                      child: Text('Bugün henüz çözülen soru yok'),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _DailySolvedBarChart extends StatefulWidget {
  final Map<String, int> data;
  final Map<String, Map<String, int>> subjectData;

  const _DailySolvedBarChart({
    required this.data,
    required this.subjectData,
  });

  @override
  State<_DailySolvedBarChart> createState() => _DailySolvedBarChartState();
}

class _DailySolvedBarChartState extends State<_DailySolvedBarChart> {
  String? _selectedDate;
  bool _showSubjectDetail = false;

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return const Center(child: Text('Grafik için veri yok'));
    }

    final maxValue = widget.data.values.reduce((a, b) => a > b ? a : b);
    final selectedDate = _selectedDate ?? widget.data.keys.last;
    final selectedTotal = widget.data[selectedDate] ?? 0;
    final selectedSubjects = widget.subjectData[selectedDate] ?? {};

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: widget.data.entries.map((entry) {
              final value = entry.value;
              final isSelected = entry.key == selectedDate;
              final barHeight =
                  maxValue == 0 ? 8.0 : (value / maxValue) * 120;

              return Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedDate = entry.key;
                      _showSubjectDetail = false;
                    });
                  },
                  onLongPress: () {
                    setState(() {
                      _selectedDate = entry.key;
                      _showSubjectDetail = true;
                    });
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '$value',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.blue : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: barHeight < 8 ? 8 : barHeight,
                        width: isSelected ? 28 : 22,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.blue
                              : Colors.blue.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 16),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _showSubjectDetail
                ? Colors.orange.shade50
                : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _showSubjectDetail
                  ? Colors.orange.shade200
                  : Colors.blue.shade100,
            ),
          ),
          child: _showSubjectDetail
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$selectedDate ders dağılımı',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (selectedSubjects.isEmpty)
                      const Text('Bu gün için ders bazlı veri yok.')
                    else
                      ...selectedSubjects.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.key),
                              Text(
                                '${e.value} soru',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                )
              : Text(
                  '$selectedDate • Toplam: $selectedTotal soru',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
        ),
      ],
    );
  }
}
// ==================== 2. KULLANICI YÖNETİM SAYFASI ====================
class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  _UserManagementPageState createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<String> _roles = ['student', 'teacher', 'admin'];
  final List<String> _allSubjects = ['Matematik', 'Fizik', 'Kimya', 'Biyoloji', 'Türkçe', 'Tarih', 'Coğrafya', 'Geometri'];
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton.icon(
            onPressed: () => _showUserDialog(),
            icon: const Icon(Icons.person_add),
            label: const Text('Yeni Kullanıcı Ekle'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('users').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('Hata: ${snapshot.error}'));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final users = snapshot.data!.docs;
              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final doc = users[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final uid = doc.id;
                  final role = data['role'] ?? '?';
                  final name = data['name'] ?? 'İsimsiz';
                  final email = data['email'] ?? 'Email yok';
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: role == 'admin' ? Colors.red : (role == 'teacher' ? Colors.blue : Colors.green),
                        child: Text(role[0].toUpperCase()),
                      ),
                      title: Text('$name ($role)'),
                      subtitle: Text(email),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit), onPressed: () => _editUser(uid, data)),
                          IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteUser(uid, email), color: Colors.red),
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

  Future<void> _showUserDialog({String? editingUid, Map<String, dynamic>? existingData}) async {
    final isEditing = editingUid != null;
    final formKey = GlobalKey<FormState>();
    String email = existingData?['email'] ?? '';
    String password = '';
    String name = existingData?['name'] ?? '';
    String role = existingData?['role'] ?? 'student';
    List<String> selectedSubjects = existingData?['subjects'] != null ? List<String>.from(existingData?['subjects']) : [];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(isEditing ? 'Kullanıcı Düzenle' : 'Yeni Kullanıcı Ekle'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: email,
                      decoration: const InputDecoration(labelText: 'E-posta'),
                      onChanged: (val) => email = val,
                      validator: (val) => val!.isEmpty ? 'Email gerekli' : null,
                    ),
                    if (!isEditing) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        decoration: const InputDecoration(labelText: 'Şifre'),
                        obscureText: true,
                        onChanged: (val) => password = val,
                        validator: (val) => val!.length < 6 ? 'Şifre en az 6 karakter' : null,
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: name,
                      decoration: const InputDecoration(labelText: 'Ad Soyad'),
                      onChanged: (val) => name = val,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Rol'),
                      items: _roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                      onChanged: (val) => setStateDialog(() => role = val!),
                    ),
                    if (role == 'teacher') ...[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Verdiği Dersler (birden çok seçebilirsiniz)'),
                            Wrap(
                              children: _allSubjects.map((subject) {
                                return CheckboxListTile(
                                  title: Text(subject),
                                  value: selectedSubjects.contains(subject),
                                  onChanged: (checked) {
                                    setStateDialog(() {
                                      if (checked == true) {
                                        selectedSubjects.add(subject);
                                      } else {
                                        selectedSubjects.remove(subject);
                                      }
                                    });
                                  },
                                  controlAffinity: ListTileControlAffinity.leading,
                                  dense: true,
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  setState(() => _isLoading = true);
                  try {
                    if (isEditing) {
                      await _updateUser(editingUid, email, name, role, selectedSubjects);
                    } else {
                      await _createUser(email, password, name, role, selectedSubjects);
                    }
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEditing ? 'Kullanıcı güncellendi' : 'Kullanıcı oluşturuldu')));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                  } finally {
                    setState(() => _isLoading = false);
                  }
                },
                child: Text(isEditing ? 'Güncelle' : 'Oluştur'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createUser(String email, String password, String name, String role, List<String> subjects) async {
    const apiKey = 'AIzaSyBznoF8WcalY8k-tUexUTrooeDJdZHsM5w'; 
    final url = Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey');
    final response = await http.post(
      url,
      body: jsonEncode({'email': email, 'password': password, 'returnSecureToken': true}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error']['message'];
      throw Exception('Auth oluşturulamadı: $error');
    }
    final uid = jsonDecode(response.body)['localId'];
    Map<String, dynamic> userData = {'email': email, 'name': name, 'role': role};
    if (role == 'teacher') userData['subjects'] = subjects;
    await _firestore.collection('users').doc(uid).set(userData);
  }

  Future<void> _updateUser(String uid, String newEmail, String newName, String newRole, List<String> subjects) async {
    Map<String, dynamic> updates = {'name': newName, 'role': newRole, 'email': newEmail};
    if (newRole == 'teacher') {
      updates['subjects'] = subjects;
    } else {
      updates['subjects'] = FieldValue.delete();
    }
    await _firestore.collection('users').doc(uid).update(updates);
  }

  Future<void> _deleteUser(String uid, String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kullanıcıyı Sil'),
        content: Text('$email adlı kullanıcıyı silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hayır')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Evet')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isLoading = true);
    try {
      await _firestore.collection('users').doc(uid).delete();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kullanıcı Firestore\'dan silindi.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Silme hatası: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _editUser(String uid, Map<String, dynamic> data) {
    _showUserDialog(editingUid: uid, existingData: data);
  }
}