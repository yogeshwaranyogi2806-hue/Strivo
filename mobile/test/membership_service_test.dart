import 'package:flutter_test/flutter_test.dart';
import 'package:strivo/core/services/membership_service.dart';

Membership m(String orgId, String name, String role) => Membership(
      id: 'membership-$orgId',
      organizationId: orgId,
      organizationName: name,
      role: OrgRole.fromValue(role),
    );

void main() {
  group('OrgRole', () {
    test('owner and coach are back office', () {
      expect(OrgRole.owner.isStaff, isTrue);
      expect(OrgRole.coach.isStaff, isTrue);
    });

    test('student and parent are front office', () {
      expect(OrgRole.student.isStaff, isFalse);
      expect(OrgRole.student.isFrontOffice, isTrue);
      expect(OrgRole.parent.isFrontOffice, isTrue);
    });

    test('an unknown role is never treated as staff', () {
      // Defaulting to owner would grant back-office access on a typo.
      final role = OrgRole.fromValue('head_coach');
      expect(role.isStaff, isFalse);
      expect(role, OrgRole.parent);
    });

    test('a null role is not staff', () {
      expect(OrgRole.fromValue(null).isStaff, isFalse);
    });
  });

  group('Membership.fromRow', () {
    test('reads the embedded organization name', () {
      final membership = Membership.fromRow(<String, dynamic>{
        'id': 'membership-1',
        'organization_id': 'org-1',
        'role': 'owner',
        'organizations': <String, dynamic>{'id': 'org-1', 'name': 'Strivo FC'},
      });
      expect(membership.organizationName, 'Strivo FC');
      expect(membership.id, 'membership-1');
      expect(membership.role, OrgRole.owner);
    });

    test('copes with the organization not being returned', () {
      final membership = Membership.fromRow(<String, dynamic>{
        'id': 'membership-1',
        'organization_id': 'org-1',
        'role': 'coach',
      });
      expect(membership.organizationName, 'this studio');
    });
  });

  group('primaryRole', () {
    test('is null with no memberships', () {
      expect(MembershipService.primaryRole(const []), isNull);
    });

    test('picks the strongest role when in several studios', () {
      final memberships = [
        m('org-1', 'Strivo FC', 'student'),
        m('org-2', 'Rovers', 'owner'),
        m('org-3', 'JUNI', 'coach'),
      ]..sort((a, b) => a.role.rank.compareTo(b.role.rank));
      expect(MembershipService.primaryRole(memberships), OrgRole.owner);
    });

    test('a coach who is also a student counts as staff', () {
      final memberships = [
        m('org-1', 'Strivo FC', 'student'),
        m('org-2', 'Strivo FC', 'coach'),
      ]..sort((a, b) => a.role.rank.compareTo(b.role.rank));
      expect(MembershipService.isBackOffice(memberships), isTrue);
    });
  });

  group('classification', () {
    test('an account with no membership is not staff', () {
      expect(MembershipService.isBackOffice(const []), isFalse);
    });

    test('an account with no membership needs a workspace', () {
      expect(MembershipService.needsWorkspace(const []), isTrue);
      expect(MembershipService.needsWorkspace([m('org-1', 'A', 'owner')]), isFalse);
    });
  });

  group('landingRoute', () {
    test('a student is kept out of the back office', () {
      expect(
        MembershipService.landingRoute([m('org-1', 'Strivo FC', 'student')]),
        '/student',
      );
    });

    test('a parent goes to the front office too', () {
      expect(
        MembershipService.landingRoute([m('org-1', 'Strivo FC', 'parent')]),
        '/student',
      );
    });

    test('a coach goes to the back office', () {
      expect(
        MembershipService.landingRoute([m('org-1', 'Strivo FC', 'coach')]),
        '/home',
      );
    });

    test('an account with no membership gets its own screen', () {
      expect(MembershipService.landingRoute(const []), '/no-workspace');
    });
  });
}