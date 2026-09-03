import 'dart:convert';
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
    'Genel Bakış',
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
              label: 'Genel Bakış',
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

class _ReportClassOption {
  const _ReportClassOption({
    required this.className,
    required this.branch,
    required this.department,
  });

  final String className;
  final String branch;
  final String department;

  String get displayName => [
        className,
        if (branch.isNotEmpty) branch,
        if (department.isNotEmpty) department,
      ].join('-');

  String get key => '$className|$branch|$department';
}

class _StatisticsPageState extends State<StatisticsPage> {
  static const String _reportsBaseUrl =
      'https://zumrenet-reports-542741706921.europe-west1.run.app';

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
  final List<Map<String, String>> _weekdayStudySlots = [];
  final List<Map<String, String>> _weekendStudySlots = [];

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

  void _showExcelLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 26),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF071A3A),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white24),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(color: Colors.lightBlueAccent),
              ),
              SizedBox(width: 18),
              Expanded(
                child: Text(
                  'Excel dosyası okunuyor...\n'
                  'Veri yoğunluğuna bağlı olarak bu işlem biraz sürebilir.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _hideExcelLoadingDialog() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _showPdfLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 26),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF071A3A),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white24),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(color: Colors.lightBlueAccent),
              ),
              SizedBox(width: 18),
              Expanded(
                child: Text(
                  'PDF raporu hazırlanıyor...\n'
                  'Seçilen aralıktaki veriler işleniyor.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _hidePdfLoadingDialog() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  String _formatIsoDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDisplayDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  DateTimeRange _reportRangeForPreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (preset == 'week') {
      final start = today.subtract(Duration(days: today.weekday - 1));
      return DateTimeRange(start: start, end: today);
    }

    if (preset == 'month') {
      return DateTimeRange(
          start: DateTime(today.year, today.month), end: today);
    }

    return DateTimeRange(start: today, end: today);
  }

  Future<List<_ReportClassOption>> _loadReportClassOptions() async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'student')
        .get();

    final optionMap = <String, _ReportClassOption>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final className = '${data['className'] ?? ''}'.trim();
      if (className.isEmpty) continue;

      final option = _ReportClassOption(
        className: className,
        branch: '${data['branch'] ?? ''}'.trim(),
        department: '${data['department'] ?? ''}'.trim(),
      );
      optionMap[option.key] = option;
    }

    final classes = optionMap.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return classes;
  }

  Future<_ReportClassOption?> _showReportClassPicker() async {
    final classes = await _loadReportClassOptions();
    if (!mounted) return null;

    if (classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sınıf raporu için öğrenci sınıf bilgisi bulunamadı.'),
        ),
      );
      return null;
    }

    var selectedClass = classes.first;

    return showDialog<_ReportClassOption>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF071A3A),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.30),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withOpacity(0.14),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.greenAccent.withOpacity(0.28),
                            ),
                          ),
                          child: const Icon(
                            Icons.groups_rounded,
                            color: Colors.greenAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Sınıf Seç',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<_ReportClassOption>(
                      initialValue: selectedClass,
                      dropdownColor: const Color(0xFF071A3A),
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Rapor sınıfı',
                        labelStyle: const TextStyle(color: Colors.white60),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.08),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide:
                              const BorderSide(color: Colors.lightBlueAccent),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      items: classes
                          .map(
                            (classOption) => DropdownMenuItem(
                              value: classOption,
                              child: Text(classOption.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedClass = value);
                      },
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(ctx, selectedClass),
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('Raporu Oluştur'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightBlueAccent,
                          foregroundColor: const Color(0xFF071A3A),
                          padding: const EdgeInsets.symmetric(vertical: 14),
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

  Future<void> _requestClassReportPdf({
    required String endpoint,
    required String fallbackFileName,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final selectedClass = await _showReportClassPicker();
    if (selectedClass == null || selectedClass.className.isEmpty) return;

    await _requestReportPdf(
      endpoint: endpoint,
      fallbackFileName: fallbackFileName,
      startDate: startDate,
      endDate: endDate,
      className: selectedClass.className,
      branch: selectedClass.branch,
      department: selectedClass.department,
    );
  }

  String? _filenameFromContentDisposition(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(r'filename="?([^";]+)"?').firstMatch(value);
    return match?.group(1);
  }

  Future<void> _requestReportPdf({
    required String endpoint,
    required String fallbackFileName,
    required DateTime startDate,
    required DateTime endDate,
    String? className,
    String? branch,
    String? department,
  }) async {
    var loadingShown = false;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final idToken = await currentUser?.getIdToken();

      if (idToken == null || idToken.isEmpty) {
        throw Exception(
            'Rapor oluşturmak için geçerli admin oturumu bulunamadı.');
      }

      if (!mounted) return;
      _showPdfLoadingDialog();
      loadingShown = true;

      final response = await http.post(
        Uri.parse('$_reportsBaseUrl$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'startDate': _formatIsoDate(startDate),
          'endDate': _formatIsoDate(endDate),
          if (className != null) 'className': className,
          if (branch != null && branch.isNotEmpty) 'branch': branch,
          if (department != null && department.isNotEmpty)
            'department': department,
        }),
      );

      if (!mounted) return;
      _hidePdfLoadingDialog();
      loadingShown = false;

      if (response.statusCode != 200) {
        if (response.statusCode == 401) {
          throw Exception('Admin oturumu doğrulanamadı.');
        }
        if (response.statusCode == 403) {
          throw Exception('Bu rapor için admin yetkisi gerekiyor.');
        }
        throw Exception('Rapor oluşturulamadı.');
      }

      final filename = _filenameFromContentDisposition(
            response.headers['content-disposition'],
          ) ??
          fallbackFileName;

      await Printing.sharePdf(bytes: response.bodyBytes, filename: filename);
    } catch (e) {
      if (!mounted) return;
      if (loadingShown) {
        _hidePdfLoadingDialog();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rapor hatası: $e')),
      );
    }
  }

  Future<void> _showPdfReportDialog() async {
    var preset = 'today';
    var selectedRange = _reportRangeForPreset(preset);

    Future<void> pickDate({
      required bool isStart,
      required StateSetter setDialogState,
    }) async {
      final picked = await showDatePicker(
        context: context,
        locale: const Locale('tr', 'TR'),
        firstDate: DateTime(2024),
        lastDate: DateTime.now(),
        initialDate: isStart ? selectedRange.start : selectedRange.end,
      );

      if (picked == null) return;
      setDialogState(() {
        preset = 'custom';
        if (isStart) {
          selectedRange = DateTimeRange(
            start: picked,
            end: picked.isAfter(selectedRange.end) ? picked : selectedRange.end,
          );
        } else {
          selectedRange = DateTimeRange(
            start: picked.isBefore(selectedRange.start)
                ? picked
                : selectedRange.start,
            end: picked,
          );
        }
      });
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final screenSize = MediaQuery.of(context).size;
            final isMobile = screenSize.width < 600;
            final rangeLabel =
                '${_formatDisplayDate(selectedRange.start)} - ${_formatDisplayDate(selectedRange.end)}';

            void selectPreset(String value) {
              setDialogState(() {
                preset = value;
                selectedRange = _reportRangeForPreset(value);
              });
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: EdgeInsets.symmetric(
                horizontal: isMobile ? 10 : 24,
                vertical: isMobile ? 12 : 24,
              ),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  maxWidth: 680,
                  maxHeight: screenSize.height * 0.90,
                ),
                padding: EdgeInsets.all(isMobile ? 16 : 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF071A3A),
                  borderRadius: BorderRadius.circular(isMobile ? 24 : 28),
                  border: Border.all(color: Colors.white24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.30),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: isMobile ? 44 : 52,
                            height: isMobile ? 44 : 52,
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.16),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.redAccent.withOpacity(0.35),
                              ),
                            ),
                            child: Icon(
                              Icons.analytics_rounded,
                              color: Colors.redAccent,
                              size: isMobile ? 25 : 29,
                            ),
                          ),
                          SizedBox(width: isMobile ? 10 : 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Rapor Merkezi',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: isMobile ? 19 : 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  isMobile
                                      ? 'PDF raporları hazırlayın.'
                                      : 'Kurum ve sınıf raporlarını PDF olarak hazırlayın.',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: isMobile ? 12 : 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isMobile ? 14 : 18),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _reportPresetChip(
                            'Bugün',
                            'today',
                            preset,
                            selectPreset,
                          ),
                          _reportPresetChip(
                            'Bu Hafta',
                            'week',
                            preset,
                            selectPreset,
                          ),
                          _reportPresetChip(
                            'Bu Ay',
                            'month',
                            preset,
                            selectPreset,
                          ),
                          _reportPresetChip('Özel', 'custom', preset, (value) {
                            setDialogState(() => preset = value);
                          }),
                        ],
                      ),
                      SizedBox(height: isMobile ? 10 : 12),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(isMobile ? 12 : 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.date_range_rounded,
                                  color: Colors.lightBlueAccent,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    rangeLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (preset == 'custom') ...[
                              const SizedBox(height: 10),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stackDates = constraints.maxWidth < 340;
                                  final buttons = [
                                    OutlinedButton.icon(
                                      onPressed: () => pickDate(
                                        isStart: true,
                                        setDialogState: setDialogState,
                                      ),
                                      icon: const Icon(
                                        Icons.calendar_today_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Başlangıç'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.lightBlueAccent,
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.06),
                                        side: BorderSide(
                                          color: Colors.lightBlueAccent
                                              .withValues(alpha: 0.32),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(15),
                                        ),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () => pickDate(
                                        isStart: false,
                                        setDialogState: setDialogState,
                                      ),
                                      icon: const Icon(
                                        Icons.event_available_rounded,
                                        size: 17,
                                      ),
                                      label: const Text('Bitiş'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.lightBlueAccent,
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.06),
                                        side: BorderSide(
                                          color: Colors.lightBlueAccent
                                              .withValues(alpha: 0.32),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(15),
                                        ),
                                      ),
                                    ),
                                  ];

                                  if (stackDates) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        buttons[0],
                                        const SizedBox(height: 8),
                                        buttons[1],
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: [
                                      Expanded(child: buttons[0]),
                                      const SizedBox(width: 10),
                                      Expanded(child: buttons[1]),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(height: isMobile ? 12 : 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 560;
                          final cards = [
                            _reportCard(
                              icon: Icons.apartment_rounded,
                              title: 'Kurum Faaliyet Özeti',
                              subtitle:
                                  'Tamamlanan zümre soruları ve etüt oturumları',
                              color: Colors.lightBlueAccent,
                              compact: compact,
                              onTap: () => _requestReportPdf(
                                endpoint: '/reports/institution-summary',
                                fallbackFileName: 'Kurum_Faaliyet_Ozeti.pdf',
                                startDate: selectedRange.start,
                                endDate: selectedRange.end,
                              ),
                            ),
                            _reportCard(
                              icon: Icons.groups_rounded,
                              title: 'Sınıf Takip Raporu',
                              subtitle: 'Öğrenci bazlı zümre ve etüt özeti',
                              color: Colors.greenAccent,
                              compact: compact,
                              onTap: () => _requestClassReportPdf(
                                endpoint: '/reports/class-tracking',
                                fallbackFileName: 'Sinif_Takip_Raporu.pdf',
                                startDate: selectedRange.start,
                                endDate: selectedRange.end,
                              ),
                            ),
                            _reportCard(
                              icon: Icons.timeline_rounded,
                              title: 'Sınıf Faaliyet Takip',
                              subtitle:
                                  'Öğrenci faaliyetlerini tarih sırasıyla listeler',
                              color: Colors.orangeAccent,
                              compact: compact,
                              onTap: () => _requestClassReportPdf(
                                endpoint: '/reports/class-activity',
                                fallbackFileName:
                                    'Sinif_Faaliyet_Takip_Raporu.pdf',
                                startDate: selectedRange.start,
                                endDate: selectedRange.end,
                              ),
                            ),
                          ];

                          if (compact) {
                            return Column(
                              children: cards
                                  .map(
                                    (card) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: card,
                                    ),
                                  )
                                  .toList(),
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: cards
                                .map(
                                  (card) => Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                      ),
                                      child: card,
                                    ),
                                  ),
                                )
                                .toList(),
                          );
                        },
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

  Widget _reportPresetChip(
    String label,
    String value,
    String selectedValue,
    ValueChanged<String> onSelected,
  ) {
    final selected = value == selectedValue;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
      backgroundColor: Colors.white.withOpacity(0.08),
      selectedColor: Colors.lightBlueAccent,
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF071A3A) : Colors.white70,
        fontWeight: FontWeight.bold,
      ),
      side: BorderSide(
        color: selected ? Colors.lightBlueAccent : Colors.white12,
      ),
    );
  }

  Widget _reportCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
    bool compact = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: compact ? 82 : 132),
        padding: EdgeInsets.all(compact ? 13 : 15),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(enabled ? 0.08 : 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: enabled ? Colors.white12 : Colors.white10),
        ),
        child: compact
            ? Row(
                children: [
                  Icon(icon, color: enabled ? color : Colors.white30, size: 27),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: enabled ? Colors.white : Colors.white38,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: enabled ? Colors.white60 : Colors.white30,
                            fontSize: 11.5,
                            height: 1.20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: enabled ? Colors.white38 : Colors.white24,
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: enabled ? color : Colors.white30, size: 28),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled ? Colors.white60 : Colors.white30,
                      fontSize: 11.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _loadStats() async {
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

  Map<String, dynamic> _parseUtf8JsonResponse(http.Response response) {
    final body = utf8.decode(response.bodyBytes);
    return Map<String, dynamic>.from(jsonDecode(body));
  }

  Future<void> _pickEdesisFile(String type) async {
    const smartImportBaseUrl =
        'https://zumrenet-smart-import-542741706921.europe-west1.run.app';

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'xls', 'xlsx'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) return;

      final file = result.files.single;
      final fileBase64 = base64Encode(file.bytes!);
      final currentUser = FirebaseAuth.instance.currentUser;
      final idToken = await currentUser?.getIdToken();

      if (idToken == null || idToken.isEmpty) {
        throw Exception('Smart Import için geçerli admin oturumu bulunamadı.');
      }

      if (!mounted) return;
      _showExcelLoadingDialog();

      final response = await http.post(
        Uri.parse('$smartImportBaseUrl/analyze'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'fileBase64': fileBase64,
          'fileName': file.name,
          'type': type,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Smart Import analiz hatası: ${response.body}');
      }
      final analyzeData = _parseUtf8JsonResponse(response);

      if (!mounted) return;
      _hideExcelLoadingDialog();

      final confirm = await _showImportAnalysisDialog(
        type: type,
        data: analyzeData,
      );

      if (confirm != true) return;

      final validRows = List.from(analyzeData['validRows'] ?? []);

      if (validRows.isEmpty) {
        throw Exception('Aktarılacak geçerli kayıt bulunamadı.');
      }

      if (!mounted) return;
      _showExcelLoadingDialog();

      final importResponse = await http.post(
        Uri.parse('$smartImportBaseUrl/import'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'type': analyzeData['type'],
          'validRows': validRows,
        }),
      );

      if (importResponse.statusCode != 200) {
        throw Exception('Smart Import aktarım hatası: ${importResponse.body}');
      }
      final importData = _parseUtf8JsonResponse(importResponse);

      final summary = {
        'totalValid': importData['totalValid'] ?? 0,
        'created': importData['created'] ?? 0,
        'updated': importData['updated'] ?? 0,
        'failed': importData['failed'] ?? 0,
      };

      if (!mounted) return;
      _hideExcelLoadingDialog();

      await _showImportResultDialog(
        importData: importData,
        summary: summary,
      );

      await _loadStats();
    } catch (e) {
      if (!mounted) return;

      _hideExcelLoadingDialog();

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
                              : '${row['fullName']} • ${(row['subjects'] is List && row['subjects'].isNotEmpty) ? row['subjects'].join(', ') : 'Branş yok'} • ${row['username']}',
                          style: const TextStyle(color: Colors.white70),
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
                          child: const Text('Sunucuya Aktar'),
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
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 26),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF071A3A),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
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
                  color: Colors.greenAccent.withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.greenAccent,
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Sunucuya Aktarım Tamamlandı',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Toplam geçerli: ${summary['totalValid'] ?? 0}\n'
                'Yeni oluşturulan: ${summary['created'] ?? 0}\n'
                'Güncellenen: ${summary['updated'] ?? 0}\n'
                'Başarısız: ${summary['failed'] ?? 0}\n'
                'Hatalı satır: ${importData['invalidCount'] ?? 0}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.45),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('Tamam'),
                ),
              ),
            ],
          ),
        ),
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
                            subtitle: 'Edesis Öğrenci Excel dosyası seçilir',
                            color: Colors.orangeAccent,
                            onTap: () => _pickEdesisFile('student'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _quickActionCard(
                            icon: Icons.badge_rounded,
                            title: 'Öğretmen Aktar',
                            subtitle: 'Edesis Öğretmen Excel dosyası seçilir',
                            color: Colors.greenAccent,
                            onTap: () => _pickEdesisFile('teacher'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _quickActionCard(
                      icon: Icons.picture_as_pdf_rounded,
                      title: 'Rapor Merkezi',
                      subtitle: 'Kurum ve sınıf PDF raporları oluşturulur',
                      color: Colors.redAccent,
                      onTap: _showPdfReportDialog,
                    ),
                    const SizedBox(height: 12),
                    _quickActionCard(
                      icon: Icons.schedule_rounded,
                      title: 'Çalışma Saatleri',
                      subtitle:
                          'Hafta içi, hafta sonu ve öğle arası vakitleri ayarlanır',
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
    final doc =
        await _firestore.collection('settings').doc('zumreSchedule').get();

    _weekdaySlots.clear();
    _weekendSlots.clear();
    _weekdayStudySlots.clear();
    _weekendStudySlots.clear();

    if (doc.exists) {
      final data = doc.data() ?? {};
      final weekday = List.from(data['weekdaySlots'] ?? []);
      final weekend = List.from(data['weekendSlots'] ?? []);
      final weekdayStudy = List.from(data['weekdayStudySlots'] ?? []);
      final weekendStudy = List.from(data['weekendStudySlots'] ?? []);
      final lunch = Map<String, dynamic>.from(data['lunchBreak'] ?? {});

      _weekdaySlots.addAll(
        weekday.map((e) => {'start': '${e['start']}', 'end': '${e['end']}'}),
      );

      _weekendSlots.addAll(
        weekend.map((e) => {'start': '${e['start']}', 'end': '${e['end']}'}),
      );

      _weekdayStudySlots.addAll(
        weekdayStudy
            .map((e) => {'start': '${e['start']}', 'end': '${e['end']}'}),
      );

      _weekendStudySlots.addAll(
        weekendStudy
            .map((e) => {'start': '${e['start']}', 'end': '${e['end']}'}),
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
                        'Zaman Yönetimi',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Zümre, etüt ve öğle arası vakitlerini yönetin',
                        style: TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 20),
                      _scheduleSection(
                        title: 'Hafta İçi Zümre Saatleri',
                        slots: _weekdaySlots,
                        color: Colors.greenAccent,
                        onAdd: () {
                          setDialogState(() {
                            _weekdaySlots
                                .add({'start': '10:40', 'end': '11:20'});
                          });
                        },
                        onDelete: (index) {
                          setDialogState(() => _weekdaySlots.removeAt(index));
                        },
                      ),
                      const SizedBox(height: 20),
                      _scheduleSection(
                        title: 'Hafta Sonu Zümre Saatleri',
                        slots: _weekendSlots,
                        color: Colors.orangeAccent,
                        onAdd: () {
                          setDialogState(() {
                            _weekendSlots
                                .add({'start': '13:00', 'end': '14:00'});
                          });
                        },
                        onDelete: (index) {
                          setDialogState(() => _weekendSlots.removeAt(index));
                        },
                      ),
                      const SizedBox(height: 20),
                      _scheduleSection(
                        title: 'Hafta İçi Etüt Saatleri',
                        slots: _weekdayStudySlots,
                        color: Colors.cyanAccent,
                        onAdd: () {
                          setDialogState(() {
                            _weekdayStudySlots
                                .add({'start': '17:00', 'end': '18:00'});
                          });
                        },
                        onDelete: (index) {
                          setDialogState(
                              () => _weekdayStudySlots.removeAt(index));
                        },
                      ),
                      const SizedBox(height: 20),
                      _scheduleSection(
                        title: 'Hafta Sonu Etüt Saatleri',
                        slots: _weekendStudySlots,
                        color: Colors.pinkAccent,
                        onAdd: () {
                          setDialogState(() {
                            _weekendStudySlots
                                .add({'start': '15:00', 'end': '16:00'});
                          });
                        },
                        onDelete: (index) {
                          setDialogState(
                              () => _weekendStudySlots.removeAt(index));
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
                                  'weekdayStudySlots': _weekdayStudySlots,
                                  'weekendStudySlots': _weekendStudySlots,
                                  'lunchBreak': {
                                    'start': _lunchStart,
                                    'end': _lunchEnd,
                                  },
                                  'updatedAt': FieldValue.serverTimestamp(),
                                });

                                if (ctx.mounted) Navigator.pop(ctx);

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Saatler güncellendi'),
                                  ),
                                );
                              },
                              child: const Text('Kaydet'),
                            ),
                          ),
                          const SizedBox(height: 16),
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
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                          _TimeTextInputFormatter(),
                        ],
                        style: const TextStyle(color: Colors.white),
                        decoration: _timeInputDecoration('Bitiş'),
                        onChanged: (value) => slot['end'] = value,
                      ),
                    ),
                    IconButton(
                      onPressed: () => onDelete(index),
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent),
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
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                    _TimeTextInputFormatter(),
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: _timeInputDecoration('Başlangıç'),
                  onChanged: (value) => _lunchStart = value,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: _lunchEnd,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                    _TimeTextInputFormatter(),
                  ],
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
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-central1');

  final List<String> _roles = ['admin', 'teacher', 'student', 'studyGuard'];
  String _roleLabel(String role) {
    switch (role.trim()) {
      case 'admin':
        return 'Yönetici';
      case 'teacher':
        return 'Öğretmen';
      case 'student':
        return 'Öğrenci';
      case 'studyGuard':
        return 'Etüt Görevlisi';
      default:
        return role;
    }
  }

  final List<String> _allSubjects = [
    'MATEMATİK',
    'FİZİK',
    'KİMYA',
    'BİYOLOJİ',
    'TÜRKÇE',
    'TARİH',
    'COĞRAFYA',
    'GEOMETRİ',
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
                  String normalizeForSearch(String str) {
                    return str
                        .toLowerCase()
                        .replaceAll('ı', 'i')
                        .replaceAll('ğ', 'g')
                        .replaceAll('ü', 'u')
                        .replaceAll('ş', 's')
                        .replaceAll('ö', 'o')
                        .replaceAll('ç', 'c')
                        .replaceAll('İ', 'i');
                  }

                  final users = allUsers.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;

                    final searchableRaw = [
                      data['fullName'],
                      data['name'],
                      data['surname'],
                      data['email'],
                      data['role'],
                      data['username'],
                      data['className'],
                      data['branch'],
                      data['department'],
                      if (data['subjects'] is List)
                        (data['subjects'] as List).join(' '),
                    ].where((e) => e != null).join(' ');

                    final searchable = normalizeForSearch(searchableRaw);
                    final query = normalizeForSearch(_userSearchQuery);

                    return _userSearchQuery.isEmpty ||
                        searchable.contains(query);
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
                                    _roleLabel(role),
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
    const String domain = '@bilimkalesi.com';

    String email = existingData?['email'] ?? '';
    String password = '';
    String newPassword = '';

    String firstName = existingData?['name']?.toString() ?? '';
    String surname = existingData?['surname']?.toString() ?? '';

    String className = existingData?['className']?.toString() ?? '';
    String branch = existingData?['branch']?.toString() ?? '';
    String department = existingData?['department']?.toString() ?? '';
    String studentNo = existingData?['studentNo']?.toString() ?? '';
    String username = existingData?['username']?.toString() ?? '';

    String role = existingData?['role']?.toString().trim() ?? 'student';

    if (!_roles.contains(role)) {
      role = 'student';
    }
    final List<String> selectedSubjects = [];

    final rawSubjects = existingData?['subjects'];

    if (rawSubjects is List) {
      for (final item in rawSubjects) {
        final value = item.toString().trim();

        if (value.isNotEmpty) {
          selectedSubjects.add(
            (value),
          );
        }
      }
    } else if (rawSubjects is String && rawSubjects.trim().isNotEmpty) {
      final parts = rawSubjects.split(RegExp(r'[,;/|]'));

      for (final item in parts) {
        final value = item.trim();

        if (value.isNotEmpty) {
          selectedSubjects.add((value));
        }
      }
    }

    final String? legacyBranch = existingData?['branch']?.toString().trim();

    if (role == 'teacher' &&
        selectedSubjects.isEmpty &&
        legacyBranch != null &&
        legacyBranch.isNotEmpty) {
      selectedSubjects.add(legacyBranch);
    }
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 18),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF071A3A),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.30),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: Colors.lightBlueAccent,
                    secondary: Colors.greenAccent,
                    surface: Color(0xFF071A3A),
                  ),
                  inputDecorationTheme: InputDecorationTheme(
                    labelStyle: const TextStyle(color: Colors.white70),
                    helperStyle: const TextStyle(color: Colors.white54),
                    hintStyle: const TextStyle(color: Colors.white38),
                    suffixStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  textTheme: Theme.of(context).textTheme.apply(
                        bodyColor: Colors.white,
                        displayColor: Colors.white,
                      ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEditing ? 'Kullanıcı Düzenle' : 'Yeni Kullanıcı Ekle',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Form(
                          key: formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextFormField(
                                initialValue: username,
                                decoration: const InputDecoration(
                                  labelText: 'Kullanıcı Adı',
                                  helperText:
                                      'Girişte kullanılacak kullanıcı adıdır. E-posta otomatik oluşturulur.',
                                  suffixText: '@bilimkalesi.com',
                                ),
                                onChanged: (val) {
                                  username = val
                                      .trim()
                                      .replaceAll(' ', '')
                                      .toLowerCase();
                                  email = '$username$domain';
                                },
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Kullanıcı adı zorunlu';
                                  }
                                  return null;
                                },
                              ),
                              if (!isEditing) ...[
                                const SizedBox(height: 8),
                                TextFormField(
                                  decoration:
                                      const InputDecoration(labelText: 'Şifre'),
                                  obscureText: true,
                                  onChanged: (val) => password = val,
                                  validator: (val) =>
                                      val == null || val.length < 6
                                          ? 'Şifre en az 6 karakter'
                                          : null,
                                ),
                              ],
                              if (isEditing) ...[
                                const SizedBox(height: 8),
                                TextFormField(
                                  decoration: const InputDecoration(
                                    labelText: 'Yeni Şifre',
                                    helperText:
                                        'Boş bırakırsanız şifre değişmez',
                                  ),
                                  obscureText: true,
                                  onChanged: (val) => newPassword = val,
                                  validator: (val) {
                                    if (val == null || val.isEmpty) return null;
                                    if (val.length < 6)
                                      return 'Şifre en az 6 karakter olmalı';
                                    return null;
                                  },
                                ),
                              ],
                              const SizedBox(height: 8),
                              TextFormField(
                                initialValue: firstName,
                                decoration: const InputDecoration(
                                  labelText: 'Ad',
                                  hintText: 'Örneğin: Mehmet Ali',
                                ),
                                textCapitalization: TextCapitalization.words,
                                onChanged: (val) => firstName = val.trim(),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Ad zorunludur';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                initialValue: surname,
                                decoration: const InputDecoration(
                                  labelText: 'Soyad',
                                  hintText: 'Örneğin: Yılmaz',
                                ),
                                textCapitalization: TextCapitalization.words,
                                onChanged: (val) => surname = val.trim(),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Soyad zorunludur';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: role,
                                decoration: const InputDecoration(
                                  labelText: 'Rol',
                                ),
                                items: _roles.map((roleValue) {
                                  return DropdownMenuItem<String>(
                                    value: roleValue,
                                    child: Text(_roleLabel(roleValue)),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value == null) return;

                                  setStateDialog(() {
                                    role = value;

                                    if (role != 'teacher') {
                                      selectedSubjects.clear();
                                    }
                                  });
                                },
                              ),
                              if (role == 'student') ...[
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: className,
                                  decoration:
                                      const InputDecoration(labelText: 'Sınıf'),
                                  onChanged: (val) => className = val.trim(),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: branch,
                                  decoration:
                                      const InputDecoration(labelText: 'Şube'),
                                  onChanged: (val) => branch = val.trim(),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: department,
                                  decoration: const InputDecoration(
                                      labelText: 'Alan / Bölüm'),
                                  onChanged: (val) => department = val.trim(),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: studentNo,
                                  decoration: const InputDecoration(
                                      labelText: 'Öğrenci No'),
                                  onChanged: (val) => studentNo = val.trim(),
                                ),
                              ],
                              if (role == 'teacher') ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Verdiği Ders',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ..._allSubjects.map((final subject) {
                                        final groupValue =
                                            selectedSubjects.isNotEmpty
                                                ? selectedSubjects.first
                                                : null;

                                        return RadioListTile<String>(
                                          contentPadding: EdgeInsets.zero,
                                          dense: true,
                                          value: subject,
                                          groupValue: groupValue,
                                          title: Text(subject),
                                          onChanged: (value) {
                                            if (value == null) return;
                                            setStateDialog(() {
                                              selectedSubjects
                                                ..clear()
                                                ..add(value);
                                            });
                                          },
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
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
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('İptal'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            onPressed: () async {
                              if (!formKey.currentState!.validate()) return;

                              setState(() => _isLoading = true);
                              try {
                                final cleanFirstName = firstName
                                    .replaceAll(RegExp(r'\s+'), ' ')
                                    .trim();

                                final cleanSurname = surname
                                    .replaceAll(RegExp(r'\s+'), ' ')
                                    .trim();

                                final fullName = '$cleanFirstName $cleanSurname'
                                    .replaceAll(RegExp(r'\s+'), ' ')
                                    .trim();

                                if (isEditing) {
                                  await _updateUser(
                                    editingUid,
                                    email,
                                    cleanFirstName,
                                    cleanSurname,
                                    fullName,
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
                                } else {
                                  await _createUser(
                                    email,
                                    password,
                                    cleanFirstName,
                                    cleanSurname,
                                    fullName,
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
                                  SnackBar(
                                    content: Text(
                                      'Hata: ${_adminFunctionErrorMessage(e)}',
                                    ),
                                  ),
                                );
                              } finally {
                                if (mounted) setState(() => _isLoading = false);
                              }
                            },
                            child: Text(isEditing ? 'Güncelle' : 'Oluştur'),
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
      ),
    );
  }

  Future<void> _updateUserPassword({
    required String uid,
    required String password,
  }) async {
    final callable = _functions.httpsCallable('updateUserPassword');

    await callable.call({
      'uid': uid,
      'password': password,
    });
  }

  String _adminFunctionErrorMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      final message = error.message?.trim();

      if (message != null && message.isNotEmpty) {
        return message;
      }

      switch (error.code) {
        case 'permission-denied':
          return 'Bu işlem için yetkiniz bulunmuyor.';
        case 'already-exists':
          return 'Bu kullanıcı adı zaten kullanılıyor.';
        case 'failed-precondition':
          return 'Bu kullanıcının aktif bir işlemi bulunuyor.';
        case 'not-found':
          return 'Kullanıcı kaydı bulunamadı.';
        case 'invalid-argument':
          return 'Girilen bilgileri kontrol edin.';
        default:
          return 'İşlem tamamlanamadı.';
      }
    }

    return error.toString();
  }

  Future<void> _createUser(
    String email,
    String password,
    String firstName,
    String surname,
    String fullName,
    String role,
    List<String> subjects,
    String username,
    String className,
    String branch,
    String department,
    String studentNo,
  ) async {
    final callable = _functions.httpsCallable('adminCreateUser');

    await callable.call({
      'email': email,
      'username': username,
      'name': firstName,
      'surname': surname,
      'fullName': fullName,
      'role': role,
      'subjects': subjects,
      'className': className,
      'branch': branch,
      'department': department,
      'studentNo': studentNo,
      'password': password,
    });
  }

  Future<void> _updateUser(
    String uid,
    String newEmail,
    String firstName,
    String surname,
    String fullName,
    String newRole,
    List<String> subjects,
    String username,
    String className,
    String branch,
    String department,
    String studentNo,
  ) async {
    final callable = _functions.httpsCallable('adminUpdateUser');

    await callable.call({
      'uid': uid,
      'email': newEmail,
      'username': username,
      'name': firstName,
      'surname': surname,
      'fullName': fullName,
      'role': newRole,
      'subjects': subjects,
      'className': className,
      'branch': branch,
      'department': department,
      'studentNo': studentNo,
    });
  }

  Future<void> _deleteUser(String uid, String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 26),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF071A3A),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
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
                  color: Colors.redAccent.withOpacity(0.16),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Kullanıcıyı Sil',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '$email kullanıcısının hesabı silinecek. Emin misiniz?',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.35),
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
                      child: const Text('Hayır'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('Evet'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final callable = _functions.httpsCallable('adminDeleteUser');
      await callable.call({
        'uid': uid,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcı hesabı silindi.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Silme hatası: ${_adminFunctionErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _editUser(String uid, Map<String, dynamic> data) {
    _showUserDialog(editingUid: uid, existingData: data);
  }
}
