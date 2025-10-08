import 'package:hive/hive.dart';

class Document extends HiveObject {
  Document({
    required this.id,
    required this.folderId,
    required this.title,
    required this.transcription,
    required this.summary,
    required this.audioPath,
    this.pdfPath,
    required this.sourceType,
    required this.createdAt,
    required this.updatedAt,
  });

  String id;
  String folderId;
  String title;
  String transcription;
  String summary;
  String audioPath;
  String? pdfPath;
  String sourceType;
  DateTime createdAt;
  DateTime updatedAt;

  Document copyWith({
    String? id,
    String? folderId,
    String? title,
    String? transcription,
    String? summary,
    String? audioPath,
    String? pdfPath,
    String? sourceType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Document(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      transcription: transcription ?? this.transcription,
      summary: summary ?? this.summary,
      audioPath: audioPath ?? this.audioPath,
      pdfPath: pdfPath ?? this.pdfPath,
      sourceType: sourceType ?? this.sourceType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id'] as String,
      folderId: json['folderId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      transcription: json['transcription'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      audioPath: json['audioPath'] as String? ?? '',
      pdfPath: json['pdfPath'] as String?,
      sourceType: json['sourceType'] as String? ?? 'upload',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'folderId': folderId,
      'title': title,
      'transcription': transcription,
      'summary': summary,
      'audioPath': audioPath,
      'pdfPath': pdfPath,
      'sourceType': sourceType,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class DocumentAdapter extends TypeAdapter<Document> {
  @override
  int get typeId => 1;

  @override
  Document read(BinaryReader reader) {
    final id = reader.readString();
    final folderId = reader.readString();
    final title = reader.readString();
    final transcription = reader.readString();
    final summary = reader.readString();
    final audioPath = reader.readString();
    final hasPdf = reader.readBool();
    final pdfPath = hasPdf ? reader.readString() : null;
    final sourceType = reader.readString();
    final createdAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());

    return Document(
      id: id,
      folderId: folderId,
      title: title,
      transcription: transcription,
      summary: summary,
      audioPath: audioPath,
      pdfPath: pdfPath,
      sourceType: sourceType,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  void write(BinaryWriter writer, Document obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.folderId)
      ..writeString(obj.title)
      ..writeString(obj.transcription)
      ..writeString(obj.summary)
      ..writeString(obj.audioPath)
      ..writeBool(obj.pdfPath != null);

    if (obj.pdfPath != null) {
      writer.writeString(obj.pdfPath!);
    }

    writer
      ..writeString(obj.sourceType)
      ..writeInt(obj.createdAt.millisecondsSinceEpoch)
      ..writeInt(obj.updatedAt.millisecondsSinceEpoch);
  }
}
