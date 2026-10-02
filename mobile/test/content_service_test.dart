import 'package:flutter_test/flutter_test.dart';
import 'package:strivo/core/services/content_service.dart';

void main() {
  group('ContentType', () {
    test('round-trips every database value', () {
      for (final type in ContentType.values) {
        expect(ContentType.fromValue(type.value), type);
      }
    });

    test('an unknown value falls back to article rather than crashing', () {
      expect(ContentType.fromValue('podcast'), ContentType.article);
      expect(ContentType.fromValue(null), ContentType.article);
    });
  });

  group('ContentItem.fromRow', () {
    ContentItem row(Map<String, dynamic> data) => ContentItem.fromRow(data);

    test('reads a published document', () {
      final item = row(<String, dynamic>{
        'id': 'c1',
        'title': 'Bouncing drill',
        'description': 'Drill for ball control.',
        'content_type': 'video',
        'file_url': 'https://example.com/drill.mp4',
        'file_name': 'drill.mp4',
        'file_size': 1048576,
        'is_published': true,
        'published_at': '2026-03-01T10:00:00Z',
      });
      expect(item.type, ContentType.video);
      expect(item.hasFile, isTrue);
      expect(item.isPublished, isTrue);
      expect(item.publishedAt, isNotNull);
      expect(item.fileSize, 1048576);
    });

    test('an article with no file is still valid', () {
      final item = row(<String, dynamic>{
        'id': 'c2',
        'title': 'Warm-up routine',
        'content_type': 'article',
        'file_url': null,
        'is_published': true,
      });
      expect(item.hasFile, isFalse);
      expect(item.publishedAt, isNull);
    });

    test('treats an empty file_url as no file', () {
      final item = row(<String, dynamic>{
        'id': 'c3',
        'title': 'Notes',
        'content_type': 'document',
        'file_url': '',
      });
      expect(item.hasFile, isFalse);
    });

    test('survives a row with almost everything missing', () {
      final item = row(<String, dynamic>{'id': 'c4'});
      expect(item.title, 'Untitled');
      expect(item.isPublished, isFalse);
      expect(item.hasFile, isFalse);
    });

    test('a missing title does not become null', () {
      final item = row(<String, dynamic>{'id': 'c5', 'title': null});
      expect(item.title, 'Untitled');
    });
  });

  group('UnlinkedStudent', () {
    test('a record side is flagged as a record, not a login', () {
      const entry = UnlinkedStudent(
        studentId: 's1',
        studentName: 'Aarav',
        membershipId: null,
        loginEmail: null,
      );
      expect(entry.isRecord, isTrue);
      expect(entry.isLogin, isFalse);
      expect(entry.label, 'Aarav');
    });

    test('a login side is flagged as a login', () {
      const entry = UnlinkedStudent(
        studentId: null,
        studentName: null,
        membershipId: 'm1',
        loginEmail: 'aarav@example.com',
      );
      expect(entry.isLogin, isTrue);
      expect(entry.isRecord, isFalse);
      expect(entry.label, 'aarav@example.com');
    });
  });
}