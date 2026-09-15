/**
 * Covers: CockpitAeCompositionService
 */
@isTest
private class CockpitAeCompositionServiceTest {

    static String iso(Date d) {
        return d == null ? null : d.year() + '-' + lp(d.month()) + '-' + lp(d.day());
    }
    static String lp(Integer n) { return n < 10 ? '0' + n : String.valueOf(n); }
    static Opportunity opp(Map<String, Object> m) {
        return (Opportunity) JSON.deserialize(JSON.serialize(m), Opportunity.class);
    }

    static Date today() { return Date.newInstance(2026, 9, 14); }
    static Date qStart() { return Date.newInstance(2026, 7, 1); }
    static Date nextStart() { return Date.newInstance(2026, 10, 1); }
    static Date nextEnd() { return Date.newInstance(2026, 12, 31); }
    static Date winEnd() { return Date.newInstance(2027, 3, 31); }

    static Id fakeOpp(Integer n) {
        return (Id) ('006000000000' + String.valueOf(100 + n).right(3));
    }
    static Id fakeUser(Integer n) {
        return (Id) ('005000000000' + String.valueOf(100 + n).right(3));
    }

    static CockpitRosterService.ScopeResult oneAe(Id userId, String name) {
        CockpitRosterService.ScopeResult s = new CockpitRosterService.ScopeResult();
        s.directorId = userId;
        s.directorName = name;
        s.teamMode = CockpitConstants.TEAM_MODE_MY;
        s.members = new List<CockpitRosterService.Member>{
            new CockpitRosterService.Member(userId, name)
        };
        return s;
    }

    static CockpitAeCompositionService.Payload run(
        CockpitRosterService.ScopeResult scope,
        List<Opportunity> opps,
        Map<Id, CockpitAeCompositionService.Booked> booked
    ) {
        return CockpitAeCompositionService.computeFrom(
            scope, opps, booked, today(), qStart(), nextStart(), nextEnd(), winEnd(),
            CockpitConstants.PRODUCT_ALL, CockpitConstants.SIZE_ALL);
    }

    static Opportunity deal(Id ownerId, Id oppId, String band, Decimal arr, Date closeDate) {
        return dealOn(ownerId, oppId, band, arr, closeDate, today().addDays(-2));
    }
    static Opportunity dealOn(Id ownerId, Id oppId, String band, Decimal arr, Date closeDate, Date lastActivity) {
        return opp(new Map<String, Object>{
            'Id' => (String) oppId,
            'OwnerId' => (String) ownerId,
            'Roll_Up_Forecast_bf__c' => band,
            'ARR_Opportunity_Amount_USD_Num__c' => arr,
            'CloseDate' => iso(closeDate),
            'LastActivityDate' => iso(lastActivity),
            'Is_Holdover__c' => false,
            'StageName' => 'Proposal',
            'SQL_Datestamp_bf__c' => iso(today().addDays(-10)),
            'Next_Step_Date_bf__c' => iso(today().addDays(5))
        });
    }

    @isTest
    static void omitted_isOwnBand_notFoldedIntoPipeline() {
        Id ae = fakeUser(1);
        List<Opportunity> opps = new List<Opportunity>{
            deal(ae, fakeOpp(1), CockpitConstants.BAND_PIPE, 1000, qStart().addDays(5)),
            deal(ae, fakeOpp(2), CockpitConstants.BAND_OMITTED, 400, qStart().addDays(6))
        };
        Test.startTest();
        CockpitAeCompositionService.Payload p = run(oneAe(ae, 'Pat'), opps,
            new Map<Id, CockpitAeCompositionService.Booked>());
        Test.stopTest();

        CockpitAeCompositionService.QuarterSlice q = p.rows[0].currentQ;
        System.assertEquals(1, q.pipeline.deals, 'Pipeline keeps its own deal');
        System.assertEquals(1000, q.pipeline.arr, 'Pipeline ARR is the Pipeline deal only');
        System.assertEquals(1, q.omitted.deals, 'Omitted is its own column');
        System.assertEquals(400, q.omitted.arr, 'Omitted ARR is not folded into Pipeline');
        System.assertEquals(1400, q.openArr, 'band sum + omitted = open ARR');
    }

