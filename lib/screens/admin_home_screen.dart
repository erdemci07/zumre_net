import 'dart:convert';
import 'dart:async';

import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/education_scope.dart';
import '../utils/class_name_display.dart';
import '../utils/guidance_student_groups.dart';
import '../utils/user_management_filters.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _selectedIndex = 0;

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
              Expanded(
                child: _selectedIndex == 0
                    ? StatisticsPage(
                        onOpenUsers: () => setState(() => _selectedIndex = 1),
                      )
                    : const UserManagementPage(),
              ),
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bilim Kalesi Eğitim Kurumları',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
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
                final shouldLogout = await _confirmLogout();
                if (!shouldLogout) return;
                await FirebaseAuth.instance.signOut();
              },
              icon: const Icon(Icons.logout, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmLogout() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF071A3A),
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
                    'Yönetici oturumundan çıkmak istiyor musunuz?',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.35),
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
                          onPressed: () => Navigator.pop(ctx, true),
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

  Widget _buildBottomNav() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF071A3A).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
            color: selected
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.transparent,
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
  final VoidCallback? onOpenUsers;

  const StatisticsPage({super.key, this.onOpenUsers});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

// ignore: unused_element
class _ReportClassOption {
  const _ReportClassOption({
    required this.className,
    required this.branch,
    required this.department,
  });

  final String className;
  final String branch;
  final String department;

  String get displayName => formatStudentClassDisplay(
        className: className,
        branch: branch,
        department: department,
      );

  String get key => '$className|$branch|$department';
}

class _StatisticsPageState extends State<StatisticsPage> {
  static const String _reportsBaseUrl =
      'https://zumrenet-reports-542741706921.europe-west1.run.app';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  int _totalSolvedToday = 0;
  bool _isLoading = true;
  final bool _isImporting = false;
  bool _isChangingInstitutionMode = false;
  Timer? _institutionCountdownTimer;
  final Map<String, Map<String, dynamic>> _weeklyScheduleDraft = {};
  static const List<Map<String, String>> _scheduleDays = [
    {'key': 'monday', 'label': 'Pazartesi'},
    {'key': 'tuesday', 'label': 'Salı'},
    {'key': 'wednesday', 'label': 'Çarşamba'},
    {'key': 'thursday', 'label': 'Perşembe'},
    {'key': 'friday', 'label': 'Cuma'},
    {'key': 'saturday', 'label': 'Cumartesi'},
    {'key': 'sunday', 'label': 'Pazar'},
  ];

  @override
  void initState() {
    super.initState();
    _loadStats();
    _institutionCountdownTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _institutionCountdownTimer?.cancel();
    super.dispose();
  }

  String _formatClock(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatRemaining(Duration duration) {
    if (duration.isNegative) return '0 dk kaldı';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '$hours sa $minutes dk kaldı';
    return '$minutes dk kaldı';
  }

  String _messageWithCancelledCount(String base, dynamic data) {
    final map = data is Map ? Map<String, dynamic>.from(data) : {};
    final cancelledCount = (map['cancelledCount'] as num?)?.toInt() ?? 0;
    if (cancelledCount <= 0) return base;
    return '$base $cancelledCount planlı zümre iptal edildi.';
  }

  String _scheduleSavedMessage(dynamic data) {
    return _messageWithCancelledCount('Saatler güncellendi.', data);
  }

  Future<T?> _runInstitutionAction<T>(
    String loadingText,
    Future<T> Function() action,
  ) async {
    if (_isChangingInstitutionMode) return null;

    setState(() => _isChangingInstitutionMode = true);
    var dialogShown = false;

    if (mounted) {
      dialogShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF071A3A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.lightBlueAccent,
                    strokeWidth: 2.4,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    loadingText,
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    try {
      return await action();
    } finally {
      if (mounted && dialogShown && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (mounted) {
        setState(() => _isChangingInstitutionMode = false);
      }
    }
  }

  String _institutionModeFromRuntime(Map<String, dynamic>? data) {
    final mode = '${data?['institutionMode'] ?? 'active'}';
    if (mode == 'closed' || mode == 'exam') return mode;
    return 'active';
  }

  String _institutionActionErrorMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) return message;

      switch (error.code) {
        case 'permission-denied':
          return 'Bu işlem için yetkiniz bulunmuyor.';
        case 'already-exists':
          return 'Seçilen aralıkta başka bir planlı işlem var.';
        case 'failed-precondition':
          return 'Bu işlem şu anda yapılamıyor.';
        case 'not-found':
          return 'Planlı işlem bulunamadı.';
        case 'invalid-argument':
          return 'Girilen bilgileri kontrol edin.';
        default:
          return 'İşlem tamamlanamadı.';
      }
    }

    return 'İşlem tamamlanamadı.';
  }

  Future<void> _setInstitutionMode(
    String mode, {
    String? examType,
  }) async {
    try {
      final response = await _runInstitutionAction(
        'Kurum durumu güncelleniyor...',
        () async {
          final callable = _functions.httpsCallable('setInstitutionMode');
          return callable.call<Map<String, dynamic>>({
            'mode': mode,
            if (examType != null) 'examType': examType,
          });
        },
      );
      if (response == null) return;

      if (!mounted) return;

      final message = switch (mode) {
        'closed' => 'Kurum bugün kapalı moda alındı.',
        'exam' => 'Deneme modu başlatıldı.',
        _ => 'Kurum normal programa döndü.',
      };

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_messageWithCancelledCount(message, response.data))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Kurum durumu güncellenemedi: ${_institutionActionErrorMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _confirmClosedMode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF071A3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Kurumu bugün kapatmak istiyor musunuz?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Yeni zümre ve etüt işlemleri başlatılmayacaktır. Sistem yarın otomatik olarak normal programa dönecektir.',
          style: TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: const Color(0xFF071A3A),
            ),
            child: const Text('Bugün Kapat'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _setInstitutionMode('closed');
    }
  }

