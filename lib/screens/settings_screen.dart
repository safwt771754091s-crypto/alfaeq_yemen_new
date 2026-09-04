import 'package:flutter/material.dart';
import '../config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('اللغة', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('العربية هي اللغة الافتراضية للتطبيق.'),
            const SizedBox(height: 18),
            const Text('إعدادات التوصيل', style: TextStyle(fontWeight: FontWeight.bold)),
            ValueListenableBuilder<bool>(
              valueListenable: AppConfig.freeDelivery,
              builder: (_, free, __) => SwitchListTile(
                title: const Text('التوصيل المجاني'),
                value: free,
                onChanged: (value) async {
                  await AppConfig.setFreeDelivery(value);
                  if (mounted) setState(() {});
                },
              ),
            ),
            const SizedBox(height: 18),
            const Text('العملة', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
              valueListenable: AppConfig.currency,
              builder: (_, currency, __) => DropdownButton<String>(
                value: currency,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'SAR', child: Text('ريال سعودي')),
                  DropdownMenuItem(value: 'USD', child: Text('دولار أمريكي')),
                  DropdownMenuItem(value: 'YER', child: Text('ريال يمني')),
                ],
                onChanged: (value) async {
                  if (value != null) {
                    await AppConfig.setCurrency(value);
                    if (mounted) setState(() {});
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
