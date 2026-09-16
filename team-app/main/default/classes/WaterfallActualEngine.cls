/**
 * Nightly actuals: quota, open qualified book, created pipeline, and the
 * Salesloft activity layer (dispositioned dials only).
 */
public with sharing class WaterfallActualEngine {

    public class ActualRow {
        @AuraEnabled public Id ownerId;
        @AuraEnabled public Decimal quota;
        @AuraEnabled public Integer openQualified;
        @AuraEnabled public Decimal openQualifiedArr;
        @AuraEnabled public Integer created;
        @AuraEnabled public Integer selfSourcedCreated;
        @AuraEnabled public Integer dials;
        @AuraEnabled public Integer connects;
        @AuraEnabled public Integer emailsSent;
        @AuraEnabled public Integer replies;
        @AuraEnabled public Integer meetingsHeld;
        @AuraEnabled public Integer callTasks;
        @AuraEnabled public Integer dispositionedCalls;
        @AuraEnabled public Integer usableConnectDenom;
        @AuraEnabled public Decimal connectRate;
        @AuraEnabled public Decimal oppsPerConnect;
        @AuraEnabled public Decimal activityComplete;
        public ActualRow() {
            quota = 0; openQualified = 0; openQualifiedArr = 0;
            created = 0; selfSourcedCreated = 0;
            dials = 0; connects = 0; emailsSent = 0; replies = 0; meetingsHeld = 0;
            callTasks = 0; dispositionedCalls = 0; usableConnectDenom = 0;
        }
    }

    public class ActualSet {
        @AuraEnabled public Map<Id, ActualRow> byOwner = new Map<Id, ActualRow>();
        @AuraEnabled public Date periodStart;
        @AuraEnabled public Date periodEnd;
        @AuraEnabled public String periodLabel;
    }

    public static ActualSet measure(Set<Id> ownerIds, String productType, String sizeBand, Date asOf) {
        ActualSet out = new ActualSet();
        if (ownerIds == null || ownerIds.isEmpty()) return out;
        Date when = asOf == null ? Date.today() : asOf;
        out.periodStart = WaterfallConstants.periodStart(when);
        out.periodEnd = WaterfallConstants.periodEnd(when);
        out.periodLabel = WaterfallConstants.periodLabel(when);
        Set<String> solutions = CockpitConstants.solutionsInProductFilter(productType);
        Map<Id, ActualRow> rows = new Map<Id, ActualRow>();
        for (Id oid : ownerIds) {
            ActualRow r = new ActualRow();
            r.ownerId = oid;
            rows.put(oid, r);
        }
        addQuota(rows, ownerIds, out.periodStart, out.periodEnd);
        addOpen(rows, ownerIds, solutions, sizeBand, out.periodStart, out.periodEnd);
        addCreated(rows, ownerIds, solutions, sizeBand, out.periodStart, out.periodEnd);
        addCalls(rows, ownerIds, out.periodStart, out.periodEnd);
        addEmails(rows, ownerIds, out.periodStart, out.periodEnd);
        addReplies(rows, ownerIds, out.periodStart, out.periodEnd);
        addMeetings(rows, ownerIds, out.periodStart, out.periodEnd);
        for (ActualRow r : rows.values()) finish(r);
        out.byOwner = rows;
        return out;
    }

    public static List<Waterfall_Actual__c> persist(ActualSet actuals) {
        if (actuals == null || actuals.byOwner == null) return new List<Waterfall_Actual__c>();
        List<Waterfall_Actual__c> recs = new List<Waterfall_Actual__c>();
        for (ActualRow r : actuals.byOwner.values()) {
            if (r.ownerId == null) continue;
            recs.add(toRecord(r, actuals));
        }
        if (!recs.isEmpty()) {
            upsert recs Waterfall_Actual__c.External_Id__c;
        }
        return recs;
    }

    static void addQuota(Map<Id, ActualRow> rows, Set<Id> ownerIds, Date periodStart, Date periodEnd) {
        for (Sales_Plan__c p : [
            SELECT Sales_Rep__c, Quota_Amount__c, Start_Date__c
            FROM Sales_Plan__c
            WHERE Sales_Rep__c IN :ownerIds
              AND Start_Date__c >= :periodStart
              AND Start_Date__c <= :periodEnd
            WITH USER_MODE
        ]) {
            ActualRow row = rows.get(p.Sales_Rep__c);
            if (row == null) continue;
            row.quota += p.Quota_Amount__c == null ? 0 : p.Quota_Amount__c;
        }
    }

    static void addOpen(
        Map<Id, ActualRow> rows, Set<Id> ownerIds, Set<String> solutions,
        String sizeBand, Date periodStart, Date periodEnd
    ) {
        for (Opportunity o : [
            SELECT OwnerId, ARR_Opportunity_Amount_USD_Num__c
            FROM Opportunity
            WHERE IsClosed = false
              AND OwnerId IN :ownerIds
              AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
              AND StageName NOT IN :CockpitConstants.MIGRATION_STAGES
              AND SQL_Datestamp_bf__c != null
              AND CloseDate >= :periodStart AND CloseDate <= :periodEnd
              AND EUNA_Solution__c IN :solutions
            WITH USER_MODE
        ]) {
            if (!WaterfallConstants.matchesSize(o.ARR_Opportunity_Amount_USD_Num__c, sizeBand)) continue;
            ActualRow row = rows.get(o.OwnerId);
            if (row == null) continue;
            row.openQualified++;
            row.openQualifiedArr += o.ARR_Opportunity_Amount_USD_Num__c == null
                ? 0 : o.ARR_Opportunity_Amount_USD_Num__c;
        }
    }

    static void addCreated(
        Map<Id, ActualRow> rows, Set<Id> ownerIds, Set<String> solutions,
        String sizeBand, Date periodStart, Date periodEnd
    ) {
        Datetime createdFrom = Datetime.newInstanceGmt(periodStart, Time.newInstance(0, 0, 0, 0));
        Datetime createdTo = Datetime.newInstanceGmt(periodEnd, Time.newInstance(23, 59, 59, 0));
        for (Opportunity o : [
            SELECT OwnerId, Primary_Team_Source__c, ARR_Opportunity_Amount_USD_Num__c
            FROM Opportunity
            WHERE CreatedDate >= :createdFrom AND CreatedDate <= :createdTo
              AND OwnerId IN :ownerIds
              AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
              AND StageName NOT IN :CockpitConstants.MIGRATION_STAGES
              AND EUNA_Solution__c IN :solutions
            WITH USER_MODE
        ]) {
            if (!WaterfallConstants.matchesSize(o.ARR_Opportunity_Amount_USD_Num__c, sizeBand)) continue;
            ActualRow row = rows.get(o.OwnerId);
            if (row == null) continue;
            row.created++;
            if (WaterfallConstants.isSelfSourced(o.Primary_Team_Source__c)) {
                row.selfSourcedCreated++;
            }
        }
    }

    static void addCalls(Map<Id, ActualRow> rows, Set<Id> ownerIds, Date periodStart, Date periodEnd) {
        for (AggregateResult ar : [
            SELECT OwnerId oid, SalesLoft1__Call_Disposition__c disp, COUNT(Id) cnt
            FROM Task
            WHERE OwnerId IN :ownerIds
              AND TaskSubtype = 'Call'
              AND Status = 'Completed'
              AND ActivityDate >= :periodStart AND ActivityDate <= :periodEnd
            GROUP BY OwnerId, SalesLoft1__Call_Disposition__c
            WITH USER_MODE
        ]) {
            Id oid = (Id) ar.get('oid');
            ActualRow row = rows.get(oid);
            if (row == null) continue;
            Integer n = ((Decimal) ar.get('cnt')).intValue();
            String disp = (String) ar.get('disp');
            row.callTasks += n;
            if (String.isBlank(disp)) continue;
            row.dispositionedCalls += n;
            row.dials += n;
            if (disp == WaterfallConstants.DISPOSITION_CONNECTED) row.connects += n;
            if (!WaterfallConstants.BAD_NUMBER_DISPOSITIONS.contains(disp)) {
                row.usableConnectDenom += n;
            }
        }
    }

    static void addEmails(Map<Id, ActualRow> rows, Set<Id> ownerIds, Date periodStart, Date periodEnd) {
        for (AggregateResult ar : [
            SELECT OwnerId oid, COUNT(Id) cnt
            FROM Task
            WHERE OwnerId IN :ownerIds
              AND TaskSubtype = 'Email'
              AND Status = 'Completed'
              AND ActivityDate >= :periodStart AND ActivityDate <= :periodEnd
              AND Auto_Reply__c = false
            GROUP BY OwnerId
            WITH USER_MODE
        ]) {
            ActualRow row = rows.get((Id) ar.get('oid'));
            if (row == null) continue;
            row.emailsSent = ((Decimal) ar.get('cnt')).intValue();
        }
    }

    static void addReplies(Map<Id, ActualRow> rows, Set<Id> ownerIds, Date periodStart, Date periodEnd) {
        Datetime fromDt = Datetime.newInstanceGmt(periodStart, Time.newInstance(0, 0, 0, 0));
        Datetime toDt = Datetime.newInstanceGmt(periodEnd, Time.newInstance(23, 59, 59, 0));
        for (AggregateResult ar : [
            SELECT CreatedById oid, COUNT(Id) cnt
            FROM EmailMessage
            WHERE CreatedById IN :ownerIds
              AND Incoming = true
              AND MessageDate >= :fromDt AND MessageDate <= :toDt
            GROUP BY CreatedById
            WITH USER_MODE
        ]) {
            ActualRow row = rows.get((Id) ar.get('oid'));
            if (row == null) continue;
            row.replies = ((Decimal) ar.get('cnt')).intValue();
        }
    }

    static void addMeetings(Map<Id, ActualRow> rows, Set<Id> ownerIds, Date periodStart, Date periodEnd) {
        Datetime fromDt = Datetime.newInstanceGmt(periodStart, Time.newInstance(0, 0, 0, 0));
        Datetime toDt = Datetime.newInstance(periodEnd, Time.newInstance(23, 59, 59, 0));
        Datetime nowDt = Datetime.now();
        if (toDt > nowDt) toDt = nowDt;
        if (fromDt > toDt) return;
        for (AggregateResult ar : [
            SELECT OwnerId oid, COUNT(Id) cnt
            FROM Event
            WHERE OwnerId IN :ownerIds
              AND StartDateTime >= :fromDt AND StartDateTime <= :toDt
            GROUP BY OwnerId
            WITH USER_MODE
        ]) {
            ActualRow row = rows.get((Id) ar.get('oid'));
            if (row == null) continue;
            row.meetingsHeld = ((Decimal) ar.get('cnt')).intValue();
        }
    }

    static void finish(ActualRow r) {
        r.connectRate = WaterfallConstants.safeDiv(r.connects, r.usableConnectDenom);
        r.oppsPerConnect = WaterfallConstants.safeDiv(r.selfSourcedCreated, r.connects);
        r.activityComplete = WaterfallConstants.safeDiv(r.dispositionedCalls, r.callTasks);
    }

    static Waterfall_Actual__c toRecord(ActualRow r, ActualSet actuals) {
        Waterfall_Actual__c rec = new Waterfall_Actual__c();
        rec.AE__c = r.ownerId;
        rec.Period_Start__c = actuals.periodStart;
        rec.Period_End__c = actuals.periodEnd;
        rec.Period_Label__c = actuals.periodLabel;
        rec.Quota_Amount__c = r.quota;
        rec.Open_Qualified_Count__c = r.openQualified;
        rec.Open_Qualified_Arr__c = r.openQualifiedArr;
        rec.Created_Count__c = r.created;
        rec.Self_Sourced_Created__c = r.selfSourcedCreated;
        rec.Dials__c = r.dials;
        rec.Connects__c = r.connects;
        rec.Emails_Sent__c = r.emailsSent;
        rec.Replies__c = r.replies;
        rec.Meetings_Held__c = r.meetingsHeld;
        rec.Activity_Data_Complete__c = r.activityComplete;
        rec.External_Id__c = String.valueOf(r.ownerId) + '|ALL|' + String.valueOf(actuals.periodStart);
        return rec;
    }
}
