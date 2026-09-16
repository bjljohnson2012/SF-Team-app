/**
 * Covers: WaterfallRateEngine
 * Asserts the gated win-rate denominator, zero-ARR ASP exclusion, and persist.
 */
@isTest
private class WaterfallRateEngineTest {

    @isTest
    static void tapClosed_gatesWinRate_andDropsZeroArrFromAsp() {
        Date sql = Date.today().addDays(-40);
        Test.startTest();
        WaterfallRateEngine.RateRow row = WaterfallRateEngine.applyClosedForTest(
            new List<Boolean>{ true, true, false, false, false },
            new List<Decimal>{ 20000, 0, 15000, 15000, 15000 },
            new List<Date>{ sql, sql, sql, sql, null },
            new List<Decimal>{ 40, 40, 40, 40, null },
            new List<String>{
                null, null, 'Strength of Competitor Relationship',
                'Ghosted', 'Product Related Reasons'
            }
        );
        Test.stopTest();

        System.assertEquals(3, row.closedCount, 'gated set is 2 wins + 1 competitive loss; Ghosted and ungated are out');
        System.assertEquals(2, row.wins, 'zero-ARR win still counts in the win rate');
        System.assertEquals(1, row.arrBearingWins, 'zero-ARR win is out of the ASP denominator');
        System.assertEquals(20000, row.arrWon, 'ASP numerator is the one ARR-bearing win');
        System.assertEquals(20000, row.aspRaw, 'ASP is not cut by the $0 win');
        System.assertEquals((2.0 / 3).setScale(4), row.winRateRaw.setScale(4), 'gated win rate is 2/3');
        System.assert(row.ungatedClosed > row.closedCount, 'ungated closed is stored and larger');
    }

    @isTest
    static void calibrate_readsOwnerBook_withoutWonQuote() {
        User dir = usr(null, 'Director');
        insert dir;
        User ae = usr(dir.Id, 'Account Executive');
        insert ae;
        Account acc = new Account(Name = 'WF Rate Acc');
        insert acc;
        Id rt = eunaSaleRtId();
        insert new Opportunity(
            Name = 'WF Open SQL',
            AccountId = acc.Id,
            OwnerId = ae.Id,
            RecordTypeId = rt,
            Type = 'New Sale',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(20),
            EUNA_Solution__c = 'Budget Professional',
            Y1_ARR_Offered_Price__c = 12000,
            SQL_Datestamp_bf__c = Date.today().addDays(-15)
        );

        Test.startTest();
        WaterfallRateEngine.RateSet rates = WaterfallRateEngine.calibrate(
            new Set<Id>{ ae.Id }, CockpitConstants.PRODUCT_GROUP_BUDGET,
            CockpitConstants.SIZE_ALL, Date.today());
        Test.stopTest();

        System.assert(rates.byOwner.containsKey(ae.Id), 'calibrate returns a row for the scoped AE');
        System.assertEquals(0, rates.byOwner.get(ae.Id).closedCount, 'open Proposal is not a gated close');
    }

    @isTest
    static void persist_upsertsExternalId() {
        User dir = usr(null, 'Director');
        insert dir;
        User ae = usr(dir.Id, 'Account Executive');
        insert ae;
        WaterfallRateEngine.RateSet rates = new WaterfallRateEngine.RateSet();
        rates.windowStart = Date.newInstance(2024, 10, 1);
        rates.windowEnd = Date.newInstance(2026, 9, 30);
        WaterfallRateEngine.RateRow row = new WaterfallRateEngine.RateRow();
        row.ownerId = ae.Id;
        row.closedCount = 8;
        row.wins = 3;
        row.arrBearingWins = 3;
        row.arrWon = 54000;
        row.winRateRaw = 0.375;
        row.winRateBlended = 0.378;
        row.aspRaw = 18000;
        row.aspBlended = 18500;
        row.sampleConfidence = 'Low';
        rates.byOwner.put(ae.Id, row);

        Test.startTest();
        List<Waterfall_Rate__c> first = WaterfallRateEngine.persist(rates);
        List<Waterfall_Rate__c> second = WaterfallRateEngine.persist(rates);
        Test.stopTest();

        System.assertEquals(1, first.size(), 'one rate row per AE');
        System.assertEquals(1, [SELECT COUNT() FROM Waterfall_Rate__c WHERE AE__c = :ae.Id],
            'second persist upserts, it does not duplicate');
        System.assertEquals(first[0].Id, second[0].Id, 'upsert key is External_Id__c');
    }

    static Id eunaSaleRtId() {
        return [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Opportunity' AND DeveloperName = 'Euna_Sale' LIMIT 1
        ].Id;
    }

    static Integer seq = 0;
    static User usr(Id mgr, String title) {
        seq++;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String u = 'wfrt' + seq + String.valueOf(System.currentTimeMillis());
        return new User(
            FirstName = 'W', LastName = 'r' + seq, Alias = ('wr' + seq).left(8),
            Email = u + '@example.com', Username = u + '@example.com.wfrt',
            ProfileId = p.Id, ManagerId = mgr, Title = title,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }
}
