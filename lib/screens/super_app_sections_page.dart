import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/app_sections.dart';
import 'cart_page.dart';

class SuperAppSectionsPage extends StatefulWidget {
  const SuperAppSectionsPage({super.key});

  @override
  State<SuperAppSectionsPage> createState() => _SuperAppSectionsPageState();
}

class _SuperAppSectionsPageState extends State<SuperAppSectionsPage> {
  String query = '';
  String selected = 'all';

  @override
  Widget build(BuildContext context) {
    final filtered = appSections.where((section) {
      final matchesQuery = query.trim().isEmpty ||
          section.title.contains(query.trim()) ||
          section.subtitle.contains(query.trim());
      final matchesCategory = selected == 'all' || section.id == selected;
      return matchesQuery && matchesCategory;
    }).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('اكتشف خدمات الفائق', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(
              tooltip: 'السلة',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())),
              icon: const Icon(Icons.shopping_bag_outlined),
            ),
          ],
        ),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _hero()),
            SliverToBoxAdapter(child: _search()),
            SliverToBoxAdapter(child: _quickCategories()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, index) => _SectionTile(section: filtered[index]),
                  childCount: filtered.length,
                ),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 235,
                  mainAxisExtent: 168,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero() => Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF0B6E4F), Color(0xFF124E78)],
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.apps_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('Super App', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ]),
            SizedBox(height: 12),
            Text('كل خدماتك في مكان واحد', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900)),
            SizedBox(height: 7),
            Text('متاجر، طعام، صحة، سفر، عقارات، وظائف، تعليم، خدمات مالية والمزيد.', style: TextStyle(color: Colors.white70, height: 1.45)),
          ],
        ),
      );

  Widget _search() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: InputDecoration(
            hintText: 'ابحث عن خدمة أو قسم...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(onPressed: () => setState(() => query = ''), icon: const Icon(Icons.clear)),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          ),
        ),
      );

  Widget _quickCategories() => SizedBox(
        height: 62,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          scrollDirection: Axis.horizontal,
          children: [
            _filter('all', 'الكل', Icons.apps_rounded),
            _filter('markets', 'تجارة', Icons.storefront_outlined),
            _filter('restaurants', 'طعام', Icons.restaurant_outlined),
            _filter('travel', 'سفر', Icons.flight_takeoff_outlined),
            _filter('health', 'صحة', Icons.medical_services_outlined),
            _filter('services', 'خدمات', Icons.handyman_outlined),
            _filter('jobs', 'وظائف', Icons.work_outline),
          ],
        ),
      );

  Widget _filter(String id, String title, IconData icon) {
    final active = selected == id;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        selected: active,
        avatar: Icon(icon, size: 18),
        label: Text(title),
        onSelected: (_) => setState(() => selected = id),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final AppSection section;
  const _SectionTile({required this.section});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => _SectionExperiencePage(section: section)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F3EE),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(_icon(section.icon), color: const Color(0xFF0B6E4F), size: 28),
                ),
                const Spacer(),
                const Icon(Icons.arrow_back_ios_new, size: 14, color: Colors.black38),
              ]),
              const Spacer(),
              Text(section.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              Text(section.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, fontSize: 11, height: 1.3)),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _icon(String name) => switch (name) {
        'storefront' => Icons.storefront_outlined,
        'restaurant' => Icons.restaurant_outlined,
        'pharmacy' => Icons.local_pharmacy_outlined,
        'beauty' => Icons.face_retouching_natural,
        'construction' => Icons.construction_outlined,
        'car' => Icons.directions_car_outlined,
        'flight' => Icons.flight_takeoff_outlined,
        'hotel' => Icons.hotel_outlined,
        'account_balance' => Icons.account_balance_wallet_outlined,
        'handyman' => Icons.handyman_outlined,
        'devices' => Icons.devices_outlined,
        'home' => Icons.home_work_outlined,
        'work' => Icons.work_outline,
        'school' => Icons.school_outlined,
        'medical' => Icons.medical_services_outlined,
        _ => Icons.explore_outlined,
      };
}

class _SectionExperiencePage extends StatelessWidget {
  final AppSection section;
  const _SectionExperiencePage({required this.section});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w900))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFE7F3EE), Color(0xFFEAF2F8)]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: Icon(_SectionTile._icon(section.icon), color: const Color(0xFF0B6E4F), size: 31),
                ),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(section.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(section.subtitle, style: const TextStyle(color: Colors.black54, height: 1.4)),
                ])),
              ]),
            ),
            const SizedBox(height: 14),
            _LiveStoreList(section: section),
          ],
        ),
      ),
    );
  }
}

class _LiveStoreList extends StatelessWidget {
  final AppSection section;
  const _LiveStoreList({required this.section});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('stores')
          .where('sectionId', isEqualTo: section.id)
          .where('status', isEqualTo: 'approved')
          .limit(30)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _EmptyCard(title: 'تعذر تحميل المحتوى', text: 'تحقق من الاتصال والصلاحيات ثم حاول مرة أخرى.');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
        }
        final stores = snapshot.data?.docs ?? const [];
        if (stores.isEmpty) {
          return const _EmptyCard(title: 'القسم جاهز لاستقبال المتاجر', text: 'سيظهر المحتوى الحقيقي هنا فور اعتماد المتاجر.');
        }
        return Column(children: stores.map((store) => Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFE7F3EE), child: Icon(Icons.storefront_outlined, color: Color(0xFF0B6E4F))),
            title: Text('${store.data()['name'] ?? 'متجر'}', style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('${store.data()['address'] ?? 'عنوان غير محدد'}'),
            trailing: const Icon(Icons.chevron_left),
          ),
        )).toList());
      },
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String title;
  final String text;
  const _EmptyCard({required this.title, required this.text});

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const Icon(Icons.explore_outlined, size: 38, color: Color(0xFF0B6E4F)),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 5),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, height: 1.4)),
          ]),
        ),
      );
}
