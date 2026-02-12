import 'dart:ui';

class TaskList {
  String id;
  String name;
  int colorValue;
  String? folderId;

  TaskList({
    required this.id,
    required this.name,
    this.colorValue = 0xFF42A5F5,
    this.folderId,
  });

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'folderId': folderId,
  };

  factory TaskList.fromJson(Map<String, dynamic> json) => TaskList(
    id: json['id'] as String,
    name: json['name'] as String,
    colorValue: json['colorValue'] as int? ?? 0xFF42A5F5,
    folderId: json['folderId'] as String?,
  );
}
