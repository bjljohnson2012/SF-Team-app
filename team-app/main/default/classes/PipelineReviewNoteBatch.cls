/**
 * Job B — regenerate director notes only when Grade_Input_Hash__c changed.
 * Scope 15, one Anthropic callout per execute(), DML after the callout.
 */
public with sharing class PipelineReviewNoteBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
    @TestVisible public Integer skipped = 0;
    @TestVisible public Integer regenerated = 0;
    public Id runId;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Pipeline_Review_Run__c run = new Pipeline_Review_Run__c(
            Status__c = PipelineReviewConstants.RUN_RUNNING,
            Started_At__c = System.now(),
            Async_Job_Id__c = bc == null ? null : bc.getJobId()
        );
        try {
            Database.insert(run, AccessLevel.SYSTEM_MODE);
            runId = run.Id;
        } catch (Exception e) {
            runId = null;
        }
        return Database.getQueryLocator([
            SELECT Id, Name, Account.Name, Owner.Name, StageName, CloseDate, ForecastCategoryName,
                   Director_Forecast_bf__c, Next_Step_bf__c, Next_Step_Date_bf__c, Director_Notes_bf__c,
                   ARR_Opportunity_Amount_USD_Num__c, LastActivityDate
            FROM Opportunity
            WHERE IsClosed = false
              AND RecordType.DeveloperName = :PipelineReviewConstants.SALE_RECORDTYPE
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Opportunity> scope) {
        if (isCancelled()) return;
        List<Opportunity> changed = new List<Opportunity>();
        for (Opportunity o : scope) {
            String current = currentHash(o);
            String stored;
            try { stored = (String) o.get('Grade_Input_Hash__c'); } catch (Exception e) { stored = null; }
            if (stored != null && current == stored) {
                skipped++;
            } else {
                changed.add(o);
            }
        }
        if (changed.isEmpty()) return;
        // Query + prompt + callout, then DML. No DML before the callout.
        List<PipelineReviewAIService.GenerateResult> results =
            PipelineReviewAIService.generateNotes(changed, Date.today(), false);
        List<Pipeline_Review_Run_Item__c> items = new List<Pipeline_Review_Run_Item__c>();
        for (PipelineReviewAIService.GenerateResult g : results) {
            Pipeline_Review_Run_Item__c item = new Pipeline_Review_Run_Item__c(
                Pipeline_Review_Run__c = runId,
                Opportunity__c = g.opportunityId,
                Status__c = g.ok ? PipelineReviewConstants.ITEM_SUCCEEDED : PipelineReviewConstants.ITEM_FAILED,
                Generated_Note__c = g.note,
                Generated_Forecast__c = g.forecast,
                Error__c = g.error
            );
            items.add(item);
            if (g.ok) regenerated++;
        }
        if (!items.isEmpty()) Database.insert(items, false, AccessLevel.SYSTEM_MODE);
    }

    public void finish(Database.BatchableContext bc) {
        if (runId == null) return;
        Pipeline_Review_Run__c run = new Pipeline_Review_Run__c(
            Id = runId,
            Status__c = PipelineReviewConstants.RUN_COMPLETED,
            Finished_At__c = System.now(),
            Skipped__c = skipped,
            Completed__c = regenerated
        );
        Database.update(run, AccessLevel.SYSTEM_MODE);
    }

    private Boolean isCancelled() {
        if (runId == null) return false;
        try {
            Pipeline_Review_Run__c run = [
                SELECT Status__c FROM Pipeline_Review_Run__c WHERE Id = :runId LIMIT 1
            ];
            return run.Status__c == PipelineReviewConstants.RUN_CANCELLED;
        } catch (Exception e) {
            return false;
        }
    }

    private static String currentHash(Opportunity o) {
        PipelineReviewGradeService.GradeInput gi = new PipelineReviewGradeService.GradeInput();
        gi.stageName = o.StageName;
        gi.closeDate = o.CloseDate;
        gi.forecastCategoryName = o.ForecastCategoryName;
        gi.nextStep = o.Next_Step_bf__c;
        gi.nextStepDate = o.Next_Step_Date_bf__c;
        gi.lastActivityDate = o.LastActivityDate;
        gi.arr = (Decimal) o.get('ARR_Opportunity_Amount_USD_Num__c');
        return PipelineReviewGradeService.inputHash(gi, new List<PipelineReviewGradeService.HistoryEntry>());
    }
}
