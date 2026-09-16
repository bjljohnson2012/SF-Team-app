/**
 * Asserts QO-versus-everything, cadence, what-if edits, and target upserts.
 */
@isTest
private class WaterfallPlayPlannerTest {

    static final Date ASOF = Date.newInstance(2026, 9, 16);

    @isTest
    static void recommended_matchesCreateCascade_andSplitsQoFromEverything() {
        WaterfallPlayPlanner.PlayDraft rec = WaterfallPlayPlanner.recommended(
            150000, stephenRate(), stephenActual(), ASOF);

        System.assertEquals(5.6, rec.winsNeeded.setScale(1), '150k / 26819 is 5.6 wins');
        System.assert(rec.qoNeeded >= 18.4 && rec.qoNeeded < 18.6,
            'qualified opps needed is ~18.4');
        System.assert(rec.oppsToCreate >= 24.2 && rec.oppsToCreate < 24.5,
            'everything to create is ~24.3 — larger than QO because qual is 76%');
        System.assert(rec.qoNeeded < rec.oppsToCreate,
            'qualified need is not the same as everything to create');
        System.assert(rec.selfSourced >= 3.1 && rec.selfSourced < 3.3, 'self-sourced lane ~3.2');
        System.assertEquals(17, rec.dialsNeeded.setScale(0), 'self / opp-per-connect / connect rate is 17 dials');
        System.assertEquals(11, rec.remainingWorkingDays,
            'Wed 16 Sep through Wed 30 Sep 2026 is 11 working days');
        System.assert(rec.dialsPerDay > 1.5 && rec.dialsPerDay < 1.6,
            '17 dials over 11 remaining days is ~1.55/day');
        System.assert(rec.dialsPerWeek > 7.5 && rec.dialsPerWeek < 8.0,
            'daily pace × 5 is ~7.7 dials/week');
        System.assertEquals(5, rec.normalDialsPerWeek.setScale(0),
            '55 dispositioned dials over 55 elapsed weekdays is 5/week');
        System.assert(rec.weeklyPaceGap > 2 && rec.weeklyPaceGap < 3,
            'recommended weekly pace is a few dials above their normal');
        System.assertEquals(0.20, rec.normalConnectRate, 'normal connect rate is their actual');
    }

    @isTest
    static void project_fromDials_scalesOutcomesLinearly() {
        WaterfallPlayPlanner.PlayDraft base = WaterfallPlayPlanner.recommended(
            150000, stephenRate(), stephenActual(), ASOF);
        Decimal origWins = base.winsNeeded;
        Decimal origArr = base.projectedArr;
        base.dialsNeeded = base.dialsNeeded * 2;

        WaterfallPlayPlanner.PlayDraft out;
        Test.startTest();
        out = WaterfallPlayPlanner.project(base, 'dials', ASOF);
        Test.stopTest();

        System.assertEquals((origWins * 2).setScale(6), out.winsNeeded.setScale(6),
            'twice the dials at the same rates is twice the wins');
        System.assertEquals((origArr * 2).setScale(2), out.projectedArr.setScale(2),
            'ARR outcome scales with the edited dial volume');
        System.assert(out.qoNeeded > base.qoNeeded, 'more dials raise qualified need coverage');
        System.assert(out.oppsToCreate > out.qoNeeded, 'everything stays above qualified');
    }

    @isTest
    static void project_fromQoNeeded_backsOutDials() {
        WaterfallPlayPlanner.PlayDraft rec = WaterfallPlayPlanner.recommended(
            150000, stephenRate(), stephenActual(), ASOF);
        rec.qoNeeded = 10;

        Test.startTest();
        WaterfallPlayPlanner.PlayDraft out = WaterfallPlayPlanner.project(rec, 'qoNeeded', ASOF);
        Test.stopTest();

        System.assert(out.dialsNeeded < rec.dialsNeeded,
            'cutting qualified need cuts the dials required');
        System.assert(out.oppsToCreate > out.qoNeeded,
            'everything is still QO ÷ qual rate');
        System.assertEquals((10 * 0.303 * 26819).setScale(0), out.projectedArr.setScale(0),
            'wins × ASP is the outcome of the edited QO');
    }

    @isTest
    static void previewAndSave_persistRecommendedNumbers() {
        User ae = usr(null, 'Account Executive');
        insert ae;
        WaterfallPlayPlanner.PlayDraft planned = WaterfallPlayPlanner.recommended(
            150000, stephenRate(), stephenActual(), ASOF);
        planned.dialsNeeded = 40;
        planned = WaterfallPlayPlanner.project(planned, 'dials', ASOF);

        Test.startTest();
        WaterfallPlayPlanner.PlayDraft preview = WaterfallController.previewPlays(planned, 'dials');
        WaterfallController.savePlays(ae.Id, CockpitConstants.PRODUCT_ALL, 'Coach asked for a higher dial floor', planned);
        Map<Id, WaterfallPlayPlanner.PlayDraft> loaded = WaterfallPlayPlanner.loadSaved(
            new Set<Id>{ ae.Id }, CockpitConstants.PRODUCT_ALL, WaterfallConstants.periodStart(Date.today()));
        Test.stopTest();

        System.assertEquals(40, preview.dialsNeeded.setScale(0), 'preview keeps the edited dial number');
        System.assertEquals(1, loaded.size(), 'save upserts one AE draft');
        System.assertEquals(40, loaded.get(ae.Id).dialsNeeded.setScale(0), 'saved Dials metric comes back');
        System.assertEquals(9, [
            SELECT COUNT() FROM Waterfall_Target__c WHERE AE__c = :ae.Id
        ], 'nine recommended numbers are stored');
    }

    @isTest
    static void save_blankReason_isRejected() {
        User ae = usr(null, 'Account Executive');
        insert ae;
        WaterfallPlayPlanner.PlayDraft planned = WaterfallPlayPlanner.recommended(
            150000, stephenRate(), stephenActual(), ASOF);
        Boolean threw = false;
        try {
            WaterfallPlayPlanner.save(ae.Id, 'ALL', '  ', planned);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'blank reason is not auditable');
    }

    static WaterfallRateEngine.RateRow stephenRate() {
        WaterfallRateEngine.RateRow rate = new WaterfallRateEngine.RateRow();
        rate.aspBlended = 26819;
        rate.winRateBlended = 0.303;
        rate.qualRate = 0.76;
        rate.selfSourcedShare = 0.13;
        return rate;
    }

    static WaterfallActualEngine.ActualRow stephenActual() {
        WaterfallActualEngine.ActualRow actual = new WaterfallActualEngine.ActualRow();
        actual.connectRate = 0.20;
        actual.oppsPerConnect = 0.94;
        actual.dials = 55;
        actual.connects = 11;
        actual.created = 4;
        actual.openQualified = 8;
        actual.activityComplete = 0.82;
        return actual;
    }

    static Integer seq = 0;
    static User usr(Id mgr, String title) {
        seq++;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String u = 'wfpl' + seq + String.valueOf(System.currentTimeMillis());
        return new User(
            FirstName = 'P', LastName = 'l' + seq, Alias = ('pl' + seq).left(8),
            Email = u + '@example.com', Username = u + '@example.com.wfpl',
            ProfileId = p.Id, ManagerId = mgr, Title = title,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }
}
