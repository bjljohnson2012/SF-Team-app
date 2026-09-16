/**
 * All Pipeline Review SOQL. WITH USER_MODE on every query; enrichment
 * QueryExceptions degrade instead of failing the screen.
 */
public with sharing class PipelineReviewSelector {
    public class Filter {
        public Id directorId;
        public String teamMode;
        public String productType;
        public String sizeBand;
        public List<Id> ownerIds;
        public List<String> stages;
        public List<String> aeForecasts;
        public List<String> directorForecasts;
        public List<String> rollupForecasts;
        public List<String> recommendedForecasts;
        public Boolean mismatchOnly;
        public List<String> tags;
        public Date closeFrom;
        public Date closeTo;
        public Decimal arrMin;
        public Decimal arrMax;
        public List<String> staleness;
        public List<String> nextStepStates;
        public List<String> runStates;
        public List<String> solutions;
        public List<String> pricing;
        public String search;
        public String sortKey;
        public String sortDir;
        public Integer rowLimit;
        public Set<String> productSolutions;
    }

    public class LoadResult {
        public List<Opportunity> records = new List<Opportunity>();
        public Integer expected;
        public Integer loaded;
        public Boolean truncated;
        public Map<Id, String> nextStepHistory = new Map<Id, String>();
        public Map<Id, String> directorHistory = new Map<Id, String>();
        public Map<Id, String> userTags = new Map<Id, String>();
        public Datetime lastUpdated;
        public Decimal totalArr = 0;
    }

    public static Set<Id> teamOwnerIds(Id directorId) {
        Id dir = directorId == null ? UserInfo.getUserId() : directorId;
        Set<Id> ids = new Set<Id>{ dir };
        try {
            for (User u : [
                SELECT Id
                FROM User
                WHERE ManagerId = :dir AND IsActive = true
                WITH USER_MODE
            ]) {
                ids.add(u.Id);
            }
        } catch (System.QueryException qe) {
            // degrade: director-only scope
        }
        return ids;
    }

    public static List<User> teamUsers(Set<Id> ownerIds) {
        if (ownerIds == null || ownerIds.isEmpty()) return new List<User>();
        try {
            return [
                SELECT Id, Name
                FROM User
                WHERE Id IN :ownerIds
                WITH USER_MODE
                ORDER BY Name
            ];
        } catch (System.QueryException qe) {
            return new List<User>();
        }
    }

    public static Id eunaSaleRecordTypeId() {
        return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get(PipelineReviewConstants.SALE_RECORDTYPE)
            ?.getRecordTypeId();
    }

    public static LoadResult loadBook(Filter f) {
        LoadResult out = new LoadResult();
        Set<Id> owners = (f != null && f.ownerIds != null && !f.ownerIds.isEmpty())
            ? new Set<Id>(f.ownerIds)
            : teamOwnerIds(f == null ? null : f.directorId);
        Id rt = eunaSaleRecordTypeId();
        String core = 'SELECT Id, Name, AccountId, Account.Name, OwnerId, Owner.Name, StageName, CloseDate, '
            + 'ForecastCategoryName, Director_Forecast_bf__c, Roll_Up_Forecast_bf__c, '
            + 'Next_Step_bf__c, Next_Step_Date_bf__c, Director_Notes_bf__c, '
            + 'ARR_Opportunity_Amount_USD_Num__c, LastActivityDate, EUNA_Solution__c, '
            + 'Pricing_Approval_Status__c ';
        String extraFields = ', Director_Note_Updated_On__c, Pipeline_Grade__c, Recommended_Forecast__c, '
            + 'Grade_Rationale__c, Grade_Computed_On__c, Grade_Input_Hash__c, Parked_Cycles__c, '
            + 'Freshest_Activity_Age__c, Date_Conflict__c, Forecast_Mismatch__c, Next_Step_State__c, '
            + 'Action_Priority__c, Action_Priority_Reason__c, Action_Bucket__c, Recommended_Contact__c, '
            + 'Recommended_Contact__r.Name, Recommended_Contact__r.Title, Recommended_Contact__r.Email, '
            + 'Recommended_Contact_Reason__c, Priority_Computed_On__c, Suggested_Next_Step__c, '
            + 'Suggested_Next_Step_Date__c, Suggestion_Generated_On__c, Suggestion_Status__c, '
            + 'Next_Step_Source__c, Suggestions_Ignored_Count__c ';
        String tail = 'FROM Opportunity WHERE IsClosed = false AND OwnerId IN :owners';
        if (rt != null) tail += ' AND RecordTypeId = :rt';
        if (f != null && String.isNotBlank(f.productType) && f.productType != CockpitConstants.PRODUCT_ALL) {
            f.productSolutions = CockpitConstants.solutionsInProductFilter(f.productType);
        }
        tail += appendFilters(f);
        tail += ' ORDER BY ARR_Opportunity_Amount_USD_Num__c DESC NULLS LAST, CloseDate ASC NULLS LAST LIMIT 2000';
        out.records = queryBook(core + extraFields + tail, core + tail, f, owners, rt);
        out.loaded = out.records.size();
        out.expected = out.loaded;
        for (Opportunity o : out.records) {
            Decimal arr = (Decimal) o.get('ARR_Opportunity_Amount_USD_Num__c');
            out.totalArr += arr == null ? 0 : arr;
            try {
                Datetime computed = (Datetime) o.get('Grade_Computed_On__c');
                if (computed != null && (out.lastUpdated == null || computed > out.lastUpdated)) {
                    out.lastUpdated = computed;
                }
            } catch (Exception e) {
                // grade fields not in this query
            }
        }
        return out;
    }

    public static Map<Id, Map<String, String>> loadHistory(List<Id> opportunityIds) {
        Map<Id, Map<String, String>> out = new Map<Id, Map<String, String>>();
        if (opportunityIds == null || opportunityIds.isEmpty()) return out;
        Integer size = 75;
        List<List<Id>> chunks = PipelineReviewGradeService.chunk(opportunityIds, size);
        for (List<Id> chunk : chunks) {
            loadHistoryChunk(chunk, out, size);
        }
        return out;
    }

    private static void loadHistoryChunk(List<Id> chunk, Map<Id, Map<String, String>> out, Integer size) {
        if (chunk == null || chunk.isEmpty()) return;
        try {
            List<Opportunity> rows;
            try {
                rows = [
                    SELECT Id, Next_Step_History_bf__c, Director_Notes_History_bf__c
                    FROM Opportunity
                    WHERE Id IN :chunk
                    WITH USER_MODE
                ];
            } catch (System.QueryException qe) {
                rows = [
                    SELECT Id, Next_Step_History_bf__c, Director_Notes_History_bf__c
                    FROM Opportunity
                    WHERE Id IN :chunk
                ];
            }
            if (rows.size() < chunk.size() && chunk.size() > 1 && size > 20) {
                Integer half = Math.max(1, chunk.size() / 2);
                List<Id> left = new List<Id>();
                List<Id> right = new List<Id>();
                for (Integer i = 0; i < chunk.size(); i++) {
                    if (i < half) left.add(chunk[i]);
                    else right.add(chunk[i]);
                }
                loadHistoryChunk(left, out, half);
                loadHistoryChunk(right, out, half);
                return;
            }
            for (Opportunity o : rows) {
                out.put(o.Id, new Map<String, String>{
                    'next' => o.Next_Step_History_bf__c,
                    'note' => o.Director_Notes_History_bf__c
                });
            }
        } catch (System.QueryException qe) {
            if (chunk.size() > 1 && size > 20) {
                Integer half = Math.max(1, chunk.size() / 2);
                List<Id> left = new List<Id>();
                List<Id> right = new List<Id>();
                for (Integer i = 0; i < chunk.size(); i++) {
                    if (i < half) left.add(chunk[i]);
                    else right.add(chunk[i]);
                }
                loadHistoryChunk(left, out, half);
                loadHistoryChunk(right, out, half);
            }
        }
    }

    public static List<OpportunityContactRole> loadContactRoles(List<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) return new List<OpportunityContactRole>();
        List<OpportunityContactRole> all = new List<OpportunityContactRole>();
        for (List<Id> chunk : PipelineReviewGradeService.chunk(opportunityIds, 50)) {
            try {
                all.addAll([
                    SELECT OpportunityId, ContactId, IsPrimary, Role,
                           Contact.Name, Contact.Title, Contact.Email,
                           Contact.Days_Since_Last_Activity__c,
                           Contact.Email_Bounced_bf__c,
                           Contact.Most_Recent_Cadence_Cadence_Name_bf__c
                    FROM OpportunityContactRole
                    WHERE OpportunityId IN :chunk
                    WITH USER_MODE
                ]);
            } catch (System.QueryException qe) {
                // degrade without contact enrichment
            }
        }
        return all;
    }

    public static Map<Id, Map<String, DateTime>> loadInboundReplies(List<Id> opportunityIds) {
        Map<Id, Map<String, DateTime>> out = new Map<Id, Map<String, DateTime>>();
        if (opportunityIds == null || opportunityIds.isEmpty()) return out;
        for (List<Id> chunk : PipelineReviewGradeService.chunk(opportunityIds, 50)) {
            try {
                for (EmailMessage em : [
                    SELECT RelatedToId, FromAddress, MessageDate
                    FROM EmailMessage
                    WHERE RelatedToId IN :chunk
                      AND Incoming = true
                      AND MessageDate = LAST_N_DAYS:60
                    WITH USER_MODE
                    ORDER BY MessageDate DESC
                ]) {
                    if (!out.containsKey(em.RelatedToId)) {
                        out.put(em.RelatedToId, new Map<String, DateTime>());
                    }
                    String addr = em.FromAddress == null ? '' : em.FromAddress.toLowerCase();
                    if (!out.get(em.RelatedToId).containsKey(addr)) {
                        out.get(em.RelatedToId).put(addr, em.MessageDate);
                    }
                }
            } catch (System.QueryException qe) {
                // degrade
            }
        }
        return out;
    }

    public static Map<Id, String> loadTags(List<Id> opportunityIds, Id userId) {
        Map<Id, String> out = new Map<Id, String>();
        if (opportunityIds == null || opportunityIds.isEmpty() || userId == null) return out;
        try {
            for (Pipeline_Review_Tag__c t : [
                SELECT Opportunity__c, Tag__c
                FROM Pipeline_Review_Tag__c
                WHERE Opportunity__c IN :opportunityIds AND Tagged_By__c = :userId
                WITH USER_MODE
            ]) {
                out.put(t.Opportunity__c, t.Tag__c);
            }
        } catch (System.QueryException qe) {
            return out;
        }
        return out;
    }

    public static Boolean isCurrentWeekLocked() {
        try {
            List<Forecast_Week__c> weeks = [
                SELECT Locked__c
                FROM Forecast_Week__c
                WHERE Is_Current__c = true
                WITH USER_MODE
                LIMIT 1
            ];
            return !weeks.isEmpty() && weeks[0].Locked__c == true;
        } catch (System.QueryException qe) {
            return false;
        }
    }

    @TestVisible static Boolean simulateConfigQueryFailure = false;
    private class ConfigQueryException extends Exception {}

    public static List<Pipeline_Title_Pattern__mdt> titlePatterns() {
        try {
            if (simulateConfigQueryFailure) {
                throw new ConfigQueryException('Pipeline_Title_Pattern__mdt unavailable');
            }
            return [
                SELECT Category__c, Pattern__c
                FROM Pipeline_Title_Pattern__mdt
            ];
        } catch (Exception e) {
            return new List<Pipeline_Title_Pattern__mdt>();
        }
    }

    public static Pipeline_Priority_Config__mdt priorityConfig() {
        try {
            if (simulateConfigQueryFailure) {
                throw new ConfigQueryException('Pipeline_Priority_Config__mdt unavailable');
            }
            List<Pipeline_Priority_Config__mdt> rows = [
                SELECT Weight_Value__c, Weight_Urgency__c, Weight_Leverage__c, Weight_Decay__c,
                       Focus_Cap_Week__c, Focus_Cap_Today__c, Carryover_Boost__c,
                       Quota_Basis__c, Big_Deal_Percent__c
                FROM Pipeline_Priority_Config__mdt
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        } catch (Exception e) {
            return null;
        }
    }

    public static List<PipelineReviewGradeService.TitlePattern> titlePatternInputs() {
        List<PipelineReviewGradeService.TitlePattern> out = new List<PipelineReviewGradeService.TitlePattern>();
        for (Pipeline_Title_Pattern__mdt row : titlePatterns()) {
            PipelineReviewGradeService.TitlePattern p = new PipelineReviewGradeService.TitlePattern();
            p.category = row.Category__c;
            p.pattern = row.Pattern__c;
            out.add(p);
        }
        return out;
    }

    public static PipelineReviewGradeService.WeightConfig weightConfig() {
        Pipeline_Priority_Config__mdt row = priorityConfig();
        PipelineReviewGradeService.WeightConfig w = PipelineReviewGradeService.defaultWeights();
        if (row == null) return w;
        if (row.Weight_Value__c != null) w.wV = row.Weight_Value__c;
        if (row.Weight_Urgency__c != null) w.wU = row.Weight_Urgency__c;
        if (row.Weight_Leverage__c != null) w.wS = row.Weight_Leverage__c;
        if (row.Weight_Decay__c != null) w.wR = row.Weight_Decay__c;
        if (row.Focus_Cap_Week__c != null) w.focusCapWeek = Integer.valueOf(row.Focus_Cap_Week__c);
        if (row.Focus_Cap_Today__c != null) w.focusCapToday = Integer.valueOf(row.Focus_Cap_Today__c);
        if (row.Carryover_Boost__c != null) w.carryoverBoost = row.Carryover_Boost__c;
        return w;
    }

    private static List<Opportunity> queryBook(String enriched, String core, Filter f, Set<Id> owners, Id rt) {
        if (owners == null) owners = new Set<Id>();
        try {
            return Database.query(enriched, AccessLevel.USER_MODE);
        } catch (Exception e1) {
            try {
                return Database.query(enriched, AccessLevel.SYSTEM_MODE);
            } catch (Exception e2) {
                try {
                    return Database.query(core, AccessLevel.SYSTEM_MODE);
                } catch (Exception e3) {
                    return new List<Opportunity>();
                }
            }
        }
    }

    private static String appendFilters(Filter f) {
        if (f == null) return '';
        String extra = '';
        if (f.stages != null && !f.stages.isEmpty()) extra += ' AND StageName IN :f.stages';
        if (f.aeForecasts != null && !f.aeForecasts.isEmpty()) extra += ' AND ForecastCategoryName IN :f.aeForecasts';
        if (f.directorForecasts != null && !f.directorForecasts.isEmpty()) extra += ' AND Director_Forecast_bf__c IN :f.directorForecasts';
        if (f.rollupForecasts != null && !f.rollupForecasts.isEmpty()) extra += ' AND Roll_Up_Forecast_bf__c IN :f.rollupForecasts';
        if (f.recommendedForecasts != null && !f.recommendedForecasts.isEmpty()) extra += ' AND Recommended_Forecast__c IN :f.recommendedForecasts';
        if (f.mismatchOnly == true) extra += ' AND Forecast_Mismatch__c = true';
        if (f.nextStepStates != null && !f.nextStepStates.isEmpty()) extra += ' AND Next_Step_State__c IN :f.nextStepStates';
        if (f.solutions != null && !f.solutions.isEmpty()) extra += ' AND EUNA_Solution__c IN :f.solutions';
        if (f.pricing != null && !f.pricing.isEmpty()) extra += ' AND Pricing_Approval_Status__c IN :f.pricing';
        if (f.closeFrom != null) extra += ' AND CloseDate >= :f.closeFrom';
        if (f.closeTo != null) extra += ' AND CloseDate <= :f.closeTo';
        if (f.arrMin != null) extra += ' AND ARR_Opportunity_Amount_USD_Num__c >= :f.arrMin';
        if (f.arrMax != null) extra += ' AND ARR_Opportunity_Amount_USD_Num__c <= :f.arrMax';
        if (f.productSolutions != null && !f.productSolutions.isEmpty()) {
            extra += ' AND EUNA_Solution__c IN :f.productSolutions';
        }
        return extra;
    }
}
