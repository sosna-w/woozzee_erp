class Warehouse {
  final int id;
  final String name;
  final String address;
  final String workTime;
  final bool isActive;
  final bool isTransitActive;

  Warehouse({
    required this.id,
    required this.name,
    required this.address,
    required this.workTime,
    required this.isActive,
    required this.isTransitActive,
  });

  factory Warehouse.fromJson(Map<String, dynamic> json) {
    return Warehouse(
      id: json['ID'] ?? 0,
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      workTime: json['workTime'] ?? '',
      isActive: json['isActive'] ?? false,
      isTransitActive: json['isTransitActive'] ?? false,
    );
  }
}