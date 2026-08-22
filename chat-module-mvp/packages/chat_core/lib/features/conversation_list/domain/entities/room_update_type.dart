class RoomUpdateType {
  const RoomUpdateType({
    required this.id,
    required this.code,
    required this.name,
    this.description = '',
    this.displayOrder = 0,
  });

  final String id;
  final String code;
  final String name;
  final String description;
  final int displayOrder;

  factory RoomUpdateType.fromJson(Map<String, dynamic> json) {
    return RoomUpdateType(
      id: (json['id'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'description': description,
        'displayOrder': displayOrder,
      };
}
