import 'package:flutter_test/flutter_test.dart';
import 'package:zumre_net/models/education_scope.dart';

void main() {
  test('LGS and YKS teacher scopes stay separate for the same subject', () {
    final lgsTeacher = {
      'teachingScopes': [
        {'level': 'LGS', 'subject': 'MATEMATİK'},
      ],
    };
    expect(teacherMatchesEducationScope(lgsTeacher, subject: 'MATEMATİK', educationLevel: 'LGS'), isTrue);
    expect(teacherMatchesEducationScope(lgsTeacher, subject: 'MATEMATİK', educationLevel: 'YKS'), isFalse);
  });

  test('a dual-scope teacher matches both levels and legacy teachers remain usable', () {
    final dualTeacher = {
      'teachingScopes': [
        {'level': 'LGS', 'subject': 'MATEMATİK'},
        {'level': 'YKS', 'subject': 'MATEMATİK'},
      ],
    };
    expect(teacherMatchesEducationScope(dualTeacher, subject: 'MATEMATİK', educationLevel: 'LGS'), isTrue);
    expect(teacherMatchesEducationScope(dualTeacher, subject: 'MATEMATİK', educationLevel: 'YKS'), isTrue);
    expect(teacherMatchesEducationScope({}, subject: 'MATEMATİK', educationLevel: 'LGS'), isTrue);
  });

  test('student level prefers explicit data and safely infers known grades', () {
    expect(inferredStudentEducationLevel({'educationLevel': 'LGS', 'className': '11'}), 'LGS');
    expect(inferredStudentEducationLevel({'className': '8/A'}), 'LGS');
    expect(inferredStudentEducationLevel({'className': '11-A'}), 'YKS');
    expect(inferredStudentEducationLevel({'className': 'Hazırlık'}), isNull);
  });
}
