import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zumre_net/theme/app_theme.dart';

void main() {
  test('AppTheme keeps the ZümreNet dark Material 3 baseline', () {
    final theme = AppTheme.theme;

    expect(theme.useMaterial3, isTrue);
    expect(theme.scaffoldBackgroundColor, AppColors.darkBlue);
    expect(theme.colorScheme.brightness, equals(Brightness.dark));
  });
}
