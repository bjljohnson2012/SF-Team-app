/**
 * Covers: CockpitAeController
 */
@isTest
private class CockpitAeControllerTest {

    @isTest
    static void getScopeOptions_returnsDirectorDrivenLists() {
        Test.startTest();
        CockpitAeController.ScopeOptions o = CockpitAeController.getScopeOptions();
        Test.stopTest();
        System.assertEquals(UserInfo.getUserId(), o.runningUserId, 'running user is the default scope');
        System.assertNotEquals(null, o.directors, 'director picker list is present');
        System.assertNotEquals(null, o.productTypes, 'product types come from Opportunity.EUNA_Solution__c');
        System.assert(o.sizeBands.contains(CockpitConstants.SIZE_ALL), 'size bands include All');
    }

    @isTest
    static void loadComposition_aeSeesOwnRow() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User ae = mk(p.Id, null, 'Account Executive');
        insert ae;

        System.runAs(ae) {
            Test.startTest();
            CockpitAeCompositionService.Payload pay = CockpitAeController.loadComposition(
                null, CockpitConstants.TEAM_MODE_MINE,
                CockpitConstants.PRODUCT_ALL, CockpitConstants.SIZE_ALL);
            Test.stopTest();
            System.assertEquals(1, pay.rows.size(), 'an AE with no reports still sees their own row');
            System.assertEquals(ae.Id, pay.rows[0].ownerId, 'the row is the running AE');
            System.assertEquals(true, pay.selfScoped, 'self-scope is explicit, not a director-only error');
        }
    }

    @isTest
    static void roster_directorPicker_notHardcoded() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User dir = mk(p.Id, null, 'Director');
        insert dir;
        User ae = mk(p.Id, dir.Id, 'Account Executive');
        insert ae;

        Test.startTest();
        CockpitRosterService.Scope mine;
        System.runAs(dir) {
            mine = CockpitRosterService.resolve(null, CockpitConstants.TEAM_MODE_MINE);
        }
        List<CockpitRosterService.Member> directors = CockpitRosterService.listDirectors();
        Test.stopTest();

        System.assert(mine.ids().contains(ae.Id), 'default scope is the running director\'s team');
        Boolean listed = false;
        for (CockpitRosterService.Member m : directors) {
            if (m.userId == dir.Id) listed = true;
        }
        System.assert(listed, 'director picker includes the manager, not a hardcoded Team Johnson id');
    }

    static Integer seq = 0;
    static User mk(Id profileId, Id mgr, String title) {
        seq++;
        String u = 'cokae' + seq + '' + System.currentTimeMillis();
        return new User(
            FirstName = 'T', LastName = 'ae' + seq, Alias = ('ae' + seq).left(8),
            Email = u + '@example.com', Username = u + '@example.com.cokae',
            ProfileId = profileId, ManagerId = mgr, Title = title,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }
}
