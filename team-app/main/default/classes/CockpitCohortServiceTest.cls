/**
 * Covers: CockpitCohortService
 * Seven behavioural cases: SQL cohort key, bucket sum, Ghosted canon,
 * blank never-real, unmapped worked, immature/thin headlines, purge detectors.
 */
@isTest
private class CockpitCohortServiceTest {

    @TestSetup
    static void makeData() {
        User dir = usr(null, 'Director');
        insert dir;
        User ae = usr(dir.Id, 'Account Executive');
        insert ae;
    }

    @isTest
    static void cohortKey_usesSqlDatestampNotCreatedDate() {
        User dir = dir();
        User ae = aeOf(dir.Id);
        Id rt = rtId();
        Account a = new Account(Name = 'SQL Cohort');
        insert a;
        Opportunity o = base(a.Id, ae.Id, rt);
        o.Name = 'Created today, SQL in 2025 Q1';
        o.SQL_Datestamp_bf__c = Date.newInstance(2025, 1, 20);
        o.StageName = 'Closed Won';
        o.CloseDate = Date.newInstance(2025, 3, 10);
        insert o;

        Test.startTest();
        CockpitCohortService.WinRatePage page = pageFor(dir.Id);
        Test.stopTest();

        CockpitCohortService.CohortRow row = rowOf(page, '2025Q1');
        System.assertNotEquals(null, row, 'SQL Q1 2025 must be the cohort key');
        System.assertEquals(null, rowOf(page, CockpitCohortService.cohortKeyOf(Date.today())),
            'CreatedDate quarter must not receive the deal');
        System.assertEquals(1, row.won, 'the won deal lands in the SQL vintage');
    }

    @isTest
    static void bucketSum_equalsCreated() {
        User dir = dir();
        User ae = aeOf(dir.Id);
        Id rt = rtId();
        Account a = new Account(Name = 'Buckets');
        insert a;
        Date sql = Date.newInstance(2025, 2, 1);
        insert new List<Opportunity>{
            closed(a.Id, ae.Id, rt, 'Won', sql, Date.newInstance(2025, 4, 1), 'Closed Won', null),
            closed(a.Id, ae.Id, rt, 'Worked', sql, Date.newInstance(2025, 4, 2), 'Closed Lost', 'Perceived lack of ROI'),
            closed(a.Id, ae.Id, rt, 'Ghost', sql, Date.newInstance(2025, 4, 3), 'Closed Lost', 'Ghosted'),
            closed(a.Id, ae.Id, rt, 'Blank', sql, Date.newInstance(2025, 4, 4), 'Closed Lost', null),
            openDeal(a.Id, ae.Id, rt, 'Open', sql)
        };

        Test.startTest();
        CockpitCohortService.WinRatePage page = pageFor(dir.Id);
        Test.stopTest();

        CockpitCohortService.CohortRow row = rowOf(page, '2025Q1');
        System.assertEquals(5, row.created, 'five SQL-cohort deals');
        System.assertEquals(row.created, row.won + row.worked + row.neverReal + row.stillOpen,
            'bucket sum equals created');
        System.assertEquals(1, row.won, 'one win');
        System.assertEquals(1, row.worked, 'ROI is a worked loss');
        System.assertEquals(2, row.neverReal, 'Ghosted + blank are never-real');
        System.assertEquals(1, row.stillOpen, 'one still open');
    }

