import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '../models/education_scope.dart';
import '../utils/class_name_display.dart';
import '../utils/guidance_presentation.dart';
import '../utils/guidance_student_groups.dart';

const _guidanceTerminalStatuses = {'completed', 'cancelled', 'no_show'};

InputDecoration _guidanceDialogFieldDecoration(String label) {
  const borderColor = Color(0x66FFFFFF);
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white70),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.08),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: borderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFFFB1C8), width: 1.5),
    ),
  );
}

String _guidanceStatus(String? value) => guidanceStatusValue(value);

bool _isGuidanceToday(Map<String, dynamic> data) {
  if (data['dayLabel'] == 'Bugün') return true;
  final now = DateTime.now();
  final today =
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return data['appointmentDate']?.toString() == today;
}

bool _canChangeGuidanceStatus(String currentStatus, String nextStatus) {
  final current = _guidanceStatus(currentStatus);
  return (current == 'pending' &&
          {'approved', 'cancelled', 'no_show'}.contains(nextStatus)) ||
      (current == 'approved' &&
          {'in_progress', 'cancelled', 'no_show'}.contains(nextStatus)) ||
      (current == 'in_progress' && nextStatus == 'completed');
}

Map<String, dynamic> _guidanceStatusUpdate(
  String currentStatus,
  String nextStatus,
) {
  if (!_canChangeGuidanceStatus(currentStatus, nextStatus)) {
    throw StateError('Invalid guidance appointment status transition.');
  }

  final auditField = switch (nextStatus) {
    'approved' => 'approvedAt',
    'in_progress' => 'startedAt',
    'completed' => 'completedAt',
    'cancelled' => 'cancelledAt',
    'no_show' => 'noShowAt',
    _ => throw StateError('Unsupported guidance appointment status.'),
  };

  return {
    'status': nextStatus,
    'updatedAt': FieldValue.serverTimestamp(),
    auditField: FieldValue.serverTimestamp(),
  };
}

class GuidanceHomeScreen extends StatefulWidget {
  const GuidanceHomeScreen({super.key});
  @override
  State<GuidanceHomeScreen> createState() => _GuidanceHomeScreenState();
}

class _GuidanceHomeScreenState extends State<GuidanceHomeScreen> {
  final db = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  final functions = FirebaseFunctions.instance;
  String flowFilter = 'today';
  String _studentSearch = '';
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _studentsSubscription;
  Map<String, Map<String, dynamic>> _studentsById = const {};
  static const _reportsBaseUrl =
      'https://zumrenet-reports-542741706921.europe-west1.run.app';

  String statusLabel(String s) => guidanceStatusLabel(s);
  Color statusColor(String s) => s == 'completed'
      ? Colors.green
      : s == 'in_progress'
          ? Colors.orange
          : s == 'no_show' || s == 'cancelled'
              ? Colors.red
              : s == 'approved'
                  ? Colors.teal
                  : const Color(0xFF2675D8);

