/**
 * Covers: CockpitConversionService
 * Behavioural floors: interpret gap, commit dash vs flag, over-index
 * conjunction, live-book sample floors, null band → Unbanded.
 */
@isTest
private class CockpitConversionServiceTest {

    @isTest
    static void interpret_countDollarGap_overEightPoints_saysLargeDealsLose() {
        CockpitConversionService.BandRow b = new CockpitConversionService.BandRow();
        b.band = 'Best Case';
        b.won = 51;
        b.lost = 336;
        b.total = 387;
        b.arrWon = 528619;
        b.arrLost = 9800000;
        b.arrTotal = 10328619;
        b.winRateCount = 0.132;
        b.winRateArr = 0.051;
        b.rateGap = 0.081;
        b.largeDealsLose = true;

        Test.startTest();
        String text = CockpitConversionService.interpret(new List<CockpitConversionService.BandRow>{ b });
        Test.stopTest();

        System.assertNotEquals(null, text, 'gap over 8 points must speak');
        System.assert(text.contains('large deals lose'), 'wording names the pattern');
        System.assert(text.contains('Best Case'), 'names the band');
        System.assertEquals(null, CockpitConversionService.interpret(new List<CockpitConversionService.BandRow>()),
            'empty list has no caption');
    }

    @isTest
    static void commitAccuracy_belowFourCloses_returnsNullNotZero() {
        Test.startTest();
        Decimal thin = CockpitConversionService.commitAccuracy(0, 3);
        Decimal none = CockpitConversionService.commitAccuracy(0, 0);
        Test.stopTest();

        System.assertEquals(null, thin, 'under 4 Commit closes is a dash, never 0%');
        System.assertEquals(null, none, 'zero sample is a dash, never 0%');
    }

    @isTest
    static void commitAccuracy_below80WithFourPlus_isComputed() {
        Test.startTest();
        Decimal rate = CockpitConversionService.commitAccuracy(3, 4);
        Decimal ok = CockpitConversionService.commitAccuracy(4, 4);
        Test.stopTest();

        System.assertEquals(0.7500, rate, '3/4 is 75%');
        System.assert(rate < CockpitConversionService.COMMIT_FLAG_RATE, '75% is below the 80% flag');
        System.assertEquals(1.0000, ok, '4/4 is 100%');
    }

    @isTest
    static void isOverIndexed_requiresAllThreeConditions() {
        Test.startTest();
        Boolean allThree = CockpitConversionService.isOverIndexed(5, 20, 0.10);
        Boolean thinCount = CockpitConversionService.isOverIndexed(3, 20, 0.10);
        Boolean lowShare = CockpitConversionService.isOverIndexed(5, 40, 0.10);
        Boolean noLift = CockpitConversionService.isOverIndexed(5, 20, 0.30);
        Test.stopTest();

        System.assertEquals(true, allThree, '5 losses, 25% of book, 2.5x team → over-indexed');
        System.assertEquals(false, thinCount, 'under 4 losses is not over-indexed');
        System.assertEquals(false, lowShare, '12.5% of AE losses is under the 18% share floor');
        System.assertEquals(false, noLift, 'equal-or-lower vs team share is not a lift');
    }

