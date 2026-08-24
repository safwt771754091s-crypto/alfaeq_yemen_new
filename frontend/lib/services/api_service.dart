import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // رابط الخادم (يمكن تغطيته برابط الإنتاج الحقيقي لاحقاً)
  static const String baseUrl = 'http://localhost:3000';

  static Future<Map<String, dynamic>> checkServerStatus() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/v1/status'));
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'status': 'error', 'message': 'Failed to load status'};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }
}
