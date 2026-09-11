import 'package:flutter/material.dart';

import 'real_wallet_page.dart';
import 'super_app_sections_page.dart';
import 'world_home_page.dart';

class SuperAppShellPage extends StatefulWidget {
  const SuperAppShellPage({super.key});

  @override
  State<SuperAppShellPage> createState() => _SuperAppShellPageState();
}

class _SuperAppShellPageState extends State<SuperAppShellPage> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: const [
            WorldHomePage(),
            SuperAppSectionsPage(),
            RealWalletPage(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.apps_outlined), selectedIcon: Icon(Icons.apps), label: 'الأقسام'),
            NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'المحفظة'),
          ],
        ),
      ),
    );
  }
}
