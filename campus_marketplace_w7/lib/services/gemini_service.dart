import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _model = 'gemini-3.5-flash-lite';
  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  Future<String> generateText(String prompt) async {
    if (_apiKey.isEmpty) {
      throw Exception('ไม่พบ GEMINI_API_KEY กรุณากำหนดผ่าน --dart-define=GEMINI_API_KEY=...');
    }

    final uri = Uri.parse('$_baseUrl/$_model:generateContent?key=$_apiKey');

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ]
    });

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final candidates = data['candidates'] as List<dynamic>?;

        if (candidates == null || candidates.isEmpty) {
          throw Exception('AI ไม่สามารถให้คำตอบได้ อาจเข้าข่ายเนื้อหาที่ไม่เหมาะสม');
        }

        final firstCandidate = candidates[0] as Map<String, dynamic>;
        final finishReason = firstCandidate['finishReason'] as String?;

        if (finishReason == 'SAFETY') {
          throw Exception('เนื้อหาเข้าข่ายไม่ปลอดภัยตามนโยบายของ Gemini กรุณาเปลี่ยนข้อความ');
        }

        final content = firstCandidate['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List<dynamic>?;

        if (parts == null || parts.isEmpty) {
          throw Exception('ไม่พบข้อความคำตอบจาก Gemini');
        }

        final nonThoughtParts = parts
            .where((p) => (p as Map<String, dynamic>)['thought'] != true && p['text'] != null)
            .map((p) => (p as Map<String, dynamic>)['text'] as String)
            .toList();

        final text = nonThoughtParts.isNotEmpty ? nonThoughtParts.join('\n') : (parts[0]['text'] as String?);
        if (text == null || text.isEmpty) {
          throw Exception('ข้อความคำตอบว่างเปล่า');
        }

        return text;
      }

      if (response.statusCode == 400 || response.statusCode == 403) {
        throw Exception('API Key ไม่ถูกต้อง หรือไม่มีสิทธิ์เข้าถึง (สถานะ ${response.statusCode})');
      }

      if (response.statusCode == 404) {
        throw Exception('ไม่พบโมเดล $_model (สถานะ 404) ตรวจสอบรายชื่อโมเดลล่าสุด');
      }

      if (response.statusCode == 429) {
        throw Exception('ใช้งานเกินโควตาต่อนาที (สถานะ 429) กรุณารอสักครู่แล้วลองใหม่');
      }

      if (response.statusCode == 503) {
        throw Exception('เซิร์ฟเวอร์ Gemini กำลังทำงานหนัก (สถานะ 503) กรุณาลองใหม่อีกครั้ง');
      }

      throw Exception('เกิดข้อผิดพลาดในการเรียก Gemini API (สถานะ ${response.statusCode})');
    } on TimeoutException {
      throw Exception('การเชื่อมต่อกับ Gemini API หมดเวลา (20 วินาที) กรุณาลองใหม่อีกครั้ง');
    } on http.ClientException {
      throw Exception('ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อ');
    } on FormatException {
      throw Exception('ข้อมูลที่ได้รับจาก Gemini ไม่ถูกต้อง');
    } catch (e) {
      rethrow;
    }
  }
}
