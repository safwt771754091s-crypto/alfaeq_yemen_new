import 'package:flutter/material.dart';

void main() {
  runApp(const AlfaeqYemenApp());
}

class AlfaeqYemenApp extends StatelessWidget {
  const AlfaeqYemenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'الفائق يمن',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const CartScreen(),
    );
  }
}

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  String selectedWallet = 'cash';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A365D),
        title: const Text('الفائق يمن - المحافظ اليمنية', style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('اختر المحفظة أو البنك للدفع:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: selectedWallet,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('محفظة كاش')),
                DropdownMenuItem(value: 'flous', child: Text('محفظة فلوس')),
                DropdownMenuItem(value: 'paisa', child: Text('محفظة بيس')),
                DropdownMenuItem(value: 'shilin', child: Text('محفظة شلن')),
                DropdownMenuItem(value: 'kuraimi', child: Text('محفظة الكريمي بلس')),
                DropdownMenuItem(value: 'jaib', child: Text('محفظة جيب')),
                DropdownMenuItem(value: 'jawali', child: Text('محفظة جوالي / سبأفون')),
                DropdownMenuItem(value: 'cod', child: Text('الدفع النقدي عند الاستلام')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => selectedWallet = val);
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A365D), minimumSize: const Size(double.infinity, 45)),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم اعتماد طريقة الدفع بنجاح!')),
                );
              },
              child: const Text('تأكيد العملية', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
