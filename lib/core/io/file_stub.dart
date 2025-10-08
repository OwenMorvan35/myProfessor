import 'dart:typed_data';

class File {
  File(String path) : _path = path;

  final String _path;

  String get path => _path;

  Uri get uri => Uri.parse(_path);

  Future<Uint8List> readAsBytes() async => Uint8List(0);
}
