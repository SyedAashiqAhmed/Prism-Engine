import 'package:flutter_notification_listener/flutter_notification_listener.dart';

import 'axio_parser.dart';
import 'dedup_service.dart';

/// Converts notification text to a transaction and persists it for the
/// dashboard, independent of whether the UI isolate is running.
class NotificationProcessor {
  static Future<bool> process(NotificationEvent event) async {
    final packageName = event.packageName ?? '';
    final title = event.title ?? '';
    final notificationText = event.text;
    final text = notificationText != null && notificationText.trim().isNotEmpty
        ? notificationText
        : event.message ?? '';
    if (title.trim().isEmpty && text.trim().isEmpty) return false;

    final parsed = AxioParser.parse(text, title: title);
    if (parsed == null) return false;

    final timestamp = event.timestamp;
    final transactionTimestamp = timestamp != null && timestamp > 0
        ? timestamp
        : DateTime.now().millisecondsSinceEpoch;

    final sourceKey =
        '${packageName}_${event.uniqueId ?? ''}_${transactionTimestamp}_${parsed.type}_${parsed.amount}';
    await DedupService.insertIfUnique(
      amount: parsed.amount,
      type: parsed.type,
      timestamp: transactionTimestamp,
      merchant: parsed.merchant,
      row: {
        'source_key': sourceKey,
        'package_name': packageName,
        'sender_header': null,
        'title': title.isNotEmpty ? title : null,
        'text': text,
        'timestamp': transactionTimestamp,
        'category': 'Bank',
        'merchant': parsed.merchant,
        'amount': parsed.amount,
        'txn_type': parsed.type,
        'is_priority': 0,
      },
    );
    return true;
  }
}
