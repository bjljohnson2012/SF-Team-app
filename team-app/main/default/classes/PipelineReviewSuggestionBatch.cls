/**
 * Job C — next-step suggestions only. Never writes Next_Step_bf__c.
 * Hygiene digest flagged counts stay unchanged (acceptance criterion 12).
 */
public with sharing class PipelineReviewSuggestionBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, Owner.Name, StageName, CloseDate, Next_Step_bf__c, Next_Step_Date_bf__c,
                   ARR_Opportunity_Amount_USD_Num__c, Pricing_Approval_Status__c
            FROM Opportunity
            WHERE IsClosed = false
              AND RecordType.DeveloperName = :PipelineReviewConstants.SALE_RECORDTYPE
              AND (Next_Step_bf__c = null OR Next_Step_Date_bf__c < TODAY)
              AND (Pricing_Approval_Status__c = null OR Pricing_Approval_Status__c != 'Pending')
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Opportunity> scope) {
        if (PipelineReviewSelector.isCurrentWeekLocked()) return;
        Date today = Date.today();
        List<Opportunity> writes = new List<Opportunity>();
        for (Opportunity o : scope) {
            PipelineReviewAIService.GenerateResult g = PipelineReviewAIService.generateNextStep(o, today);
            if (g != null && g.ok) {
                writes.add(new Opportunity(
                    Id = o.Id,
                    Suggested_Next_Step__c = g.nextStep,
                    Suggested_Next_Step_Date__c = g.nextStepDate,
                    Suggestion_Generated_On__c = System.now(),
                    Suggestion_Status__c = 'Pending'
                ));
            }
        }
        PipelineReviewWriteService.writeSuggestions(writes);
    }

    public void finish(Database.BatchableContext bc) {
    }
}
