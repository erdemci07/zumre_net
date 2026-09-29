import 'package:flutter_test/flutter_test.dart';
import 'package:zumre_net/models/education_scope.dart';

void main() {
  test('scoped time slots only match the intended education level', () {
    expect(
      timeSlotMatchesEducationLevel({'educationLevel': 'LGS'}, 'LGS'),
      isTrue,
    );
    expect(
      timeSlotMatchesEducationLevel({'educationLevel': 'LGS'}, 'YKS'),
      isFalse,
    );
    expect(timeSlotMatchesEducationLevel({}, null), isTrue);
  });

  test('time management filter keeps legacy shared slots visible', () {
    expect(
      timeSlotMatchesManagementFilter({'educationLevel': 'BOTH'}, 'LGS'),
      isTrue,
    );
    expect(
      timeSlotMatchesManagementFilter({'educationLevel': 'YKS'}, 'LGS'),
      isFalse,
    );
    expect(timeSlotMatchesManagementFilter({'educationLevel': 'LGS'}, 'ALL'),
        isTrue);
  });

  test(
      'teacher availability rejects intersecting intervals but allows touching ones',
      () {
    expect(
      timeIntervalsOverlap(
        firstStart: '14:20',
        firstEnd: '15:00',
        secondStart: '14:40',
        secondEnd: '15:20',
      ),
      isTrue,
    );
    expect(
      timeIntervalsOverlap(
        firstStart: '14:20',
        firstEnd: '15:00',
        secondStart: '15:00',
        secondEnd: '15:40',
      ),
      isFalse,
    );
  });
}