    @isTest
    static void ghostedExcluded_fromContestedByDefault() {
        User dir = dir();
        User ae = aeOf(dir.Id);
        Id rt = rtId();
        Account a = new Account(Name = 'Ghosted');
        insert a;
        Date sql = Date.newInstance(2025, 2, 1);
        insert new List<Opportunity>{
            closed(a.Id, ae.Id, rt, 'Won', sql, Date.newInstance(2025, 5, 1), 'Closed Won', null),
            closed(a.Id, ae.Id, rt, 'Ghost', sql, Date.newInstance(2025, 5, 2), 'Closed Lost', 'Ghosted')
        };

        Test.startTest();
        CockpitCohortService.WinRatePage page = pageFor(dir.Id);
        Test.stopTest();

        CockpitCohortService.CohortRow row = rowOf(page, '2025Q1');
        System.assertEquals(1, row.neverReal, 'Ghosted is never-real under Euna canon');
        System.assertEquals(0, row.worked, 'Ghosted is not a worked loss');
        System.assertEquals(1, row.contestedWR, 'contested is won/(won+worked) = 1/1');
        System.assert(page.excludeGhosted, 'default setting excludes Ghosted');
        System.assert(page.ghostedConvention.contains('never-real'),
            'page prints the Ghosted convention');
    }

    @isTest
    static void blankReason_isNeverReal() {
        Opportunity o = (Opportunity) JSON.deserialize(
            '{"IsClosed":true,"IsWon":false}', Opportunity.class);
        System.assertEquals('NEVER', CockpitCohortService.classifyForTest(o),
            'blank loss reason is never-real');
    }

    @isTest
    static void unmappedReason_isWorkedAndSurfaced() {
        User dir = dir();
        User ae = aeOf(dir.Id);
        Id rt = rtId();
        Account a = new Account(Name = 'Unmapped');
        insert a;
        Date sql = Date.newInstance(2025, 2, 1);
        insert closed(a.Id, ae.Id, rt, 'Refs', sql, Date.newInstance(2025, 5, 1),
            'Closed Lost', 'Quality of references');

        Test.startTest();
        CockpitCohortService.WinRatePage page = pageFor(dir.Id);
        Test.stopTest();

        CockpitCohortService.CohortRow row = rowOf(page, '2025Q1');
        System.assertEquals(1, row.worked, 'unmapped reason counts as worked loss');
        System.assertEquals(0, row.neverReal, 'unmapped is not never-real');
        System.assertEquals(1, page.unmappedReasons.size(), 'unmapped reasons are surfaced');
        System.assertEquals('Quality of references', page.unmappedReasons[0].reason,
            'Quality of references is left unmapped so mapping honesty can surface it');
    }

    @isTest
    static void immatureExcludedFromHeadlines_thinSampleFlagged() {
        User dir = dir();
        User ae = aeOf(dir.Id);
        Id rt = rtId();
        Account a = new Account(Name = 'Maturity');
        insert a;
        Date today = Date.today();
        Integer q = CockpitConstants.quarterOf(today);
        Date thisQ = CockpitConstants.quarterStart(today.year(), q);
        insert new List<Opportunity>{
            closed(a.Id, ae.Id, rt, 'Old Win', Date.newInstance(2025, 1, 10),
                Date.newInstance(2025, 3, 1), 'Closed Won', null),
            closed(a.Id, ae.Id, rt, 'Old Work', Date.newInstance(2025, 1, 11),
                Date.newInstance(2025, 3, 2), 'Closed Lost', 'Perceived lack of ROI'),
            openDeal(a.Id, ae.Id, rt, 'Fresh', thisQ.addDays(1))
        };

        Test.startTest();
        CockpitCohortService.WinRatePage page = pageFor(dir.Id);
        Test.stopTest();

        CockpitCohortService.CohortRow mature = rowOf(page, '2025Q1');
        CockpitCohortService.CohortRow fresh = rowOf(page, CockpitCohortService.cohortKeyOf(thisQ));
        System.assertEquals(true, mature.mature, '2025 Q1 is past p75');
        System.assertEquals(true, mature.thinSample, 'two deals is under the 15 floor');
        System.assertEquals(false, mature.headline, 'thin mature rows are not headlines');
        System.assertEquals(false, fresh.mature, 'current quarter is immature');
        System.assertEquals(null, page.headlines.contestedWR,
            'thin-only mature vintages do not fill headline rates (null, not 0%)');
    }

