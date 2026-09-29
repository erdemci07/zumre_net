import 'package:flutter_test/flutter_test.dart';
import 'package:zumre_net/utils/user_management_filters.dart';

void main() {
  final users = <Map<String, dynamic>>[
    {
      'role': 'student',
      'name': 'Ayşe',
      'surname': 'Yılmaz',
      'username': 'ayse.yilmaz',
      'className': '12-DERSLİK 4',
      'branch': 'DERSLİK 4',
      'department': 'SAY',
      'educationLevel': 'YKS',
    },
    {
      'role': 'student',
      'name': 'Can',
      'surname': 'Kaya',
      'className': '8-DERSLİK 9',
      'branch': 'DERSLİK 9',
      'department': 'LGS',
      'educationLevel': 'LGS',
    },
    {
      'role': 'teacher',
      'name': 'Deniz',
      'subjects': ['MATEMATİK'],
      'teachingScopes': [
        {'level': 'YKS', 'subject': 'MATEMATİK'},
      ],
    },
  ];

  test('student filters combine level, class and department', () {
    const filters = UserManagementFilters(
      role: 'student',
      educationLevel: 'YKS',
      className: '12-DERSLİK 4',
      department: 'say',
    );

    final result = users
        .where((user) => userMatchesManagementFilters(user, filters))
        .toList();

    expect(result, hasLength(1));
    expect(result.single['username'], 'ayse.yilmaz');
  });

  test('teacher filters include teaching scope and Turkish-insensitive search',
      () {
    const filters = UserManagementFilters(
      role: 'teacher',
      educationLevel: 'YKS',
      subject: 'matematik',
      search: 'deniz',
    );

    final result = users
        .where((user) => userMatchesManagementFilters(user, filters))
        .toList();

    expect(result, hasLength(1));
    expect(result.single['name'], 'Deniz');
  });

  test('student filter candidates cascade by level, class and branch', () {
    final cascadeUsers = <Map<String, dynamic>>[
      {
        'role': 'student',
        'className': '8-A',
        'branch': 'A',
        'department': 'LGS',
        'educationLevel': 'LGS',
      },
      {
        'role': 'student',
        'className': '12-B',
        'branch': 'B',
        'department': 'SAY',
        'educationLevel': 'YKS',
      },
    ];
    const filters = UserManagementFilters(
      role: 'student',
      educationLevel: 'LGS',
      className: '8-A',
      branch: 'A',
    );
    final options = cascadingStudentFilterOptions(
      cascadeUsers,
      filters,
    );

    expect(options.classNames, ['8-A']);
    expect(options.branches, ['A']);
    expect(options.departments, ['LGS']);
  });
}
