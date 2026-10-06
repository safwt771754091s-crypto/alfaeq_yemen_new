import 'package:flutter/material.dart';

/// Wraps the customer experience. The account center already exposes logout
/// and account controls, so this shell only renders the child directly.
class CustomerSessionShell extends StatelessWidget {
  final Widget child;

  const CustomerSessionShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
