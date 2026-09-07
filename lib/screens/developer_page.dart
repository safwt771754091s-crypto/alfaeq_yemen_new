import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class DeveloperPage extends StatefulWidget {
  const DeveloperPage({super.key});

  @override
  State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage> {
  final _auth = AuthService();
  bool _allowed = false;
  bool _loading = true;
  String _role = '';
  Map<String, dynamic> _profile = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = snap.data() ?? {};
    final role = (data['role'] as String?) ?? 'customer';
    final claimAdmin = await _auth.hasAdminClaim();
    if (mounted) {
      setState(() {
        _role = role;
        _profile = data;
        _allowed = claimAdmin || role == 'developer';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_allowed) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('صفحة المطور')),
          body: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('ليس لديك صلاحية الوصول إلى صفحة المطور.', textAlign: TextAlign.center))),
        ),
      );
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('مركز المطور'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.code)), title: const Text('صفحة المطور', style: TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('الصلاحية: $_role'))),
            const SizedBox(height: 12),
            const _DevCard(icon: Icons.security, title: 'الأمان والصلاحيات', subtitle: 'المستخدم العادي لا يحصل على صلاحيات الإدارة. الإدارة الفعلية تعتمد على Firebase Auth custom claim: admin=true.'),
            _DevCard(icon: Icons.person, title: 'المستخدم الحالي', subtitle: 'UID: ${FirebaseAuth.instance.currentUser?.uid ?? '-'}\nالبريد: ${FirebaseAuth.instance.currentUser?.email ?? '-'}'),
            _DevCard(icon: Icons.storage, title: 'ملف المستخدم', subtitle: 'role: ${_profile['role'] ?? '-'}\nname: ${_profile['name'] ?? '-'}'),
            const _DevCard(icon: Icons.cloud_done, title: 'Firebase', subtitle: 'المصادقة وFirestore متصلان بالتطبيق.'),
          ],
        ),
      ),
    );
  }
}

class _DevCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _DevCard({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Card(child: ListTile(leading: Icon(icon), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(subtitle)));
}
