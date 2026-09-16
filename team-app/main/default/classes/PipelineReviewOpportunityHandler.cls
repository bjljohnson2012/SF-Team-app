/**
 * Shared recompute used by Job A and the Opportunity trigger. Recursion-safe.
 * Queries are bulked; the grade engine itself stays pure.
 */
public with sharing class PipelineReviewOpportunityHandler {
    @TestVisible static Boolean running = false;

    public static void afterChange(List<Opportunity> news, Map<Id, Opportunity> oldMap) {
        if (running || news == null || news.isEmpty()) return;
        List<Opportunity> changed = new List<Opportunity>();
        for (Opportunity o : news) {
            if (oldMap == null || relevantChange(oldMap.get(o.Id), o)) changed.add(o);
        }
        if (changed.isEmpty()) return;
        // Leave the user save alone if this transaction is already near governor caps.
        if (Limits.getLimitQueries() - Limits.getQueries() < 20) return;
        running = true;
        try {
            recompute(changed, Date.today());
        } catch (Exception e) {
            // Config miss or grade-path error must never fail Opportunity DML.
            System.debug(LoggingLevel.ERROR,
                'PipelineReviewOpportunityHandler.afterChange degraded: '
                + e.getTypeName() + ' ' + e.getMessage());
        } finally {
            running = false;
        }
    }

    public static void recompute(List<Opportunity> scope, Date today) {
        if (scope == null || scope.isEmpty() || today == null) return;
        List<Id> ids = new List<Id>();
        Decimal maxArr = 1000;
        for (Opportunity o : scope) {
            ids.add(o.Id);
            Decimal arr = (Decimal) o.get('ARR_Opportunity_Amount_USD_Num__c');
            if (arr != null && arr > maxArr) maxArr = arr;
        }
        Map<Id, Map<String, String>> history = PipelineReviewSelector.loadHistory(ids);
        List<OpportunityContactRole> roles = PipelineReviewSelector.loadContactRoles(ids);
        Map<Id, Map<String, DateTime>> replies = PipelineReviewSelector.loadInboundReplies(ids);
        Map<Id, List<PipelineReviewGradeService.ContactCandidate>> byOpp =
            new Map<Id, List<PipelineReviewGradeService.ContactCandidate>>();
        for (OpportunityContactRole role : roles) {
            if (!byOpp.containsKey(role.OpportunityId)) {
                byOpp.put(role.OpportunityId, new List<PipelineReviewGradeService.ContactCandidate>());
            }
            PipelineReviewGradeService.ContactCandidate c = new PipelineReviewGradeService.ContactCandidate();
            c.contactId = role.ContactId;
            c.opportunityId = role.OpportunityId;
            c.name = role.Contact == null ? null : role.Contact.Name;
            c.title = role.Contact == null ? null : role.Contact.Title;
            c.email = role.Contact == null ? null : role.Contact.Email;
            c.isPrimary = role.IsPrimary;
            c.role = role.Role;
            c.daysSinceActivity = role.Contact == null || role.Contact.Days_Since_Last_Activity__c == null
                ? null : Integer.valueOf(role.Contact.Days_Since_Last_Activity__c);
            c.bounced = role.Contact != null && role.Contact.Email_Bounced_bf__c == true;
            c.inActiveCadence = role.Contact != null
                && String.isNotBlank(role.Contact.Most_Recent_Cadence_Cadence_Name_bf__c);
            if (replies.containsKey(role.OpportunityId) && c.email != null) {
                DateTime replied = replies.get(role.OpportunityId).get(c.email.toLowerCase());
                if (replied != null) c.inboundReplyAgeDays = replied.date().daysBetween(today);
            }
            byOpp.get(role.OpportunityId).add(c);
        }
        List<PipelineReviewGradeService.TitlePattern> patterns = PipelineReviewSelector.titlePatternInputs();
        PipelineReviewGradeService.WeightConfig weights = PipelineReviewSelector.weightConfig();
        Boolean locked = PipelineReviewSelector.isCurrentWeekLocked();
        List<Opportunity> updates = new List<Opportunity>();
        List<PipelineReviewGradeService.BucketRow> bucketRows = new List<PipelineReviewGradeService.BucketRow>();
        Map<Id, PipelineReviewGradeService.GradeResult> results = new Map<Id, PipelineReviewGradeService.GradeResult>();
        for (Opportunity o : scope) {
            PipelineReviewGradeService.GradeInput gi = new PipelineReviewGradeService.GradeInput();
            gi.opportunityId = o.Id;
            gi.stageName = o.StageName;
            gi.closeDate = o.CloseDate;
            gi.forecastCategoryName = o.ForecastCategoryName;
            gi.directorForecast = o.Director_Forecast_bf__c;
            gi.rollupForecast = o.Roll_Up_Forecast_bf__c;
            gi.nextStep = o.Next_Step_bf__c;
            gi.nextStepDate = o.Next_Step_Date_bf__c;
            gi.directorNote = o.Director_Notes_bf__c;
            gi.lastActivityDate = o.LastActivityDate;
            gi.arr = (Decimal) o.get('ARR_Opportunity_Amount_USD_Num__c');
            gi.pricingApproval = o.Pricing_Approval_Status__c;
            gi.forecastWeekLocked = locked;
            gi.contacts = byOpp.containsKey(o.Id) ? byOpp.get(o.Id) : new List<PipelineReviewGradeService.ContactCandidate>();
            gi.titlePatterns = patterns;
            String hist = history.containsKey(o.Id) ? history.get(o.Id).get('next') : null;
            gi.history = PipelineReviewGradeService.parseHistory(hist, today);
            PipelineReviewGradeService.GradeResult gr = PipelineReviewGradeService.grade(gi, today, weights, maxArr);
            results.put(o.Id, gr);
            PipelineReviewGradeService.BucketRow br = new PipelineReviewGradeService.BucketRow();
            br.opportunityId = o.Id;
            br.priority = gr.actionPriority;
            br.naturalBucket = gr.actionBucket;
            bucketRows.add(br);
        }
        Map<Id, String> buckets = PipelineReviewGradeService.assignBuckets(bucketRows, weights.focusCapWeek);
        for (Opportunity o : scope) {
            PipelineReviewGradeService.GradeResult gr = results.get(o.Id);
            Opportunity upd = new Opportunity(Id = o.Id);
            upd.Pipeline_Grade__c = gr.pipelineGrade;
            upd.Recommended_Forecast__c = gr.recommendedForecast;
            upd.Grade_Rationale__c = gr.rationale;
            upd.Grade_Computed_On__c = System.now();
            upd.Grade_Input_Hash__c = gr.inputHash;
            upd.Parked_Cycles__c = gr.parkedCycles;
            upd.Freshest_Activity_Age__c = gr.freshestAge;
            upd.Date_Conflict__c = gr.dateConflict;
            upd.Forecast_Mismatch__c = gr.forecastMismatch;
            upd.Next_Step_State__c = gr.nextStepState;
            upd.Action_Priority__c = gr.actionPriority;
            upd.Action_Priority_Reason__c = gr.actionPriorityReason;
            upd.Action_Bucket__c = buckets.containsKey(o.Id) ? buckets.get(o.Id) : gr.actionBucket;
            upd.Recommended_Contact__c = gr.recommendedContactId;
            upd.Recommended_Contact_Reason__c = gr.recommendedContactReason;
            upd.Priority_Computed_On__c = System.now();
            updates.add(upd);
        }
        PipelineReviewWriteService.applyGradeResults(updates);
    }

    @TestVisible
    static Boolean relevantChange(Opportunity oldRow, Opportunity neu) {
        if (oldRow == null) return true;
        return oldRow.StageName != neu.StageName
            || oldRow.CloseDate != neu.CloseDate
            || oldRow.ForecastCategoryName != neu.ForecastCategoryName
            || oldRow.Director_Forecast_bf__c != neu.Director_Forecast_bf__c
            || oldRow.Next_Step_bf__c != neu.Next_Step_bf__c
            || oldRow.Next_Step_Date_bf__c != neu.Next_Step_Date_bf__c
            || oldRow.LastActivityDate != neu.LastActivityDate;
    }
}
