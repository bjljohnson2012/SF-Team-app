/**
 * Covers: CockpitConversionController
 */
@isTest
private class CockpitConversionControllerTest {

    @isTest
    static void load_andOptions_matchFilterContract() {
        User dir = usr(null, 'Director');
        insert dir;
        User rep = usr(dir.Id, 'Account Executive');
        insert rep;

        System.runAs(dir) {
            Test.startTest();
            CockpitConversionService.ScopeOptions opts = CockpitConversionController.getScopeOptions();
            CockpitConversionService.PagePayload page = CockpitConversionController.load(
                dir.Id, 'director', null, 'ALL');
            Test.stopTest();

            System.assertNotEquals(null, opts, 'filter options returned');
            System.assert(!opts.directors.isEmpty(), 'director picker includes My team');
            System.assertEquals('mine', opts.directors[0].value, 'first option is my-team mode');
            Set<String> salesUsernames = new Set<String>();
            for (Forecast_Director__mdt d : [
                SELECT Username__c FROM Forecast_Director__mdt
                WHERE Is_Active__c = true AND Excluded__c = false
            ]) {
                if (String.isNotBlank(d.Username__c)) salesUsernames.add(d.Username__c.toLowerCase());
            }
            for (CockpitConversionService.FilterOption o : opts.directors) {
                if (o.value == 'mine') continue;
                User u = [SELECT Username FROM User WHERE Id = :o.value];
                System.assert(salesUsernames.contains(u.Username.toLowerCase()),
                    'picker lists sales directors only');
            }
            System.assert(!opts.productTypes.isEmpty(), 'product type is EUNA_Solution__c');
            System.assert(!opts.sizeBands.isEmpty(), 'ARR size bands served from Apex');
            System.assertNotEquals(null, page, 'load returns a payload');
            System.assertNotEquals(null, page.scope, 'scope is director-driven');
            System.assertEquals(dir.Id, page.scope.directorId, 'selected director is honored');
        }
    }

    static Integer seq = 0;
    static User usr(Id mgr, String title) {
        seq++;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String u = 'cvcc' + seq + String.valueOf(System.currentTimeMillis());
        return new User(
            FirstName = 'T', LastName = 'c' + seq, Alias = ('c' + seq).left(8),
            Email = u + '@example.com', Username = u + '@example.com.cvcc',
            ProfileId = p.Id, ManagerId = mgr, Title = title,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }
}
