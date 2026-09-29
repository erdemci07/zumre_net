import 'package:flutter_test/flutter_test.dart';
import 'package:zumre_net/utils/guidance_student_groups.dart';

void main() {
  final students = <Map<String, dynamic>>[
    {
      '_id': 'a',
      'fullName': 'Ayse Yilmaz',
      'className': '8-DERSLIK 9',
      'branch': 'DERSLIK 9',
      'department': 'LGS',
    },
    {
      '_id': 'b',
      'fullName': 'Can Kaya',
      'className': '8-DERSLIK 9',
      'branch': 'DERSLIK 9',
      'department': 'LGS',
    },
    {
      '_id': 'c',
      'fullName': 'Deniz Arslan',
      'className': '12-DERSLIK 11 SAY',
      'branch': 'DERSLIK 11 SAY',
      'department': 'SAY',
    },
    {'_id': 'd', 'fullName': 'Eksik Bilgi'},
  ];

  test('groups assigned students by existing class, branch and department', () {
    final groups = groupGuidanceStudents(students);

    expect(groups, hasLength(3));
    expect(groups.singleWhere((group) => group.students.length == 2).label,
        contains('8.'));
    expect(
        groups
            .singleWhere((group) => group.label == 'Sınıf bilgisi yok')
            .students
            .single['_id'],
        'd');
  });

  test('student and class search leaves only matching groups', () {
    expect(groupGuidanceStudents(students, query: 'can').single.students,
        hasLength(1));
    expect(
        groupGuidanceStudents(students, query: '12')
            .single
            .students
            .single['_id'],
        'c');
  });
}
