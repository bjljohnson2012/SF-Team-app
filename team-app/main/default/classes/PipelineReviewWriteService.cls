/**
 * Sole DML path for Pipeline Review. Controllers and LWCs do not write.
 * Partial-success updates; every field change is audited to Forecast_Edit_Log__c.
 */
public with sharing class PipelineReviewWriteService {
    public class WriteResult {
        public Boolean ok;
        public String error;
        public Id recordId;
    }

    public static void assertCanWrite(Boolean bulkGenerate) {
        String level = ForecastAccessService.getForecastAccessLevel();
        if (bulkGenerate == true
            && level != PipelineReviewConstants.ACCESS_MANAGER
            && level != PipelineReviewConstants.ACCESS_VP) {
            throw new AuraHandledException('Bulk generation requires manager access.');
        }
        if (String.isBlank(level)) {
            throw new AuraHandledException('Forecast access is required.');
        }
    }

    public static Boolean weekLocked() {
        return PipelineReviewSelector.isCurrentWeekLocked();
    }

    public static List<WriteResult> applyGradeResults(List<Opportunity> records) {
        List<WriteResult> out = new List<WriteResult>();
        if (records == null || records.isEmpty()) return out;
        Database.SaveResult[] saves = Database.update(records, false);
        for (Integer i = 0; i < saves.size(); i++) {
            WriteResult wr = new WriteResult();
            wr.ok = saves[i].isSuccess();
            wr.recordId = records[i].Id;
            if (!saves[i].isSuccess()) {
                wr.error = saves[i].getErrors()[0].getMessage();
            }
            out.add(wr);
        }
        return out;
    }

    public static WriteResult saveDirectorNote(Id opportunityId, String note, Boolean aiGenerated) {
        WriteResult wr = new WriteResult();
        wr.recordId = opportunityId;
        if (opportunityId == null || String.isBlank(note)) {
            wr.ok = false;
            wr.error = 'Note is required.';
            return wr;
        }
        if (aiGenerated == true && !PipelineReviewGradeService.isValidNote(note)) {
            wr.ok = false;
            wr.error = 'Note failed validation and was not written.';
            return wr;
        }
        Opportunity prior = [
            SELECT Id, Director_Notes_bf__c, Director_Notes_History_bf__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];
        Opportunity upd = new Opportunity(
            Id = opportunityId,
            Director_Notes_bf__c = note,
            Director_Note_Updated_On__c = Date.today(),
            Director_Notes_History_bf__c = appendHistory(prior.Director_Notes_History_bf__c, note)
        );
        wr = updateOne(upd);
        if (wr.ok) {
            audit(opportunityId, 'Director_Notes_bf__c', prior.Director_Notes_bf__c, note,
                aiGenerated == true ? PipelineReviewConstants.SRC_AI : PipelineReviewConstants.SRC_HUMAN);
        }
        return wr;
    }

    public static WriteResult saveNextStep(Id opportunityId, String step, Date stepDate, String source) {
        WriteResult wr = new WriteResult();
        wr.recordId = opportunityId;
        if (weekLocked() && source != PipelineReviewConstants.NS_DIRECTOR) {
            wr.ok = false;
            wr.error = 'Forecast week is locked. Next-step writes are blocked.';
            return wr;
        }
        Opportunity prior = [
            SELECT Id, Next_Step_bf__c, Next_Step_Date_bf__c, Next_Step_History_bf__c, CloseDate
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];
        Opportunity upd = new Opportunity(
            Id = opportunityId,
            Next_Step_bf__c = step,
            Next_Step_Date_bf__c = stepDate,
            Next_Step_Source__c = String.isBlank(source) ? PipelineReviewConstants.NS_REP : source,
            Next_Step_History_bf__c = appendHistory(prior.Next_Step_History_bf__c, step),
            Date_Conflict__c = stepDate != null && prior.CloseDate != null && stepDate > prior.CloseDate
        );
        wr = updateOne(upd);
        if (wr.ok) {
            audit(opportunityId, 'Next_Step_bf__c', prior.Next_Step_bf__c, step, PipelineReviewConstants.SRC_HUMAN);
        }
        return wr;
    }

    public static WriteResult acceptSuggestion(Id opportunityId) {
        Opportunity o = [
            SELECT Id, Suggested_Next_Step__c, Suggested_Next_Step_Date__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];
        if (String.isBlank(o.Suggested_Next_Step__c)) {
            WriteResult wr = new WriteResult();
            wr.ok = false;
            wr.error = 'No suggestion to accept.';
            return wr;
        }
        WriteResult wr = saveNextStep(
            opportunityId, o.Suggested_Next_Step__c, o.Suggested_Next_Step_Date__c,
            PipelineReviewConstants.NS_ACCEPTED
        );
        if (wr.ok) {
            updateOne(new Opportunity(
                Id = opportunityId,
                Suggestion_Status__c = 'Accepted'
            ));
        }
        return wr;
    }

    public static WriteResult markDone(Id opportunityId, Id focusId, String nextStep, Date nextDate) {
        Opportunity prior = [
            SELECT Id, Next_Step_bf__c, Next_Step_History_bf__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];
        String completed = String.isBlank(prior.Next_Step_bf__c) ? 'Completed' : prior.Next_Step_bf__c;
        Opportunity upd = new Opportunity(
            Id = opportunityId,
            Next_Step_bf__c = nextStep,
            Next_Step_Date_bf__c = nextDate,
            Next_Step_History_bf__c = appendHistory(prior.Next_Step_History_bf__c, completed)
        );
        WriteResult wr = updateOne(upd);
        if (wr.ok && focusId != null) {
            updateOneFocus(new Pipeline_Week_Focus__c(
                Id = focusId,
                Status__c = PipelineReviewConstants.FOCUS_DONE,
                Completed_On__c = System.now()
            ));
        }
        if (wr.ok) {
            audit(opportunityId, 'Next_Step_bf__c', prior.Next_Step_bf__c, nextStep, PipelineReviewConstants.SRC_HUMAN);
        }
        return wr;
    }

    public static WriteResult reschedule(Id opportunityId, Id focusId, Date nextDate) {
        Opportunity prior = [
            SELECT Id, Next_Step_Date_bf__c, Parked_Cycles__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];
        Opportunity upd = new Opportunity(Id = opportunityId, Next_Step_Date_bf__c = nextDate);
        WriteResult wr = updateOne(upd);
        if (wr.ok && focusId != null) {
            updateOneFocus(new Pipeline_Week_Focus__c(
                Id = focusId,
                Status__c = PipelineReviewConstants.FOCUS_RESCHEDULED
            ));
        }
        if (wr.ok) {
            audit(opportunityId, 'Next_Step_Date_bf__c', String.valueOf(prior.Next_Step_Date_bf__c),
                String.valueOf(nextDate), PipelineReviewConstants.SRC_HUMAN);
        }
        return wr;
    }

    public static WriteResult upsertTag(Id opportunityId, String tag) {
        WriteResult wr = new WriteResult();
        wr.recordId = opportunityId;
        if (opportunityId == null || String.isBlank(tag)) {
            wr.ok = false;
            wr.error = 'Tag and opportunity are required.';
            return wr;
        }
        String ext = String.valueOf(opportunityId) + '-' + String.valueOf(UserInfo.getUserId());
        Pipeline_Review_Tag__c row = new Pipeline_Review_Tag__c(
            Opportunity__c = opportunityId,
            Tag__c = tag,
            Tagged_By__c = UserInfo.getUserId(),
            External_Id__c = ext
        );
        Database.UpsertResult ur = Database.upsert(row, Pipeline_Review_Tag__c.External_Id__c, false);
        wr.ok = ur.isSuccess();
        if (!ur.isSuccess()) wr.error = ur.getErrors()[0].getMessage();
        return wr;
    }

    public static WriteResult snooze(Id opportunityId, Date untilDate) {
        WriteResult wr = new WriteResult();
        String ext = String.valueOf(opportunityId) + '-' + String.valueOf(UserInfo.getUserId());
        Pipeline_Action_Snooze__c row = new Pipeline_Action_Snooze__c(
            Opportunity__c = opportunityId,
            User__c = UserInfo.getUserId(),
            Snooze_Until__c = untilDate,
            External_Id__c = ext
        );
        Database.UpsertResult ur = Database.upsert(row, Pipeline_Action_Snooze__c.External_Id__c, false);
        wr.ok = ur.isSuccess();
        wr.recordId = opportunityId;
        if (!ur.isSuccess()) wr.error = ur.getErrors()[0].getMessage();
        return wr;
    }

    public static void writeSuggestions(List<Opportunity> records) {
        if (records == null || records.isEmpty()) return;
        Database.update(records, false);
    }

    public static void audit(Id opportunityId, String fieldName, String oldVal, String newVal, String source) {
        Forecast_Edit_Log__c log = new Forecast_Edit_Log__c(
            Opportunity__c = opportunityId,
            Field_Changed__c = fieldName,
            Old_Value__c = oldVal == null ? null : oldVal.left(255),
            New_Value__c = newVal == null ? null : newVal.left(255)
        );
        try {
            log.put('Source__c', source);
        } catch (Exception e) {
            // Source__c may not be readable in this transaction yet
        }
        Database.insert(log, false);
    }

    public static String appendHistory(String existing, String text) {
        if (String.isBlank(text)) return existing;
        Date t = Date.today();
        String line = t.month() + '/' + t.day() + '/' + t.year() + ' : ' + text;
        if (String.isBlank(existing)) return line;
        return line + '<p></p><p></p>' + existing;
    }

    private static WriteResult updateOne(Opportunity rec) {
        WriteResult wr = new WriteResult();
        wr.recordId = rec.Id;
        Database.SaveResult sr = Database.update(rec, false);
        wr.ok = sr.isSuccess();
        if (!sr.isSuccess()) wr.error = sr.getErrors()[0].getMessage();
        return wr;
    }

    private static void updateOneFocus(Pipeline_Week_Focus__c rec) {
        Database.update(rec, false);
    }
}
