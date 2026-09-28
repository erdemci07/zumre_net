import 'package:flutter_test/flutter_test.dart';
import 'package:zumre_net/utils/class_name_display.dart';

void main() {
  test('formats trusted production className prefixes for display only', () {
    expect(formatClassNameDisplay('5-DERSLİK 5'), '5. Sınıf • Derslik 5');
    expect(formatClassNameDisplay('11-DERSLİK 4 SAY'),
        '11. Sınıf • Derslik 4 SAY');
    expect(formatClassNameDisplay('12-HAFTA SONU ETÜT'),
        '12. Sınıf • Hafta Sonu Etüt');
    expect(formatClassNameDisplay('MEZUN-ÇALIŞMA SALONU'),
        'Mezun • Çalışma Salonu');
  });

  test('leaves untrusted legacy values unchanged and skips empty separators',
      () {
    expect(formatClassNameDisplay('DERSLİK-16-SÖZEL'), 'DERSLİK-16-SÖZEL');
    expect(
      formatStudentClassDisplay(
        className: '10-DERSLİK 6',
        department: 'SAY',
      ),
      '10. Sınıf • Derslik 6 • SAY',
    );
  });
}
