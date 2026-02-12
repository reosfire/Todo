class Folder {
  String id;
  String name;
  int order;

  Folder({required this.id, required this.name, this.order = 0});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'order': order};

  factory Folder.fromJson(Map<String, dynamic> json) => Folder(
        id: json['id'] as String,
        name: json['name'] as String,
        order: json['order'] as int? ?? 0,
      );
}
