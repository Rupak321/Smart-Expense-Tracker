import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/theme/app_theme.dart';

/// Relative luminance contrast ratio, per WCAG 2.1.
double contrastRatio(Color a, Color b) {
  double channel(double component) {
    return component <= 0.03928
        ? component / 12.92
        : math.pow((component + 0.055) / 1.055, 2.4).toDouble();
  }

  double luminance(Color color) {
    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  final first = luminance(a) + 0.05;
  final second = luminance(b) + 0.05;
  return first > second ? first / second : second / first;
}

void main() {
  final themes = {
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
  };

  themes.forEach((name, theme) {
    final scheme = theme.colorScheme;

    group('$name theme', () {
      test('cards are distinguishable from the page behind them', () {
        // The original theme painted both the scaffold and every card with
        // colorScheme.surface, so cards were literally invisible.
        expect(
          scheme.appCard,
          isNot(equals(scheme.appBackground)),
          reason: 'card and background must not be the same colour',
        );
        expect(theme.scaffoldBackgroundColor, equals(scheme.appBackground));
        expect(theme.cardTheme.color, equals(scheme.appCard));
      });

      test('body text is readable on both card and background', () {
        expect(contrastRatio(scheme.onSurface, scheme.appCard),
            greaterThan(4.5));
        expect(contrastRatio(scheme.onSurface, scheme.appBackground),
            greaterThan(4.5));
      });

      test('hero foreground is readable on the hero fill', () {
        for (final fill in scheme.appHeroGradient) {
          expect(
            contrastRatio(scheme.appOnHero, fill),
            greaterThan(4.5),
            reason: 'hero text must stay readable on $fill',
          );
        }
      });

      test('income and expense accents are readable on cards', () {
        expect(contrastRatio(scheme.appExpense, scheme.appCard),
            greaterThan(3.0));
        expect(contrastRatio(scheme.appIncome, scheme.appCard),
            greaterThan(3.0));
      });

      test('income and expense are visually distinct from each other', () {
        expect(scheme.appIncome, isNot(equals(scheme.appExpense)));
      });

      test('chart palette entries are all distinct and visible on cards', () {
        expect(
          AppColorRoles.chartPalette.toSet().length,
          equals(AppColorRoles.chartPalette.length),
          reason: 'duplicate palette colours make legend entries ambiguous',
        );
        for (final color in AppColorRoles.chartPalette) {
          expect(
            contrastRatio(color, scheme.appCard),
            greaterThan(1.6),
            reason: '$color disappears against the $name card surface',
          );
        }
      });

      test('input fields are distinguishable from the card they sit on', () {
        expect(theme.inputDecorationTheme.fillColor, equals(scheme.appCardMuted));
        expect(scheme.appCardMuted, isNot(equals(scheme.appCard)));
      });
    });
  });
}
