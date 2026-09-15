/**
 * Covers: CockpitRosterService
 */
@isTest
private class CockpitRosterServiceTest {

    @isTest
    static void twoLevelWalk_excludesNonAE() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User dir = mk(p.Id, null, 'Director');
        insert dir;
        User ae = mk(p.Id, dir.Id, 'Account Executive');
        User se = mk(p.Id, dir.Id, 'Solutions Engineer');
        insert new List<User>{ ae, se };
        User ae2 = mk(p.Id, ae.Id, 'Account Executive');
        insert ae2;

        Test.startTest();
        List<CockpitRosterService.Member> team = CockpitRosterService.teamFor(dir.Id);
        Set<Id> ids = CockpitRosterService.teamIds(dir.Id);
        Test.stopTest();

        System.assert(ids.contains(ae.Id), 'level-1 AE included');
        System.assert(ids.contains(ae2.Id), 'level-2 AE included through the team lead');
        System.assert(!ids.contains(se.Id), 'Solutions Engineer excluded');
        System.assertEquals(2, team.size(), 'two AEs kept, SE dropped');
    }

    @isTest
    static void isSalesTeamLeaderRole_keepsDirectorsUnderCso_dropsSupportAndSe() {
        System.assertEquals(true,
            CockpitRosterService.isSalesTeamLeaderRole('MM NE Director', 'Director, Sales'));
        System.assertEquals(true,
            CockpitRosterService.isSalesTeamLeaderRole('VP Sales', 'Corporate Strategy'));
        System.assertEquals(true,
            CockpitRosterService.isSalesTeamLeaderRole('Chief Sales Officer', 'Chief Sales Officer'));
        System.assertEquals(false,
            CockpitRosterService.isSalesTeamLeaderRole('Chief Sales Officer', 'Chief Product Officer'),
            'CSO role with a non-CSO title is not a sales team leader');
        System.assertEquals(false,
            CockpitRosterService.isSalesTeamLeaderRole('Director - Sales Support', 'Senior Bid Specialist'));
        System.assertEquals(false,
            CockpitRosterService.isSalesTeamLeaderRole('Solutions Engineers', 'VP, Solutions'));
        System.assertEquals(false,
            CockpitRosterService.isSalesTeamLeaderRole('Partnerships', 'VP, Partnerships'));
        System.assertEquals(false,
            CockpitRosterService.isSalesTeamLeaderRole('MM NE Rep', 'Account Executive'));
        System.assertEquals(false, CockpitRosterService.isSalesTeamLeaderRole(null, 'Director'));
    }

    @isTest
    static void salesDirectors_onlyCsoRollupTeamLeaders() {
        Set<Id> underCso = CockpitRosterService.rolesUnderChiefSalesOfficer();
        System.assert(!underCso.isEmpty(), 'org has a Chief Sales Officer role tree');

        Test.startTest();
        List<CockpitRosterService.DirectorOption> dirs = CockpitRosterService.salesDirectors();
        Test.stopTest();

        Set<Id> seen = new Set<Id>();
        for (CockpitRosterService.DirectorOption d : dirs) {
            System.assertNotEquals(null, d.userId, 'sales director has a user id');
            System.assertEquals(false, seen.contains(d.userId), 'each leader once');
            seen.add(d.userId);
            User u = [
                SELECT IsActive, Title, UserRoleId, UserRole.Name
                FROM User WHERE Id = :d.userId
            ];
            System.assertEquals(true, u.IsActive, 'inactive users stay out of the picker');
            System.assert(underCso.contains(u.UserRoleId),
                u.Name + ' role must roll up to Chief Sales Officer');
            System.assertEquals(true,
                CockpitRosterService.isSalesTeamLeaderRole(
                    u.UserRole == null ? null : u.UserRole.Name, u.Title),
                u.Name + ' is a selling-team leader role, not support/SE/alliances');
        }
    }

    @isTest
    static void emptyTeam_returnsEmpty() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User lone = mk(p.Id, null, 'Director');
        insert lone;
        System.assert(CockpitRosterService.teamIds(lone.Id).isEmpty(), 'no reports -> empty');
    }

    static Integer seq = 0;
    static User mk(Id profileId, Id mgr, String title) {
        seq++;
        String u = 'cokr' + seq + '' + System.currentTimeMillis();
        return new User(
            FirstName = 'T', LastName = 'r' + seq, Alias = ('r' + seq).left(8),
            Email = u + '@example.com', Username = u + '@example.com.cokr',
            ProfileId = profileId, ManagerId = mgr, Title = title,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }
}