    @isTest
    static void liveFlags_onlyWhenSampleFloorMet() {
        CockpitConversionService.LiveRow thin = new CockpitConversionService.LiveRow();
        thin.dealCount = 5;
        thin.scoredCount = 5;
        thin.shareBelow3 = 0.80;
        thin.silentShare = 0.80;
        thin.nextStepShare = 0.80;
        thin.pushedShare = 0.80;
        thin.openArr = 50000;
        thin.aboveBestCaseShare = 0.01;

        CockpitConversionService.LiveRow hot = new CockpitConversionService.LiveRow();
        hot.dealCount = 10;
        hot.scoredCount = 8;
        hot.shareBelow3 = 0.70;
        hot.silentShare = 0.40;
        hot.nextStepShare = 0.50;
        hot.pushedShare = 0.35;
        hot.openArr = 250000;
        hot.aboveBestCaseShare = 0.02;

        Test.startTest();
        List<String> thinFlags = CockpitConversionService.liveFlags(thin);
        List<String> hotFlags = CockpitConversionService.liveFlags(hot);
        Test.stopTest();

        System.assertEquals(0, thinFlags.size(), 'flags stay off when sample floors are missed');
        System.assert(hotFlags.contains('Weak MEDDPICC'), 'MEDDPICC flags at >=60% with 6+ scored');
        System.assert(hotFlags.contains('Silent 30d+'), 'silence flags at >=35% with 8+ open');
        System.assert(hotFlags.contains('Next step lapsed/missing'), 'next-step flags at >=40% with 8+ open');
        System.assert(hotFlags.contains('Pushed 3+'), 'push flags at >=30% with 8+ open');
        System.assert(hotFlags.contains('Banded above Best Case'), 'under-banding flags below 5% with $200k open');
    }

    @isTest
    static void bandConversion_nullBandIsUnbanded_andLoadSums() {
        User dir = setupDirectorWithRep();
        User rep = [SELECT Id FROM User WHERE ManagerId = :dir.Id LIMIT 1];
        Id rtId = eunaSaleRtId();

        System.runAs(dir) {
            Account a = new Account(Name = 'Conv Acme');
            insert a;
            List<Opportunity> opps = new List<Opportunity>{
                closedDeal(a.Id, rep.Id, rtId, 'Closed Lost', 'Commit', 'Budget Professional', 40000, Date.today().addDays(-10), 'Ghosted'),
                closedDeal(a.Id, rep.Id, rtId, 'Closed Lost', 'Best Case', 'Budget Professional', 180000, Date.today().addDays(-12), 'Ghosted'),
                closedDeal(a.Id, rep.Id, rtId, 'Closed Lost', null, 'Budget Professional', 20000, Date.today().addDays(-8), 'Perceived lack of ROI'),
                openDeal(a.Id, rep.Id, rtId, 'Budget Professional', 60000)
            };
            insert opps;

            Test.startTest();
            CockpitConversionService.PagePayload page = CockpitConversionService.load(
                dir.Id, CockpitConversionService.TEAM_DIRECTOR, null, CockpitConversionService.SIZE_ALL);
            Test.stopTest();

            System.assertEquals(false, page.scope.emptyScope, 'director with an AE is a valid scope');
            System.assert(page.closedInWindow >= 3, 'closed rows in window are counted');
            Boolean sawUnbanded = false;
            Integer bandSum = 0;
            for (CockpitConversionService.BandRow b : page.bands) {
                bandSum += b.total;
                if (b.band == CockpitConversionService.UNBANDED) {
                    sawUnbanded = true;
                    System.assert(b.lost >= 1, 'null band is kept as Unbanded, not dropped');
                }
            }
            System.assertEquals(true, sawUnbanded, 'null Forecast_Category_before_Close__c → Unbanded');
            System.assertEquals(page.closedInWindow, bandSum, 'sum of bands equals closed in window');
            System.assertNotEquals(null, page.conventionCaption, 'page says it is closure-based');
            System.assertNotEquals(null, page.liveBook, 'live book is computed');
            System.assert(!page.lossMatrix.isEmpty(), 'loss matrix includes floored closed-lost reasons');
            CockpitConversionService.PagePayload sized = CockpitConversionService.load(
                dir.Id, CockpitConversionService.TEAM_DIRECTOR, 'Budget Professional',
                CockpitConversionService.SIZE_UNDER_50);
            System.assertNotEquals(null, sized.scope.caption, 'product + size filters produce a caption');
        }
    }

