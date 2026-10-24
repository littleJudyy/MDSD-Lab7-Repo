import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/listing_draft.dart';
import '../services/gemini_vision_service.dart';

class SellItemPage extends StatefulWidget {
  const SellItemPage({super.key});

  @override
  State<SellItemPage> createState() => _SellItemPageState();
}

class _SellItemPageState extends State<SellItemPage> {
  static const _prompt = '''
คุณคือผู้ช่วยเขียนประกาศขายของมือสองในตลาดนัดออนไลน์สำหรับนักศึกษามหาวิทยาลัย
จากรูปภาพสินค้าที่แนบมา ให้วิเคราะห์แล้วตอบกลับเป็น JSON เท่านั้น ตามโครงสร้างนี้:
{
  "title": "ชื่อประกาศสั้นกระชับ ไม่เกิน 40 ตัวอักษร",
  "category": "หมวดหมู่ที่เหมาะสมที่สุด เลือกจาก: หนังสือเรียน, อุปกรณ์อิเล็กทรอนิกส์, ของแต่งหอพัก, เสื้อผ้า, อื่นๆ",
  "description": "คำบรรยายสินค้า 2-3 ประโยค ที่ดึงดูดผู้ซื้อและบอกสภาพของสินค้าตามที่เห็นในภาพ"
}
ห้ามตอบข้อความอื่นนอกเหนือจาก JSON ดังกล่าว
''';

  File? _imageFile;
  bool _isPicking = false;
  bool _isLoading = false;
  String? _errorMessage;
  ListingDraft? _savedDraft;

  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_isPicking) return;
    _isPicking = true;
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      setState(() {
        _imageFile = File(pickedFile.path);
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('Error picking image: $e');
    } finally {
      _isPicking = false;
    }
  }

  Future<void> _analyzeWithAI() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกรูปภาพสินค้าก่อน')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final draft = await GeminiVisionService().analyzeProductImage(
        imageFile: _imageFile!,
        prompt: _prompt,
      );

      if (!mounted) return;
      setState(() {
        _titleController.text = draft.title;
        _categoryController.text = draft.category;
        _descriptionController.text = draft.description;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _confirmDraft() {
    // เก็บค่าจากฟอร์มไว้ใน State ของแอป
    _savedDraft = ListingDraft(
      title: _titleController.text,
      category: _categoryController.text,
      description: _descriptionController.text,
    );
    debugPrint('Saved draft: ${_savedDraft?.title}');

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('บันทึกร่างประกาศเรียบร้อยแล้ว'),
        backgroundColor: Colors.green,
      ),
    );

    setState(() {
      _imageFile = null;
      _titleController.clear();
      _categoryController.clear();
      _descriptionController.clear();
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ลงประกาศขายสินค้า'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // แสดงตัวอย่างภาพสินค้า
            if (_imageFile != null)
              Container(
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.file(
                  _imageFile!,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image, size: 64, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('ยังไม่ได้เลือกรูปภาพ', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // ปุ่มเลือกรูปภาพ และ ปุ่มให้ AI ช่วยแนะนำ
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('เลือกรูปภาพสินค้า'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_imageFile != null && !_isLoading)
                        ? _analyzeWithAI
                        : null,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('ให้ AI ช่วยแนะนำ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // สถานะ Loading: กำลังวิเคราะห์
            if (_isLoading)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    SizedBox(width: 16),
                    Text(
                      'AI กำลังวิเคราะห์ภาพสินค้า...',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

            // สถานะ Error: ข้อความสีแดง
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // ฟอร์มตรวจทานและแก้ไข (Human-in-the-loop)
            Text(
              'ข้อมูลสินค้า (ตรวจสอบและแก้ไขได้)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'ชื่อประกาศสินค้า',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: 'หมวดหมู่',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'คำบรรยายสินค้า',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
            ),
            const SizedBox(height: 16),

            // ปุ่มยืนยันร่างประกาศ
            ElevatedButton(
              onPressed: _confirmDraft,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'ยืนยันร่างประกาศ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
