/// Index that tracks per-entity modification timestamps and deletions.
///
/// Stored both remotely (on Dropbox as `/index.json`) and locally to enable
/// efficient diffing during sync.
class SyncIndex {
  /// Entity key (e.g. `"tasks/abc-123"`) → last modified timestamp.
  Map<String, DateTime> entities;

  /// Entity key → deletion timestamp.
  /// Used to propagate deletions across devices.
  Map<String, DateTime> deletions;

  SyncIndex({
    Map<String, DateTime>? entities,
    Map<String, DateTime>? deletions,
  })  : entities = entities ?? {},
        deletions = deletions ?? {};

  Map<String, dynamic> toJson() => {
        'entities':
            entities.map((k, v) => MapEntry(k, v.toIso8601String())),
        'deletions':
            deletions.map((k, v) => MapEntry(k, v.toIso8601String())),
      };

  factory SyncIndex.fromJson(Map<String, dynamic> json) => SyncIndex(
        entities: (json['entities'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, DateTime.parse(v as String)),
        ),
        deletions: (json['deletions'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, DateTime.parse(v as String)),
        ),
      );
}
