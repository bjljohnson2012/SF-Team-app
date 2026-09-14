/**
 * Covers: CockpitWinRateController
 */
@isTest
private class CockpitWinRateControllerTest {

    @isTest
    static void filterOptions_areDirectorProductAndSize() {
        Test.startTest();
        CockpitWinRateController.FilterOptions o = CockpitWinRateController.getFilterOptions();
        Test.stopTest();
        System.assertEquals(UserInfo.getUserId(), o.defaultDirectorId,
            'default scope is the running user, not a hardcoded director');
        System.assertEquals('My team', o.directors[0].label, 'first pick is My team');
        System.assertEquals(CockpitConstants.PRODUCT_ALL, o.productTypes[0].value, 'products start at All');
        System.assert(o.productTypes.size() > 1, 'product types come from EUNA_Solution__c');
        System.assertEquals(4, o.sizeBands.size(), 'All + three ARR bands');
    }

    @isTest
    static void getPage_emptyScopeExplainsNoAes() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String u = 'wrc' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User se = new User(
            FirstName = 'S', LastName = 'e', Alias = 'se1',
            Email = u + '@example.com', Username = u + '@example.com.wrc',
            ProfileId = p.Id, Title = 'Solutions Engineer',
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert se;

        Test.startTest();
        CockpitCohortService.Page page = CockpitWinRateController.getPage(
            se.Id, CockpitConstants.TEAM_MODE_DIRECTOR,
            CockpitConstants.PRODUCT_ALL, CockpitConstants.SIZE_ALL
        );
        Test.stopTest();

        System.assertNotEquals(null, page.emptyMessage, 'empty scope explains no AEs');
        System.assert(page.emptyMessage.contains('account executives'),
            'message is not a raw director-only error');
        System.assertEquals(0, page.rows.size(), 'no rows when scope has no AEs');
    }

    @isTest
    static void getPage_aeSeesOwnRow() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String u = 'wra' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User ae = new User(
            FirstName = 'A', LastName = 'e', Alias = 'ae1',
            Email = u + '@example.com', Username = u + '@example.com.wra',
            ProfileId = p.Id, Title = 'Account Executive',
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert ae;
        Account acc = new Account(Name = 'AE Book');
        insert acc;
        Id rt = [SELECT Id FROM RecordType WHERE SobjectType = 'Opportunity' AND DeveloperName = 'Euna_Sale' LIMIT 1].Id;
        insert new Opportunity(
            Name = 'Mine', AccountId = acc.Id, OwnerId = ae.Id, RecordTypeId = rt,
            Type = 'New Sale', StageName = 'Closed Won',
            CloseDate = Date.newInstance(2025, 3, 1),
            SQL_Datestamp_bf__c = Date.newInstance(2025, 1, 15)
        );

        Test.startTest();
        CockpitCohortService.Page page = CockpitWinRateController.getPage(
            ae.Id, CockpitConstants.TEAM_MODE_DIRECTOR,
            CockpitConstants.PRODUCT_ALL, CockpitConstants.SIZE_ALL
        );
        Test.stopTest();

        System.assertEquals(null, page.emptyMessage, 'AE is a valid viewer of their own row');
        System.assert(!page.rows.isEmpty(), 'AE own-book page has the SQL cohort');
        System.assert(page.scopeCaption.contains(ae.LastName) || page.scopeCaption.contains('Team of'),
            'caption names the scoped person');
    }
}
