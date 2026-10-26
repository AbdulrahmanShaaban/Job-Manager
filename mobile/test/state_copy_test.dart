import 'package:flutter_test/flutter_test.dart';
import 'package:job_manager/models/voice.dart';
import 'package:job_manager/state/data_providers.dart';
import 'package:job_manager/state/voice_controller.dart';

void main() {
  group('VoiceState.copyWith', () {
    test('keeps the current status and error when they are omitted', () {
      const state = VoiceState(status: 'اتكلم…', error: 'خطأ قديم');

      final next = state.copyWith(phase: VoicePhase.listening);

      expect(next.status, 'اتكلم…');
      expect(next.error, 'خطأ قديم');
    });

    test('clears status and error when null is passed explicitly', () {
      const state = VoiceState(status: 'اتكلم…', error: 'خطأ قديم');

      final next = state.copyWith(status: null, error: null);

      expect(next.status, isNull);
      expect(next.error, isNull);
    });

    test('keeps the draft unless it is explicitly cleared', () {
      const draft = AssistantDraft(kind: 'visit', operationId: 'op-1');
      const state = VoiceState(draft: draft, status: 'راجع المسودة');

      final kept = state.copyWith(phase: VoicePhase.reviewing);
      final cleared = kept.copyWith(clearDraft: true);

      expect(kept.draft, same(draft));
      expect(cleared.draft, isNull);
      expect(cleared.phase, VoicePhase.reviewing);
    });
  });

  group('SyncStatus.copyWith', () {
    test('keeps the last error when omitted and clears it when null', () {
      const status = SyncStatus(pending: 2, lastError: 'فشل الرفع');

      final kept = status.copyWith(pending: 1);
      final cleared = kept.copyWith(lastError: null);

      expect(kept.lastError, 'فشل الرفع');
      expect(kept.pending, 1);
      expect(cleared.lastError, isNull);
    });

    test('reports queued work when any queue is non-empty', () {
      expect(const SyncStatus().hasQueued, isFalse);
      expect(const SyncStatus(pending: 1).hasQueued, isTrue);
      expect(const SyncStatus(conflicts: 1).hasQueued, isTrue);
      expect(const SyncStatus(failed: 1).hasQueued, isTrue);
    });
  });
}
