/// Parsed financial transaction result from raw SMS or push notification text.
class ParsedTxn {
  final String type; // 'DEBIT' or 'CREDIT'
  final double amount;
  final String? merchant;
  final String? accountLast4;

  const ParsedTxn({
    required this.type,
    required this.amount,
    this.merchant,
    this.accountLast4,
  });

  @override
  String toString() {
    return 'ParsedTxn(type: $type, amount: $amount, merchant: $merchant, acc: $accountLast4)';
  }
}

/// Axio-grade anchored regex parser for Indian bank and fintech SMS alerts.
/// Features blacklist filtering, available balance stripping, and anchored amount matching.
class AxioParser {
  static ParsedTxn? parse(String rawText, {String? title}) {
    final fullText = title != null && title.isNotEmpty ? '$title $rawText' : rawText;
    final lower = fullText.toLowerCase();

    // 1. Blacklist: Skip OTPs, bill alerts, statements, and promotional spam
    if (lower.contains('otp') ||
        lower.contains('one time password') ||
        lower.contains('verification code') ||
        lower.contains('bill due') ||
        lower.contains('statement generated') ||
        lower.contains('pre-approved') ||
        lower.contains('apply now') ||
        lower.contains('congratulations') ||
        lower.contains('special offer')) {
      return null;
    }

    // 2. Erase Available Balance FIRST (Avoids grabbing e.g. "Avl Bal: Rs. 45,000" as the spend amount)
    final textNoBal = rawText.replaceAll(
      RegExp(
        r'(?:avl\s*bal|available\s*balance|bal|balance)\s*:?\s*(?:rs\.?|inr|₹)?\s*[\d,]+(?:\.\d{1,2})?',
        caseSensitive: false,
      ),
      '',
    );

    // 3. Extract Account / Card Last 4 Digits
    String? accountLast4;
    final acctMatch = RegExp(
      r'(?:a\/c|acct|account|card|ending)\s*(?:no\.?)?\s*[\*xX]*(\d{4})',
      caseSensitive: false,
    ).firstMatch(rawText);
    if (acctMatch != null) {
      accountLast4 = acctMatch.group(1);
    }

    // 4. Extract Merchant Name (e.g. "Paid to Swiggy", "at Amazon", "VPA swiggy@okaxis")
    String? merchant;
    final merchantMatch = RegExp(
      r'(?:to|at|vpa|paid to|info:|trf to)\s+([A-Za-z0-9\s&]{3,25}?)(?:\s+on|\s+ref|\s+upi|\s+avl|\s+dated|\s*\.|$)',
      caseSensitive: false,
    ).firstMatch(textNoBal);
    if (merchantMatch != null) {
      final candidate = merchantMatch.group(1)?.trim();
      if (candidate != null &&
          candidate.isNotEmpty &&
          !candidate.toLowerCase().contains('account') &&
          !candidate.toLowerCase().contains('bank')) {
        merchant = candidate;
      }
    }

    // 5. DEBIT Check (Anchored Regex)
    final debitRegex = RegExp(
      r'(?:debited\s*(?:with|by)?|paid|sent|spent|withdrawn|deducted)\s*(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)|(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)\s*(?:debited|spent|paid|withdrawn|deducted)',
      caseSensitive: false,
    );
    final debitMatch = debitRegex.firstMatch(textNoBal);
    if (debitMatch != null) {
      final amountStr = debitMatch.group(1) ?? debitMatch.group(2);
      final amount = _cleanAmount(amountStr);
      if (amount > 0) {
        return ParsedTxn(
          type: 'DEBIT',
          amount: amount,
          merchant: merchant,
          accountLast4: accountLast4,
        );
      }
    }

    // 6. CREDIT Check (Anchored Regex)
    final creditRegex = RegExp(
      r'(?:credited\s*(?:with|by)?|received|deposited|refunded|reversed|added)\s*(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)|(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)\s*(?:credited|received|deposited|refunded|added)',
      caseSensitive: false,
    );
    final creditMatch = creditRegex.firstMatch(textNoBal);
    if (creditMatch != null) {
      final amountStr = creditMatch.group(1) ?? creditMatch.group(2);
      final amount = _cleanAmount(amountStr);
      if (amount > 0) {
        return ParsedTxn(
          type: 'CREDIT',
          amount: amount,
          merchant: merchant,
          accountLast4: accountLast4,
        );
      }
    }

    return null;
  }

  static double _cleanAmount(String? raw) {
    if (raw == null) return 0.0;
    final sanitized = raw.replaceAll(',', '').trim();
    return double.tryParse(sanitized) ?? 0.0;
  }
}
