/**
 * Covers: CockpitForecastController
 */
@isTest
private class CockpitForecastControllerTest {

    @isTest
    static void load_returnsScoredPipeline() {
        User dir = setupDirectorWithRep();
        User rep = [SELECT Id FROM User WHERE ManagerId = :dir.Id LIMIT 1];
        Id rtId = eunaSaleRtId();

        System.runAs(dir) {
            Opportunity o = newDeal(rep.Id, rtId);
            insert o;

            Test.startTest();
            CockpitForecastController.Payload pay = CockpitForecastController.load();
            Test.stopTest();

            System.assert(pay.teamSize >= 1, 'team resolved');
            System.assertEquals(1, pay.deals.size(), 'the rep deal is returned');
            System.assertEquals('Acme', pay.deals[0].account, 'account maps');
            System.assertNotEquals(null, pay.deals[0].bucket, 'deal has a quarter bucket');
            System.assertNotEquals(null, pay.qLabelA, 'current quarter label set');
            System.assert(pay.aeNames != null && !pay.aeNames.isEmpty(), 'AE names for filter');
        }
    }

    @isTest
    static void setInCall_and_setOverride_persist() {
        User dir = setupDirectorWithRep();
        User rep = [SELECT Id FROM User WHERE ManagerId = :dir.Id LIMIT 1];
        Id rtId = eunaSaleRtId();

        System.runAs(dir) {
            Opportunity o = newDeal(rep.Id, rtId);
            insert o;

            Test.startTest();
            CockpitForecastController.setInCall(o.Id, true);
            CockpitForecastController.setOverride(o.Id, 'HI', 'Verbal win, paper in flight');
            Integer n = CockpitForecastController.applyDefaultPicks('A');
            Test.stopTest();

            Opportunity check = [SELECT Cockpit_In_Call__c, Cockpit_Class_Override__c, Cockpit_Override_Note__c
                                 FROM Opportunity WHERE Id = :o.Id];
            System.assertEquals(true, check.Cockpit_In_Call__c, 'in-call persisted');
            System.assertEquals('HI', check.Cockpit_Class_Override__c, 'override class persisted');
            System.assertEquals('Verbal win, paper in flight', check.Cockpit_Override_Note__c, 'note persisted');
            System.assert(n >= 1, 'applyDefaultPicks touched the deal');
        }
    }

    @isTest
    static void setOverride_blankClears() {
        User dir = setupDirectorWithRep();
        User rep = [SELECT Id FROM User WHERE ManagerId = :dir.Id LIMIT 1];
        Id rtId = eunaSaleRtId();
        System.runAs(dir) {
            Opportunity o = newDeal(rep.Id, rtId);
            insert o;
            CockpitForecastController.setOverride(o.Id, 'MD', 'note');
            CockpitForecastController.setOverride(o.Id, '', null);
            Opportunity check = [SELECT Cockpit_Class_Override__c FROM Opportunity WHERE Id = :o.Id];
            System.assertEquals(null, check.Cockpit_Class_Override__c, 'blank class clears the override');
        }
    }

    @isTest
    static void analytics_returnLists() {
        User dir = setupDirectorWithRep();
        User rep = [SELECT Id FROM User WHERE ManagerId = :dir.Id LIMIT 1];
        Id rtId = eunaSaleRtId();
        System.runAs(dir) {
            Account a = new Account(Name = 'Hist');
            insert a;
            Opportunity lost = new Opportunity(
                Name = 'Lost Deal', AccountId = a.Id, OwnerId = rep.Id, RecordTypeId = rtId,
                Type = 'New Sale', StageName = 'Closed Lost', CloseDate = Date.today().addDays(-40),
                Lost_Reason__c = 'Ghosted', SQL_Datestamp_bf__c = Date.today().addDays(-160));
            insert lost;

            Test.startTest();
            List<CockpitForecastController.QuarterRow> cp = CockpitForecastController.getCreatedPipeline();
            List<CockpitForecastController.BandRow> cv = CockpitForecastController.getConversion();
            List<CockpitForecastController.CohortRow> wr = CockpitForecastController.getWinRateTruth();
            List<CockpitForecastController.AeRow> ae = CockpitForecastController.getAeConversion();
            Test.stopTest();
            System.assertNotEquals(null, cp, 'created pipeline list returned');
            System.assert(!cp.isEmpty(), 'created pipeline has the historical quarter');
            System.assertNotEquals(null, cv, 'conversion list returned');
            System.assert(!wr.isEmpty(), 'win-rate truth has the team row + cohort');
            System.assert(!ae.isEmpty(), 'AE-by-AE has the rep');
        }
    }

    @isTest
    static void load_noReports_throws() {
        User lone = usr(null, 'Director');
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

    // ---- helpers ----
    static Integer seq = 0;

    static User setupDirectorWithRep() {
        User dir = usr(null, 'Director');
        insert dir;
        User rep = usr(dir.Id, 'Account Executive');
        insert rep;
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'GTM_Team_Johnson_Access' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = dir.Id, PermissionSetId = ps.Id);
        return dir;
    }

    static Id eunaSaleRtId() {
        return [SELECT Id FROM RecordType
                WHERE SobjectType = 'Opportunity' AND DeveloperName = 'Euna_Sale' LIMIT 1].Id;
    }

    static Date curQtrStart() {
        Date t = Date.today();
        return Date.newInstance(t.year(), ((t.month() - 1) / 3) * 3 + 1, 1);
    }

    static Opportunity newDeal(Id ownerId, Id rtId) {
        Account a = new Account(Name = 'Acme');
        insert a;
        return new Opportunity(
            Name = 'Big Deal', AccountId = a.Id, OwnerId = ownerId, RecordTypeId = rtId,
            Type = 'New Sale', StageName = 'Proposal', CloseDate = curQtrStart().addDays(20),
            SQL_Datestamp_bf__c = Date.today().addDays(-15));
    }

    static User usr(Id mgr, String title) {
        seq++;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String u = 'cokc' + seq + '' + System.currentTimeMillis();
        return new User(
            FirstName = 'T', LastName = 'c' + seq, Alias = ('c' + seq).left(8),
            Email = u + '@example.com', Username = u + '@example.com.cokc',
            ProfileId = p.Id, ManagerId = mgr, Title = title,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
    }
}
