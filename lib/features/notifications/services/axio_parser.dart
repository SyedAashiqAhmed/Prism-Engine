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
/// Handles HDFC, SBI, ICICI, Axis, Kotak, GPay, PhonePe, Paytm patterns.
/// Features blacklist filtering, available balance stripping, and anchored amount matching.
class AxioParser {
  static ParsedTxn? parse(String rawText, {String? title}) {
    // Combine title + text for full-context parsing.
    final fullText =
        title != null && title.isNotEmpty ? '$title $rawText' : rawText;
    final lower = fullText.toLowerCase();

    // ── 1. Blacklist: Skip OTPs, bill alerts, statements, promotional spam ──
    if (lower.contains('otp') ||
        lower.contains('one time password') ||
        lower.contains('verification code') ||
        lower.contains('bill due') ||
        lower.contains('bill payment due') ||
        lower.contains('statement generated') ||
        lower.contains('pre-approved') ||
        lower.contains('apply now') ||
        lower.contains('special offer') ||
        lower.contains('minimum due') ||
        lower.contains('loan offer') ||
        lower.contains('your reward') ||
        lower.contains('cashback earned')) {
      return null;
    }

    // ── 2. Erase Available Balance from FULL text FIRST ──────────────────
    // Prevents "Avl Bal: Rs. 45,000" from being grabbed as the spend amount.
    final textNoBal = fullText.replaceAll(
      RegExp(
        r'(?:avl\s*bal|available\s*balance|bal|balance|avbl|a\/c\s*bal(?:ance)?)\s*:?\s*(?:rs\.?|inr|₹)?\s*[\d,]+(?:\.\d{1,2})?',
        caseSensitive: false,
      ),
      '',
    );

    // ── 3. Extract Account / Card Last 4 Digits ───────────────────────────
    String? accountLast4;
    final acctMatch = RegExp(
      r'(?:a\/c|acct|account|card|ending|a\/c\s*no\.?|acct\.?\s*no\.?)\s*(?:no\.?)?\s*[\*xX]*(\d{4})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (acctMatch != null) {
      accountLast4 = acctMatch.group(1);
    }

    // ── 4. Extract Merchant Name ─────────────────────────────────────────
    // Handles "Paid to Swiggy", "at Amazon", "VPA swiggy@okaxis",
    // "trf to", "Info: Merchant Name"
    String? merchant;
    final merchantPatterns = [
      RegExp(
        r'(?:paid\s+to|transferred?\s+to|trf\s+to|sent\s+to)\s+([A-Za-z0-9][A-Za-z0-9\s&._-]{2,30}?)(?:\s+on\b|\s+ref\b|\s+upi\b|\s+avl\b|\s+dated\b|\s+via\b|\s*[,.]|$)',
        caseSensitive: false,
      ),
      RegExp(
        r'\bat\s+([A-Za-z][A-Za-z0-9\s&._-]{2,25}?)(?:\s+on\b|\s+ref\b|\s+upi\b|\s+avl\b|\s+dated\b|\s*[,.]|$)',
        caseSensitive: false,
      ),
      RegExp(
        r'vpa\s+([A-Za-z0-9][A-Za-z0-9._@-]{3,40}?)(?:\s+on\b|\s+ref\b|\s+for\b|\s*[,.]|$)',
        caseSensitive: false,
      ),
      RegExp(
        r'info\s*:\s*([A-Za-z0-9][A-Za-z0-9\s&._-]{2,30}?)(?:\s+ref\b|\s*[,.]|$)',
        caseSensitive: false,
      ),
    ];

    for (final pattern in merchantPatterns) {
      final m = pattern.firstMatch(textNoBal);
      if (m != null) {
        final candidate = m.group(1)?.trim();
        if (candidate != null &&
            candidate.isNotEmpty &&
            !candidate.toLowerCase().contains('account') &&
            !candidate.toLowerCase().contains('bank') &&
            candidate.length >= 2) {
          merchant = candidate;
          break;
        }
      }
    }

    // ── 5. DEBIT Check ────────────────────────────────────────────────────
    // Handles patterns from HDFC, SBI, Axis, Kotak, GPay, PhonePe, Paytm, ICICI
    //
    // Patterns covered:
    //   "debited with Rs. 5,000.00"
    //   "debited by Rs 500"
    //   "Rs. 5000 debited from"
    //   "INR 5000.00 debited"
    //   "₹5000 debited"
    //   "deducted Rs 200"
    //   "Paid Rs. 100 to"
    //   "Payment of Rs 500"
    //   "sent Rs 200"
    //   "spent Rs. 1,200"
    //   "withdrawn Rs 5000"
    //   "transferred Rs. 2000"
    //   "purchase of Rs 399"
    final debitRegex = RegExp(
      r'(?:'
      // Pattern A: keyword THEN amount
      r'(?:debited?\s*(?:with|by|for)?|deducted|withdrawn|sent|spent|paid|'
      r'payment\s*of|purchase\s*(?:of)?|transferred?)\s*'
      r'(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)'
      r'|'
      // Pattern B: amount THEN keyword
      r'(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)\s*'
      r'(?:debited?|deducted|spent|paid|withdrawn|transferred?)'
      r')',
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

    // ── 6. CREDIT Check ───────────────────────────────────────────────────
    // Handles patterns from all major Indian banks
    //
    // Patterns covered:
    //   "credited with Rs. 5,000.00"
    //   "credited by Rs 500"
    //   "Rs. 5000 credited to"
    //   "INR 5000.00 credited"
    //   "₹5000 credited"
    //   "received Rs 200"
    //   "deposited Rs. 1,200"
    //   "refunded Rs 399"
    //   "reversed Rs 500"
    //   "added Rs 1000"
    //   "Congratulations! Rs. XXXX credited"   ← HDFC specific
    final creditRegex = RegExp(
      r'(?:'
      // Pattern A: keyword THEN amount
      r'(?:credited?\s*(?:with|by|for)?|received|deposited|refunded?|reversed?|added)\s*'
      r'(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)'
      r'|'
      // Pattern B: amount THEN keyword
      r'(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)\s*'
      r'(?:credited?|received|deposited|refunded?|added)'
      r')',
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
    // Remove commas (Indian number formatting: 1,00,000)
    final sanitized = raw.replaceAll(',', '').trim();
    return double.tryParse(sanitized) ?? 0.0;
  }
}
