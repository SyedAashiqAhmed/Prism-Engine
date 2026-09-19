/// Strict typed domain model for transactions and notifications in Prism Engine.
class TransactionModel {
  final int? id;
  final String sourceKey;
  final String packageName;
  final String? senderHeader;
  final String? title;
  final String text;
  final int timestamp;
  final String category;
  final String? merchant;
  final double? amount;
  final String? txnType; // 'DEBIT' or 'CREDIT'
  final bool isPriority;

  const TransactionModel({
    this.id,
    required this.sourceKey,
    required this.packageName,
    this.senderHeader,
    this.title,
    required this.text,
    required this.timestamp,
    required this.category,
    this.merchant,
    this.amount,
    this.txnType,
    this.isPriority = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'source_key': sourceKey,
      'package_name': packageName,
      'sender_header': senderHeader,
      'title': title,
      'text': text,
      'timestamp': timestamp,
      'category': category,
      'merchant': merchant,
      'amount': amount,
      'txn_type': txnType,
      'is_priority': isPriority ? 1 : 0,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'] as int?,
      sourceKey: map['source_key'] as String? ?? '',
      packageName: map['package_name'] as String? ?? '',
      senderHeader: map['sender_header'] as String?,
      title: map['title'] as String?,
      text: map['text'] as String? ?? '',
      timestamp: map['timestamp'] as int? ?? 0,
      category: map['category'] as String? ?? 'General',
      merchant: map['merchant'] as String?,
      amount: (map['amount'] as num?)?.toDouble(),
      txnType: map['txn_type'] as String?,
      isPriority: (map['is_priority'] as int? ?? 0) == 1,
    );
  }

  TransactionModel copyWith({
    int? id,
    String? sourceKey,
    String? packageName,
    String? senderHeader,
    String? title,
    String? text,
    int? timestamp,
    String? category,
    String? merchant,
    double? amount,
    String? txnType,
    bool? isPriority,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      sourceKey: sourceKey ?? this.sourceKey,
      packageName: packageName ?? this.packageName,
      senderHeader: senderHeader ?? this.senderHeader,
      title: title ?? this.title,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      category: category ?? this.category,
      merchant: merchant ?? this.merchant,
      amount: amount ?? this.amount,
      txnType: txnType ?? this.txnType,
      isPriority: isPriority ?? this.isPriority,
    );
  }

  @override
  String toString() {
    return 'TransactionModel(id: $id, type: $txnType, amount: $amount, merchant: $merchant, time: $timestamp)';
  }
}
