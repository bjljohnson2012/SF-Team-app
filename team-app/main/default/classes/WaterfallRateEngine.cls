/**
 * Calibrates waterfall rates from trailing closed business. Gated win rate,
 * ARR-bearing ASP, median cycle, true-cohort qualification, self-sourced mix.
 */
public with sharing class WaterfallRateEngine {

    public class RateRow {
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String solution;
        @AuraEnabled public Integer closedCount;
        @AuraEnabled public Integer wins;
        @AuraEnabled public Integer arrBearingWins;
        @AuraEnabled public Decimal arrWon;
        @AuraEnabled public Decimal winRateRaw;
        @AuraEnabled public Decimal winRateBlended;
        @AuraEnabled public Decimal winRateUngated;
        @AuraEnabled public Decimal aspRaw;
        @AuraEnabled public Decimal aspBlended;
        @AuraEnabled public Decimal cycleMedianDays;
        @AuraEnabled public Integer landsQuarters;
        @AuraEnabled public Decimal qualRate;
        @AuraEnabled public Decimal selfSourcedShare;
        @AuraEnabled public String sampleConfidence;
        public Integer ungatedClosed;
        public Integer ungatedWins;
        public Integer created;
        public Integer createdQualified;
        public Integer sqlCount;
        public Integer selfSourcedSql;
        public List<Decimal> cycleDays;
        public RateRow() {
            closedCount = 0; wins = 0; arrBearingWins = 0; arrWon = 0;
            ungatedClosed = 0; ungatedWins = 0;
            created = 0; createdQualified = 0; sqlCount = 0; selfSourcedSql = 0;
            cycleDays = new List<Decimal>();
        }
    }

    public class RateSet {
        @AuraEnabled public Map<Id, RateRow> byOwner = new Map<Id, RateRow>();
        @AuraEnabled public RateRow team;
        @AuraEnabled public Date windowStart;
        @AuraEnabled public Date windowEnd;
    }

    public static RateSet calibrate(Set<Id> ownerIds, String productType, String sizeBand, Date asOf) {
        RateSet out = new RateSet();
        if (ownerIds == null || ownerIds.isEmpty()) return out;
        Date asOfDay = asOf == null ? Date.today() : asOf;
        out.windowStart = WaterfallConstants.windowStart(asOfDay);
        out.windowEnd = WaterfallConstants.periodEnd(asOfDay);
        Set<String> solutions = CockpitConstants.solutionsInProductFilter(productType);
        Map<Id, RateRow> rows = new Map<Id, RateRow>();
        for (Id oid : ownerIds) {
            RateRow r = new RateRow();
            r.ownerId = oid;
            rows.put(oid, r);
        }
        RateRow team = new RateRow();

        addClosed(rows, team, ownerIds, solutions, sizeBand, out.windowStart);
        addCreated(rows, team, ownerIds, solutions, sizeBand, out.windowStart);
        addChannel(rows, team, ownerIds, solutions, sizeBand, out.windowStart);

        finish(team, null);
        for (Id oid : rows.keySet()) finish(rows.get(oid), team);
        out.byOwner = rows;
        out.team = team;
        return out;
    }

    public static List<Waterfall_Rate__c> persist(RateSet rates) {
        if (rates == null || rates.byOwner == null) return new List<Waterfall_Rate__c>();
        List<Waterfall_Rate__c> recs = new List<Waterfall_Rate__c>();
        for (RateRow r : rates.byOwner.values()) {
            if (r.ownerId == null) continue;
            recs.add(toRecord(r, rates.windowStart, rates.windowEnd));
        }
        if (!recs.isEmpty()) {
            upsert recs Waterfall_Rate__c.External_Id__c;
        }
        return recs;
    }

    static void addClosed(
        Map<Id, RateRow> rows, RateRow team, Set<Id> ownerIds,
        Set<String> solutions, String sizeBand, Date windowStart
    ) {
        for (Opportunity o : [
            SELECT OwnerId, IsWon, ARR_Opportunity_Amount_USD_Num__c, EUNA_Solution__c,
                   SQL_Datestamp_bf__c, Days_since_SQL__c, Lost_Reason__c
            FROM Opportunity
            WHERE IsClosed = true
              AND CloseDate >= :windowStart
              AND OwnerId IN :ownerIds
              AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
              AND StageName NOT IN :CockpitConstants.MIGRATION_STAGES
              AND EUNA_Solution__c IN :solutions
            WITH USER_MODE
        ]) {
            if (!WaterfallConstants.matchesSize(o.ARR_Opportunity_Amount_USD_Num__c, sizeBand)) continue;
            RateRow row = rows.get(o.OwnerId);
            if (row == null) continue;
            tapClosed(row, o);
            tapClosed(team, o);
        }
    }

    @TestVisible
    static RateRow applyClosedForTest(
        List<Boolean> won, List<Decimal> arr, List<Date> sql,
        List<Decimal> days, List<String> lostReason
    ) {
        RateRow row = new RateRow();
        Integer n = won == null ? 0 : won.size();
        for (Integer i = 0; i < n; i++) {
            tapClosed(
                row,
                won[i],
                arr == null ? null : arr[i],
                sql == null ? null : sql[i],
                days == null ? null : days[i],
                lostReason == null ? null : lostReason[i]
            );
        }
        finish(row, null);
        return row;
    }

    static void tapClosed(RateRow row, Opportunity o) {
        tapClosed(
            row, o.IsWon, o.ARR_Opportunity_Amount_USD_Num__c,
            o.SQL_Datestamp_bf__c, o.Days_since_SQL__c, o.Lost_Reason__c
        );
    }

    static void tapClosed(
        RateRow row, Boolean isWon, Decimal arr, Date sql, Decimal days, String lostReason
    ) {
        row.ungatedClosed++;
        if (isWon == true) row.ungatedWins++;
        Boolean gated = sql != null
            && (isWon == true || WaterfallConstants.isCompetitiveLoss(lostReason));
        if (!gated) return;
        row.closedCount++;
        if (isWon == true) {
            row.wins++;
            Decimal amount = arr == null ? 0 : arr;
            if (amount > 0) {
                row.arrBearingWins++;
                row.arrWon += amount;
            }
            if (days != null && days >= 0) row.cycleDays.add(days);
        }
    }

    static void addCreated(
        Map<Id, RateRow> rows, RateRow team, Set<Id> ownerIds,
        Set<String> solutions, String sizeBand, Date windowStart
    ) {
        Datetime createdFrom = Datetime.newInstanceGmt(windowStart, Time.newInstance(0, 0, 0, 0));
        for (Opportunity o : [
            SELECT OwnerId, SQL_Datestamp_bf__c, ARR_Opportunity_Amount_USD_Num__c
            FROM Opportunity
            WHERE CreatedDate >= :createdFrom
              AND OwnerId IN :ownerIds
              AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
              AND StageName NOT IN :CockpitConstants.MIGRATION_STAGES
              AND EUNA_Solution__c IN :solutions
            WITH USER_MODE
        ]) {
            if (!WaterfallConstants.matchesSize(o.ARR_Opportunity_Amount_USD_Num__c, sizeBand)) continue;
            RateRow row = rows.get(o.OwnerId);
            if (row == null) continue;
            row.created++;
            team.created++;
            if (o.SQL_Datestamp_bf__c != null) {
                row.createdQualified++;
                team.createdQualified++;
            }
        }
    }

    static void addChannel(
        Map<Id, RateRow> rows, RateRow team, Set<Id> ownerIds,
        Set<String> solutions, String sizeBand, Date windowStart
    ) {
        for (Opportunity o : [
            SELECT OwnerId, Primary_Team_Source__c, ARR_Opportunity_Amount_USD_Num__c
            FROM Opportunity
            WHERE SQL_Datestamp_bf__c >= :windowStart
              AND OwnerId IN :ownerIds
              AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
              AND StageName NOT IN :CockpitConstants.MIGRATION_STAGES
              AND EUNA_Solution__c IN :solutions
            WITH USER_MODE
        ]) {
            if (!WaterfallConstants.matchesSize(o.ARR_Opportunity_Amount_USD_Num__c, sizeBand)) continue;
            RateRow row = rows.get(o.OwnerId);
            if (row == null) continue;
            row.sqlCount++;
            team.sqlCount++;
            if (WaterfallConstants.isSelfSourced(o.Primary_Team_Source__c)) {
                row.selfSourcedSql++;
                team.selfSourcedSql++;
            }
        }
    }

    static void finish(RateRow row, RateRow baseline) {
        row.winRateRaw = WaterfallConstants.safeDiv(row.wins, row.closedCount);
        row.winRateUngated = WaterfallConstants.safeDiv(row.ungatedWins, row.ungatedClosed);
        row.aspRaw = WaterfallConstants.safeDiv(row.arrWon, row.arrBearingWins);
        row.qualRate = WaterfallConstants.safeDiv(row.createdQualified, row.created);
        row.selfSourcedShare = WaterfallConstants.clampShare(
            WaterfallConstants.safeDiv(row.selfSourcedSql, row.sqlCount));
        row.cycleMedianDays = WaterfallConstants.median(row.cycleDays);
        row.landsQuarters = WaterfallConstants.landsQuarters(row.cycleMedianDays);
        row.sampleConfidence = WaterfallConstants.sampleConfidence(row.closedCount);
        if (baseline == null) {
            row.winRateBlended = row.winRateRaw;
            row.aspBlended = row.aspRaw;
            return;
        }
        row.winRateBlended = WaterfallConstants.blend(
            nzRate(row.winRateRaw, baseline.winRateRaw),
            row.closedCount,
            baseline.winRateRaw);
        row.aspBlended = WaterfallConstants.blend(
            nzRate(row.aspRaw, baseline.aspRaw),
            row.arrBearingWins,
            baseline.aspRaw);
    }

    static Decimal nzRate(Decimal personal, Decimal fallback) {
        return personal == null ? fallback : personal;
    }

    static Waterfall_Rate__c toRecord(RateRow r, Date windowStart, Date windowEnd) {
        String sol = String.isBlank(r.solution) ? WaterfallConstants.SOLUTION_ALL : r.solution;
        Waterfall_Rate__c rec = new Waterfall_Rate__c();
        rec.AE__c = r.ownerId;
        rec.Solution__c = r.solution;
        rec.Window_Start__c = windowStart;
        rec.Window_End__c = windowEnd;
        rec.Closed_Count__c = r.closedCount;
        rec.Wins__c = r.wins;
        rec.Arr_Bearing_Wins__c = r.arrBearingWins;
        rec.Arr_Won__c = r.arrWon;
        rec.Win_Rate_Raw__c = r.winRateRaw;
        rec.Win_Rate_Blended__c = r.winRateBlended;
        rec.Win_Rate_Ungated__c = r.winRateUngated;
        rec.ASP_Raw__c = r.aspRaw;
        rec.ASP_Blended__c = r.aspBlended;
        rec.Cycle_Median_Days__c = r.cycleMedianDays;
        rec.Lands_Quarters__c = r.landsQuarters;
        rec.Qual_Rate__c = r.qualRate;
        rec.Self_Sourced_Share__c = r.selfSourcedShare;
        rec.Sample_Confidence__c = r.sampleConfidence;
        rec.External_Id__c = String.valueOf(r.ownerId) + '|' + sol + '|'
            + String.valueOf(windowStart);
        return rec;
    }
}