    @isTest
    static void evidenceCall_bookedPlusWeightedInclude() {
        Id ae = fakeUser(2);
        Opportunity hi = deal(ae, fakeOpp(11), CockpitConstants.BAND_COMMIT, 1000, qStart().addDays(4));
        hi.Cockpit_Class_Override__c = 'HI';
        Opportunity md = deal(ae, fakeOpp(12), CockpitConstants.BAND_ML, 1000, qStart().addDays(5));
        md.Cockpit_Class_Override__c = 'MD';
        Opportunity ex = deal(ae, fakeOpp(13), CockpitConstants.BAND_PIPE, 1000, qStart().addDays(6));
        ex.Cockpit_Class_Override__c = 'EX';

        CockpitAeCompositionService.Booked b = new CockpitAeCompositionService.Booked();
        b.n = 1;
        b.arr = 200;
        Map<Id, CockpitAeCompositionService.Booked> booked =
            new Map<Id, CockpitAeCompositionService.Booked>{ ae => b };

        Test.startTest();
        CockpitAeCompositionService.Payload p = run(oneAe(ae, 'Pat'),
            new List<Opportunity>{ hi, md, ex }, booked);
        Test.stopTest();

        Decimal expected = 200 + (1000 * 85 / 100) + (1000 * 30 / 100);
        System.assertEquals(expected, p.rows[0].currentQ.evidenceCall,
            'evidence call = booked + HI*85% + MD*30%');
        System.assertEquals(true, p.rows[0].currentQ.showBooked, 'current quarter shows Booked');
        System.assertEquals(false, p.rows[0].nextQ.showBooked, 'next quarter has no Booked column');
        System.assertEquals(0, p.rows[0].nextQ.bookedArr, 'next quarter booked stays unused, not a zero column');
    }

    @isTest
    static void futureLastActivity_isQuiet() {
        Id ae = fakeUser(3);
        Opportunity o = dealOn(ae, fakeOpp(21), CockpitConstants.BAND_PIPE, 5000, qStart().addDays(8), today().addDays(21));
        o.Cockpit_Class_Override__c = 'EX';

        Test.startTest();
        System.assertEquals(true, CockpitAeCompositionService.isSilent(o, today()),
            'future LastActivityDate is quiet, not fresh');
        CockpitAeCompositionService.Payload p = run(oneAe(ae, 'Pat'),
            new List<Opportunity>{ o }, new Map<Id, CockpitAeCompositionService.Booked>());
        Test.stopTest();

        Boolean silent = false;
        for (CockpitAeCompositionService.Signal s : p.rows[0].signals) {
            if (s.code == 'SILENT') silent = true;
        }
        System.assert(silent, 'silent-book signal fires for a future-dated activity');
    }

    @isTest
    static void concentration_firesAbove40_notAt40() {
        Id ae = fakeUser(4);
        List<Opportunity> at40 = new List<Opportunity>{
            deal(ae, fakeOpp(31), CockpitConstants.BAND_PIPE, 40, qStart().addDays(2)),
            deal(ae, fakeOpp(32), CockpitConstants.BAND_PIPE, 30, qStart().addDays(3)),
            deal(ae, fakeOpp(35), CockpitConstants.BAND_PIPE, 30, qStart().addDays(4))
        };
        at40[0].Cockpit_Class_Override__c = 'EX';
        at40[1].Cockpit_Class_Override__c = 'EX';
        at40[2].Cockpit_Class_Override__c = 'EX';

        List<Opportunity> over40 = new List<Opportunity>{
            deal(ae, fakeOpp(33), CockpitConstants.BAND_PIPE, 41, qStart().addDays(2)),
            deal(ae, fakeOpp(34), CockpitConstants.BAND_PIPE, 30, qStart().addDays(3)),
            deal(ae, fakeOpp(36), CockpitConstants.BAND_PIPE, 29, qStart().addDays(4))
        };
        over40[0].Cockpit_Class_Override__c = 'EX';
        over40[1].Cockpit_Class_Override__c = 'EX';
        over40[2].Cockpit_Class_Override__c = 'EX';

        Test.startTest();
        List<CockpitAeCompositionService.Signal> eq =
            CockpitAeCompositionService.signalsFor(at40, at40, today());
        List<CockpitAeCompositionService.Signal> gt =
            CockpitAeCompositionService.signalsFor(over40, over40, today());
        Test.stopTest();

        System.assertEquals(false, hasCode(eq, 'CONCENTRATION'), '40% exactly does not fire');
        System.assertEquals(true, hasCode(gt, 'CONCENTRATION'), '>40% fires');
    }

    @isTest
    static void meddpicc_requiresFourScoredDeals() {
        Id ae = fakeUser(5);
        List<Opportunity> three = new List<Opportunity>();
        for (Integer i = 0; i < 3; i++) {
            Opportunity o = deal(ae, fakeOpp(40 + i), CockpitConstants.BAND_PIPE, 10, qStart().addDays(i + 1));
            o.Cockpit_Class_Override__c = 'EX';
            three.add(o);
            CockpitAeCompositionService.testMeddpiccByOpp.put(o.Id, 1);
        }
        List<Opportunity> four = new List<Opportunity>(three);
        Opportunity fourth = deal(ae, fakeOpp(49), CockpitConstants.BAND_PIPE, 10, qStart().addDays(8));
        fourth.Cockpit_Class_Override__c = 'EX';
        four.add(fourth);
        CockpitAeCompositionService.testMeddpiccByOpp.put(fourth.Id, 1);

        Test.startTest();
        List<CockpitAeCompositionService.Signal> under =
            CockpitAeCompositionService.signalsFor(three, three, today());
        List<CockpitAeCompositionService.Signal> enough =
            CockpitAeCompositionService.signalsFor(four, four, today());
        Test.stopTest();

        System.assertEquals(false, hasCode(under, 'MEDDPICC'), 'floor of 4 scored deals — 3 does not fire');
        System.assertEquals(true, hasCode(enough, 'MEDDPICC'), '4 scored deals below 3/8 fires');
    }

