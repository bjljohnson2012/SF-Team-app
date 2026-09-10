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
        @AuraEnabled public String account, ae, stage, klass, reason, nextStep;
        @AuraEnabled public Decimal arr, pushes;
        @AuraEnabled public Integer score;
        @AuraEnabled public Date closeDate;
    }

    public class Payload {
        @AuraEnabled public List<Deal> deals;
        @AuraEnabled public Integer teamSize;
        @AuraEnabled public Decimal highArr, medArr, modeledCall;
        @AuraEnabled public String quarterLabel;
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
        Date winEnd = winStart.addMonths(9).addDays(-1);

        List<Opportunity> opps = [
            SELECT Id, Name, Account.Name, Owner.Name, StageName, CloseDate,
                   ARR_Opportunity_Amount_USD_Num__c, Pricing_Approval_Status__c,
                   SQL_Datestamp_bf__c, Next_Step_Date_bf__c, Next_Step_bf__c,
                   LastActivityDate
            FROM Opportunity
            WHERE IsClosed = false
              AND OwnerId IN :owners
              AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
              AND CloseDate >= :winStart AND CloseDate <= :winEnd
            WITH USER_MODE
            ORDER BY ARR_Opportunity_Amount_USD_Num__c DESC NULLS LAST
            LIMIT 500
        ];

        Map<Id, Decimal> pushMap = pushCounts(new Map<Id, Opportunity>(opps).keySet());

        Payload p = new Payload();
        p.deals = new List<Deal>();
        p.teamSize = owners.size();
        p.highArr = 0;
        p.medArr = 0;

        for (Opportunity o : opps) {
            Decimal pushes = pushMap.containsKey(o.Id) ? pushMap.get(o.Id) : 0;
            CockpitScoreService.Result r = CockpitScoreService.score(o, null, pushes, today);

            Deal d = new Deal();
            d.id        = o.Id;
            d.account   = (o.Account != null) ? o.Account.Name : o.Name;
            d.ae        = (o.Owner != null) ? o.Owner.Name : null;
            d.stage     = o.StageName;
            d.arr       = o.ARR_Opportunity_Amount_USD_Num__c;
            d.closeDate = o.CloseDate;
            d.nextStep  = o.Next_Step_bf__c;
            d.pushes    = pushes;
            d.score     = r.score;
            d.klass     = r.klass;
            d.reason    = r.reason;
            p.deals.add(d);

            if (d.arr != null) {
                if (r.klass == 'HI') p.highArr += d.arr;
                else if (r.klass == 'MD') p.medArr += d.arr;
            }
        }

        p.modeledCall = (p.highArr * CockpitConstants.WEIGHT_HIGH_PCT / 100)
                      + (p.medArr * CockpitConstants.WEIGHT_MED_PCT / 100);
        p.quarterLabel = today.year() + ' Q' + q + ' \u2192 +9mo';
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
}
