class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.shopId,
    required this.name,
    required this.price,
    this.durationMinutes = 30,
  });

  final String id;
  final String shopId;
  final String name;
  final double price;
  final int durationMinutes;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shop_id': shopId,
      'name': name,
      'price': price,
      'duration_minutes': durationMinutes,
    };
  }

  factory ServiceItem.fromMap(Map<String, dynamic> map) {
    return ServiceItem(
      id: map['id'] as String,
      shopId: map['shop_id'] as String,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      durationMinutes: map['duration_minutes'] as int? ?? 30,
    );
  }
}

class ShopProfile {
  const ShopProfile({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.address,
    required this.phone,
    required this.totalChairs,
    required this.createdAt,
    this.services = const [],
    this.latitude,
    this.longitude,
    this.isOpen = true,
    this.isListed = false,
  });

  final String id;
  final String ownerId;
  final String name;
  final String address;
  final String phone;
  final int totalChairs;
  final DateTime createdAt;
  final List<ServiceItem> services;

  /// Unused in Siz (no map); kept so the table matches its columns.
  final double? latitude;
  final double? longitude;

  /// Open now (shown to clients as open or closed).
  final bool isOpen;

  /// Shown in the clients' list of salons.
  final bool isListed;

  bool get hasLocation => latitude != null && longitude != null;

  ShopProfile copyWith({
    String? id,
    String? ownerId,
    String? name,
    String? address,
    String? phone,
    int? totalChairs,
    DateTime? createdAt,
    List<ServiceItem>? services,
    double? latitude,
    double? longitude,
    bool? isOpen,
    bool? isListed,
  }) {
    return ShopProfile(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      totalChairs: totalChairs ?? this.totalChairs,
      createdAt: createdAt ?? this.createdAt,
      services: services ?? this.services,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isOpen: isOpen ?? this.isOpen,
      isListed: isListed ?? this.isListed,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'name': name,
      'address': address,
      'phone': phone,
      'total_chairs': totalChairs,
      'created_at': createdAt.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'is_open': isOpen ? 1 : 0,
      'is_listed': isListed ? 1 : 0,
    };
  }

  /// Reads a row of the database (flags as 0/1).
  factory ShopProfile.fromMap(
    Map<String, dynamic> map, {
    List<ServiceItem> services = const [],
  }) {
    bool flag(Object? value, bool fallback) =>
        value == null ? fallback : value == true || value == 1;

    return ShopProfile(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      name: map['name'] as String,
      address: map['address'] as String,
      phone: map['phone'] as String,
      totalChairs: map['total_chairs'] as int? ?? 8,
      createdAt: DateTime.parse(map['created_at'] as String),
      services: services,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      isOpen: flag(map['is_open'], true),
      isListed: flag(map['is_listed'], false),
    );
  }
}
