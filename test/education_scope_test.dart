import 'package:flutter_test/flutter_test.dart';
import 'package:zumre_net/models/education_scope.dart';

void main() {
  test('LGS and YKS teacher scopes stay separate for the same subject', () {
    final lgsTeacher = {
      'teachingScopes': [
        {'level': 'LGS', 'subject': 'MATEMATİK'},
      ],
    };
    expect(
        teacherMatchesEducationScope(lgsTeacher,
            subject: 'MATEMATİK', educationLevel: 'LGS'),
        isTrue);
    expect(
        teacherMatchesEducationScope(lgsTeacher,
            subject: 'MATEMATİK', educationLevel: 'YKS'),
        isFalse);
  });

  test(
      'a dual-scope teacher matches both levels and legacy teachers remain usable',
      () {
    final dualTeacher = {
      'teachingScopes': [
        {'level': 'LGS', 'subject': 'MATEMATİK'},
        {'level': 'YKS', 'subject': 'MATEMATİK'},
      ],
    };
    expect(
        teacherMatchesEducationScope(dualTeacher,
            subject: 'MATEMATİK', educationLevel: 'LGS'),
        isTrue);
    expect(
        teacherMatchesEducationScope(dualTeacher,
            subject: 'MATEMATİK', educationLevel: 'YKS'),
        isTrue);
    expect(
        teacherMatchesEducationScope({},
            subject: 'MATEMATİK', educationLevel: 'LGS'),
        isTrue);
  });

  test('study guard education levels are normalized from user data', () {
    expect(
      educationLevelsFromData({
        'educationLevels': ['LGS', 'YKS', 'LGS'],
      }),
      ['LGS', 'YKS'],
    );
    expect(
      educationLevelsFromData({'educationLevel': 'LGS'}),
      ['LGS'],
    );
  });

  test('student level only infers trusted production className prefixes', () {
    expect(
        inferredStudentEducationLevel(
            {'educationLevel': 'LGS', 'className': '11'}),
        'LGS');
    for (final className in [
      '5-DERSLİK 5',
      '6-DERSLİK 6',
      '7-DERSLİK 4',
      '8-DERSLİK 9'
    ]) {
      expect(inferredStudentEducationLevel({'className': className}), 'LGS');
    }
    for (final className in [
      '10-DERSLİK 6',
      '11-DERSLİK 4 SAY',
      '12-DERSLİK 13 EA',
      'MEZUN-DERSLİK 10'
    ]) {
      expect(inferredStudentEducationLevel({'className': className}), 'YKS');
    }
    expect(inferredStudentEducationLevel({'className': 'DERSLİK 8'}), 'LGS');
    expect(
        inferredStudentEducationLevel({'className': 'DERSLİK 10 SAY'}), 'YKS');
    expect(
        inferredStudentEducationLevel({'className': 'DERSLİK 11 EA'}), 'YKS');
    expect(inferredStudentEducationLevel({'className': 'DERSLİK-16-SÖZEL'}),
        isNull);
    expect(inferredStudentEducationLevel({'branch': 'DERSLİK 7'}), 'LGS');
    expect(
        inferredStudentEducationLevel({'department': 'DERSLİK 12 SAY'}), 'YKS');
    expect(inferredStudentEducationLevel({'className': 'MEZUN 10'}), 'YKS');
    final lgsTeacher = {
      'teachingScopes': [
        {'level': 'LGS', 'subject': 'MATEMATİK'},
      ],
    };
    expect(
      teacherMatchesEducationScope(
        lgsTeacher,
        subject: 'MATEMATİK',
        educationLevel: null,
      ),
      isFalse,
    );
  });
}
