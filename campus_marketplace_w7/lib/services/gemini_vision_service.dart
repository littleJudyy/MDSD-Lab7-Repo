import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/listing_draft.dart';

class GeminiVisionService {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _model = 'gemini-3.5-flash-lite';
  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  Future<ListingDraft> analyzeProductImage({
    required File imageFile,
    required String prompt,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('ไม่พบ GEMINI_API_KEY กรุณากำหนดผ่าน --dart-define=GEMINI_API_KEY=...');
    }

    // 1. อ่านไฟล์รูปภาพเป็นไบต์ แล้วแปลงเป็น Base64
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    String mimeType = 'image/jpeg';
    final path = imageFile.path.toLowerCase();
    if (path.endsWith('.png')) {
      mimeType = 'image/png';
    } else if (path.endsWith('.webp')) {
      mimeType = 'image/webp';
    }

    final uri = Uri.parse('$_baseUrl/$_model:generateContent?key=$_apiKey');

    // 2. ส่ง Prompt และ Inline Data (รูปภาพ) ไปพร้อมกันใน parts
    // และใช้ responseSchema เพื่อบังคับให้ตอบกลับเป็น JSON เท่านั้น
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': mimeType,
                'data': base64Image,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'responseSchema': {
          'type': 'OBJECT',
          'properties': {
            'title': {'type': 'STRING'},
            'category': {'type': 'STRING'},
            'description': {'type': 'STRING'}
          },
          'required': ['title', 'category', 'description']
        }
      }
    });

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        // ถอดรหัส JSON ชั้นที่ 1: แกะโครงสร้าง Response ของ Gemini API
        final Map<String, dynamic> data = jsonDecode(response.body);
        final candidates = data['candidates'] as List<dynamic>?;

        if (candidates == null || candidates.isEmpty) {
          throw Exception('AI ไม่สามารถวิเคราะห์ภาพนี้ได้ อาจเข้าข่ายเนื้อหาที่ไม่เหมาะสม ลองใช้ภาพอื่น');
        }

        final firstCandidate = candidates[0] as Map<String, dynamic>;
        final finishReason = firstCandidate['finishReason'] as String?;

        if (finishReason == 'SAFETY') {
          throw Exception('เนื้อหาที่วิเคราะห์เข้าข่ายไม่ปลอดภัยตามนโยบายของ Gemini กรุณาใช้ภาพอื่น');
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

        final rawJsonText = nonThoughtParts.isNotEmpty ? nonThoughtParts.join('\n') : (parts[0]['text'] as String?);
        if (rawJsonText == null || rawJsonText.isEmpty) {
          throw Exception('ข้อความคำตอบว่างเปล่า');
        }

        // ถอดรหัส JSON ชั้นที่ 2: แปลงข้อความ JSON String ให้เป็น Map
        final Map<String, dynamic> draftJson = jsonDecode(rawJsonText);
        return ListingDraft.fromJson(draftJson);
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
      throw Exception('การเชื่อมต่อกับ Gemini API หมดเวลา (25 วินาที) กรุณาลองใหม่อีกครั้ง');
    } on http.ClientException {
      throw Exception('ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อ');
    } on FormatException catch (e) {
      throw Exception('รูปแบบ JSON จาก Gemini ไม่ถูกต้อง: $e');
    } catch (e) {
      rethrow;
    }
  }
}
