import 'package:flutter/material.dart';

class TaskList {
  String id;
  String name;
  int iconCodePoint;
  int colorValue;
  String? folderId;

  TaskList({
    required this.id,
    required this.name,
    this.iconCodePoint = 0xe16a, // Icons.list
    this.colorValue = 0xFF42A5F5,
    this.folderId,
  });

  IconData get icon => IconData(iconCodePoint, fontFamily: 'MaterialIcons');
  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconCodePoint': iconCodePoint,
        'colorValue': colorValue,
        'folderId': folderId,
      };

  factory TaskList.fromJson(Map<String, dynamic> json) => TaskList(
        id: json['id'] as String,
        name: json['name'] as String,
        iconCodePoint: json['iconCodePoint'] as int? ?? 0xe16a,
        colorValue: json['colorValue'] as int? ?? 0xFF42A5F5,
        folderId: json['folderId'] as String?,
      );
}
