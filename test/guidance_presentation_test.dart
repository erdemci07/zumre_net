import 'package:flutter_test/flutter_test.dart';
import 'package:zumre_net/utils/guidance_presentation.dart';

void main() {
  test('guidance status labels preserve the existing status model', () {
    expect(guidanceStatusLabel('pending'), 'Randevulu');
    expect(guidanceStatusLabel('approved'), 'Geldi / Bekliyor');
    expect(guidanceStatusLabel('in_progress'), 'Görüşmede');
    expect(guidanceStatusLabel('no_show'), 'Gelmedi');
  });

  test('guidance card only exposes a guardian name when it exists', () {
    expect(
        guidanceGuardianLabel(
            {'guardianName': 'Murat', 'guardianSurname': 'Yılmaz'}),
        'Murat Yılmaz');
    expect(guidanceGuardianLabel(null), isEmpty);
    expect(guidanceParticipantLabel({'participantType': 'both'}),
        'Katılımcı: Öğrenci ve veli');
  });

  test('times sort safely and invalid values go to the end', () {
    expect(guidanceTimeSortValue('09:30'),
        lessThan(guidanceTimeSortValue('14:00')));
    expect(guidanceTimeSortValue('bad'), 24 * 60);
  });
}
