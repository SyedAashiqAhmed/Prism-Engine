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

    test('Credit amount before "has been credited" is classified as CREDIT', () {
      const text =
          'INR 2,500.00 has been credited to your A/c XX9876. Avl Bal: Rs 15,200';
      final parsed = AxioParser.parse(text);

      expect(parsed, isNotNull);
      expect(parsed!.type, equals('CREDIT'));
      expect(parsed.amount, equals(2500.00));
    });

    test('Debit amount before "has been debited" is classified as DEBIT', () {
      const text =
          'Rs. 1,234.50 has been debited from account XX4321. Available balance Rs. 8,765.50';
      final parsed = AxioParser.parse(text);

      expect(parsed, isNotNull);
      expect(parsed!.type, equals('DEBIT'));
      expect(parsed.amount, equals(1234.50));
    });

    test('Available credit limit is not mistaken for the transaction amount', () {
      const text =
          'Your card ending 1122 was charged INR 399.00 at STORE. Available limit: INR 45,000.00';
      final parsed = AxioParser.parse(text);

      expect(parsed, isNotNull);
      expect(parsed!.type, equals('DEBIT'));
      expect(parsed.amount, equals(399.00));
    });

    test('Cashback credit is not discarded as promotional text', () {
      const text = 'Cashback earned: Rs 25.00 credited to your wallet';
      final parsed = AxioParser.parse(text);

      expect(parsed, isNotNull);
      expect(parsed!.type, equals('CREDIT'));
      expect(parsed.amount, equals(25.00));
    });

    test('Uses the first amount-direction pair when both are mentioned', () {
      const text =
          'Rs 500.00 credited to your account; next payment of Rs 120.00 debited';
      final parsed = AxioParser.parse(text);

      expect(parsed, isNotNull);
      expect(parsed!.type, equals('CREDIT'));
      expect(parsed.amount, equals(500.00));
    });

    test('Notification body direction takes precedence over a stale title', () {
      const text = 'Rs 500.00 credited to your account';
      final parsed = AxioParser.parse(text, title: 'Debit alert');

      expect(parsed, isNotNull);
      expect(parsed!.type, equals('CREDIT'));
      expect(parsed.amount, equals(500.00));
    });

    test('Account digits after a direction word are not treated as amount', () {
      const text = 'Your account has been credited to account XX9876';

      expect(AxioParser.parse(text), isNull);
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
