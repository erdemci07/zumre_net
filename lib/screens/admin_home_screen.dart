import 'dart:convert';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;


class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    StatisticsPage(),
    UserManagementPage(),
  ];

  final List<String> _titles = const [
    'Dashboard',
    'Kullanıcılar',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0E3A8A),
              Color(0xFF1E63D6),
              Color(0xFF08204D),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAdminHeader(),
              Expanded(child: _pages[_selectedIndex]),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildAdminHeader() {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'admin';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.20),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.admin_panel_settings,
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
                    'ZümreNet Yönetici Paneli',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _titles[_selectedIndex],
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Çıkış Yap',
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
              icon: const Icon(Icons.logout, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF071A3A).withOpacity(0.92),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(
          children: [
            _navItem(
              index: 0,
              icon: Icons.dashboard_rounded,
              label: 'Dashboard',
            ),
            _navItem(
              index: 1,
              icon: Icons.people_alt_rounded,
              label: 'Kullanıcılar',
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = _selectedIndex == index;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          setState(() => _selectedIndex = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color:
                selected ? Colors.white.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : Colors.white54,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== 1. İSTATİSTİK SAYFASI ====================

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});
  

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, int> _subjectStats = {};
  Map<String, Map<String, int>> _dailySubjectStats = {};
  Map<String, int> _dailyStats = {};

  int _totalSolvedToday = 0;
  int _totalSolvedAll = 0;
  bool _isLoading = true;
  bool _isImporting = false;
  final List<Map<String, String>> _weekdaySlots = [];
final List<Map<String, String>> _weekendSlots = [];

String _lunchStart = '12:20';
String _lunchEnd = '13:00';

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  String _dateKey(DateTime date) {
    return '${date.day}/${date.month}';
  }
  void _showPdfLoadingDialog() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: const [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(),
          ),
          SizedBox(width: 18),
          Expanded(
            child: Text(
              'PDF raporu hazırlanıyor...\n'
              'Veri yoğunluğuna bağlı olarak bu işlem birkaç saniye sürebilir.',
            ),
          ),
        ],
      ),
    ),
  );
}
void _hidePdfLoadingDialog() {
  if (Navigator.canPop(context)) {
    Navigator.pop(context);
  }
}

