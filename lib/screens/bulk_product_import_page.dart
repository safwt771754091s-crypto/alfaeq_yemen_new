import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_sections.dart';
import '../services/supabase_service.dart';

class BulkProductImportPage extends StatefulWidget {
  const BulkProductImportPage({super.key});

  @override
  State<BulkProductImportPage> createState() => _BulkProductImportPageState();
}

class _BulkProductImportPageState extends State<BulkProductImportPage> {
  String? _selectedStoreId;
  String? _selectedSectionId;
  bool _busy = false;
  String? _fileName;
  List<_ImportRow> _preview = [];
  List<_ImportError> _errors = [];
  int _validCount = 0;
  int _duplicateCount = 0;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final file = result.files.single;
    setState(() {
      _fileName = file.name;
      _preview = [];
      _errors = [];
      _validCount = 0;
      _duplicateCount = 0;
    });
    await _parseFile(file.bytes!, file.name.toLowerCase());
  }

  Future<void> _parseFile(Uint8List bytes, String name) async {
    setState(() => _busy = true);
    try {
      final rows = name.endsWith('.csv') ? _parseCsv(bytes) : _parseExcel(bytes);
      final parsed = <_ImportRow>[];
      final errors = <_ImportError>[];
      final seenRefs = <String>{};
      var duplicates = 0;

      for (var i = 0; i < rows.length; i++) {
        final rowNumber = i + 2;
        final map = rows[i];
        final reference = _value(map, ['reference', 'ref', 'رقم المرجع', 'المرجع', 'sku']).trim();
        final nameValue = _value(map, ['name', 'product_name', 'اسم الصنف', 'اسم المنتج']).trim();
        final priceText = _value(map, ['price', 'السعر']).trim();
        final stockText = _value(map, ['stock', 'quantity', 'qty', 'الكمية', 'المخزون']).trim();
        final imageUrl = _value(map, ['imageUrl', 'image_url', 'image', 'الصورة', 'رابط الصورة']).trim();
        final description = _value(map, ['description', 'الوصف']).trim();
        final storeId = _value(map, ['storeId', 'store_id', 'معرف المتجر']).trim().isNotEmpty
            ? _value(map, ['storeId', 'store_id', 'معرف المتجر']).trim()
            : (_selectedStoreId ?? '');
        final sectionId = _value(map, ['sectionId', 'section_id', 'القسم']).trim().isNotEmpty
            ? _value(map, ['sectionId', 'section_id', 'القسم']).trim()
            : (_selectedSectionId ?? appSections.first.id);
        final price = num.tryParse(priceText.replaceAll(',', ''));
        final stock = int.tryParse(stockText.replaceAll(',', ''));

        String? error;
        if (reference.isEmpty) error = 'رقم المرجع مطلوب';
        else if (nameValue.isEmpty) error = 'اسم الصنف مطلوب';
        else if (price == null || price < 0) error = 'السعر غير صالح';
        else if (stock == null || stock < 0) error = 'الكمية غير صالحة';
        else if (storeId.isEmpty) error = 'حدد المتجر أو أضف storeId في الملف';
        else if (seenRefs.contains(reference)) error = 'رقم المرجع مكرر داخل الملف';

        if (error != null) {
          errors.add(_ImportError(rowNumber, error));
          if (error.contains('مكرر')) duplicates++;
          continue;
        }
        seenRefs.add(reference);
        parsed.add(_ImportRow(
          rowNumber: rowNumber,
          reference: reference,
          name: nameValue,
          price: price!.toDouble(),
          stock: stock!,
          imageUrl: imageUrl,
          description: description,
          storeId: storeId,
          sectionId: sectionId,
        ));
      }

      if (!mounted) return;
      setState(() {
        _preview = parsed;
        _errors = errors;
        _validCount = parsed.length;
        _duplicateCount = duplicates;
      });
    } catch (e) {
      if (mounted) setState(() => _errors = [_ImportError(0, 'تعذر قراءة الملف: $e')]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, String>> _parseExcel(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) throw const FormatException('ملف Excel لا يحتوي على ورقة بيانات.');
    final sheet = workbook.tables.values.first;
    if (sheet.rows.isEmpty) return [];
    final headers = sheet.rows.first.map((cell) => _cellText(cell?.value)).map(_normalizeHeader).toList();
    return [
      for (final row in sheet.rows.skip(1))
        {
          for (var i = 0; i < headers.length; i++)
            if (headers[i].isNotEmpty) headers[i]: i < row.length ? _cellText(row[i]?.value) : '',
        }
    ];
  }

  List<Map<String, String>> _parseCsv(Uint8List bytes) {
    final text = String.fromCharCodes(bytes).replaceFirst('\ufeff', '');
    final lines = text.split(RegExp(r'\r?\n')).where((line) => line.trim().isNotEmpty).toList();
    if (lines.isEmpty) return [];
    final headers = _splitCsv(lines.first).map(_normalizeHeader).toList();
    return [
      for (final line in lines.skip(1))
        {
          for (var i = 0; i < headers.length; i++)
            if (headers[i].isNotEmpty) headers[i]: i < _splitCsv(line).length ? _splitCsv(line)[i].trim() : '',
        }
    ];
  }

  List<String> _splitCsv(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    values.add(buffer.toString());
    return values;
  }

  String _normalizeHeader(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  String _value(Map<String, String> row, List<String> keys) {
    for (final key in keys) {
      final normalized = _normalizeHeader(key);
      final value = row[normalized];
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  String _cellText(dynamic value) {
    if (value == null) return '';
    if (value is TextCellValue) return value.value.text ?? '';
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    if (value is BoolCellValue) return value.value.toString();
    return value.toString();
  }

  Future<void> _import() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null || _preview.isEmpty) return;
    setState(() => _busy = true);
    try {
      final db = FirebaseFirestore.instance;
      final references = _preview.map((r) => r.reference).toList();
      final existing = <String>{};
      for (var start = 0; start < references.length; start += 10) {
        final chunk = references.sublist(start, (start + 10).clamp(0, references.length));
        final snap = await db.collection('products').where('reference', whereIn: chunk).get();
        existing.addAll(snap.docs.map((d) => (d.data()['reference'] ?? '').toString()));
      }

      final importable = _preview.where((row) => !existing.contains(row.reference)).toList();
      final skipped = _preview.length - importable.length;

      for (var start = 0; start < importable.length; start += 400) {
        final batch = db.batch();
        final chunk = importable.sublist(start, (start + 400).clamp(0, importable.length));
        for (final row in chunk) {
          final ref = db.collection('products').doc();
          batch.set(ref, {
            'reference': row.reference,
            'storeId': row.storeId,
            'sectionId': row.sectionId,
            'ownerId': user.uid,
            'createdBy': user.uid,
            'name': row.name,
            'description': row.description,
            'imageUrl': row.imageUrl,
            'price': row.price,
            'currency': 'YER',
            'stock': row.stock,
            'soldQuantity': 0,
            'status': 'active',
            'source': 'bulk_import',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      await db.collection('auditLogs').add({
        'actorUid': user.uid,
        'action': 'products.bulk_import',
        'result': 'success',
        'source': 'admin_bulk_import',
        'fileName': _fileName,
        'attempted': _preview.length,
        'imported': importable.length,
        'skippedExistingReferences': skipped,
        'invalidRows': _errors.length,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        _preview = importable;
        _duplicateCount += skipped;
        _validCount = importable.length;
      });
      _message('اكتمل الاستيراد: ${importable.length} صنف جديد، وتم تجاوز $skipped رقم مرجع موجود مسبقاً.');
    } on FirebaseException catch (e) {
      _message('تعذر الاستيراد: ${e.message ?? e.code}');
    } catch (e) {
      _message('تعذر الاستيراد: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadTemplate() async {
    final bytes = Excel.createExcel();
    final sheet = bytes['Sheet1'];
    final headers = ['reference', 'name', 'quantity', 'price', 'imageUrl', 'description', 'storeId', 'sectionId'];
    for (var i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
    }
    final examples = ['PRD-0001', 'اسم الصنف', '10', '15000', 'https://...', 'وصف الصنف', 'STORE_ID', appSections.first.id];
    for (var i = 0; i < examples.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = TextCellValue(examples[i]);
    }
    final data = Uint8List.fromList(bytes.encode()!);
    final path = await FilePicker.platform.saveFile(fileName: 'alfaeq_products_template.xlsx', bytes: data);
    if (path != null && mounted) _message('تم تجهيز نموذج Excel.');
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('استيراد الأصناف بالجملة')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('استيراد حقيقي إلى Firestore', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  const Text('ارفع Excel أو CSV يحتوي على رقم المرجع، اسم الصنف، الكمية، السعر والصورة. ستتم المعاينة والتحقق قبل الحفظ.'),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(onPressed: _busy ? null : _downloadTemplate, icon: const Icon(Icons.download_outlined), label: const Text('تحميل نموذج Excel')),
                    FilledButton.icon(onPressed: _busy ? null : _pickFile, icon: const Icon(Icons.upload_file_outlined), label: const Text('رفع ملف الأصناف')),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSectionId ?? appSections.first.id,
                    decoration: const InputDecoration(labelText: 'القسم الافتراضي للصفوف التي لا تحتوي sectionId'),
                    items: [for (final s in appSections) DropdownMenuItem(value: s.id, child: Text(s.title))],
                    onChanged: _busy ? null : (v) => setState(() => _selectedSectionId = v),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance.collection('stores').where('status', whereIn: ['approved', 'active']).limit(200).snapshots(),
                    builder: (context, snapshot) {
                      final docs = snapshot.data?.docs ?? [];
                      return DropdownButtonFormField<String>(
                        initialValue: _selectedStoreId,
                        decoration: const InputDecoration(labelText: 'المتجر الافتراضي إذا لم يوجد storeId في الملف'),
                        items: [
                          const DropdownMenuItem<String>(value: null, child: Text('استخدم storeId الموجود في الملف')),
                          ...docs.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name'] ?? d.id}'))),
                        ],
                        onChanged: _busy ? null : (v) => setState(() => _selectedStoreId = v),
                      );
                    },
                  ),
                ]),
              ),
            ),
            if (_fileName != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('الملف: $_fileName', style: const TextStyle(fontWeight: FontWeight.w800))),
            if (_busy) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
            if (_fileName != null && !_busy) Card(child: ListTile(leading: const Icon(Icons.fact_check_outlined), title: const Text('جاهز للمراجعة'), subtitle: Text('صالح: $_validCount • أخطاء: ${_errors.length} • مراجع مكررة: $_duplicateCount'))),
            if (_errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('الأخطاء التي لن تدخل قاعدة البيانات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ..._errors.take(30).map((e) => ListTile(dense: true, leading: const Icon(Icons.error_outline), title: Text('الصف ${e.row}'), subtitle: Text(e.message))),
            ],
            if (_preview.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('معاينة قبل الحفظ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              ..._preview.take(50).map((row) => Card(child: ListTile(
                leading: row.imageUrl.isEmpty ? const Icon(Icons.inventory_2_outlined) : Image.network(row.imageUrl, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined)),
                title: Text('${row.name} • ${row.reference}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('الكمية: ${row.stock} • السعر: ${row.price} YER\nالمتجر: ${row.storeId}'),
                isThreeLine: true,
              ))),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _import, icon: const Icon(Icons.cloud_upload_outlined), label: Text('اعتماد واستيراد $_validCount صنف إلى Firestore'))),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportRow {
  final int rowNumber;
  final String reference;
  final String name;
  final double price;
  final int stock;
  final String imageUrl;
  final String description;
  final String storeId;
  final String sectionId;
  const _ImportRow({required this.rowNumber, required this.reference, required this.name, required this.price, required this.stock, required this.imageUrl, required this.description, required this.storeId, required this.sectionId});
}

class _ImportError {
  final int row;
  final String message;
  const _ImportError(this.row, this.message);
}