  Future<TimeOfDay?> _showDigitalTimePicker({
    required TimeOfDay initialTime,
  }) async {
    final hourController = TextEditingController(
      text: initialTime.hour.toString().padLeft(2, '0'),
    );
    final minuteController = TextEditingController(
      text: initialTime.minute.toString().padLeft(2, '0'),
    );
    String? errorText;

    final result = await showDialog<TimeOfDay>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final hour = int.tryParse(hourController.text.trim());
              final minute = int.tryParse(minuteController.text.trim());

              if (hour == null ||
                  minute == null ||
                  hour < 0 ||
                  hour > 23 ||
                  minute < 0 ||
                  minute > 59) {
                setDialogState(() {
                  errorText = 'Geçerli bir saat girin.';
                });
                return;
              }

              Navigator.pop(ctx, TimeOfDay(hour: hour, minute: minute));
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF071A3A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text(
                'Saat Gir',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: hourController,
                          autofocus: true,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            hintText: '15',
                            hintStyle: TextStyle(color: Colors.white30),
                          ),
                          onSubmitted: (_) => submit(),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          ':',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: minuteController,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            hintText: '06',
                            hintStyle: TextStyle(color: Colors.white30),
                          ),
                          onSubmitted: (_) => submit(),
                        ),
                      ),
                    ],
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: submit,
                  child: const Text('Tamam'),
                ),
              ],
            );
          },
        );
      },
    );

    hourController.dispose();
    minuteController.dispose();
    return result;
  }

  Future<void> _showExamModeDialog({
    String initialType = 'tyt',
    DateTime? initialStart,
    String? examId,
  }) async {
    var selectedType = initialType.toLowerCase() == 'ayt' ? 'ayt' : 'tyt';
    DateTime? scheduledDateTime = initialStart;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final minutes = selectedType == 'tyt' ? 165 : 180;
            final estimatedEnd = DateTime.now().add(Duration(minutes: minutes));
            final plannedEnd =
                scheduledDateTime?.add(Duration(minutes: minutes));
            final canPlan = scheduledDateTime != null &&
                scheduledDateTime!.isAfter(DateTime.now());

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 430),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF071A3A),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Deneme Modu',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
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
                    const Text(
                      'Deneme Türü',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'tyt', label: Text('TYT')),
                        ButtonSegment(value: 'ayt', label: Text('AYT')),
                      ],
                      selected: {selectedType},
                      onSelectionChanged: (value) {
                        setDialogState(() => selectedType = value.first);
                      },
                    ),
                    const SizedBox(height: 16),
                    _adminInfoCard(
                      icon: Icons.timer_rounded,
                      title: selectedType == 'tyt'
                          ? 'TYT • 165 dakika'
                          : 'AYT • 180 dakika',
                      subtitle:
                          'Başlangıç: Şimdi · ${_formatClock(DateTime.now())}\nTahmini bitiş: ${_formatClock(estimatedEnd)}',
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: scheduledDateTime ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 30)),
                        );
                        if (pickedDate == null) return;
                        if (!context.mounted) return;
                        final pickedTime = await _showDigitalTimePicker(
                          initialTime: TimeOfDay.fromDateTime(
                            scheduledDateTime ?? DateTime.now(),
                          ),
                        );
                        if (pickedTime == null) return;
                        setDialogState(() {
                          scheduledDateTime = DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            pickedDate.day,
                            pickedTime.hour,
                            pickedTime.minute,
                          );
                        });
                      },
                      icon: const Icon(Icons.edit_calendar_rounded),
                      label: Text(
                        scheduledDateTime == null
                            ? 'Planlı deneme tarihini seç'
                            : '${_formatDisplayDate(scheduledDateTime!)} · ${_formatClock(scheduledDateTime!)}',
                      ),
                    ),
                    if (scheduledDateTime != null && plannedEnd != null) ...[
                      const SizedBox(height: 10),
                      _adminInfoCard(
                        icon: Icons.event_rounded,
                        title: 'Planlı Deneme',
                        subtitle:
                            'Başlangıç: ${_formatDisplayDate(scheduledDateTime!)} · ${_formatClock(scheduledDateTime!)}\nBitiş: ${_formatClock(plannedEnd)}',
                      ),
                    ],
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Vazgeç'),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _setInstitutionMode(
                              'exam',
                              examType: selectedType,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.lightBlueAccent,
                            foregroundColor: const Color(0xFF071A3A),
                          ),
                          child: const Text('Şimdi Başlat'),
                        ),
                        ElevatedButton(
                          onPressed: canPlan
                              ? () async {
                                  Navigator.pop(ctx);
                                  await _createPlannedExam(
                                    examType: selectedType,
                                    scheduledStart: scheduledDateTime!,
                                    examId: examId,
                                  );
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: const Color(0xFF071A3A),
                          ),
                          child: const Text('Denemeyi Planla'),
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

  Future<void> _confirmEndExamEarly() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF071A3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Deneme erken bitirilsin mi?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Sistem normal programa döner. O an aktif zümre veya etüt slotu varsa kalan süre kullanılabilir.',
          style: TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Erken Bitir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _setInstitutionMode('active');
    }
  }

  List<Map<String, dynamic>> _conflictsFromResponse(dynamic data) {
    if (data is! Map) return [];
    final raw = data['conflicts'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _conflictSummaryText(List<Map<String, dynamic>> conflicts) {
    if (conflicts.isEmpty) return 'Etkilenen planlı zümre bulunmuyor.';
    return conflicts.take(6).map((item) {
      return '${item['dateKey']} · ${item['start']}-${item['end']} · ${item['count']} planlı öğrenci';
    }).join('\n');
  }

  Future<bool> _confirmAppointmentCancellations({
    required String title,
    required int count,
    required List<Map<String, dynamic>> conflicts,
    required String reason,
  }) async {
    if (count <= 0) return true;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF071A3A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              '$reason\n\n${_conflictSummaryText(conflicts)}',
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: const Color(0xFF071A3A),
                ),
                child: const Text('Onayla'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _createPlannedExam({
    required String examType,
    required DateTime scheduledStart,
    String? examId,
  }) async {
    try {
      final callable = _functions.httpsCallable('createPlannedExam');
      var response = await _runInstitutionAction(
        'Deneme planlanıyor...',
        () => callable.call<Map<String, dynamic>>({
          'examType': examType,
          'dateKey': _formatIsoDate(scheduledStart),
          'startTime': _formatClock(scheduledStart),
          'scheduledStart': scheduledStart.toIso8601String(),
          if (examId != null) 'examId': examId,
        }),
      );
      if (response == null) return;
      var data = response.data;

      if (data['requiresConfirm'] == true) {
        final conflicts = _conflictsFromResponse(data);
        final confirmed = await _confirmAppointmentCancellations(
          title: 'Planlı zümreler iptal edilecek',
          count: data['conflictCount'] as int? ?? conflicts.length,
          conflicts: conflicts,
          reason:
              'Bu deneme saatine denk gelen planlı zümreler iptal edilecek.',
        );
        if (!confirmed) return;

        response = await _runInstitutionAction(
          'Deneme planlanıyor...',
          () => callable.call<Map<String, dynamic>>({
            'examType': examType,
            'dateKey': _formatIsoDate(scheduledStart),
            'startTime': _formatClock(scheduledStart),
            'scheduledStart': scheduledStart.toIso8601String(),
            'confirm': true,
            if (examId != null) 'examId': examId,
          }),
        );
        if (response == null) return;
        data = response.data;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _messageWithCancelledCount('Deneme planlandı.', data),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deneme planlanamadı: ${_institutionActionErrorMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _cancelPlannedExam([String? examId]) async {
    if (_isChangingInstitutionMode) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF071A3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Planlı deneme iptal edilsin mi?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Henüz başlamamış planlı deneme kaldırılacaktır.',
          style: TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await _runInstitutionAction(
        'Planlı deneme iptal ediliyor...',
        () {
          final callable = _functions.httpsCallable('cancelPlannedExam');
          return callable.call<Map<String, dynamic>>({
            if (examId != null) 'examId': examId,
          });
        },
      );
      if (response == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Planlı deneme iptal edildi.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Planlı deneme iptal edilemedi: ${_institutionActionErrorMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _startPlannedExamNow([String? examId]) async {
    if (_isChangingInstitutionMode) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF071A3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Planlı deneme şimdi başlatılsın mı?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Kurum deneme moduna alınır. O an bekleyen zümre/etüt akışları durdurulur.',
          style: TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.lightBlueAccent,
              foregroundColor: const Color(0xFF071A3A),
            ),
            child: const Text('Şimdi Başlat'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await _runInstitutionAction(
        'Planlı deneme başlatılıyor...',
        () {
          final callable = _functions.httpsCallable('startPlannedExamNow');
          return callable.call<Map<String, dynamic>>({
            if (examId != null) 'examId': examId,
          });
        },
      );
      if (response == null) return;
      final data = response.data;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _messageWithCancelledCount('Planlı deneme başlatıldı.', data),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Planlı deneme başlatılamadı: ${_institutionActionErrorMessage(error)}',
          ),
        ),
      );
    }
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

  Future<void> _requestTeacherReportPdf({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    var selectedLevel = 'LGS';
    final level = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final mobile = MediaQuery.of(context).size.width < 600;
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(
              horizontal: mobile ? 14 : 24,
              vertical: 24,
            ),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 480),
              padding: EdgeInsets.all(mobile ? 18 : 22),
              decoration: BoxDecoration(
                color: const Color(0xFF071A3A),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .28),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.lightBlueAccent.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.groups_2_rounded,
                        color: Colors.lightBlueAccent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Öğretmen Faaliyet Özeti',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Rapor kapsamını seçin',
                            style:
                                TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  Row(
                    children: ['LGS', 'YKS'].map((item) {
                      final selected = selectedLevel == item;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: item == 'LGS' ? 6 : 0,
                            left: item == 'YKS' ? 6 : 0,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () =>
                                setDialogState(() => selectedLevel = item),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: selected
                                    ? Colors.lightBlueAccent
                                        .withValues(alpha: .18)
                                    : Colors.white.withValues(alpha: .06),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selected
                                      ? Colors.lightBlueAccent
                                      : Colors.white12,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Column(children: [
                                Icon(
                                  selected
                                      ? Icons.check_circle_rounded
                                      : Icons.circle_outlined,
                                  color: selected
                                      ? Colors.lightBlueAccent
                                      : Colors.white54,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Seçilen kapsamdaki tüm öğretmenler gösterilir. Faaliyeti olmayan öğretmenler 0 değerleriyle raporda kalır; zümrede çözülen soru ve tamamlanan etüt sayıları ayrı gösterilir.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.lightBlueAccent,
                        foregroundColor: const Color(0xFF071A3A),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, selectedLevel),
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text(
                        'Raporu Oluştur',
                        style: TextStyle(fontWeight: FontWeight.w800),
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
    if (level == null) return;

    await _requestReportPdf(
      endpoint: '/reports/teacher-activity-summary',
      fallbackFileName: '${level}_Ogretmen_Faaliyet_Ozeti.pdf',
      preferredFileName:
          '${level}_Ogretmen_Faaliyet_Ozeti_${_formatIsoDate(startDate)}_${_formatIsoDate(endDate)}.pdf',
      startDate: startDate,
      endDate: endDate,
      educationLevel: level,
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
    String? preferredFileName,
    String? className,
    String? branch,
    String? department,
    String? educationLevel,
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
          if (educationLevel != null && educationLevel.isNotEmpty)
            'educationLevel': educationLevel,
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

      final filename = preferredFileName ??
          _filenameFromContentDisposition(
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
      barrierDismissible: false,
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
                      color: Colors.black.withValues(alpha: 0.30),
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
                              color: Colors.redAccent.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.35),
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
                          color: Colors.white.withValues(alpha: 0.08),
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
                              icon: Icons.badge_rounded,
                              title: 'Öğretmen Faaliyet Özeti',
                              subtitle:
                                  'LGS/YKS bazında tüm öğretmenleri, faaliyet olmasa da listeler',
                              color: Colors.orangeAccent,
                              compact: compact,
                              onTap: () => _requestTeacherReportPdf(
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
      backgroundColor: Colors.white.withValues(alpha: 0.08),
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
          color: Colors.white.withValues(alpha: enabled ? 0.08 : 0.04),
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
      final tomorrowStart = todayStart.add(const Duration(days: 1));

      final todaySnapshot = await _firestore
          .collection('queues')
          .where('status', isEqualTo: 'completed')
          .where(
            'completedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
          )
          .where('completedAt', isLessThan: Timestamp.fromDate(tomorrowStart))
          .count()
          .get();

      if (!mounted) return;

      setState(() {
        _totalSolvedToday = todaySnapshot.count ?? 0;
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

  void _showExcelLoadingDialog({
    int? totalUsers,
    bool isImporting = false,
  }) {
    final message = isImporting && totalUsers != null && totalUsers > 0
        ? '$totalUsers kullanıcı işleniyor, lütfen bekleyin...'
        : 'Excel dosyası okunuyor...\n'
            'Veri yoğunluğuna bağlı olarak bu işlem biraz sürebilir.';

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
          child: Row(
            children: [
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(color: Colors.lightBlueAccent),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white70, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickEdesisFile(String type) async {
    const smartImportBaseUrl =
        'https://zumrenet-smart-import-542741706921.europe-west1.run.app';

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
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
          'includeGuardian': false,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Smart Import analiz hatası: ${response.body}');
      }
      var analyzeData = _parseUtf8JsonResponse(response);

      if (!mounted) return;
      _hideExcelLoadingDialog();

      var includeGuardian = false;
      var mappingOverrides = <String, int>{};

      while (mounted) {
        final selection = await _showImportAnalysisDialog(
          type: type,
          data: analyzeData,
          includeGuardian: includeGuardian,
          mappingOverrides: mappingOverrides,
        );

        if (selection == null) return;

        includeGuardian = selection['includeGuardian'] == true;
        mappingOverrides = Map<String, int>.from(
          selection['mappingOverrides'] ?? const <String, int>{},
        );

        if (selection['action'] == 'import') break;

        _showExcelLoadingDialog();
        final reanalyzeResponse = await http.post(
          Uri.parse('$smartImportBaseUrl/analyze'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'fileBase64': fileBase64,
            'fileName': file.name,
            'type': type,
            'includeGuardian': includeGuardian,
            'mappingOverrides': mappingOverrides,
          }),
        );
        if (reanalyzeResponse.statusCode != 200) {
          throw Exception(
              'Smart Import analiz hatası: ${reanalyzeResponse.body}');
        }
        analyzeData = _parseUtf8JsonResponse(reanalyzeResponse);
        if (!mounted) return;
        _hideExcelLoadingDialog();
      }

      final validRows = List.from(analyzeData['validRows'] ?? []);

      if (validRows.isEmpty) {
        throw Exception('Aktarılacak geçerli kayıt bulunamadı.');
      }

      if (!mounted) return;
      _showExcelLoadingDialog(
        totalUsers: validRows.length,
        isImporting: true,
      );

      final importResponse = await http.post(
        Uri.parse('$smartImportBaseUrl/import'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'type': analyzeData['type'],
          'validRows': validRows,
          'includeGuardian': includeGuardian,
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

  Future<void> _showBulkImportChoiceDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF071A3A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Toplu Kullanıcı Aktarımı',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
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
              const SizedBox(height: 6),
              const Text(
                'Excel dosyası kullanarak öğrenci ve öğretmen hesaplarını yükleyin.',
                style: TextStyle(color: Colors.white60, height: 1.35),
              ),
              const SizedBox(height: 18),
              _quickActionCard(
                icon: Icons.school_rounded,
                title: 'Öğrenci Aktar',
                subtitle: 'Edesis Öğrenci Excel dosyası seçilir',
                color: Colors.orangeAccent,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickEdesisFile('student');
                },
              ),
              const SizedBox(height: 10),
              _quickActionCard(
                icon: Icons.badge_rounded,
                title: 'Öğretmen Aktar',
                subtitle: 'Edesis Öğretmen Excel dosyası seçilir',
                color: Colors.greenAccent,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickEdesisFile('teacher');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _showImportAnalysisDialog({
    required String type,
    required Map<String, dynamic> data,
    required bool includeGuardian,
    required Map<String, int> mappingOverrides,
  }) {
    final preview = List.from(data['preview'] ?? []);
    final ignored = List.from(data['ignoredHeaders'] ?? []);
    final missing = List.from(data['missingFields'] ?? []);
    final invalidPreview = List.from(data['invalidPreview'] ?? []);
    final headers = List.from(data['headers'] ?? []);
    final mappingDetails = List.from(data['mappingDetails'] ?? []);
    final currentMapping = Map<String, dynamic>.from(data['mapping'] ?? {});
    final manualFields = <String>{
      ...missing.map((field) => field.toString()),
      ...mappingDetails
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => item['confidence'] == 'MEDIUM')
          .map((item) => item['field'].toString()),
    };

    if (type == 'student' && includeGuardian) {
      for (final field in const [
        'guardianName',
        'guardianSurname',
        'guardianPhone',
      ]) {
        if (!mappingDetails.any(
          (item) => Map<String, dynamic>.from(item)['field'] == field,
        )) {
          manualFields.add(field);
        }
      }
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
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
                  if (type == 'student') ...[
                    const SizedBox(height: 14),
                    const Text(
                      'İçe Aktarma Türü',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    RadioGroup<bool>(
                      groupValue: includeGuardian,
                      onChanged: (value) => Navigator.pop(ctx, {
                        'action': 'reanalyze',
                        'includeGuardian': value == true,
                        'mappingOverrides': mappingOverrides,
                      }),
                      child: const Column(
                        children: [
                          RadioListTile<bool>(
                            value: false,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            activeColor: Colors.orangeAccent,
                            title: Text(
                              'Sadece Öğrenciler',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          RadioListTile<bool>(
                            value: true,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            activeColor: Colors.orangeAccent,
                            title: Text(
                              'Öğrenciler + Veli Bilgileri',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  _analysisLine('Dosya', '${data['fileName']}'),
                  _analysisLine('Sayfa', '${data['sheetName'] ?? '-'}'),
                  _analysisLine('Başlık satırı', '${data['headerRow'] ?? '-'}'),
                  _analysisLine(
                      'Kontrol gerekli', '${data['reviewCount'] ?? 0}'),
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
                  if (mappingDetails.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Eşleştirilen Alanlar',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...mappingDetails.map((item) {
                      final detail = Map<String, dynamic>.from(item);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '✓ ${_smartImportFieldLabel(detail['field'].toString())} ← ${detail['header']} — ${_smartImportConfidenceLabel(detail['confidence'].toString())}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      );
                    }),
                  ],
                  if (manualFields.isNotEmpty && headers.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Kontrol edilmesi gereken eşleştirmeler',
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...manualFields.map((field) {
                      final mappedIndex = currentMapping[field];
                      final selectedIndex = mappingOverrides[field] ??
                          (mappedIndex is num ? mappedIndex.toInt() : null);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DropdownButtonFormField<int>(
                          initialValue: selectedIndex,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF10264C),
                          decoration: InputDecoration(
                            labelText: _smartImportFieldLabel(field),
                            labelStyle: const TextStyle(color: Colors.white70),
                            enabledBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white38),
                            ),
                          ),
                          style: const TextStyle(color: Colors.white),
                          items: headers.asMap().entries.map((entry) {
                            return DropdownMenuItem<int>(
                              value: entry.key,
                              child: Text(
                                '${entry.value} (Sütun ${entry.key + 1})',
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            final nextOverrides = Map<String, int>.from(
                              mappingOverrides,
                            );
                            nextOverrides[field] = value;
                            Navigator.pop(ctx, {
                              'action': 'reanalyze',
                              'includeGuardian': includeGuardian,
                              'mappingOverrides': nextOverrides,
                            });
                          },
                        ),
                      );
                    }),
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
                      missing
                          .map((field) =>
                              _smartImportFieldLabel(field.toString()))
                          .join(', '),
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
                              ? _smartImportStudentPreviewLine(row)
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
                          onPressed: (data['validCount'] ?? 0) > 0
                              ? () => Navigator.pop(ctx, {
                                    'action': 'import',
                                    'includeGuardian': includeGuardian,
                                    'mappingOverrides': mappingOverrides,
                                  })
                              : null,
                          child: Text(
                            (data['invalidCount'] ?? 0) > 0
                                ? 'Geçerli Kayıtları Aktar'
                                : 'Sunucuya Aktar',
                          ),
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

  String _smartImportFieldLabel(String field) {
    const labels = {
      'name': 'Öğrenci Adı',
      'surname': 'Öğrenci Soyadı',
      'fullName': 'Öğrenci Adı Soyadı',
      'username': 'Kullanıcı Adı',
      'password': 'Şifre',
      'className': 'Sınıf / Şube',
      'branch': 'Şube',
      'department': 'Bölüm',
      'phone': 'Telefon Numarası',
      'subjects': 'Branş',
      'guardianName': 'Veli Adı',
      'guardianSurname': 'Veli Soyadı',
      'guardianPhone': 'Veli Telefon Numarası',
    };
    return labels[field] ?? 'Eşleştirilmemiş Alan';
  }

  String _smartImportConfidenceLabel(String confidence) {
    switch (confidence) {
      case 'EXACT':
        return 'Kesin';
      case 'HIGH':
        return 'Yüksek güven';
      case 'MANUAL':
        return 'Manuel seçildi';
      default:
        return 'Kontrol gerekli';
    }
  }

  String _smartImportStudentPreviewLine(Map<String, dynamic> row) {
    final values = [
      row['fullName']?.toString().trim() ?? '',
      formatStudentClassDisplay(
        className: row['className'],
        branch: row['branch'],
        department: row['department'],
      ),
      row['username']?.toString().trim() ?? '',
    ].where((value) => value.isNotEmpty);

    return values.join(' • ');
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
                  color: Colors.greenAccent.withValues(alpha: 0.16),
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

  Widget _buildPlannedExamSummary() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('settings').doc('plannedExam').snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data == null) {
          return const SizedBox.shrink();
        }

        final items = <Map<String, dynamic>>[];
        final rawItems = data['items'];
        if (rawItems is List) {
          for (final item in rawItems) {
            if (item is Map) {
              items.add(Map<String, dynamic>.from(item));
            }
          }
        } else {
          items.add(data);
        }

        final visibleItems = items.where((item) {
          final status = '${item['status'] ?? ''}';
          final endValue = item['scheduledEnd'];
          final endDate = endValue is Timestamp ? endValue.toDate() : null;
          return (status == 'scheduled' || status == 'active') &&
              (endDate == null || endDate.isAfter(DateTime.now()));
        }).toList()
          ..sort((a, b) {
            final aStart = a['scheduledStart'];
            final bStart = b['scheduledStart'];
            final aDate = aStart is Timestamp ? aStart.toDate() : DateTime(0);
            final bDate = bStart is Timestamp ? bStart.toDate() : DateTime(0);
            return aDate.compareTo(bDate);
          });

        if (visibleItems.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          children: visibleItems.map((item) {
            final status = '${item['status'] ?? ''}';
            final examId = item['id']?.toString();
            final examType = '${item['examType'] ?? ''}'.toUpperCase();
            final startValue = item['scheduledStart'];
            final endValue = item['scheduledEnd'];
            final startDate =
                startValue is Timestamp ? startValue.toDate() : null;
            final endDate = endValue is Timestamp ? endValue.toDate() : null;
            final active = status == 'active';
            final accent = active ? Colors.lightBlueAccent : Colors.amber;
            final title = active ? 'Deneme Devam Ediyor' : 'Planlı Deneme';
            final subtitle = [
              if (examType.isNotEmpty) examType,
              if (startDate != null)
                'Başlangıç: ${_formatDisplayDate(startDate)} · ${_formatClock(startDate)}',
              if (endDate != null) 'Bitiş: ${_formatClock(endDate)}',
            ].join('\n');

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        active
                            ? Icons.assignment_turned_in_rounded
                            : Icons.event_note_rounded,
                        color: accent,
                      ),
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
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white70, height: 1.35),
                  ),
                  if (!active) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              _isChangingInstitutionMode || startDate == null
                                  ? null
                                  : () => _showExamModeDialog(
                                        initialType: examType,
                                        initialStart: startDate,
                                        examId: examId,
                                      ),
                          icon: const Icon(Icons.edit_calendar_rounded),
                          label: const Text('Düzenle'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isChangingInstitutionMode
                              ? null
                              : () => _cancelPlannedExam(examId),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('İptal'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isChangingInstitutionMode
                              ? null
                              : () => _startPlannedExamNow(examId),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Şimdi Başlat'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.lightBlueAccent,
                            foregroundColor: const Color(0xFF071A3A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildInstitutionModeCard() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('settings').doc('runtimeState').snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final mode = _institutionModeFromRuntime(data);
        final examType = '${data?['examType'] ?? ''}'.toUpperCase();
        final examEndsAt = data?['examEndsAt'];
        final examEndDate =
            examEndsAt is Timestamp ? examEndsAt.toDate() : null;
        final remaining = examEndDate?.difference(DateTime.now());

        final accent = switch (mode) {
          'closed' => Colors.orangeAccent,
          'exam' => Colors.lightBlueAccent,
          _ => Colors.greenAccent,
        };
        final title = switch (mode) {
          'closed' => 'Kurum Kapalı',
          'exam' => 'Deneme Devam Ediyor',
          _ => 'Kurum Aktif',
        };
        final subtitle = switch (mode) {
          'closed' =>
            'Bugün zümre ve etüt işlemleri durduruldu. Yarın sistem normal programa döner.',
          'exam' =>
            '$examType • Bitiş: ${examEndDate == null ? '-' : _formatClock(examEndDate)}\n${remaining == null ? '' : _formatRemaining(remaining)}',
          _ =>
            'Normal çalışma düzeni aktif. Zümre ve etüt mevcut programa göre çalışır.',
        };

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: _adminGlassDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.domain_rounded, color: accent, size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Kurum Durumu',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                      ),
                    ),
                  ),
                  if (_isChangingInstitutionMode)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(
                  color: accent,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'active',
                      icon: Icon(Icons.play_circle_rounded),
                      label: Text('Aktif'),
                    ),
                    ButtonSegment(
                      value: 'closed',
                      icon: Icon(Icons.pause_circle_rounded),
                      label: Text('Kapalı'),
                    ),
                    ButtonSegment(
                      value: 'exam',
                      icon: Icon(Icons.assignment_rounded),
                      label: FittedBox(child: Text('Deneme')),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: _isChangingInstitutionMode
                      ? null
                      : (selection) async {
                          final selected = selection.first;
                          if (selected == mode) return;
                          if (selected == 'closed') {
                            await _confirmClosedMode();
                          } else if (selected == 'exam') {
                            await _showExamModeDialog();
                          } else {
                            await _setInstitutionMode('active');
                          }
                        },
                ),
              ),
              if (mode == 'closed' || mode == 'exam') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isChangingInstitutionMode
                        ? null
                        : mode == 'exam'
                            ? _confirmEndExamEarly
                            : () => _setInstitutionMode('active'),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(
                      mode == 'exam'
                          ? 'Denemeyi Erken Bitir'
                          : 'Tekrar Aktif Yap',
                    ),
                  ),
                ),
              ],
              _buildPlannedExamSummary(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTodayStatusSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('queues')
          .where('status', whereIn: ['waiting', 'in_progress']).snapshots(),
      builder: (context, queueSnapshot) {
        final queues = queueSnapshot.data?.docs ?? [];
        final waiting =
            queues.where((doc) => doc.data()['status'] == 'waiting').length;
        final inProgress =
            queues.where((doc) => doc.data()['status'] == 'in_progress').length;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestore
              .collection('studySessions')
              .where('status', isEqualTo: 'active')
              .snapshots(),
          builder: (context, studySnapshot) {
            final activeStudyStudents =
                (studySnapshot.data?.docs ?? []).fold<int>(0, (total, doc) {
              final value = doc.data()['activeStudentCount'];
              if (value is int) return total + value;
              if (value is num) return total + value.toInt();
              return total;
            });

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _firestore
                  .collection('users')
                  .where('role', isEqualTo: 'teacher')
                  .snapshots(),
              builder: (context, teacherSnapshot) {
                final availableTeachers = (teacherSnapshot.data?.docs ?? [])
                    .where((doc) => doc.data()['teacherStatus'] == 'available')
                    .length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Bugünkü Durum'),
                    const SizedBox(height: 12),
                    _runtimeSummaryStrip(),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _smallStatusPill(
                          label: 'Zümre',
                          value: 'Bugün $_totalSolvedToday çözüm',
                          color: Colors.greenAccent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount =
                            constraints.maxWidth < 680 ? 2 : 4;
                        return GridView.count(
                          crossAxisCount: crossAxisCount,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio:
                              constraints.maxWidth < 420 ? 2.05 : 4.0,
                          children: [
                            _operationMetricCard(
                              title: 'Bekleyen Öğrenci',
                              value: '$waiting',
                              icon: Icons.hourglass_top_rounded,
                              color: Colors.orangeAccent,
                            ),
                            _operationMetricCard(
                              title: 'Çözümü Devam Eden',
                              value: '$inProgress',
                              icon: Icons.hourglass_bottom_rounded,
                              color: Colors.lightBlueAccent,
                            ),
                            _operationMetricCard(
                              title: 'Etütteki Öğrenci',
                              value: '$activeStudyStudents',
                              icon: Icons.auto_stories_rounded,
                              color: Colors.greenAccent,
                            ),
                            _operationMetricCard(
                              title: 'Müsait Öğretmen',
                              value: '$availableTeachers',
                              icon: Icons.how_to_reg_rounded,
                              color: Colors.purpleAccent,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  bool _scopeZumreIsOpenNow(
    Map<String, dynamic> scheduleData,
    String educationLevel,
  ) {
    final now = DateTime.now();
    final weekly = scheduleData['weeklySchedule'];
    if (weekly is! Map) return false;
    final dayKey = _scheduleDays[now.weekday - 1]['key']!;
    final day = weekly[dayKey];
    if (day is! Map || day['closed'] == true || day['zumreClosed'] == true) {
      return false;
    }

    final nowMinutes = now.hour * 60 + now.minute;
    final rawSlots = day['zumreSlots'];
    if (rawSlots is! List) return false;

    return rawSlots.whereType<Map>().any((slot) {
      if (!institutionScheduleSlotMatchesEducationLevel(
        slot,
        educationLevel,
      )) {
        return false;
      }
      final start = _clockToMinutes('${slot['start'] ?? ''}');
      final end = _clockToMinutes('${slot['end'] ?? ''}');
      return start >= 0 &&
          end > start &&
          nowMinutes >= start &&
          nowMinutes < end;
    });
  }

  bool _scopeStudyIsOpenNow(
    Map<String, dynamic> scheduleData,
    String educationLevel,
  ) {
    final now = DateTime.now();
    final weekly = scheduleData['weeklySchedule'];
    if (weekly is! Map) return false;
    final dayKey = _scheduleDays[now.weekday - 1]['key']!;
    final day = weekly[dayKey];
    if (day is! Map || day['closed'] == true || day['studyClosed'] == true) {
      return false;
    }

    final nowMinutes = now.hour * 60 + now.minute;
    final rawSlots = day['studySlots'];
    if (rawSlots is! List) return false;

    return rawSlots.whereType<Map>().any((slot) {
      if (!institutionScheduleSlotMatchesEducationLevel(
        slot,
        educationLevel,
      )) {
        return false;
      }
      final start = _clockToMinutes('${slot['start'] ?? ''}');
      final end = _clockToMinutes('${slot['end'] ?? ''}');
      return start >= 0 &&
          end > start &&
          nowMinutes >= start &&
          nowMinutes < end;
    });
  }

  Widget _runtimeSummaryStrip() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('settings').doc('runtimeState').snapshots(),
      builder: (context, runtimeSnapshot) {
        final runtimeData = runtimeSnapshot.data?.data() ?? {};
        final mode = _institutionModeFromRuntime(runtimeData);
        final suffix = mode == 'closed'
            ? 'Kurum kapalı'
            : mode == 'exam'
                ? 'Deneme modu'
                : null;

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _firestore
              .collection('settings')
              .doc('zumreSchedule')
              .snapshots(),
          builder: (context, scheduleSnapshot) {
            final scheduleData = scheduleSnapshot.data?.data() ?? {};
            final lgsOpen =
                suffix == null && _scopeZumreIsOpenNow(scheduleData, 'LGS');
            final yksOpen =
                suffix == null && _scopeZumreIsOpenNow(scheduleData, 'YKS');
            final lgsStudyOpen =
                suffix == null && _scopeStudyIsOpenNow(scheduleData, 'LGS');
            final yksStudyOpen =
                suffix == null && _scopeStudyIsOpenNow(scheduleData, 'YKS');

            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _smallStatusPill(
                  label: 'LGS Zümre',
                  value: suffix ?? (lgsOpen ? 'Aktif' : 'Kapalı'),
                  color: lgsOpen ? Colors.greenAccent : Colors.orangeAccent,
                ),
                _smallStatusPill(
                  label: 'YKS Zümre',
                  value: suffix ?? (yksOpen ? 'Aktif' : 'Kapalı'),
                  color: yksOpen ? Colors.greenAccent : Colors.orangeAccent,
                ),
                _smallStatusPill(
                  label: 'LGS Etüt',
                  value: suffix ?? (lgsStudyOpen ? 'Aktif' : 'Kapalı'),
                  color:
                      lgsStudyOpen ? Colors.greenAccent : Colors.orangeAccent,
                ),
                _smallStatusPill(
                  label: 'YKS Etüt',
                  value: suffix ?? (yksStudyOpen ? 'Aktif' : 'Kapalı'),
                  color:
                      yksStudyOpen ? Colors.greenAccent : Colors.orangeAccent,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _smallStatusPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.17),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.42), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle_rounded, color: color, size: 9),
          const SizedBox(width: 8),
          Text(
            '$label: $value',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _operationMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelSection({
    required String title,
    required List<Widget> children,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 680) {
              return Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    children[i],
                    if (i != children.length - 1) const SizedBox(height: 10),
                  ],
                ],
              );
            }

            final cardWidth = (constraints.maxWidth - 12) / 2;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: children
                  .map(
                    (child) => SizedBox(
                      width: cardWidth,
                      child: child,
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadStats,
          triggerMode: RefreshIndicatorTriggerMode.onEdge,
          displacement: 56,
          edgeOffset: 8,
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : ListView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                  children: [
                    _buildInstitutionModeCard(),
                    const SizedBox(height: 18),
                    _buildTodayStatusSection(),
                    const SizedBox(height: 18),
                    _panelSection(
                      title: 'Hızlı İşlemler',
                      children: [
                        _quickActionCard(
                          icon: Icons.manage_search_rounded,
                          title: 'Kullanıcı Takibi',
                          subtitle: 'Öğrencileri ve kullanıcı kayıtlarını aç',
                          color: Colors.greenAccent,
                          onTap: widget.onOpenUsers ?? () {},
                        ),
                        _quickActionCard(
                          icon: Icons.picture_as_pdf_rounded,
                          title: 'Rapor Merkezi',
                          subtitle: 'Kurum ve sınıf PDF raporları oluşturulur',
                          color: Colors.redAccent,
                          onTap: _showPdfReportDialog,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _panelSection(
                      title: 'Kurum İşleyişi',
                      children: [
                        _quickActionCard(
                          icon: Icons.schedule_rounded,
                          title: 'Zaman Yönetimi',
                          subtitle:
                              'Zümre, etüt ve öğle arası vakitleri ayarlanır',
                          color: Colors.purpleAccent,
                          onTap: _showZumreScheduleDialog,
                        ),
                        _quickActionCard(
                          icon: Icons.upload_file_rounded,
                          title: 'Toplu Kullanıcı Aktarımı',
                          subtitle:
                              'Excel dosyası kullanarak öğrenci ve öğretmen hesaplarını toplu yönetin.',
                          color: Colors.orangeAccent,
                          onTap: () => _showBulkImportChoiceDialog(),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        if (_isImporting)
          Container(
            color: Colors.black.withValues(alpha: 0.45),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }

  BoxDecoration _adminGlassDecoration() {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.16),
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

    _weeklyScheduleDraft
      ..clear()
      ..addAll(_weeklyScheduleFromData(doc.data() ?? {}));

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var isSaving = false;
        var scopeFilter = 'YKS';
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
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Zaman Yönetimi',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
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
                      const SizedBox(height: 6),
                      const Text(
                        'LGS ve YKS için ayrı ayrı zümre ve etüt saatleri oluşturun.',
                        style: TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        scopeFilter == 'LGS'
                            ? 'LGS saatlerini düzenliyorsunuz.'
                            : 'YKS saatlerini düzenliyorsunuz.',
                        style: const TextStyle(
                          color: Colors.lightBlueAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ['LGS', 'LGS'],
                          ['YKS', 'YKS'],
                        ]
                            .map(
                              (item) => ChoiceChip(
                                label: Text(item[1]),
                                selected: scopeFilter == item[0],
                                onSelected: (_) => setDialogState(
                                  () => scopeFilter = item[0],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 10),
                      ..._scheduleDays.map(
                        (day) => _dailyScheduleTile(
                          dayKey: day['key']!,
                          dayLabel: day['label']!,
                          scopeFilter: scopeFilter,
                          setDialogState: setDialogState,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed:
                                  isSaving ? null : () => Navigator.pop(ctx),
                              child: const Text('Vazgeç'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      final validationError =
                                          _validateWeeklySchedule();
                                      if (validationError != null) {
                                        ScaffoldMessenger.of(this.context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(validationError)),
                                        );
                                        return;
                                      }

                                      final weeklySchedule =
                                          _weeklyScheduleForFirestore();
                                      setDialogState(() => isSaving = true);

                                      try {
                                        final callable =
                                            _functions.httpsCallable(
                                          'applyZumreScheduleChange',
                                        );
                                        var response = await callable.call({
                                          'weeklySchedule': weeklySchedule,
                                        });
                                        var data = Map<String, dynamic>.from(
                                            response.data as Map);

                                        if (data['requiresConfirm'] == true) {
                                          setDialogState(
                                              () => isSaving = false);
                                          final conflicts =
                                              _conflictsFromResponse(data);
                                          final confirmed =
                                              await _confirmAppointmentCancellations(
                                            title:
                                                'Planlı zümreler iptal edilecek',
                                            count:
                                                data['conflictCount'] as int? ??
                                                    conflicts.length,
                                            conflicts: conflicts,
                                            reason:
                                                'Program değişikliğiyle artık geçerli olmayan planlı zümreler iptal edilecek.',
                                          );
                                          if (!confirmed) return;

                                          if (!ctx.mounted) return;
                                          setDialogState(() => isSaving = true);
                                          response = await callable.call({
                                            'weeklySchedule': weeklySchedule,
                                            'confirm': true,
                                          });
                                          data = Map<String, dynamic>.from(
                                              response.data as Map);
                                        }

                                        if (!mounted) return;
                                        if (ctx.mounted) Navigator.pop(ctx);

                                        ScaffoldMessenger.of(this.context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                _scheduleSavedMessage(data)),
                                          ),
                                        );
                                      } catch (error) {
                                        if (ctx.mounted) {
                                          setDialogState(
                                              () => isSaving = false);
                                        }
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(this.context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Saatler güncellenemedi: ${_institutionActionErrorMessage(error)}',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              child: isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                      ),
                                    )
                                  : const Text('Kaydet'),
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

  List<Map<String, String>> _slotListFromRaw(dynamic raw) {
    if (raw is! List) return [];

    return raw
        .whereType<Map>()
        .map(
          (slot) {
            return {
              'start': '${slot['start'] ?? ''}',
              'end': '${slot['end'] ?? ''}',
              // Ortak tanımlanmış eski slotlar mevcut YKS programıdır.
              // LGS, bundan sonra kendi bağımsız slotlarıyla oluşturulur.
              'educationLevel': institutionScheduleScopeFromData(slot),
            };
          },
        )
        .where((slot) => slot['start']!.isNotEmpty && slot['end']!.isNotEmpty)
        .toList();
  }

  Map<String, Map<String, dynamic>> _weeklyScheduleFromData(
    Map<String, dynamic> data,
  ) {
    final result = <String, Map<String, dynamic>>{};
    final rawWeekly = data['weeklySchedule'];
    final weekdayZumre = _slotListFromRaw(data['weekdaySlots']);
    final weekendZumre = _slotListFromRaw(data['weekendSlots']);
    final weekdayStudy = _slotListFromRaw(data['weekdayStudySlots']);
    final weekendStudy = _slotListFromRaw(data['weekendStudySlots']);

    for (final day in _scheduleDays) {
      final key = day['key']!;
      final rawDay = rawWeekly is Map ? rawWeekly[key] : null;

      if (rawDay is Map) {
        final legacyClosed = rawDay['closed'] == true;
        result[key] = {
          'closed': legacyClosed,
          'zumreClosed': legacyClosed || rawDay['zumreClosed'] == true,
          'studyClosed': legacyClosed || rawDay['studyClosed'] == true,
          'zumreSlots': _slotListFromRaw(rawDay['zumreSlots']),
          'studySlots': _slotListFromRaw(rawDay['studySlots']),
        };
      } else {
        final isWeekendDay = key == 'saturday' || key == 'sunday';
        result[key] = {
          'closed': false,
          'zumreClosed': false,
          'studyClosed': false,
          'zumreSlots': List<Map<String, String>>.from(
            isWeekendDay ? weekendZumre : weekdayZumre,
          ),
          'studySlots': List<Map<String, String>>.from(
            isWeekendDay ? weekendStudy : weekdayStudy,
          ),
        };
      }
    }

    return result;
  }

  Map<String, dynamic> _weeklyScheduleForFirestore() {
    return _weeklyScheduleDraft.map((key, value) {
      final zumreClosed = value['zumreClosed'] == true;
      final studyClosed = value['studyClosed'] == true;
      return MapEntry(key, {
        'closed': zumreClosed && studyClosed,
        'zumreClosed': zumreClosed,
        'studyClosed': studyClosed,
        'zumreSlots': List<Map<String, String>>.from(value['zumreSlots']),
        'studySlots': List<Map<String, String>>.from(value['studySlots']),
      });
    });
  }

  int _clockToMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return -1;

    final hour = int.tryParse(parts[0]) ?? -1;
    final minute = int.tryParse(parts[1]) ?? -1;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return -1;

    return hour * 60 + minute;
  }

  String? _validateWeeklySchedule() {
    for (final day in _scheduleDays) {
      final key = day['key']!;
      final label = day['label']!;
      final config = _weeklyScheduleDraft[key]!;

      for (final entry in [
        MapEntry('Zümre', config['zumreSlots'] as List<Map<String, String>>),
        MapEntry('Etüt', config['studySlots'] as List<Map<String, String>>),
      ]) {
        for (final slot in entry.value) {
          final start = _clockToMinutes(slot['start'] ?? '');
          final end = _clockToMinutes(slot['end'] ?? '');
          if (start < 0 || end < 0 || start >= end) {
            return '$label ${entry.key} saatlerinde başlangıç bitişten önce olmalı.';
          }
          if (!educationLevels.contains(slot['educationLevel'])) {
            return '$label ${entry.key} için LGS veya YKS kapsamı seçilmelidir.';
          }
        }
      }
    }

    return null;
  }

  Widget _scheduleClosedToggle({
    required String label,
    required bool value,
    required Color color,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: value
              ? color.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value ? color.withValues(alpha: 0.65) : Colors.white12,
          ),
        ),
        child: Row(
          children: [
            Icon(
              value
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: value ? color : Colors.white54,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dailyScheduleTile({
    required String dayKey,
    required String dayLabel,
    required String scopeFilter,
    required StateSetter setDialogState,
  }) {
    final day = _weeklyScheduleDraft[dayKey]!;
    final zumreClosed = day['zumreClosed'] == true || day['closed'] == true;
    final studyClosed = day['studyClosed'] == true || day['closed'] == true;
    final zumreSlots = day['zumreSlots'] as List<Map<String, String>>;
    final studySlots = day['studySlots'] as List<Map<String, String>>;
    final visibleZumreSlots = zumreSlots
        .where((slot) => timeSlotMatchesManagementFilter(slot, scopeFilter))
        .length;
    final visibleStudySlots = studySlots
        .where((slot) => timeSlotMatchesManagementFilter(slot, scopeFilter))
        .length;
    final summaryParts = <String>[
      zumreClosed ? 'Zümre kapalı' : '$visibleZumreSlots zümre',
      studyClosed ? 'Etüt kapalı' : '$visibleStudySlots etüt',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: Colors.white70,
          collapsedIconColor: Colors.white60,
          title: Text(
            dayLabel,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            summaryParts.join(' • '),
            style: TextStyle(
              color: (zumreClosed || studyClosed)
                  ? Colors.orangeAccent
                  : Colors.white60,
              fontSize: 12,
            ),
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: _scheduleClosedToggle(
                    label: 'Zümre Kapalı',
                    value: zumreClosed,
                    color: Colors.greenAccent,
                    onChanged: (value) {
                      setDialogState(() {
                        day['closed'] = false;
                        day['zumreClosed'] = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _scheduleClosedToggle(
                    label: 'Etüt Kapalı',
                    value: studyClosed,
                    color: Colors.cyanAccent,
                    onChanged: (value) {
                      setDialogState(() {
                        day['closed'] = false;
                        day['studyClosed'] = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _scheduleSection(
              title: 'Zümre Saatleri',
              slots: zumreSlots,
              color: Colors.greenAccent,
              enabled: !zumreClosed,
              onAdd: () {
                setDialogState(() {
                  zumreSlots.add({
                    'start': '09:00',
                    'end': '09:40',
                    'educationLevel': scopeFilter,
                  });
                });
              },
              onDelete: (index) {
                setDialogState(() => zumreSlots.removeAt(index));
              },
              scopeFilter: scopeFilter,
            ),
            const SizedBox(height: 10),
            _scheduleSection(
              title: 'Etüt Saatleri',
              slots: studySlots,
              color: Colors.cyanAccent,
              enabled: !studyClosed,
              onAdd: () {
                setDialogState(() {
                  studySlots.add({
                    'start': '10:00',
                    'end': '10:45',
                    'educationLevel': scopeFilter,
                  });
                });
              },
              onDelete: (index) {
                setDialogState(() => studySlots.removeAt(index));
              },
              scopeFilter: scopeFilter,
            ),
          ],
        ),
      ),
    );
  }

  Widget _scheduleSection({
    required String title,
    required List<Map<String, String>> slots,
    required Color color,
    required VoidCallback onAdd,
    required Function(int index) onDelete,
    required String scopeFilter,
    bool enabled = true,
  }) {
    final visibleSlotEntries = slots.asMap().entries.where(
          (entry) =>
              entry.value['educationLevel']?.toUpperCase() == scopeFilter,
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
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
                onPressed: enabled ? onAdd : null,
                icon: Icon(Icons.add_circle, color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (visibleSlotEntries.isEmpty)
            const Text(
              'Bu kademe için henüz saat eklenmedi.',
              style: TextStyle(color: Colors.white60),
            )
          else
            ...visibleSlotEntries.map((entry) {
              final index = entry.key;
              final slot = entry.value;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    Row(
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
                            enabled: enabled,
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
                            enabled: enabled,
                            style: const TextStyle(color: Colors.white),
                            decoration: _timeInputDecoration('Bitiş'),
                            onChanged: (value) => slot['end'] = value,
                          ),
                        ),
                        IconButton(
                          onPressed: enabled ? () => onDelete(index) : null,
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
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
      fillColor: Colors.white.withValues(alpha: 0.08),
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
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.all(16),
        decoration: _adminGlassDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 29),
            const SizedBox(height: 11),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
                                    Colors.white.withValues(alpha: 0.42),
                                    Colors.white.withValues(alpha: 0.18),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.lightBlueAccent
                                        .withValues(alpha: 0.35),
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
                ? Colors.orangeAccent.withValues(alpha: 0.14)
                : Colors.lightBlueAccent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _showSubjectDetail
                  ? Colors.orangeAccent.withValues(alpha: 0.30)
                  : Colors.lightBlueAccent.withValues(alpha: 0.30),
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

class _StudentFieldOptions {
  const _StudentFieldOptions({
    required this.classNames,
    required this.branches,
    required this.departments,
  });

  final List<String> classNames;
  final List<String> branches;
  final List<String> departments;
}

String _autocompleteSearchKey(String value) => value
    .trim()
    .replaceAll('İ', 'I')
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ş', 's')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c');

class _EditableAutocompleteField extends StatelessWidget {
  const _EditableAutocompleteField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: value),
      optionsBuilder: (textEditingValue) {
        final query = _autocompleteSearchKey(textEditingValue.text);
        if (query.isEmpty) return options;
        return options.where(
          (option) => _autocompleteSearchKey(option).contains(query),
        );
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: label),
          textCapitalization: TextCapitalization.words,
          onChanged: onChanged,
        );
      },
    );
  }
}

class _UserManagementPageState extends State<UserManagementPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');
  static const int _bulkDeleteClientBatchSize = 50;

  final List<String> _roles = [
    'admin',
    'teacher',
    'student',
    'guidance',
    'studyGuard'
  ];
  String _roleLabel(String role) {
    switch (role.trim()) {
      case 'admin':
        return 'Yönetici';
      case 'teacher':
        return 'Öğretmen';
      case 'student':
        return 'Öğrenci';
      case 'guidance':
        return 'Rehberlikçi';
      case 'studyGuard':
        return 'Etüt Görevlisi';
      default:
        return role;
    }
  }

  bool _isLoading = false;
  bool _isBulkDeleting = false;
  int _bulkDeleteProcessed = 0;
  int _bulkDeleteTotal = 0;
  String _userSearchQuery = '';
  String _userRoleFilter = 'all';
  String? _userEducationLevelFilter;
  String? _userClassNameFilter;
  String? _userBranchFilter;
  String? _userDepartmentFilter;
  String? _userSubjectFilter;
  final Set<String> _selectedUserIds = {};

  Future<_StudentFieldOptions> _loadStudentFieldOptions() async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .get();
      final classNames = <String, String>{};
      final branches = <String, String>{};
      final departments = <String, String>{};

      void addValue(Map<String, String> values, Object? value) {
        final text = value?.toString().trim() ?? '';
        if (text.isEmpty) return;
        values.putIfAbsent(_autocompleteSearchKey(text), () => text);
      }

      for (final doc in snapshot.docs) {
        final data = doc.data();
        addValue(classNames, data['className']);
        addValue(branches, data['branch']);
        addValue(departments, data['department']);
      }

      List<String> sortedValues(Map<String, String> values) {
        final result = values.values.toList()..sort();
        return result;
      }

      return _StudentFieldOptions(
        classNames: sortedValues(classNames),
        branches: sortedValues(branches),
        departments: sortedValues(departments),
      );
    } catch (_) {
      return const _StudentFieldOptions(
        classNames: [],
        branches: [],
        departments: [],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<QuerySnapshot>(
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
            final allUserData = allUsers
                .map((doc) => doc.data() as Map<String, dynamic>)
                .toList();
            final guidanceNamesById = <String, String>{
              for (final doc in allUsers)
                if ((doc.data() as Map<String, dynamic>)['role'] == 'guidance')
                  doc.id:
                      '${(doc.data() as Map<String, dynamic>)['fullName'] ?? (doc.data() as Map<String, dynamic>)['name'] ?? 'Rehberlik Servisi'}',
            };
            final filters = UserManagementFilters(
              role: _userRoleFilter,
              search: _userSearchQuery,
              educationLevel: _userEducationLevelFilter,
              className: _userClassNameFilter,
              branch: _userBranchFilter,
              department: _userDepartmentFilter,
              subject: _userSubjectFilter,
            );
            final users = allUsers
                .where(
                  (doc) => userMatchesManagementFilters(
                    doc.data() as Map<String, dynamic>,
                    filters,
                  ),
                )
                .toList();

            final roleCounts = <String, int>{'all': allUsers.length};
            for (final userDoc in allUsers) {
              final userData = userDoc.data() as Map<String, dynamic>;
              final userRole = (userData['role'] ?? '').toString();
              roleCounts[userRole] = (roleCounts[userRole] ?? 0) + 1;
            }

            final studentUsers =
                allUserData.where((data) => data['role'] == 'student');
            final teacherUsers =
                allUserData.where((data) => data['role'] == 'teacher');
            final studentClassNames =
                distinctUserValues(studentUsers, (data) => data['className']);
            final studentBranches =
                distinctUserValues(studentUsers, (data) => data['branch']);
            final studentDepartments =
                distinctUserValues(studentUsers, (data) => data['department']);
            final cascadingStudentOptions = cascadingStudentFilterOptions(
              studentUsers,
              filters,
            );
            final teacherSubjects = distinctTeacherSubjects(teacherUsers);

            final currentUid = FirebaseAuth.instance.currentUser?.uid;
            final selectableUids = users
                .map((doc) => doc.id)
                .where((uid) => uid != currentUid)
                .toList();
            final selectedVisibleCount =
                selectableUids.where(_selectedUserIds.contains).length;
            final allVisibleSelected = selectableUids.isNotEmpty &&
                selectedVisibleCount == selectableUids.length;
            final selectedCount = _selectedUserIds.length;
            return CustomScrollView(
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: _isBulkDeleting ? null : () => _showUserDialog(),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.person_add_alt_1,
                              color: Colors.greenAccent,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Yeni Kullanıcı Ekle',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right, color: Colors.white54),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Kullanıcı ara...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.10),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _userSearchQuery = value.trim();
                        });
                      },
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          ['all', 'Tümü'],
                          ['student', 'Öğrenciler'],
                          ['teacher', 'Öğretmenler'],
                          ['guidance', 'Rehberlik'],
                          ['studyGuard', 'Etüt'],
                          ['admin', 'Yönetici'],
                        ].map((item) {
                          final key = item[0];
                          final selected = _userRoleFilter == key;
                          final count = roleCounts[key] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              selected: selected,
                              showCheckmark: false,
                              onSelected: (_) => setState(() {
                                _userRoleFilter = key;
                                _clearUserDynamicFilters();
                                _selectedUserIds.clear();
                              }),
                              label: Text('${item[1]}  $count'),
                              labelStyle: TextStyle(
                                color: selected
                                    ? const Color(0xFF071A3A)
                                    : Colors.white,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                              selectedColor: const Color(0xFF7DD3FC),
                              backgroundColor: const Color(0xFF173B73),
                              elevation: selected ? 3 : 0,
                              pressElevation: 0,
                              side: BorderSide(
                                color: selected
                                    ? const Color(0xFFB8ECFF)
                                    : const Color(0xFF5A87C8),
                                width: selected ? 1.4 : 1,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                if (_userRoleFilter == 'student' ||
                    _userRoleFilter == 'teacher')
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: _userDynamicFilterPanel(
                        role: _userRoleFilter,
                        classNames: _userRoleFilter == 'student'
                            ? cascadingStudentOptions.classNames
                            : studentClassNames,
                        branches: _userRoleFilter == 'student'
                            ? cascadingStudentOptions.branches
                            : studentBranches,
                        departments: _userRoleFilter == 'student'
                            ? cascadingStudentOptions.departments
                            : studentDepartments,
                        teacherSubjects: teacherSubjects,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _bulkSelectionBar(
                    selectedCount: selectedCount,
                    visibleCount: selectableUids.length,
                    progressCount: _bulkDeleteProcessed,
                    progressTotal: _bulkDeleteTotal,
                    allVisibleSelected: allVisibleSelected,
                    onSelectAllChanged: _isBulkDeleting
                        ? null
                        : (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedUserIds.addAll(selectableUids);
                              } else {
                                _selectedUserIds.removeAll(selectableUids);
                              }
                            });
                          },
                    onDeleteSelected:
                        selectedCount == 0 || _isBulkDeleting || _isLoading
                            ? null
                            : () => _bulkDeleteUsers(allUsers),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final doc = users[index];
                        final data = doc.data() as Map<String, dynamic>;

                        final uid = doc.id;
                        final role = data['role'] ?? '?';
                        final name = data['fullName'] ??
                            data['name'] ??
                            data['email'] ??
                            'İsimsiz';
                        final email = data['email'] ?? 'Email yok';
                        final guidanceCounselorId =
                            data['guidanceCounselorId']?.toString().trim() ??
                                '';
                        final guidanceCounselorName =
                            guidanceCounselorId.isEmpty
                                ? null
                                : guidanceNamesById[guidanceCounselorId] ??
                                    'Atanmış rehberlikçi';
                        final roleColor = role == 'admin'
                            ? Colors.redAccent
                            : role == 'teacher'
                                ? Colors.lightBlueAccent
                                : Colors.greenAccent;
                        final canSelect = uid != currentUid &&
                            !_isBulkDeleting &&
                            !_isLoading;
                        final isSelected = _selectedUserIds.contains(uid);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.redAccent.withValues(alpha: 0.45)
                                  : Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: isSelected,
                                onChanged: canSelect
                                    ? (checked) {
                                        setState(() {
                                          if (checked == true) {
                                            _selectedUserIds.add(uid);
                                          } else {
                                            _selectedUserIds.remove(uid);
                                          }
                                        });
                                      }
                                    : null,
                                activeColor: Colors.redAccent,
                                checkColor: Colors.white,
                                side: const BorderSide(
                                  color: Colors.white54,
                                  width: 1.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$name',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15.5,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '$email',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Wrap(
                                      spacing: 7,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          _roleLabel(role),
                                          style: TextStyle(
                                            color: roleColor,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (role == 'student' &&
                                            ((data['className'] ?? '').toString().isNotEmpty ||
                                                (data['branch'] ?? '')
                                                    .toString()
                                                    .isNotEmpty ||
                                                (data['department'] ?? '')
                                                    .toString()
                                                    .isNotEmpty))
                                          Text(
                                            formatStudentClassDisplay(
                                              className: data['className'],
                                              branch: data['branch'],
                                              department: data['department'],
                                            ),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        if (role == 'teacher' &&
                                            teachingScopesFromData(data)
                                                .isNotEmpty)
                                          Text(
                                            teachingScopesFromData(data)
                                                .map((scope) =>
                                                    '${scope['level']} • ${scope['subject']}')
                                                .join('\n'),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          )
                                        else if (role == 'teacher' &&
                                            data['subjects'] is List &&
                                            (data['subjects'] as List)
                                                .isNotEmpty)
                                          Text(
                                            (data['subjects'] as List)
                                                .map((v) => v.toString())
                                                .join(' • '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        if (role == 'student' &&
                                            guidanceCounselorName != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.purpleAccent
                                                  .withValues(alpha: 0.14),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Colors.purpleAccent
                                                    .withValues(alpha: 0.42),
                                              ),
                                            ),
                                            child: Text(
                                              'Rehber: $guidanceCounselorName',
                                              style: const TextStyle(
                                                color: Colors.purpleAccent,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          )
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.white70,
                                ),
                                onPressed: _isBulkDeleting
                                    ? null
                                    : () => _editUser(uid, data),
                              ),
                              if (role == 'guidance')
                                IconButton(
                                  tooltip: 'Atanmış öğrenciler',
                                  icon: const Icon(
                                    Icons.groups_rounded,
                                    color: Colors.lightBlueAccent,
                                  ),
                                  onPressed: _isBulkDeleting
                                      ? null
                                      : () => _showGuidanceCounselorStudents(
                                            uid,
                                            data,
                                          ),
                                ),
                              if (role == 'guidance')
                                IconButton(
                                  tooltip: 'Veli görüşme saatleri',
                                  icon: const Icon(
                                    Icons.event_available_rounded,
                                    color: Colors.amberAccent,
                                  ),
                                  onPressed: _isBulkDeleting
                                      ? null
                                      : () => _showGuidanceAvailabilityDialog(
                                            uid,
                                            data,
                                          ),
                                ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                ),
                                onPressed: _isBulkDeleting
                                    ? null
                                    : () => _deleteUser(uid, email),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: users.length,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (_isLoading)
          Container(
            color: Colors.black.withValues(alpha: 0.45),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }

  void _clearUserDynamicFilters() {
    _userEducationLevelFilter = null;
    _userClassNameFilter = null;
    _userBranchFilter = null;
    _userDepartmentFilter = null;
    _userSubjectFilter = null;
  }

  Widget _userFilterDropdown({
    required String label,
    required List<String> values,
    required String? selectedValue,
    required ValueChanged<String?> onChanged,
  }) {
    final value = values.contains(selectedValue) ? selectedValue : null;
    final selected = value != null;
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        dropdownColor: const Color(0xFF10264C),
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: selected ? const Color(0xFFB8ECFF) : Colors.white70,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          filled: true,
          fillColor: selected
              ? const Color(0xFF1F5D91)
              : const Color(0xFF10264C).withValues(alpha: 0.72),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color:
                  selected ? const Color(0xFF8EDBFF) : const Color(0xFF4D78B5),
              width: selected ? 1.4 : 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.lightBlueAccent),
          ),
        ),
        items: [
          DropdownMenuItem<String>(
            value: null,
            child: Text('Tüm $label', overflow: TextOverflow.ellipsis),
          ),
          ...values.map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(item, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _userDynamicFilterPanel({
    required String role,
    required List<String> classNames,
    required List<String> branches,
    required List<String> departments,
    required List<String> teacherSubjects,
  }) {
    final student = role == 'student';
    final hasFilters = _userEducationLevelFilter != null ||
        _userClassNameFilter != null ||
        _userBranchFilter != null ||
        _userDepartmentFilter != null ||
        _userSubjectFilter != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  student ? 'Öğrenci filtreleri' : 'Öğretmen filtreleri',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hasFilters)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _clearUserDynamicFilters();
                    _selectedUserIds.clear();
                  }),
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  label: const Text('Temizle'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.lightBlueAccent,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _userFilterDropdown(
                label: 'Kademe',
                values: educationLevels.toList()..sort(),
                selectedValue: _userEducationLevelFilter,
                onChanged: (value) => setState(() {
                  _userEducationLevelFilter = value;
                  if (student) {
                    _userClassNameFilter = null;
                    _userBranchFilter = null;
                    _userDepartmentFilter = null;
                  }
                  _selectedUserIds.clear();
                }),
              ),
              if (student) ...[
                _userFilterDropdown(
                  label: 'Sınıf',
                  values: classNames,
                  selectedValue: _userClassNameFilter,
                  onChanged: (value) => setState(() {
                    _userClassNameFilter = value;
                    _userBranchFilter = null;
                    _userDepartmentFilter = null;
                    _selectedUserIds.clear();
                  }),
                ),
                _userFilterDropdown(
                  label: 'Şube',
                  values: branches,
                  selectedValue: _userBranchFilter,
                  onChanged: (value) => setState(() {
                    _userBranchFilter = value;
                    _userDepartmentFilter = null;
                    _selectedUserIds.clear();
                  }),
                ),
                _userFilterDropdown(
                  label: 'Alan / Bölüm',
                  values: departments,
                  selectedValue: _userDepartmentFilter,
                  onChanged: (value) => setState(() {
                    _userDepartmentFilter = value;
                    _selectedUserIds.clear();
                  }),
                ),
              ] else
                _userFilterDropdown(
                  label: 'Branş',
                  values: teacherSubjects,
                  selectedValue: _userSubjectFilter,
                  onChanged: (value) => setState(() {
                    _userSubjectFilter = value;
                    _selectedUserIds.clear();
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bulkSelectionBar({
    required int selectedCount,
    required int visibleCount,
    required int progressCount,
    required int progressTotal,
    required bool allVisibleSelected,
    required ValueChanged<bool?>? onSelectAllChanged,
    required VoidCallback? onDeleteSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 460;
            final selectAll = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: allVisibleSelected,
                  onChanged: visibleCount == 0 ? null : onSelectAllChanged,
                  activeColor: Colors.lightBlueAccent,
                  checkColor: const Color(0xFF071A3A),
                  side: const BorderSide(color: Colors.white54, width: 1.5),
                ),
                const Text(
                  'Tümünü Seç',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            );
            final countText = Text(
              _isBulkDeleting
                  ? '$progressCount / $progressTotal kullanıcı işlendi'
                  : selectedCount > 0
                      ? '$selectedCount kullanıcı seçili'
                      : 'Toplu işlem için kullanıcı seçin',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            );
            final deleteButton = ElevatedButton.icon(
              onPressed: onDeleteSelected,
              icon: _isBulkDeleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delete_sweep_rounded, size: 18),
              label: Text(
                _isBulkDeleting ? 'Siliniyor...' : 'Seçilenleri Sil',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.12),
                disabledForegroundColor: Colors.white38,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            );
            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: selectAll),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: countText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  deleteButton,
                ],
              );
            }

            return Row(
              children: [
                selectAll,
                const SizedBox(width: 10),
                countText,
                const Spacer(),
                deleteButton,
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showUserDialog({
    String? editingUid,
    Map<String, dynamic>? existingData,
  }) async {
    final studentFieldOptions = await _loadStudentFieldOptions();
    final guidanceSnapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'guidance')
        .get();
    if (!mounted) return;
    final guidanceCounselors = guidanceSnapshot.docs;
    final isEditing = editingUid != null;
    final formKey = GlobalKey<FormState>();
    const String domain = '@bilimkalesi.com';

    String email = existingData?['email'] ?? '';
    String password = '';
    String newPassword = '';
    bool showPassword = false;
    bool showNewPassword = false;
    bool isUserDialogSaving = false;

    String firstName = existingData?['name']?.toString() ?? '';
    String surname = existingData?['surname']?.toString() ?? '';

    String className = existingData?['className']?.toString() ?? '';
    String branch = existingData?['branch']?.toString() ?? '';
    String department = existingData?['department']?.toString() ?? '';
    String guardianName = existingData?['guardianName']?.toString() ?? '';
    String guardianSurname = existingData?['guardianSurname']?.toString() ?? '';
    String guardianPhone = existingData?['guardianPhone']?.toString() ?? '';
    String? guidanceCounselorId =
        existingData?['guidanceCounselorId']?.toString().trim();
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
    final selectedEducationLevels = <String>{};
    final selectedScopeSubjects = <String, String>{};
    for (final scope in teachingScopesFromData(existingData ?? {})) {
      final level = scope['level']!;
      selectedEducationLevels.add(level);
      selectedScopeSubjects[level] = scope['subject']!;
    }
    String? studentEducationLevel =
        validEducationLevel(existingData?['educationLevel']);
    final selectedStudyEducationLevels =
        educationLevelsFromData(existingData ?? {}).toSet();
    if (role == 'studyGuard' && selectedStudyEducationLevels.isEmpty) {
      // Legacy study guards were institution-wide before educationLevels.
      selectedStudyEducationLevels.addAll(educationLevels);
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
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
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Theme(
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
                        fillColor: Colors.white.withValues(alpha: 0.08),
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isEditing
                                    ? 'Kullanıcı Düzenle'
                                    : 'Yeni Kullanıcı Ekle',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
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
                                      decoration: InputDecoration(
                                        labelText: 'Şifre',
                                        suffixIcon: IconButton(
                                          tooltip: showPassword
                                              ? 'Şifreyi gizle'
                                              : 'Şifreyi göster',
                                          onPressed: () {
                                            setStateDialog(() {
                                              showPassword = !showPassword;
                                            });
                                          },
                                          icon: Icon(
                                            showPassword
                                                ? Icons.visibility_off_rounded
                                                : Icons.visibility_rounded,
                                          ),
                                        ),
                                      ),
                                      obscureText: !showPassword,
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
                                      decoration: InputDecoration(
                                        labelText: 'Yeni Şifre',
                                        helperText:
                                            'Boş bırakırsanız şifre değişmez',
                                        suffixIcon: IconButton(
                                          tooltip: showNewPassword
                                              ? 'Şifreyi gizle'
                                              : 'Şifreyi göster',
                                          onPressed: () {
                                            setStateDialog(() {
                                              showNewPassword =
                                                  !showNewPassword;
                                            });
                                          },
                                          icon: Icon(
                                            showNewPassword
                                                ? Icons.visibility_off_rounded
                                                : Icons.visibility_rounded,
                                          ),
                                        ),
                                      ),
                                      obscureText: !showNewPassword,
                                      onChanged: (val) => newPassword = val,
                                      validator: (val) {
                                        if (val == null || val.isEmpty) {
                                          return null;
                                        }
                                        if (val.length < 6) {
                                          return 'Şifre en az 6 karakter olmalı';
                                        }
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
                                    textCapitalization:
                                        TextCapitalization.words,
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
                                    textCapitalization:
                                        TextCapitalization.words,
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
                                    initialValue: role,
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
                                    _EditableAutocompleteField(
                                      label: 'Sınıf',
                                      value: className,
                                      options: studentFieldOptions.classNames,
                                      onChanged: (val) =>
                                          className = val.trim(),
                                    ),
                                    const SizedBox(height: 8),
                                    _EditableAutocompleteField(
                                      label: 'Şube',
                                      value: branch,
                                      options: studentFieldOptions.branches,
                                      onChanged: (val) => branch = val.trim(),
                                    ),
                                    const SizedBox(height: 8),
                                    _EditableAutocompleteField(
                                      label: 'Alan / Bölüm',
                                      value: department,
                                      options: studentFieldOptions.departments,
                                      onChanged: (val) =>
                                          department = val.trim(),
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      initialValue: guardianName,
                                      decoration: const InputDecoration(
                                          labelText: 'Veli Adı'),
                                      onChanged: (val) =>
                                          guardianName = val.trim(),
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      initialValue: guardianSurname,
                                      decoration: const InputDecoration(
                                          labelText: 'Veli Soyadı'),
                                      onChanged: (val) =>
                                          guardianSurname = val.trim(),
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      initialValue: guardianPhone,
                                      keyboardType: TextInputType.phone,
                                      decoration: const InputDecoration(
                                          labelText: 'Veli Telefon Numarası'),
                                      onChanged: (val) =>
                                          guardianPhone = val.trim(),
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      initialValue: guidanceCounselors.any(
                                        (doc) => doc.id == guidanceCounselorId,
                                      )
                                          ? guidanceCounselorId
                                          : null,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Rehber Öğretmen',
                                        helperText:
                                            'Veli randevusu için öğrencinin rehber öğretmeni seçilir.',
                                      ),
                                      items: [
                                        const DropdownMenuItem<String>(
                                          value: null,
                                          child: Text('Henüz atanmadı'),
                                        ),
                                        ...guidanceCounselors.map(
                                          (doc) => DropdownMenuItem<String>(
                                            value: doc.id,
                                            child: Text(
                                              '${doc.data()['fullName'] ?? doc.data()['name'] ?? 'Rehberlik Servisi'}',
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: (value) => setStateDialog(
                                        () => guidanceCounselorId = value,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      initialValue: studentEducationLevel,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'Eğitim Kademesi (opsiyonel)',
                                      ),
                                      items: [
                                        const DropdownMenuItem<String>(
                                          value: null,
                                          child:
                                              Text('Sınıftan otomatik belirle'),
                                        ),
                                        ...educationLevels.map(
                                          (level) => DropdownMenuItem(
                                            value: level,
                                            child: Text(level),
                                          ),
                                        ),
                                      ],
                                      onChanged: (value) => setStateDialog(
                                        () => studentEducationLevel = value,
                                      ),
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
                                          Wrap(
                                            spacing: 8,
                                            children: educationLevels
                                                .map((level) => FilterChip(
                                                      label: Text(level),
                                                      selected:
                                                          selectedEducationLevels
                                                              .contains(level),
                                                      onSelected: (selected) =>
                                                          setStateDialog(() {
                                                        if (selected) {
                                                          selectedEducationLevels
                                                              .add(level);
                                                          selectedScopeSubjects.putIfAbsent(
                                                              level,
                                                              () => (level ==
                                                                          'LGS'
                                                                      ? lgsSubjects
                                                                      : yksSubjects)
                                                                  .first);
                                                        } else {
                                                          selectedEducationLevels
                                                              .remove(level);
                                                          selectedScopeSubjects
                                                              .remove(level);
                                                        }
                                                        selectedSubjects
                                                          ..clear()
                                                          ..addAll(
                                                              selectedScopeSubjects
                                                                  .values
                                                                  .toSet());
                                                      }),
                                                    ))
                                                .toList(),
                                          ),
                                          ...selectedEducationLevels
                                              .map((level) {
                                            final subjects = level == 'LGS'
                                                ? lgsSubjects
                                                : yksSubjects;
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 8),
                                              child: DropdownButtonFormField<
                                                  String>(
                                                initialValue:
                                                    selectedScopeSubjects[
                                                        level],
                                                decoration: InputDecoration(
                                                    labelText: '$level Branşı'),
                                                items: subjects
                                                    .map((subject) =>
                                                        DropdownMenuItem(
                                                          value: subject,
                                                          child: Text(subject),
                                                        ))
                                                    .toList(),
                                                onChanged: (subject) {
                                                  if (subject == null) return;
                                                  setStateDialog(() {
                                                    selectedScopeSubjects[
                                                        level] = subject;
                                                    selectedSubjects
                                                      ..clear()
                                                      ..addAll(
                                                          selectedScopeSubjects
                                                              .values
                                                              .toSet());
                                                  });
                                                },
                                              ),
                                            );
                                          }),
                                          if (selectedEducationLevels.isEmpty)
                                            const Padding(
                                              padding: EdgeInsets.only(top: 8),
                                              child: Text(
                                                'Eski öğretmen kayıtları kademesiz olarak çalışmaya devam eder.',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (role == 'studyGuard') ...[
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
                                            'Etüt Kapsamı',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            'Görevlinin takip edeceği etüt programını seçin.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white60,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            children: educationLevels
                                                .map(
                                                  (level) => FilterChip(
                                                    label: Text(level),
                                                    selected:
                                                        selectedStudyEducationLevels
                                                            .contains(level),
                                                    onSelected: (selected) =>
                                                        setStateDialog(() {
                                                      if (selected) {
                                                        selectedStudyEducationLevels
                                                            .add(level);
                                                      } else {
                                                        selectedStudyEducationLevels
                                                            .remove(level);
                                                      }
                                                    }),
                                                  ),
                                                )
                                                .toList(),
                                          ),
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                onPressed: () async {
                                  if (!formKey.currentState!.validate()) return;

                                  final teachingScopes = selectedEducationLevels
                                      .map((level) => {
                                            'level': level,
                                            'subject':
                                                selectedScopeSubjects[level],
                                          })
                                      .where(
                                          (scope) => scope['subject'] != null)
                                      .toList();
                                  if (!isEditing &&
                                      role == 'teacher' &&
                                      teachingScopes.isEmpty) {
                                    ScaffoldMessenger.of(this.context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Öğretmen için en az bir kademe ve branş seçin.'),
                                      ),
                                    );
                                    return;
                                  }
                                  if (role == 'studyGuard' &&
                                      selectedStudyEducationLevels.isEmpty) {
                                    ScaffoldMessenger.of(this.context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Etüt görevlisi için LGS veya YKS kapsamı seçin.'),
                                      ),
                                    );
                                    return;
                                  }

                                  setStateDialog(() {
                                    isUserDialogSaving = true;
                                  });
                                  try {
                                    final cleanFirstName = firstName
                                        .replaceAll(RegExp(r'\s+'), ' ')
                                        .trim();

                                    final cleanSurname = surname
                                        .replaceAll(RegExp(r'\s+'), ' ')
                                        .trim();

                                    final fullName =
                                        '$cleanFirstName $cleanSurname'
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
                                        educationLevel: studentEducationLevel,
                                        educationLevels: role == 'studyGuard'
                                            ? selectedStudyEducationLevels
                                                .toList()
                                            : selectedEducationLevels.toList(),
                                        teachingScopes: teachingScopes,
                                        guardianName: guardianName,
                                        guardianSurname: guardianSurname,
                                        guardianPhone: guardianPhone,
                                        guidanceCounselorId:
                                            guidanceCounselorId,
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
                                        educationLevel: studentEducationLevel,
                                        educationLevels: role == 'studyGuard'
                                            ? selectedStudyEducationLevels
                                                .toList()
                                            : selectedEducationLevels.toList(),
                                        teachingScopes: teachingScopes,
                                        guardianName: guardianName,
                                        guardianSurname: guardianSurname,
                                        guardianPhone: guardianPhone,
                                        guidanceCounselorId:
                                            guidanceCounselorId,
                                      );
                                    }
                                    if (ctx.mounted) Navigator.pop(ctx);

                                    if (!mounted) return;
                                    ScaffoldMessenger.of(this.context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          isEditing
                                              ? 'Kullanıcı güncellendi'
                                              : 'Kullanıcı oluşturuldu',
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      setStateDialog(() {
                                        isUserDialogSaving = false;
                                      });
                                    }
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(this.context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Hata: ${_adminFunctionErrorMessage(e)}',
                                        ),
                                      ),
                                    );
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
                  if (isUserDialogSaving)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF071A3A).withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
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
    String department, {
    String? educationLevel,
    List<String> educationLevels = const [],
    List<Map<String, String?>> teachingScopes = const [],
    String guardianName = '',
    String guardianSurname = '',
    String guardianPhone = '',
    String? guidanceCounselorId,
  }) async {
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
      if (educationLevel != null) 'educationLevel': educationLevel,
      if (educationLevels.isNotEmpty) 'educationLevels': educationLevels,
      if (teachingScopes.isNotEmpty) 'teachingScopes': teachingScopes,
      'guardianName': guardianName,
      'guardianSurname': guardianSurname,
      'guardianPhone': guardianPhone,
      'guidanceCounselorId': guidanceCounselorId ?? '',
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
    String department, {
    String? educationLevel,
    List<String> educationLevels = const [],
    List<Map<String, String?>> teachingScopes = const [],
    String guardianName = '',
    String guardianSurname = '',
    String guardianPhone = '',
    String? guidanceCounselorId,
  }) async {
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
      if (educationLevel != null) 'educationLevel': educationLevel,
      if (educationLevels.isNotEmpty) 'educationLevels': educationLevels,
      if (teachingScopes.isNotEmpty) 'teachingScopes': teachingScopes,
      'guardianName': guardianName,
      'guardianSurname': guardianSurname,
      'guardianPhone': guardianPhone,
      'guidanceCounselorId': guidanceCounselorId ?? '',
    });
  }

  Future<void> _bulkDeleteUsers(
    List<QueryDocumentSnapshot<Object?>> visibleUsers,
  ) async {
    final visibleSelectedUsers =
        visibleUsers.where((doc) => _selectedUserIds.contains(doc.id)).toList();

    if (visibleSelectedUsers.isEmpty) return;

    final confirmed = await _showBulkDeleteConfirmDialog(visibleSelectedUsers);

    if (confirmed != true) return;
    if (!mounted) return;

    final selectedUids = visibleSelectedUsers.map((doc) => doc.id).toList();
    final allResults = <Map<String, dynamic>>[];
    var deletedCount = 0;
    var skippedCount = 0;
    var failedCount = 0;
    var completedRequestCount = 0;
    Object? batchError;

    setState(() {
      _isBulkDeleting = true;
      _bulkDeleteProcessed = 0;
      _bulkDeleteTotal = selectedUids.length;
    });

    try {
      final callable = _functions.httpsCallable('adminBulkDeleteUsers');

      for (var start = 0;
          start < selectedUids.length;
          start += _bulkDeleteClientBatchSize) {
        final batchUids =
            selectedUids.skip(start).take(_bulkDeleteClientBatchSize).toList();

        try {
          final response = await callable.call({
            'targetUids': batchUids,
          });
          final batchData = Map<String, dynamic>.from(response.data as Map);
          final batchResults = _bulkResultItems(batchData);

          allResults.addAll(batchResults);
          deletedCount += _bulkResultInt(batchData, 'deletedCount');
          skippedCount += _bulkResultInt(batchData, 'skippedCount');
          failedCount += _bulkResultInt(batchData, 'failedCount');
          completedRequestCount += 1;

          if (!mounted) return;

          final processed = allResults.length;
          final deletedIds = batchResults
              .where((item) => item['status'] == 'deleted')
              .map((item) => '${item['uid']}')
              .toSet();

          setState(() {
            _bulkDeleteProcessed = processed;
            _selectedUserIds.removeAll(deletedIds);
          });
        } catch (e) {
          batchError = e;
          break;
        }
      }

      if (!mounted) return;

      final deletedIds = allResults
          .where((item) => item['status'] == 'deleted')
          .map((item) => '${item['uid']}')
          .toSet();

      setState(() {
        _selectedUserIds.removeAll(deletedIds);
      });

      final aggregateData = {
        'requestedCount': selectedUids.length,
        'deletedCount': deletedCount,
        'skippedCount': skippedCount,
        'failedCount': failedCount,
        'completedRequestCount': completedRequestCount,
        'totalRequestCount':
            (selectedUids.length / _bulkDeleteClientBatchSize).ceil(),
        'results': allResults,
      };

      if (batchError != null) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${allResults.length} / ${selectedUids.length} kullanıcı işlendi. '
              'Kalan seçimleri tekrar deneyin: '
              '${_adminFunctionErrorMessage(batchError)}',
            ),
          ),
        );
      }

      await _showBulkDeleteResultDialog(aggregateData);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Toplu silme tamamlanamadı: ${_adminFunctionErrorMessage(e)}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBulkDeleting = false;
          _bulkDeleteProcessed = 0;
          _bulkDeleteTotal = 0;
        });
      }
    }
  }

  Future<bool?> _showBulkDeleteConfirmDialog(
    List<QueryDocumentSnapshot<Object?>> selectedUsers,
  ) {
    final preview = selectedUsers.take(6).map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return _userDisplayName(doc.id, data);
    }).toList();
    final extraCount = selectedUsers.length - preview.length;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF071A3A),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_sweep_rounded,
                      color: Colors.redAccent,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Seçilen Kullanıcıları Sil',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '${selectedUsers.length} kullanıcı için Firebase Auth hesabı ve users kaydı silinecek. Tamamlanan geçmiş kayıtlar korunur.',
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final name in preview)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (extraCount > 0)
                      Text(
                        '+$extraCount kullanıcı daha',
                        style: const TextStyle(color: Colors.white60),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
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
                      child: const Text('Sil'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showBulkDeleteResultDialog(Map<String, dynamic> data) {
    final results = _bulkResultItems(data);
    final detailItems =
        results.where((item) => item['status'] != 'deleted').take(12).toList();

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 620),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF071A3A),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Toplu Silme Sonucu',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
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
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _bulkResultChip(
                    '${_bulkResultInt(data, 'deletedCount')} silindi',
                    Colors.greenAccent,
                  ),
                  _bulkResultChip(
                    '${_bulkResultInt(data, 'skippedCount')} atlandı',
                    Colors.orangeAccent,
                  ),
                  _bulkResultChip(
                    '${_bulkResultInt(data, 'failedCount')} hata',
                    Colors.redAccent,
                  ),
                ],
              ),
              if (detailItems.isNotEmpty) ...[
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: detailItems.length,
                    separatorBuilder: (_, __) => const Divider(
                      color: Colors.white12,
                      height: 14,
                    ),
                    itemBuilder: (context, index) {
                      final item = detailItems[index];
                      final status = '${item['status']}';
                      final color = status == 'skipped'
                          ? Colors.orangeAccent
                          : Colors.redAccent;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            status == 'skipped'
                                ? Icons.info_outline_rounded
                                : Icons.error_outline_rounded,
                            color: color,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${item['name']} - ${item['reason']}',
                              style: const TextStyle(
                                color: Colors.white70,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightBlueAccent,
                  foregroundColor: const Color(0xFF071A3A),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text('Tamam'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bulkResultChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _bulkResultItems(Map<String, dynamic> data) {
    final rawResults = data['results'];

    if (rawResults is! List) return [];

    return rawResults
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  int _bulkResultInt(Map<String, dynamic> data, String key) {
    final value = data[key];

    if (value is int) return value;
    if (value is num) return value.toInt();

    return 0;
  }

  String _userDisplayName(String uid, Map<String, dynamic> data) {
    final fullName = '${data['fullName'] ?? ''}'.trim();
    final email = '${data['email'] ?? ''}'.trim();
    final username = '${data['username'] ?? ''}'.trim();

    return fullName.isNotEmpty
        ? fullName
        : email.isNotEmpty
            ? email
            : username.isNotEmpty
                ? username
                : uid;
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
                  color: Colors.redAccent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.35)),
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcı hesabı silindi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Silme hatası: ${_adminFunctionErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showGuidanceCounselorAssignment(
    String studentId,
    Map<String, dynamic> student,
  ) async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'guidance')
        .get();
    if (!mounted) return;
    final counselors = snapshot.docs;
    if (counselors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Atanabilecek rehberlikçi bulunamadı.'),
      ));
      return;
    }
    var selected = student['guidanceCounselorId']?.toString();
    if (!counselors.any((doc) => doc.id == selected)) selected = null;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rehberlikçi Ata'),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Rehber öğretmen'),
            items: counselors
                .map((doc) => DropdownMenuItem(
                      value: doc.id,
                      child: Text(
                          '${doc.data()['fullName'] ?? doc.data()['name'] ?? 'Rehberlik Servisi'}'),
                    ))
                .toList(),
            onChanged: (value) => setDialogState(() => selected = value),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: selected == null
                    ? null
                    : () async {
                        await _functions
                            .httpsCallable('adminAssignGuidanceCounselor')
                            .call({
                          'counselorId': selected,
                          'studentIds': [studentId],
                        });
                        if (context.mounted) Navigator.pop(context);
                      },
                child: const Text('Ata')),
          ],
        ),
      ),
    );
  }

  bool _isValidGuidanceAvailabilityRange(String rawStart, String rawEnd) {
    int asMinutes(String value) {
      final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value.trim());
      if (match == null) return -1;
      final hour = int.tryParse(match.group(1)!) ?? 24;
      final minute = int.tryParse(match.group(2)!) ?? 60;
      if (hour > 23 || minute > 59) return -1;
      return hour * 60 + minute;
    }

    final start = asMinutes(rawStart);
    final end = asMinutes(rawEnd);
    return start >= 0 && end > start;
  }

  Future<void> _showGuidanceAvailabilityDialog(
    String counselorId,
    Map<String, dynamic> data,
  ) async {
    const days = [
      ['monday', 'Pazartesi'],
      ['tuesday', 'Salı'],
      ['wednesday', 'Çarşamba'],
      ['thursday', 'Perşembe'],
      ['friday', 'Cuma'],
      ['saturday', 'Cumartesi'],
      ['sunday', 'Pazar'],
    ];
    final raw = Map<String, dynamic>.from(data['guidanceAvailability'] ?? {});
    final weekly = Map<String, dynamic>.from(raw['weekly'] ?? {});
    final originalSlots = <String, List<Map<String, String>>>{};
    for (final day in days) {
      originalSlots[day[0]] = (weekly[day[0]] as List? ?? const [])
          .whereType<Map>()
          .map((slot) => {
                'start': '${slot['start'] ?? ''}',
                'end': '${slot['end'] ?? ''}',
              })
          .toList();
    }
    final selected = <String, Map<String, String>?>{
      for (final day in days)
        day[0]: originalSlots[day[0]]!.isEmpty
            ? null
            : Map<String, String>.from(originalSlots[day[0]]!.first),
    };
    var slotMinutes = (raw['slotMinutes'] as num?)?.toInt() ?? 20;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          backgroundColor: const Color(0xFF0B234B),
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: const BorderSide(color: Color(0xFF4D78B5)),
          ),
          title: const Text('Veli Görüşme Saatleri',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Görüşme yapılacak günleri açın ve başlangıç/bitiş saatlerini seçin. Kapalı günlerde veli randevusu oluşturulmaz.',
                    style: TextStyle(color: Colors.white70, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  ...days.map((day) {
                    final slot = selected[day[0]];
                    final enabled = slot != null;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 9),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: LayoutBuilder(
                        builder: (context, rowConstraints) {
                          final mobile = rowConstraints.maxWidth < 390;
                          Widget timeField(String key, String hint) {
                            return TextFormField(
                              initialValue: slot?[key],
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                                _TimeTextInputFormatter(),
                              ],
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: hint,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                                enabledBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white24),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Color(0xFF8EDBFF)),
                                ),
                              ),
                              onChanged: (value) => slot?[key] = value,
                            );
                          }

                          final switchAndDay = Row(
                            mainAxisSize:
                                mobile ? MainAxisSize.max : MainAxisSize.min,
                            children: [
                              Switch(
                                value: enabled,
                                onChanged: (value) => setDialogState(() {
                                  selected[day[0]] = value
                                      ? {'start': '13:00', 'end': '17:50'}
                                      : null;
                                }),
                              ),
                              if (mobile)
                                Expanded(
                                  child: Text(
                                    day[1],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              else
                                SizedBox(
                                  width: 82,
                                  child: Text(
                                    day[1],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              if (mobile && !enabled)
                                const Text(
                                  'Kurumda değil',
                                  style: TextStyle(color: Colors.white54),
                                ),
                            ],
                          );

                          final timeFields = Row(
                            children: [
                              Expanded(child: timeField('start', '08:30')),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white54,
                                  size: 18,
                                ),
                              ),
                              Expanded(child: timeField('end', '17:30')),
                            ],
                          );

                          if (mobile) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                switchAndDay,
                                if (enabled) ...[
                                  const SizedBox(height: 8),
                                  timeFields,
                                ],
                              ],
                            );
                          }

                          return Row(
                            children: [
                              switchAndDay,
                              if (enabled)
                                Expanded(child: timeFields)
                              else
                                const Expanded(
                                  child: Text(
                                    'Kurumda değil',
                                    textAlign: TextAlign.end,
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int>(
                    initialValue:
                        [15, 20, 30].contains(slotMinutes) ? slotMinutes : 20,
                    dropdownColor: const Color(0xFF10264C),
                    iconEnabledColor: const Color(0xFFB8ECFF),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Randevu süresi',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4D78B5))),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF8EDBFF))),
                    ),
                    items: const [15, 20, 30]
                        .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value dakika',
                                style: const TextStyle(color: Colors.white))))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => slotMinutes = value ?? 20),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () async {
                final weeklyPayload = <String, List<Map<String, String>>>{};
                for (final day in days) {
                  final slot = selected[day[0]];
                  if (slot != null &&
                      !_isValidGuidanceAvailabilityRange(
                        slot['start'] ?? '',
                        slot['end'] ?? '',
                      )) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${day[1]} için başlangıç ve bitiş saatlerini HH:mm biçiminde kontrol edin.',
                        ),
                      ),
                    );
                    return;
                  }
                  weeklyPayload[day[0]] = slot == null
                      ? <Map<String, String>>[]
                      : [
                          slot,
                          ...originalSlots[day[0]]!.skip(1),
                        ];
                }
                try {
                  await _functions
                      .httpsCallable('saveGuidanceAvailability')
                      .call({
                    'counselorId': counselorId,
                    'guidanceAvailability': {
                      'weekly': weeklyPayload,
                      'closedDates': const <String>[],
                      'slotMinutes': slotMinutes,
                    },
                  });
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                          content: Text(_adminFunctionErrorMessage(error))),
                    );
                  }
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7DD3FC),
                foregroundColor: const Color(0xFF071A3A),
              ),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGuidanceCounselorStudents(
    String counselorId,
    Map<String, dynamic> counselor,
  ) async {
    final counselorName =
        '${counselor['fullName'] ?? counselor['name'] ?? 'Rehberlikçi'}';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0B234B),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: Color(0xFF4D78B5)),
        ),
        title: Text(
          '$counselorName • Öğrenciler',
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 540,
          height: 520,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _firestore
                .collection('users')
                .where('role', isEqualTo: 'student')
                .where('guidanceCounselorId', isEqualTo: counselorId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final students = snapshot.data!.docs
                  .map((doc) => {...doc.data(), '_id': doc.id})
                  .toList();
              final groups = groupGuidanceStudents(students);
              if (groups.isEmpty) {
                return const Center(
                  child: Text(
                    'Atanmış öğrenci bulunmuyor.',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _firestore
                    .collection('guidanceTasks')
                    .where('counselorId', isEqualTo: counselorId)
                    .snapshots(),
                builder: (context, tasksSnapshot) {
                  final activeStudentIds =
                      (tasksSnapshot.data?.docs ?? const [])
                          .where((task) => task.data()['active'] != false)
                          .map((task) => task.data()['studentId']?.toString())
                          .whereType<String>()
                          .toSet();
                  return ListView(
                    children: groups
                        .map((group) => ExpansionTile(
                              collapsedTextColor: Colors.white,
                              textColor: const Color(0xFF8EDBFF),
                              iconColor: const Color(0xFF8EDBFF),
                              collapsedIconColor: Colors.white70,
                              title: Text(group.label),
                              subtitle: Text(
                                '${group.students.length} öğrenci',
                                style: const TextStyle(color: Colors.white60),
                              ),
                              children: group.students
                                  .map((student) => ListTile(
                                        title:
                                            Text(guidanceStudentName(student)),
                                        subtitle: Text(
                                          activeStudentIds
                                                  .contains(student['_id'])
                                              ? 'Haftalık takip aktif'
                                              : 'Aktif haftalık takip yok',
                                          style: const TextStyle(
                                            color: Colors.white60,
                                          ),
                                        ),
                                        trailing: IconButton(
                                          tooltip: 'Rehber öğretmeni değiştir',
                                          icon: const Icon(
                                              Icons.assignment_ind_rounded),
                                          onPressed: () =>
                                              _showGuidanceCounselorAssignment(
                                            student['_id']?.toString() ?? '',
                                            student,
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ))
                        .toList(),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB8ECFF),
            ),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  void _editUser(String uid, Map<String, dynamic> data) {
    _showUserDialog(editingUid: uid, existingData: data);
  }
}
