import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get apiBaseUrl => _get('API_BASE_URL', fallback: 'http://localhost:8080/api');
  static bool get shareOpenInBrowser => _get('SHARE_OPEN_IN_BROWSER', fallback: 'true').toLowerCase() == 'true';

  static String _get(String key, {required String fallback}) {
    return dotenv.env[key] ?? fallback;
  }
}
