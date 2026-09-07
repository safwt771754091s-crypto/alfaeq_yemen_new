class AppSection {
  final String id;
  final String title;
  final String subtitle;
  final String icon;
  const AppSection(this.id, this.title, this.subtitle, this.icon);
}

const appSections = <AppSection>[
  AppSection('markets', 'المتاجر والأسواق', 'شراء من المتاجر المحلية', 'storefront'),
  AppSection('restaurants', 'المطاعم والبقالات', 'طلبات الطعام والمواد اليومية', 'restaurant'),
  AppSection('pharmacies', 'الصيدليات', 'منتجات وخدمات الصيدليات', 'pharmacy'),
  AppSection('beauty', 'التجميل والعناية', 'العناية والجمال', 'beauty'),
  AppSection('construction', 'مواد البناء والنقل الثقيل', 'مواد ومركبات النقل', 'construction'),
  AppSection('cars', 'السيارات وقطع الغيار', 'بيع وتأجير وصيانة', 'car'),
  AppSection('travel', 'السفر والطيران', 'حجوزات السفر والرحلات', 'flight'),
  AppSection('hotels', 'الفنادق والإقامة', 'حجوزات الفنادق والشقق', 'hotel'),
  AppSection('banks', 'البنوك والمحافظ', 'خدمات مالية ومحافظ إلكترونية', 'account_balance'),
  AppSection('services', 'الخدمات والحرف', 'مهنيون وخدمات منزلية', 'handyman'),
  AppSection('electronics', 'الإلكترونيات والكهربائيات', 'أجهزة وملحقات', 'devices'),
  AppSection('real_estate', 'العقارات', 'بيع وإيجار العقارات', 'home'),
  AppSection('jobs', 'الوظائف', 'فرص العمل والتوظيف', 'work'),
  AppSection('education', 'التعليم والتدريب', 'دورات ومدربون ومراكز', 'school'),
  AppSection('health', 'الصحة والعيادات', 'عيادات ومواعيد وخدمات صحية', 'medical'),
  AppSection('local_tourism', 'السياحة والرحلات المحلية', 'رحلات وتجارب داخل اليمن', 'explore'),
];
