import 'package:flutter/material.dart';

class Tag {
  String id;
  String name;
  int colorValue;

  Tag({required this.id, required this.name, this.colorValue = 0xFF42A5F5});

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
  };

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
    id: json['id'] as String,
    name: json['name'] as String,
    colorValue: json['colorValue'] as int? ?? 0xFF42A5F5,
  );
}
