import 'package:flutter_test/flutter_test.dart';

import 'package:alfaeq_yemen/core/query_cache.dart';

/// The storefront depends on this cache to keep a single round trip per read.
/// Each query costs roughly half a second against the live project, so a
/// regression here is immediately visible to users as a slow page.
void main() {
  setUp(() => QueryCache.instance.invalidate());

  group('QueryCache', () {
    test('shares one in-flight future between concurrent callers', () async {
      var loads = 0;
      Future<int> load() async {
        loads++;
        return 42;
      }

      final results = await Future.wait([
        QueryCache.instance.remember('k', load),
        QueryCache.instance.remember('k', load),
        QueryCache.instance.remember('k', load),
      ]);

      expect(results, [42, 42, 42]);
      expect(loads, 1, reason: 'a rebuild must not queue a second round trip');
    });

    test('serves the cached value until the TTL expires', () async {
      var loads = 0;
      Future<String> load() async => 'v${++loads}';

      expect(await QueryCache.instance.remember('k', load), 'v1');
      expect(await QueryCache.instance.remember('k', load), 'v1');
      expect(loads, 1);
    });

    test('reloads once the TTL has passed', () async {
      var loads = 0;
      Future<String> load() async => 'v${++loads}';

      await QueryCache.instance.remember('k', load, ttl: Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(await QueryCache.instance.remember('k', load, ttl: Duration.zero), 'v2');
      expect(loads, 2);
    });

    test('does not cache a failed read', () async {
      var loads = 0;
      Future<int> failing() async {
        loads++;
        throw StateError('offline');
      }

      await expectLater(QueryCache.instance.remember('k', failing), throwsStateError);
      await expectLater(QueryCache.instance.remember('k', failing), throwsStateError);
      expect(loads, 2, reason: 'a transient error must not poison the TTL window');
    });

    test('keeps different keys apart and invalidates by prefix', () async {
      var loads = 0;
      Future<String> load(String key) async => '$key-${++loads}';

      expect(await QueryCache.instance.remember('catalog.a', () => load('a')), 'a-1');
      expect(await QueryCache.instance.remember('catalog.b', () => load('b')), 'b-2');

      QueryCache.instance.invalidate('catalog.');
      expect(await QueryCache.instance.remember('catalog.a', () => load('a')), 'a-3');
      expect(loads, 3);
    });
  });
}