Future<void> _showPdfReportDialog() async {
  DateTime? startDate;
  DateTime? endDate;

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('PDF Rapor Oluştur'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.today),
                    label: const Text('Bugünün Raporu'),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _generateDailyPdfReport();
                    },
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: const Text('Başlangıç Tarihi Seç'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      locale: const Locale('tr', 'TR'),
                      context: context,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                      initialDate: startDate ?? DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() => startDate = picked);
                    }
                  },
                ),
                if (startDate != null)
                  Text('Başlangıç: ${startDate!.day}.${startDate!.month}.${startDate!.year}'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: const Text('Bitiş Tarihi Seç'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      locale: const Locale('tr', 'TR'),
                      context: context,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                      initialDate: endDate ?? startDate ?? DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() => endDate = picked);
                    }
                  },
                ),
                if (endDate != null)
                  Text('Bitiş: ${endDate!.day}.${endDate!.month}.${endDate!.year}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: startDate == null || endDate == null
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        await _generatePdfReportForRange(
                          startDate: startDate!,
                          endDate: endDate!,
                        );
                      },
                child: const Text('Tarih Aralığı Raporu'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _generateDailyPdfReport() async {
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayEnd = todayStart.add(const Duration(days: 1));

  await _generatePdfReport(
    startDate: todayStart,
    endDateExclusive: todayEnd,
    fileNamePrefix: 'ZumreNet_Gunluk_Rapor',
  );
}

Future<void> _generatePdfReportForRange({
  required DateTime startDate,
  required DateTime endDate,
}) async {
  final start = DateTime(startDate.year, startDate.month, startDate.day);
  final endExclusive = DateTime(endDate.year, endDate.month, endDate.day)
      .add(const Duration(days: 1));

  await _generatePdfReport(
    startDate: start,
    endDateExclusive: endExclusive,
    fileNamePrefix: 'ZumreNet_Tarih_Araligi_Raporu',
  );
}

Future<void> _generatePdfReport({
  required DateTime startDate,
  required DateTime endDateExclusive,
  required String fileNamePrefix,
}) async {
  _showPdfLoadingDialog();
  final regularFont = await PdfGoogleFonts.notoSansRegular();
  final boldFont = await PdfGoogleFonts.notoSansBold();

  final snapshot = await _firestore
      .collection('queues')
      .where('status', isEqualTo: 'completed')
      .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
      .where('completedAt', isLessThan: Timestamp.fromDate(endDateExclusive))
      .get();

  final Map<String, Map<String, dynamic>> studentMap = {};
  final Map<String, int> subjectTotals = {};
  final Set<String> teacherIds = {};
  final List<Map<String, dynamic>> historyRows = [];

  String formatDate(DateTime date) {
    const months = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String shortDateTime(dynamic timestamp) {
    if (timestamp is! Timestamp) return '-';
    final d = timestamp.toDate();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  for (final doc in snapshot.docs) {
    final data = doc.data();

    final studentName = data['studentName'] ?? 'Öğrenci';
    final studentId = '${data['studentId'] ?? studentName}';
    final teacherName = data['teacherName'] ?? '-';
    final teacherId = data['teacherId'];
    final subject = data['subject'] ?? 'Bilinmeyen';
    final completedAt = data['completedAt'];

    final questionCount =
        data['questionCount'] is num ? (data['questionCount'] as num).toInt() : 1;

    if (teacherId != null) teacherIds.add('$teacherId');

    final studentDoc = await _firestore.collection('users').doc(studentId).get();
    final studentData = studentDoc.data() ?? {};

    studentMap.putIfAbsent(studentId, () {
      return {
        'studentName': studentName,
        'className': studentData['className'] ?? data['className'] ?? '',
        'branch': studentData['branch'] ?? data['branch'] ?? '',
        'department': studentData['department'] ?? data['department'] ?? '',
        'subjects': <String, int>{},
        'total': 0,
        'lastTeacher': '',
        'lastCompleted': null,
      };
    });

    final subjects = studentMap[studentId]!['subjects'] as Map<String, int>;
    subjects[subject] = (subjects[subject] ?? 0) + questionCount;

    studentMap[studentId]!['total'] =
        (studentMap[studentId]!['total'] ?? 0) + questionCount;
    studentMap[studentId]!['lastTeacher'] = teacherName;
    studentMap[studentId]!['lastCompleted'] = completedAt;

    subjectTotals[subject] = (subjectTotals[subject] ?? 0) + questionCount;

    historyRows.add({
      'completedAt': completedAt,
      'studentName': studentName,
      'teacherName': teacherName,
      'subject': subject,
      'questionCount': questionCount,
    });
  }

  historyRows.sort((a, b) {
    final at = a['completedAt'];
    final bt = b['completedAt'];
    if (at is! Timestamp && bt is! Timestamp) return 0;
    if (at is! Timestamp) return 1;
    if (bt is! Timestamp) return -1;
    return at.toDate().compareTo(bt.toDate());
  });

  final totalQuestions = subjectTotals.values.fold<int>(0, (a, b) => a + b);
  final average = studentMap.isEmpty ? 0 : totalQuestions / studentMap.length;

  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
  );

  final endVisible = endDateExclusive.subtract(const Duration(days: 1));
  final dateTitle = startDate.year == endVisible.year &&
          startDate.month == endVisible.month &&
          startDate.day == endVisible.day
      ? formatDate(startDate)
      : '${formatDate(startDate)} - ${formatDate(endVisible)}';

  pw.Widget statBox(String title, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey50,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.blueGrey200),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(title, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  pw.Widget subjectBar(String subject, int value) {
    final max = subjectTotals.values.isEmpty
        ? 1
        : subjectTotals.values.reduce((a, b) => a > b ? a : b);
    final percent = max == 0 ? 0.0 : value / max;

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Row(
        children: [
          pw.SizedBox(width: 85, child: pw.Text(subject, style: const pw.TextStyle(fontSize: 9))),
          pw.Expanded(
  child: pw.LayoutBuilder(
    builder: (context, constraints) {
      return pw.Container(
        height: 9,
        color: PdfColors.blueGrey100,
        child: pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Container(
            width: constraints!.maxWidth * percent,
            height: 9,
            color: PdfColors.blue700,
          ),
        ),
      );
    },
  ),
),
          pw.SizedBox(width: 8),
          pw.Text('$value', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  final fileName =
      '${fileNamePrefix}_${startDate.year}_${startDate.month}_${startDate.day}.pdf';

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(18),
          decoration: pw.BoxDecoration(
            color: PdfColors.blue900,
            borderRadius: pw.BorderRadius.circular(14),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('ZümreNet',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 26,
                    fontWeight: pw.FontWeight.bold,
                  )),
              pw.SizedBox(height: 4),
              pw.Text('Kullanım Analiz Raporu',
                  style: const pw.TextStyle(color: PdfColors.white, fontSize: 15)),
              pw.SizedBox(height: 10),
              pw.Text(dateTitle,
                  style: pw.TextStyle(
                    color: PdfColors.greenAccent100,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  )),
            ],
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Row(
          children: [
            pw.Expanded(child: statBox('Öğrenci', '${studentMap.length}')),
            pw.SizedBox(width: 8),
            pw.Expanded(child: statBox('Öğretmen', '${teacherIds.length}')),
            pw.SizedBox(width: 8),
            pw.Expanded(child: statBox('Çözülen Soru', '$totalQuestions')),
            pw.SizedBox(width: 8),
            pw.Expanded(child: statBox('Aktif Zümre', '${subjectTotals.length}')),
            pw.SizedBox(width: 8),
            pw.Expanded(child: statBox('Ort. Soru', average.toStringAsFixed(1))),
          ],
        ),
        pw.SizedBox(height: 22),
        pw.Text('Ders / Zümre Dağılımı',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        if (subjectTotals.isEmpty)
          pw.Text('Bu tarih aralığında çözülen soru bulunamadı.')
        else
          ...subjectTotals.entries.map((e) => subjectBar(e.key, e.value)),
        pw.SizedBox(height: 22),
        pw.Text('Öğrenci Kullanım Özeti',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Table.fromTextArray(
          headers: ['Öğrenci', 'Sınıf', 'Alan', 'Toplam', 'Son İşlem', 'Son Öğretmen'],
          data: studentMap.values.map((student) {
            final classText =
                '${student['className']}${student['branch'] != '' ? '-${student['branch']}' : ''}';
            return [
              student['studentName'],
              classText,
              student['department'],
              '${student['total']}',
              shortDateTime(student['lastCompleted']),
              student['lastTeacher'],
            ];
          }).toList(),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          cellPadding: const pw.EdgeInsets.all(5),
        ),
        pw.SizedBox(height: 22),
        pw.Text('İşlem Geçmişi',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Table.fromTextArray(
          headers: ['Tarih/Saat', 'Öğrenci', 'Öğretmen', 'Ders', 'Soru'],
          data: historyRows.map((row) {
            return [
              shortDateTime(row['completedAt']),
              row['studentName'],
              row['teacherName'],
              row['subject'],
              '${row['questionCount']}',
            ];
          }).toList(),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
          cellStyle: const pw.TextStyle(fontSize: 7),
          cellPadding: const pw.EdgeInsets.all(4),
        ),
      ],
    ),
  );
  _hidePdfLoadingDialog();

  await Printing.sharePdf(
    bytes: await pdf.save(),
    filename: fileName,
  );
}

  Future<void> _loadStats() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final last7DaysStart = todayStart.subtract(const Duration(days: 6));

      final snapshot = await _firestore
          .collection('queues')
          .where('status', isEqualTo: 'completed')
          .get();

      final Map<String, int> subjectCount = {};
      final Map<String, int> dailyCount = {};
      final Map<String, Map<String, int>> dailySubjectCount = {};

      for (int i = 6; i >= 0; i--) {
        final day = todayStart.subtract(Duration(days: i));
        dailyCount[_dateKey(day)] = 0;
        dailySubjectCount[_dateKey(day)] = {};
      }

      int todayCount = 0;
      int allCount = 0;

      for (final doc in snapshot.docs) {
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

        if (completedDate
            .isAfter(last7DaysStart.subtract(const Duration(seconds: 1)))) {
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

      if (!mounted) return;

      setState(() {
        _subjectStats = subjectCount;
        _dailyStats = dailyCount;
        _totalSolvedToday = todayCount;
        _totalSolvedAll = allCount;
        _dailySubjectStats = dailySubjectCount;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İstatistik yüklenemedi: $e')),
      );
    }
  }

  Future<void> _pickEdesisFile(String type) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'xls', 'xlsx'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) return;

      final file = result.files.single;
      final fileBase64 = base64Encode(file.bytes!);

      if (!mounted) return;

      setState(() => _isImporting = true);

      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final analyzeCallable = functions.httpsCallable('analyzeEdesisFile');
      
      

      final analyzeResult = await analyzeCallable.call({
        'fileBase64': fileBase64,
        'fileName': file.name,
        'type': type,
      });

      final analyzeData = Map<String, dynamic>.from(analyzeResult.data);

      if (!mounted) return;

      setState(() => _isImporting = false);

      final confirm = await _showImportAnalysisDialog(
        type: type,
        data: analyzeData,
      );

      if (confirm != true) return;

      if (!mounted) return;
      setState(() => _isImporting = true);

      final importCallable = functions.httpsCallable('importEdesisFile');

      final importResult = await importCallable.call({
        'fileBase64': fileBase64,
        'fileName': file.name,
        'type': type,
      });

      final importData = Map<String, dynamic>.from(importResult.data);
      final summary =
          Map<String, dynamic>.from(importData['importSummary'] ?? {});

      if (!mounted) return;

      setState(() => _isImporting = false);

      await _showImportResultDialog(
        importData: importData,
        summary: summary,
      );

      await _loadStats();
    } catch (e) {
      if (!mounted) return;

      setState(() => _isImporting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Aktarım hatası: $e')),
      );
    }
  }

  Future<bool?> _showImportAnalysisDialog({
    required String type,
    required Map<String, dynamic> data,
  }) {
    final preview = List.from(data['preview'] ?? []);
    final ignored = List.from(data['ignoredHeaders'] ?? []);
    final missing = List.from(data['missingFields'] ?? []);
    final invalidPreview = List.from(data['invalidPreview'] ?? []);

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF071A3A),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white24),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        type == 'student'
                            ? Icons.school_rounded
                            : Icons.badge_rounded,
                        color: type == 'student'
                            ? Colors.orangeAccent
                            : Colors.greenAccent,
                        size: 34,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          type == 'student'
                              ? 'Öğrenci Dosyası Analizi'
                              : 'Öğretmen Dosyası Analizi',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _analysisLine('Dosya', '${data['fileName']}'),
                  _analysisLine('Toplam satır', '${data['totalRows'] ?? 0}'),
                  _analysisLine('Geçerli kayıt', '${data['validCount'] ?? 0}'),
                  _analysisLine('Hatalı kayıt', '${data['invalidCount'] ?? 0}'),
                  _analysisLine('Yok sayılan sütun', '${ignored.length}'),
                  if (ignored.isNotEmpty) ...[
  const SizedBox(height: 8),
  const Text(
    'Yok sayılan başlıklar',
    style: TextStyle(
      color: Colors.orangeAccent,
      fontWeight: FontWeight.bold,
    ),
  ),
  const SizedBox(height: 6),
  Text(
    ignored.map((e) {
      final item = Map<String, dynamic>.from(e);
      return item['original'].toString();
    }).join(', '),
    style: const TextStyle(color: Colors.white70),
  ),
],
                  if (missing.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Eksik zorunlu alanlar',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      missing.join(', '),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Önizleme',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (preview.isEmpty)
                    const Text(
                      'Önizleme için geçerli kayıt yok.',
                      style: TextStyle(color: Colors.white60),
                    )
                  else
                    ...preview.take(6).map((item) {
                      final row = Map<String, dynamic>.from(item);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
type == 'student'
    ? '${row['fullName']} • ${row['className']}-${row['branch']} • ${row['department'] ?? ''} • ${row['username']}'
    : '${row['fullName']} • ${(row['subjects'] is List && row['subjects'].isNotEmpty) ? row['subjects'].join(', ') : 'Branş yok'} • ${row['username']}',                          style: const TextStyle(color: Colors.white70),
                        ),
                      );
                    }),
                  if (invalidPreview.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'İlk hatalı satırlar',
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...invalidPreview.take(4).map((item) {
                      final row = Map<String, dynamic>.from(item);
                      final errors = List.from(row['errors'] ?? []);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Satır ${row['rowNumber']}: ${errors.join(', ')}',
                          style: const TextStyle(color: Colors.white60),
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
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
                          onPressed: data['ok'] == true
                              ? () => Navigator.pop(ctx, true)
                              : null,
                          child: const Text('Firebase’e Aktar'),
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
  }

  Widget _analysisLine(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white60),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportResultDialog({
    required Map<String, dynamic> importData,
    required Map<String, dynamic> summary,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aktarım Tamamlandı'),
        content: Text(
          'Toplam geçerli: ${summary['totalValid'] ?? 0}\n'
          'Yeni oluşturulan: ${summary['created'] ?? 0}\n'
          'Güncellenen: ${summary['updated'] ?? 0}\n'
          'Başarısız: ${summary['failed'] ?? 0}\n'
          'Hatalı satır: ${importData['invalidCount'] ?? 0}',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadStats,
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _adminStatCard(
                            title: 'Bugün',
                            value: '$_totalSolvedToday',
                            subtitle: 'çözülen soru',
                            icon: Icons.today_rounded,
                            color: Colors.greenAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _adminStatCard(
                            title: 'Toplam',
                            value: '$_totalSolvedAll',
                            subtitle: 'tüm çözümler',
                            icon: Icons.done_all_rounded,
                            color: Colors.lightBlueAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle('Son 7 Günlük Çözüm Grafiği'),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: _adminGlassDecoration(),
                      child: SizedBox(
                        height: 310,
                        child: _DailySolvedBarChart(
                          data: _dailyStats,
                          subjectData: _dailySubjectStats,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('Bugünkü Ders Dağılımı'),
                    const SizedBox(height: 10),
                    if (_subjectStats.isEmpty)
                      _adminInfoCard(
                        icon: Icons.info_outline,
                        title: 'Bugün henüz çözülen soru yok',
                        subtitle:
                            'Sorular çözüldükçe ders bazlı dağılım burada görünecek.',
                      )
                    else
                      ..._subjectStats.entries.map(
                        (entry) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: _adminGlassDecoration(),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.menu_book_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Text(
                                '${entry.value} soru',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    _sectionTitle('Veri Merkezi'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _quickActionCard(
                            icon: Icons.school_rounded,
                            title: 'Öğrenci Aktar',
                            subtitle: 'Edesis Öğrenci Excel dosyası',
                            color: Colors.orangeAccent,
                            onTap: () => _pickEdesisFile('student'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _quickActionCard(
                            icon: Icons.badge_rounded,
                            title: 'Öğretmen Aktar',
                            subtitle: 'Edesis Öğretmen Excel dosyası',
                            color: Colors.greenAccent,
                            onTap: () => _pickEdesisFile('teacher'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _quickActionCard(
  icon: Icons.picture_as_pdf_rounded,
  title: 'PDF Rapor Oluştur',
  subtitle: 'Bugün veya tarih aralığı',
  color: Colors.redAccent,
  onTap: _showPdfReportDialog,
),  
                                        const SizedBox(height: 12),
                    _quickActionCard(
                      icon: Icons.schedule_rounded,
                      title: 'Zümre Saatleri',
                      subtitle: 'Hafta içi, hafta sonu ve öğle arası',
                      color: Colors.purpleAccent,
                      onTap: _showZumreScheduleDialog,
                    ),
                  ],
                ),         
        ),
        if (_isImporting)
          Container(
            color: Colors.black.withOpacity(0.45),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }

  BoxDecoration _adminGlassDecoration() {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.10),
      borderRadius: BorderRadius.circular(24),
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

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 19,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _adminStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _adminGlassDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _adminInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _adminGlassDecoration(),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
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
  Future<void> _showZumreScheduleDialog() async {
  final doc = await _firestore.collection('settings').doc('zumreSchedule').get();

  _weekdaySlots.clear();
  _weekendSlots.clear();

  if (doc.exists) {
    final data = doc.data() ?? {};
    final weekday = List.from(data['weekdaySlots'] ?? []);
    final weekend = List.from(data['weekendSlots'] ?? []);
    final lunch = Map<String, dynamic>.from(data['lunchBreak'] ?? {});

    _weekdaySlots.addAll(
      weekday.map((e) => {'start': '${e['start']}', 'end': '${e['end']}'}),
    );

    _weekendSlots.addAll(
      weekend.map((e) => {'start': '${e['start']}', 'end': '${e['end']}'}),
    );

    _lunchStart = lunch['start'] ?? '12:20';
    _lunchEnd = lunch['end'] ?? '13:00';
  }

  if (!mounted) return;

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
                color: const Color(0xFF071A3A),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white24),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Zümre Saatleri Ayarı',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Öğrenci sıra alma ve öğretmen öğrenci ekleme bu saatlere göre çalışır.',
                      style: TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 20),
                    _scheduleSection(
                      title: 'Hafta İçi Zümre Saatleri',
                      slots: _weekdaySlots,
                      color: Colors.greenAccent,
                      onAdd: () {
                        setDialogState(() {
                          _weekdaySlots.add({'start': '10:40', 'end': '11:20'});
                        });
                      },
                      onDelete: (index) {
                        setDialogState(() => _weekdaySlots.removeAt(index));
                      },
                    ),
                    const SizedBox(height: 16),
                    _scheduleSection(
                      title: 'Hafta Sonu Zümre Saatleri',
                      slots: _weekendSlots,
                      color: Colors.orangeAccent,
                      onAdd: () {
                        setDialogState(() {
                          _weekendSlots.add({'start': '13:00', 'end': '14:00'});
                        });
                      },
                      onDelete: (index) {
                        setDialogState(() => _weekendSlots.removeAt(index));
                      },
                    ),
                    const SizedBox(height: 16),
                    _lunchSection(),
                    const SizedBox(height: 22),
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
                              await _firestore
                                  .collection('settings')
                                  .doc('zumreSchedule')
                                  .set({
                                'weekdaySlots': _weekdaySlots,
                                'weekendSlots': _weekendSlots,
                                'lunchBreak': {
                                  'start': _lunchStart,
                                  'end': _lunchEnd,
                                },
                                'updatedAt': FieldValue.serverTimestamp(),
                              });

                              if (ctx.mounted) Navigator.pop(ctx);

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Zümre saatleri güncellendi'),
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

Widget _scheduleSection({
  required String title,
  required List<Map<String, String>> slots,
  required Color color,
  required VoidCallback onAdd,
  required Function(int index) onDelete,
}) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.access_time, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            IconButton(
              onPressed: onAdd,
              icon: Icon(Icons.add_circle, color: color),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (slots.isEmpty)
          const Text(
            'Henüz saat eklenmedi.',
            style: TextStyle(color: Colors.white60),
          )
        else
          ...List.generate(slots.length, (index) {
            final slot = slots[index];

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      keyboardType: TextInputType.number,
inputFormatters: [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(4),
  _TimeTextInputFormatter(),
],
                      initialValue: slot['start'],
                      style: const TextStyle(color: Colors.white),
                      decoration: _timeInputDecoration('Başlangıç'),
                      onChanged: (value) => slot['start'] = value,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      initialValue: slot['end'],
                      style: const TextStyle(color: Colors.white),
                      decoration: _timeInputDecoration('Bitiş'),
                      onChanged: (value) => slot['end'] = value,
                    ),
                  ),
                  IconButton(
                    onPressed: () => onDelete(index),
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  ),
                ],
              ),
            );
          }),
      ],
    ),
  );
}

Widget _lunchSection() {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.restaurant_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text(
              'Öğle Arası',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: _lunchStart,
                style: const TextStyle(color: Colors.white),
                decoration: _timeInputDecoration('Başlangıç'),
                onChanged: (value) => _lunchStart = value,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                keyboardType: TextInputType.number,
inputFormatters: [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(4),
  _TimeTextInputFormatter(),
],
                initialValue: _lunchEnd,
                style: const TextStyle(color: Colors.white),
                decoration: _timeInputDecoration('Bitiş'),
                onChanged: (value) => _lunchEnd = value,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

InputDecoration _timeInputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white60),
    hintText: '09:00',
    hintStyle: const TextStyle(color: Colors.white38),
    filled: true,
    fillColor: Colors.white.withOpacity(0.08),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
  );
}

  Widget _quickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _adminGlassDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
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
      return const Center(
        child: Text(
          'Grafik için veri yok',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final maxValue = widget.data.values.reduce((a, b) => a > b ? a : b);
    final selectedDate = _selectedDate ?? widget.data.keys.last;
    final selectedTotal = widget.data[selectedDate] ?? 0;
    final selectedSubjects = widget.subjectData[selectedDate] ?? {};

    return Column(
      children: [
        SizedBox(
          height: 185,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: widget.data.entries.map((entry) {
              final value = entry.value;
              final isSelected = entry.key == selectedDate;
              final barHeight = maxValue == 0 ? 8.0 : (value / maxValue) * 125;

              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
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
                          color: isSelected ? Colors.white : Colors.white60,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: barHeight < 8 ? 8 : barHeight,
                        width: isSelected ? 30 : 22,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: isSelected
                                ? [
                                    Colors.lightBlueAccent,
                                    Colors.blueAccent,
                                  ]
                                : [
                                    Colors.white.withOpacity(0.42),
                                    Colors.white.withOpacity(0.18),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.lightBlueAccent
                                        .withOpacity(0.35),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : [],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected ? Colors.white : Colors.white54,
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
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _showSubjectDetail
                ? Colors.orangeAccent.withOpacity(0.14)
                : Colors.lightBlueAccent.withOpacity(0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _showSubjectDetail
                  ? Colors.orangeAccent.withOpacity(0.30)
                  : Colors.lightBlueAccent.withOpacity(0.30),
            ),
          ),
          child: _showSubjectDetail
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$selectedDate ders dağılımı',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (selectedSubjects.isEmpty)
                      const Text(
                        'Bu gün için ders bazlı veri yok.',
                        style: TextStyle(color: Colors.white70),
                      )
                    else
                      ...selectedSubjects.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                e.key,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              Text(
                                '${e.value} soru',
                                style: const TextStyle(
                                  color: Colors.white,
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
                  '$selectedDate • Toplam: $selectedTotal soru\nDers dağılımı için çubuğa basılı tutun.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
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
  State<UserManagementPage> createState() => _UserManagementPageState();
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

class _UserManagementPageState extends State<UserManagementPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final List<String> _roles = ['admin', 'teacher', 'student'];
  final List<String> _allSubjects = [
    'Matematik',
    'Fizik',
    'Kimya',
    'Biyoloji',
    'Türkçe',
    'Tarih',
    'Coğrafya',
    'Geometri',
  ];

  bool _isLoading = false;
  String _userSearchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => _showUserDialog(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.person_add_alt_1, color: Colors.greenAccent),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Yeni Kullanıcı Ekle',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.white54),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
  child: TextField(
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: 'Kullanıcı ara...',
      hintStyle: const TextStyle(color: Colors.white54),
      prefixIcon: const Icon(Icons.search, color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withOpacity(0.10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
    ),
    onChanged: (value) {
      setState(() {
        _userSearchQuery = value.trim().toLowerCase();
      });
    },
  ),
),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('users').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Hata: ${snapshot.error}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }

                 final allUsers = snapshot.data!.docs;

final users = allUsers.where((doc) {
  final data = doc.data() as Map<String, dynamic>;

  final searchable = [
    data['fullName'],
    data['name'],
    data['surname'],
    data['email'],
    data['role'],
    data['username'],
    data['className'],
    data['branch'],
    data['department'],
    if (data['subjects'] is List) (data['subjects'] as List).join(' '),
  ].where((e) => e != null).join(' ').toLowerCase();

  return _userSearchQuery.isEmpty ||
      searchable.contains(_userSearchQuery);
}).toList();

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final doc = users[index];
                      final data = doc.data() as Map<String, dynamic>;

                      final uid = doc.id;
                      final role = data['role'] ?? '?';
                      final name = data['fullName'] ??
                          data['name'] ??
                          data['email'] ??
                          'İsimsiz';
                      final email = data['email'] ?? 'Email yok';
                      final roleColor = role == 'admin'
                          ? Colors.redAccent
                          : role == 'teacher'
                              ? Colors.lightBlueAccent
                              : Colors.greenAccent;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(24),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: roleColor.withOpacity(0.20),
                              child: Text(
                                role.isNotEmpty ? role[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: roleColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$name',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '$email',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '$role',
                                    style: TextStyle(
                                      color: roleColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),

                                ],
                              ),
                            ),
                            IconButton(
                              icon:
                                  const Icon(Icons.edit, color: Colors.white70),
                              onPressed: () => _editUser(uid, data),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => _deleteUser(uid, email),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
        if (_isLoading)
          Container(
            color: Colors.black.withOpacity(0.45),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }

  Future<void> _showUserDialog({
    String? editingUid,
    Map<String, dynamic>? existingData,
  }) async {
    final isEditing = editingUid != null;
    final formKey = GlobalKey<FormState>();

    String email = existingData?['email'] ?? '';
    String password = '';
    String newPassword = '';
    String name = existingData?['fullName'] ?? existingData?['name'] ?? '';
    String role = existingData?['role'] ?? 'student';
    String className = existingData?['className'] ?? '';
String branch = existingData?['branch'] ?? '';
String department = existingData?['department'] ?? '';
String studentNo = existingData?['studentNo'] ?? '';
String username = existingData?['username'] ?? '';
    List<String> selectedSubjects = existingData?['subjects'] != null
        ? List<String>.from(existingData?['subjects'])
        : [];

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
                      validator: (val) =>
                          val == null || val.isEmpty ? 'Email gerekli' : null,
                    ),
                    if (!isEditing) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        decoration: const InputDecoration(labelText: 'Şifre'),
                        obscureText: true,
                        onChanged: (val) => password = val,
                        validator: (val) => val == null || val.length < 6
                            ? 'Şifre en az 6 karakter'
                            : null,
                      ),
                    ],
                    if (isEditing) ...[
  const SizedBox(height: 8),
  TextFormField(
    decoration: const InputDecoration(
      labelText: 'Yeni Şifre',
      helperText: 'Boş bırakırsanız şifre değişmez',
    ),
    obscureText: true,
    onChanged: (val) => newPassword = val,
    validator: (val) {
      if (val == null || val.isEmpty) return null;
      if (val.length < 6) return 'Şifre en az 6 karakter olmalı';
      return null;
    },
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
                      value: role,
                      decoration: const InputDecoration(labelText: 'Rol'),
                      items: _roles
                          .map(
                            (r) => DropdownMenuItem(
                              value: r,
                              child: Text(r),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setStateDialog(() => role = val);
                      },
                    ),
                    if (role == 'teacher') ...[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Verdiği Dersler'),
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
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
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
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  setState(() => _isLoading = true);

                  try {
                    if (isEditing) {
                      await _updateUser(
                        editingUid,
                        email,
                        name,
                        role,
                        selectedSubjects,
                        username,
                        className,
                        branch,
                        department,
                        studentNo,
                      );
                      if (newPassword.trim().isNotEmpty) {
  await _updateUserPassword(
    uid: editingUid,
    password: newPassword.trim(),
  );
}
                    }
                    if (!isEditing) {
                      await _createUser(
                        email,
                        password,
                        name,
                        role,
                        selectedSubjects,
                        username,
                        className,
                        branch,
                        department,
                        studentNo,
                      );
                    }

                    if (ctx.mounted) Navigator.pop(ctx);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEditing
                              ? 'Kullanıcı güncellendi'
                              : 'Kullanıcı oluşturuldu',
                        ),
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Hata: $e')),
                    );
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
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
  Future<void> _updateUserPassword({
  required String uid,
  required String password,
}) async {
  final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  final callable = functions.httpsCallable('updateUserPassword');

  await callable.call({
    'uid': uid,
    'password': password,
  });
}

  Future<void> _createUser(
    String email,
    String password,
    String name,
    String role,
    List<String> subjects,
    String username,
    String className,
    String branch,
    String department,
    String studentNo,
  ) async {
    const apiKey = 'AIzaSyBznoF8WcalY8k-tUexUTrooeDJdZHsM5w';
    final url = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey',
    );

    final response = await http.post(
      url,
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error']['message'];
      throw Exception('Auth oluşturulamadı: $error');
    }

    final uid = jsonDecode(response.body)['localId'];

    final parts = name.trim().split(' ');
    final firstName = parts.isNotEmpty ? parts.first : name;
    final surname = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    final Map<String, dynamic> userData = {
      'uid': uid,
      'email': email,
      'name': firstName,
      'surname': surname,
      'fullName': name,
      'role': role,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (role == 'teacher') {
      userData['subjects'] = subjects;
      userData['teacherStatus'] = 'available';
    }

    await _firestore.collection('users').doc(uid).set(userData);
  }

  Future<void> _updateUser(
    String uid,
    String newEmail,
    String newName,
    String newRole,
    List<String> subjects,
    String username,
    String className,
    String branch,
    String department,
    String studentNo,
  ) async {
    final parts = newName.trim().split(' ');
    final firstName = parts.isNotEmpty ? parts.first : newName;
    final surname = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    final Map<String, dynamic> updates = {
      'name': firstName,
      'surname': surname,
      'fullName': newName,
      'role': newRole,
      'email': newEmail,
      'updatedAt': FieldValue.serverTimestamp(),
      'username': username,
      'className': className,
      'branch': branch,
      'department': department,
      'studentNo': studentNo,
    };

    if (newRole == 'teacher') {
      updates['subjects'] = subjects;
      updates['teacherStatus'] = 'available';
    } else {
      updates['subjects'] = FieldValue.delete();
      updates['teacherStatus'] = FieldValue.delete();
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

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await _firestore.collection('users').doc(uid).delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcı Firestore’dan silindi.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silme hatası: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _editUser(String uid, Map<String, dynamic> data) {
    _showUserDialog(editingUid: uid, existingData: data);
  }
}