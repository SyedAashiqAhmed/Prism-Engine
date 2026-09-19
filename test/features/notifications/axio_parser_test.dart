import 'package:flutter_test/flutter_test.dart';
import 'package:prism_engine/features/notifications/services/axio_parser.dart';

void main() {
  group('AxioParser Bank SMS & Notification Parsing Tests', () {
    test('HDFC Bank Debit SMS with Avl Bal is parsed correctly', () {
      const sms =
          'HDFC Bank: Rs 540.00 debited from a/c **4321 on 19-09-26 to SWIGGY. Avl bal: Rs 24,500.00';
      final parsed = AxioParser.parse(sms);

      expect(parsed, isNotNull);
      expect(parsed!.type, equals('DEBIT'));
      expect(parsed.amount, equals(540.00));
      expect(parsed.accountLast4, equals('4321'));
      expect(parsed.merchant?.toUpperCase(), contains('SWIGGY'));
    });

    test('SBI UPI Credit SMS is parsed correctly', () {
      const sms =
          'Dear SBI User, your A/C 9876 has been credited with Rs 2,500.00 on 19Sep by transfer from JOHN. Avl Bal: Rs 15,200.00';
      final parsed = AxioParser.parse(sms);

      expect(parsed, isNotNull);
      expect(parsed!.type, equals('CREDIT'));
      expect(parsed.amount, equals(2500.00));
      expect(parsed.accountLast4, equals('9876'));
    });

    test('ICICI Credit Card Spend with INR and Available Limit', () {
      const sms =
          'Tranx of INR 1,299.00 spent on ICICI Bank Card ending 1122 at AMAZON on 19-Sep-26. Available limit: INR 45,000.00';
      final parsed = AxioParser.parse(sms);

      expect(parsed, isNotNull);
      expect(parsed!.type, equals('DEBIT'));
      expect(parsed.amount, equals(1299.00));
      expect(parsed.accountLast4, equals('1122'));
      expect(parsed.merchant?.toUpperCase(), contains('AMAZON'));
    });

    test('Google Pay notification with Rupee symbol ₹', () {
      const text = 'Paid ₹350.00 to ZOMATO on Google Pay';
      final parsed = AxioParser.parse(text);

      expect(parsed, isNotNull);
      expect(parsed!.type, equals('DEBIT'));
      expect(parsed.amount, equals(350.00));
      expect(parsed.merchant?.toUpperCase(), contains('ZOMATO'));
    });

    test('Paytm wallet debit SMS is parsed correctly', () {
      const text = 'Paid Rs 85.00 to Chai Point at Paytm. Bal Rs 120.00';
      final parsed = AxioParser.parse(text);

      expect(parsed, isNotNull);
      expect(parsed!.type, equals('DEBIT'));
      expect(parsed.amount, equals(85.00));
      expect(parsed.merchant?.toUpperCase(), contains('CHAI POINT'));
    });

    test('Blacklist Filter: OTP SMS returns null', () {
      const sms =
          'Your OTP for HDFC NetBanking is 481920. Do not share this OTP with anyone.';
      final parsed = AxioParser.parse(sms);

      expect(parsed, isNull);
    });

    test('Blacklist Filter: Pre-approved promotional spam returns null', () {
      const sms =
          'Congratulations! Pre-approved loan of Rs 5,00,000 is waiting for you! Apply now.';
      final parsed = AxioParser.parse(sms);

      expect(parsed, isNull);
    });
  });
}
