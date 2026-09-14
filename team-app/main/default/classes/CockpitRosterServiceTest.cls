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
    static void emptyTeam_nonAE_returnsEmpty() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User lone = mk(p.Id, null, 'Solutions Engineer');
        insert lone;
        System.assert(CockpitRosterService.teamIds(lone.Id).isEmpty(),
            'non-AE with no reports is not a valid viewer row');
    }

    @isTest
    static void aeWithNoReports_seesSelf() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User ae = mk(p.Id, null, 'Account Executive');
        insert ae;
        Set<Id> ids = CockpitRosterService.teamIds(ae.Id);
        System.assert(ids.contains(ae.Id), 'AE is a valid viewer of their own row');
        System.assertEquals(1, ids.size(), 'self only');
    }

    @isTest
    static void resolveScope_defaultsToRunningUser() {
        CockpitRosterService.ScopeResult s = CockpitRosterService.resolveScope(
            null, CockpitConstants.TEAM_MODE_MY);
        System.assertEquals(UserInfo.getUserId(), s.directorId, 'my team is the running user');
        System.assertNotEquals(null, s.directorName, 'director name populated');
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
