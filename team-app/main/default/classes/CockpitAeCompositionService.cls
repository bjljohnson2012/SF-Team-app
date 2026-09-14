/**
 * Live AE composition: where each rep's number comes from right now, plus
 * 1:1 signals. This tab does not persist scores; override wins over class.
 */
public with sharing class CockpitAeCompositionService {

    @TestVisible static Boolean liveScoreIfClassMissing = true;
    @TestVisible static Map<Id, Integer> testMeddpiccByOpp = new Map<Id, Integer>();

    public class ScopeRequest {
        @AuraEnabled public Id directorId;
        @AuraEnabled public String teamMode;
        @AuraEnabled public String productType;
        @AuraEnabled public String sizeBand;
    }

    public class BandCell {
        @AuraEnabled public Integer deals = 0;
        @AuraEnabled public Decimal arr = 0;
        @AuraEnabled public Decimal share;
    }

    public class QuarterSlice {
        @AuraEnabled public String label;
        @AuraEnabled public Boolean showBooked;
        @AuraEnabled public Decimal bookedArr = 0;
        @AuraEnabled public Integer bookedN = 0;
        @AuraEnabled public Decimal openArr = 0;
        @AuraEnabled public Integer openN = 0;
        @AuraEnabled public Decimal holdoverArr = 0;
        @AuraEnabled public Integer holdoverN = 0;
        @AuraEnabled public BandCell commitBand;
        @AuraEnabled public BandCell mostLikely;
        @AuraEnabled public BandCell bestCase;
        @AuraEnabled public BandCell pipeline;
        @AuraEnabled public BandCell omitted;
        @AuraEnabled public BandCell unbanded;
        @AuraEnabled public Decimal includeHighArr = 0;
        @AuraEnabled public Decimal includeMedArr = 0;
        @AuraEnabled public Decimal excludeArr = 0;
        @AuraEnabled public Integer includeHighN = 0;
        @AuraEnabled public Integer includeMedN = 0;
        @AuraEnabled public Integer excludeN = 0;
        @AuraEnabled public Decimal evidenceCall = 0;
        public QuarterSlice() {
            commitBand = new BandCell();
            mostLikely = new BandCell();
            bestCase = new BandCell();
            pipeline = new BandCell();
            omitted = new BandCell();
            unbanded = new BandCell();
        }
    }

    public class Signal {
        @AuraEnabled public String code;
        @AuraEnabled public String fact;
    }

    public class AeRow {
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String name;
        @AuraEnabled public QuarterSlice currentQ;
        @AuraEnabled public QuarterSlice nextQ;
        @AuraEnabled public List<Signal> signals;
        @AuraEnabled public String cleanBook;
    }

    public class Payload {
        @AuraEnabled public String scopeCaption;
        @AuraEnabled public String directorName;
        @AuraEnabled public Boolean selfScoped;
        @AuraEnabled public String qLabelA;
        @AuraEnabled public String qLabelB;
        @AuraEnabled public Decimal weightHighPct;
        @AuraEnabled public Decimal weightMedPct;
        @AuraEnabled public List<AeRow> rows;
        @AuraEnabled public QuarterSlice teamWindow;
        @AuraEnabled public String emptyReason;
        @AuraEnabled public String classCaption;
        @AuraEnabled public Boolean classMissing;
    }

    public class Booked {
        public Integer n = 0;
        public Decimal arr = 0;
    }

    public static Payload compute(ScopeRequest req) {
        Date today = Date.today();
        CockpitRosterService.Scope scope = CockpitRosterService.resolve(
            req == null ? null : req.directorId,
            req == null ? null : req.teamMode);
        String productType = (req == null || String.isBlank(req.productType))
            ? CockpitConstants.PRODUCT_ALL : req.productType;
        String sizeBand = (req == null || String.isBlank(req.sizeBand))
            ? CockpitConstants.SIZE_ALL : req.sizeBand;

        Payload empty = new Payload();
        empty.directorName = scope.directorName;
        empty.selfScoped = scope.selfScoped;
        empty.weightHighPct = CockpitConstants.WEIGHT_HIGH_PCT;
        empty.weightMedPct = CockpitConstants.WEIGHT_MED_PCT;
        empty.rows = new List<AeRow>();
        empty.scopeCaption = caption(scope.directorName, productType, sizeBand);
        stampQuarterLabels(empty, today);

        Set<Id> owners = scope.ids();
        if (owners.isEmpty()) {
            empty.emptyReason = 'This scope has no account executives. '
                + 'If you are an AE you should see your own row — try My team.';
            return empty;
        }

        Date qStart = CockpitConstants.quarterStart(today.year(), CockpitConstants.quarterOf(today));
        Date winEnd = qStart.addMonths(9).addDays(-1);
        Date nextStart = qStart.addMonths(3);
        Date nextEnd = qStart.addMonths(6).addDays(-1);

        String holdoverField = Schema.sObjectType.Opportunity.fields.Is_Holdover__c.isAccessible()
            ? ', Is_Holdover__c' : '';
        String soql = 'SELECT Id, OwnerId, CloseDate, LastActivityDate, StageName, '
            + 'Roll_Up_Forecast_bf__c, ARR_Opportunity_Amount_USD_Num__c, '
            + 'Cockpit_Class_Override__c, Pricing_Approval_Status__c, '
            + 'SQL_Datestamp_bf__c, Next_Step_Date_bf__c, EUNA_Solution__c'
            + holdoverField
            + ' FROM Opportunity WHERE IsClosed = false AND OwnerId IN :owners'
            + ' AND RecordType.DeveloperName = :saleRt'
            + ' AND Type IN :newBiz'
            + ' AND StageName NOT IN :mig'
            + ' AND CloseDate >= :qStart AND CloseDate <= :winEnd'
            + ' LIMIT 800';
        String saleRt = CockpitConstants.SALE_RECORDTYPE;
        Set<String> newBiz = CockpitConstants.NEW_BUSINESS_TYPES;
        Set<String> mig = CockpitConstants.MIGRATION_STAGES;
        List<Opportunity> opps = Database.query(soql, AccessLevel.USER_MODE);

        Map<Id, Booked> booked = queryBooked(owners, qStart, CockpitConstants.quarterEnd(
            today.year(), CockpitConstants.quarterOf(today)), productType, sizeBand);

        return computeFrom(scope, opps, booked, today, qStart, nextStart, nextEnd, winEnd,
            productType, sizeBand);
    }

    @TestVisible
    static Payload computeFrom(
        CockpitRosterService.Scope scope,
        List<Opportunity> opps,
        Map<Id, Booked> booked,
        Date today,
        Date qStart,
        Date nextStart,
        Date nextEnd,
        Date winEnd,
        String productType,
        String sizeBand
    ) {
        Payload p = new Payload();
        p.directorName = scope.directorName;
        p.selfScoped = scope.selfScoped == true;
        p.weightHighPct = CockpitConstants.WEIGHT_HIGH_PCT;
        p.weightMedPct = CockpitConstants.WEIGHT_MED_PCT;
        p.rows = new List<AeRow>();
        p.scopeCaption = caption(scope.directorName, productType, sizeBand);
        p.classCaption = 'Class is scored live. Cockpit_Class_Override__c wins when set. '
            + 'Cockpit_Class__c is not on this org; a null stored class is not treated as Exclude.';
        p.classMissing = false;
        stampQuarterLabels(p, today);

        List<Opportunity> kept = new List<Opportunity>();
        for (Opportunity o : opps) {
            if (!matchesProduct(o, productType)) continue;
            if (!matchesSize(o.ARR_Opportunity_Amount_USD_Num__c, sizeBand)) continue;
            kept.add(o);
        }

        Map<Id, String> classByOpp = new Map<Id, String>();
        Integer unclassified = 0;
        for (Opportunity o : kept) {
            String cls = effectiveClass(o, today);
            if (cls == null) {
                unclassified++;
            } else {
                classByOpp.put(o.Id, cls);
            }
        }
        if (unclassified > 0) {
            p.classMissing = true;
            p.emptyReason = 'Scoring class is missing on ' + unclassified
                + ' open deal(s). The composition tab will not treat a null class as Exclude. '
                + 'Find the scoring-batch dependency before reading this as an empty book.';
            p.teamWindow = newSlice(windowLabel(qStart, winEnd), false);
            return p;
        }

        Map<Id, AeRow> byOwner = new Map<Id, AeRow>();
        for (CockpitRosterService.Member m : scope.members) {
            AeRow row = newRow(m.userId, m.name, p.qLabelA, p.qLabelB);
            applyBooked(row.currentQ, booked.get(m.userId));
            byOwner.put(m.userId, row);
        }

        QuarterSlice window = newSlice(windowLabel(qStart, winEnd), false);
        Map<Id, List<Opportunity>> currentByOwner = new Map<Id, List<Opportunity>>();
        Map<Id, List<Opportunity>> nextByOwner = new Map<Id, List<Opportunity>>();
        Map<Id, List<Opportunity>> bothByOwner = new Map<Id, List<Opportunity>>();

        for (Opportunity o : kept) {
            AeRow row = byOwner.get(o.OwnerId);
            if (row == null) continue;
            String cls = classByOpp.get(o.Id);
            addToSlice(window, o, cls);
            if (o.CloseDate >= qStart && o.CloseDate < nextStart) {
                addToSlice(row.currentQ, o, cls);
                addOpp(currentByOwner, o);
                addOpp(bothByOwner, o);
            } else if (o.CloseDate >= nextStart && o.CloseDate <= nextEnd) {
                addToSlice(row.nextQ, o, cls);
                addOpp(nextByOwner, o);
                addOpp(bothByOwner, o);
            }
        }

        finishSlice(window, 0, p.weightHighPct, p.weightMedPct);
        p.teamWindow = window;

        List<AeRow> rows = new List<AeRow>();
        for (CockpitRosterService.Member m : scope.members) {
            AeRow row = byOwner.get(m.userId);
            finishSlice(row.currentQ, booked.containsKey(m.userId) ? booked.get(m.userId).arr : 0,
                p.weightHighPct, p.weightMedPct);
            finishSlice(row.nextQ, 0, p.weightHighPct, p.weightMedPct);
            row.signals = signalsFor(
                bothByOwner.containsKey(m.userId) ? bothByOwner.get(m.userId) : new List<Opportunity>(),
                currentByOwner.containsKey(m.userId) ? currentByOwner.get(m.userId) : new List<Opportunity>(),
                today);
            row.cleanBook = row.signals.isEmpty()
                ? 'Nothing cleared the evidence bar.'
                : null;
            rows.add(row);
        }
        p.rows = rows;
        return p;
    }

    @TestVisible
    static List<Signal> signalsFor(List<Opportunity> currentAndNext, List<Opportunity> currentOnly, Date today) {
        List<Signal> out = new List<Signal>();

        Integer commitN = 0;
        Integer mlN = 0;
        Integer scored = 0;
        Integer thin = 0;
        Integer silentN = 0;
        Decimal silentArr = 0;
        Integer zeroN = 0;
        for (Opportunity o : currentAndNext) {
            String band = o.Roll_Up_Forecast_bf__c;
            if (band == CockpitConstants.BAND_COMMIT) commitN++;
            if (band == CockpitConstants.BAND_ML) mlN++;
            Integer med = meddpiccOf(o);
            if (med != null) {
                scored++;
                if (med < 3) thin++;
            }
            if (isSilent(o, today)) {
                silentN++;
                silentArr += nz(o.ARR_Opportunity_Amount_USD_Num__c);
            }
            if (nz(o.ARR_Opportunity_Amount_USD_Num__c) == 0) zeroN++;
        }
        if (!currentAndNext.isEmpty() && commitN == 0) {
            out.add(sig('COMMIT', '0 deals in Commit across current and next quarter'));
        }
        if (scored >= 4 && ((Decimal) thin).divide(scored, 4) > 0.5) {
            out.add(sig('MEDDPICC', thin + ' of ' + scored + ' scored deals are below 3/8 MEDDPICC'));
        }
        if (silentN > 0) {
            out.add(sig('SILENT', silentN + ' open deal(s) / $' + silentArr.setScale(0)
                + ' with no real activity in 30+ days'));
        }
        if (zeroN > 0) {
            out.add(sig('ZERO_ARR', zeroN + ' open record(s) at $0 ARR'));
        }

        Decimal currentOpen = 0;
        Decimal largest = 0;
        for (Opportunity o : currentOnly) {
            Decimal arr = nz(o.ARR_Opportunity_Amount_USD_Num__c);
            currentOpen += arr;
            if (arr > largest) largest = arr;
        }
        Decimal concPct = currentOpen == 0 ? 0 : largest.divide(currentOpen, 6, System.RoundingMode.HALF_UP) * 100;
        if (currentOpen > 0 && concPct.setScale(4, System.RoundingMode.HALF_UP) > CockpitConstants.CONCENTRATION_PCT) {
            Decimal pct = concPct;
            out.add(sig('CONCENTRATION', 'Largest current-quarter deal is $' + largest.setScale(0)
                + ' — ' + pct.setScale(1) + '% of this AE\'s current-quarter open ARR'));
        }

        if (!currentAndNext.isEmpty() && mlN == 0) {
            out.add(sig('UNUSED_ML', '0 deals in Most Likely across current and next quarter'));
        }
        return out;
    }

    @TestVisible
    static String effectiveClass(Opportunity o, Date today) {
        if (String.isNotBlank(o.Cockpit_Class_Override__c)) {
            return o.Cockpit_Class_Override__c;
        }
        if (liveScoreIfClassMissing) {
            CockpitScoreService.Result r = CockpitScoreService.score(o, meddpiccOf(o), 0, today);
            return r.klass;
        }
        return null;
    }

    @TestVisible
    static Boolean isSilent(Opportunity o, Date today) {
        Date touch = o.LastActivityDate;
        if (touch == null || touch > today) return true;
        return touch.daysBetween(today) >= 30;
    }

    private static Map<Id, Booked> queryBooked(
        Set<Id> owners, Date qStart, Date qEnd, String productType, String sizeBand
    ) {
        Map<Id, Booked> out = new Map<Id, Booked>();
        Boolean filterProduct = productType != CockpitConstants.PRODUCT_ALL;
        Boolean filterSize = sizeBand != CockpitConstants.SIZE_ALL;
        if (filterProduct || filterSize) {
            for (Opportunity o : [
                SELECT OwnerId, ARR_Opportunity_Amount_USD_Num__c, EUNA_Solution__c
                FROM Opportunity
                WHERE IsClosed = true AND IsWon = true
                  AND OwnerId IN :owners
                  AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
                  AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
                  AND StageName NOT IN :CockpitConstants.MIGRATION_STAGES
                  AND CloseDate >= :qStart AND CloseDate <= :qEnd
                WITH USER_MODE
            ]) {
                if (!matchesProduct(o, productType)) continue;
                if (!matchesSize(o.ARR_Opportunity_Amount_USD_Num__c, sizeBand)) continue;
                Booked b = out.get(o.OwnerId);
                if (b == null) { b = new Booked(); out.put(o.OwnerId, b); }
                b.n++;
                b.arr += nz(o.ARR_Opportunity_Amount_USD_Num__c);
            }
            return out;
        }
        for (AggregateResult ar : [
            SELECT OwnerId oid, COUNT(Id) n, SUM(ARR_Opportunity_Amount_USD_Num__c) arr
            FROM Opportunity
            WHERE IsClosed = true AND IsWon = true
              AND OwnerId IN :owners
              AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
              AND StageName NOT IN :CockpitConstants.MIGRATION_STAGES
              AND CloseDate >= :qStart AND CloseDate <= :qEnd
            WITH USER_MODE
            GROUP BY OwnerId
        ]) {
            Booked b = new Booked();
            b.n = (Integer) ar.get('n');
            Decimal arr = (Decimal) ar.get('arr');
            b.arr = arr == null ? 0 : arr;
            out.put((Id) ar.get('oid'), b);
        }
        return out;
    }

    private static void addToSlice(QuarterSlice s, Opportunity o, String cls) {
        Decimal arr = nz(o.ARR_Opportunity_Amount_USD_Num__c);
        s.openN++;
        s.openArr += arr;
        if (holdoverOf(o)) {
            s.holdoverN++;
            s.holdoverArr += arr;
        }
        BandCell cell = cellFor(s, o.Roll_Up_Forecast_bf__c);
        cell.deals++;
        cell.arr += arr;
        if (cls == 'HI') { s.includeHighN++; s.includeHighArr += arr; }
        else if (cls == 'MD') { s.includeMedN++; s.includeMedArr += arr; }
        else { s.excludeN++; s.excludeArr += arr; }
    }

    private static BandCell cellFor(QuarterSlice s, String band) {
        if (band == CockpitConstants.BAND_COMMIT) return s.commitBand;
        if (band == CockpitConstants.BAND_ML) return s.mostLikely;
        if (band == CockpitConstants.BAND_BC) return s.bestCase;
        if (band == CockpitConstants.BAND_PIPE) return s.pipeline;
        if (band == CockpitConstants.BAND_OMITTED) return s.omitted;
        return s.unbanded;
    }

    private static void finishSlice(QuarterSlice s, Decimal bookedArr, Decimal wHi, Decimal wMed) {
        share(s.commitBand, s.openArr);
        share(s.mostLikely, s.openArr);
        share(s.bestCase, s.openArr);
        share(s.pipeline, s.openArr);
        share(s.omitted, s.openArr);
        share(s.unbanded, s.openArr);
        Decimal booked = bookedArr == null ? 0 : bookedArr;
        if (s.showBooked) {
            s.evidenceCall = booked
                + (s.includeHighArr * wHi / 100)
                + (s.includeMedArr * wMed / 100);
        } else {
            s.evidenceCall = (s.includeHighArr * wHi / 100)
                + (s.includeMedArr * wMed / 100);
        }
    }

    private static void applyBooked(QuarterSlice s, Booked b) {
        if (b == null) return;
        s.bookedN = b.n;
        s.bookedArr = b.arr;
    }

    private static void share(BandCell c, Decimal openArr) {
        c.share = (openArr == null || openArr == 0) ? 0 : c.arr.divide(openArr, 4);
    }

    private static AeRow newRow(Id ownerId, String name, String qA, String qB) {
        AeRow r = new AeRow();
        r.ownerId = ownerId;
        r.name = name;
        r.currentQ = newSlice(qA, true);
        r.nextQ = newSlice(qB, false);
        r.signals = new List<Signal>();
        return r;
    }

    private static QuarterSlice newSlice(String label, Boolean showBooked) {
        QuarterSlice s = new QuarterSlice();
        s.label = label;
        s.showBooked = showBooked;
        return s;
    }

    private static void addOpp(Map<Id, List<Opportunity>> m, Opportunity o) {
        List<Opportunity> listRef = m.get(o.OwnerId);
        if (listRef == null) {
            listRef = new List<Opportunity>();
            m.put(o.OwnerId, listRef);
        }
        listRef.add(o);
    }

    private static Signal sig(String code, String fact) {
        Signal s = new Signal();
        s.code = code;
        s.fact = fact;
        return s;
    }

    private static Integer meddpiccOf(Opportunity o) {
        if (o.Id != null && testMeddpiccByOpp.containsKey(o.Id)) {
            return testMeddpiccByOpp.get(o.Id);
        }
        return null;
    }

    private static Boolean matchesProduct(Opportunity o, String productType) {
        if (String.isBlank(productType) || productType == CockpitConstants.PRODUCT_ALL) return true;
        return o.EUNA_Solution__c == productType;
    }

    @TestVisible
    static Boolean matchesSize(Decimal arr, String sizeBand) {
        if (String.isBlank(sizeBand) || sizeBand == CockpitConstants.SIZE_ALL) return true;
        Decimal a = nz(arr);
        if (sizeBand == CockpitConstants.SIZE_UNDER_50K) return a < 50000;
        if (sizeBand == CockpitConstants.SIZE_50_150K) return a >= 50000 && a < 150000;
        if (sizeBand == CockpitConstants.SIZE_OVER_150K) return a >= 150000;
        return true;
    }

    private static void stampQuarterLabels(Payload p, Date today) {
        Integer q = CockpitConstants.quarterOf(today);
        p.qLabelA = 'Q' + q + ' ' + today.year();
        Integer qb = (q == 4) ? 1 : q + 1;
        Integer yb = (q == 4) ? today.year() + 1 : today.year();
        p.qLabelB = 'Q' + qb + ' ' + yb;
    }

    private static String windowLabel(Date startDt, Date endDt) {
        return 'Q' + CockpitConstants.quarterOf(startDt) + ' ' + startDt.year()
            + '–Q' + CockpitConstants.quarterOf(endDt) + ' ' + endDt.year();
    }

    private static String caption(String directorName, String productType, String sizeBand) {
        String product = (String.isBlank(productType) || productType == CockpitConstants.PRODUCT_ALL)
            ? 'All products' : productType;
        String size = sizeLabel(sizeBand);
        String who = String.isBlank(directorName) ? 'your team' : directorName;
        return 'Team of ' + who + ' · ' + product + ' · ' + size;
    }

    private static String sizeLabel(String sizeBand) {
        if (sizeBand == CockpitConstants.SIZE_UNDER_50K) return 'Under $50k';
        if (sizeBand == CockpitConstants.SIZE_50_150K) return '$50–150k';
        if (sizeBand == CockpitConstants.SIZE_OVER_150K) return '$150k+';
        return 'All sizes';
    }

    private static Boolean holdoverOf(Opportunity o) {
        try {
            return o.Is_Holdover__c == true;
        } catch (Exception e) {
            return false;
        }
    }

    private static Decimal nz(Decimal d) { return d == null ? 0 : d; }
}
