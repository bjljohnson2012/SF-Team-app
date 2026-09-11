/**
 * Forecasting Hub controller (guide P9, Phase B read-only subset). One cacheable
 * entry point: the director's team pipeline for the current quarter forward nine
 * months, each deal scored on demand, plus the modeled-call number. No MEDDPICC
 * read (heap), no materialized score fields (batch), no override/cohort layers.
 * with sharing + USER_MODE: a director cannot see another director's book.
 */
public with sharing class CockpitForecastController {

    public class Deal {
        @AuraEnabled public Id id;
        @AuraEnabled public String account, ae, stage, band, klass, reason, nextStep, bucket;
        @AuraEnabled public String overrideCls, overrideNote;
        @AuraEnabled public Boolean inCall, reviewDone;
        @AuraEnabled public Decimal arr, pushes;
        @AuraEnabled public Integer score;
        @AuraEnabled public Date closeDate;
    }

    public class Payload {
        @AuraEnabled public List<Deal> deals;
        @AuraEnabled public List<String> aeNames;
        @AuraEnabled public Integer teamSize;
        @AuraEnabled public String qLabelA, qLabelB, qLabelC;
    }

    public class QuarterRow {
        @AuraEnabled public String label;
        @AuraEnabled public Decimal bookedArr, createdArr;
        @AuraEnabled public Integer bookedN, createdN;
    }

    public class BandRow {
        @AuraEnabled public String band;
        @AuraEnabled public Integer total, won;
        @AuraEnabled public Decimal totalArr, wonArr, winRate, winRateArr;
    }

    @AuraEnabled(cacheable=true)
    public static Payload load() {
        Set<Id> owners = CockpitRosterService.teamIds(UserInfo.getUserId());
        if (owners.isEmpty()) {
            throw new AuraHandledException(
                'No active direct reports found. The Forecasting Hub is for sales directors.');
        }

        Date today = Date.today();
        Integer q = CockpitConstants.quarterOf(today);
        Date winStart = CockpitConstants.quarterStart(today.year(), q);
        Date bStart = winStart.addMonths(3);   // start of next quarter
        Date cStart = winStart.addMonths(6);    // start of quarter after
        Date winEnd = winStart.addMonths(9).addDays(-1);

        List<Opportunity> opps = [
            SELECT Id, Name, Account.Name, Owner.Name, StageName, CloseDate,
                   ForecastCategoryName, ARR_Opportunity_Amount_USD_Num__c,
                   Pricing_Approval_Status__c, SQL_Datestamp_bf__c,
                   Next_Step_Date_bf__c, Next_Step_bf__c, LastActivityDate,
                   Cockpit_In_Call__c, Cockpit_Class_Override__c, Cockpit_Override_Note__c
            FROM Opportunity
            WHERE IsClosed = false
              AND OwnerId IN :owners
              AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
              AND CloseDate >= :winStart AND CloseDate <= :winEnd
            WITH USER_MODE
            ORDER BY ARR_Opportunity_Amount_USD_Num__c DESC NULLS LAST
            LIMIT 800
        ];

        Map<Id, Decimal> pushMap = pushCounts(new Map<Id, Opportunity>(opps).keySet());

        Payload p = new Payload();
        p.deals = new List<Deal>();
        p.teamSize = owners.size();

        for (Opportunity o : opps) {
            Decimal pushes = pushMap.containsKey(o.Id) ? pushMap.get(o.Id) : 0;
            CockpitScoreService.Result r = CockpitScoreService.score(o, null, pushes, today);

            Deal d = new Deal();
            d.id        = o.Id;
            d.account   = (o.Account != null) ? o.Account.Name : o.Name;
            d.ae        = (o.Owner != null) ? o.Owner.Name : null;
            d.stage     = o.StageName;
            d.band      = o.ForecastCategoryName;
            d.arr       = o.ARR_Opportunity_Amount_USD_Num__c;
            d.closeDate = o.CloseDate;
            d.nextStep  = o.Next_Step_bf__c;
            d.pushes    = pushes;
            d.score     = r.score;
            d.klass     = r.klass;
            d.reason    = r.reason;
            d.bucket    = (o.CloseDate < bStart) ? 'A' : (o.CloseDate < cStart ? 'B' : 'C');
            d.inCall      = o.Cockpit_In_Call__c;
            d.overrideCls = o.Cockpit_Class_Override__c;
            d.overrideNote = o.Cockpit_Override_Note__c;
            p.deals.add(d);
        }

        Set<Id> reviewed = PricingReviewController.reviewedOppIds(new Map<Id, Opportunity>(opps).keySet());
        for (Deal d : p.deals) d.reviewDone = reviewed.contains(d.id);

        List<String> names = new List<String>();
        for (CockpitRosterService.Member m : CockpitRosterService.teamFor(UserInfo.getUserId())) {
            names.add(m.name);
        }
        p.aeNames = names;

        p.qLabelA = 'Q' + q + ' ' + today.year();
        Integer qb = (q == 4) ? 1 : q + 1;
        Integer yb = (q == 4) ? today.year() + 1 : today.year();
        p.qLabelB = 'Q' + qb + ' ' + yb;
        Integer qc = (qb == 4) ? 1 : qb + 1;
        Integer yc = (qb == 4) ? yb + 1 : yb;
        p.qLabelC = 'Q' + qc + ' ' + yc;
        return p;
    }

    /**
     * Phase B push counts from OpportunityFieldHistory for the displayed deals.
     * Bounded to one team's open pipeline so the 2,000-group aggregate cap is not
     * a risk. Phase A replaces this with the Cockpit_Push_Count__c trigger/field.
     */
    private static Map<Id, Decimal> pushCounts(Set<Id> oppIds) {
        Map<Id, Decimal> m = new Map<Id, Decimal>();
        if (oppIds.isEmpty() || oppIds.size() > 1500) return m;
        for (AggregateResult ar : [
            SELECT OpportunityId oid, COUNT(Id) c
            FROM OpportunityFieldHistory
            WHERE Field = 'CloseDate' AND OpportunityId IN :oppIds
            GROUP BY OpportunityId
        ]) {
            Decimal c = (Integer) ar.get('c');
            m.put((Id) ar.get('oid'), c);
        }
        return m;
    }

    // ---- persistence: the director's fill-in fields, stored on the record ----

    @AuraEnabled
    public static void setInCall(Id opportunityId, Boolean included) {
        if (opportunityId == null) throw new AuraHandledException('An opportunity id is required.');
        Database.update(
            new Opportunity(Id = opportunityId, Cockpit_In_Call__c = (included == true)),
            AccessLevel.USER_MODE);
    }

    @AuraEnabled
    public static void setOverride(Id opportunityId, String klass, String note) {
        if (opportunityId == null) throw new AuraHandledException('An opportunity id is required.');
        String k = String.isBlank(klass) ? null : klass;
        Database.update(
            new Opportunity(Id = opportunityId,
                Cockpit_Class_Override__c = k,
                Cockpit_Override_Note__c = (k == null ? null : note)),
            AccessLevel.USER_MODE);
    }

    /** Sets Cockpit_In_Call__c to the engine/override default (HI/MD) for the given bucket. */
    @AuraEnabled
    public static Integer applyDefaultPicks(String bucket) {
        Set<Id> owners = CockpitRosterService.teamIds(UserInfo.getUserId());
        if (owners.isEmpty()) throw new AuraHandledException('No active direct reports found.');
        Date today = Date.today();
        Integer q = CockpitConstants.quarterOf(today);
        Date winStart = CockpitConstants.quarterStart(today.year(), q);
        Date bStart = winStart.addMonths(3);
        Date cStart = winStart.addMonths(6);
        Date winEnd = winStart.addMonths(9).addDays(-1);

        Map<Id, Decimal> pushMap = new Map<Id, Decimal>();
        List<Opportunity> updates = new List<Opportunity>();
        for (Opportunity o : [
            SELECT Id, StageName, CloseDate, ARR_Opportunity_Amount_USD_Num__c,
                   Pricing_Approval_Status__c, SQL_Datestamp_bf__c, Next_Step_Date_bf__c,
                   LastActivityDate, Cockpit_Class_Override__c
            FROM Opportunity
            WHERE IsClosed = false AND OwnerId IN :owners
              AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
              AND CloseDate >= :winStart AND CloseDate <= :winEnd
            WITH USER_MODE
        ]) {
            String bk = (o.CloseDate < bStart) ? 'A' : (o.CloseDate < cStart ? 'B' : 'C');
            if (bucket != null && bucket != bk) continue;
            String cls = String.isNotBlank(o.Cockpit_Class_Override__c)
                ? o.Cockpit_Class_Override__c
                : CockpitScoreService.score(o, null, 0, today).klass;
            updates.add(new Opportunity(Id = o.Id, Cockpit_In_Call__c = (cls == 'HI' || cls == 'MD')));
        }
        if (!updates.isEmpty()) Database.update(updates, AccessLevel.USER_MODE);
        return updates.size();
    }

    // ---- analytics (read-only, aggregate; sharing enforced by the class) ----

    @AuraEnabled(cacheable=true)
    public static List<QuarterRow> getCreatedPipeline() {
        Set<Id> owners = CockpitRosterService.teamIds(UserInfo.getUserId());
        if (owners.isEmpty()) return new List<QuarterRow>();
        Date since = Date.today().addMonths(-24).toStartOfMonth();
        Map<String, QuarterRow> rows = new Map<String, QuarterRow>();
        for (AggregateResult ar : [
            SELECT CALENDAR_YEAR(CloseDate) y, CALENDAR_QUARTER(CloseDate) q,
                   COUNT(Id) c, SUM(ARR_Opportunity_Amount_USD_Num__c) arr
            FROM Opportunity
            WHERE IsClosed = true AND IsWon = true AND OwnerId IN :owners
              AND CloseDate >= :since AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
            GROUP BY CALENDAR_YEAR(CloseDate), CALENDAR_QUARTER(CloseDate)
        ]) {
            QuarterRow r = rowFor(rows, (Integer) ar.get('y'), (Integer) ar.get('q'));
            r.bookedN = (Integer) ar.get('c');
            r.bookedArr = (Decimal) ar.get('arr');
        }
        for (AggregateResult ar : [
            SELECT CALENDAR_YEAR(SQL_Datestamp_bf__c) y, CALENDAR_QUARTER(SQL_Datestamp_bf__c) q,
                   COUNT(Id) c, SUM(ARR_Opportunity_Amount_USD_Num__c) arr
            FROM Opportunity
            WHERE OwnerId IN :owners AND SQL_Datestamp_bf__c >= :since
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
            GROUP BY CALENDAR_YEAR(SQL_Datestamp_bf__c), CALENDAR_QUARTER(SQL_Datestamp_bf__c)
        ]) {
            QuarterRow r = rowFor(rows, (Integer) ar.get('y'), (Integer) ar.get('q'));
            r.createdN = (Integer) ar.get('c');
            r.createdArr = (Decimal) ar.get('arr');
        }
        List<QuarterRow> out = rows.values();
        out.sort(new QuarterRowSort());
        return out;
    }

    private static QuarterRow rowFor(Map<String, QuarterRow> rows, Integer y, Integer q) {
        String key = y + 'Q' + q;
        QuarterRow r = rows.get(key);
        if (r == null) {
            r = new QuarterRow();
            r.label = 'Q' + q + ' ' + y;
            r.bookedArr = 0; r.createdArr = 0; r.bookedN = 0; r.createdN = 0;
            rows.put(key, r);
        }
        return r;
    }

    public class QuarterRowSort implements Comparator<QuarterRow> {
        public Integer compare(QuarterRow a, QuarterRow b) { return a.label.compareTo(b.label); }
    }

    @AuraEnabled(cacheable=true)
    public static List<BandRow> getConversion() {
        Set<Id> owners = CockpitRosterService.teamIds(UserInfo.getUserId());
        if (owners.isEmpty()) return new List<BandRow>();
        Date since = Date.today().addMonths(-24).toStartOfMonth();
        Map<String, BandRow> byBand = new Map<String, BandRow>();
        for (AggregateResult ar : [
            SELECT Forecast_Category_before_Close__c b, IsWon w,
                   COUNT(Id) c, SUM(ARR_Opportunity_Amount_USD_Num__c) arr
            FROM Opportunity
            WHERE IsClosed = true AND OwnerId IN :owners AND CloseDate >= :since
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
            GROUP BY Forecast_Category_before_Close__c, IsWon
        ]) {
            String band = (String) ar.get('b');
            if (String.isBlank(band)) band = 'Unknown';
            BandRow r = byBand.get(band);
            if (r == null) {
                r = new BandRow();
                r.band = band; r.total = 0; r.won = 0; r.totalArr = 0; r.wonArr = 0;
                byBand.put(band, r);
            }
            Integer c = (Integer) ar.get('c');
            Decimal arr = (Decimal) ar.get('arr');
            r.total += c;
            r.totalArr += (arr == null ? 0 : arr);
            if ((Boolean) ar.get('w')) { r.won += c; r.wonArr += (arr == null ? 0 : arr); }
        }
        List<BandRow> out = new List<BandRow>();
        for (String band : new List<String>{ 'Commit', 'Most Likely', 'Best Case', 'Pipeline', 'Omitted' }) {
            if (byBand.containsKey(band)) { finalizeBand(byBand.get(band)); out.add(byBand.remove(band)); }
        }
        for (BandRow r : byBand.values()) { finalizeBand(r); out.add(r); }
        return out;
    }

    private static void finalizeBand(BandRow r) {
        r.winRate = r.total == 0 ? 0 : ((Decimal) r.won).divide(r.total, 4);
        r.winRateArr = (r.totalArr == null || r.totalArr == 0) ? 0 : r.wonArr.divide(r.totalArr, 4);
    }

    // ---- loss-reason -> root cause (ported from the cockpit DEFAULT_ROOT) ----
    private static final Map<String, String> LOSS_ROOT = new Map<String, String>{
        'Opportunity not Qualified' => 'QUAL', 'Insufficient Data' => 'QUAL', 'Not Qualified' => 'QUAL', 'Disqualified' => 'QUAL',
        'Ghosted' => 'ENGAGE', 'No Decision / deferred' => 'ENGAGE', 'No Decision' => 'ENGAGE', 'No Response' => 'ENGAGE', 'Deferred' => 'ENGAGE',
        'Perceived lack of ROI' => 'VALUE', 'Price' => 'VALUE', 'Budget' => 'VALUE', 'No Budget' => 'VALUE',
        'Product Related Reasons' => 'FIT', 'Product Gap' => 'FIT', 'Missing Functionality' => 'FIT',
        'Upper Management pushback' => 'EB',
        'Strength of Competitor Relationship' => 'COMP', 'Lost to Competitor' => 'COMP',
        'Entered process too late' => 'TIMING', 'RFP Related' => 'TIMING', 'Timing' => 'TIMING',
        'Contracting Issues' => 'PAPER', 'Compliance Issues' => 'PAPER', 'Legal' => 'PAPER', 'Security Review' => 'PAPER',
        'Duplicate Opportunity' => 'DUPE', 'Duplicate' => 'DUPE', 'Test' => 'DUPE'
    };
    private static String rootOf(String reason) {
        if (String.isBlank(reason)) return 'UNMAPPED';
        String r = LOSS_ROOT.get(reason);
        return r == null ? 'UNMAPPED' : r;
    }
    // Never-real = never a real deal: unqualified or duplicate. Excluded from contested win rate.
    private static Boolean isNeverReal(String reason) {
        if (String.isBlank(reason)) return true;
        String r = rootOf(reason);
        return r == 'QUAL' || r == 'DUPE';
    }

    public class CohortRow {
        @AuraEnabled public String label;
        @AuraEnabled public Integer created = 0, won = 0, worked = 0, never = 0, stillOpen = 0;
        @AuraEnabled public Decimal cohortWR, resolvedWR, contestedWR, qualYield;
    }

    /** Creation-cohort win rate: follows opps forward from the SQL gate, four denominators. */
    @AuraEnabled(cacheable=true)
    public static List<CohortRow> getWinRateTruth() {
        Set<Id> owners = CockpitRosterService.teamIds(UserInfo.getUserId());
        if (owners.isEmpty()) return new List<CohortRow>();
        Date since = Date.today().addMonths(-24).toStartOfMonth();
        Map<String, CohortRow> byQ = new Map<String, CohortRow>();
        CohortRow team = new CohortRow();
        team.label = 'Team (all cohorts)';
        for (Opportunity o : [
            SELECT SQL_Datestamp_bf__c, IsClosed, IsWon, Lost_Reason__c
            FROM Opportunity
            WHERE OwnerId IN :owners AND SQL_Datestamp_bf__c >= :since
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
        ]) {
            Date s = o.SQL_Datestamp_bf__c;
            String key = s.year() + 'Q' + CockpitConstants.quarterOf(s);
            CohortRow r = byQ.get(key);
            if (r == null) { r = new CohortRow(); r.label = 'Q' + CockpitConstants.quarterOf(s) + ' ' + s.year(); byQ.put(key, r); }
            for (CohortRow b : new List<CohortRow>{ r, team }) {
                b.created++;
                if (!o.IsClosed) b.stillOpen++;
                else if (o.IsWon) b.won++;
                else if (isNeverReal(o.Lost_Reason__c)) b.never++;
                else b.worked++;
            }
        }
        List<CohortRow> out = byQ.values();
        for (CohortRow r : out) rates(r);
        rates(team);
        out.sort(new CohortSort());
        out.add(0, team);
        return out;
    }
    private static void rates(CohortRow r) {
        Integer resolved = r.won + r.worked + r.never;
        Integer contested = r.won + r.worked;
        r.cohortWR    = r.created == 0 ? null : ((Decimal) r.won).divide(r.created, 4);
        r.resolvedWR  = resolved == 0 ? null : ((Decimal) r.won).divide(resolved, 4);
        r.contestedWR = contested == 0 ? null : ((Decimal) r.won).divide(contested, 4);
        r.qualYield   = r.created == 0 ? null : ((Decimal) contested).divide(r.created, 4);
    }
    public class CohortSort implements Comparator<CohortRow> {
        public Integer compare(CohortRow a, CohortRow b) { return a.label.compareTo(b.label); }
    }

    public class AeRow {
        @AuraEnabled public String ae, topRoot;
        @AuraEnabled public Integer won = 0, lost = 0;
        @AuraEnabled public Decimal wonArr = 0, lostArr = 0, winRate;
    }

    /** Per-AE closed-business conversion and dominant loss root cause, trailing 24 months. */
    @AuraEnabled(cacheable=true)
    public static List<AeRow> getAeConversion() {
        Set<Id> owners = CockpitRosterService.teamIds(UserInfo.getUserId());
        if (owners.isEmpty()) return new List<AeRow>();
        Date since = Date.today().addMonths(-24).toStartOfMonth();
        Map<String, AeRow> byAe = new Map<String, AeRow>();
        Map<String, Map<String, Integer>> rootByAe = new Map<String, Map<String, Integer>>();
        for (AggregateResult ar : [
            SELECT Owner.Name n, IsWon w, Lost_Reason__c lr,
                   COUNT(Id) c, SUM(ARR_Opportunity_Amount_USD_Num__c) arr
            FROM Opportunity
            WHERE IsClosed = true AND OwnerId IN :owners AND CloseDate >= :since
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
            GROUP BY Owner.Name, IsWon, Lost_Reason__c
        ]) {
            String name = (String) ar.get('n');
            if (String.isBlank(name)) continue;
            AeRow r = byAe.get(name);
            if (r == null) { r = new AeRow(); r.ae = name; byAe.put(name, r); rootByAe.put(name, new Map<String, Integer>()); }
            Integer c = (Integer) ar.get('c');
            Decimal arr = (Decimal) ar.get('arr');
            if ((Boolean) ar.get('w')) {
                r.won += c; r.wonArr += (arr == null ? 0 : arr);
            } else {
                String root = rootOf((String) ar.get('lr'));
                if (root == 'DUPE') continue;
                r.lost += c; r.lostArr += (arr == null ? 0 : arr);
                Map<String, Integer> rc = rootByAe.get(name);
                rc.put(root, (rc.containsKey(root) ? rc.get(root) : 0) + c);
            }
        }
        for (String name : byAe.keySet()) {
            AeRow r = byAe.get(name);
            Integer denom = r.won + r.lost;
            r.winRate = denom == 0 ? null : ((Decimal) r.won).divide(denom, 4);
            String top = null; Integer best = -1;
            for (String root : rootByAe.get(name).keySet()) {
                if (rootByAe.get(name).get(root) > best) { best = rootByAe.get(name).get(root); top = root; }
            }
            r.topRoot = top;
        }
        List<AeRow> out = byAe.values();
        out.sort(new AeSort());
        return out;
    }
    public class AeSort implements Comparator<AeRow> {
        public Integer compare(AeRow a, AeRow b) {
            if (a.wonArr == b.wonArr) return 0;
            return (a.wonArr < b.wonArr) ? 1 : -1;
        }
    }

    public class ProblemRow {
        @AuraEnabled public String reason, root;
        @AuraEnabled public Integer count;
        @AuraEnabled public Boolean mapped;
    }

    /** Loss-reason inventory for the Problems tab; UNMAPPED reasons are surfaced loudly. */
    @AuraEnabled(cacheable=true)
    public static List<ProblemRow> getProblems() {
        Set<Id> owners = CockpitRosterService.teamIds(UserInfo.getUserId());
        if (owners.isEmpty()) return new List<ProblemRow>();
        Date since = Date.today().addMonths(-24).toStartOfMonth();
        List<ProblemRow> out = new List<ProblemRow>();
        for (AggregateResult ar : [
            SELECT Lost_Reason__c lr, COUNT(Id) c
            FROM Opportunity
            WHERE IsClosed = true AND IsWon = false AND OwnerId IN :owners
              AND CloseDate >= :since AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
            GROUP BY Lost_Reason__c
            ORDER BY COUNT(Id) DESC
        ]) {
            ProblemRow r = new ProblemRow();
            r.reason = String.isBlank((String) ar.get('lr')) ? '(blank)' : (String) ar.get('lr');
            r.count = (Integer) ar.get('c');
            r.root = rootOf((String) ar.get('lr'));
            r.mapped = r.root != 'UNMAPPED';
            out.add(r);
        }
        return out;
    }

    /** Recent closed-won deals for the Closed-Won pipeline view. */
    @AuraEnabled(cacheable=true)
    public static List<Deal> getClosedWon() {
        Set<Id> owners = CockpitRosterService.teamIds(UserInfo.getUserId());
        if (owners.isEmpty()) return new List<Deal>();
        Date since = Date.today().addMonths(-12).toStartOfMonth();
        List<Deal> out = new List<Deal>();
        for (Opportunity o : [
            SELECT Id, Name, Account.Name, Owner.Name, StageName, CloseDate,
                   ARR_Opportunity_Amount_USD_Num__c
            FROM Opportunity
            WHERE IsClosed = true AND IsWon = true AND OwnerId IN :owners
              AND CloseDate >= :since AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
            ORDER BY CloseDate DESC
            LIMIT 200
        ]) {
            Deal d = new Deal();
            d.id = o.Id;
            d.account = (o.Account != null) ? o.Account.Name : o.Name;
            d.ae = (o.Owner != null) ? o.Owner.Name : null;
            d.stage = o.StageName;
            d.arr = o.ARR_Opportunity_Amount_USD_Num__c;
            d.closeDate = o.CloseDate;
            out.add(d);
        }
        return out;
    }

    // ---- AI: Claude-powered coaching over the team's own numbers ----

    @AuraEnabled
    public static String analyzePerformance(String area) {
        String ctx;
        if (area == 'conversion') {
            ctx = 'BAND WIN RATES (band held before close):\n';
            for (BandRow b : getConversion()) {
                ctx += '  ' + b.band + ': ' + pct(b.winRate) + ' by count (' + b.won + '/' + b.total
                     + '), ' + pct(b.winRateArr) + ' by ARR\n';
            }
            List<CohortRow> wr = getWinRateTruth();
            if (!wr.isEmpty()) {
                CohortRow t = wr[0];
                ctx += 'CREATION COHORT (team): cohort WR ' + pct(t.cohortWR) + ', contested WR '
                     + pct(t.contestedWR) + ', qualification yield ' + pct(t.qualYield)
                     + ' (created ' + t.created + ', won ' + t.won + ', worked ' + t.worked
                     + ', never-real ' + t.never + ')\n';
            }
            ctx += 'PER AE (trailing 24mo):\n';
            for (AeRow a : getAeConversion()) {
                ctx += '  ' + a.ae + ': win ' + pct(a.winRate) + ', won ' + a.won + ', lost '
                     + a.lost + ', dominant loss cause ' + a.topRoot + '\n';
            }
        } else if (area == 'pipeline') {
            ctx = 'CREATED vs BOOKED by quarter (new-business ARR):\n';
            for (QuarterRow r : getCreatedPipeline()) {
                ctx += '  ' + r.label + ': created ' + r.createdN + '/$' + fmt(r.createdArr)
                     + ', booked ' + r.bookedN + '/$' + fmt(r.bookedArr) + '\n';
            }
        } else {
            Payload p = load();
            Date today = Date.today();
            Integer hi = 0, md = 0, ex = 0;
            Decimal hiArr = 0, mdArr = 0;
            for (Deal d : p.deals) {
                if (d.bucket != 'A') continue;
                String cls = String.isNotBlank(d.overrideCls) ? d.overrideCls : d.klass;
                if (cls == 'HI') { hi++; hiArr += (d.arr == null ? 0 : d.arr); }
                else if (cls == 'MD') { md++; mdArr += (d.arr == null ? 0 : d.arr); }
                else ex++;
            }
            ctx = 'CURRENT QUARTER (' + p.qLabelA + ') team pipeline: '
                + hi + ' Include-High ($' + fmt(hiArr) + '), '
                + md + ' Include-Med ($' + fmt(mdArr) + '), ' + ex + ' Exclude. Team of '
                + p.teamSize + ' AEs, ' + p.deals.size() + ' open deals in window.\n';
        }
        String prompt = 'You are a blunt, experienced sales forecasting coach for a sales director at a '
            + 'govtech company. Using ONLY the team data below, give 3 to 5 specific, actionable insights '
            + 'as short bullet points (each one sentence). Call out the single biggest risk. Do not restate '
            + 'the numbers back; interpret them.\n\n' + ctx;
        try {
            return AnthropicService.complete(prompt);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static String pct(Decimal d) { return d == null ? '-' : (d * 100).setScale(1) + '%'; }
    private static String fmt(Decimal d) { return d == null ? '0' : String.valueOf(d.setScale(0)); }

    public class ForecastSummary {
        @AuraEnabled public String qLabelA, qLabelB;
        @AuraEnabled public Integer daysLeftA = 0, bookedNA = 0, bookedNB = 0, medianCycle = 0;
        @AuraEnabled public Decimal pctElapsedA = 0, bookedArrA = 0, bookedArrB = 0, newPipelineEstA = 0;
    }

    /** Header + build inputs for the forecast Summary: booked-to-date, quarter clock,
     *  and a trailing estimate of new pipeline created AND closed inside a quarter. */
    @AuraEnabled(cacheable=true)
    public static ForecastSummary getForecastSummary() {
        ForecastSummary s = new ForecastSummary();
        Set<Id> owners = CockpitRosterService.teamIds(UserInfo.getUserId());
        Date today = Date.today();
        Integer q = CockpitConstants.quarterOf(today);
        Date qStartA = CockpitConstants.quarterStart(today.year(), q);
        Date qEndA = qStartA.addMonths(3).addDays(-1);
        Date qStartB = qStartA.addMonths(3);
        Date qEndB = qStartA.addMonths(6).addDays(-1);
        s.qLabelA = 'Q' + q + ' ' + today.year();
        Integer qb = (q == 4) ? 1 : q + 1;
        Integer yb = (q == 4) ? today.year() + 1 : today.year();
        s.qLabelB = 'Q' + qb + ' ' + yb;
        s.daysLeftA = today.daysBetween(qEndA);
        Integer tot = qStartA.daysBetween(qEndA);
        s.pctElapsedA = tot == 0 ? 0 : ((Decimal) qStartA.daysBetween(today)).divide(tot, 4);
        if (owners.isEmpty()) return s;

        for (AggregateResult ar : [
            SELECT COUNT(Id) c, SUM(ARR_Opportunity_Amount_USD_Num__c) arr
            FROM Opportunity WHERE IsClosed = true AND IsWon = true AND OwnerId IN :owners
              AND CloseDate >= :qStartA AND CloseDate <= :qEndA AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
        ]) { s.bookedNA = (Integer) ar.get('c'); s.bookedArrA = nz((Decimal) ar.get('arr')); }
        for (AggregateResult ar : [
            SELECT COUNT(Id) c, SUM(ARR_Opportunity_Amount_USD_Num__c) arr
            FROM Opportunity WHERE IsClosed = true AND IsWon = true AND OwnerId IN :owners
              AND CloseDate >= :qStartB AND CloseDate <= :qEndB AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
        ]) { s.bookedNB = (Integer) ar.get('c'); s.bookedArrB = nz((Decimal) ar.get('arr')); }

        // Trailing 4 quarters: deals both created (SQL gate) and won inside one quarter.
        Date since = qStartA.addMonths(-12);
        Decimal inQ = 0;
        List<Integer> cycles = new List<Integer>();
        for (Opportunity o : [
            SELECT SQL_Datestamp_bf__c, CloseDate, ARR_Opportunity_Amount_USD_Num__c
            FROM Opportunity WHERE IsClosed = true AND IsWon = true AND OwnerId IN :owners
              AND CloseDate >= :since AND CloseDate < :qStartA AND SQL_Datestamp_bf__c != null
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
        ]) {
            Integer d = o.SQL_Datestamp_bf__c.daysBetween(o.CloseDate);
            if (d >= 0) cycles.add(d);
            Date sd = o.SQL_Datestamp_bf__c;
            if (sd.year() == o.CloseDate.year() && CockpitConstants.quarterOf(sd) == CockpitConstants.quarterOf(o.CloseDate)) {
                inQ += nz(o.ARR_Opportunity_Amount_USD_Num__c);
            }
        }
        s.newPipelineEstA = inQ.divide(4, 0);
        if (!cycles.isEmpty()) { cycles.sort(); s.medianCycle = cycles[cycles.size() / 2]; }
        return s;
    }
    private static Decimal nz(Decimal d) { return d == null ? 0 : d; }

    // ---- admin: who can access the app and do what ----
    public class AccessUser {
        @AuraEnabled public String name, username, profile;
        @AuraEnabled public Boolean active;
    }
    public class AccessInfo {
        @AuraEnabled public List<AccessUser> users = new List<AccessUser>();
        @AuraEnabled public List<String> tabs = new List<String>();
        @AuraEnabled public List<String> activities = new List<String>();
        @AuraEnabled public Boolean editInCall = false, overrideClass = false, apexAccess = false;
        @AuraEnabled public String permSet = 'GTM_Team_Johnson_Access';
    }

    @AuraEnabled(cacheable=true)
    public static AccessInfo getAccessMatrix() {
        AccessInfo info = new AccessInfo();
        for (PermissionSetAssignment psa : [
            SELECT Assignee.Name, Assignee.Username, Assignee.IsActive, Assignee.Profile.Name
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'GTM_Team_Johnson_Access' AND Assignee.IsActive = true
            ORDER BY Assignee.Name
        ]) {
            AccessUser u = new AccessUser();
            u.name = psa.Assignee.Name;
            u.username = psa.Assignee.Username;
            u.profile = psa.Assignee.Profile.Name;
            u.active = psa.Assignee.IsActive;
            info.users.add(u);
        }
        for (FieldPermissions fp : [
            SELECT Field, PermissionsEdit FROM FieldPermissions
            WHERE Parent.Name = 'GTM_Team_Johnson_Access'
        ]) {
            if (fp.Field == 'Opportunity.Cockpit_In_Call__c' && fp.PermissionsEdit) info.editInCall = true;
            if (fp.Field == 'Opportunity.Cockpit_Class_Override__c' && fp.PermissionsEdit) info.overrideClass = true;
        }
        for (SetupEntityAccess sea : [
            SELECT SetupEntityType FROM SetupEntityAccess
            WHERE Parent.Name = 'GTM_Team_Johnson_Access' AND SetupEntityType = 'ApexClass' LIMIT 1
        ]) { info.apexAccess = true; }

        info.tabs = new List<String>{ 'Main (Team Opportunity Insights)', 'Sales Performance', 'Admin' };
        info.activities.add('View Forecast, Pipeline & Conversion sub-tabs');
        if (info.editInCall) info.activities.add('Tick deals into the call (Cockpit_In_Call__c)');
        if (info.overrideClass) info.activities.add('Override deal classification (Cockpit_Class_Override__c)');
        info.activities.add('Run Claude AI insight on each section');
        info.activities.add('Adjust weights & submitted call (session)');
        return info;
    }
}
