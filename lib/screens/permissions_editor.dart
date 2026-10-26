import 'package:flutter/material.dart';

import '../core/permission_catalog.dart';
import '../services/supabase_service.dart';

/// Shows the full permission matrix for [uid] and persists changes.
///
/// Only the master owner can open this (RLS + `master_permission_set` enforce
/// it server-side). Returns true when at least one change was saved.
Future<bool> showPermissionsEditor(
  BuildContext context, {
  required String uid,
  String? title,
  bool allowEdit = true,
}) async {
  final client = SupabaseService.client;
  Map<String, bool> current;
  try {
    final rows = await client
        .from('master_permissions')
        .select('permission,granted')
        .eq('uid', uid);
    current = {
      for (final row in rows)
        (row['permission'] ?? '').toString(): row['granted'] == true,
    };
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحميل الصلاحيات: $e')),
      );
    }
    return false;
  }
  if (!context.mounted) return false;

  final selected = Map<String, bool>.from(current);
  // Default to granted so the owner can see the whole catalog at a glance.
  for (final p in PermissionCatalog.all) {
    selected.putIfAbsent(p.id, () => true);
  }

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title ?? 'صلاحيات الحساب'),
          content: SizedBox(
            width: 560,
            height: 520,
            child: ListView(
              children: [
                for (final entry in PermissionCatalog.byCategory.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Text(
                      PermissionCatalog.categoryLabels[entry.key] ?? entry.key,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  for (final permission in entry.value)
                    CheckboxListTile(
                      dense: true,
                      value: selected[permission.id] ?? true,
                      title: Text(permission.label),
                      subtitle: Text(permission.id, style: const TextStyle(fontSize: 11)),
                      onChanged: allowEdit
                          ? (value) => setDialogState(() => selected[permission.id] = value == true)
                          : null,
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إغلاق')),
            if (allowEdit)
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.save_outlined),
                label: const Text('حفظ الصلاحيات'),
              ),
          ],
        ),
      ),
    ),
  );

  if (saved != true) return false;

  final changed = <String, bool>{
    for (final entry in selected.entries)
      if (current[entry.key] != entry.value) entry.key: entry.value,
  };
  if (changed.isEmpty) return false;

  try {
    for (final entry in changed.entries) {
      await client.rpc('master_permission_set', params: {
        'p_uid': uid,
        'p_permission': entry.key,
        'p_granted': entry.value,
      });
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الصلاحيات على الخادم.')),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ الصلاحيات: $e')),
      );
    }
    return false;
  }
}
