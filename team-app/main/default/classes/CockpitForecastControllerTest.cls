/**
 * Covers: CockpitForecastController
 */
@isTest
private class CockpitForecastControllerTest {

    @isTest
    static void load_returnsScoredPipeline() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User dir = usr(p.Id, null, 'Director');
        insert dir;
        User rep = usr(p.Id, dir.Id, 'Account Executive');
        insert rep;
        Id rtId = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Opportunity' AND DeveloperName = 'Euna_Sale' LIMIT 1
        ].Id;

        System.runAs(dir) {
            Account a = new Account(Name = 'Acme');
            insert a;
            // ARR_Opportunity_Amount_USD_Num__c is a read-only formula, so it is
            // not set here; the deal still matches the filters and is returned.
            Opportunity o = new Opportunity(
                Name = 'Big Deal', AccountId = a.Id, OwnerId = rep.Id, RecordTypeId = rtId,
                Type = 'New Sale', StageName = 'Proposal',
                CloseDate = Date.today().addDays(30),
                SQL_Datestamp_bf__c = Date.today().addDays(-15)
            );
            insert o;

            Test.startTest();
            CockpitForecastController.Payload pay = CockpitForecastController.load();
            Test.stopTest();

            System.assert(pay.teamSize >= 1, 'team resolved');
            System.assertEquals(1, pay.deals.size(), 'the rep deal is returned');
            System.assertEquals('Acme', pay.deals[0].account, 'account maps');
            System.assertNotEquals(null, pay.deals[0].klass, 'deal is classified');
            System.assertNotEquals(null, pay.deals[0].bucket, 'deal has a quarter bucket');
            System.assertNotEquals(null, pay.qLabelA, 'current quarter label set');
        }
    }

    @isTest
    static void load_noReports_throws() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User lone = usr(p.Id, null, 'Director');
        insert lone;
        System.runAs(lone) {
            try {
                CockpitForecastController.load();
                System.assert(false, 'expected AuraHandledException for no reports');
            } catch (AuraHandledException e) {
                System.assert(true, 'no-reports path throws');
            }
        }
    }

    static Integer seq = 0;
    static User usr(Id profileId, Id mgr, String title) {
        seq++;
        String u = 'cokc' + seq + '' + System.currentTimeMillis();
        return new User(
            FirstName = 'T', LastName = 'c' + seq, Alias = ('c' + seq).left(8),
            Email = u + '@example.com', Username = u + '@example.com.cokc',
            ProfileId = profileId, ManagerId = mgr, Title = title,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }
}