  @override
  void initState() {
    super.initState();
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    _studentsSubscription = db
        .collection('users')
        .where('role', isEqualTo: 'student')
        .where('guidanceCounselorId', isEqualTo: uid)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _studentsById = {
          for (final doc in snapshot.docs)
            doc.id: {...doc.data(), '_id': doc.id},
        };
      });
    });
  }

  @override
  void dispose() {
    _studentsSubscription?.cancel();
    super.dispose();
  }

  Future<void> changeStatus(
      String id, String currentStatus, String nextStatus) async {
    if (!_canChangeGuidanceStatus(currentStatus, nextStatus)) return;
    await db.collection('guidanceAppointments').doc(id).update(
          _guidanceStatusUpdate(currentStatus, nextStatus),
        );
  }

  List<_GuidanceClassOption> _classSummaryOptions(
    Map<String, Map<String, dynamic>> studentsById,
  ) {
    final options = <String, _GuidanceClassOption>{};
    for (final student in studentsById.values) {
      final className = '${student['className'] ?? ''}'.trim();
      if (className.isEmpty) continue;
      final option = _GuidanceClassOption(
        className: className,
        branch: '${student['branch'] ?? ''}'.trim(),
        department: '${student['department'] ?? ''}'.trim(),
      );
      options[option.key] = option;
    }
    final values = options.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return values;
  }

  Future<void> _showClassActivitySummary() async {
    final studentsById = _studentsById;
    if (!mounted) return;
    final classes = _classSummaryOptions(studentsById);
    if (classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Faaliyet özeti için sınıf bilgisi bulunamadı.'),
      ));
      return;
    }
    var selected = classes.first;
    final request = await showDialog<_GuidanceSummaryRequest>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF5A1C38), Color(0xFF32101F)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.picture_as_pdf_rounded,
                        color: Color(0xFFFFB1C8)),
                    SizedBox(width: 10),
                    Text(
                      'Sınıf Faaliyet Özeti',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Özet anonimdir; panoya asılabilir veya öğrenci/veli WhatsApp gruplarında paylaşılabilir.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<_GuidanceClassOption>(
                  initialValue: selected,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF4A1830),
                  iconEnabledColor: Colors.white70,
                  style: const TextStyle(color: Colors.white),
                  decoration: _guidanceDialogFieldDecoration('Sınıf'),
                  items: classes
                      .map((item) => DropdownMenuItem(
                            value: item,
                            child: Text(
                              item.displayName,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => selected = value);
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.white70),
                      child: const Text('Vazgeç'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(
                        dialogContext,
                        _GuidanceSummaryRequest(selected),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB1C8),
                        foregroundColor: const Color(0xFF4A1830),
                      ),
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('Özeti Hazırla'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (request == null) return;
    await _requestClassActivitySummary(request);
  }

  Future<void> _requestClassActivitySummary(
    _GuidanceSummaryRequest request,
  ) async {
    var loadingShown = false;
    try {
      final token = await auth.currentUser?.getIdToken();
      if (token == null || token.isEmpty) {
        throw StateError('Geçerli oturum bulunamadı.');
      }
      if (!mounted) return;
      loadingShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF32101F),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white24),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFFB1C8)),
                  SizedBox(height: 18),
                  Text(
                    'Faaliyet özeti oluşturuluyor…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Kayıtlar hazırlanıp PDF oluşturuluyor. Bu işlem birkaç saniye sürebilir; pencereyi kapatmayın.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final response = await http.post(
        Uri.parse('$_reportsBaseUrl/reports/class-activity-summary'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'startDate': today,
          'endDate': today,
          'className': request.classOption.className,
          if (request.classOption.branch.isNotEmpty)
            'branch': request.classOption.branch,
          if (request.classOption.department.isNotEmpty)
            'department': request.classOption.department,
        }),
      );
      if (loadingShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingShown = false;
      }
      if (response.statusCode != 200) {
        String detail = '';
        try {
          final body = jsonDecode(response.body);
          if (body is Map) detail = '${body['detail'] ?? ''}'.trim();
        } catch (_) {
          // Non-JSON error pages are handled by the status-specific message.
        }
        if (response.statusCode == 404) {
          throw StateError(
            'Faaliyet özeti servisi güncel değil. Lütfen kurum yöneticisine bildirin.',
          );
        }
        throw StateError(
          detail.isNotEmpty ? detail : 'Faaliyet özeti oluşturulamadı.',
        );
      }
      await Printing.sharePdf(
        bytes: response.bodyBytes,
        filename: '${request.classOption.filePrefix}_Sinif_Faaliyet_Ozeti.pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Güvenli faaliyet özeti hazır.'),
      ));
    } on StateError catch (error) {
      if (loadingShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingShown = false;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.message.toString()),
      ));
    } catch (_) {
      if (loadingShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingShown = false;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Faaliyet özeti hazırlanamadı. Lütfen tekrar deneyin.'),
      ));
    }
  }

  Future<void> _showStudentAssignmentDialog() async {
    final snapshot = await db
        .collection('users')
        .where('role', isEqualTo: 'student')
        .get();
    if (!mounted) return;

    final students = snapshot.docs;
    final uid = auth.currentUser!.uid;
    String query = '';
    String levelFilter = 'ALL';
    String classFilter = 'ALL';
    final selectedIds = <String>{};
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final classOptions = students
              .map((doc) => formatStudentClassDisplay(
                    className: doc.data()['className'],
                    branch: doc.data()['branch'],
                    department: doc.data()['department'],
                  ))
              .where((value) => value.trim().isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          final filtered = students.where((doc) {
            final data = doc.data();
            final name = guidanceStudentName(data).toLowerCase();
            final classLabel = formatStudentClassDisplay(
              className: data['className'],
              branch: data['branch'],
              department: data['department'],
            );
            final level = inferredStudentEducationLevel(data) ?? '';
            final counselorId =
                '${data['guidanceCounselorId'] ?? ''}'.trim();
            final visibleByAssignment =
                counselorId.isEmpty || counselorId == uid;
            final q = query.trim().toLowerCase();
            final matchesSearch = q.isEmpty ||
                name.contains(q) ||
                classLabel.toLowerCase().contains(q);
            final matchesLevel =
                levelFilter == 'ALL' || level == levelFilter;
            final matchesClass =
                classFilter == 'ALL' || classLabel == classFilter;
            return visibleByAssignment &&
                matchesSearch &&
                matchesLevel &&
                matchesClass;
          }).toList()
            ..sort((a, b) {
              final ac = formatStudentClassDisplay(
                className: a.data()['className'],
                branch: a.data()['branch'],
                department: a.data()['department'],
              );
              final bc = formatStudentClassDisplay(
                className: b.data()['className'],
                branch: b.data()['branch'],
                department: b.data()['department'],
              );
              final byClass = ac.compareTo(bc);
              return byClass != 0
                  ? byClass
                  : guidanceStudentName(a.data())
                      .compareTo(guidanceStudentName(b.data()));
            });

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4A102B), Color(0xFF8B3155)],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                children: [
                  Row(children: [
                    const Icon(Icons.group_add_rounded,
                        color: Color(0xFFFFB1C8), size: 28),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Öğrenci Ata',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800)),
                          Text(
                              'Kademe ve sınıfa göre öğrencileri filtreleyin. Size atanmış öğrenciler bilgi amaçlı listede kalır.',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: submitting
                          ? null
                          : () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (value) =>
                        setDialogState(() => query = value),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Öğrenci veya sınıf ara',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: .10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: levelFilter,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF4A1830),
                        style: const TextStyle(color: Colors.white),
                        decoration: _guidanceDialogFieldDecoration('Kademe'),
                        items: const [
                          DropdownMenuItem(value: 'ALL', child: Text('Tümü')),
                          DropdownMenuItem(value: 'LGS', child: Text('LGS')),
                          DropdownMenuItem(value: 'YKS', child: Text('YKS')),
                        ],
                        onChanged: (value) => setDialogState(() {
                          levelFilter = value ?? 'ALL';
                          classFilter = 'ALL';
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: classFilter,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF4A1830),
                        style: const TextStyle(color: Colors.white),
                        decoration: _guidanceDialogFieldDecoration('Sınıf'),
                        items: [
                          const DropdownMenuItem(
                              value: 'ALL', child: Text('Tümü')),
                          ...classOptions.map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(value,
                                    overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (value) => setDialogState(
                            () => classFilter = value ?? 'ALL'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'Atanabilecek öğrenci bulunmuyor.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, index) {
                              final doc = filtered[index];
                              final data = doc.data();
                              final selected = selectedIds.contains(doc.id);
                              final counselorId =
                                  '${data['guidanceCounselorId'] ?? ''}'.trim();
                              final assignedToMe = counselorId == uid;
                              final classLabel = formatStudentClassDisplay(
                                className: data['className'],
                                branch: data['branch'],
                                department: data['department'],
                              );
                              return CheckboxListTile(
                                value: selected,
                                activeColor: const Color(0xFFFFB1C8),
                                checkColor: const Color(0xFF4A1830),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(guidanceStudentName(data),
                                    style:
                                        const TextStyle(color: Colors.white)),
                                subtitle: Text(
                                  [
                                    if (classLabel.isNotEmpty) classLabel,
                                    if (assignedToMe) 'Zaten size atanmış',
                                  ].join(' • '),
                                  style: TextStyle(
                                    color: assignedToMe
                                        ? const Color(0xFFFFB1C8)
                                        : Colors.white60,
                                  ),
                                ),
                                onChanged: submitting || assignedToMe
                                    ? null
                                    : (value) => setDialogState(() {
                                          if (value == true) {
                                            selectedIds.add(doc.id);
                                          } else {
                                            selectedIds.remove(doc.id);
                                          }
                                        }),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: selectedIds.isEmpty || submitting
                          ? null
                          : () async {
                              setDialogState(() => submitting = true);
                              try {
                                final response = await functions
                                    .httpsCallable('guidanceAssignStudents')
                                    .call({
                                  'studentIds': selectedIds.toList(),
                                });
                                final data =
                                    Map<String, dynamic>.from(response.data);
                                final assigned =
                                    (data['assignedCount'] as num?)?.toInt() ??
                                        0;
                                final skipped =
                                    (data['skippedCount'] as num?)?.toInt() ??
                                        0;
                                if (!dialogContext.mounted) return;
                                Navigator.pop(dialogContext);
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(skipped == 0
                                        ? '$assigned öğrenci size atandı.'
                                        : '$assigned öğrenci atandı, $skipped öğrenci daha önce atanmış olduğu için atlandı.'),
                                  ),
                                );
                              } on FirebaseFunctionsException catch (error) {
                                if (!dialogContext.mounted) return;
                                setDialogState(() => submitting = false);
                                ScaffoldMessenger.of(dialogContext)
                                    .showSnackBar(SnackBar(
                                  content: Text(error.message ??
                                      'Öğrenci ataması yapılamadı.'),
                                ));
                              }
                            },
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(submitting
                          ? 'Atanıyor...'
                          : 'Seçilenleri Öğrencilerime Ekle'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB1C8),
                        foregroundColor: const Color(0xFF4A1830),
                        padding: const EdgeInsets.symmetric(vertical: 14),
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

  Future<void> addStudent() async {
    final students = await db
        .collection('users')
        .where('role', isEqualTo: 'student')
        .where('guidanceCounselorId', isEqualTo: auth.currentUser!.uid)
        .get();
    if (!mounted) return;
    String query = '';
    String? selectedId;
    String? selectedName;
    String reason = 'Akademik takip';
    String day = 'Bugün';
    String time = '14:30';
    final timeController = TextEditingController(text: time);
    bool isSubmitting = false;
    const days = [
      'Bugün',
      'Yarın',
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma'
    ];
    const reasons = [
      'Akademik takip',
      'Ödev kontrolü',
      'Sınav / hedef planlama',
      'Ders çalışma düzeni',
      'Motivasyon',
      'Genel görüşme'
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final filtered = students.docs.where((d) {
          final x = d.data();
          final name =
              '${x['fullName'] ?? '${x['name'] ?? ''} ${x['surname'] ?? ''}'}'
                  .trim();
          final cls = '${x['className'] ?? ''} ${x['branch'] ?? ''}'.trim();
          final q = query.toLowerCase();
          return q.isEmpty ||
              name.toLowerCase().contains(q) ||
              cls.toLowerCase().contains(q);
        }).toList();
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4A102B), Color(0xFF8B3155)]),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(children: [
              Row(children: [
                Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFB1C8).withValues(alpha: .16),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.person_add_alt_1_rounded,
                        color: Color(0xFFFFB1C8), size: 28)),
                const SizedBox(width: 12),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Öğrenci Ekle',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w800)),
                      Text('Kayıtlı öğrencilerden birini seçin.',
                          style: TextStyle(color: Colors.white70, fontSize: 12))
                    ])),
                IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white70)),
              ]),
              const SizedBox(height: 14),
              TextField(
                  onChanged: (v) => setD(() => query = v),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                      hintText: 'Öğrenci ara...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: .11),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none))),
              const SizedBox(height: 12),
              Expanded(
                  child: Container(
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: .15))),
                      child: ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: Colors.white.withValues(alpha: .10)),
                          itemBuilder: (_, i) {
                            final d = filtered[i];
                            final x = d.data();
                            final name =
                                '${x['fullName'] ?? '${x['name'] ?? ''} ${x['surname'] ?? ''}'}'
                                    .trim();
                            final cls = formatStudentClassDisplay(
                              className: x['className'],
                              branch: x['branch'],
                            );
                            final selected = selectedId == d.id;
                            return ListTile(
                                onTap: () => setD(() {
                                      selectedId = d.id;
                                      selectedName = name;
                                    }),
                                leading: CircleAvatar(
                                    backgroundColor: selected
                                        ? const Color(0xFFFFB1C8)
                                        : Colors.white12,
                                    child: Icon(
                                        selected
                                            ? Icons.check_rounded
                                            : Icons.person_rounded,
                                        color: selected
                                            ? const Color(0xFF4A102B)
                                            : Colors.white)),
                                title: Text(name,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700)),
                                subtitle: cls.isEmpty
                                    ? null
                                    : Text(cls,
                                        style: const TextStyle(
                                            color: Colors.white60)),
                                trailing: selected
                                    ? const Icon(Icons.check_circle_rounded,
                                        color: Color(0xFFFFB1C8))
                                    : null);
                          }))),
              if (selectedId != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: DropdownButtonFormField<String>(
                          initialValue: reason,
                          dropdownColor: const Color(0xFF681E40),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                              labelText: 'Görüşme / görev',
                              labelStyle: TextStyle(color: Colors.white70),
                              enabledBorder: UnderlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Colors.white38))),
                          items: reasons
                              .map((e) =>
                                  DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setD(() => reason = v ?? reason))),
                ]),
                const SizedBox(height: 8),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Gün',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700))),
                const SizedBox(height: 6),
                SizedBox(
                    height: 42,
                    child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: days.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 7),
                        itemBuilder: (_, i) {
                          final e = days[i];
                          return ChoiceChip(
                              label: Text(e),
                              selected: day == e,
                              onSelected: (_) => setD(() => day = e),
                              selectedColor: const Color(0xFFFFB1C8),
                              backgroundColor: Colors.white10,
                              labelStyle: TextStyle(
                                  color: day == e
                                      ? const Color(0xFF4A102B)
                                      : Colors.white));
                        })),
                const SizedBox(height: 8),
                TextField(
                    controller: timeController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_TimeTextFormatter()],
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: 'Saat',
                        hintText: '14:30',
                        labelStyle: TextStyle(color: Colors.white70)),
                    onChanged: (v) => time = v),
              ],
              const SizedBox(height: 12),
              SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB1C8),
                          foregroundColor: const Color(0xFF4A102B),
                          disabledBackgroundColor: Colors.white12),
                      onPressed: selectedId == null || isSubmitting
                          ? null
                          : () async {
                              final currentUser = auth.currentUser;
                              if (currentUser == null) return;
                              setD(() => isSubmitting = true);
                              try {
                                final u = await db
                                    .collection('users')
                                    .doc(currentUser.uid)
                                    .get();
                                final data = u.data() ?? {};
                                final counselorName =
                                    '${data['fullName'] ?? '${data['name'] ?? ''} ${data['surname'] ?? ''}'}'
                                        .trim();
                                await db
                                    .collection('guidanceAppointments')
                                    .add({
                                  'studentId': selectedId,
                                  'studentName': selectedName,
                                  'counselorId': currentUser.uid,
                                  'counselorName': counselorName.isEmpty
                                      ? 'Rehberlik Servisi'
                                      : counselorName,
                                  'reason': reason,
                                  'dayLabel': day,
                                  'time': time,
                                  'status': 'approved',
                                  'source': 'guidance',
                                  'createdAt': FieldValue.serverTimestamp(),
                                  'updatedAt': FieldValue.serverTimestamp(),
                                  'approvedAt': FieldValue.serverTimestamp()
                                });
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                              } catch (_) {
                                if (ctx.mounted) {
                                  setD(() => isSubmitting = false);
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Görüşme eklenemedi. Lütfen tekrar deneyin.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                      icon: const Icon(Icons.add_rounded),
                      label: Text(
                          isSubmitting ? 'Ekleniyor...' : 'Görüşmeye Ekle',
                          style:
                              const TextStyle(fontWeight: FontWeight.w800)))),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> addWeeklyTask({
    String? initialStudentId,
    Map<String, dynamic>? initialStudent,
  }) async {
    final students = await db
        .collection('users')
        .where('role', isEqualTo: 'student')
        .where('guidanceCounselorId', isEqualTo: auth.currentUser!.uid)
        .get();
    final activeTaskSnapshot = await db
        .collection('guidanceTasks')
        .where('counselorId', isEqualTo: auth.currentUser!.uid)
        .get();
    if (!mounted) return;
    final activeTasksByStudent = <String, Map<String, dynamic>>{};
    for (final doc in activeTaskSnapshot.docs) {
      final data = doc.data();
      if (data['active'] != false) {
        final id = '${data['studentId'] ?? ''}';
        if (id.isNotEmpty) activeTasksByStudent[id] = data;
      }
    }

    String query = '';
    String? studentId = initialStudentId;
    String? studentName =
        initialStudent == null ? null : guidanceStudentName(initialStudent);
    String title = 'Haftalık Ödev Kontrolü';
    String day = 'Her Pazartesi';
    bool isSubmitting = false;
    Map<String, dynamic>? selectedExistingTask =
        studentId == null ? null : activeTasksByStudent[studentId];
    if (selectedExistingTask != null) {
      studentId = null;
      studentName = null;
    }
    const tasks = [
      'Haftalık Ödev Kontrolü',
      'Akademik Takip',
      'Hedef Kontrolü',
      'Ders Programı Kontrolü',
    ];
    const days = [
      'Her Pazartesi',
      'Her Salı',
      'Her Çarşamba',
      'Her Perşembe',
      'Her Cuma',
      'Her Cumartesi',
      'Her Pazar',
    ];

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final filtered = students.docs.where((d) {
            final x = d.data();
            final n =
                '${x['fullName'] ?? '${x['name'] ?? ''} ${x['surname'] ?? ''}'}'
                    .toLowerCase();
            return query.isEmpty || n.contains(query.toLowerCase());
          }).toList();
          final screen = MediaQuery.of(ctx).size;
          final mobile = screen.width < 600;

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(
              horizontal: mobile ? 10 : 24,
              vertical: mobile ? 10 : 24,
            ),
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: screen.height * .92,
              ),
              padding: EdgeInsets.all(mobile ? 14 : 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4A102B), Color(0xFF8B3155)],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white12),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.repeat_rounded,
                          color: Color(0xFFFFB1C8), size: 28),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Haftalık Takip Ver',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800)),
                            Text('Öğrenci, görev ve tekrar gününü seçin.',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white70),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (v) => setD(() => query = v),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Öğrenci ara...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: .10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      constraints: BoxConstraints(
                        minHeight: 86,
                        maxHeight: mobile ? 150 : 190,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .07),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: filtered.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(18),
                                child: Text('Öğrenci bulunamadı.',
                                    style: TextStyle(color: Colors.white60)),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final d = filtered[i], x = d.data();
                                final n =
                                    '${x['fullName'] ?? '${x['name'] ?? ''} ${x['surname'] ?? ''}'}'
                                        .trim();
                                final cls = formatStudentClassDisplay(
                                  className: x['className'],
                                  branch: x['branch'],
                                );
                                final existingTask =
                                    activeTasksByStudent[d.id];
                                final hasTask = existingTask != null;
                                final selected = studentId == d.id;
                                final existingTitle =
                                    '${existingTask?['title'] ?? ''}'.trim();
                                final existingSchedule =
                                    '${existingTask?['schedule'] ?? ''}'.trim();
                                return ListTile(
                                  dense: mobile,
                                  enabled: !hasTask,
                                  onTap: hasTask
                                      ? null
                                      : () => setD(() {
                                            studentId = d.id;
                                            studentName = n;
                                          }),
                                  leading: CircleAvatar(
                                    backgroundColor: selected
                                        ? const Color(0xFFFFB1C8)
                                        : Colors.white12,
                                    child: Icon(
                                      selected ? Icons.check : Icons.person,
                                      color: selected
                                          ? const Color(0xFF4A102B)
                                          : Colors.white,
                                    ),
                                  ),
                                  title: Text(n,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                    hasTask
                                        ? [
                                            if (cls.isNotEmpty) cls,
                                            'Zaten aktif takip var',
                                            if (existingTitle.isNotEmpty)
                                              existingTitle,
                                            if (existingSchedule.isNotEmpty)
                                              existingSchedule,
                                          ].join(' • ')
                                        : cls,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: hasTask
                                          ? const Color(0xFFFFD7E4)
                                          : Colors.white60,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: Icon(
                                    hasTask
                                        ? Icons.lock_clock_rounded
                                        : selected
                                            ? Icons.check_circle
                                            : Icons.chevron_right_rounded,
                                    color: hasTask
                                        ? Colors.white38
                                        : selected
                                            ? const Color(0xFFFFB1C8)
                                            : Colors.white38,
                                  ),
                                );
                              },
                            ),
                    ),
                    if (selectedExistingTask != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB1C8)
                              .withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFFFB1C8)
                                .withValues(alpha: .30),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                color: Color(0xFFFFB1C8)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Bu öğrencinin zaten aktif haftalık takip programı var: '
                                '${selectedExistingTask['title'] ?? 'Haftalık takip'} • '
                                '${selectedExistingTask['schedule'] ?? ''}. '
                                'Değişiklik için Takipleri Yönet ekranını kullanın.',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (studentId != null) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: title,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF4A102B),
                        style: const TextStyle(color: Colors.white),
                        decoration: _guidanceDialogFieldDecoration('Görev'),
                        items: tasks
                            .map((value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setD(() => title = value ?? title),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: day,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF4A102B),
                        style: const TextStyle(color: Colors.white),
                        decoration:
                            _guidanceDialogFieldDecoration('Tekrar Günü'),
                        items: days
                            .map((value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ))
                            .toList(),
                        onChanged: (value) => setD(() => day = value ?? day),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB1C8),
                          foregroundColor: const Color(0xFF4A102B),
                        ),
                        onPressed: studentId == null || isSubmitting
                            ? null
                            : () async {
                                final selectedStudentId = studentId!;
                                final uid = auth.currentUser!.uid;
                                final taskRef = db
                                    .collection('guidanceTasks')
                                    .doc('${uid}_$selectedStudentId');
                                setD(() => isSubmitting = true);
                                try {
                                  await db.runTransaction((tx) async {
                                    final existing = await tx.get(taskRef);
                                    if (existing.exists &&
                                        existing.data()?['active'] != false) {
                                      throw StateError(
                                        'Bu öğrenci için zaten aktif bir haftalık görevlendirme var.',
                                      );
                                    }
                                    tx.set(taskRef, {
                                      'studentId': selectedStudentId,
                                      'studentName': studentName,
                                      'counselorId': uid,
                                      'title': title,
                                      'schedule': day,
                                      'active': true,
                                      'createdAt':
                                          FieldValue.serverTimestamp(),
                                      'updatedAt':
                                          FieldValue.serverTimestamp(),
                                    });
                                  });
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } on StateError catch (error) {
                                  if (!ctx.mounted) return;
                                  setD(() => isSubmitting = false);
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text(error.message)),
                                  );
                                } catch (_) {
                                  if (!ctx.mounted) return;
                                  setD(() => isSubmitting = false);
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Görevlendirme kaydedilemedi. Lütfen tekrar deneyin.',
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.repeat_rounded),
                        label: Text(
                          isSubmitting ? 'Kaydediliyor...' : 'Takibi Başlat',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> manageWeeklyTasks() async {
    final uid = auth.currentUser!.uid;
    await showDialog(
        context: context,
        builder: (ctx) => Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
                constraints:
                    const BoxConstraints(maxWidth: 520, maxHeight: 650),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF4A102B), Color(0xFF8B3155)]),
                    borderRadius: BorderRadius.circular(24)),
                child: Column(children: [
                  Row(children: [
                    const Expanded(
                        child: Text('Haftalık Takipler',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800))),
                    IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: Colors.white70))
                  ]),
                  const SizedBox(height: 8),
                  Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: db
                        .collection('guidanceTasks')
                        .where('counselorId', isEqualTo: uid)
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final tasks = snap.data!.docs
                          .where((d) => d.data()['active'] != false)
                          .toList();
                      if (tasks.isEmpty) {
                        return const Center(
                            child: Text('Aktif haftalık takip yok.',
                                style: TextStyle(color: Colors.white70)));
                      }
                      return ListView.separated(
                          itemCount: tasks.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final doc = tasks[i], x = doc.data();
                            return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .08),
                                    borderRadius: BorderRadius.circular(16)),
                                child: Row(children: [
                                  const Icon(Icons.repeat_rounded,
                                      color: Color(0xFFFFB1C8)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text('${x['studentName'] ?? 'Öğrenci'}',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800)),
                                        Text(
                                            '${x['title'] ?? ''} • ${x['schedule'] ?? ''}',
                                            style: const TextStyle(
                                                color: Colors.white60,
                                                fontSize: 12))
                                      ])),
                                  PopupMenuButton<String>(
                                      iconColor: Colors.white70,
                                      onSelected: (v) async {
                                        if (v == 'cancel') {
                                          await doc.reference.update({
                                            'active': false,
                                            'updatedAt':
                                                FieldValue.serverTimestamp()
                                          });
                                        } else {
                                          await doc.reference.update({
                                            'schedule': v,
                                            'updatedAt':
                                                FieldValue.serverTimestamp()
                                          });
                                        }
                                      },
                                      itemBuilder: (_) => [
                                            ...[
                                              'Her Pazartesi',
                                              'Her Salı',
                                              'Her Çarşamba',
                                              'Her Perşembe',
                                              'Her Cuma',
                                              'Her Cumartesi',
                                              'Her Pazar'
                                            ].map((e) => PopupMenuItem(
                                                value: e, child: Text(e))),
                                            const PopupMenuDivider(),
                                            const PopupMenuItem(
                                                value: 'cancel',
                                                child: Text('Takibi İptal Et')),
                                          ])
                                ]));
                          });
                    },
                  ))
                ]))));
  }

  Widget _flowFilterButton(String value, String label, int count) {
    final selected = flowFilter == value;
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () => setState(() => flowFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFC75B82)
              : Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
              color: selected ? const Color(0xFFFFB1C8) : Colors.white24),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w600))),
          const SizedBox(width: 5),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: selected ? .22 : .10),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('$count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800))),
        ]),
      ),
    );
  }

  Widget _dailyStatusChip(String label, Object value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .32)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text('$value',
            style: TextStyle(color: color, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _appointmentDetailChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white70),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
    );
  }

  Future<void> _showOwnAvailabilityDialog(
    Map<String, dynamic> counselor,
  ) async {
    const days = <String, String>{
      'monday': 'Pazartesi',
      'tuesday': 'Salı',
      'wednesday': 'Çarşamba',
      'thursday': 'Perşembe',
      'friday': 'Cuma',
      'saturday': 'Cumartesi',
      'sunday': 'Pazar',
    };
    final raw =
        Map<String, dynamic>.from(counselor['guidanceAvailability'] ?? {});
    final weekly = Map<String, dynamic>.from(raw['weekly'] ?? {});
    final temp = <String, List<Map<String, String>>>{
      for (final key in days.keys)
        key: (weekly[key] as List? ?? const [])
            .whereType<Map>()
            .map(
              (slot) => {
                'start': '${slot['start'] ?? '09:00'}',
                'end': '${slot['end'] ?? '17:00'}',
              },
            )
            .toList(),
    };
    var slotMinutes = (raw['slotMinutes'] as num?)?.toInt() ?? 20;

    InputDecoration timeDecoration(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.09),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(
              color: Color(0xFFFFB1C8),
              width: 1.3,
            ),
          ),
        );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4A102B), Color(0xFF8B3155)],
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
                                tooltip: 'Saat aralığı ekle',
                                onPressed: () => setDialogState(() {
                                  temp[day.key]!.add({
                                    'start': '09:00',
                                    'end': '17:00',
                                  });
                                }),
                                icon: const Icon(
                                  Icons.add_circle,
                                  color: Color(0xFFFFB1C8),
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
                                padding: const EdgeInsets.only(top: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(
                                              left: 14,
                                              bottom: 6,
                                            ),
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
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                              LengthLimitingTextInputFormatter(
                                                4,
                                              ),
                                              _TimeTextFormatter(),
                                            ],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            decoration: timeDecoration('09:00'),
                                            onChanged: (value) =>
                                                slot['start'] = value,
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
                                              left: 14,
                                              bottom: 6,
                                            ),
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
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                              LengthLimitingTextInputFormatter(
                                                4,
                                              ),
                                              _TimeTextFormatter(),
                                            ],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            decoration: timeDecoration('17:00'),
                                            onChanged: (value) =>
                                                slot['end'] = value,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Saat aralığını sil',
                                      onPressed: () => setDialogState(
                                        () => temp[day.key]!.removeAt(index),
                                      ),
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      children: [
                        DropdownButtonFormField<int>(
                          initialValue: [15, 20, 30].contains(slotMinutes)
                              ? slotMinutes
                              : 20,
                          dropdownColor: const Color(0xFF4A1830),
                          iconEnabledColor: Colors.white70,
                          style: const TextStyle(color: Colors.white),
                          decoration: _guidanceDialogFieldDecoration(
                            'Veli görüşme süresi',
                          ),
                          items: const [15, 20, 30]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    '$value dakika',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setDialogState(
                            () => slotMinutes = value ?? 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Vazgeç'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            for (final day in days.entries) {
                              for (final slot in temp[day.key] ?? const []) {
                                if (!_isValidAvailabilityRange(
                                  slot['start'] ?? '',
                                  slot['end'] ?? '',
                                )) {
                                  ScaffoldMessenger.of(dialogContext)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${day.value} için saat aralığını kontrol edin.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                              }
                            }
                            try {
                              await functions
                                  .httpsCallable('saveGuidanceAvailability')
                                  .call({
                                'counselorId': auth.currentUser!.uid,
                                'guidanceAvailability': {
                                  'weekly': temp,
                                  'closedDates': const <String>[],
                                  'slotMinutes': slotMinutes,
                                },
                              });
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            } on FirebaseFunctionsException catch (error) {
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext)
                                    .showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      error.message ??
                                          'Çalışma saatleri kaydedilemedi.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFB1C8),
                            foregroundColor: const Color(0xFF4A1830),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Kaydet'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isValidAvailabilityRange(String rawStart, String rawEnd) {
    int asMinutes(String value) {
      final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value.trim());
      if (match == null) return -1;
      final hour = int.tryParse(match.group(1)!) ?? 24;
      final minute = int.tryParse(match.group(2)!) ?? 60;
      return hour > 23 || minute > 59 ? -1 : hour * 60 + minute;
    }

    final start = asMinutes(rawStart);
    final end = asMinutes(rawEnd);
    return start >= 0 && end > start;
  }

  Widget _myStudentsPanel(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> appointments,
  ) {
    final groups = groupGuidanceStudents(
      _studentsById.values,
      query: _studentSearch,
    );
    final uid = auth.currentUser!.uid;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('guidanceTasks')
          .where('counselorId', isEqualTo: uid)
          .snapshots(),
      builder: (context, taskSnap) {
        final activeTasks = <String, Map<String, dynamic>>{};
        for (final doc in taskSnap.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
          final data = doc.data();
          if (data['active'] != false) {
            final studentId = '${data['studentId'] ?? ''}';
            if (studentId.isNotEmpty) activeTasks[studentId] = data;
          }
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            onChanged: (value) => setState(() => _studentSearch = value),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Öğrenci veya sınıf ara',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withValues(alpha: .08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text('Size atanmış öğrenci bulunmuyor.',
                    style: TextStyle(color: Colors.white70)),
              ),
            ),
          ...groups.map((group) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                ),
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                    childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    iconColor: Colors.white70,
                    collapsedIconColor: Colors.white60,
                    title: Text(group.label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800)),
                    subtitle: Text('${group.students.length} öğrenci',
                        style: const TextStyle(color: Colors.white60)),
                    children: group.students.map((student) {
                      final studentId = student['_id']?.toString() ?? '';
                      final task = activeTasks[studentId];
                      final hasTask = task != null;
                      final taskTitle = '${task?['title'] ?? ''}'.trim();
                      final taskSchedule = '${task?['schedule'] ?? ''}'.trim();
                      final subtitle = hasTask
                          ? [
                              if (taskTitle.isNotEmpty) taskTitle,
                              if (taskSchedule.isNotEmpty) taskSchedule,
                            ].join(' • ')
                          : 'Henüz haftalık takip programı yok';

                      return ListTile(
                        onTap: () => _showStudentGuidanceDetail(
                          studentId,
                          student,
                          appointments,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: hasTask
                              ? const Color(0xFFFFB1C8)
                                  .withValues(alpha: .18)
                              : Colors.white10,
                          child: Icon(
                            hasTask
                                ? Icons.event_repeat_rounded
                                : Icons.person_outline_rounded,
                            color: hasTask
                                ? const Color(0xFFFFB1C8)
                                : Colors.white70,
                          ),
                        ),
                        title: Text(guidanceStudentName(student),
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hasTask
                                ? const Color(0xFFFFD7E4)
                                : Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: hasTask
                              ? 'Aktif haftalık takip mevcut'
                              : 'Haftalık Takip Ver',
                          icon: Icon(
                            hasTask
                                ? Icons.check_circle_rounded
                                : Icons.playlist_add_check_rounded,
                            color: hasTask
                                ? Colors.white38
                                : const Color(0xFFFFB1C8),
                          ),
                          onPressed: studentId.isEmpty || hasTask
                              ? null
                              : () => addWeeklyTask(
                                    initialStudentId: studentId,
                                    initialStudent: student,
                                  ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              )),
        ]);
      },
    );
  }

  Future<void> _showStudentGuidanceDetail(
    String studentId,
    Map<String, dynamic> student,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> appointments,
  ) async {
    final guardian = guidanceGuardianLabel(student);
    final classLabel = formatStudentClassDisplay(
      className: student['className'],
      branch: student['branch'],
      department: student['department'],
    );
    final upcoming = appointments.where((item) {
      final data = item.data();
      return data['studentId'] == studentId &&
          !_guidanceTerminalStatuses.contains(_guidanceStatus(data['status']));
    }).toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.of(dialogContext).size.height * .82,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4A102B), Color(0xFF7A2449)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .28),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB1C8).withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.person_rounded,
                        color: Color(0xFFFFB1C8)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(guidanceStudentName(student),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800)),
                        if (classLabel.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(classLabel,
                              style: const TextStyle(color: Colors.white70)),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                  ),
                ]),
                if (guardian.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _guidanceInfoRow(
                    Icons.family_restroom_rounded,
                    'Veli',
                    [
                      guardian,
                      '${student?['guardianPhone'] ?? ''}'.trim(),
                    ].where((value) => value.isNotEmpty).join(' • '),
                  ),
                ],
                const SizedBox(height: 10),
                _guidanceInfoRow(
                  Icons.event_rounded,
                  'Yaklaşan randevu',
                  upcoming.isEmpty
                      ? 'Planlanmış randevu yok'
                      : '${upcoming.length} randevu',
                ),
                if (upcoming.isNotEmpty)
                  ...upcoming.take(3).map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(left: 46, top: 5),
                          child: Text(
                            '${item.data()['dayLabel'] ?? ''} • ${item.data()['time'] ?? ''}',
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12),
                          ),
                        ),
                      ),
                const SizedBox(height: 10),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: db
                      .collection('guidanceTasks')
                      .where('counselorId', isEqualTo: auth.currentUser!.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final tasks = (snapshot.data?.docs ?? const [])
                        .where((item) =>
                            item.data()['studentId'] == studentId &&
                            item.data()['active'] != false)
                        .toList();
                    final task = tasks.isEmpty ? null : tasks.first.data();
                    final hasTask = task != null;
                    final taskTitle = '${task?['title'] ?? ''}'.trim();
                    final taskSchedule = '${task?['schedule'] ?? ''}'.trim();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _guidanceInfoRow(
                          Icons.repeat_rounded,
                          'Haftalık takip',
                          hasTask
                              ? [
                                  if (taskTitle.isNotEmpty) taskTitle,
                                  if (taskSchedule.isNotEmpty) taskSchedule,
                                ].join(' • ')
                              : 'Henüz program oluşturulmamış',
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: hasTask
                                  ? Colors.white12
                                  : const Color(0xFFFFB1C8),
                              foregroundColor: hasTask
                                  ? Colors.white38
                                  : const Color(0xFF4A102B),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                            onPressed: studentId.isEmpty || hasTask
                                ? null
                                : () {
                                    Navigator.pop(dialogContext);
                                    addWeeklyTask(
                                      initialStudentId: studentId,
                                      initialStudent: student,
                                    );
                                  },
                            icon: Icon(hasTask
                                ? Icons.check_circle_rounded
                                : Icons.playlist_add_check_rounded),
                            label: Text(
                              hasTask
                                  ? 'Aktif Takip Programı Var'
                                  : 'Haftalık Takip Ver',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _guidanceInfoRow(IconData icon, String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFFFB1C8).withValues(alpha: .12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFFFFB1C8)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ]),
    );
  }

  Future<bool> _confirmLogout() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF4A1830),
                borderRadius: BorderRadius.circular(26),
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
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: Colors.redAccent,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Çıkış Yap',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Rehberlik oturumunuzu kapatmak istiyor musunuz?',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.35),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Vazgeç'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Çıkış Yap'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
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
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser!.uid;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.collection('users').doc(uid).snapshots(),
        builder: (context, userSnap) {
          final name =
              '${userSnap.data?.data()?['fullName'] ?? 'Rehberlik Servisi'}';
          return Scaffold(
            backgroundColor: const Color(0xFF4A1830),
            appBar: AppBar(
                elevation: 0,
                backgroundColor: const Color(0xFF6B2143),
                foregroundColor: Colors.white,
                title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const Text('Rehberlik Servisi',
                          style: TextStyle(fontSize: 11, color: Colors.white60))
                    ]),
                actions: [
                  IconButton(
                      tooltip: 'Çıkış Yap',
                      onPressed: () async {
                        if (await _confirmLogout()) await auth.signOut();
                      },
                      icon: const Icon(Icons.logout_rounded))
                ]),
            body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db
                    .collection('guidanceAppointments')
                    .where('counselorId', isEqualTo: uid)
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data!.docs.toList()
                    ..sort((a, b) {
                      final at = a.data()['createdAt'] as Timestamp?;
                      final bt = b.data()['createdAt'] as Timestamp?;
                      return (bt?.millisecondsSinceEpoch ?? 0)
                          .compareTo(at?.millisecondsSinceEpoch ?? 0);
                    });
                  final active = docs
                      .where((d) => !_guidanceTerminalStatuses.contains(
                          _guidanceStatus(d.data()['status'] as String?)))
                      .length;
                  final today = docs.where((d) {
                    final x = d.data();
                    return _isGuidanceToday(x) &&
                        !_guidanceTerminalStatuses
                            .contains(_guidanceStatus(x['status'] as String?));
                  }).toList();
                  final upcoming = docs.where((d) {
                    final x = d.data();
                    return !_isGuidanceToday(x) &&
                        !_guidanceTerminalStatuses
                            .contains(_guidanceStatus(x['status'] as String?));
                  }).toList();
                  today.sort((a, b) => guidanceTimeSortValue(a.data()['time'])
                      .compareTo(guidanceTimeSortValue(b.data()['time'])));
                  final finished = docs
                      .where((d) => _guidanceTerminalStatuses.contains(
                          _guidanceStatus(d.data()['status'] as String?)))
                      .toList();
                  final current = today.where((d) =>
                      _guidanceStatus(d.data()['status'] as String?) ==
                      'in_progress');
                  final waiting = today.where((d) {
                    final status =
                        _guidanceStatus(d.data()['status'] as String?);
                    return status == 'pending' || status == 'approved';
                  });
                  final next = today.where((d) =>
                      _guidanceStatus(d.data()['status'] as String?) !=
                      'in_progress');
                  final completedToday = finished.where(
                    (d) =>
                        _isGuidanceToday(d.data()) &&
                        _guidanceStatus(d.data()['status'] as String?) ==
                            'completed',
                  );
                  final visible = flowFilter == 'today'
                      ? today
                      : flowFilter == 'upcoming'
                          ? upcoming
                          : finished;
                  return ListView(padding: const EdgeInsets.all(16), children: [
                    Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [Color(0xFF6A1B3D), Color(0xFFB54C72)]),
                            borderRadius: BorderRadius.circular(26)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Bugünün Rehberlik Akışı',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 5),
                              Text(
                                  '${docs.length} kayıt • $active aktif görüşme/talep',
                                  style:
                                      const TextStyle(color: Colors.white70)),
                              const SizedBox(height: 14),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(
                                            color: Colors.white54)),
                                    onPressed: () => _showOwnAvailabilityDialog(
                                      userSnap.data?.data() ?? const {},
                                    ),
                                    icon: const Icon(
                                        Icons.event_available_rounded),
                                    label: const Text('Çalışma Programı')),
                                OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(
                                            color: Colors.white54)),
                                    onPressed: _showStudentAssignmentDialog,
                                    icon: const Icon(Icons.group_add_rounded),
                                    label: const Text('Öğrenci Ata')),
                                OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(
                                            color: Colors.white54)),
                                    onPressed: addWeeklyTask,
                                    icon: const Icon(Icons.repeat_rounded),
                                    label: const Text('Haftalık Takip Ver')),
                                OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(
                                            color: Colors.white54)),
                                    onPressed: manageWeeklyTasks,
                                    icon: const Icon(
                                        Icons.manage_history_rounded),
                                    label: const Text('Takipleri Yönet')),
                                OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(
                                            color: Colors.white54)),
                                    onPressed: _showClassActivitySummary,
                                    icon: const Icon(
                                        Icons.picture_as_pdf_rounded),
                                    label: const Text('Faaliyet Özeti')),
                              ])
                            ])),
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _dailyStatusChip('Şu An', current.length, Colors.orange),
                      _dailyStatusChip(
                          'Sıradaki',
                          next.isEmpty
                              ? '-'
                              : '${next.first.data()['time'] ?? '-'}',
                          Colors.lightBlueAccent),
                      _dailyStatusChip(
                          'Bekleyen', waiting.length, Colors.tealAccent),
                      _dailyStatusChip('Tamamlanan', completedToday.length,
                          Colors.greenAccent),
                    ]),
                    const SizedBox(height: 14),
                    Wrap(spacing: 7, runSpacing: 7, children: [
                      SizedBox(
                          width: 112,
                          child: _flowFilterButton(
                              'today', 'Bugün', today.length)),
                      SizedBox(
                          width: 112,
                          child: _flowFilterButton(
                              'upcoming', 'Yaklaşan', upcoming.length)),
                      SizedBox(
                          width: 112,
                          child: _flowFilterButton(
                              'finished', 'Geçmiş', finished.length)),
                      SizedBox(
                          width: 128,
                          child: _flowFilterButton('students', 'Öğrencilerim',
                              _studentsById.length)),
                    ]),
                    const SizedBox(height: 16),
                    if (flowFilter == 'students')
                      _myStudentsPanel(docs)
                    else if (visible.isEmpty)
                      Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .06),
                              borderRadius: BorderRadius.circular(20)),
                          child: const Center(
                              child: Text('Henüz randevu veya görüşme yok.',
                                  style: TextStyle(color: Colors.white70)))),
                    if (flowFilter != 'students')
                      ...visible.map((doc) {
                        final x = doc.data();
                        final s = _guidanceStatus(x['status'] as String?);
                        final col = statusColor(s);
                        final student =
                            _studentsById['${x['studentId'] ?? ''}'];
                        final classLabel = student == null
                            ? ''
                            : formatStudentClassDisplay(
                                className: student['className'],
                                branch: student['branch'],
                                department: student['department'],
                              );
                        final guardian = guidanceGuardianLabel(student);
                        final participant = guidanceParticipantLabel(x);
                        return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  Color(0xFF48152C),
                                  Color(0xFF70213F)
                                ]),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white12)),
                            child: Padding(
                                padding: const EdgeInsets.all(15),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        CircleAvatar(
                                            backgroundColor:
                                                col.withValues(alpha: .12),
                                            child: Icon(Icons.person_rounded,
                                                color: col)),
                                        const SizedBox(width: 10),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Text(
                                                  '${x['studentName'] ?? 'Öğrenci'}',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 16)),
                                              Text(
                                                  '${x['dayLabel'] ?? ''} • ${x['time'] ?? ''} • ${x['reason'] ?? ''}',
                                                  style: const TextStyle(
                                                      color: Colors.white60,
                                                      fontSize: 12))
                                            ])),
                                        Chip(
                                            label: Text(statusLabel(s)),
                                            backgroundColor:
                                                col.withValues(alpha: .10),
                                            labelStyle: TextStyle(
                                                color: col,
                                                fontWeight: FontWeight.w700))
                                      ]),
                                      if (classLabel.isNotEmpty ||
                                          participant.isNotEmpty ||
                                          guardian.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 10),
                                          child: Wrap(
                                              spacing: 7,
                                              runSpacing: 6,
                                              children: [
                                                if (classLabel.isNotEmpty)
                                                  _appointmentDetailChip(
                                                    Icons.school_rounded,
                                                    classLabel,
                                                  ),
                                                if (participant.isNotEmpty)
                                                  _appointmentDetailChip(
                                                    Icons.groups_rounded,
                                                    participant,
                                                  ),
                                                if (guardian.isNotEmpty)
                                                  _appointmentDetailChip(
                                                    Icons
                                                        .family_restroom_rounded,
                                                    'Veli: ${[
                                                      guardian,
                                                      '${student?['guardianPhone'] ?? ''}'.trim(),
                                                    ].where((value) => value.isNotEmpty).join(' • ')}',
                                                  ),
                                              ]),
                                        ),
                                      if (!_guidanceTerminalStatuses
                                          .contains(s)) ...[
                                        const Divider(height: 22),
                                        Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              if (s == 'pending')
                                                FilledButton(
                                                    onPressed: () =>
                                                        changeStatus(doc.id, s,
                                                            'approved'),
                                                    child: const Text('Geldi')),
                                              if (s == 'approved')
                                                FilledButton(
                                                    onPressed: () async {
                                                      final planned =
                                                          '${x['dayLabel'] ?? ''}';
                                                      if (planned != 'Bugün' &&
                                                          !_isGuidanceToday(
                                                              x)) {
                                                        final ok = await showDialog<
                                                                bool>(
                                                            context: context,
                                                            builder: (dctx) =>
                                                                AlertDialog(
                                                                    title: const Text(
                                                                        'Planlanan günden önce başlat'),
                                                                    content: Text(
                                                                        'Bu görüşme $planned için planlandı. Yine de şimdi başlatmak istiyor musunuz?'),
                                                                    actions: [
                                                                      TextButton(
                                                                          onPressed: () => Navigator.pop(
                                                                              dctx,
                                                                              false),
                                                                          child:
                                                                              const Text('Vazgeç')),
                                                                      FilledButton(
                                                                          onPressed: () => Navigator.pop(
                                                                              dctx,
                                                                              true),
                                                                          child:
                                                                              const Text('Evet, Başlat'))
                                                                    ]));
                                                        if (ok != true) return;
                                                      }
                                                      await changeStatus(doc.id,
                                                          s, 'in_progress');
                                                    },
                                                    child: const Text(
                                                        'Görüşmeyi Başlat')),
                                              if (s == 'in_progress')
                                                FilledButton(
                                                    onPressed: () =>
                                                        changeStatus(doc.id, s,
                                                            'completed'),
                                                    child: const Text(
                                                        'Görüşmeyi Tamamla')),
                                              OutlinedButton(
                                                  onPressed: s == 'in_progress'
                                                      ? null
                                                      : () async {
                                                          final ok = await showDialog<
                                                                  bool>(
                                                              context: context,
                                                              builder: (dctx) =>
                                                                  AlertDialog(
                                                                      title: const Text(
                                                                          'Randevuyu iptal et'),
                                                                      content:
                                                                          const Text(
                                                                              'Bu randevu iptal edilecek. Devam edilsin mi?'),
                                                                      actions: [
                                                                        TextButton(
                                                                            onPressed: () => Navigator.pop(dctx,
                                                                                false),
                                                                            child:
                                                                                const Text('Vazgeç')),
                                                                        FilledButton(
                                                                            onPressed: () => Navigator.pop(dctx,
                                                                                true),
                                                                            child:
                                                                                const Text('İptal Et'))
                                                                      ]));
                                                          if (ok == true) {
                                                            await changeStatus(
                                                                doc.id,
                                                                s,
                                                                'cancelled');
                                                          }
                                                        },
                                                  child:
                                                      const Text('İptal Et')),
                                              OutlinedButton(
                                                  onPressed: s == 'in_progress'
                                                      ? null
                                                      : () => changeStatus(
                                                          doc.id, s, 'no_show'),
                                                  child: const Text('Gelmedi'))
                                            ])
                                      ]
                                    ])));
                      })
                  ]);
                }),
          );
        });
  }
}

class _TimeTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 4) digits = digits.substring(0, 4);
    final text = digits.length > 2
        ? '${digits.substring(0, 2)}:${digits.substring(2)}'
        : digits;
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

class _GuidanceClassOption {
  const _GuidanceClassOption({
    required this.className,
    required this.branch,
    required this.department,
  });

  final String className;
  final String branch;
  final String department;

  String get key => '$className\u0000$branch\u0000$department';
  String get displayName => formatStudentClassDisplay(
        className: className,
        branch: branch,
        department: department,
      );
  String get filePrefix => '$className-$branch'
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^\w\-.]+'), '');
}

class _GuidanceSummaryRequest {
  const _GuidanceSummaryRequest(this.classOption);

  final _GuidanceClassOption classOption;
}
