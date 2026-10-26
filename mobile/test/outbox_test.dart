import 'package:flutter_test/flutter_test.dart';
import 'package:job_manager/data/local_db.dart';

void main() {
  group('OutboxItem', () {
    final createdAt = DateTime(2026, 10, 26, 12, 30);

    test('row round-trip keeps the idempotency key and body', () {
      final item = OutboxItem(
        id: 'op-1',
        kind: 'visit',
        method: 'POST',
        path: '/sites/site-1/visits',
        body: const {'completedWork': 'تركيب لوحة', 'source': 'VOICE'},
        siteId: 'site-1',
        createdAt: createdAt,
        attempts: 2,
        lastError: 'timeout',
        state: OutboxState.failed,
      );

      final restored = OutboxItem.fromRow(item.toRow());

      expect(restored.id, 'op-1');
      expect(restored.kind, 'visit');
      expect(restored.body['completedWork'], 'تركيب لوحة');
      expect(restored.siteId, 'site-1');
      expect(restored.createdAt, createdAt);
      expect(restored.attempts, 2);
      expect(restored.lastError, 'timeout');
      expect(restored.state, OutboxState.failed);
    });

    test('unknown state names degrade to pending instead of throwing', () {
      final restored = OutboxItem.fromRow({
        'id': 'op-2',
        'kind': 'task',
        'method': 'POST',
        'path': '/tasks',
        'body': '{}',
        'created_at': createdAt.millisecondsSinceEpoch,
        'state': 'something-new',
      });

      expect(restored.state, OutboxState.pending);
      expect(restored.body, isEmpty);
    });

    test('Arabic labels describe every queued kind', () {
      OutboxItem item(String kind) => OutboxItem(
        id: kind,
        kind: kind,
        method: 'POST',
        path: '/',
        body: const {},
        createdAt: createdAt,
      );

      expect(item('site').labelAr, 'موقع جديد');
      expect(item('visit').labelAr, 'زيارة جديدة');
      expect(item('task').labelAr, 'مهمة جديدة');
      expect(item('taskUpdate').labelAr, 'تعديل مهمة');
      expect(item('siteUpdate').labelAr, 'تعديل موقع');
      expect(item('other').labelAr, 'تغيير');
    });

    test('creates are identified by kind', () {
      OutboxItem item(String kind) => OutboxItem(
        id: kind,
        kind: kind,
        method: 'POST',
        path: '/',
        body: const {},
        createdAt: createdAt,
      );

      expect(item('site').isCreate, isTrue);
      expect(item('visit').isCreate, isTrue);
      expect(item('task').isCreate, isTrue);
      expect(item('taskUpdate').isCreate, isFalse);
      expect(item('siteUpdate').isCreate, isFalse);
    });
  });
}
