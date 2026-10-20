class OwnerAccount {
  const OwnerAccount({
    required this.id,
    required this.email,
    required this.passwordHash,
    required this.salt,
    required this.fullName,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String passwordHash;
  final String salt;
  final String fullName;
  final DateTime createdAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'password_hash': passwordHash,
      'salt': salt,
      'full_name': fullName,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory OwnerAccount.fromMap(Map<String, dynamic> map) {
    return OwnerAccount(
      id: map['id'] as String,
      email: map['email'] as String,
      passwordHash: map['password_hash'] as String,
      salt: map['salt'] as String,
      fullName: map['full_name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
