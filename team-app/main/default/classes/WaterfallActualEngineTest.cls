/**
 * Covers: WaterfallActualEngine, WaterfallActualSchedulable
 * Asserts dispositioned-only dials and the bad-number connect denominator.
 */
@isTest
private class WaterfallActualEngineTest {

    @isTest
    static void measure_countsDispositionedDialsOnly() {
        User dir = usr(null, 'Director');
        insert dir;
        User ae = usr(dir.Id, 'Account Executive');
        insert ae;
        Date today = Date.today();
        Date start = WaterfallConstants.periodStart(today);
        insert new List<Task>{
            call(ae.Id, start.addDays(1), 'Connected'),
            call(ae.Id, start.addDays(2), 'Connected'),
            call(ae.Id, start.addDays(3), 'No Answer'),
            call(ae.Id, start.addDays(4), 'Wrong Number'),
            call(ae.Id, start.addDays(5), null)
        };
        Datetime heldStart = Datetime.now().addHours(-3);
        if (heldStart.date() < start) heldStart = Datetime.newInstance(start, Time.newInstance(9, 0, 0, 0));
        insert new Event(
            OwnerId = ae.Id,
            Subject = 'Held',
            StartDateTime = heldStart,
            EndDateTime = heldStart.addHours(1)
        );

        Test.startTest();
        WaterfallActualEngine.ActualSet actuals = WaterfallActualEngine.measure(
            new Set<Id>{ ae.Id }, CockpitConstants.PRODUCT_ALL,
            CockpitConstants.SIZE_ALL, today);
        Test.stopTest();

        WaterfallActualEngine.ActualRow row = actuals.byOwner.get(ae.Id);
        System.assertEquals(5, row.callTasks, 'all completed Call tasks are the coverage denominator');
        System.assertEquals(4, row.dials, 'undispositioned Call is not a dial');
        System.assertEquals(2, row.connects, 'Connected is the only connect');
        System.assertEquals(3, row.usableConnectDenom, 'Wrong Number is out of the connect denominator');
        System.assertEquals((2.0 / 3).setScale(4), row.connectRate.setScale(4), '2 connects / 3 usable');
        System.assertEquals((4.0 / 5).setScale(4), row.activityComplete.setScale(4), '4 of 5 calls have a disposition');
        System.assert(row.meetingsHeld >= 1, 'past Event in the period counts as a meeting held');
    }

    @isTest
    static void persist_andSchedulable_doNotThrow() {
        User dir = usr(null, 'Director');
        insert dir;
        User ae = usr(dir.Id, 'Account Executive');
        insert ae;
        insert new Sales_Plan__c(
            Sales_Rep__c = ae.Id,
            Quarter__c = CockpitConstants.quarterOf(Date.today()),
            Fiscal_Year__c = Date.today().year(),
            Quota_Amount__c = 150000,
            Start_Date__c = WaterfallConstants.periodStart(Date.today())
        );

        Test.startTest();
        WaterfallActualEngine.ActualSet actuals = WaterfallActualEngine.measure(
            new Set<Id>{ ae.Id }, CockpitConstants.PRODUCT_ALL,
            CockpitConstants.SIZE_ALL, Date.today());
        List<Waterfall_Actual__c> recs = WaterfallActualEngine.persist(actuals);
        Integer n = WaterfallActualSchedulable.run(Date.today());
        Test.stopTest();

        System.assertEquals(1, recs.size(), 'one actuals row per AE');
        System.assertEquals(150000, recs[0].Quota_Amount__c, 'quota is summed from Sales_Plan__c');
        System.assert(n >= 0, 'schedulable returns a non-negative persist count');
    }

    static Task call(Id ownerId, Date day, String disp) {
        return new Task(
            OwnerId = ownerId,
            Subject = 'Call',
            Status = 'Completed',
            TaskSubtype = 'Call',
            ActivityDate = day,
            SalesLoft1__Call_Disposition__c = disp
        );
    }

    static Integer seq = 0;
    static User usr(Id mgr, String title) {
        seq++;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String u = 'wfac' + seq + String.valueOf(System.currentTimeMillis());
        return new User(
            FirstName = 'W', LastName = 'a' + seq, Alias = ('wa' + seq).left(8),
            Email = u + '@example.com', Username = u + '@example.com.wfac',
            ProfileId = p.Id, ManagerId = mgr, Title = title,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }
}
