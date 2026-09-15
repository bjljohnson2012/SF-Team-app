/**
 * Live Conversion Metrics (closure-based). Answers what a forecast word
 * (Commit / Most Likely / Best Case) actually turned into, plus commit
 * accuracy, loss-root over-index, and live-book leading indicators.
 * Aggregates only — no snapshot, no Win Rate Truth batch pattern.
 */
public with sharing class CockpitConversionService {

    public static final Date CLOSED_SINCE = Date.newInstance(2025, 1, 1);
    public static final Date LOSS_REASON_FLOOR = Date.newInstance(2026, 2, 5);
    public static final Integer COMMIT_SAMPLE_FLOOR = 4;
    public static final Decimal COMMIT_FLAG_RATE = 0.80;
    public static final Decimal RATE_GAP_POINTS = 0.08;
    public static final Integer OVERINDEX_MIN_LOSSES = 4;
    public static final Decimal OVERINDEX_SHARE = 0.18;
    public static final Decimal OVERINDEX_LIFT = 1.25;
    public static final Integer FLAG_MEDD_MIN_SCORED = 6;
    public static final Decimal FLAG_MEDD_SHARE = 0.60;
    public static final Integer FLAG_OPEN_MIN = 8;
    public static final Decimal FLAG_SILENT_SHARE = 0.35;
    public static final Decimal FLAG_NEXT_SHARE = 0.40;
    public static final Decimal FLAG_PUSH_SHARE = 0.30;
    public static final Decimal FLAG_ABOVE_BC_SHARE = 0.05;
    public static final Decimal FLAG_ABOVE_BC_MIN_ARR = 200000;
    public static final String SIZE_ALL = 'ALL';
    public static final String SIZE_UNDER_50 = 'UNDER_50';
    public static final String SIZE_50_150 = '50_150';
    public static final String SIZE_150_PLUS = '150_PLUS';
    public static final String TEAM_MINE = 'mine';
    public static final String TEAM_DIRECTOR = 'director';
    public static final String UNBANDED = 'Not on forecast';
    public static final String NOT_ON_FORECAST = 'Not on forecast';
    public static final String ROOT_UNMAPPED = 'UNMAPPED';
    public static final String CP_M1 = 'M1';
    public static final String CP_M2 = 'M2';
    public static final String CP_M3 = 'M3';
    public static final String CP_START = 'M1';
    public static final String CP_MID = 'M2';
    public static final String CP_LAST = 'M3';
    public static final String QUARTER_ALL = 'ALL';
    public static final Integer MONTH_WEEK_OVERLAP_DAYS = 6;

    public static final List<String> MIGRATION_STAGES = new List<String>{
        'Migration', 'Migrating', 'Migration Complete'
    };
    public static final List<String> BAND_ORDER = new List<String>{
        'Commit', 'Most Likely', 'Best Case', 'Pipeline', 'Omitted', 'Closed', NOT_ON_FORECAST
    };
    public static final Set<String> ABOVE_BEST_CASE = new Set<String>{ 'Commit', 'Most Likely' };

    private static final Map<String, String> LOSS_ROOT = new Map<String, String>{
        'Opportunity not Qualified' => 'QUAL',
        'Insufficient Data' => 'QUAL',
        'Not Qualified' => 'QUAL',
        'Disqualified' => 'QUAL',
        'Ghosted' => 'ENGAGE',
        'No Decision / deferred' => 'ENGAGE',
        'No Decision' => 'ENGAGE',
        'No Response' => 'ENGAGE',
        'Deferred' => 'ENGAGE',
        'Relationship Issues' => 'ENGAGE',
        'Perceived lack of ROI' => 'VALUE',
        'Price' => 'VALUE',
        'Budget' => 'VALUE',
        'No Budget' => 'VALUE',
        'Quality of references' => 'VALUE',
        'Change in Budget / Strategic Direction' => 'VALUE',
        'Product Related Reasons' => 'FIT',
        'Product Gap' => 'FIT',
        'Missing Functionality' => 'FIT',
        'Product/Feature Issues' => 'FIT',
        'Adoption Issues' => 'FIT',
        'ERP Change / Utilizing ERP' => 'FIT',
        'Implementation Challenges' => 'FIT',
        'Integration Issues' => 'FIT',
        'Support Issues' => 'FIT',
        'Upper Management pushback' => 'EB',
        'Strength of Competitor Relationship' => 'COMP',
        'Strength of Competitor - Partner Relationship' => 'COMP',
        'Lost to Competitor' => 'COMP',
        'Entered process too late' => 'TIMING',
        'RFP Related' => 'TIMING',
        'Timing' => 'TIMING',
        'Contracting Issues' => 'PAPER',
        'Compliance Issues' => 'PAPER',
        'Legal' => 'PAPER',
        'Security Review' => 'PAPER',
        'Duplicate Opportunity' => 'DUPE',
        'Duplicate' => 'DUPE',
        'Test' => 'DUPE'
    };

    public class Scope {
        @AuraEnabled public Id directorId;
        @AuraEnabled public String directorName;
        @AuraEnabled public String teamMode;
        @AuraEnabled public String productType;
        @AuraEnabled public String sizeBand;
        @AuraEnabled public String closeQuarter;
        @AuraEnabled public String caption;
        @AuraEnabled public Boolean emptyScope;
        @AuraEnabled public String emptyMessage;
        @AuraEnabled public Boolean aeSelfFallback;
        @AuraEnabled public List<Id> ownerIds;
        @AuraEnabled public Map<Id, String> ownerNames;
    }

    public class FilterOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        public FilterOption(String v, String l) { value = v; label = l; }
    }

    public class ScopeOptions {
        @AuraEnabled public List<FilterOption> directors = new List<FilterOption>();
        @AuraEnabled public List<FilterOption> productTypes = new List<FilterOption>();
        @AuraEnabled public List<FilterOption> sizeBands = new List<FilterOption>();
        @AuraEnabled public List<FilterOption> closeQuarters = new List<FilterOption>();
    }

    public class BandRow {
        @AuraEnabled public String band;
        @AuraEnabled public Integer won = 0;
        @AuraEnabled public Integer lost = 0;
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Decimal arrWon = 0;
        @AuraEnabled public Decimal arrLost = 0;
        @AuraEnabled public Decimal arrTotal = 0;
        @AuraEnabled public Decimal winRateCount;
        @AuraEnabled public Decimal winRateArr;
        @AuraEnabled public Decimal rateGap;
        @AuraEnabled public Boolean largeDealsLose = false;
    }

    public class CommitRow {
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String aeName;
        @AuraEnabled public Integer won = 0;
        @AuraEnabled public Integer commitCloses = 0;
        @AuraEnabled public Decimal rate;
        @AuraEnabled public Boolean flagged = false;
        @AuraEnabled public String sampleTooltip;
    }

    public class LossRow {
        @AuraEnabled public String reason;
        @AuraEnabled public String root;
        @AuraEnabled public Integer losses = 0;
        @AuraEnabled public Decimal share;
        @AuraEnabled public Boolean mapped = true;
    }

    public class OverIndexRow {
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String aeName;
        @AuraEnabled public String reason;
        @AuraEnabled public String root;
        @AuraEnabled public Integer losses = 0;
        @AuraEnabled public Decimal share;
        @AuraEnabled public Decimal teamShare;
    }

    public class LiveRow {
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String aeName;
        @AuraEnabled public Decimal openArr = 0;
        @AuraEnabled public Integer dealCount = 0;
        @AuraEnabled public Integer scoredCount = 0;
        @AuraEnabled public Decimal avgMeddpicc;
        @AuraEnabled public Decimal shareBelow3;
        @AuraEnabled public Decimal silentShare;
        @AuraEnabled public Decimal nextStepShare;
        @AuraEnabled public Decimal pushedShare;
        @AuraEnabled public Decimal aboveBestCaseShare;
        @AuraEnabled public List<String> flags = new List<String>();
    }

    public class AeBandRow {
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String aeName;
        @AuraEnabled public String band;
        @AuraEnabled public Integer won = 0;
        @AuraEnabled public Integer lost = 0;
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Decimal arrWon = 0;
        @AuraEnabled public Decimal arrTotal = 0;
        @AuraEnabled public Decimal winRateCount;
        @AuraEnabled public Decimal winRateArr;
    }

    public class CheckpointTable {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String caption;
        @AuraEnabled public List<BandRow> rows = new List<BandRow>();
        @AuraEnabled public List<AeBandRow> byAe = new List<AeBandRow>();
        @AuraEnabled public String interpretation;
        @AuraEnabled public String explain;
    }

    public class PagePayload {
        @AuraEnabled public Scope scope;
        @AuraEnabled public ScopeOptions options;
        @AuraEnabled public List<BandRow> bands = new List<BandRow>();
        @AuraEnabled public List<CheckpointTable> bandCheckpoints = new List<CheckpointTable>();
        @AuraEnabled public String bandInterpretation;
        @AuraEnabled public String bandWriterCaption;
        @AuraEnabled public String conventionCaption;
        @AuraEnabled public String forecastExplain;
        @AuraEnabled public String commitExplain;
        @AuraEnabled public String lossExplain;
        @AuraEnabled public String liveExplain;
        @AuraEnabled public String lossReasonFloorCaption;
        @AuraEnabled public Boolean meddpiccAvailable;
        @AuraEnabled public Integer medianCycleDays;
        @AuraEnabled public Integer closedInWindow = 0;
        @AuraEnabled public List<CommitRow> commitAccuracy = new List<CommitRow>();
        @AuraEnabled public List<LossRow> lossMatrix = new List<LossRow>();
        @AuraEnabled public List<OverIndexRow> overIndexed = new List<OverIndexRow>();
        @AuraEnabled public List<LiveRow> liveBook = new List<LiveRow>();
    }

    public static ScopeOptions getScopeOptions() {
        ScopeOptions o = new ScopeOptions();
        o.directors.add(new FilterOption(TEAM_MINE, 'My team'));
        for (CockpitRosterService.DirectorOption d : CockpitRosterService.salesDirectors()) {
            String label = String.isBlank(d.segment) ? d.name : (d.segment + ' · ' + d.name);
            o.directors.add(new FilterOption(String.valueOf(d.userId), label));
        }
        o.productTypes.add(new FilterOption('', 'All products'));
        o.productTypes.add(new FilterOption(CockpitConstants.PRODUCT_GROUP_BUDGET, 'Budget'));
        o.productTypes.add(new FilterOption(CockpitConstants.PRODUCT_GROUP_GRANTS, 'Grants'));
        o.productTypes.add(new FilterOption(CockpitConstants.PRODUCT_GROUP_PROC_SOURCING, 'Procurement Sourcing'));
        o.productTypes.add(new FilterOption(CockpitConstants.PRODUCT_GROUP_PROC_MARKET, 'Procurement Marketplace'));
        o.sizeBands.add(new FilterOption(SIZE_ALL, 'All sizes'));
        o.sizeBands.add(new FilterOption(SIZE_UNDER_50, 'Under $50k'));
        o.sizeBands.add(new FilterOption(SIZE_50_150, '$50–150k'));
        o.sizeBands.add(new FilterOption(SIZE_150_PLUS, '$150k+'));
        o.closeQuarters.add(new FilterOption(QUARTER_ALL, 'All close quarters'));
        Date cursor = CockpitConstants.quarterStart(CLOSED_SINCE.year(), CockpitConstants.quarterOf(CLOSED_SINCE));
        Date today = Date.today();
        while (cursor <= today) {
            Integer y = cursor.year();
            Integer q = CockpitConstants.quarterOf(cursor);
            o.closeQuarters.add(new FilterOption(y + '-Q' + q, 'Q' + q + ' ' + y));
            cursor = cursor.addMonths(3);
        }
        return o;
    }

    public static PagePayload load(Id directorId, String teamMode, String productType, String sizeBand) {
        return load(directorId, teamMode, productType, sizeBand, null);
    }

    public static PagePayload load(
        Id directorId, String teamMode, String productType, String sizeBand, String closeQuarter
    ) {
        PagePayload page = new PagePayload();
        page.options = getScopeOptions();
        page.scope = resolveScope(directorId, teamMode, productType, sizeBand, closeQuarter);
        page.conventionCaption =
            'This tab is closure-based: it scores deals that closed in the selected close quarter. '
            + 'Cohort conversion (from the SQL gate) lives on Win Rate Truth.';
        page.bandWriterCaption =
            'Forecast category in each month of the close quarter: weekly roll-up snapshot in that month, '
            + 'else Forecast Category history as of month-end, else the band held before close if the '
            + 'deal closed in that month. No source → Not on forecast. Live — refresh to recompute.';
        page.forecastExplain =
            'Forecast category accuracy: of deals that closed in this quarter, what category were they '
            + 'in during the first, second, and third month — and what share of those won? '
            + 'That is conversion from the word the team used that month. '
            + page.bandWriterCaption;
        page.commitExplain =
            'Commit accuracy is won ÷ sat in Commit during the third month of the close quarter. '
            + 'Dash below 4 Commit closes — never shown as 0%. Flag below 80% once the floor is met.';
        page.lossExplain =
            'Loss reasons before ' + String.valueOf(LOSS_REASON_FLOOR)
            + ' are unreliable. Over-indexed when a rep has ≥4 losses in a reason, ≥18% of their losses, '
            + 'and more than 1.25× the team share.';
        page.liveExplain =
            'Open book per AE right now. Flags fire only when the sample floor is met. '
            + 'This section ignores the close-quarter filter — it is the live book, not closed deals.';
        page.lossReasonFloorCaption = page.lossExplain;
        page.meddpiccAvailable = canRead('Cockpit_MEDDPICC__c');

        if (page.scope.emptyScope) {
            return page;
        }

        Date qStart;
        Date qEnd;
        Date[] bounds = closeQuarterBounds(page.scope.closeQuarter);
        if (bounds != null) {
            qStart = bounds[0];
            qEnd = bounds[1];
        }
        String extra = extraFilters(page.scope.productType, page.scope.sizeBand, qStart, qEnd);
        String liveExtra = extraFilters(page.scope.productType, page.scope.sizeBand, null, null);
        List<Id> owners = page.scope.ownerIds;
        Date closedSince = CLOSED_SINCE;
        String saleRt = CockpitConstants.SALE_RECORDTYPE;
        Set<String> nbTypes = CockpitConstants.NEW_BUSINESS_TYPES;
        List<String> migStages = MIGRATION_STAGES;
        Set<String> solutions = CockpitConstants.solutionsInProductFilter(page.scope.productType);

        List<ClosedDeal> deals = loadClosedDeals(
            owners, extra, solutions, closedSince, saleRt, nbTypes, migStages, qStart, qEnd);
        page.closedInWindow = deals.size();
        fillBandCheckpoints(page, deals);

        fillLossMatrix(page, owners, extra, solutions, closedSince, saleRt, nbTypes, migStages, qStart, qEnd);
        fillLiveBook(page, owners, liveExtra, solutions, saleRt, nbTypes, migStages);
        page.medianCycleDays = loadMedianCycle(
            owners, extra, solutions, closedSince, saleRt, nbTypes, migStages, qStart, qEnd);
        return page;
    }

    public static String interpret(List<BandRow> bands) {
        if (bands == null || bands.isEmpty()) return null;
        List<String> lines = new List<String>();
        for (BandRow b : bands) {
            if (b != null && b.largeDealsLose == true) {
                lines.add(
                    'On ' + b.band + ', large deals lose: count win rate is '
                    + pct(b.winRateCount) + ' while dollar win rate is '
                    + pct(b.winRateArr) + '.'
                );
            }
        }
        return lines.isEmpty() ? null : String.join(lines, ' ');
    }

    public static Decimal commitAccuracy(Integer won, Integer commitCloses) {
        if (commitCloses == null || commitCloses < COMMIT_SAMPLE_FLOOR) return null;
        Integer w = won == null ? 0 : won;
        return Decimal.valueOf(w).divide(commitCloses, 4);
    }

    public static Integer medianCycle(List<Integer> days) {
        if (days == null || days.isEmpty()) return null;
        List<Integer> copy = new List<Integer>(days);
        copy.sort();
        return copy[copy.size() / 2];
    }

    public static Boolean isOverIndexed(Integer reasonLosses, Integer aeLosses, Decimal teamShare) {
        if (reasonLosses == null || reasonLosses < OVERINDEX_MIN_LOSSES) return false;
        if (aeLosses == null || aeLosses <= 0) return false;
        Decimal share = Decimal.valueOf(reasonLosses).divide(aeLosses, 4);
        if (share < OVERINDEX_SHARE) return false;
        Decimal ts = teamShare == null ? 0 : teamShare;
        return share > (OVERINDEX_LIFT * ts);
    }

    public static List<String> liveFlags(LiveRow r) {
        List<String> flags = new List<String>();
        if (r == null) return flags;
        if (r.scoredCount >= FLAG_MEDD_MIN_SCORED && r.shareBelow3 != null && r.shareBelow3 >= FLAG_MEDD_SHARE) {
            flags.add('Weak MEDDPICC');
        }
        if (r.dealCount >= FLAG_OPEN_MIN && r.silentShare != null && r.silentShare >= FLAG_SILENT_SHARE) {
            flags.add('Silent 30d+');
        }
        if (r.dealCount >= FLAG_OPEN_MIN && r.nextStepShare != null && r.nextStepShare >= FLAG_NEXT_SHARE) {
            flags.add('Next step lapsed/missing');
        }
        if (r.dealCount >= FLAG_OPEN_MIN && r.pushedShare != null && r.pushedShare >= FLAG_PUSH_SHARE) {
            flags.add('Pushed 3+');
        }
        if (r.openArr != null && r.openArr >= FLAG_ABOVE_BC_MIN_ARR
            && r.aboveBestCaseShare != null && r.aboveBestCaseShare < FLAG_ABOVE_BC_SHARE) {
            flags.add('Banded above Best Case');
        }
        return flags;
    }

    @TestVisible
    static Scope resolveScope(Id directorId, String teamMode, String productType, String sizeBand) {
        return resolveScope(directorId, teamMode, productType, sizeBand, null);
    }

    @TestVisible
    static Scope resolveScope(
        Id directorId, String teamMode, String productType, String sizeBand, String closeQuarter
    ) {
        Scope s = new Scope();
        s.teamMode = String.isBlank(teamMode) ? TEAM_MINE : teamMode;
        s.productType = normalizeProductGroup(productType);
        s.sizeBand = String.isBlank(sizeBand) ? SIZE_ALL : sizeBand;
        s.closeQuarter = String.isBlank(closeQuarter) ? currentQuarterKey() : closeQuarter;
        s.aeSelfFallback = false;
        s.emptyScope = false;
        s.ownerIds = new List<Id>();
        s.ownerNames = new Map<Id, String>();

        Id requested = (s.teamMode == TEAM_DIRECTOR && directorId != null)
            ? directorId
            : UserInfo.getUserId();
        s.directorId = requested;

        User director = [
            SELECT Id, Name, Title, Profile.Name, UserRole.Name
            FROM User
            WHERE Id = :requested
            WITH USER_MODE
            LIMIT 1
        ];
        s.directorName = director.Name;

        List<CockpitRosterService.Member> team = CockpitRosterService.teamFor(requested);
        if (team.isEmpty()) {
            if (!isNonAe(director)) {
                team.add(new CockpitRosterService.Member(director.Id, director.Name));
                s.aeSelfFallback = true;
            }
        }
        for (CockpitRosterService.Member m : team) {
            s.ownerIds.add(m.userId);
            s.ownerNames.put(m.userId, m.name);
        }
        if (s.ownerIds.isEmpty()) {
            s.emptyScope = true;
            s.emptyMessage =
                'This scope has no account executives. An AE can still open the page '
                + 'to see their own row; a director with no selling team has nothing to show.';
        }
        s.caption = scopeCaption(s);
        return s;
    }

    @TestVisible
    static Date checkpointDate(Date closeDate, String key) {
        return monthStart(closeDate, key);
    }

    @TestVisible
    static Date monthStart(Date closeDate, String key) {
        if (closeDate == null) return null;
        Integer q = CockpitConstants.quarterOf(closeDate);
        Date start = CockpitConstants.quarterStart(closeDate.year(), q);
        if (key == CP_M2) return start.addMonths(1);
        if (key == CP_M3) return start.addMonths(2);
        return start;
    }

    @TestVisible
    static String categoryInMonth(
        List<SnapPoint> points, Date closeDate, String key, String beforeClose
    ) {
        Date start = monthStart(closeDate, key);
        if (start == null) return NOT_ON_FORECAST;
        Date endDate = start.addMonths(1).addDays(-1);
        SnapPoint best = latestInMonth(points, start, endDate);
        if (best != null && String.isNotBlank(best.band)) return normalizeBand(best.band);
        if (closeDate >= start && closeDate <= endDate && String.isNotBlank(beforeClose)) {
            return normalizeBand(beforeClose);
        }
        return NOT_ON_FORECAST;
    }

    @TestVisible
    static String normalizeBand(String raw) {
        return String.isBlank(raw) ? NOT_ON_FORECAST : raw;
    }

    @TestVisible
    static String currentQuarterKey() {
        Date t = Date.today();
        return t.year() + '-Q' + CockpitConstants.quarterOf(t);
    }

    @TestVisible
    static Date[] closeQuarterBounds(String closeQuarter) {
        if (String.isBlank(closeQuarter) || closeQuarter == QUARTER_ALL) return null;
        List<String> parts = closeQuarter.split('-Q');
        if (parts.size() != 2) return null;
        Integer y = Integer.valueOf(parts[0]);
        Integer q = Integer.valueOf(parts[1]);
        return new Date[]{ CockpitConstants.quarterStart(y, q), CockpitConstants.quarterEnd(y, q) };
    }

    @TestVisible
    static String rootOf(String reason) {
        if (String.isBlank(reason)) return ROOT_UNMAPPED;
        String mapped = LOSS_ROOT.get(reason);
        return mapped == null ? ROOT_UNMAPPED : mapped;
    }

    @TestVisible
    public class SnapPoint {
        @TestVisible Date weekStart;
        @TestVisible String band;
        public SnapPoint(Date w, String b) { weekStart = w; band = b; }
    }

    @TestVisible static Map<Id, List<SnapPoint>> snapshotOverride;

    private class ClosedDeal {
        Id id;
        Id ownerId;
        Boolean won;
        Date closeDate;
        Decimal arr;
        String beforeClose;
    }

    private class HistPoint {
        DateTime changed;
        String value;
    }

    private class CommitAcc {
        Id ownerId;
        Integer won = 0;
        Integer commitCloses = 0;
    }

    private class LiveAcc {
        Id ownerId;
        Decimal openArr = 0;
        Integer dealCount = 0;
        Integer scored = 0;
        Decimal meddSum = 0;
        Integer below3 = 0;
        Integer silent = 0;
        Integer nextLapsed = 0;
        Integer pushed = 0;
        Decimal aboveArr = 0;
    }

    private static List<ClosedDeal> loadClosedDeals(
        List<Id> owners,
        String extra,
        Set<String> solutions,
        Date closedSince,
        String saleRt,
        Set<String> nbTypes,
        List<String> migStages,
        Date qStart,
        Date qEnd
    ) {
        String soql =
            'SELECT Id, OwnerId, IsWon, CloseDate, ARR_Opportunity_Amount_USD_Num__c, '
            + 'Forecast_Category_before_Close__c '
            + 'FROM Opportunity '
            + 'WHERE IsClosed = true AND CloseDate >= :closedSince '
            + 'AND OwnerId IN :owners '
            + 'AND RecordType.DeveloperName = :saleRt '
            + 'AND Type IN :nbTypes '
            + 'AND StageName NOT IN :migStages '
            + extra
            + ' LIMIT 2000';
        List<ClosedDeal> deals = new List<ClosedDeal>();
        for (Opportunity o : Database.query(soql, AccessLevel.USER_MODE)) {
            ClosedDeal d = new ClosedDeal();
            d.id = o.Id;
            d.ownerId = o.OwnerId;
            d.won = o.IsWon;
            d.closeDate = o.CloseDate;
            d.arr = nz(o.ARR_Opportunity_Amount_USD_Num__c);
            d.beforeClose = o.Forecast_Category_before_Close__c;
            deals.add(d);
        }
        return deals;
    }

    private static void fillBandCheckpoints(PagePayload page, List<ClosedDeal> deals) {
        Map<Id, List<SnapPoint>> snaps = loadSnaps(deals);
        Map<Id, List<HistPoint>> hist = loadCategoryHistory(deals);
        Map<Id, CommitAcc> commitByOwner = new Map<Id, CommitAcc>();
        List<String> keys = new List<String>{ CP_M1, CP_M2, CP_M3 };
        Map<String, String> labels = new Map<String, String>{
            CP_M1 => 'First month of the quarter',
            CP_M2 => 'Second month of the quarter',
            CP_M3 => 'Third month of the quarter'
        };
        Map<String, String> captions = new Map<String, String>{
            CP_M1 => 'Forecast category during month 1 of the close quarter, and conversion from that word.',
            CP_M2 => 'Forecast category during month 2 of the close quarter, and conversion from that word.',
            CP_M3 => 'Forecast category during month 3 of the close quarter, and conversion from that word. Commit accuracy uses this month.'
        };

        page.bandCheckpoints = new List<CheckpointTable>();
        List<String> interpretations = new List<String>();
        for (String key : keys) {
            Map<String, BandRow> teamBands = new Map<String, BandRow>();
            Map<String, BandRow> aeBands = new Map<String, BandRow>();
            for (ClosedDeal d : deals) {
                String band = categoryForDeal(d, key, snaps.get(d.id), hist.get(d.id));
                BandRow row = teamBands.get(band);
                if (row == null) {
                    row = new BandRow();
                    row.band = band;
                    teamBands.put(band, row);
                }
                applyOutcome(row, d.won, 1, d.arr);
                String aeKey = String.valueOf(d.ownerId) + '|' + band;
                BandRow aeRow = aeBands.get(aeKey);
                if (aeRow == null) {
                    aeRow = new BandRow();
                    aeRow.band = band;
                    aeBands.put(aeKey, aeRow);
                }
                applyOutcome(aeRow, d.won, 1, d.arr);
                if (key == CP_M3 && band == 'Commit') {
                    CommitAcc ca = commitByOwner.get(d.ownerId);
                    if (ca == null) {
                        ca = new CommitAcc();
                        ca.ownerId = d.ownerId;
                        commitByOwner.put(d.ownerId, ca);
                    }
                    ca.commitCloses++;
                    if (d.won == true) ca.won++;
                }
            }
            CheckpointTable t = new CheckpointTable();
            t.key = key;
            t.label = labels.get(key);
            t.caption = captions.get(key);
            t.rows = orderBands(teamBands);
            finalizeBands(t.rows);
            t.byAe = toAeBandRows(aeBands, page.scope.ownerNames);
            t.interpretation = interpret(t.rows);
            t.explain =
                t.caption + ' '
                + (t.interpretation == null ? 'Refresh to recompute from live Salesforce.' : t.interpretation);
            if (String.isNotBlank(t.interpretation)) {
                interpretations.add(t.label + ': ' + t.interpretation);
            }
            page.bandCheckpoints.add(t);
        }
        page.bands = page.bandCheckpoints.isEmpty()
            ? new List<BandRow>()
            : page.bandCheckpoints[page.bandCheckpoints.size() - 1].rows;
        page.bandInterpretation = interpretations.isEmpty() ? null : String.join(interpretations, ' ');
        page.commitAccuracy = toCommitRows(commitByOwner, page.scope.ownerNames);
    }

    private static String categoryForDeal(
        ClosedDeal d, String key, List<SnapPoint> points, List<HistPoint> hist
    ) {
        String fromSnap = categoryInMonth(points, d.closeDate, key, null);
        if (fromSnap != NOT_ON_FORECAST) return fromSnap;
        Date start = monthStart(d.closeDate, key);
        if (start != null) {
            String fromHist = historyAsOf(hist, start.addMonths(1).addDays(-1));
            if (String.isNotBlank(fromHist)) return normalizeBand(fromHist);
        }
        return categoryInMonth(points, d.closeDate, key, d.beforeClose);
    }

    private static Map<Id, List<SnapPoint>> loadSnaps(List<ClosedDeal> deals) {
        if (snapshotOverride != null) return snapshotOverride;
        Map<Id, List<SnapPoint>> out = new Map<Id, List<SnapPoint>>();
        if (deals == null || deals.isEmpty() || !canReadWeeklySnapshots()) return out;

        List<Id> ids = new List<Id>();
        Date minD;
        Date maxD;
        for (ClosedDeal d : deals) {
            ids.add(d.id);
            Date s = monthStart(d.closeDate, CP_M1);
            Date e = monthStart(d.closeDate, CP_M3);
            if (e != null) e = e.addMonths(1).addDays(-1);
            if (s != null) s = s.addDays(-MONTH_WEEK_OVERLAP_DAYS);
            if (s != null && (minD == null || s < minD)) minD = s;
            if (e != null && (maxD == null || e > maxD)) maxD = e;
        }
        if (minD == null || maxD == null) return out;

        Map<Id, Date> weekStartById = new Map<Id, Date>();
        for (Forecast_Week__c wk : [
            SELECT Id, Week_Start__c FROM Forecast_Week__c
            WHERE Week_Start__c >= :minD AND Week_Start__c <= :maxD
        ]) {
            weekStartById.put(wk.Id, wk.Week_Start__c);
        }
        if (weekStartById.isEmpty()) return out;
        Set<Id> weekIds = weekStartById.keySet();

        for (Integer i = 0; i < ids.size(); i += 200) {
            Integer last = Math.min(i + 200, ids.size());
            List<Id> slice = new List<Id>();
            List<String> textIds = new List<String>();
            for (Integer j = i; j < last; j++) {
                slice.add(ids[j]);
                textIds.add(String.valueOf(ids[j]));
            }
            for (Weekly_Forecast_Snapshot__c w : [
                SELECT Opportunity__c, Opportunity_Id_Text__c, Roll_Up_Forecast__c,
                    Standard_Forecast_Category__c, Bucket__c, Week__c
                FROM Weekly_Forecast_Snapshot__c
                WHERE Week__c IN :weekIds
                AND (Opportunity__c IN :slice OR Opportunity_Id_Text__c IN :textIds)
                LIMIT 10000
            ]) {
                Id oppId = w.Opportunity__c;
                if (oppId == null && String.isNotBlank(w.Opportunity_Id_Text__c)) {
                    try { oppId = (Id) w.Opportunity_Id_Text__c; } catch (Exception e) { oppId = null; }
                }
                if (oppId == null) continue;
                Date ws = weekStartById.get(w.Week__c);
                String cat = firstBand(w.Roll_Up_Forecast__c, w.Standard_Forecast_Category__c, w.Bucket__c);
                if (!out.containsKey(oppId)) out.put(oppId, new List<SnapPoint>());
                out.get(oppId).add(new SnapPoint(ws, cat));
            }
        }
        return out;
    }

    private static Boolean canReadWeeklySnapshots() {
        Schema.SObjectType t = Schema.getGlobalDescribe().get('Weekly_Forecast_Snapshot__c');
        if (t == null) return false;
        Schema.DescribeSObjectResult d = t.getDescribe();
        if (!d.isAccessible()) return false;
        Schema.SObjectField f = d.fields.getMap().get('roll_up_forecast__c');
        return f != null && f.getDescribe().isAccessible();
    }

    private static SnapPoint latestInMonth(List<SnapPoint> points, Date monthStart, Date monthEnd) {
        if (points == null || monthStart == null || monthEnd == null) return null;
        Date windowStart = monthStart.addDays(-MONTH_WEEK_OVERLAP_DAYS);
        SnapPoint best = null;
        for (SnapPoint p : points) {
            if (p == null || p.weekStart == null) continue;
            if (p.weekStart < windowStart || p.weekStart > monthEnd) continue;
            if (best == null || p.weekStart > best.weekStart) best = p;
        }
        return best;
    }

    private static String firstBand(String rollUp, String standard, String bucket) {
        if (String.isNotBlank(rollUp)) return rollUp;
        if (String.isNotBlank(standard)) return standard;
        if (String.isNotBlank(bucket) && bucket != 'Closed Won') return bucket;
        if (bucket == 'Closed Won') return 'Closed';
        return null;
    }

    private static String historyAsOf(List<HistPoint> hist, Date asOf) {
        if (hist == null || asOf == null) return null;
        DateTime cutoff = DateTime.newInstance(asOf, Time.newInstance(23, 59, 59, 0));
        String last;
        for (HistPoint h : hist) {
            if (h.changed != null && h.changed <= cutoff && String.isNotBlank(h.value)) {
                last = h.value;
            }
        }
        return last;
    }

    private static Map<Id, List<HistPoint>> loadCategoryHistory(List<ClosedDeal> deals) {
        Map<Id, List<HistPoint>> out = new Map<Id, List<HistPoint>>();
        if (deals == null || deals.isEmpty()) return out;
        List<Id> ids = new List<Id>();
        for (ClosedDeal d : deals) ids.add(d.id);
        for (Integer i = 0; i < ids.size(); i += 200) {
            Integer last = Math.min(i + 200, ids.size());
            List<Id> slice = new List<Id>();
            for (Integer j = i; j < last; j++) slice.add(ids[j]);
            for (OpportunityFieldHistory h : [
                SELECT OpportunityId, NewValue, CreatedDate
                FROM OpportunityFieldHistory
                WHERE Field = 'ForecastCategoryName' AND OpportunityId IN :slice
                ORDER BY CreatedDate
                LIMIT 10000
            ]) {
                if (!out.containsKey(h.OpportunityId)) out.put(h.OpportunityId, new List<HistPoint>());
                HistPoint p = new HistPoint();
                p.changed = h.CreatedDate;
                p.value = h.NewValue == null ? null : String.valueOf(h.NewValue);
                out.get(h.OpportunityId).add(p);
            }
        }
        return out;
    }

    private static List<AeBandRow> toAeBandRows(Map<String, BandRow> aeBands, Map<Id, String> names) {
        List<AeBandRow> out = new List<AeBandRow>();
        for (String k : aeBands.keySet()) {
            BandRow src = aeBands.get(k);
            finalizeBands(new List<BandRow>{ src });
            List<String> parts = k.split('\\|', 2);
            AeBandRow r = new AeBandRow();
            r.ownerId = (Id) parts[0];
            r.aeName = names != null && names.containsKey(r.ownerId) ? names.get(r.ownerId) : parts[0];
            r.band = src.band;
            r.won = src.won;
            r.lost = src.lost;
            r.total = src.total;
            r.arrWon = src.arrWon;
            r.arrTotal = src.arrTotal;
            r.winRateCount = src.winRateCount;
            r.winRateArr = src.winRateArr;
            out.add(r);
        }
        out.sort(new AeBandSort());
        return out;
    }

    private static void applyOutcome(BandRow row, Boolean won, Integer c, Decimal arr) {
        row.total += c;
        row.arrTotal += arr;
        if (won == true) {
            row.won += c;
            row.arrWon += arr;
        } else {
            row.lost += c;
            row.arrLost += arr;
        }
    }

    private static void finalizeBands(List<BandRow> bands) {
        for (BandRow r : bands) {
            r.winRateCount = r.total == 0 ? null : Decimal.valueOf(r.won).divide(r.total, 4);
            r.winRateArr = (r.arrTotal == null || r.arrTotal == 0)
                ? null
                : r.arrWon.divide(r.arrTotal, 4);
            Decimal countPct = r.winRateCount == null ? 0 : r.winRateCount;
            Decimal arrPct = r.winRateArr == null ? 0 : r.winRateArr;
            r.rateGap = (r.winRateCount == null || r.winRateArr == null)
                ? null
                : (countPct - arrPct).abs();
            r.largeDealsLose = r.rateGap != null
                && r.rateGap > RATE_GAP_POINTS
                && r.winRateArr < r.winRateCount;
        }
    }

    private static List<BandRow> orderBands(Map<String, BandRow> byBand) {
        List<BandRow> out = new List<BandRow>();
        Set<String> seen = new Set<String>();
        for (String name : BAND_ORDER) {
            if (byBand.containsKey(name)) {
                out.add(byBand.get(name));
                seen.add(name);
            }
        }
        List<String> rest = new List<String>(byBand.keySet());
        rest.sort();
        for (String name : rest) {
            if (!seen.contains(name)) out.add(byBand.get(name));
        }
        return out;
    }

    private static List<CommitRow> toCommitRows(Map<Id, CommitAcc> byOwner, Map<Id, String> names) {
        List<CommitRow> out = new List<CommitRow>();
        for (Id oid : byOwner.keySet()) {
            CommitAcc ca = byOwner.get(oid);
            CommitRow r = new CommitRow();
            r.ownerId = oid;
            r.aeName = names.containsKey(oid) ? names.get(oid) : String.valueOf(oid);
            r.won = ca.won;
            r.commitCloses = ca.commitCloses;
            r.rate = commitAccuracy(ca.won, ca.commitCloses);
            r.flagged = r.rate != null && r.rate < COMMIT_FLAG_RATE;
            r.sampleTooltip = r.rate == null
                ? 'Dash until ' + COMMIT_SAMPLE_FLOOR + ' Commit closes (sample is '
                    + ca.commitCloses + '). Never shown as 0%.'
                : null;
            out.add(r);
        }
        out.sort(new CommitSort());
        return out;
    }

    private static void fillLossMatrix(
        PagePayload page,
        List<Id> owners,
        String extra,
        Set<String> solutions,
        Date closedSince,
        String saleRt,
        Set<String> nbTypes,
        List<String> migStages,
        Date qStart,
        Date qEnd
    ) {
        Date floor = LOSS_REASON_FLOOR;
        String soql =
            'SELECT OwnerId oid, Lost_Reason__c lr, COUNT(Id) c '
            + 'FROM Opportunity '
            + 'WHERE IsClosed = true AND IsWon = false AND CloseDate >= :floor '
            + 'AND OwnerId IN :owners '
            + 'AND RecordType.DeveloperName = :saleRt '
            + 'AND Type IN :nbTypes '
            + 'AND StageName NOT IN :migStages '
            + extra
            + ' GROUP BY OwnerId, Lost_Reason__c';

        Map<String, Integer> teamByReason = new Map<String, Integer>();
        Map<Id, Integer> aeTotals = new Map<Id, Integer>();
        Map<Id, Map<String, Integer>> aeByReason = new Map<Id, Map<String, Integer>>();
        Integer teamTotal = 0;

        for (AggregateResult ar : Database.query(soql, AccessLevel.USER_MODE)) {
            Id oid = (Id) ar.get('oid');
            String reason = (String) ar.get('lr');
            String key = String.isBlank(reason) ? '(blank)' : reason;
            Integer c = (Integer) ar.get('c');
            teamTotal += c;
            teamByReason.put(key, (teamByReason.containsKey(key) ? teamByReason.get(key) : 0) + c);
            aeTotals.put(oid, (aeTotals.containsKey(oid) ? aeTotals.get(oid) : 0) + c);
            if (!aeByReason.containsKey(oid)) aeByReason.put(oid, new Map<String, Integer>());
            Map<String, Integer> rm = aeByReason.get(oid);
            rm.put(key, (rm.containsKey(key) ? rm.get(key) : 0) + c);
        }

        List<LossRow> rows = new List<LossRow>();
        for (String reason : teamByReason.keySet()) {
            LossRow r = new LossRow();
            r.reason = reason;
            r.root = rootOf(reason == '(blank)' ? null : reason);
            r.losses = teamByReason.get(reason);
            r.share = teamTotal == 0 ? null : Decimal.valueOf(r.losses).divide(teamTotal, 4);
            r.mapped = r.root != ROOT_UNMAPPED;
            rows.add(r);
        }
        rows.sort(new LossSort());
        page.lossMatrix = rows;

        List<OverIndexRow> flagged = new List<OverIndexRow>();
        for (Id oid : aeByReason.keySet()) {
            Integer aeLosses = aeTotals.get(oid);
            for (String reason : aeByReason.get(oid).keySet()) {
                Integer n = aeByReason.get(oid).get(reason);
                Decimal teamShare = (teamTotal == 0)
                    ? 0
                    : Decimal.valueOf(teamByReason.get(reason)).divide(teamTotal, 4);
                if (isOverIndexed(n, aeLosses, teamShare)) {
                    OverIndexRow x = new OverIndexRow();
                    x.ownerId = oid;
                    x.aeName = page.scope.ownerNames.containsKey(oid)
                        ? page.scope.ownerNames.get(oid)
                        : String.valueOf(oid);
                    x.reason = reason;
                    x.root = rootOf(reason == '(blank)' ? null : reason);
                    x.losses = n;
                    x.share = Decimal.valueOf(n).divide(aeLosses, 4);
                    x.teamShare = teamShare;
                    flagged.add(x);
                }
            }
        }
        page.overIndexed = flagged;
    }

    private static void fillLiveBook(
        PagePayload page,
        List<Id> owners,
        String extra,
        Set<String> solutions,
        String saleRt,
        Set<String> nbTypes,
        List<String> migStages
    ) {
        Boolean hasMedd = canRead('Cockpit_MEDDPICC__c');
        Boolean hasCockpitPush = canRead('Cockpit_Push_Count__c');
        Boolean hasRollUp = canRead('Roll_Up_Forecast_bf__c');
        Boolean hasPushCount = canRead('PushCount');
        page.meddpiccAvailable = hasMedd;
        Date today = Date.today();

        String fields = 'OwnerId, ARR_Opportunity_Amount_USD_Num__c, LastActivityDate, Next_Step_Date_bf__c';
        if (hasRollUp) fields += ', Roll_Up_Forecast_bf__c';
        if (hasPushCount) fields += ', PushCount';
        if (hasMedd) fields += ', Cockpit_MEDDPICC__c';
        if (hasCockpitPush) fields += ', Cockpit_Push_Count__c';

        String soql =
            'SELECT ' + fields + ' FROM Opportunity '
            + 'WHERE IsClosed = false '
            + 'AND OwnerId IN :owners '
            + 'AND RecordType.DeveloperName = :saleRt '
            + 'AND Type IN :nbTypes '
            + 'AND StageName NOT IN :migStages '
            + extra
            + ' LIMIT 2000';

        Map<Id, LiveAcc> byOwner = new Map<Id, LiveAcc>();
        for (Id oid : owners) {
            LiveAcc seed = new LiveAcc();
            seed.ownerId = oid;
            byOwner.put(oid, seed);
        }

        for (Opportunity o : Database.query(soql, AccessLevel.USER_MODE)) {
            LiveAcc a = byOwner.get(o.OwnerId);
            if (a == null) {
                a = new LiveAcc();
                a.ownerId = o.OwnerId;
                byOwner.put(o.OwnerId, a);
            }
            Decimal arr = nz(o.ARR_Opportunity_Amount_USD_Num__c);
            a.dealCount++;
            a.openArr += arr;

            Date touch = o.LastActivityDate;
            if (touch == null || touch > today || touch.daysBetween(today) >= 30) {
                a.silent++;
            }
            if (o.Next_Step_Date_bf__c == null || o.Next_Step_Date_bf__c < today) {
                a.nextLapsed++;
            }
            Decimal pushes = hasCockpitPush
                ? (Decimal) o.get('Cockpit_Push_Count__c')
                : (hasPushCount ? o.PushCount : null);
            if (pushes != null && pushes >= 3) a.pushed++;
            if (hasRollUp && ABOVE_BEST_CASE.contains(o.Roll_Up_Forecast_bf__c)) a.aboveArr += arr;

            if (hasMedd) {
                Decimal medd = (Decimal) o.get('Cockpit_MEDDPICC__c');
                if (medd != null) {
                    a.scored++;
                    a.meddSum += medd;
                    if (medd < 3) a.below3++;
                }
            }
        }

        List<LiveRow> rows = new List<LiveRow>();
        for (Id oid : byOwner.keySet()) {
            LiveAcc a = byOwner.get(oid);
            LiveRow r = new LiveRow();
            r.ownerId = oid;
            r.aeName = page.scope.ownerNames.containsKey(oid)
                ? page.scope.ownerNames.get(oid)
                : String.valueOf(oid);
            r.openArr = a.openArr;
            r.dealCount = a.dealCount;
            r.scoredCount = a.scored;
            r.avgMeddpicc = a.scored == 0 ? null : a.meddSum.divide(a.scored, 2);
            r.shareBelow3 = a.scored == 0 ? null : Decimal.valueOf(a.below3).divide(a.scored, 4);
            r.silentShare = a.dealCount == 0 ? null : Decimal.valueOf(a.silent).divide(a.dealCount, 4);
            r.nextStepShare = a.dealCount == 0 ? null : Decimal.valueOf(a.nextLapsed).divide(a.dealCount, 4);
            r.pushedShare = a.dealCount == 0 ? null : Decimal.valueOf(a.pushed).divide(a.dealCount, 4);
            r.aboveBestCaseShare = (a.openArr == null || a.openArr == 0)
                ? null
                : a.aboveArr.divide(a.openArr, 4);
            r.flags = liveFlags(r);
            rows.add(r);
        }
        rows.sort(new LiveSort());
        page.liveBook = rows;
    }

    private static Integer loadMedianCycle(
        List<Id> owners,
        String extra,
        Set<String> solutions,
        Date closedSince,
        String saleRt,
        Set<String> nbTypes,
        List<String> migStages,
        Date qStart,
        Date qEnd
    ) {
        String soql =
            'SELECT SQL_Datestamp_bf__c, CloseDate FROM Opportunity '
            + 'WHERE IsClosed = true AND IsWon = true '
            + 'AND CloseDate >= :closedSince AND SQL_Datestamp_bf__c != null '
            + 'AND OwnerId IN :owners '
            + 'AND RecordType.DeveloperName = :saleRt '
            + 'AND Type IN :nbTypes '
            + 'AND StageName NOT IN :migStages '
            + extra
            + ' LIMIT 2000';
        List<Integer> days = new List<Integer>();
        for (Opportunity o : Database.query(soql, AccessLevel.USER_MODE)) {
            Integer d = o.SQL_Datestamp_bf__c.daysBetween(o.CloseDate);
            if (d >= 0) days.add(d);
        }
        return medianCycle(days);
    }

    @TestVisible
    static String normalizeProductGroup(String productType) {
        if (String.isBlank(productType) || productType == CockpitConstants.PRODUCT_ALL) return productType;
        if (productType == CockpitConstants.PRODUCT_GROUP_BUDGET
            || productType == CockpitConstants.PRODUCT_GROUP_GRANTS
            || productType == CockpitConstants.PRODUCT_GROUP_PROC_SOURCING
            || productType == CockpitConstants.PRODUCT_GROUP_PROC_MARKET) {
            return productType;
        }
        if (CockpitConstants.SOLUTIONS_BUDGET.contains(productType)) {
            return CockpitConstants.PRODUCT_GROUP_BUDGET;
        }
        if (CockpitConstants.SOLUTIONS_GRANTS.contains(productType)) {
            return CockpitConstants.PRODUCT_GROUP_GRANTS;
        }
        if (CockpitConstants.SOLUTIONS_PROC_SOURCING.contains(productType)) {
            return CockpitConstants.PRODUCT_GROUP_PROC_SOURCING;
        }
        if (CockpitConstants.SOLUTIONS_PROC_MARKET.contains(productType)) {
            return CockpitConstants.PRODUCT_GROUP_PROC_MARKET;
        }
        return productType;
    }

    @TestVisible
    static String productCaption(String productType) {
        if (String.isBlank(productType) || productType == CockpitConstants.PRODUCT_ALL) {
            return 'All products';
        }
        if (productType == CockpitConstants.PRODUCT_GROUP_BUDGET) return 'Budget';
        if (productType == CockpitConstants.PRODUCT_GROUP_GRANTS) return 'Grants';
        if (productType == CockpitConstants.PRODUCT_GROUP_PROC_SOURCING) return 'Procurement Sourcing';
        if (productType == CockpitConstants.PRODUCT_GROUP_PROC_MARKET) return 'Procurement Marketplace';
        return productType;
    }

    private static String extraFilters(String productType, String sizeBand, Date qStart, Date qEnd) {
        String extra = '';
        if (String.isNotBlank(productType) && productType != CockpitConstants.PRODUCT_ALL) {
            extra += ' AND EUNA_Solution__c IN :solutions ';
        }
        if (sizeBand == SIZE_UNDER_50) {
            extra += ' AND ARR_Opportunity_Amount_USD_Num__c < 50000 ';
        } else if (sizeBand == SIZE_50_150) {
            extra += ' AND ARR_Opportunity_Amount_USD_Num__c >= 50000 '
                + 'AND ARR_Opportunity_Amount_USD_Num__c < 150000 ';
        } else if (sizeBand == SIZE_150_PLUS) {
            extra += ' AND ARR_Opportunity_Amount_USD_Num__c >= 150000 ';
        }
        if (qStart != null && qEnd != null) {
            extra += ' AND CloseDate >= :qStart AND CloseDate <= :qEnd ';
        }
        return extra;
    }

    private static String scopeCaption(Scope s) {
        String product = productCaption(s.productType);
        String size = SIZE_ALL;
        if (s.sizeBand == SIZE_UNDER_50) size = 'Under $50k';
        else if (s.sizeBand == SIZE_50_150) size = '$50–150k';
        else if (s.sizeBand == SIZE_150_PLUS) size = '$150k+';
        else size = 'All sizes';
        String who = s.aeSelfFallback ? s.directorName : ('Team of ' + s.directorName);
        String qtr = (String.isBlank(s.closeQuarter) || s.closeQuarter == QUARTER_ALL)
            ? 'All close quarters'
            : s.closeQuarter.replace('-', ' ');
        return who + ' · ' + product + ' · ' + size + ' · ' + qtr;
    }

    private static Boolean isNonAe(User u) {
        String haystack = (
            (u.Title == null ? '' : u.Title) + ' ' +
            (u.Profile == null || u.Profile.Name == null ? '' : u.Profile.Name) + ' ' +
            (u.UserRole == null || u.UserRole.Name == null ? '' : u.UserRole.Name)
        ).toUpperCase();
        for (String token : CockpitConstants.NON_AE_TOKENS) {
            if (haystack.contains(token)) return true;
        }
        return false;
    }

    private static Boolean hasField(String apiName) {
        return canRead(apiName);
    }

    private static Boolean canRead(String apiName) {
        if (String.isBlank(apiName)) return false;
        Schema.SObjectField f = Opportunity.SObjectType.getDescribe()
            .fields.getMap().get(apiName.toLowerCase());
        return f != null && f.getDescribe().isAccessible();
    }

    private static Decimal nz(Decimal d) { return d == null ? 0 : d; }

    private static String pct(Decimal d) {
        return d == null ? '—' : (d * 100).setScale(1) + '%';
    }

    private class CommitSort implements Comparator<CommitRow> {
        public Integer compare(CommitRow a, CommitRow b) {
            return (a.aeName == null ? '' : a.aeName).compareTo(b.aeName == null ? '' : b.aeName);
        }
    }
    private class LossSort implements Comparator<LossRow> {
        public Integer compare(LossRow a, LossRow b) {
            if (a.losses == b.losses) return 0;
            return a.losses > b.losses ? -1 : 1;
        }
    }
    private class LiveSort implements Comparator<LiveRow> {
        public Integer compare(LiveRow a, LiveRow b) {
            Decimal aa = a.openArr == null ? 0 : a.openArr;
            Decimal bb = b.openArr == null ? 0 : b.openArr;
            if (aa == bb) return 0;
            return aa > bb ? -1 : 1;
        }
    }
    private class AeBandSort implements Comparator<AeBandRow> {
        public Integer compare(AeBandRow a, AeBandRow b) {
            Integer nameCmp = (a.aeName == null ? '' : a.aeName)
                .compareTo(b.aeName == null ? '' : b.aeName);
            if (nameCmp != 0) return nameCmp;
            Integer ia = BAND_ORDER.indexOf(a.band);
            Integer ib = BAND_ORDER.indexOf(b.band);
            if (ia < 0) ia = 99;
            if (ib < 0) ib = 99;
            if (ia != ib) return ia < ib ? -1 : 1;
            return (a.band == null ? '' : a.band).compareTo(b.band == null ? '' : b.band);
        }
    }
}
