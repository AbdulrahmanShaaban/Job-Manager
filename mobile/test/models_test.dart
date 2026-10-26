import 'package:flutter_test/flutter_test.dart';
import 'package:job_manager/models/site.dart';
import 'package:job_manager/models/task.dart';
import 'package:job_manager/models/visit.dart';
import 'package:job_manager/models/voice.dart';

void main() {
  group('Site', () {
    final companyJson = <String, dynamic>{
      'id': 'site-1',
      'name': 'فيلا المعادي',
      'scope': 'COMPANY',
      'status': 'ACTIVE',
      'address': 'المعادي، القاهرة',
      'workspace': {'id': 'ws-1', 'name': 'شركة النصر'},
      'openTaskCount': 3,
      'lastVisit': {
        'id': 'visit-1',
        'siteId': 'site-1',
        'visitDate': '2026-10-25',
        'completedWork': 'تركيب لوحة التوزيع',
      },
    };

    test('parses company scope, workspace and nested last visit', () {
      final site = Site.fromJson(companyJson);

      expect(site.scope, SiteScope.company);
      expect(site.status, SiteStatus.active);
      expect(site.workspaceName, 'شركة النصر');
      expect(site.openTaskCount, 3);
      expect(site.lastVisit?.visitDate, '2026-10-25');
      expect(site.pending, isFalse);
    });

    test('map link prefers an explicit URL', () {
      final site = Site.fromJson({...companyJson, 'mapUrl': 'https://maps.example/place'});
      expect(site.mapLink, 'https://maps.example/place');
    });

    test('map link falls back to coordinates then the address', () {
      final withCoordinates = Site.fromJson({
        ...companyJson,
        'latitude': 30.1,
        'longitude': 31.2,
      });
      expect(withCoordinates.mapLink, contains('30.1,31.2'));

      final addressOnly = Site.fromJson(companyJson);
      expect(addressOnly.mapLink, contains(Uri.encodeComponent('المعادي، القاهرة')));
    });

    test('personal sites have no workspace requirement', () {
      final site = Site.fromJson({
        'id': 'site-2',
        'name': 'شغل خاص',
        'scope': 'PERSONAL',
        'status': 'ARCHIVED',
        'address': 'الجيزة',
      });
      expect(site.scope, SiteScope.personal);
      expect(site.status, SiteStatus.archived);
      expect(site.workspaceId, isNull);
    });
  });

  group('Task', () {
    test('detects overdue open tasks only', () {
      final open = Task.fromJson({
        'id': 'task-1',
        'title': 'معايرة',
        'status': 'OPEN',
        'priority': 'HIGH',
        'dueDate': '2000-01-01',
      });
      expect(open.priority, TaskPriority.high);
      expect(open.isOverdue, isTrue);

      final done = Task.fromJson({
        'id': 'task-2',
        'title': 'خلصت',
        'status': 'DONE',
        'dueDate': '2000-01-01',
      });
      expect(done.isOverdue, isFalse);
    });

    test('unknown wire values fall back safely', () {
      expect(TaskStatus.fromWire('NOPE'), TaskStatus.open);
      expect(TaskPriority.fromWire(null), TaskPriority.normal);
    });
  });

  group('Visit', () {
    test('keeps the date-only value and edit metadata', () {
      final visit = Visit.fromJson({
        'id': 'visit-1',
        'siteId': 'site-1',
        'visitDate': '2026-10-26',
        'completedWork': 'تركيب',
        'source': 'VOICE',
        'revision': 2,
        'editedAt': '2026-10-26T10:00:00.000Z',
        'createdBy': {'name': 'أحمد'},
      });

      expect(visit.visitDate, '2026-10-26');
      expect(visit.isVoice, isTrue);
      expect(visit.wasEdited, isTrue);
      expect(visit.createdByName, 'أحمد');
      expect(visit.editedAt, isNotNull);
    });
  });

  group('AssistantDraft', () {
    test('ignores read-only tool results', () {
      expect(AssistantDraft.tryParse(null), isNull);
      expect(
        AssistantDraft.tryParse({
          'ok': true,
          'result': {'kind': 'search', 'sites': []},
        }),
        isNull,
      );
    });

    test('parses a visit draft that needs confirmation', () {
      final draft = AssistantDraft.tryParse({
        'ok': true,
        'result': {
          'kind': 'visit',
          'requiresConfirmation': true,
          'operationId': 'op-1',
          'site': {'id': 'site-1', 'name': 'فيلا المعادي'},
          'visitDate': '2026-10-26',
          'completedWork': 'تركيب لوحة',
          'remainingWork': 'اختبار الأحمال',
        },
      });

      expect(draft, isNotNull);
      expect(draft!.isVisit, isTrue);
      expect(draft.siteId, 'site-1');
      expect(draft.siteName, 'فيلا المعادي');
      expect(draft.completedWork, 'تركيب لوحة');
    });

    test('parses a task update draft', () {
      final draft = AssistantDraft.tryParse({
        'ok': true,
        'result': {
          'kind': 'taskUpdate',
          'requiresConfirmation': true,
          'operationId': 'op-2',
          'taskId': 'task-1',
          'title': 'معايرة المضخات',
          'proposed': {'status': 'DONE'},
          'baseUpdatedAt': '2026-10-25T09:00:00.000Z',
        },
      });

      expect(draft, isNotNull);
      expect(draft!.isTaskUpdate, isTrue);
      expect(draft.taskId, 'task-1');
      expect(draft.proposedStatus, 'DONE');
      expect(draft.baseUpdatedAt, '2026-10-25T09:00:00.000Z');
    });
  });
}
