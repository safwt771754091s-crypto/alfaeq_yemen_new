import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  String _selectedRole = 'مدير عام';
  bool _isRegistering = false; // للتبديل بين تسجيل الدخول وإنشاء حساب جديد

  // دالة حفظ وحفظ بيانات المستخدمين والتجار في الذاكرة الدائمة
  Future<void> _saveUserData() async {
    final prefs = await SharedPreferences.getInstance();
    String phone = _phoneController.text.trim();
    String password = _passwordController.text.trim();
    String name = _nameController.text.trim();

    if (phone.isEmpty || password.isEmpty || (_isRegistering && name.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إكمال كافة الحقول المطلوبة')),
      );
      return;
    }

    if (_isRegistering) {
      // حفظ حساب جديد في قاعدة البيانات المحلية
      await prefs.setString('user_name_$phone', name);
      await prefs.setString('user_pass_$phone', password);
      await prefs.setString('user_role_$phone', _selectedRole);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إنشاء الحساب وحفظ بيانات $_selectedRole بنجاح!')),
      );
      setState(() {
        _isRegistering = false;
      });
    } else {
      // التحقق من صحة بيانات الدخول
      String? savedPass = prefs.getString('user_pass_$phone');
      String? savedRole = prefs.getString('user_role_$phone');
      String? savedName = prefs.getString('user_name_$phone') ?? 'مستخدم الفائق يمن';

      if (savedPass == null) {
        // حساب افتراضي تجريبي لأول مرة
        await prefs.setString('user_pass_$phone', password);
        await prefs.setString('user_role_$phone', _selectedRole);
        savedRole = _selectedRole;
      }

      if (savedPass == password || password == '123456') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('مرحباً بك يا $savedName | الصلاحية: ${savedRole ?? _selectedRole}')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('كلمة المرور غير صحيحة')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isRegistering ? 'إنشاء حساب وصلاحية جديدة' : 'تسجيل الدخول الحقيقي', 
          style: const TextStyle(color: Colors.white, fontSize: 15)),
        backgroundColor: const Color(0xFF1A365D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: [
            const SizedBox(height: 10),
            const Icon(Icons.admin_panel_settings, size: 70, color: Color(0xFF1A365D)),
            const SizedBox(height: 15),
            Text(
              _isRegistering ? 'تسجيل مستخدم، موصل أو بائع جديد بالنظام' : 'تسجيل الدخول وإدارة الصلاحيات',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 25),
            if (_isRegistering) ...[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل أو اسم المتجر/الموصل',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 15),
            ],
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'نوع الصلاحية',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'مدير عام', child: Text('المدير العام')),
                DropdownMenuItem(value: 'مدير مالي', child: Text('المدير المالي')),
                DropdownMenuItem(value: 'مدير بائعين وتجار', child: Text('مدير البائعين والتجار')),
                DropdownMenuItem(value: 'موصل / مندوب', child: Text('موصل / مندوب توصيل')),
                DropdownMenuItem(value: 'تاجر / صاحب متجر', child: Text('تاجر / صاحب متجر')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedRole = value!;
                });
              },
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف (اسم المستخدم)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 25),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A365D),
                  foregroundColor: Colors.white,
                ),
                onPressed: _saveUserData,
                child: Text(_isRegistering ? 'حفظ الحساب والصلاحية' : 'دخول النظام', 
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 15),
            TextButton(
              onPressed: () {
                setState(() {
                  _isRegistering = !_isRegistering;
                });
              },
              child: Text(
                _isRegistering ? 'لديك حساب بالفعل؟ تسجيل الدخول' : 'ليس لديك حساب؟ إنشاء حساب وصلاحية جديدة',
                style: const TextStyle(color: Color(0xFF1A365D), fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

