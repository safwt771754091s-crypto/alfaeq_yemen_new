import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Keeps the existing customer experience intact while providing a clear,
/// always-available account/logout control.
class CustomerSessionShell extends StatelessWidget {
  final Widget child;

  const CustomerSessionShell({super.key, required this.child});

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد تسجيل الخروج من حسابك؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AuthService().signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 12,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _logout(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.logout_outlined, size: 20),
                    SizedBox(width: 6),
                    Text('خروج', style: TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
