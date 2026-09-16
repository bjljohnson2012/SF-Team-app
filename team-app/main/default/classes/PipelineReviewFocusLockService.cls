/**
 * Job D — Monday 06:00 lock. Writes Pipeline_Week_Focus__c with frozen
 * rank/priority/reason. Idempotent on External_Id__c.
 */
public with sharing class PipelineReviewFocusLockService {
    public class LockResult {
        public Integer written;
        public Integer dropped;
        public Integer carried;
    }

    public static LockResult lockWeek(Date today) {
        Date monday = PipelineReviewController.weekStart(today);
        Date priorMonday = monday.addDays(-7);
        PipelineReviewGradeService.WeightConfig w = PipelineReviewSelector.weightConfig();
        Integer cap = w.focusCapWeek;
        Decimal boost = w.carryoverBoost == null ? PipelineReviewConstants.DEFAULT_CARRYOVER : w.carryoverBoost;
        LockResult result = new LockResult();
        result.written = 0;
        result.dropped = 0;
        result.carried = 0;

        Map<Id, User> directors = new Map<Id, User>();
        for (User u : [
            SELECT Id FROM User WHERE Id IN :PipelineReviewSelector.teamOwnerIds(UserInfo.getUserId())
        ]) directors.put(u.Id, u);

        Set<Id> users = new Set<Id>(directors.keySet());
        for (User report : [
            SELECT Id FROM User WHERE ManagerId IN :users AND IsActive = true
        ]) users.add(report.Id);

        Map<Id, Set<Id>> lastOpen = new Map<Id, Set<Id>>();
        for (Pipeline_Week_Focus__c prior : [
            SELECT Opportunity__c, User__c, Status__c
            FROM Pipeline_Week_Focus__c
            WHERE Week_Start__c = :priorMonday AND Status__c = :PipelineReviewConstants.FOCUS_OPEN
        ]) {
            if (!lastOpen.containsKey(prior.User__c)) lastOpen.put(prior.User__c, new Set<Id>());
            lastOpen.get(prior.User__c).add(prior.Opportunity__c);
        }

        List<Opportunity> book = [
            SELECT Id, OwnerId, Action_Priority__c, Action_Priority_Reason__c, Action_Bucket__c
            FROM Opportunity
            WHERE IsClosed = false
              AND OwnerId IN :users
              AND RecordType.DeveloperName = :PipelineReviewConstants.SALE_RECORDTYPE
        ];
        Map<Id, List<Opportunity>> byOwner = new Map<Id, List<Opportunity>>();
        for (Opportunity o : book) {
            if (!byOwner.containsKey(o.OwnerId)) byOwner.put(o.OwnerId, new List<Opportunity>());
            byOwner.get(o.OwnerId).add(o);
        }
        List<Pipeline_Week_Focus__c> upserts = new List<Pipeline_Week_Focus__c>();
        for (Id uid : byOwner.keySet()) {
            List<Scored> scored = new List<Scored>();
            Set<Id> carriedIds = lastOpen.containsKey(uid) ? lastOpen.get(uid) : new Set<Id>();
            for (Opportunity o : byOwner.get(uid)) {
                Scored s = new Scored();
                s.opp = o;
                s.priority = o.Action_Priority__c == null ? 0 : o.Action_Priority__c;
                s.carried = carriedIds.contains(o.Id);
                if (s.carried) s.priority += boost;
                scored.add(s);
            }
            scored.sort();
            Set<Id> kept = new Set<Id>();
            Integer rank = 1;
            for (Scored s : scored) {
                if (rank > cap) break;
                upserts.add(focusRow(s.opp, uid, monday, rank, s.priority, s.opp.Action_Priority_Reason__c,
                    PipelineReviewConstants.FOCUS_OPEN, s.carried));
                kept.add(s.opp.Id);
                if (s.carried) result.carried++;
                rank++;
                result.written++;
            }
            for (Id priorId : carriedIds) {
                if (kept.contains(priorId)) continue;
                Opportunity dummy = new Opportunity(Id = priorId);
                upserts.add(focusRow(dummy, uid, monday, cap + 1, 0, 'Dropped after carryover boost',
                    PipelineReviewConstants.FOCUS_DROPPED, true));
                result.dropped++;
            }
        }
        if (!upserts.isEmpty()) {
            Database.upsert(upserts, Pipeline_Week_Focus__c.External_Id__c, false);
        }
        return result;
    }

    private static Pipeline_Week_Focus__c focusRow(
        Opportunity o, Id uid, Date monday, Integer rank, Decimal priority, String reason,
        String status, Boolean carried
    ) {
        return new Pipeline_Week_Focus__c(
            Opportunity__c = o.Id,
            User__c = uid,
            Week_Start__c = monday,
            Rank__c = rank,
            Priority_At_Lock__c = priority,
            Reason_At_Lock__c = reason,
            Status__c = status,
            Carried_From_Prior_Week__c = carried,
            External_Id__c = String.valueOf(o.Id) + '-' + String.valueOf(uid) + '-' + String.valueOf(monday)
        );
    }

    private class Scored implements Comparable {
        public Opportunity opp;
        public Decimal priority;
        public Boolean carried;
        public Integer compareTo(Object other) {
            Scored o = (Scored) other;
            Decimal a = priority == null ? 0 : priority;
            Decimal b = o.priority == null ? 0 : o.priority;
            if (a == b) return 0;
            return a > b ? -1 : 1;
        }
    }
}
