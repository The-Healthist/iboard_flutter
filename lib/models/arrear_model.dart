class ArrearModel {
  final String id;
  final String blgId;
  final String roomNo;
  final String customerName;
  final double amount;
  final DateTime dueDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final bool isDeleted;

  ArrearModel({
    required this.id,
    required this.blgId,
    required this.roomNo,
    required this.customerName,
    required this.amount,
    required this.dueDate,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.isDeleted,
  });

  factory ArrearModel.fromJson(Map<String, dynamic> json) {
    return ArrearModel(
      id: json['id']?.toString() ?? '',
      blgId: json['blg_id']?.toString() ?? json['blgId']?.toString() ?? '',
      roomNo: json['room_no']?.toString() ?? json['roomNo']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ??
          json['customerName']?.toString() ??
          '',
      amount: (json['amount'] is num) ? json['amount'].toDouble() : 0.0,
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'].toString())
          : json['dueDate'] != null
              ? DateTime.parse(json['dueDate'].toString())
              : DateTime.now(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : json['createdAt'] != null
              ? DateTime.parse(json['createdAt'].toString())
              : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : json['updatedAt'] != null
              ? DateTime.parse(json['updatedAt'].toString())
              : DateTime.now(),
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'].toString())
          : json['deletedAt'] != null
              ? DateTime.parse(json['deletedAt'].toString())
              : null,
      isDeleted: json['is_deleted'] ?? json['isDeleted'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'blg_id': blgId,
      'room_no': roomNo,
      'customer_name': customerName,
      'amount': amount,
      'due_date': dueDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'is_deleted': isDeleted,
    };
  }
}
