import 'package:flutter_test/flutter_test.dart';
import 'package:strivo/core/services/invitation_service.dart';

void main() {
  group('normaliseCode', () {
    test('accepts a bare lowercase code', () {
      expect(
        InvitationService.normaliseCode('a1b2c3d4e5f60718'),
        'A1B2C3D4E5F60718',
      );
    });

    test('strips the grouping spaces', () {
      expect(
        InvitationService.normaliseCode('A1B2 C3D4 E5F6 0718'),
        'A1B2C3D4E5F60718',
      );
    });

    test('strips anything else pasted in, such as a full link', () {
      expect(
        InvitationService.normaliseCode('https://strivo.app/invite/a1b2c3d4e5f60718'),
        'A1B2C3D4E5F60718',
      );
    });

    test('trims surrounding whitespace', () {
      expect(InvitationService.normaliseCode('  A1B2C3D4E5F60718  '), 'A1B2C3D4E5F60718');
    });
  });

  group('formatCode', () {
    test('groups into blocks of four for reading', () {
      expect(InvitationService.formatCode('A1B2C3D4E5F60718'), 'A1B2 C3D4 E5F6 0718');
    });

    test('does not drop a trailing partial block', () {
      expect(InvitationService.formatCode('A1B2C3D4E5F6'), 'A1B2 C3D4 E5F6');
      expect(InvitationService.formatCode('A1B2C3'), 'A1B2 C3');
    });

    test('handles a single character without throwing', () {
      expect(InvitationService.formatCode('A'), 'A');
    });
  });

  group('InviteRole', () {
    test('maps database values back to roles', () {
      expect(InviteRole.fromValue('owner'), InviteRole.owner);
      expect(InviteRole.fromValue('coach'), InviteRole.coach);
      expect(InviteRole.fromValue('student'), InviteRole.student);
    });

    test('falls back to student for an unknown value', () {
      expect(InviteRole.fromValue('principal'), InviteRole.student);
      expect(InviteRole.fromValue(null), InviteRole.student);
    });
  });

  group('InvitationPreview', () {
    test('an open code is redeemable by anyone', () {
      const preview = InvitationPreview(
        role: InviteRole.student,
        organizationName: 'Strivo FC',
        invitedEmail: null,
        isUsable: true,
      );
      expect(preview.openToAnyone, isTrue);
    });

    test('a code bound to an address is not open', () {
      const preview = InvitationPreview(
        role: InviteRole.coach,
        organizationName: 'Strivo FC',
        invitedEmail: 'coach@example.com',
        isUsable: true,
      );
      expect(preview.openToAnyone, isFalse);
    });

    test('an empty invited email counts as open', () {
      const preview = InvitationPreview(
        role: InviteRole.coach,
        organizationName: 'Strivo FC',
        invitedEmail: '',
        isUsable: true,
      );
      expect(preview.openToAnyone, isTrue);
    });

    test('reads a row returned by invitation_details', () {
      final preview = InvitationPreview.fromRow(<String, dynamic>{
        'role': 'coach',
        'organization_name': 'Strivo FC',
        'invited_email': null,
        'is_usable': true,
      });
      expect(preview.role, InviteRole.coach);
      expect(preview.organizationName, 'Strivo FC');
      expect(preview.isUsable, isTrue);
    });
  });
}