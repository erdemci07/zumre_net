import 'package:flutter_test/flutter_test.dart';
import 'package:zumre_net/utils/appointment_time_groups.dart';

void main() {
  test('groups appointment times in day-period order', () {
    expect(
      groupAppointmentTimes(['18:30', '09:00', '13:20', '11:40', '17:00']),
      {
        'Sabah': ['09:00', '11:40'],
        'Öğle': ['13:20', '17:00'],
        'Akşam': ['18:30'],
      },
    );
  });

  test('omits periods without available times', () {
    expect(groupAppointmentTimes(['09:00']), {
      'Sabah': ['09:00'],
    });
  });
}