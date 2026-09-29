import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  List<Map<String, dynamic>> _existingAppointments = const [];
  List<Map<String, dynamic>> _searchResults = const [];
  String? _selectionToken, _maskedPhone, _studentClassLabel;
  int _step = 0;
  bool _loading = false;

  @override
  void dispose() {
    _username.dispose();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

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
        setState(() {
          _sessionToken = data['sessionToken'] as String?;
          _studentName = data['studentName'] as String?;
          _counselorName = data['counselorName'] as String?;
          _existingAppointments = existingAppointments;
          _step = existingAppointments.isEmpty ? 2 : 1;
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
            _step = 4;
          });
          return;
        }
        if (data['deliveryAvailable'] != true) {
          throw StateError(
              'SMS doğrulama servisi şu anda kullanıma açık değil.');
        }
        setState(() {
          _challengeId = data['challengeId'] as String?;
          _step = 3;
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
          _step = 4;
        });
      });

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
                            _progress(),
                            const SizedBox(height: 30),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: KeyedSubtree(
                                key: ValueKey(_step),
                                child: _step == 0
                                    ? _verifyStep()
                                    : _step == 1
                                        ? _existingAppointmentStep()
                                        : _step == 2
                                            ? _slotStep()
                                            : _step == 3
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

  Widget _progress() {
    const labels = ['Öğrenci', 'Doğrulama', 'Randevu', 'Tamamlandı'];
    final current = _step == 0
        ? 0
        : _step == 4
            ? 3
            : _step == 3
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
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+()\- ]'))
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
          ]);

  Widget _existingAppointmentStep() {
    final nearest = _existingAppointments.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline_rounded,
          color: Color(0xFF3172B8), size: 36),
      const SizedBox(height: 12),
      const Text('Yaklaşan bir randevunuz var',
          style: TextStyle(
              color: Color(0xFF132D51),
              fontSize: 22,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: 7),
      Text(
          '$_studentName için daha önce oluşturulmuş bir rehberlik görüşmesi bulunuyor.',
          style: const TextStyle(color: Color(0xFF62748A))),
      const SizedBox(height: 16),
      _appointmentSummaryCard(nearest),
      if (_existingAppointments.length > 1)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
              '${_existingAppointments.length - 1} diğer randevuyu görüntüle'),
          children: _existingAppointments
              .skip(1)
              .map(_appointmentSummaryCard)
              .toList(),
        ),
      const SizedBox(height: 12),
      const Text(
          'Başka bir randevu oluşturmanız gerekiyorsa devam edebilirsiniz.',
          style: TextStyle(color: Color(0xFF62748A))),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
            child: OutlinedButton(
                onPressed: () => setState(() => _step = 0),
                child: const Text('Vazgeç'))),
        const SizedBox(width: 10),
        Expanded(
            child: FilledButton(
                onPressed: () => setState(() => _step = 2),
                child: const Text('Yeni Randevuya Devam Et'))),
      ]),
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

  Widget _slotStep() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
            const Text('Uygun gün ve saat',
                style: TextStyle(
                    color: Color(0xFF183656),
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(7, (index) {
                  final dateValue = DateTime.now().add(Duration(days: index));
                  final date = _dateKey(dateValue);
                  return ChoiceChip(
                      label: Text(_shortDateLabel(dateValue),
                          textAlign: TextAlign.center),
                      selected: _date == date,
                      onSelected: _loading ? null : (_) => _loadSlots(date));
                })),
            if (_date != null) ...[
              const SizedBox(height: 14),
              if (_loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(),
                ))
              else if (_slots.isEmpty)
                const Text('Bu tarihte uygun saat bulunmuyor.')
              else
                Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _slots
                        .map((slot) => ChoiceChip(
                            label: Text(slot),
                            selected: _time == slot,
                            onSelected: (_) => setState(() => _time = slot)))
                        .toList())
            ],
            const SizedBox(height: 20),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: _time == null || _loading ? null : _requestOtp,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: const Color(0xFF236AAC)),
                    child: const Text('Randevu Özetiyle Devam Et'))),
          ]);

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
        const Text('Randevunuz oluşturuldu',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
                _step = 0;
                _sessionToken = null;
                _existingAppointments = const [];
                _date = null;
                _time = null;
                _slots = const [];
                _phone.clear();
                _otp.clear();
              }),
              child: const Text('Ana Sayfaya Dön'),
            )),
      ]);
}
