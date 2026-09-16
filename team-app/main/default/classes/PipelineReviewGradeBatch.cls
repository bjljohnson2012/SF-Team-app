/**
 * Job A — grade, contact, and This Week priority. No callouts. Scope 200.
 */
public with sharing class PipelineReviewGradeBatch implements Database.Batchable<SObject>, Database.Stateful {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Id rt = PipelineReviewSelector.eunaSaleRecordTypeId();
        if (rt == null) {
            return Database.getQueryLocator([
                SELECT Id FROM Opportunity WHERE IsClosed = false LIMIT 1
            ]);
        }
        return Database.getQueryLocator([
            SELECT Id, StageName, CloseDate, ForecastCategoryName, Director_Forecast_bf__c,
                   Roll_Up_Forecast_bf__c, Next_Step_bf__c, Next_Step_Date_bf__c, Director_Notes_bf__c,
                   LastActivityDate, ARR_Opportunity_Amount_USD_Num__c, Pricing_Approval_Status__c,
                   OwnerId
            FROM Opportunity
            WHERE IsClosed = false AND RecordType.DeveloperName = :PipelineReviewConstants.SALE_RECORDTYPE
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Opportunity> scope) {
        PipelineReviewOpportunityHandler.recompute(scope, Date.today());
    }

    public void finish(Database.BatchableContext bc) {
    }
}
