/**
 * Covers: WaterfallConstants
 * Asserts shrinkage, median cycle, lands, sample labels, and the 100% tripwire.
 */
@isTest
private class WaterfallConstantsTest {

    @isTest
    static void blend_k20_halfWeightAtTwentyDeals() {
        Test.startTest();
        Decimal blended = WaterfallConstants.blend(0.171, 20, 0.380);
        Decimal nick = WaterfallConstants.blend(5940, 1, 19235);
        Test.stopTest();
        System.assertEquals(0.2755, blended.setScale(4), 'at n=K personal and baseline share the weight');
        System.assert(nick > 17000 && nick < 19000, 'one-deal ASP is pulled to the team, not left at $5,940');
    }

    @isTest
    static void median_dropsNothingAndSplitsEven() {
        Test.startTest();
        Decimal odd = WaterfallConstants.median(new List<Decimal>{ 10, 30, 20 });
        Decimal even = WaterfallConstants.median(new List<Decimal>{ 4, 8, 10, 20 });
        Decimal empty = WaterfallConstants.median(new List<Decimal>());
        Test.stopTest();
        System.assertEquals(20, odd, 'odd median is the middle value after sort');
        System.assertEquals(9, even, 'even median averages the two centre values');
        System.assertEquals(null, empty, 'empty list has no median');
    }

    @isTest
    static void landsQuarters_usesCeilOfMedianOver91() {
        Test.startTest();
        System.assertEquals(2, WaterfallConstants.landsQuarters(175), '175d is Q+2');
        System.assertEquals(3, WaterfallConstants.landsQuarters(221), '221d is Q+3');
        System.assertEquals(4, WaterfallConstants.landsQuarters(280), '280d is Q+4');
        System.assertEquals(1, WaterfallConstants.landsQuarters(4), '4d still lands Q+1');
        System.assertEquals(1, WaterfallConstants.landsQuarters(null), 'null cycle is Q+1, not Q+0');
        Test.stopTest();
    }

    @isTest
    static void sampleConfidence_labelsThinRates() {
        System.assertEquals('Low', WaterfallConstants.sampleConfidence(6), 'Nick-sized sample is Low');
        System.assertEquals('Medium', WaterfallConstants.sampleConfidence(19), '19 closes is Medium');
        System.assertEquals('Medium', WaterfallConstants.sampleConfidence(35), '35 closes is Medium');
        System.assertEquals('High', WaterfallConstants.sampleConfidence(71), '71 closes is High');
    }

    @isTest
    static void clampShare_isTheMixedAnchorTripwire() {
        System.assertEquals(1, WaterfallConstants.clampShare(1.40), 'over 100% clamps — mixed date anchors show up here');
        System.assertEquals(0, WaterfallConstants.clampShare(-0.2), 'negative share clamps to 0');
        System.assertEquals(0.13, WaterfallConstants.clampShare(0.13), 'in-range share is unchanged');
    }

    @isTest
    static void workingDaysBetween_countsWeekdaysInclusive() {
        Date mon = Date.newInstance(2026, 9, 14);
        Date fri = Date.newInstance(2026, 9, 18);
        Date sun = Date.newInstance(2026, 9, 20);
        Date wed = Date.newInstance(2026, 9, 16);
        Test.startTest();
        Integer week = WaterfallConstants.workingDaysBetween(mon, fri);
        Integer throughWeekend = WaterfallConstants.workingDaysBetween(mon, sun);
        Integer weekendOnly = WaterfallConstants.workingDaysBetween(sun.addDays(-1), sun);
        Integer oneDay = WaterfallConstants.workingDaysBetween(wed, wed);
        Integer empty = WaterfallConstants.workingDaysBetween(fri, mon);
        Test.stopTest();
        System.assertEquals(5, week, 'Mon–Fri is five working days');
        System.assertEquals(5, throughWeekend, 'Sat/Sun add nothing');
        System.assertEquals(0, weekendOnly, 'a weekend span is zero working days');
        System.assertEquals(1, oneDay, 'a Wednesday counts as one');
        System.assertEquals(0, empty, 'end before start is zero');
        System.assertEquals(0, WaterfallConstants.weekdayIndex(mon), '1900-01-01 alignment: 2026-09-14 is Monday');
        System.assertEquals(2, WaterfallConstants.weekdayIndex(wed), 'Wednesday is index 2');
    }

    @isTest
    static void matchesSize_usesSharedBands() {
        System.assertEquals(true, WaterfallConstants.matchesSize(12000, CockpitConstants.SIZE_UNDER_50K), '12k is under 50k');
        System.assertEquals(false, WaterfallConstants.matchesSize(12000, CockpitConstants.SIZE_OVER_150K), '12k is not 150k+');
        System.assertEquals(true, WaterfallConstants.matchesSize(90000, CockpitConstants.SIZE_50_150K), '90k is mid band');
        System.assertEquals(true, WaterfallConstants.matchesSize(null, CockpitConstants.SIZE_ALL), 'All sizes keeps null ARR');
    }
}