    @isTest
    static void purgeDetectors_silentAndDump() {
        User dir = dir();
        User ae = aeOf(dir.Id);
        Id rt = rtId();
        Account a = new Account(Name = 'Purge');
        insert a;
        Date sql = Date.newInstance(2025, 2, 1);
        Date dumpDay = Date.newInstance(2025, 6, 15);
        List<Opportunity> opps = new List<Opportunity>{
            closed(a.Id, ae.Id, rt, 'Silent', sql, Date.today().addDays(-90),
                'Closed Lost', 'Perceived lack of ROI')
        };
        for (Integer i = 0; i < 5; i++) {
            opps.add(closed(a.Id, ae.Id, rt, 'Dump ' + i, sql, dumpDay,
                'Closed Lost', 'Perceived lack of ROI'));
        }
        insert opps;

        Test.startTest();
        CockpitCohortService.WinRatePage page = pageFor(dir.Id);
        Test.stopTest();

        System.assert(page.purgeSilentCount >= 1, 'silent close with no activity is a purge');
        System.assert(page.purgeDumpCount >= 5, 'five same-owner same-CloseDate losses are a dump');
    }

    @isTest
    static void nullRate_notZero() {
        System.assertEquals(null, CockpitCohortService.rate(0, 0),
            'empty denominator is null so the UI can render an em dash');
        System.assertEquals(0.5, CockpitCohortService.rate(1, 2), '1/2 stores at 4 decimals');
    }

    static CockpitCohortService.WinRatePage pageFor(Id directorId) {
        CockpitCohortService.Filter f = new CockpitCohortService.Filter();
        f.directorId = directorId;
        f.teamMode = CockpitConstants.TEAM_MODE_DIRECTOR;
        f.productType = CockpitConstants.PRODUCT_ALL;
        f.sizeBand = CockpitConstants.SIZE_ALL;
        return CockpitCohortService.buildPage(f);
    }

    static CockpitCohortService.CohortRow rowOf(CockpitCohortService.WinRatePage page, String key) {
        for (CockpitCohortService.CohortRow r : page.rows) {
            if (r.cohortKey == key) return r;
        }
        return null;
    }

    static Opportunity base(Id accountId, Id ownerId, Id rt) {
        return new Opportunity(
            AccountId = accountId, OwnerId = ownerId, RecordTypeId = rt,
            Type = 'New Sale', StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );
    }

    static Opportunity closed(Id accountId, Id ownerId, Id rt, String name, Date sql, Date closeDate,
            String stage, String reason) {
        Opportunity o = base(accountId, ownerId, rt);
        o.Name = name;
        o.SQL_Datestamp_bf__c = sql;
        o.CloseDate = closeDate;
        o.StageName = stage;
        o.Lost_Reason__c = reason;
        return o;
    }

    static Opportunity openDeal(Id accountId, Id ownerId, Id rt, String name, Date sql) {
        Opportunity o = base(accountId, ownerId, rt);
        o.Name = name;
        o.SQL_Datestamp_bf__c = sql;
        o.StageName = 'Proposal';
        o.CloseDate = Date.today().addDays(40);
        return o;
    }

    static User dir() {
        return [SELECT Id FROM User WHERE Title = 'Director' AND LastName LIKE 'w%' ORDER BY CreatedDate DESC LIMIT 1];
    }
    static User aeOf(Id dirId) {
        return [SELECT Id FROM User WHERE ManagerId = :dirId AND Title = 'Account Executive' LIMIT 1];
    }
    static Id rtId() {
        return [SELECT Id FROM RecordType WHERE SobjectType = 'Opportunity' AND DeveloperName = 'Euna_Sale' LIMIT 1].Id;
    }

    static Integer seq = 0;
    static User usr(Id mgr, String title) {
        seq++;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String u = 'wrt' + seq + '' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return new User(
            FirstName = 'W', LastName = 'w' + seq, Alias = ('w' + seq).left(8),
            Email = u + '@example.com', Username = u + '@example.com.wrt',
            ProfileId = p.Id, ManagerId = mgr, Title = title,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }
}
