/**
 * Covers: WaterfallController, WaterfallCalibrationSchedulable
 * Asserts both plans, the self-sourced clamp, and empty-scope copy.
 */
@isTest
private class WaterfallControllerTest {

    @isTest
    static void buildPlan_closeAndCreate_useTheCascade() {
        WaterfallRateEngine.RateRow rate = new WaterfallRateEngine.RateRow();
        rate.aspBlended = 26819;
        rate.winRateBlended = 0.303;
        rate.qualRate = 0.76;
        rate.selfSourcedShare = 0.13;
        WaterfallActualEngine.ActualRow actual = new WaterfallActualEngine.ActualRow();
        actual.connectRate = 0.20;
        actual.oppsPerConnect = 0.94;

        Test.startTest();
        WaterfallController.Plan closeP = WaterfallController.buildPlan(
            'close', 'Q3 2026', 'Deal execution. Not activity.', 150000, rate, actual);
        WaterfallController.Plan createP = WaterfallController.buildPlan(
            'create', 'Q1 2027', 'Activity and channel capacity.', 150000, rate, actual);
        Test.stopTest();

        System.assertEquals(5.6, closeP.winsNeeded.setScale(1), '150k / 26819 is 5.6 wins');
        System.assert(closeP.qoNeeded >= 18.4 && closeP.qoNeeded < 18.6,
            'qualified opps needed is ~18.4 on Stephen\'s cascade');
        System.assertEquals(3, closeP.rungs.size(), 'close plan stops at qualified opps — activity is the other clock');
        System.assert(createP.oppsToCreate >= 24.2 && createP.oppsToCreate < 24.5,
            'opps to create is ~24.3');
        System.assert(createP.selfSourced >= 3.1 && createP.selfSourced < 3.3,
            'self-sourced lane is ~3.2');
        System.assertEquals(17, createP.dialsNeeded.setScale(0), 'self-sourced / opp-per-connect / connect rate is 17 dials');
        System.assertEquals(6, createP.rungs.size(), 'create plan walks the full cascade');
        System.assert(createP.rungs[5].op.contains('0.94'),
            'opp per connect is a ratio, not a percent');
        System.assert(!createP.rungs[5].op.contains('94.0%'),
            '0.94 opp/connect must not render as 94%');
    }

    @isTest
    static void buildPlan_clampsSelfSourcedShareAtOne() {
        WaterfallRateEngine.RateRow rate = new WaterfallRateEngine.RateRow();
        rate.aspBlended = 10000;
        rate.winRateBlended = 0.50;
        rate.qualRate = 1;
        rate.selfSourcedShare = 1.80;
        WaterfallActualEngine.ActualRow actual = new WaterfallActualEngine.ActualRow();
        actual.connectRate = 1;
        actual.oppsPerConnect = 1;

        Test.startTest();
        WaterfallController.Plan createP = WaterfallController.buildPlan(
            'create', 'Q4 2026', 'Activity', 10000, rate, actual);
        Test.stopTest();

        System.assertEquals(2, createP.selfSourced.setScale(0),
            'self-sourced share above 100% clamps — mixed CreatedDate/SQL anchors trip here first');
    }

    @isTest
    static void load_emptyScope_explainsInsteadOfThrowing() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User loner = new User(
            FirstName = 'W', LastName = 'Empty', Alias = 'wempty',
            Email = 'wempty@example.com', Username = 'wempty' + System.currentTimeMillis() + '@example.com.wf',
            ProfileId = p.Id, Title = 'Solutions Engineer',
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert loner;

        Test.startTest();
        WaterfallController.PagePayload page;
        System.runAs(loner) {
            page = WaterfallController.load(null, CockpitConstants.TEAM_MODE_MY,
                CockpitConstants.PRODUCT_ALL, CockpitConstants.SIZE_ALL);
        }
        Integer cal = WaterfallCalibrationSchedulable.run(Date.today());
        Test.stopTest();

        System.assertNotEquals(null, page.emptyReason, 'SE-only scope explains, it does not throw');
        System.assertEquals(0, page.rows.size(), 'no AE cards when the scope is empty');
        System.assert(cal >= 0, 'calibration job is safe on an empty director list');
    }

    @isTest
    static void load_directorTeam_returnsACard() {
        User dir = usr(null, 'Director');
        insert dir;
        User ae = usr(dir.Id, 'Account Executive');
        insert ae;
        Account acc = new Account(Name = 'WF Ctrl Acc');
        insert acc;
        Id rt = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Opportunity' AND DeveloperName = 'Euna_Sale' LIMIT 1
        ].Id;
        insert new Opportunity(
            Name = 'Open Q',
            AccountId = acc.Id,
            OwnerId = ae.Id,
            RecordTypeId = rt,
            Type = 'New Sale',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(10),
            EUNA_Solution__c = 'Budget Professional',
            Y1_ARR_Offered_Price__c = 12000,
            SQL_Datestamp_bf__c = Date.today().addDays(-20)
        );
        insert new Sales_Plan__c(
            Sales_Rep__c = ae.Id,
            Quarter__c = CockpitConstants.quarterOf(Date.today()),
            Fiscal_Year__c = Date.today().year(),
            Quota_Amount__c = 60000,
            Start_Date__c = WaterfallConstants.periodStart(Date.today())
        );

        Test.startTest();
        WaterfallController.PagePayload page;
        System.runAs(dir) {
            page = WaterfallController.load(null, CockpitConstants.TEAM_MODE_MY,
                CockpitConstants.PRODUCT_GROUP_BUDGET, CockpitConstants.SIZE_ALL);
        }
        Test.stopTest();

        System.assertEquals(1, page.rows.size(), 'director default scope is their AE team');
        System.assertEquals(ae.Id, page.rows[0].ownerId, 'card is the report, not a hardcoded roster');
        System.assertEquals(60000, page.rows[0].quota, 'quota comes from Sales_Plan__c');
        System.assertEquals(1, page.rows[0].haveQo, 'open SQL-stamped Budget deal is Have');
        System.assertNotEquals(null, page.rows[0].closePlan, 'close plan is present');
        System.assertNotEquals(null, page.rows[0].createPlan, 'create plan is present');
        System.assertNotEquals(null, page.rows[0].recommended, 'each AE has a recommended play plan');
        System.assertNotEquals(null, page.rows[0].planned, 'planned starts as the recommended numbers');
        System.assert(page.remainingWorkingDays != null && page.remainingWorkingDays >= 0,
            'remaining weekdays drive dial cadence');
        System.assert(page.scopeCaption.contains('Budget'), 'caption names the product family');
    }

    static Integer seq = 0;
    static User usr(Id mgr, String title) {
        seq++;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String u = 'wfct' + seq + String.valueOf(System.currentTimeMillis());
        return new User(
            FirstName = 'W', LastName = 'c' + seq, Alias = ('wc' + seq).left(8),
            Email = u + '@example.com', Username = u + '@example.com.wfct',
            ProfileId = p.Id, ManagerId = mgr, Title = title,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }
}
