import 'task.dart';
import 'task_list.dart';
import 'folder.dart';
import 'tag.dart';
import 'smart_list.dart';

/// Root container for all app data – serialized to/from JSON for local
/// persistence and Google Drive sync.
class AppData {
  List<Task> tasks;
  List<TaskList> lists;
  List<Folder> folders;
  List<Tag> tags;
  List<SmartList> smartLists;
  DateTime lastModified;

  AppData({
    List<Task>? tasks,
    List<TaskList>? lists,
    List<Folder>? folders,
    List<Tag>? tags,
    List<SmartList>? smartLists,
    DateTime? lastModified,
  }) : tasks = tasks ?? [],
       lists = lists ?? [],
       folders = folders ?? [],
       tags = tags ?? [],
       smartLists = smartLists ?? [],
       lastModified = lastModified ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'tasks': tasks.map((t) => t.toJson()).toList(),
    'lists': lists.map((l) => l.toJson()).toList(),
    'folders': folders.map((f) => f.toJson()).toList(),
    'tags': tags.map((t) => t.toJson()).toList(),
    'smartLists': smartLists.map((s) => s.toJson()).toList(),
    'lastModified': lastModified.toIso8601String(),
  };

  factory AppData.fromJson(Map<String, dynamic> json) => AppData(
    tasks:
        (json['tasks'] as List?)
            ?.map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    lists:
        (json['lists'] as List?)
            ?.map((e) => TaskList.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    folders:
        (json['folders'] as List?)
            ?.map((e) => Folder.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    tags:
        (json['tags'] as List?)
            ?.map((e) => Tag.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    smartLists:
        (json['smartLists'] as List?)
            ?.map((e) => SmartList.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    lastModified: json['lastModified'] != null
        ? DateTime.parse(json['lastModified'] as String)
        : DateTime.now(),
  );
}
