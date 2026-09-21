import 'package:cloud_functions/cloud_functions.dart';

/// Starts the authoritative server-side Super Alfaeq catalog import.
/// The catalog itself lives with Cloud Functions so the APK does not depend
/// on duplicating a large product dataset into Flutter assets.
class SuperAlfaeqCatalogImporter {
  final FirebaseFunctions functions;

  SuperAlfaeqCatalogImporter({FirebaseFunctions? firebaseFunctions})
      : functions = firebaseFunctions ??
            FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<bool> isReady() async {
    try {
      final result = await functions
          .httpsCallable('ensureSuperAlfaeqCatalog')
          .call(<String, dynamic>{'checkOnly': true});
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['ok'] == true && data['ready'] == true;
    } on FirebaseFunctionsException {
      return false;
    }
  }

  Future<int> importIfNeeded({
    void Function(int done, int total)? onProgress,
  }) async {
    // The callable performs authentication, owner/admin authorization,
    // idempotency, batching and server-side writes.
    final result = await functions
        .httpsCallable('ensureSuperAlfaeqCatalog')
        .call(<String, dynamic>{});
    final data = Map<String, dynamic>.from(result.data as Map);
    if (data['ok'] != true) return 0;
    final imported = (data['imported'] as num?)?.toInt() ?? 0;
    final active = (data['active'] as num?)?.toInt() ?? imported;
    onProgress?.call(active, imported);
    return imported;
  }
}
