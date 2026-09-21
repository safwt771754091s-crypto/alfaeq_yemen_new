import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show rootBundle;

class SuperAlfaeqCatalogImporter {
  static const _files = <String>[
    'assets/data/super_alfaeq/catalog_01.json',
    'assets/data/super_alfaeq/catalog_02.json',
    'assets/data/super_alfaeq/catalog_03.json',
    'assets/data/super_alfaeq/catalog_04.json',
    'assets/data/super_alfaeq/catalog_05.json',
    'assets/data/super_alfaeq/catalog_06.json',
    'assets/data/super_alfaeq/catalog_07.json',
    'assets/data/super_alfaeq/catalog_08.json',
  ];

  final FirebaseFirestore db;
  final FirebaseAuth auth;

  SuperAlfaeqCatalogImporter({FirebaseFirestore? firestore, FirebaseAuth? firebaseAuth})
      : db = firestore ?? FirebaseFirestore.instance,
        auth = firebaseAuth ?? FirebaseAuth.instance;

  String _unit(String raw) {
    final u = raw.trim().toLowerCase();
    if (['كجم','كيلو','كيلوجرام','kg'].contains(u)) return 'kg';
    if (['جرام','غرام','g','جم'].contains(u)) return 'g';
    if (['لتر','ل','liter','l'].contains(u)) return 'l';
    if (['مل','ملي','ml'].contains(u)) return 'ml';
    if (['متر','m'].contains(u)) return 'm';
    return 'piece';
  }

  int _scale(String unit) => const {'piece': 1, 'kg': 1000, 'g': 1, 'l': 1000, 'ml': 1, 'm': 1}[unit] ?? 1;

  String? _image(String? barcode) {
    final digits = (barcode ?? '').replaceAll(RegExp(r'\\D'), '');
    if (digits.length < 8) return null;
    return 'https://images.openfoodfacts.org/images/products/${digits.substring(0, 3)}/${digits.substring(3, 6)}/${digits.substring(6, 9)}/${digits.substring(9)}/front_en.400.jpg';
  }

  Future<bool> _claimAdmin() async {
    final user = auth.currentUser;
    if (user == null) return false;
    final token = await user.getIdTokenResult(true);
    final c = token.claims ?? const <String, dynamic>{};
    return c['admin'] == true || c['owner'] == true || c['role'] == 'admin' || c['role'] == 'owner';
  }

  Future<bool> isReady() async {
    final snap = await db.collection('settings').doc('super_alfaeq_catalog').get();
    return snap.data()?['status'] == 'ready';
  }

  Future<int> importIfNeeded({void Function(int done, int total)? onProgress}) async {
    if (!await _claimAdmin()) return 0;
    if (await isReady()) return 0;

    final user = auth.currentUser!;
    final marker = db.collection('settings').doc('super_alfaeq_catalog');
    final markerSnap = await marker.get();
    if (markerSnap.data()?['status'] == 'importing') return 0;

    await marker.set({
      'status': 'importing',
      'source': 'الفائق_يمن_منتجات_سوبر_الفائق_جاهز_للمراجعة.xlsx',
      'startedBy': user.uid,
      'startedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final storeRef = db.collection('stores').doc('super-alfaeq');
    await storeRef.set({
      'name': 'سوبر الفائق',
      'sectionId': 'markets',
      'ownerId': user.uid,
      'status': 'approved',
      'enabled': true,
      'address': 'سوبر الفائق — متجر المنصة',
      'catalogSource': 'excel_2026_09_19',
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    var total = 0;
    var done = 0;
    for (final file in _files) {
      final raw = await rootBundle.loadString(file);
      final rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      total += rows.length;
    }

    var rowIndex = 0;
    var active = 0;
    for (final file in _files) {
      final raw = await rootBundle.loadString(file);
      final rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      for (var offset = 0; offset < rows.length; offset += 400) {
        final batch = db.batch();
        final end = (offset + 400 < rows.length) ? offset + 400 : rows.length;
        for (var i = offset; i < end; i++) {
          final row = rows[i];
          rowIndex++;
          final id = 'super_${(row['id'] ?? '').toString().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}_$rowIndex';
          final unit = _unit((row['unit'] ?? 'حبة').toString());
          final scale = _scale(unit);
          final price = (row['price'] as num?)?.toDouble() ?? 0;
          final stock = (row['stock'] as num?)?.toDouble() ?? 0;
          active++;
          final ref = db.collection('products').doc(id);
          batch.set(ref, {
            'name': (row['name'] ?? 'منتج').toString(),
            'barcode': row['barcode'],
            'internalRef': row['internalRef'],
            'category': (row['category'] ?? 'عام').toString(),
            'price': price < 0 ? 0 : price,
            'cost': (row['cost'] as num?)?.toDouble() ?? 0,
            'currency': 'YER',
            'stock': stock < 0 ? 0 : stock,
            'stockBase': ((stock < 0 ? 0 : stock) * scale).round(),
            'expectedStock': (row['expectedStock'] as num?)?.toDouble() ?? 0,
            'saleUnit': unit,
            'unitScale': scale,
            'baseUnit': ['kg','g'].contains(unit) ? 'g' : (['l','ml'].contains(unit) ? 'ml' : unit),
            'unitLabel': const {'piece':'قطعة','kg':'كجم','g':'جرام','l':'لتر','ml':'مل','m':'متر'}[unit] ?? 'قطعة',
            'stepBase': (unit == 'kg' || unit == 'l') ? 250 : 1,
            'minOrderBase': (unit == 'kg' || unit == 'l') ? 250 : 1,
            'storeId': 'super-alfaeq',
            'sectionId': 'markets',
            'ownerId': user.uid,
            'merchantName': 'سوبر الفائق',
            'status': 'active',
            'imageUrl': _image(row['barcode']?.toString()),
            'source': 'excel_import',
            'sourceFile': 'الفائق_يمن_منتجات_سوبر_الفائق_جاهز_للمراجعة.xlsx',
            'updatedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        await batch.commit();
        done += end - offset;
        onProgress?.call(done, total);
      }
    }

    await marker.set({
      'status': 'ready',
      'imported': done,
      'active': active,
      'storeId': 'super-alfaeq',
      'completedBy': user.uid,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return done;
  }
}
