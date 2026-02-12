import 'dart:ui';

class TaskList {
  String id;
  String name;
  int? colorValue;
  String? folderId;
  int order;

  TaskList({
    required this.id,
    required this.name,
    this.colorValue,
    this.folderId,
    this.order = 0,
  });

  Color? get color => colorValue != null ? Color(colorValue!) : null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'folderId': folderId,
    'order': order,
  };

  factory TaskList.fromJson(Map<String, dynamic> json) => TaskList(
    id: json['id'] as String,
    name: json['name'] as String,
    colorValue: json['colorValue'] as int?,
    folderId: json['folderId'] as String?,
    order: json['order'] as int? ?? 0,
  );
}
