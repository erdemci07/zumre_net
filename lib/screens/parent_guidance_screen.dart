import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/appointment_time_groups.dart';

class ParentGuidanceScreen extends StatefulWidget {
  const ParentGuidanceScreen({super.key});

  @override
  State<ParentGuidanceScreen> createState() => _ParentGuidanceScreenState();
}

class _ParentGuidanceScreenState extends State<ParentGuidanceScreen> {
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  String? _sessionToken,
      _challengeId,
      _studentName,
      _counselorName,
      _date,
      _time;
  List<String> _slots = const [];
  List<Map<String, dynamic>> _availableDates = const [];
  List<Map<String, dynamic>> _existingAppointments = const [];
  List<Map<String, dynamic>> _searchResults = const [];
  String? _selectionToken,
      _maskedPhone,
      _studentClassLabel,
      _editingAppointmentId;
  int _step = 0;
  bool _loading = false;
  bool _availabilityLoadFailed = false;
  bool _resultWasReschedule = false;
  String? _entryMode;

  @override
  void dispose() {
    _username.dispose();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  String _shortDateLabel(DateTime value) {
    const weekdays = ['Paz', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt'];
    const months = [
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
    ];
    return '${value.day} ${months[value.month - 1]}\n${weekdays[value.weekday % 7]}';
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await action();
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message ?? 'İşlem tamamlanamadı.')));
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message.toString())),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('İşlem tamamlanamadı. Lütfen tekrar deneyin.')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _search(String value) => _run(() async {
        if (value.trim().length < 3) {
          setState(() => _searchResults = const []);
          return;
        }
        final result = await _functions
            .httpsCallable('publicGuidanceSearchStudents')
            .call({'query': value});
        final data = Map<String, dynamic>.from(result.data as Map);
        setState(() => _searchResults = (data['results'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList());
      });

  Future<void> _selectStudent(Map<String, dynamic> result) => _run(() async {
        final token = result['selectionToken'] as String?;
        final response = await _functions
            .httpsCallable('publicGuidanceSelectStudent')
            .call({'selectionToken': token});
        final data = Map<String, dynamic>.from(response.data as Map);
        if (data['hasGuardianPhone'] != true) {
          throw StateError(
              'Bu öğrenci için kayıtlı veli telefonu bulunamadı. Lütfen kurumla iletişime geçin.');
        }
        setState(() {
          _selectionToken = token;
          _studentName = result['studentName'] as String?;
          _studentClassLabel = result['classLabel'] as String?;
          _maskedPhone = data['maskedPhone'] as String?;
          _searchResults = const [];
        });
      });

  Future<void> _verify() => _run(() async {
        if (!RegExp(r'^\d{10}$').hasMatch(_phone.text)) {
          throw StateError('Telefon numarası tam 10 rakam olmalıdır.');
        }
        final result = await _functions
            .httpsCallable('publicGuidanceVerifySelectedPhone')
            .call({
          'selectionToken': _selectionToken,
          'guardianPhone': _phone.text
        });
        final data = Map<String, dynamic>.from(result.data as Map);
        final existingResult = await _functions
            .httpsCallable('publicGuidanceExistingAppointments')
            .call({'sessionToken': data['sessionToken']});
        final existingData =
            Map<String, dynamic>.from(existingResult.data as Map);
        final existingAppointments =
            (existingData['appointments'] as List? ?? const [])
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
        var availableDates = <Map<String, dynamic>>[];
        var availabilityLoadFailed = false;
        try {
          final availabilityResult = await _functions
              .httpsCallable('publicGuidanceAvailableDates')
              .call({'sessionToken': data['sessionToken']});
          final availabilityData =
              Map<String, dynamic>.from(availabilityResult.data as Map);
          availableDates = (availabilityData['dates'] as List? ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        } catch (_) {
          availabilityLoadFailed = true;
        }
        setState(() {
          _sessionToken = data['sessionToken'] as String?;
          _studentName = data['studentName'] as String?;
          _counselorName = data['counselorName'] as String?;
          _existingAppointments = existingAppointments;
          _availableDates = availableDates;
          _availabilityLoadFailed = availabilityLoadFailed;
          if (_entryMode != 'manage' && existingAppointments.isEmpty) {
            _date = availableDates.isEmpty
                ? null
                : availableDates.first['date']?.toString();
            _slots = availableDates.isEmpty
                ? const []
                : List<String>.from(availableDates.first['slots'] ?? const []);
          }
          _step = _entryMode == 'manage'
              ? 1
              : existingAppointments.isEmpty
                  ? 2
                  : 1;
        });
      });

  Future<void> _loadSlots(String date) => _run(() async {
        final result = await _functions
            .httpsCallable('publicGuidanceAvailableSlots')
            .call({'sessionToken': _sessionToken, 'date': date});
        final data = Map<String, dynamic>.from(result.data as Map);
        setState(() {
          _date = date;
          _time = null;
          _slots = List<String>.from(data['slots'] ?? const []);
        });
      });

  Future<void> _requestOtp() => _run(() async {
        final result = await _functions
            .httpsCallable('publicGuidanceRequestOtp')
            .call(
                {'sessionToken': _sessionToken, 'date': _date, 'time': _time});
        final data = Map<String, dynamic>.from(result.data as Map);
        if (data['phoneMatchFallback'] == true) {
          final booking = await _functions
              .httpsCallable('publicGuidanceConfirmPhoneMatchedBooking')
              .call({
            'sessionToken': _sessionToken,
            'date': _date,
            'time': _time,
          });
          final bookingData = Map<String, dynamic>.from(booking.data as Map);
          setState(() {
            _studentName = bookingData['studentName'] as String?;
            _counselorName = bookingData['counselorName'] as String?;
            _date = bookingData['date'] as String?;
            _time = bookingData['time'] as String?;
            _step = 5;
          });
          return;
        }
        if (data['deliveryAvailable'] != true) {
          throw StateError(
              'SMS doğrulama servisi şu anda kullanıma açık değil.');
        }
        setState(() {
          _challengeId = data['challengeId'] as String?;
          _step = 4;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  '${data['maskedPhone']} numaralı telefona kod gönderildi.')));
        }
      });

  Future<void> _confirmOtp() => _run(() async {
        final result = await _functions
            .httpsCallable('publicGuidanceConfirmOtp')
            .call({
          'sessionToken': _sessionToken,
          'challengeId': _challengeId,
          'code': _otp.text
        });
        final data = Map<String, dynamic>.from(result.data as Map);
        setState(() {
          _studentName = data['studentName'] as String?;
          _counselorName = data['counselorName'] as String?;
          _date = data['date'] as String?;
          _time = data['time'] as String?;
          _step = 5;
        });
      });

  Future<void> _confirmAppointment() async {
    if (_editingAppointmentId == null) {
      await _requestOtp();
      return;
    }
    await _run(() async {
      final result = await _functions
          .httpsCallable('publicGuidanceRescheduleAppointment')
          .call({
        'sessionToken': _sessionToken,
        'appointmentId': _editingAppointmentId,
        'date': _date,
        'time': _time,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      setState(() {
        _date = data['date'] as String?;
        _time = data['time'] as String?;
        _resultWasReschedule = true;
        _editingAppointmentId = null;
        _step = 5;
      });
    });
  }

  Future<void> _cancelAppointment(Map<String, dynamic> appointment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF102848),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFDCE5F0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Randevuyu iptal et',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${appointment['date'] ?? ''} • ${appointment['time'] ?? ''}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 6),
              const Text(
                'Bu randevu iptal edilecek. Devam edilsin mi?',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      child: const Text('Geri Dön'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      icon: const Icon(Icons.event_busy_rounded),
                      label: const Text('İptal Et'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB54747),
                        foregroundColor: Colors.white,
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
    if (confirmed != true || !mounted) return;

    await _run(() async {
      final id = appointment['id']?.toString() ?? '';
      if (id.isEmpty) throw StateError('Randevu bilgisi bulunamadı.');
      await _functions
          .httpsCallable('publicGuidanceCancelAppointment')
          .call({'sessionToken': _sessionToken, 'appointmentId': id});
      var availableDates = _availableDates;
      var availabilityLoadFailed = false;
      try {
        final availabilityResult = await _functions
            .httpsCallable('publicGuidanceAvailableDates')
            .call({'sessionToken': _sessionToken});
        final availabilityData =
            Map<String, dynamic>.from(availabilityResult.data as Map);
        availableDates = (availabilityData['dates'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      } catch (_) {
        availabilityLoadFailed = true;
      }
      if (!mounted) return;
      setState(() {
        _existingAppointments = _existingAppointments
            .where((item) => item['id']?.toString() != id)
            .toList();
        _availableDates = availableDates;
        _availabilityLoadFailed = availabilityLoadFailed;
        _step = _entryMode == 'manage'
            ? 1
            : _existingAppointments.isEmpty
                ? 2
                : 1;
      });
    });
  }

  Future<void> _startReschedule(Map<String, dynamic> appointment) async {
    final appointmentId = appointment['id']?.toString();
    final sessionToken = _sessionToken;
    if (appointmentId == null ||
        appointmentId.isEmpty ||
        sessionToken == null) {
      return;
    }

    setState(() => _loading = true);
    try {
      final result =
          await _functions.httpsCallable('publicGuidanceAvailableDates').call({
        'sessionToken': sessionToken,
        'appointmentId': appointmentId,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final dates = (data['dates'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _editingAppointmentId = appointmentId;
        _availableDates = dates;
        _availabilityLoadFailed = false;
        _date = dates.isEmpty ? null : dates.first['date']?.toString();
        _time = null;
        _slots = dates.isEmpty
            ? const []
            : List<String>.from(dates.first['slots'] ?? const []);
        _step = 2;
      });
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Uygun saatler yüklenemedi.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Uygun saatler yüklenemedi. Lütfen tekrar deneyin.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startNewAppointment() {
    setState(() {
      _editingAppointmentId = null;
      _date = _availableDates.isEmpty
          ? null
          : _availableDates.first['date']?.toString();
      _time = null;
      _slots = _availableDates.isEmpty
          ? const []
          : List<String>.from(_availableDates.first['slots'] ?? const []);
      _step = 2;
    });
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF236AAC),
            brightness: Brightness.light,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            labelStyle: TextStyle(color: Color(0xFF35516F)),
            hintStyle: TextStyle(color: Color(0xFF788A9D)),
          ),
        ),
        child: Scaffold(
          backgroundColor: const Color(0xFFF4F7FB),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = constraints.maxWidth < 520 ? 18.0 : 34.0;
                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                        horizontal: horizontal, vertical: 28),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Container(
                        padding: EdgeInsets.all(
                            constraints.maxWidth < 400 ? 20 : 30),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: const Color(0xFFDCE5F0)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x160D2855),
                              blurRadius: 32,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('BİLİM KALESİ',
                                style: TextStyle(
                                  color: Color(0xFF3270B8),
                                  letterSpacing: 1.4,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                )),
                            const SizedBox(height: 8),
                            const Text('Rehberlik Görüşmesi',
                                style: TextStyle(
                                  color: Color(0xFF132D51),
                                  fontSize: 28,
                                  height: 1.1,
                                  fontWeight: FontWeight.w800,
                                )),
                            const SizedBox(height: 7),
                            const Text(
                                'Randevunuzu birkaç adımda oluşturabilirsiniz.',
                                style: TextStyle(color: Color(0xFF62748A))),
                            const SizedBox(height: 24),
                            if (_entryMode != null) ...[
                              _progress(),
                              const SizedBox(height: 30),
                            ],
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: KeyedSubtree(
                                key: ValueKey(_step),
                                child: _entryMode == null
                                    ? _entryChoiceStep()
                                    : _step == 0
                                        ? _verifyStep()
                                        : _step == 1
                                            ? _existingAppointmentStep()
                                            : _step == 2
                                                ? _slotStep()
                                                : _step == 3
                                                    ? _reviewStep()
                                                    : _step == 4
                                                        ? _otpStep()
                                                        : _resultStep(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

  Widget _entryChoiceStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Nasıl devam etmek istersiniz?',
            style: TextStyle(
              color: Color(0xFF132D51),
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => setState(() {
              _entryMode = 'book';
              _step = 0;
            }),
            icon: const Icon(Icons.event_available_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: Text('Randevu Al'),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _entryMode = 'manage';
              _step = 0;
            }),
            icon: const Icon(Icons.edit_calendar_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: Text('Var Olan Randevunuzu Yönetin'),
            ),
          ),
        ],
      );

  Widget _progress() {
    const labels = ['Bilgiler', 'Randevu', 'Son Kontrol', 'Tamamlandı'];
    final current = _step == 0
        ? 0
        : _step == 5
            ? 3
            : _step >= 3
                ? 2
                : 1;
    return Row(
      children: List.generate(labels.length, (index) {
        final active = index <= current;
        return Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              height: 4,
              margin:
                  EdgeInsets.only(right: index == labels.length - 1 ? 0 : 5),
              decoration: BoxDecoration(
                color:
                    active ? const Color(0xFF2E7BC6) : const Color(0xFFE1E8F0),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 7),
            Text(labels[index],
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active
                      ? const Color(0xFF1E568F)
                      : const Color(0xFF8B9AAC),
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                )),
          ]),
        );
      }),
    );
  }

  Widget _verifyStep() => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Öğrencinizi bulun',
                style: TextStyle(
                    color: Color(0xFF132D51),
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Devam etmek için öğrencinin adını yazarak arama yapın.',
                style: TextStyle(color: Color(0xFF62748A))),
            const SizedBox(height: 18),
            TextField(
                controller: _username,
                decoration: InputDecoration(
                  hintText: 'Öğrenci adı yazın',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF5F8FC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                autocorrect: false,
                onChanged: _search),
            if (_username.text.trim().length >= 3 &&
                _searchResults.isEmpty &&
                !_loading)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text('Eşleşen öğrenci bulunamadı.',
                    style: TextStyle(color: Color(0xFF62748A))),
              ),
            ..._searchResults.map((result) => Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Material(
                    color: const Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _loading ? null : () => _selectStudent(result),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          const Icon(Icons.person_outline_rounded,
                              color: Color(0xFF3270B8)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('${result['studentName']}',
                                    style: const TextStyle(
                                        color: Color(0xFF183656),
                                        fontWeight: FontWeight.w700)),
                                if ('${result['classLabel'] ?? ''}'.isNotEmpty)
                                  Text('${result['classLabel']}',
                                      style: const TextStyle(
                                          color: Color(0xFF62748A),
                                          fontSize: 12)),
                              ])),
                          const Icon(Icons.chevron_right_rounded,
                              color: Color(0xFF62748A)),
                        ]),
                      ),
                    ),
                  ),
                )),
            if (_selectionToken != null)
              Container(
                margin: const EdgeInsets.only(top: 18),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: const Color(0xFFF0F6FC),
                    borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  const Icon(Icons.school_outlined, color: Color(0xFF3270B8)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$_studentName',
                          style: const TextStyle(
                              color: Color(0xFF183656),
                              fontWeight: FontWeight.w700)),
                      if ((_studentClassLabel ?? '').isNotEmpty)
                        Text(_studentClassLabel!,
                            style: const TextStyle(
                                color: Color(0xFF62748A), fontSize: 12)),
                    ],
                  )),
                  TextButton(
                      onPressed: () => setState(() {
                            _selectionToken = null;
                            _maskedPhone = null;
                            _studentClassLabel = null;
                            _sessionToken = null;
                            _existingAppointments = const [];
                            _phone.clear();
                          }),
                      child: const Text('Değiştir')),
                ]),
              ),
            if (_selectionToken != null) const SizedBox(height: 20),
            if (_selectionToken != null) ...[
              const Text('Veli Doğrulaması',
                  style: TextStyle(
                      color: Color(0xFF132D51),
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              const Text(
                  'Sistemde kayıtlı veli telefon numarasını girerek devam edin.',
                  style: TextStyle(color: Color(0xFF62748A))),
              const SizedBox(height: 10),
              Text('Kayıtlı numara: $_maskedPhone',
                  style: const TextStyle(
                      color: Color(0xFF3270B8), fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 12),
            if (_selectionToken != null)
              TextField(
                  controller: _phone,
                  decoration: InputDecoration(
                    labelText: 'Telefon',
                    hintText: '5__ ___ ____',
                    helperText: 'Numarayı başında 0 olmadan giriniz.',
                    filled: true,
                    fillColor: const Color(0xFFF5F8FC),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 10,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ]),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                  onPressed:
                      _loading || _selectionToken == null ? null : _verify,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: const Color(0xFF236AAC)),
                  child: const Text('Devam Et')),
            ),
            Center(
              child: TextButton(
                onPressed:
                    _loading ? null : () => setState(() => _entryMode = null),
                child: const Text('Ana Seçime Dön'),
              ),
            ),
          ]);

  Widget _existingAppointmentStep() {
    if (_existingAppointments.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_busy_rounded,
              color: Color(0xFF62748A), size: 42),
          const SizedBox(height: 12),
          const Text('Aktif bir randevu bulunamadı.',
              style: TextStyle(
                  color: Color(0xFF132D51),
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text(
            'Yeni bir görüşme planlayabilir veya ana seçime dönebilirsiniz.',
            style: TextStyle(color: Color(0xFF62748A)),
          ),
          const SizedBox(height: 18),
          if (_entryMode == 'manage') ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _startNewAppointment,
                icon: const Icon(Icons.event_available_rounded),
                label: const Text('Yeni Randevu Oluştur'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            onPressed: () => setState(() {
              _entryMode = null;
              _step = 0;
            }),
            child: const Text('Ana Seçime Dön'),
          ),
        ],
      );
    }
    final appointments = _entryMode == 'manage'
        ? _existingAppointments
        : [_existingAppointments.first];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(
        _entryMode == 'manage'
            ? Icons.calendar_month_rounded
            : Icons.info_outline_rounded,
        color: const Color(0xFF3172B8),
        size: 36,
      ),
      const SizedBox(height: 12),
      Text(
        _entryMode == 'manage'
            ? 'Randevularınız'
            : 'Yaklaşan bir randevunuz var',
        style: const TextStyle(
            color: Color(0xFF132D51),
            fontSize: 22,
            fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 7),
      Text(
        '$_studentName için tarih ve saat değişikliği yapabilir veya randevuyu iptal edebilirsiniz.',
        style: const TextStyle(color: Color(0xFF62748A)),
      ),
      const SizedBox(height: 16),
      ...appointments.map((appointment) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _appointmentSummaryCard(appointment),
                const SizedBox(height: 8),
                _appointmentActions(appointment),
              ],
            ),
          )),
      if (_entryMode != 'manage' && _existingAppointments.length > 1)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
              '${_existingAppointments.length - 1} diğer randevuyu görüntüle'),
          children: _existingAppointments.skip(1).map((appointment) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _appointmentSummaryCard(appointment),
                  const SizedBox(height: 8),
                  _appointmentActions(appointment),
                ],
              ),
            );
          }).toList(),
        ),
      const SizedBox(height: 12),
      if (_entryMode != 'manage') ...[
        const Text(
            'Başka bir randevu oluşturmanız gerekiyorsa devam edebilirsiniz.',
            style: TextStyle(color: Color(0xFF62748A))),
        const SizedBox(height: 20),
      ],
      Row(children: [
        Expanded(
            child: OutlinedButton(
                onPressed: () => setState(() {
                      _entryMode = null;
                      _step = 0;
                    }),
                child: const Text('Ana Seçime Dön'))),
        if (_entryMode != 'manage') ...[
          const SizedBox(width: 10),
          Expanded(
              child: FilledButton.icon(
                  onPressed: _loading ? null : _startNewAppointment,
                  icon: const Icon(Icons.event_available_rounded),
                  label: const Text('Yeni Randevu'))),
        ],
      ]),
    ]);
  }

  Widget _appointmentActions(Map<String, dynamic> appointment) {
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _loading ? null : () => _startReschedule(appointment),
          icon: const Icon(Icons.edit_calendar_rounded),
          label: const Text('Tarih / Saat'),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _loading ? null : () => _cancelAppointment(appointment),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('İptal Et'),
        ),
      ),
    ]);
  }

  Widget _appointmentSummaryCard(Map<String, dynamic> appointment) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: const Color(0xFFF2F7FC),
            borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${appointment['date'] ?? ''} • ${appointment['time'] ?? ''}',
              style: const TextStyle(
                  color: Color(0xFF183656), fontWeight: FontWeight.w800)),
          if ('${appointment['counselorName'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Rehber Öğretmen: ${appointment['counselorName']}',
                style: const TextStyle(color: Color(0xFF62748A))),
          ],
        ]),
      );

  Widget _groupedAppointmentTimes({
    required List<String> times,
    required String? selectedTime,
    required ValueChanged<String> onSelected,
  }) {
    const periodIcons = {
      'Sabah': Icons.wb_sunny_outlined,
      'Öğle': Icons.wb_cloudy_outlined,
      'Akşam': Icons.nights_stay_outlined,
    };
    final groups = groupAppointmentTimes(times);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: groups.entries.map((group) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F8FC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2EAF3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(periodIcons[group.key],
                      size: 17, color: const Color(0xFF3270B8)),
                  const SizedBox(width: 7),
                  Text(
                    group.key,
                    style: const TextStyle(
                      color: Color(0xFF183656),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${group.value.length} saat',
                    style: const TextStyle(
                      color: Color(0xFF62748A),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: group.value.map((time) {
                  final selected = selectedTime == time;
                  return ChoiceChip(
                    label: Text(time),
                    selected: selected,
                    onSelected: (_) => onSelected(time),
                    selectedColor: const Color(0xFFDCEBFA),
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: selected
                          ? const Color(0xFF1E568F)
                          : const Color(0xFF35516F),
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                    side: BorderSide(
                      color: selected
                          ? const Color(0xFF3270B8)
                          : const Color(0xFFD7E1ED),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _slotStep() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_entryMode == 'manage')
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                            _editingAppointmentId = null;
                            _step = 1;
                          }),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Randevulara Dön'),
                ),
              ),
            const Text('Randevu seçimi',
                style: TextStyle(
                    color: Color(0xFF132D51),
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: const Color(0xFFF2F7FC),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Öğrenci: $_studentName',
                        style: const TextStyle(
                            color: Color(0xFF183656),
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text('Rehber Öğretmen: $_counselorName',
                        style: const TextStyle(color: Color(0xFF62748A))),
                  ]),
            ),
            const SizedBox(height: 16),
            const Text('Tarih seçin',
                style: TextStyle(
                    color: Color(0xFF183656),
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (_availabilityLoadFailed)
              const Text(
                'Uygun günler yüklenemedi. Lütfen geri dönüp bilgilerinizi yeniden doğrulayın.',
                style: TextStyle(color: Color(0xFFB54747)),
              )
            else if (_availableDates.isEmpty)
              const Text(
                'Rehberlik öğretmeninin çalışma programında uygun bir boş saat bulunmuyor.',
                style: TextStyle(color: Color(0xFF62748A)),
              )
            else
              SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _availableDates.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final option = _availableDates[index];
                    final date = option['date']?.toString() ?? '';
                    final dateValue = DateTime.tryParse('${date}T12:00:00');
                    if (dateValue == null) return const SizedBox.shrink();
                    final selected = _date == date;
                    final dateParts = _shortDateLabel(dateValue).split('\n');
                    return SizedBox(
                      width: 88,
                      child: Material(
                        color:
                            selected ? const Color(0xFF236AAC) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _loading ? null : () => _loadSlots(date),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF236AAC)
                                    : const Color(0xFFDCE5F0),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  dateParts.first,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : const Color(0xFF183656),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  dateParts.last,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white70
                                        : const Color(0xFF62748A),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (_date != null) ...[
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 18, color: Color(0xFF3270B8)),
                  SizedBox(width: 7),
                  Text(
                    'Saat seçin',
                    style: TextStyle(
                      color: Color(0xFF183656),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(),
                ))
              else if (_slots.isEmpty)
                const Text('Bu tarihte uygun saat bulunmuyor.')
              else
                _groupedAppointmentTimes(
                  times: _slots,
                  selectedTime: _time,
                  onSelected: (time) => setState(() => _time = time),
                )
            ],
            const SizedBox(height: 20),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: _time == null || _loading
                        ? null
                        : () => setState(() => _step = 3),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: const Color(0xFF236AAC)),
                    child: const Text('Randevu Özetiyle Devam Et'))),
          ]);

  Widget _reviewStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Son kontrol',
              style: TextStyle(
                  color: Color(0xFF132D51),
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Randevu henüz oluşturulmadı. Bilgileri kontrol edip onaylayın.',
            style: TextStyle(color: Color(0xFF62748A)),
          ),
          const SizedBox(height: 16),
          _appointmentSummaryCard({
            'date': _date,
            'time': _time,
            'counselorName': _counselorName,
          }),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _loading ? null : () => setState(() => _step = 2),
                child: const Text('Geri Dön'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _loading ? null : _confirmAppointment,
                child: Text(_editingAppointmentId == null
                    ? 'Randevuyu Onayla'
                    : 'Değişikliği Onayla'),
              ),
            ),
          ]),
        ],
      );

  Widget _otpStep() => Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Randevu özeti',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text('$_studentName • $_date • $_time'),
        Text('Rehber Öğretmen: $_counselorName'),
        const SizedBox(height: 16),
        const Text('Telefonunuza gelen 6 haneli kodu girin.'),
        TextField(
            controller: _otp,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Doğrulama kodu')),
        SizedBox(
            width: double.infinity,
            child: FilledButton(
                onPressed: _loading ? null : _confirmOtp,
                child: const Text('Randevuyu Oluştur'))),
      ]);

  Widget _resultStep() => Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded,
            color: Color(0xFF2F9C73), size: 64),
        const SizedBox(height: 12),
        Text(
            _resultWasReschedule
                ? 'Randevunuz güncellendi'
                : 'Randevunuz oluşturuldu',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Text('$_date • $_time',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('$_counselorName'),
        const SizedBox(height: 16),
        const Text(
            'Görüşme saatinden birkaç dakika önce kurumda bulunmanızı rica ederiz.',
            textAlign: TextAlign.center),
        const SizedBox(height: 18),
        SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => setState(() {
                _entryMode = null;
                _step = 0;
                _sessionToken = null;
                _existingAppointments = const [];
                _date = null;
                _time = null;
                _slots = const [];
                _editingAppointmentId = null;
                _resultWasReschedule = false;
                _phone.clear();
                _otp.clear();
              }),
              child: const Text('Ana Sayfaya Dön'),
            )),
      ]);
}
