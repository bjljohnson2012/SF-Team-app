/**
 * Covers: CockpitConversionService
 * Behavioural floors: interpret gap, commit dash vs flag, over-index
 * conjunction, live-book sample floors, null band → Not on forecast.
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
    static void checkpointDate_isFirstSecondAndThirdMonthOfCloseQuarter() {
        Date q3 = Date.newInstance(2026, 9, 10);
        System.assertEquals(Date.newInstance(2026, 7, 1),
            CockpitConversionService.checkpointDate(q3, CockpitConversionService.CP_M1));
        System.assertEquals(Date.newInstance(2026, 8, 1),
            CockpitConversionService.checkpointDate(q3, CockpitConversionService.CP_M2));
        System.assertEquals(Date.newInstance(2026, 9, 1),
            CockpitConversionService.checkpointDate(q3, CockpitConversionService.CP_M3));
        Date q1 = Date.newInstance(2026, 3, 10);
        System.assertEquals(Date.newInstance(2026, 1, 1),
            CockpitConversionService.checkpointDate(q1, CockpitConversionService.CP_M1));
        System.assertEquals(Date.newInstance(2026, 2, 1),
            CockpitConversionService.checkpointDate(q1, CockpitConversionService.CP_M2));
        System.assertEquals(Date.newInstance(2026, 3, 1),
            CockpitConversionService.checkpointDate(q1, CockpitConversionService.CP_M3));
        System.assertEquals(null, CockpitConversionService.checkpointDate(null, CockpitConversionService.CP_M1));
    }

    @isTest
    static void categoryInMonth_firstSecondThird_andNotOnForecast() {
        Date close = Date.newInstance(2026, 9, 10);
        List<CockpitConversionService.SnapPoint> points = new List<CockpitConversionService.SnapPoint>{
            new CockpitConversionService.SnapPoint(Date.newInstance(2026, 7, 2), 'Commit'),
            new CockpitConversionService.SnapPoint(Date.newInstance(2026, 8, 13), 'Best Case'),
            new CockpitConversionService.SnapPoint(Date.newInstance(2026, 9, 3), 'Pipeline')
        };
        System.assertEquals('Commit',
            CockpitConversionService.categoryInMonth(points, close, CockpitConversionService.CP_M1, null),
            'July week is first month of Q3');
        System.assertEquals('Best Case',
            CockpitConversionService.categoryInMonth(points, close, CockpitConversionService.CP_M2, null),
            'August week is second month of Q3');
        System.assertEquals('Pipeline',
            CockpitConversionService.categoryInMonth(points, close, CockpitConversionService.CP_M3, null),
            'September week is third month of Q3');
        System.assertEquals(CockpitConversionService.NOT_ON_FORECAST,
            CockpitConversionService.categoryInMonth(new List<CockpitConversionService.SnapPoint>(), close,
                CockpitConversionService.CP_M1, null));
        System.assertEquals(CockpitConversionService.NOT_ON_FORECAST,
            CockpitConversionService.categoryInMonth(null, close, CockpitConversionService.CP_M1, null));
        System.assertEquals(CockpitConversionService.NOT_ON_FORECAST,
            CockpitConversionService.categoryInMonth(
                new List<CockpitConversionService.SnapPoint>{
                    new CockpitConversionService.SnapPoint(Date.newInstance(2026, 7, 2), null)
                },
                close, CockpitConversionService.CP_M1, null),
            'blank roll-up in the month is Not on forecast');
        System.assertEquals(CockpitConversionService.NOT_ON_FORECAST,
            CockpitConversionService.categoryInMonth(points, Date.newInstance(2026, 4, 10),
                CockpitConversionService.CP_M1, null),
            'Q2 first month has no July week');
        System.assertEquals('Commit',
            CockpitConversionService.categoryInMonth(
                new List<CockpitConversionService.SnapPoint>(),
                close, CockpitConversionService.CP_M3, 'Commit'),
            'before-close fills the month the deal actually closed');
        System.assertEquals(CockpitConversionService.NOT_ON_FORECAST,
            CockpitConversionService.categoryInMonth(
                new List<CockpitConversionService.SnapPoint>(),
                close, CockpitConversionService.CP_M1, 'Commit'),
            'before-close does not leak into an earlier month');
    }

    @isTest
    static void forecastAccuracy_monthCategories_byAe_andCloseQuarter() {
        User dir = setupDirectorWithRep();
        User rep = [SELECT Id FROM User WHERE ManagerId = :dir.Id LIMIT 1];
        Id rtId = eunaSaleRtId();
        Date closeQ3 = Date.newInstance(2026, 9, 10);

        System.runAs(dir) {
            Account a = new Account(Name = 'Conv Acme');
            insert a;
            Opportunity moved = closedDeal(a.Id, rep.Id, rtId, 'Closed Lost', 'Commit',
                'Budget Professional', 40000, closeQ3, 'Ghosted');
            Opportunity bare = closedDeal(a.Id, rep.Id, rtId, 'Closed Lost', null,
                'Budget Professional', 20000, closeQ3.addDays(-2), 'Perceived lack of ROI');
            Opportunity large = closedDeal(a.Id, rep.Id, rtId, 'Closed Lost', 'Best Case',
                'Budget Professional', 180000, closeQ3.addDays(-5), 'Ghosted');
            Opportunity q1 = closedDeal(a.Id, rep.Id, rtId, 'Closed Lost', 'Pipeline',
                'Budget Professional', 25000, Date.newInstance(2026, 2, 10), 'Ghosted');
            insert new List<Opportunity>{ moved, bare, large, q1, openDeal(a.Id, rep.Id, rtId, 'Budget Professional', 60000) };
            CockpitConversionService.snapshotOverride = new Map<Id, List<CockpitConversionService.SnapPoint>>{
                moved.Id => new List<CockpitConversionService.SnapPoint>{
                    new CockpitConversionService.SnapPoint(Date.newInstance(2026, 7, 2), 'Commit'),
                    new CockpitConversionService.SnapPoint(Date.newInstance(2026, 8, 13), 'Best Case'),
                    new CockpitConversionService.SnapPoint(Date.newInstance(2026, 9, 3), 'Pipeline')
                }
            };

            Test.startTest();
            CockpitConversionService.PagePayload page = CockpitConversionService.load(
                dir.Id, CockpitConversionService.TEAM_DIRECTOR, null, CockpitConversionService.SIZE_ALL, '2026-Q3');
            Test.stopTest();

            System.assertEquals(false, page.scope.emptyScope, 'director with an AE is a valid scope');
            System.assertEquals('2026-Q3', page.scope.closeQuarter, 'selected close quarter is honored');
            System.assertEquals(3, page.closedInWindow, 'Q1 close is excluded from the Q3 book');
            System.assertEquals(3, page.bandCheckpoints.size(), 'first, second, third month tables');
            System.assertEquals(CockpitConversionService.CP_M1, page.bandCheckpoints[0].key);
            System.assertEquals(CockpitConversionService.CP_M2, page.bandCheckpoints[1].key);
            System.assertEquals(CockpitConversionService.CP_M3, page.bandCheckpoints[2].key);
            System.assertEquals('First month of the quarter', page.bandCheckpoints[0].label);
            System.assertEquals('Second month of the quarter', page.bandCheckpoints[1].label);
            System.assertEquals('Third month of the quarter', page.bandCheckpoints[2].label);
            System.assertEquals(true, bandHas(page.bandCheckpoints[0].rows, 'Commit', 1),
                'first month reads the July week');
            System.assertEquals(true, bandHas(page.bandCheckpoints[1].rows, 'Best Case', 1),
                'second month reads the August week');
            System.assertEquals(true, bandHas(page.bandCheckpoints[2].rows, 'Pipeline', 1),
                'third month reads the September week');
            System.assertEquals(true, bandHas(page.bandCheckpoints[2].rows, 'Best Case', 1),
                'third month uses before-close when the deal closed that month and had no snapshot');
            for (CockpitConversionService.CheckpointTable t : page.bandCheckpoints) {
                System.assert(!t.byAe.isEmpty(), t.key + ' flattens by AE');
                System.assertNotEquals(null, t.explain, t.key + ' explains the table');
                for (CockpitConversionService.BandRow b : t.rows) {
                    System.assertNotEquals(CockpitConversionService.NOT_ON_FORECAST, b.band,
                        t.key + ' leaves deals with no source off the table');
                }
            }
            System.assertNotEquals(null, page.forecastExplain, 'forecast category accuracy is explained');
            System.assert(page.forecastExplain.contains('In-quarter'), 'explain names the in-quarter toggle');
            System.assertNotEquals(null, page.conventionCaption, 'page explains the book-to-quarter-end comparison');
            System.assertNotEquals(null, page.liveBook, 'live book is computed');
            System.assert(!page.lossMatrix.isEmpty(), 'loss matrix includes floored closed-lost reasons');
            System.assert(page.options.closeQuarters.size() > 1, 'quarter picker is served');
            System.assertEquals(CockpitConversionService.QUARTER_ALL, page.options.closeQuarters[0].value);

            CockpitConversionService.PagePayload allQ = CockpitConversionService.load(
                dir.Id, CockpitConversionService.TEAM_DIRECTOR, null, CockpitConversionService.SIZE_ALL,
                CockpitConversionService.QUARTER_ALL);
            System.assertEquals(3, allQ.bandCheckpoints.size(), 'All quarters still builds the current-quarter book');

            CockpitConversionService.snapshotOverride = null;
            CockpitConversionService.PagePayload liveQuery = CockpitConversionService.load(
                dir.Id, CockpitConversionService.TEAM_DIRECTOR, null, CockpitConversionService.SIZE_ALL, '2026-Q3');
            System.assertEquals(3, liveQuery.bandCheckpoints.size(), 'live snapshot query still builds three tables');
            CockpitConversionService.PagePayload sized = CockpitConversionService.load(
                dir.Id, CockpitConversionService.TEAM_DIRECTOR, CockpitConstants.PRODUCT_GROUP_BUDGET,
                CockpitConversionService.SIZE_UNDER_50, '2026-Q3');
            System.assertNotEquals(null, sized.scope.caption, 'product + size filters produce a caption');
            System.assert(sized.scope.caption.contains('Budget'), 'caption names the Budget group');
            System.assert(sized.scope.caption.contains('2026 Q3') || sized.scope.caption.contains('2026-Q3'),
                'caption names the close quarter');
        }
    }

    @isTest
    static void productType_fourGroups_budgetExcludesGrants() {
        User dir = setupDirectorWithRep();
        User rep = [SELECT Id FROM User WHERE ManagerId = :dir.Id LIMIT 1];
        Id rtId = eunaSaleRtId();
        Date closeQ3 = Date.newInstance(2026, 9, 10);
        System.runAs(dir) {
            Account a = new Account(Name = 'Conv Product');
            insert a;
            insert new List<Opportunity>{
                closedDeal(a.Id, rep.Id, rtId, 'Closed Lost', 'Commit',
                    'Budget Professional', 40000, closeQ3, 'Ghosted'),
                closedDeal(a.Id, rep.Id, rtId, 'Closed Lost', 'Commit',
                    'Grants', 30000, closeQ3, 'Ghosted')
            };
            Test.startTest();
            CockpitConversionService.PagePayload budget = CockpitConversionService.load(
                dir.Id, CockpitConversionService.TEAM_DIRECTOR, CockpitConstants.PRODUCT_GROUP_BUDGET,
                CockpitConversionService.SIZE_ALL, '2026-Q3');
            CockpitConversionService.PagePayload grants = CockpitConversionService.load(
                dir.Id, CockpitConversionService.TEAM_DIRECTOR, CockpitConstants.PRODUCT_GROUP_GRANTS,
                CockpitConversionService.SIZE_ALL, '2026-Q3');
            CockpitConversionService.ScopeOptions opts = CockpitConversionService.getScopeOptions();
            Test.stopTest();
            System.assertEquals(1, budget.closedInWindow, 'Budget group is Pro + Ent only');
            System.assertEquals(CockpitConstants.PRODUCT_GROUP_BUDGET, budget.scope.productType);
            System.assertEquals(1, grants.closedInWindow, 'Grants group excludes Budget');
            System.assertEquals(5, opts.productTypes.size(), 'All products + four families');
            System.assertEquals('', opts.productTypes[0].value);
            System.assertEquals(CockpitConstants.PRODUCT_GROUP_BUDGET, opts.productTypes[1].value);
            System.assertEquals('Budget', opts.productTypes[1].label);
            System.assertEquals('Grants', opts.productTypes[2].label);
            System.assertEquals('Procurement Sourcing', opts.productTypes[3].label);
            System.assertEquals('Procurement Marketplace', opts.productTypes[4].label);
        }
    }

    @isTest
    static void fateOf_andRates_inQuarterVsPush() {
        Date qStart = Date.newInstance(2026, 7, 1);
        Date qEnd = Date.newInstance(2026, 9, 30);
        System.assertEquals(CockpitConversionService.FATE_FUNDED,
            CockpitConversionService.fateOf(true, true, Date.newInstance(2026, 8, 10), qStart, qEnd));
        System.assertEquals(CockpitConversionService.FATE_LOST,
            CockpitConversionService.fateOf(true, false, Date.newInstance(2026, 9, 10), qStart, qEnd));
        System.assertEquals(CockpitConversionService.FATE_PUSHED,
            CockpitConversionService.fateOf(false, false, Date.newInstance(2026, 10, 15), qStart, qEnd));
        System.assertEquals(CockpitConversionService.FATE_OPEN,
            CockpitConversionService.fateOf(false, false, Date.newInstance(2026, 9, 20), qStart, qEnd));
        System.assertEquals(CockpitConversionService.FATE_PRIOR,
            CockpitConversionService.fateOf(true, false, Date.newInstance(2026, 2, 10), qStart, qEnd));

        CockpitConversionService.BandRow row = new CockpitConversionService.BandRow();
        row.band = 'Commit';
        CockpitConversionService.applyFate(row, CockpitConversionService.FATE_FUNDED, 100000);
        CockpitConversionService.applyFate(row, CockpitConversionService.FATE_FUNDED, 100000);
        CockpitConversionService.applyFate(row, CockpitConversionService.FATE_LOST, 100000);
        CockpitConversionService.applyFate(row, CockpitConversionService.FATE_LOST, 100000);
        CockpitConversionService.applyFate(row, CockpitConversionService.FATE_PUSHED, 100000);
        CockpitConversionService.applyFate(row, CockpitConversionService.FATE_PUSHED, 100000);
        CockpitConversionService.applyFate(row, CockpitConversionService.FATE_PUSHED, 100000);
        CockpitConversionService.applyFate(row, CockpitConversionService.FATE_PUSHED, 100000);
        CockpitConversionService.finalizeBands(new List<CockpitConversionService.BandRow>{ row });
        System.assertEquals(0.5000, row.winRateInQuarter, 'in-quarter is funded ÷ closed that quarter');
        System.assertEquals(0.2500, row.winRateInclPush, 'include push puts slips in the denominator');
        System.assertEquals(2, row.won);
        System.assertEquals(2, row.lost);
        System.assertEquals(4, row.pushed);
    }

    @isTest
    static void forecastAccuracy_pushedDealIsNotInQuarterClose() {
        User dir = setupDirectorWithRep();
        User rep = [SELECT Id FROM User WHERE ManagerId = :dir.Id LIMIT 1];
        Id rtId = eunaSaleRtId();
        Date closeQ3 = Date.newInstance(2026, 9, 10);
        System.runAs(dir) {
            Account a = new Account(Name = 'Conv Push');
            insert a;
            Opportunity closed = closedDeal(a.Id, rep.Id, rtId, 'Closed Lost', 'Commit',
                'Budget Professional', 40000, closeQ3, 'Ghosted');
            Opportunity slipped = openDeal(a.Id, rep.Id, rtId, 'Budget Professional', 50000);
            slipped.CloseDate = Date.newInstance(2026, 10, 20);
            insert new List<Opportunity>{ closed, slipped };
            CockpitConversionService.snapshotOverride = new Map<Id, List<CockpitConversionService.SnapPoint>>{
                closed.Id => new List<CockpitConversionService.SnapPoint>{
                    new CockpitConversionService.SnapPoint(Date.newInstance(2026, 7, 2), 'Commit')
                },
                slipped.Id => new List<CockpitConversionService.SnapPoint>{
                    new CockpitConversionService.SnapPoint(Date.newInstance(2026, 7, 2), 'Most Likely')
                }
            };
            Test.startTest();
            CockpitConversionService.PagePayload page = CockpitConversionService.load(
                dir.Id, CockpitConversionService.TEAM_DIRECTOR, null, CockpitConversionService.SIZE_ALL, '2026-Q3');
            Test.stopTest();
            CockpitConversionService.BandRow commit = bandOf(page.bandCheckpoints[0].rows, 'Commit');
            CockpitConversionService.BandRow ml = bandOf(page.bandCheckpoints[0].rows, 'Most Likely');
            System.assertNotEquals(null, commit, 'July Commit stays on the book');
            System.assertEquals(1, commit.lost, 'in-quarter close is a loss');
            System.assertEquals(0, commit.pushed, 'the Q3 close is not a push');
            System.assertNotEquals(null, ml, 'July Most Likely stays on the book');
            System.assertEquals(1, ml.pushed, 'Q4 close date is a push');
            System.assertEquals(0, ml.lost, 'a push is not an in-quarter loss');
            System.assertEquals(1, page.pushedInWindow, 'quarter tally counts the slip');
            System.assertEquals(1, page.commitAccuracy.size(), 'Funded is by AE for Commit/Most Likely');
            System.assertEquals(2, page.commitAccuracy[0].book, 'Commit close plus Most Likely slip');
            System.assertEquals(1, page.commitAccuracy[0].lost);
            System.assertEquals(1, page.commitAccuracy[0].pushed);
            CockpitConversionService.snapshotOverride = null;
        }
    }

    @isTest
    static void normalizeProductGroup_mapsSkuAndKeepsFamily() {
        System.assertEquals(CockpitConstants.PRODUCT_GROUP_BUDGET,
            CockpitConversionService.normalizeProductGroup('Budget Professional'));
        System.assertEquals(CockpitConstants.PRODUCT_GROUP_GRANTS,
            CockpitConversionService.normalizeProductGroup('Amplifund'));
        System.assertEquals(CockpitConstants.PRODUCT_GROUP_PROC_SOURCING,
            CockpitConversionService.normalizeProductGroup('Procurement-Bonfire'));
        System.assertEquals(CockpitConstants.PRODUCT_GROUP_PROC_MARKET,
            CockpitConversionService.normalizeProductGroup('Procurement-EqualLevel'));
        System.assertEquals(CockpitConstants.PRODUCT_GROUP_BUDGET,
            CockpitConversionService.normalizeProductGroup(CockpitConstants.PRODUCT_GROUP_BUDGET));
        System.assertEquals('', CockpitConversionService.normalizeProductGroup(''));
        System.assertEquals('Budget', CockpitConversionService.productCaption(CockpitConstants.PRODUCT_GROUP_BUDGET));
        System.assertEquals('Procurement Sourcing',
            CockpitConversionService.productCaption(CockpitConstants.PRODUCT_GROUP_PROC_SOURCING));
        System.assertEquals('All products', CockpitConversionService.productCaption(null));
    }

    @isTest
    static void emptyScope_explainsNoAes_doesNotThrow() {
        User lone = usr(null, 'Solutions Engineer');
        insert lone;
        System.runAs(lone) {
            Test.startTest();
            CockpitConversionService.PagePayload page = CockpitConversionService.load(
                lone.Id, CockpitConversionService.TEAM_MINE, null, CockpitConversionService.SIZE_ALL, null);
            Test.stopTest();
            System.assertEquals(true, page.scope.emptyScope, 'director with no AEs is an empty scope');
            System.assertNotEquals(null, page.scope.emptyMessage, 'empty state is explained');
            System.assert(page.scope.emptyMessage.contains('account executives'),
                'message talks about AEs, not a raw director-only error');
        }
    }

    @isTest
    static void resolveScope_blankQuarter_defaultsToCurrent() {
        User dir = setupDirectorWithRep();
        System.runAs(dir) {
            Test.startTest();
            CockpitConversionService.Scope blank = CockpitConversionService.resolveScope(
                dir.Id, CockpitConversionService.TEAM_DIRECTOR, null, CockpitConversionService.SIZE_ALL, null);
            CockpitConversionService.Scope allQ = CockpitConversionService.resolveScope(
                dir.Id, CockpitConversionService.TEAM_DIRECTOR, null, CockpitConversionService.SIZE_ALL,
                CockpitConversionService.QUARTER_ALL);
            Test.stopTest();
            System.assertEquals(CockpitConversionService.currentQuarterKey(), blank.closeQuarter,
                'blank close quarter defaults to the running quarter');
            System.assertEquals(CockpitConversionService.QUARTER_ALL, allQ.closeQuarter,
                'All close quarters is an explicit choice, not a default');
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
        System.assertEquals(CockpitConversionService.NOT_ON_FORECAST,
            CockpitConversionService.normalizeBand(null), 'null band');
        System.assertEquals(CockpitConversionService.NOT_ON_FORECAST,
            CockpitConversionService.normalizeBand(''), 'blank band');
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

    static Boolean bandHas(List<CockpitConversionService.BandRow> rows, String band, Integer minTotal) {
        CockpitConversionService.BandRow b = bandOf(rows, band);
        return b != null && b.total >= minTotal;
    }

    static CockpitConversionService.BandRow bandOf(List<CockpitConversionService.BandRow> rows, String band) {
        if (rows == null) return null;
        for (CockpitConversionService.BandRow b : rows) {
            if (b.band == band) return b;
        }
        return null;
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
