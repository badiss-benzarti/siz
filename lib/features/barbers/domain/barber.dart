class Barber {
  const Barber({
    required this.id,
    required this.shopId,
    required this.name,
    required this.phone,
    required this.commissionRate,
    this.isOnDuty = true,
    this.assignedChair,
    required this.createdAt,
    this.isArchived = false,
    this.profileId,
    this.requestedName,
  });

  final String id;
  final String shopId;
  final String name;
  final String phone;
  final double commissionRate; // e.g. 0.60 for 60%
  final bool isOnDuty;
  final int? assignedChair;
  final DateTime createdAt;
  final bool isArchived;

  /// The barber's own account, once they joined with an invitation code.
  /// Set when the barber joins with an invitation code.
  final String? profileId;

  bool get isLinkedToApp => profileId != null;

  /// A new name the barber asked for from their app; the owner accepts or
  /// declines it.
  final String? requestedName;

  Barber copyWith({
    String? id,
    String? shopId,
    String? name,
    String? phone,
    double? commissionRate,
    bool? isOnDuty,
    int? assignedChair,
    DateTime? createdAt,
    bool? isArchived,
    String? profileId,
    String? requestedName,
    bool clearAssignedChair = false,
  }) {
    return Barber(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      commissionRate: commissionRate ?? this.commissionRate,
      isOnDuty: isOnDuty ?? this.isOnDuty,
      assignedChair: clearAssignedChair
          ? null
          : (assignedChair ?? this.assignedChair),
      createdAt: createdAt ?? this.createdAt,
      isArchived: isArchived ?? this.isArchived,
      profileId: profileId ?? this.profileId,
      requestedName: requestedName ?? this.requestedName,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shop_id': shopId,
      'name': name,
      'phone': phone,
      'commission_rate': commissionRate,
      'is_on_duty': isOnDuty ? 1 : 0,
      'assigned_chair': assignedChair,
      'created_at': createdAt.toIso8601String(),
      'is_archived': isArchived ? 1 : 0,
      'profile_id': profileId,
      'requested_name': requestedName,
    };
  }

  factory Barber.fromMap(Map<String, dynamic> map) {
    return Barber(
      id: map['id'] as String,
      shopId: map['shop_id'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String,
      commissionRate: (map['commission_rate'] as num).toDouble(),
      isOnDuty: (map['is_on_duty'] as int) == 1,
      assignedChair: map['assigned_chair'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      profileId: map['profile_id'] as String?,
      requestedName: map['requested_name'] as String?,
    );
  }
}
