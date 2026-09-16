/**
 * Per-AE play plan: recommended cascade, weekday cadence, and what-if
 * projections when a manager edits recommended numbers.
 */
public with sharing class WaterfallPlayPlanner {

    public class PlayDraft {
        @AuraEnabled public Decimal quota;
        @AuraEnabled public Decimal asp;
        @AuraEnabled public Decimal winRate;
        @AuraEnabled public Decimal qualRate;
        @AuraEnabled public Decimal selfShare;
        @AuraEnabled public Decimal oppsPerConnect;
        @AuraEnabled public Decimal connectRate;

        @AuraEnabled public Decimal winsNeeded;
        @AuraEnabled public Decimal qoNeeded;
        @AuraEnabled public Decimal oppsToCreate;
        @AuraEnabled public Decimal selfSourced;
        @AuraEnabled public Decimal channelOpps;
        @AuraEnabled public Decimal connectsNeeded;
        @AuraEnabled public Decimal dialsNeeded;

        @AuraEnabled public Decimal projectedArr;
        @AuraEnabled public Decimal quotaCoverage;
        @AuraEnabled public Decimal qoGap;
        @AuraEnabled public Decimal createGap;
        @AuraEnabled public Decimal dialsRemaining;

        @AuraEnabled public Integer haveQo;
        @AuraEnabled public Integer created;
        @AuraEnabled public Integer actualDials;
        @AuraEnabled public Integer actualConnects;

        @AuraEnabled public Integer remainingWorkingDays;
        @AuraEnabled public Integer elapsedWorkingDays;
        @AuraEnabled public Integer workingDaysInPeriod;
        @AuraEnabled public Decimal remainingWeeks;
        @AuraEnabled public Decimal dialsPerDay;
        @AuraEnabled public Decimal dialsPerWeek;
        @AuraEnabled public Decimal connectsPerDay;
        @AuraEnabled public Decimal connectsPerWeek;
        @AuraEnabled public Decimal normalDialsPerDay;
        @AuraEnabled public Decimal normalDialsPerWeek;
        @AuraEnabled public Decimal normalConnectsPerWeek;
        @AuraEnabled public Decimal normalConnectRate;
        @AuraEnabled public Decimal weeklyPaceGap;
        @AuraEnabled public Boolean activityIndicative;
        @AuraEnabled public String editedField;
    }

    public static PlayDraft recommended(
        Decimal quota,
        WaterfallRateEngine.RateRow rate,
        WaterfallActualEngine.ActualRow actual,
        Date asOf
    ) {
        PlayDraft d = new PlayDraft();
        d.quota = quota == null ? 0 : quota;
        if (rate != null) {
            d.asp = rate.aspBlended;
            d.winRate = rate.winRateBlended;
            d.qualRate = rate.qualRate;
            d.selfShare = WaterfallConstants.clampShare(rate.selfSourcedShare);
        }
        if (actual != null) {
            d.oppsPerConnect = (actual.oppsPerConnect != null && actual.oppsPerConnect > 0)
                ? actual.oppsPerConnect : 1;
            d.connectRate = actual.connectRate;
            d.haveQo = actual.openQualified;
            d.created = actual.created;
            d.actualDials = actual.dials;
            d.actualConnects = actual.connects;
            d.activityIndicative = actual.activityComplete == null
                || actual.activityComplete < WaterfallConstants.ACTIVITY_COMPLETE_FLOOR;
            d.normalConnectRate = actual.connectRate;
        } else {
            d.oppsPerConnect = 1;
            d.haveQo = 0;
            d.created = 0;
            d.actualDials = 0;
            d.actualConnects = 0;
        }
        return project(d, 'rate', asOf);
    }

    public static PlayDraft project(PlayDraft incoming, String editedField, Date asOf) {
        PlayDraft d = copyOf(incoming);
        d.editedField = editedField;
        String field = String.isBlank(editedField) ? 'rate' : editedField;
        Decimal oppPer = (d.oppsPerConnect != null && d.oppsPerConnect > 0) ? d.oppsPerConnect : 1;
        Decimal selfShare = WaterfallConstants.clampShare(d.selfShare);
        d.selfShare = selfShare;

        if (field == 'dials') {
            d.connectsNeeded = mul(d.dialsNeeded, d.connectRate);
            d.selfSourced = mul(d.connectsNeeded, oppPer);
            d.oppsToCreate = WaterfallConstants.safeDiv(d.selfSourced, selfShare);
            d.qoNeeded = mul(d.oppsToCreate, d.qualRate);
            d.winsNeeded = mul(d.qoNeeded, d.winRate);
        } else if (field == 'connects') {
            d.dialsNeeded = WaterfallConstants.safeDiv(d.connectsNeeded, d.connectRate);
            d.selfSourced = mul(d.connectsNeeded, oppPer);
            d.oppsToCreate = WaterfallConstants.safeDiv(d.selfSourced, selfShare);
            d.qoNeeded = mul(d.oppsToCreate, d.qualRate);
            d.winsNeeded = mul(d.qoNeeded, d.winRate);
        } else if (field == 'selfSourced') {
            d.oppsToCreate = WaterfallConstants.safeDiv(d.selfSourced, selfShare);
            d.qoNeeded = mul(d.oppsToCreate, d.qualRate);
            d.winsNeeded = mul(d.qoNeeded, d.winRate);
            d.connectsNeeded = WaterfallConstants.safeDiv(d.selfSourced, oppPer);
            d.dialsNeeded = WaterfallConstants.safeDiv(d.connectsNeeded, d.connectRate);
        } else if (field == 'oppsToCreate') {
            d.qoNeeded = mul(d.oppsToCreate, d.qualRate);
            d.winsNeeded = mul(d.qoNeeded, d.winRate);
            d.selfSourced = mul(d.oppsToCreate, selfShare);
            d.connectsNeeded = WaterfallConstants.safeDiv(d.selfSourced, oppPer);
            d.dialsNeeded = WaterfallConstants.safeDiv(d.connectsNeeded, d.connectRate);
        } else if (field == 'qoNeeded') {
            d.winsNeeded = mul(d.qoNeeded, d.winRate);
            d.oppsToCreate = WaterfallConstants.safeDiv(d.qoNeeded, d.qualRate);
            d.selfSourced = mul(d.oppsToCreate, selfShare);
            d.connectsNeeded = WaterfallConstants.safeDiv(d.selfSourced, oppPer);
            d.dialsNeeded = WaterfallConstants.safeDiv(d.connectsNeeded, d.connectRate);
        } else if (field == 'winsNeeded') {
            d.qoNeeded = WaterfallConstants.safeDiv(d.winsNeeded, d.winRate);
            d.oppsToCreate = WaterfallConstants.safeDiv(d.qoNeeded, d.qualRate);
            d.selfSourced = mul(d.oppsToCreate, selfShare);
            d.connectsNeeded = WaterfallConstants.safeDiv(d.selfSourced, oppPer);
            d.dialsNeeded = WaterfallConstants.safeDiv(d.connectsNeeded, d.connectRate);
        } else {
            d.winsNeeded = WaterfallConstants.safeDiv(d.quota, d.asp);
            d.qoNeeded = WaterfallConstants.safeDiv(d.winsNeeded, d.winRate);
            d.oppsToCreate = WaterfallConstants.safeDiv(d.qoNeeded, d.qualRate);
            d.selfSourced = mul(d.oppsToCreate, selfShare);
            d.connectsNeeded = WaterfallConstants.safeDiv(d.selfSourced, oppPer);
            d.dialsNeeded = WaterfallConstants.safeDiv(d.connectsNeeded, d.connectRate);
        }

        d.channelOpps = (d.oppsToCreate == null || d.selfSourced == null)
            ? null : d.oppsToCreate - d.selfSourced;
        d.projectedArr = mul(d.winsNeeded, d.asp);
        d.quotaCoverage = WaterfallConstants.safeDiv(d.projectedArr, d.quota);
        Integer have = d.haveQo == null ? 0 : d.haveQo;
        d.qoGap = d.qoNeeded == null ? null : d.qoNeeded - have;
        Integer createdN = d.created == null ? 0 : d.created;
        d.createGap = d.oppsToCreate == null ? null : d.oppsToCreate - createdN;
        Integer dialled = d.actualDials == null ? 0 : d.actualDials;
        d.dialsRemaining = d.dialsNeeded == null ? null : d.dialsNeeded - dialled;

        applyCadence(d, asOf);
        return d;
    }

    public static Map<Id, PlayDraft> loadSaved(Set<Id> ownerIds, String product, Date periodStart) {
        Map<Id, PlayDraft> out = new Map<Id, PlayDraft>();
        if (ownerIds == null || ownerIds.isEmpty() || periodStart == null) return out;
        if (!Schema.sObjectType.Waterfall_Target__c.isAccessible()
            || !Schema.sObjectType.Waterfall_Target__c.fields.AE__c.isAccessible()
            || !Schema.sObjectType.Waterfall_Target__c.fields.Metric__c.isAccessible()
            || !Schema.sObjectType.Waterfall_Target__c.fields.Target_Value__c.isAccessible()) {
            return out;
        }
        String sol = String.isBlank(product) ? WaterfallConstants.SOLUTION_ALL : product;
        List<Waterfall_Target__c> rows = [
            SELECT AE__c, Metric__c, Target_Value__c, Solution__c
            FROM Waterfall_Target__c
            WHERE AE__c IN :ownerIds
              AND Period_Start__c = :periodStart
              AND Solution__c = :sol
            WITH USER_MODE
        ];
        for (Waterfall_Target__c row : rows) {
            if (row.AE__c == null || String.isBlank(row.Metric__c)) continue;
            PlayDraft d = out.get(row.AE__c);
            if (d == null) {
                d = new PlayDraft();
                out.put(row.AE__c, d);
            }
            applyMetric(d, row.Metric__c, row.Target_Value__c);
        }
        return out;
    }

    public static void save(Id ownerId, String productType, String reason, PlayDraft planned) {
        if (ownerId == null) {
            throw new AuraHandledException('An AE is required to save a play plan.');
        }
        if (String.isBlank(reason)) {
            throw new AuraHandledException('A reason is required so the change stays auditable.');
        }
        if (planned == null) {
            throw new AuraHandledException('Nothing to save.');
        }
        String sol = String.isBlank(productType) ? WaterfallConstants.SOLUTION_ALL : productType;
        Date start = WaterfallConstants.periodStart(Date.today());
        List<Waterfall_Target__c> rows = new List<Waterfall_Target__c>();
        addTarget(rows, ownerId, sol, start, WaterfallConstants.METRIC_WIN_RATE, planned.winRate, reason);
        addTarget(rows, ownerId, sol, start, WaterfallConstants.METRIC_QUAL_RATE, planned.qualRate, reason);
        addTarget(rows, ownerId, sol, start, WaterfallConstants.METRIC_SELF_SHARE, planned.selfShare, reason);
        addTarget(rows, ownerId, sol, start, WaterfallConstants.METRIC_OPPS_PER_CONNECT, planned.oppsPerConnect, reason);
        addTarget(rows, ownerId, sol, start, WaterfallConstants.METRIC_CONNECT_RATE, planned.connectRate, reason);
        addTarget(rows, ownerId, sol, start, WaterfallConstants.METRIC_QO, planned.qoNeeded, reason);
        addTarget(rows, ownerId, sol, start, WaterfallConstants.METRIC_OPPS, planned.oppsToCreate, reason);
        addTarget(rows, ownerId, sol, start, WaterfallConstants.METRIC_CONNECTS, planned.connectsNeeded, reason);
        addTarget(rows, ownerId, sol, start, WaterfallConstants.METRIC_DIALS, planned.dialsNeeded, reason);
        if (!rows.isEmpty()) {
            Database.upsert(rows, Waterfall_Target__c.External_Id__c, AccessLevel.USER_MODE);
        }
    }

    public static PlayDraft mergeSaved(PlayDraft recommendedDraft, PlayDraft saved, Date asOf) {
        if (recommendedDraft == null) return null;
        if (saved == null) return copyOf(recommendedDraft);
        PlayDraft d = copyOf(recommendedDraft);
        overlay(d, saved);
        String field = saved.dialsNeeded != null ? 'dials'
            : (saved.qoNeeded != null ? 'qoNeeded' : 'rate');
        return project(d, field, asOf);
    }

    static void applyCadence(PlayDraft d, Date asOf) {
        Date day = asOf == null ? Date.today() : asOf;
        Date start = WaterfallConstants.periodStart(day);
        Date finish = WaterfallConstants.periodEnd(day);
        d.workingDaysInPeriod = WaterfallConstants.workingDaysBetween(start, finish);
        d.remainingWorkingDays = WaterfallConstants.workingDaysBetween(day, finish);
        Date yesterday = day.addDays(-1);
        d.elapsedWorkingDays = yesterday < start
            ? 0
            : WaterfallConstants.workingDaysBetween(start, yesterday);
        d.remainingWeeks = d.remainingWorkingDays == null
            ? null
            : Decimal.valueOf(d.remainingWorkingDays) / 5;
        Integer daysLeft = d.remainingWorkingDays == null ? 0 : d.remainingWorkingDays;
        d.dialsPerDay = daysLeft == 0 ? d.dialsNeeded : WaterfallConstants.safeDiv(d.dialsNeeded, daysLeft);
        d.connectsPerDay = daysLeft == 0 ? d.connectsNeeded : WaterfallConstants.safeDiv(d.connectsNeeded, daysLeft);
        d.dialsPerWeek = mul(d.dialsPerDay, 5);
        d.connectsPerWeek = mul(d.connectsPerDay, 5);

        Integer elapsed = d.elapsedWorkingDays == null ? 0 : d.elapsedWorkingDays;
        Decimal actualDials = d.actualDials == null ? 0 : d.actualDials;
        Decimal actualConnects = d.actualConnects == null ? 0 : d.actualConnects;
        d.normalDialsPerDay = elapsed == 0 ? null : WaterfallConstants.safeDiv(actualDials, elapsed);
        d.normalDialsPerWeek = mul(d.normalDialsPerDay, 5);
        d.normalConnectsPerWeek = elapsed == 0
            ? null
            : mul(WaterfallConstants.safeDiv(actualConnects, elapsed), 5);
        if (d.normalConnectRate == null) {
            d.normalConnectRate = WaterfallConstants.safeDiv(actualConnects, actualDials);
        }
        d.weeklyPaceGap = (d.dialsPerWeek == null || d.normalDialsPerWeek == null)
            ? null
            : d.dialsPerWeek - d.normalDialsPerWeek;
    }

    static void applyMetric(PlayDraft d, String metric, Decimal value) {
        if (metric == WaterfallConstants.METRIC_WIN_RATE) d.winRate = value;
        else if (metric == WaterfallConstants.METRIC_QUAL_RATE) d.qualRate = value;
        else if (metric == WaterfallConstants.METRIC_SELF_SHARE) d.selfShare = value;
        else if (metric == WaterfallConstants.METRIC_OPPS_PER_CONNECT) d.oppsPerConnect = value;
        else if (metric == WaterfallConstants.METRIC_CONNECT_RATE) d.connectRate = value;
        else if (metric == WaterfallConstants.METRIC_QO) d.qoNeeded = value;
        else if (metric == WaterfallConstants.METRIC_OPPS) d.oppsToCreate = value;
        else if (metric == WaterfallConstants.METRIC_CONNECTS) d.connectsNeeded = value;
        else if (metric == WaterfallConstants.METRIC_DIALS) d.dialsNeeded = value;
    }

    static void overlay(PlayDraft dest, PlayDraft src) {
        if (src.winRate != null) dest.winRate = src.winRate;
        if (src.qualRate != null) dest.qualRate = src.qualRate;
        if (src.selfShare != null) dest.selfShare = src.selfShare;
        if (src.oppsPerConnect != null) dest.oppsPerConnect = src.oppsPerConnect;
        if (src.connectRate != null) dest.connectRate = src.connectRate;
        if (src.qoNeeded != null) dest.qoNeeded = src.qoNeeded;
        if (src.oppsToCreate != null) dest.oppsToCreate = src.oppsToCreate;
        if (src.connectsNeeded != null) dest.connectsNeeded = src.connectsNeeded;
        if (src.dialsNeeded != null) dest.dialsNeeded = src.dialsNeeded;
    }

    static void addTarget(
        List<Waterfall_Target__c> rows, Id ownerId, String sol, Date start,
        String metric, Decimal value, String reason
    ) {
        if (value == null) return;
        Waterfall_Target__c rec = new Waterfall_Target__c();
        rec.AE__c = ownerId;
        rec.Solution__c = sol;
        rec.Period_Start__c = start;
        rec.Metric__c = metric;
        rec.Target_Value__c = value;
        rec.Reason__c = reason.left(255);
        rec.External_Id__c = WaterfallConstants.targetKey(ownerId, sol, start, metric);
        rows.add(rec);
    }

    static PlayDraft copyOf(PlayDraft src) {
        PlayDraft d = new PlayDraft();
        if (src == null) return d;
        d.quota = src.quota;
        d.asp = src.asp;
        d.winRate = src.winRate;
        d.qualRate = src.qualRate;
        d.selfShare = src.selfShare;
        d.oppsPerConnect = src.oppsPerConnect;
        d.connectRate = src.connectRate;
        d.winsNeeded = src.winsNeeded;
        d.qoNeeded = src.qoNeeded;
        d.oppsToCreate = src.oppsToCreate;
        d.selfSourced = src.selfSourced;
        d.channelOpps = src.channelOpps;
        d.connectsNeeded = src.connectsNeeded;
        d.dialsNeeded = src.dialsNeeded;
        d.haveQo = src.haveQo;
        d.created = src.created;
        d.actualDials = src.actualDials;
        d.actualConnects = src.actualConnects;
        d.activityIndicative = src.activityIndicative;
        d.normalConnectRate = src.normalConnectRate;
        return d;
    }

    static Decimal mul(Decimal a, Decimal b) {
        if (a == null || b == null) return null;
        return a * b;
    }
}
