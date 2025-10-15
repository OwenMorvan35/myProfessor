import 'package:hive/hive.dart';

class Document extends HiveObject {
  Document({
    required this.id,
    required this.folderId,
    required this.title,
    required this.transcription,
    required this.summary,
    required this.course,
    required this.audioPath,
    this.originalAudioPath,
    required this.processingStatus,
    this.processingError,
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
  String course;
  String audioPath;
  String? originalAudioPath;
  String processingStatus;
  String? processingError;
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
    String? course,
    String? audioPath,
    String? originalAudioPath,
    String? processingStatus,
    String? processingError,
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
      course: course ?? this.course,
      audioPath: audioPath ?? this.audioPath,
      originalAudioPath: originalAudioPath ?? this.originalAudioPath,
      processingStatus: processingStatus ?? this.processingStatus,
      processingError: processingError ?? this.processingError,
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
      course: json['course'] as String? ?? '',
      audioPath: json['audioPath'] as String? ?? '',
      originalAudioPath: json['originalAudioPath'] as String?,
      processingStatus: json['processingStatus'] as String? ?? 'pending',
      processingError: json['processingError'] as String?,
      pdfPath: json['pdfPath'] as String?,
      sourceType: json['sourceType'] as String? ?? 'upload',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'folderId': folderId,
      'title': title,
      'transcription': transcription,
      'summary': summary,
      'course': course,
      'audioPath': audioPath,
      'originalAudioPath': originalAudioPath,
      'processingStatus': processingStatus,
      'processingError': processingError,
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
    var course = '';
    try {
      final hasCourse = reader.readBool();
      if (hasCourse) {
        course = reader.readString();
      }
    } catch (_) {
      course = '';
    }
    String? originalAudioPath;
    String processingStatus = 'pending';
    String? processingError;
    try {
      if (reader.availableBytes > 0) {
        final hasOriginal = reader.readBool();
        if (hasOriginal) {
          originalAudioPath = reader.readString();
        }
        if (reader.availableBytes > 0) {
          processingStatus = reader.readString();
        }
        if (reader.availableBytes > 0) {
          final hasProcessingError = reader.readBool();
          if (hasProcessingError && reader.availableBytes > 0) {
            processingError = reader.readString();
          }
        }
      }
    } catch (_) {
      processingStatus = transcription.isNotEmpty ? 'completed' : 'pending';
      processingError = null;
    }

    return Document(
      id: id,
      folderId: folderId,
      title: title,
      transcription: transcription,
      summary: summary,
      course: course,
      audioPath: audioPath,
      originalAudioPath: originalAudioPath,
      processingStatus: processingStatus,
      processingError: processingError,
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
      ..writeInt(obj.updatedAt.millisecondsSinceEpoch)
      ..writeBool(obj.course.isNotEmpty);

    if (obj.course.isNotEmpty) {
      writer.writeString(obj.course);
    }

    final hasOriginal = (obj.originalAudioPath ?? '').isNotEmpty;
    writer.writeBool(hasOriginal);
    if (hasOriginal) {
      writer.writeString(obj.originalAudioPath!);
    }

    writer.writeString(obj.processingStatus);
    final hasProcessingError = (obj.processingError ?? '').isNotEmpty;
    writer.writeBool(hasProcessingError);
    if (hasProcessingError) {
      writer.writeString(obj.processingError!);
    }
  }
}
