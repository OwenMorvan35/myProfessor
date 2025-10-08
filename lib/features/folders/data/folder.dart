import 'package:hive/hive.dart';

class Folder extends HiveObject {
  Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.documentIds,
  });

  String id;
  String name;
  DateTime createdAt;
  DateTime updatedAt;
  List<String> documentIds;

  Folder copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? documentIds,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      documentIds: documentIds ?? List<String>.from(this.documentIds),
    );
  }

  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      documentIds: (json['documentIds'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'documentIds': documentIds,
    };
  }
}

class FolderAdapter extends TypeAdapter<Folder> {
  @override
  int get typeId => 0;

  @override
  Folder read(BinaryReader reader) {
    final id = reader.readString();
    final name = reader.readString();
    final createdAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final length = reader.readInt();
    final docs = <String>[];
    for (var i = 0; i < length; i++) {
      docs.add(reader.readString());
    }

    return Folder(
      id: id,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      documentIds: docs,
    );
  }

  @override
  void write(BinaryWriter writer, Folder obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.name)
      ..writeInt(obj.createdAt.millisecondsSinceEpoch)
      ..writeInt(obj.updatedAt.millisecondsSinceEpoch)
      ..writeInt(obj.documentIds.length);

    for (final docId in obj.documentIds) {
      writer.writeString(docId);
    }
  }
}
