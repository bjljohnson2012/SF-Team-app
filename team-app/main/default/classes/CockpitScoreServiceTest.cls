/**
 * Covers: CockpitScoreService, CockpitConstants
 * Read-only fields (ARR formula, LastActivityDate) are injected via JSON, the
 * standard way to populate non-writeable fields for an in-memory unit test.
 */
@isTest
private class CockpitScoreServiceTest {

    static String iso(Date d) {
        return d == null ? null : d.year() + '-' + lp(d.month()) + '-' + lp(d.day());
    }
    static String lp(Integer n) { return n < 10 ? '0' + n : '' + n; }
    static Opportunity opp(Map<String, Object> m) {
        return (Opportunity) JSON.deserialize(JSON.serialize(m), Opportunity.class);
    }

    @isTest
    static void highScore_classifiesHI() {
        Opportunity o = opp(new Map<String, Object>{
            'StageName' => 'Verbal Win',                            // +3
            'Pricing_Approval_Status__c' => 'Approved',             // +2
            'SQL_Datestamp_bf__c' => iso(Date.today().addDays(-5)), // +1
            'LastActivityDate' => iso(Date.today().addDays(-3)),    // active +1
            'Next_Step_Date_bf__c' => iso(Date.today().addDays(5)), // no penalty
            'ARR_Opportunity_Amount_USD_Num__c' => 100000
        });
        CockpitScoreService.Result r = CockpitScoreService.score(o, null, 0, Date.today());
        System.assertEquals(7, r.score, 'Verbal Win + Approved + SQL + active = 7');
        System.assertEquals('HI', r.klass, 'score 7 is Include-High');
    }

    @isTest
    static void zeroArr_classifiesEX() {
        Opportunity o = opp(new Map<String, Object>{
            'StageName' => 'Proposal',
            'SQL_Datestamp_bf__c' => iso(Date.today()),
            'ARR_Opportunity_Amount_USD_Num__c' => 0
        });
        CockpitScoreService.Result r = CockpitScoreService.score(o, null, 0, Date.today());
        System.assertEquals('EX', r.klass, 'zero ARR is always Exclude');
        System.assert(r.reason.contains('zero ARR'), 'reason names the zero ARR');
    }

    @isTest
    static void futureActivity_isNoEvidence() {
        Opportunity o = opp(new Map<String, Object>{
            'StageName' => 'Discovery',                             // -1
            'LastActivityDate' => iso(Date.today().addDays(30)),    // future -> no activity -2
            'ARR_Opportunity_Amount_USD_Num__c' => 5000
        });
        CockpitScoreService.Result r = CockpitScoreService.score(o, null, 8, Date.today()); // 8 pushes -2
        System.assert(r.score < 0, 'penalties stack negative');
        System.assertEquals('EX', r.klass);
        System.assert(r.reason.contains('no activity ever'), 'future date treated as no evidence');
    }

    @isTest
    static void meddpicc_and_medClass() {
        Opportunity o = opp(new Map<String, Object>{
            'StageName' => 'Proposal',                              // +2
            'SQL_Datestamp_bf__c' => iso(Date.today()),             // +1
            'LastActivityDate' => iso(Date.today().addDays(-10)),   // +1
            'Next_Step_Date_bf__c' => iso(Date.today().addDays(3)), // no penalty
            'ARR_Opportunity_Amount_USD_Num__c' => 20000
        });
        CockpitScoreService.Result r = CockpitScoreService.score(o, 3, 3, Date.today()); // MEDD +1, 3 pushes -1
        System.assertEquals('MD', r.klass, 'score 4 is Include-Med');
        System.assert(r.reason.contains('MEDDPICC 3/8'), 'MEDDPICC contributes when provided');
    }

    @isTest
    static void quarterMath() {
        System.assertEquals(1, CockpitConstants.quarterOf(Date.newInstance(2026, 2, 15)));
        System.assertEquals(3, CockpitConstants.quarterOf(Date.newInstance(2026, 9, 10)));
        System.assertEquals(Date.newInstance(2026, 7, 1), CockpitConstants.quarterStart(2026, 3));
        System.assertEquals(Date.newInstance(2026, 9, 30), CockpitConstants.quarterEnd(2026, 3));
    }
}
