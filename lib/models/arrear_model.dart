// 物业管理费用相关模型
class ManagementFeeModel {
  final List<Block> blocks;

  ManagementFeeModel({required this.blocks});

  factory ManagementFeeModel.fromJson(Map<String, dynamic> json) {
    return ManagementFeeModel(
      blocks: (json['blocks'] as List<dynamic>?)
              ?.map((block) => Block.fromJson(block as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'blocks': blocks.map((block) => block.toJson()).toList(),
    };
  }
}

class Block {
  final String name;
  final List<Floor> floors;

  Block({required this.name, required this.floors});

  factory Block.fromJson(Map<String, dynamic> json) {
    return Block(
      name: json['name']?.toString() ?? '',
      floors: (json['floors'] as List<dynamic>?)
              ?.map((floor) => Floor.fromJson(floor as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'floors': floors.map((floor) => floor.toJson()).toList(),
    };
  }
}

class Floor {
  final String name;
  final List<Unit> units;

  Floor({required this.name, required this.units});

  factory Floor.fromJson(Map<String, dynamic> json) {
    return Floor(
      name: json['name']?.toString() ?? '',
      units: (json['units'] as List<dynamic>?)
              ?.map((unit) => Unit.fromJson(unit as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'units': units.map((unit) => unit.toJson()).toList(),
    };
  }
}

class Unit {
  final String name;
  final List<Bill> bills;

  Unit({required this.name, required this.bills});

  factory Unit.fromJson(Map<String, dynamic> json) {
    return Unit(
      name: json['name']?.toString() ?? '',
      bills: (json['bills'] as List<dynamic>?)
              ?.map((bill) => Bill.fromJson(bill as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'bills': bills.map((bill) => bill.toJson()).toList(),
    };
  }
}

class Bill {
  final String period;
  final dynamic value; // 可以是数字或字符串 "已付"
  final String? itemId; // 其他费用特有字段
  final String? remark; // 其他费用特有字段

  Bill({
    required this.period,
    required this.value,
    this.itemId,
    this.remark,
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    // 处理物业管理费用的账单格式
    if (json.length == 1) {
      final entry = json.entries.first;
      return Bill(
        period: entry.key,
        value: entry.value,
      );
    }

    // 处理其他费用的账单格式
    return Bill(
      period: json['trs_to']?.toString() ?? '',
      value: json['trs_val'],
      itemId: json['item_id']?.toString(),
      remark: json['remark']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    if (itemId != null || remark != null) {
      // 其他费用格式
      return {
        'trs_to': period,
        'trs_val': value,
        if (itemId != null) 'item_id': itemId,
        if (remark != null) 'remark': remark,
      };
    } else {
      // 物业管理费用格式
      return {period: value};
    }
  }

  ///1, 检查是否已付款
  bool get isPaid => value == "已付";

  ///2, 获取费用金额（如果是数字）
  double? get amount {
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  ///3, 获取费用状态描述
  String get statusDescription {
    if (isPaid) {
      return "已付";
    }
    if (amount != null) {
      if (amount! < 0) {
        return "欠费 ${amount!.abs().toStringAsFixed(0)}";
      } else {
        return "余额 ${amount!.toStringAsFixed(0)}";
      }
    }
    return "未知状态";
  }

  ///4, 获取完整的费用信息（用于其他费用显示）
  Map<String, dynamic> get fullFeeInfo {
    return {
      'period': period,
      'value': value,
      'itemId': itemId,
      'remark': remark,
    };
  }

  ///5, 是否为其他费用（有itemId或remark）
  bool get isOtherFee => itemId != null || remark != null;
}

// 其他公摊费用相关模型
class OtherFeeModel {
  final List<Block> blocks;

  OtherFeeModel({required this.blocks});

  factory OtherFeeModel.fromJson(Map<String, dynamic> json) {
    return OtherFeeModel(
      blocks: (json['blocks'] as List<dynamic>?)
              ?.map((block) => Block.fromJson(block as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'blocks': blocks.map((block) => block.toJson()).toList(),
    };
  }
}

// 保留原有的欠费模型以保持向后兼容
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