    @isTest
    static void override_winsOverLiveScore() {
        Id ae = fakeUser(6);
        Opportunity o = deal(ae, fakeOpp(51), CockpitConstants.BAND_COMMIT, 80000, qStart().addDays(4));
        o.Cockpit_Class_Override__c = 'EX';
        o.StageName = 'Verbal Win';
        o.Pricing_Approval_Status__c = 'Approved';

        Test.startTest();
        String cls = CockpitAeCompositionService.effectiveClass(o, today());
        CockpitAeCompositionService.Payload p = run(oneAe(ae, 'Pat'),
            new List<Opportunity>{ o }, new Map<Id, CockpitAeCompositionService.Booked>());
        Test.stopTest();

        System.assertEquals('EX', cls, 'override wins over a live score that would be Include-High');
        System.assertEquals(1, p.rows[0].currentQ.excludeN, 'overridden deal lands in Exclude');
        System.assertEquals(0, p.rows[0].currentQ.includeHighN, 'live HI score is not used');
    }

    @isTest
    static void cleanBook_emptyListNotNull() {
        Id ae = fakeUser(7);
        Opportunity commitDeal = deal(ae, fakeOpp(61), CockpitConstants.BAND_COMMIT, 40, qStart().addDays(4));
        commitDeal.Cockpit_Class_Override__c = 'HI';
        Opportunity ml = deal(ae, fakeOpp(62), CockpitConstants.BAND_ML, 30, qStart().addDays(5));
        ml.Cockpit_Class_Override__c = 'MD';
        Opportunity pipe = deal(ae, fakeOpp(63), CockpitConstants.BAND_PIPE, 30, qStart().addDays(6));
        pipe.Cockpit_Class_Override__c = 'EX';

        Test.startTest();
        CockpitAeCompositionService.Payload p = run(oneAe(ae, 'Pat'),
            new List<Opportunity>{ commitDeal, ml, pipe }, new Map<Id, CockpitAeCompositionService.Booked>());
        Test.stopTest();

        System.assertNotEquals(null, p.rows[0].signals, 'clean book is an empty list, never null');
        System.assertEquals(0, p.rows[0].signals.size(), 'nothing cleared the evidence bar');
        System.assertEquals('Nothing cleared the evidence bar.', p.rows[0].cleanBook,
            'explicit clean-book sentence, never an empty cell');
    }

    @isTest
    static void nullClass_emptyState_notSilentExclude() {
        Id ae = fakeUser(8);
        Opportunity o = deal(ae, fakeOpp(71), CockpitConstants.BAND_PIPE, 1000, qStart().addDays(4));
        CockpitAeCompositionService.liveScoreIfClassMissing = false;

        Test.startTest();
        CockpitAeCompositionService.Payload p = run(oneAe(ae, 'Pat'),
            new List<Opportunity>{ o }, new Map<Id, CockpitAeCompositionService.Booked>());
        Test.stopTest();

        CockpitAeCompositionService.liveScoreIfClassMissing = true;
        System.assertEquals(true, p.classMissing, 'null class is an explicit empty state');
        System.assert(p.emptyReason.contains('null class'), 'reason names the missing class');
        System.assertEquals(0, p.rows.size(), 'do not render Exclude-as-default rows');
    }

    @isTest
    static void sizeBand_under50k() {
        System.assertEquals(true,
            CockpitAeCompositionService.matchesSize(49999, CockpitConstants.SIZE_UNDER_50K));
        System.assertEquals(false,
            CockpitAeCompositionService.matchesSize(50000, CockpitConstants.SIZE_UNDER_50K));
        System.assertEquals(true,
            CockpitAeCompositionService.matchesSize(50000, CockpitConstants.SIZE_50_150K));
        System.assertEquals(true,
            CockpitAeCompositionService.matchesSize(150000, CockpitConstants.SIZE_OVER_150K));
    }

    static Boolean hasCode(List<CockpitAeCompositionService.Signal> signals, String code) {
        for (CockpitAeCompositionService.Signal s : signals) {
            if (s.code == code) return true;
        }
        return false;
    }
}
