import 'package:alfaeq_yemen/services/mini_programs_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MiniProgramsService.slugify', () {
    test('lowercases and dashes latin names', () {
      expect(MiniProgramsService.slugify('Super Alfaeq Store'), 'super-alfaeq-store');
    });

    test('preserves Arabic letters', () {
      expect(MiniProgramsService.slugify('المتاجر والبقالات'), 'المتاجر-والبقالات');
    });

    test('collapses punctuation and trims dashes', () {
      expect(MiniProgramsService.slugify('  "Reels" -- الفائق!! '), 'reels-الفائق');
    });

    test('falls back to a stable slug when nothing usable remains', () {
      expect(MiniProgramsService.slugify('  @@@  '), 'program');
    });
  });

  group('MiniProgram.fromRow', () {
    test('reads every field and coerces types', () {
      final program = MiniProgram.fromRow({
        'id': 'mp-reels',
        'slug': 'reels',
        'name': 'فيديو الفائق',
        'description': 'مقاطع قصيرة',
        'icon': 'play',
        'route': 'screen:reels',
        'category': 'ترفيه',
        'publisher_name': 'الفائق يمن',
        'verified': true,
        'featured': true,
        'usage_count': 12,
        'sort_order': 5,
      });
      expect(program.id, 'mp-reels');
      expect(program.route, 'screen:reels');
      expect(program.verified, isTrue);
      expect(program.featured, isTrue);
      expect(program.usageCount, 12);
      expect(program.sortOrder, 5);
    });

    test('applies safe defaults for missing columns', () {
      final program = MiniProgram.fromRow({'id': 'x', 'name': 'برنامج'});
      expect(program.icon, 'explore');
      expect(program.category, 'عام');
      expect(program.verified, isFalse);
      expect(program.usageCount, 0);
      expect(program.sortOrder, 100);
    });
  });
}
