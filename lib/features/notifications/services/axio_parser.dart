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
    final fullText = title != null && title.isNotEmpty
        ? '$title $rawText'
        : rawText;
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
        lower.contains('loan offer')) {
      return null;
    }

    // Remove balances and available limits so they cannot be mistaken for the
    // transaction amount.
    final textNoBal = _removeBalances(fullText);

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
        r'\bto\s+([A-Za-z0-9][A-Za-z0-9\s&._-]{2,30}?)(?:\s+at\b|\s+on\b|\s+ref\b|\s+upi\b|\s+avl\b|\s+dated\b|\s+via\b|\s*[,.]|$)',
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

    final rawTextNoBal = _removeBalances(rawText);
    var debit = _findTransaction(
      rawTextNoBal,
      type: 'DEBIT',
      keywords:
          r'debit(?:ed)?|deducted|withdrawn|withdrawal|spent|paid|payment|purchase|sent|transfer(?:red)?|charged',
    );
    var credit = _findTransaction(
      rawTextNoBal,
      type: 'CREDIT',
      keywords:
          r'credit(?:ed)?(?!\s+card)|received|deposited|refund(?:ed)?|reversed?|added|cashback',
    );

    // Prefer explicit transaction wording in the notification body over a
    // potentially generic or stale title such as "Debit alert".
    if (debit == null && credit == null) {
      debit = _findTransaction(
        textNoBal,
        type: 'DEBIT',
        keywords:
            r'debit(?:ed)?|deducted|withdrawn|withdrawal|spent|paid|payment|purchase|sent|transfer(?:red)?|charged',
      );
      credit = _findTransaction(
        textNoBal,
        type: 'CREDIT',
        keywords:
            r'credit(?:ed)?(?!\s+card)|received|deposited|refund(?:ed)?|reversed?|added|cashback',
      );
    }

    if (debit == null && credit == null) return null;
    if (debit != null && credit != null && debit.start == credit.start) {
      return null;
    }
    final transaction = debit == null
        ? credit!
        : credit == null || debit.start < credit.start
        ? debit
        : credit;

    return ParsedTxn(
      type: transaction.type,
      amount: transaction.amount,
      merchant: merchant,
      accountLast4: accountLast4,
    );
  }

  static _TransactionMatch? _findTransaction(
    String text, {
    required String type,
    required String keywords,
  }) {
    const amount = r'([\d,]+(?:\.\d{1,2})?)';
    const currency = r'(?:rs\.?|inr|₹)\s*';
    final amountAfterKeywordWithCurrency = RegExp(
      '(?:\\b(?:$keywords)\\b)(?:\\s+[a-z0-9*/.-]+){0,8}?'
      '\\s*$currency$amount',
      caseSensitive: false,
    );
    final amountAfterKeywordWithoutCurrency = RegExp(
      '(?:\\b(?:$keywords)\\b)\\s*(?:(?:of|by|for|with)\\s*)?$amount',
      caseSensitive: false,
    );
    final amountBeforeKeyword = RegExp(
      '(?:rs\\.?|inr|₹)\\s*$amount\\s+(?:(?:has|was|is)\\s+been\\s+)?'
      '(?:successfully\\s+)?\\b(?:$keywords)\\b',
      caseSensitive: false,
    );

    final matches = <_TransactionMatch>[];
    for (final match in [
      amountAfterKeywordWithCurrency.firstMatch(text),
      amountAfterKeywordWithoutCurrency.firstMatch(text),
      amountBeforeKeyword.firstMatch(text),
    ]) {
      if (match == null) continue;
      final value = _cleanAmount(match.group(1));
      if (value > 0) {
        matches.add(_TransactionMatch(match.start, type, value));
      }
    }
    if (matches.isEmpty) return null;
    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches.first;
  }

  static double _cleanAmount(String? raw) {
    if (raw == null) return 0.0;
    // Remove commas (Indian number formatting: 1,00,000)
    final sanitized = raw.replaceAll(',', '').trim();
    return double.tryParse(sanitized) ?? 0.0;
  }

  static String _removeBalances(String text) {
    return text.replaceAll(
      RegExp(
        r'\b(?:avl\.?\s*(?:bal(?:ance)?|limit|credit)|available\s+(?:balance|limit|credit)|current\s+balance|closing\s+balance|a\/c\s*bal(?:ance)?|avbl|balance|bal)\b\s*:?\s*(?:rs\.?|inr|₹)?\s*[\d,]+(?:\.\d{1,2})?',
        caseSensitive: false,
      ),
      '',
    );
  }
}

class _TransactionMatch {
  final int start;
  final String type;
  final double amount;

  const _TransactionMatch(this.start, this.type, this.amount);
}
