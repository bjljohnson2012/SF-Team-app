/**
 * LWC entry for the AE Waterfall tab. Builds the close plan (this period)
 * and the create plan (period + cycle) from calibrated rates and live actuals.
 */
public with sharing class WaterfallController {

    public class Rung {
        @AuraEnabled public String name;
        @AuraEnabled public String op;
        @AuraEnabled public String value;
        @AuraEnabled public Integer depth;
        @AuraEnabled public Boolean indicative;
        public Rung(String n, String o, String v, Integer d, Boolean ind) {
            name = n; op = o; value = v; depth = d; indicative = ind;
        }
    }

    public class Plan {
        @AuraEnabled public String kind;
        @AuraEnabled public String periodLabel;
        @AuraEnabled public String lever;
        @AuraEnabled public Decimal quota;
        @AuraEnabled public Decimal winsNeeded;
        @AuraEnabled public Decimal qoNeeded;
        @AuraEnabled public Decimal oppsToCreate;
        @AuraEnabled public Decimal selfSourced;
        @AuraEnabled public Decimal connectsNeeded;
        @AuraEnabled public Decimal dialsNeeded;
        @AuraEnabled public List<Rung> rungs = new List<Rung>();
    }

    public class AeCard {
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String name;
        @AuraEnabled public String sampleConfidence;
        @AuraEnabled public Integer closedCount;
        @AuraEnabled public Decimal winRateRaw;
        @AuraEnabled public Decimal winRateBlended;
        @AuraEnabled public Decimal winRateUngated;
        @AuraEnabled public Decimal aspRaw;
        @AuraEnabled public Decimal aspBlended;
        @AuraEnabled public Decimal cycleMedianDays;
        @AuraEnabled public Integer landsQuarters;
        @AuraEnabled public Decimal qualRate;
        @AuraEnabled public Decimal selfSourcedShare;
        @AuraEnabled public Decimal connectRate;
        @AuraEnabled public Decimal oppsPerConnect;
        @AuraEnabled public Decimal activityComplete;
        @AuraEnabled public Boolean activityIndicative;
        @AuraEnabled public Decimal quota;
        @AuraEnabled public Integer haveQo;
        @AuraEnabled public Decimal haveArr;
        @AuraEnabled public Integer created;
        @AuraEnabled public Integer dials;
        @AuraEnabled public Integer connects;
        @AuraEnabled public Integer emailsSent;
        @AuraEnabled public Integer replies;
        @AuraEnabled public Integer meetingsHeld;
        @AuraEnabled public Plan closePlan;
        @AuraEnabled public Plan createPlan;
    }

    public class PagePayload {
        @AuraEnabled public String scopeCaption;
        @AuraEnabled public String emptyReason;
        @AuraEnabled public String periodLabel;
        @AuraEnabled public String createPeriodLabel;
        @AuraEnabled public String teamCaption;
        @AuraEnabled public List<AeCard> rows = new List<AeCard>();
    }

    @AuraEnabled
    public static PagePayload load(Id directorId, String teamMode, String productType, String sizeBand) {
        return build(directorId, teamMode, productType, sizeBand, Date.today());
    }

    public static PagePayload build(
        Id directorId, String teamMode, String productType, String sizeBand, Date asOf
    ) {
        Date asOfDay = asOf == null ? Date.today() : asOf;
        String product = String.isBlank(productType) ? CockpitConstants.PRODUCT_ALL : productType;
        String size = String.isBlank(sizeBand) ? CockpitConstants.SIZE_ALL : sizeBand;
        CockpitRosterService.ScopeResult scope = CockpitRosterService.resolveScope(directorId, teamMode);
        PagePayload page = new PagePayload();
        page.scopeCaption = 'Team of ' + scope.directorName
            + ' · ' + CockpitConstants.productGroupLabel(product)
            + ' · ' + WaterfallConstants.sizeLabel(size);
        page.periodLabel = WaterfallConstants.periodLabel(asOfDay);
        if (scope.members == null || scope.members.isEmpty()) {
            page.emptyReason = scope.emptyMessage;
            return page;
        }

        Set<Id> ownerIds = scope.ownerIds();
        Map<Id, String> names = new Map<Id, String>();
        for (CockpitRosterService.Member m : scope.members) names.put(m.userId, m.name);

        WaterfallRateEngine.RateSet rates =
            WaterfallRateEngine.calibrate(ownerIds, product, size, asOfDay);
        WaterfallActualEngine.ActualSet actuals =
            WaterfallActualEngine.measure(ownerIds, product, size, asOfDay);

        Integer teamLands = rates.team == null ? 2 : rates.team.landsQuarters;
        Date createAsOf = WaterfallConstants.shiftPeriod(asOfDay, teamLands);
        page.createPeriodLabel = WaterfallConstants.periodLabel(createAsOf);
        if (rates.team != null) {
            page.teamCaption = 'Team baseline: '
                + rates.team.wins + ' wins of ' + rates.team.closedCount + ' closed'
                + (rates.team.winRateRaw == null ? '' : ' = ' + pct(rates.team.winRateRaw))
                + (rates.team.aspRaw == null ? '' : ', ASP ' + money(rates.team.aspRaw)
                    + ' across ' + rates.team.arrBearingWins + ' ARR-bearing wins.');
        }

        for (Id oid : ownerIds) {
            page.rows.add(cardFor(
                oid, names.get(oid), rates.byOwner.get(oid), actuals.byOwner.get(oid),
                asOfDay, createAsOf, page.periodLabel, page.createPeriodLabel
            ));
        }
        return page;
    }

    @TestVisible
    static Plan buildPlan(
        String kind, String periodLabel, String lever, Decimal quota,
        WaterfallRateEngine.RateRow rate, WaterfallActualEngine.ActualRow actual
    ) {
        Plan p = new Plan();
        p.kind = kind;
        p.periodLabel = periodLabel;
        p.lever = lever;
        p.quota = quota == null ? 0 : quota;
        Decimal asp = rate == null ? null : rate.aspBlended;
        Decimal wr = rate == null ? null : rate.winRateBlended;
        Decimal qual = rate == null ? null : rate.qualRate;
        Decimal selfShare = WaterfallConstants.clampShare(
            rate == null ? null : rate.selfSourcedShare);
        Decimal oppPerConnect = (actual != null && actual.oppsPerConnect != null && actual.oppsPerConnect > 0)
            ? actual.oppsPerConnect : 1;
        Decimal connectRate = actual == null ? null : actual.connectRate;
        Boolean indicative = actual != null
            && (actual.activityComplete == null
                || actual.activityComplete < WaterfallConstants.ACTIVITY_COMPLETE_FLOOR);

        p.winsNeeded = WaterfallConstants.safeDiv(p.quota, asp);
        p.qoNeeded = WaterfallConstants.safeDiv(p.winsNeeded, wr);
        p.oppsToCreate = WaterfallConstants.safeDiv(p.qoNeeded, qual);
        p.selfSourced = (p.oppsToCreate == null || selfShare == null)
            ? null : p.oppsToCreate * selfShare;
        p.connectsNeeded = WaterfallConstants.safeDiv(p.selfSourced, oppPerConnect);
        p.dialsNeeded = WaterfallConstants.safeDiv(p.connectsNeeded, connectRate);

        p.rungs.add(new Rung('Quota', 'Sales_Plan__c · ' + periodLabel, money(p.quota), 0, false));
        p.rungs.add(new Rung(
            'Wins needed',
            '÷ ASP ' + money(asp) + ' blended',
            dec(p.winsNeeded, 1), 1, false));
        p.rungs.add(new Rung(
            'Qualified opps needed',
            '÷ win rate ' + pct(wr) + ' blended, gated',
            dec(p.qoNeeded, 1), 2, false));
        if (kind == 'create') {
            p.rungs.add(new Rung(
                'Opps to create',
                '÷ qualification rate ' + pct(qual),
                dec(p.oppsToCreate, 1), 3, false));
            p.rungs.add(new Rung(
                'Self sourced share',
                '× ' + pct(selfShare) + ' AE and AM sourced mix',
                dec(p.selfSourced, 1), 4, false));
            p.rungs.add(new Rung(
                'Connects, then dials',
                '÷ ' + dec(oppPerConnect, 2) + ' opp per connect, ÷ ' + pct(connectRate) + ' connect rate',
                (p.dialsNeeded == null ? '—' : dec(p.dialsNeeded, 0) + ' dials'),
                5, indicative));
        }
        return p;
    }

    static AeCard cardFor(
        Id ownerId, String name, WaterfallRateEngine.RateRow rate,
        WaterfallActualEngine.ActualRow actual, Date asOfDay, Date createAsOf,
        String closeLabel, String createLabel
    ) {
        AeCard c = new AeCard();
        c.ownerId = ownerId;
        c.name = name;
        if (rate != null) {
            c.sampleConfidence = rate.sampleConfidence;
            c.closedCount = rate.closedCount;
            c.winRateRaw = rate.winRateRaw;
            c.winRateBlended = rate.winRateBlended;
            c.winRateUngated = rate.winRateUngated;
            c.aspRaw = rate.aspRaw;
            c.aspBlended = rate.aspBlended;
            c.cycleMedianDays = rate.cycleMedianDays;
            c.landsQuarters = rate.landsQuarters;
            c.qualRate = rate.qualRate;
            c.selfSourcedShare = rate.selfSourcedShare;
        }
        Decimal quota = actual == null ? 0 : actual.quota;
        c.quota = quota;
        if (actual != null) {
            c.haveQo = actual.openQualified;
            c.haveArr = actual.openQualifiedArr;
            c.created = actual.created;
            c.dials = actual.dials;
            c.connects = actual.connects;
            c.emailsSent = actual.emailsSent;
            c.replies = actual.replies;
            c.meetingsHeld = actual.meetingsHeld;
            c.connectRate = actual.connectRate;
            c.oppsPerConnect = actual.oppsPerConnect;
            c.activityComplete = actual.activityComplete;
            c.activityIndicative = actual.activityComplete == null
                || actual.activityComplete < WaterfallConstants.ACTIVITY_COMPLETE_FLOOR;
        }
        Integer lands = c.landsQuarters == null ? 2 : c.landsQuarters;
        c.closePlan = buildPlan(
            'close', closeLabel, 'Deal execution. Not activity.', quota, rate, actual);
        // Known gap: next-period quota is assumed equal to this one until
        // Sales_Plan__c rows exist for the shifted period.
        c.createPlan = buildPlan(
            'create',
            createLabel,
            'Activity and channel capacity.',
            quota,
            rate,
            actual);
        if (c.createPlan != null) {
            c.createPlan.periodLabel = WaterfallConstants.periodLabel(
                WaterfallConstants.shiftPeriod(asOfDay, lands));
        }
        return c;
    }

    static String money(Decimal n) {
        if (n == null) return '—';
        return '$' + String.valueOf(n.setScale(0, RoundingMode.HALF_UP).format());
    }
    static String pct(Decimal n) {
        if (n == null) return '—';
        return String.valueOf((n * 100).setScale(1, RoundingMode.HALF_UP)) + '%';
    }
    static String dec(Decimal n, Integer scale) {
        if (n == null) return '—';
        return String.valueOf(n.setScale(scale, RoundingMode.HALF_UP));
    }
}
