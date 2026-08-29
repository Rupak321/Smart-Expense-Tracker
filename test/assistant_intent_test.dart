import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/services/ai_financial_assistant_service.dart';

void main() {
  bool isQuestion(String text) {
    return AiFinancialAssistantService.looksLikeQuestionOrHypothetical(text);
  }

  group('question and hypothetical detection', () {
    test('treats anything ending in a question mark as a question', () {
      expect(isQuestion('should I send 5000 to mom?'), isTrue);
      expect(isQuestion('spent 500 on lunch?'), isTrue);
    });

    test('catches question openers without punctuation', () {
      expect(isQuestion('can i afford a 60000 laptop'), isTrue);
      expect(isQuestion('should i buy a 5000 phone'), isTrue);
      expect(isQuestion('how much did i spend on food'), isTrue);
      expect(isQuestion('where is my money going'), isTrue);
    });

    test('catches future intent', () {
      expect(isQuestion('planning to buy a bike for 200000'), isTrue);
      expect(isQuestion('thinking of moving to a 15000 flat'), isTrue);
      expect(isQuestion('if i spend 5000 on this will it hurt'), isTrue);
    });

    test('catches requests for advice', () {
      expect(isQuestion('give me advice on saving'), isTrue);
      expect(isQuestion('suggest a budget for me'), isTrue);
    });

    test('leaves plain statements of fact alone', () {
      // These are the ones that should still become proposed records.
      expect(isQuestion('spent 500 on lunch'), isFalse);
      expect(isQuestion('got 45k salary'), isFalse);
      expect(isQuestion('paid 1200 rent'), isFalse);
      expect(isQuestion('sent 5000 to mom'), isFalse);
      expect(isQuestion('mom gave me 2000'), isFalse);
    });

    test('does not fire on words that merely contain a starter', () {
      // "whatever" starts with "what" but is not a question opener; the
      // trailing space in the check is what prevents the false positive.
      expect(isQuestion('whatever i spent 300 today'), isFalse);
      expect(isQuestion('howdy, logged 200 for tea'), isFalse);
    });
  });
}
