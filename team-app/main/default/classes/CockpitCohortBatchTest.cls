/**
 * Covers: CockpitCohortBatch
 */
@isTest
private class CockpitCohortBatchTest {

    @isTest
    static void execute_upsertsSnapshotForDirector() {
        User dir = usr(null, 'Director');
        insert dir;
        User ae = usr(dir.Id, 'Account Executive');
        insert ae;
        Account a = new Account(Name = 'Snap');
        insert a;
        Id rt = [SELECT Id FROM RecordType WHERE SobjectType = 'Opportunity' AND DeveloperName = 'Euna_Sale' LIMIT 1].Id;
        insert new Opportunity(
            Name = 'Won', AccountId = a.Id, OwnerId = ae.Id, RecordTypeId = rt,
            Type = 'New Sale', StageName = 'Closed Won',
            CloseDate = Date.newInstance(2025, 3, 1),
            SQL_Datestamp_bf__c = Date.newInstance(2025, 1, 15),
            EUNA_Solution__c = 'Budget Professional'
        );

        Test.startTest();
        Database.executeBatch(new CockpitCohortBatch(new List<Id>{ dir.Id }), 1);
        Test.stopTest();

        List<Cockpit_Cohort_Snapshot__c> snaps = [
            SELECT External_Id__c, Director__c, Cohort_Key__c, Won_Count__c,
                   Contested_Win_Rate__c, Snapshot_Date__c
            FROM Cockpit_Cohort_Snapshot__c
            WHERE Director__c = :dir.Id
        ];
        Cockpit_Cohort_Snapshot__c sqlSnap;
        for (Cockpit_Cohort_Snapshot__c s : snaps) {
            if (s.Cohort_Key__c == '2025Q1') sqlSnap = s;
        }
        System.assertNotEquals(null, sqlSnap, 'SQL cohort upserted');
        System.assertEquals(1, sqlSnap.Won_Count__c, 'won count stored');
        System.assertEquals(Date.today(), sqlSnap.Snapshot_Date__c, 'as-of is today');
        System.assert(sqlSnap.External_Id__c.contains(String.valueOf(dir.Id)),
            'external id is director-scoped, not UserInfo-only');
    }

    @isTest
    static void schedule_enqueuesWithoutRunningOrgDirectors() {
        String jobId = System.schedule(
            'Cockpit cohort test ' + String.valueOf(Crypto.getRandomInteger()),
            '0 15 2 * * ?',
            new CockpitCohortBatch()
        );
        CronTrigger ct = [SELECT Id, CronJobDetail.Name FROM CronTrigger WHERE Id = :jobId];
        System.assertNotEquals(null, ct.Id, 'schedulable accepted');
        System.assert(ct.CronJobDetail.Name.contains('Cockpit cohort test'),
            'job name is the one we scheduled');
    }

    static Integer seq = 0;
    static User usr(Id mgr, String title) {
        seq++;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String u = 'wrb' + seq + '' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return new User(
            FirstName = 'B', LastName = 'b' + seq, Alias = ('b' + seq).left(8),
            Email = u + '@example.com', Username = u + '@example.com.wrb',
            ProfileId = p.Id, ManagerId = mgr, Title = title,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }
}