    @isTest
    static void emptyScope_explainsNoAes_doesNotThrow() {
        User lone = usr(null, 'Solutions Engineer');
        insert lone;
        System.runAs(lone) {
            Test.startTest();
            CockpitConversionService.PagePayload page = CockpitConversionService.load(
                lone.Id, CockpitConversionService.TEAM_MINE, null, CockpitConversionService.SIZE_ALL);
            Test.stopTest();
            System.assertEquals(true, page.scope.emptyScope, 'director with no AEs is an empty scope');
            System.assertNotEquals(null, page.scope.emptyMessage, 'empty state is explained');
            System.assert(page.scope.emptyMessage.contains('account executives'),
                'message talks about AEs, not a raw director-only error');
        }
    }

    @isTest
    static void medianCycle_returnsMiddleValue() {
        Test.startTest();
        Integer mid = CockpitConversionService.medianCycle(new List<Integer>{ 10, 40, 20 });
        Integer empty = CockpitConversionService.medianCycle(new List<Integer>());
        Test.stopTest();
        System.assertEquals(20, mid, 'sorted median of 10/20/40 is 20');
        System.assertEquals(null, empty, 'empty cycle list is null');
    }

    @isTest
    static void normalizeBand_andRootOf_blankPaths() {
        System.assertEquals('Unbanded', CockpitConversionService.normalizeBand(null), 'null band');
        System.assertEquals('Unbanded', CockpitConversionService.normalizeBand(''), 'blank band');
        System.assertEquals('Commit', CockpitConversionService.normalizeBand('Commit'), 'named band kept');
        System.assertEquals('UNMAPPED', CockpitConversionService.rootOf(null), 'blank reason is unmapped');
        System.assertEquals('ENGAGE', CockpitConversionService.rootOf('Ghosted'), 'Ghosted maps to ENGAGE');
        System.assertEquals('UNMAPPED', CockpitConversionService.rootOf('Brand new reason'), 'unknown stays unmapped');
    }

    static User setupDirectorWithRep() {
        User dir = usr(null, 'Director');
        insert dir;
        User rep = usr(dir.Id, 'Account Executive');
        insert rep;
        return dir;
    }

    static Id eunaSaleRtId() {
        return [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Opportunity' AND DeveloperName = 'Euna_Sale' LIMIT 1
        ].Id;
    }

    static Opportunity openDeal(Id accountId, Id ownerId, Id rtId, String solution, Decimal arr) {
        return new Opportunity(
            Name = 'Open Conv',
            AccountId = accountId,
            OwnerId = ownerId,
            RecordTypeId = rtId,
            Type = 'New Sale',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(20),
            EUNA_Solution__c = solution,
            Y1_ARR_Offered_Price__c = arr,
            SQL_Datestamp_bf__c = Date.today().addDays(-15)
        );
    }

    static Opportunity closedDeal(
        Id accountId, Id ownerId, Id rtId, String stage, String band,
        String solution, Decimal arr, Date closeDate, String lostReason
    ) {
        return new Opportunity(
            Name = 'Conv ' + String.valueOf(closeDate),
            AccountId = accountId,
            OwnerId = ownerId,
            RecordTypeId = rtId,
            Type = 'New Sale',
            StageName = stage,
            CloseDate = closeDate,
            Forecast_Category_before_Close__c = band,
            EUNA_Solution__c = solution,
            Y1_ARR_Offered_Price__c = arr,
            Lost_Reason__c = lostReason,
            SQL_Datestamp_bf__c = closeDate.addDays(-40)
        );
    }

    static Integer seq = 0;
    static User usr(Id mgr, String title) {
        seq++;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String u = 'cvcn' + seq + String.valueOf(System.currentTimeMillis());
        return new User(
            FirstName = 'T', LastName = 'v' + seq, Alias = ('v' + seq).left(8),
            Email = u + '@example.com', Username = u + '@example.com.cvcn',
            ProfileId = p.Id, ManagerId = mgr, Title = title,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }
}
