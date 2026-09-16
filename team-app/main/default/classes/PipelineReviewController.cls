/**
 * Thin AuraEnabled façade for Pipeline Review. No business logic, no DML.
 */
public with sharing class PipelineReviewController {
    public class PageDTO {
        @AuraEnabled public List<RowDTO> rows;
        @AuraEnabled public Integer expected;
        @AuraEnabled public Integer loaded;
        @AuraEnabled public Boolean truncated;
        @AuraEnabled public Decimal totalArr;
        @AuraEnabled public Datetime lastUpdated;
        @AuraEnabled public String accessLevel;
        @AuraEnabled public Boolean weekLocked;
        @AuraEnabled public List<UserDTO> aes;
        @AuraEnabled public List<PipelineReviewSavedViewService.ViewDTO> views;
        @AuraEnabled public List<RunDTO> runs;
    }

    public class RowDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String account;
        @AuraEnabled public String ae;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String stage;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public Decimal arr;
        @AuraEnabled public String aeForecast;
        @AuraEnabled public String directorForecast;
        @AuraEnabled public String rollupForecast;
        @AuraEnabled public String recommendedForecast;
        @AuraEnabled public String grade;
        @AuraEnabled public String rationale;
        @AuraEnabled public String tag;
        @AuraEnabled public Boolean mismatch;
        @AuraEnabled public Boolean dateConflict;
        @AuraEnabled public String nextStep;
        @AuraEnabled public Date nextStepDate;
        @AuraEnabled public String nextStepState;
        @AuraEnabled public String note;
        @AuraEnabled public String suggestedNextStep;
        @AuraEnabled public Date suggestedNextStepDate;
        @AuraEnabled public String suggestionStatus;
        @AuraEnabled public String nextStepSource;
        @AuraEnabled public Decimal priority;
        @AuraEnabled public String priorityReason;
        @AuraEnabled public String bucket;
        @AuraEnabled public String contactName;
        @AuraEnabled public String contactTitle;
        @AuraEnabled public String contactEmail;
        @AuraEnabled public String contactReason;
        @AuraEnabled public Integer parkedCycles;
        @AuraEnabled public Integer freshestAge;
        @AuraEnabled public String url;
    }

    public class UserDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
    }

    public class RunDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal total;
        @AuraEnabled public Decimal completed;
        @AuraEnabled public Decimal failed;
        @AuraEnabled public Decimal skipped;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public Datetime finishedAt;
    }

    public class WeekPageDTO {
        @AuraEnabled public String mode;
        @AuraEnabled public Date weekStart;
        @AuraEnabled public Integer focusCap;
        @AuraEnabled public Integer focusCount;
        @AuraEnabled public Integer dueCount;
        @AuraEnabled public Integer overdueCount;
        @AuraEnabled public Integer unworkableCount;
        @AuraEnabled public Integer cleared;
        @AuraEnabled public Integer carried;
        @AuraEnabled public Integer dropped;
        @AuraEnabled public Datetime lastUpdated;
        @AuraEnabled public String accessLevel;
        @AuraEnabled public List<RowDTO> focus;
        @AuraEnabled public List<RowDTO> dueThisWeek;
        @AuraEnabled public List<RowDTO> decideOrKill;
        @AuraEnabled public List<RowDTO> fixFirst;
        @AuraEnabled public List<AeChipDTO> aeChips;
    }

    public class AeChipDTO {
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String name;
        @AuraEnabled public Integer focusCount;
        @AuraEnabled public Integer cleared;
        @AuraEnabled public Integer overdue;
    }

    @AuraEnabled
    public static PageDTO loadPage(String filterJson) {
        PipelineReviewSelector.Filter f = parseFilter(filterJson);
        PipelineReviewSelector.LoadResult load = PipelineReviewSelector.loadBook(f);
        Map<Id, String> tags = new Map<Id, String>();
        List<Id> ids = new List<Id>();
        for (Opportunity o : load.records) ids.add(o.Id);
        try {
            tags = PipelineReviewSelector.loadTags(ids, UserInfo.getUserId());
        } catch (Exception e) {
            tags = new Map<Id, String>();
        }
        PageDTO page = new PageDTO();
        page.rows = new List<RowDTO>();
        page.expected = load.expected;
        page.loaded = load.loaded;
        page.truncated = load.loaded != load.expected;
        page.totalArr = load.totalArr;
        page.lastUpdated = load.lastUpdated;
        page.accessLevel = ForecastAccessService.getForecastAccessLevel();
        page.weekLocked = PipelineReviewSelector.isCurrentWeekLocked();
        page.aes = new List<UserDTO>();
        for (User u : PipelineReviewSelector.teamUsers(PipelineReviewSelector.teamOwnerIds(f.directorId))) {
            UserDTO d = new UserDTO();
            d.id = u.Id;
            d.name = u.Name;
            page.aes.add(d);
        }
        String search = f == null ? null : f.search;
        for (Opportunity o : load.records) {
            RowDTO row = toRow(o, tags.get(o.Id));
            if (String.isNotBlank(search) && !rowMatchesSearch(row, search)) continue;
            page.rows.add(row);
        }
        page.expected = page.rows.size();
        page.loaded = page.rows.size();
        try {
            page.views = PipelineReviewSavedViewService.listViews();
        } catch (Exception e) {
            page.views = new List<PipelineReviewSavedViewService.ViewDTO>();
        }
        page.runs = listRuns();
        return page;
    }

    @AuraEnabled
    public static WeekPageDTO loadThisWeek(String mode, Id directorId) {
        String level = ForecastAccessService.getForecastAccessLevel();
        Date today = Date.today();
        String resolved = resolveMode(mode, today);
        PipelineReviewSelector.Filter f = new PipelineReviewSelector.Filter();
        f.directorId = directorId;
        if (level == PipelineReviewConstants.ACCESS_REP) {
            f.ownerIds = new List<Id>{ UserInfo.getUserId() };
        }
        PipelineReviewSelector.LoadResult load = PipelineReviewSelector.loadBook(f);
        PipelineReviewGradeService.WeightConfig w = PipelineReviewSelector.weightConfig();
        Integer cap = resolved == PipelineReviewConstants.MODE_TODAY ? w.focusCapToday : w.focusCapWeek;
        Date monday = weekStart(today);
        Set<Id> snoozed = new Set<Id>();
        if (resolved == PipelineReviewConstants.MODE_TODAY) {
            try {
                for (Pipeline_Action_Snooze__c s : [
                    SELECT Opportunity__c
                    FROM Pipeline_Action_Snooze__c
                    WHERE User__c = :UserInfo.getUserId() AND Snooze_Until__c >= :today
                ]) snoozed.add(s.Opportunity__c);
            } catch (Exception e) { /* degrade */ }
        }
        Map<Id, Pipeline_Week_Focus__c> locked = new Map<Id, Pipeline_Week_Focus__c>();
        if (resolved == PipelineReviewConstants.MODE_WEEK) {
            try {
                for (Pipeline_Week_Focus__c row : [
                    SELECT Id, Opportunity__c, Rank__c, Priority_At_Lock__c, Reason_At_Lock__c,
                           Status__c, Carried_From_Prior_Week__c, User__c
                    FROM Pipeline_Week_Focus__c
                    WHERE Week_Start__c = :monday
                      AND Status__c != :PipelineReviewConstants.FOCUS_DROPPED
                    ORDER BY Rank__c
                ]) locked.put(row.Opportunity__c, row);
            } catch (Exception e) { /* degrade */ }
        }
        WeekPageDTO page = new WeekPageDTO();
        page.mode = resolved;
        page.weekStart = monday;
        page.focusCap = cap;
        page.focus = new List<RowDTO>();
        page.dueThisWeek = new List<RowDTO>();
        page.decideOrKill = new List<RowDTO>();
        page.fixFirst = new List<RowDTO>();
        page.aeChips = new List<AeChipDTO>();
        page.accessLevel = level;
        page.lastUpdated = load.lastUpdated;
        Map<Id, AeChipDTO> chips = new Map<Id, AeChipDTO>();
        Integer due = 0, overdue = 0, unworkable = 0, cleared = 0, carried = 0, dropped = 0;
        List<RowDTO> liveRanked = new List<RowDTO>();
        for (Opportunity o : load.records) {
            RowDTO row = toRow(o, null);
            if (o.Next_Step_Date_bf__c == null || String.isBlank(o.Next_Step_bf__c)) unworkable++;
            if (o.Next_Step_Date_bf__c != null && o.Next_Step_Date_bf__c < today) overdue++;
            if (o.Next_Step_Date_bf__c != null && o.Next_Step_Date_bf__c >= today
                && o.Next_Step_Date_bf__c <= today.addDays(7)) due++;
            String bucket = (String) safeGet(o, 'Action_Bucket__c');
            if (bucket == PipelineReviewConstants.BUCKET_FIX) page.fixFirst.add(row);
            else if (bucket == PipelineReviewConstants.BUCKET_KILL) page.decideOrKill.add(row);
            else if (bucket == PipelineReviewConstants.BUCKET_DUE) page.dueThisWeek.add(row);
            if (!snoozed.contains(o.Id)) liveRanked.add(row);
            if (!chips.containsKey(o.OwnerId)) {
                AeChipDTO c = new AeChipDTO();
                c.ownerId = o.OwnerId;
                c.name = o.Owner == null ? '' : o.Owner.Name;
                c.focusCount = 0; c.cleared = 0; c.overdue = 0;
                chips.put(o.OwnerId, c);
            }
            if (o.Next_Step_Date_bf__c != null && o.Next_Step_Date_bf__c < today) {
                chips.get(o.OwnerId).overdue++;
            }
        }
        if (resolved == PipelineReviewConstants.MODE_WEEK && !locked.isEmpty()) {
            for (Opportunity o : load.records) {
                if (!locked.containsKey(o.Id)) continue;
                Pipeline_Week_Focus__c snap = locked.get(o.Id);
                RowDTO row = toRow(o, null);
                row.priority = snap.Priority_At_Lock__c;
                row.priorityReason = snap.Reason_At_Lock__c;
                row.bucket = PipelineReviewConstants.BUCKET_FOCUS;
                page.focus.add(row);
                if (snap.Status__c == PipelineReviewConstants.FOCUS_DONE) cleared++;
                if (snap.Carried_From_Prior_Week__c == true) carried++;
                if (chips.containsKey(o.OwnerId)) {
                    chips.get(o.OwnerId).focusCount++;
                    if (snap.Status__c == PipelineReviewConstants.FOCUS_DONE) chips.get(o.OwnerId).cleared++;
                }
            }
        } else {
            liveRanked.sort(new PriorityDesc());
            Integer n = 0;
            for (RowDTO row : liveRanked) {
                if (n >= cap) break;
                if (row.bucket == PipelineReviewConstants.BUCKET_FIX) continue;
                page.focus.add(row);
                n++;
            }
        }
        try {
            dropped = [
                SELECT COUNT() FROM Pipeline_Week_Focus__c
                WHERE Week_Start__c = :monday AND Status__c = :PipelineReviewConstants.FOCUS_DROPPED
            ];
        } catch (Exception e) { dropped = 0; }
        page.focusCount = page.focus.size();
        page.dueCount = due;
        page.overdueCount = overdue;
        page.unworkableCount = unworkable;
        page.cleared = cleared;
        page.carried = carried;
        page.dropped = dropped;
        page.aeChips = chips.values();
        return page;
    }

    @AuraEnabled
    public static PipelineReviewWriteService.WriteResult saveNote(Id opportunityId, String note, Boolean aiGenerated) {
        PipelineReviewWriteService.assertCanWrite(false);
        return PipelineReviewWriteService.saveDirectorNote(opportunityId, note, aiGenerated);
    }

    @AuraEnabled
    public static PipelineReviewWriteService.WriteResult saveNextStep(Id opportunityId, String step, Date stepDate) {
        PipelineReviewWriteService.assertCanWrite(false);
        return PipelineReviewWriteService.saveNextStep(opportunityId, step, stepDate, PipelineReviewConstants.NS_REP);
    }

    @AuraEnabled
    public static PipelineReviewWriteService.WriteResult acceptSuggestion(Id opportunityId) {
        PipelineReviewWriteService.assertCanWrite(false);
        return PipelineReviewWriteService.acceptSuggestion(opportunityId);
    }

    @AuraEnabled
    public static PipelineReviewWriteService.WriteResult upsertTag(Id opportunityId, String tag) {
        PipelineReviewWriteService.assertCanWrite(false);
        return PipelineReviewWriteService.upsertTag(opportunityId, tag);
    }

    @AuraEnabled
    public static PipelineReviewWriteService.WriteResult markDone(Id opportunityId, Id focusId, String nextStep, Date nextDate) {
        PipelineReviewWriteService.assertCanWrite(false);
        return PipelineReviewWriteService.markDone(opportunityId, focusId, nextStep, nextDate);
    }

    @AuraEnabled
    public static PipelineReviewWriteService.WriteResult reschedule(Id opportunityId, Id focusId, Date nextDate) {
        PipelineReviewWriteService.assertCanWrite(false);
        return PipelineReviewWriteService.reschedule(opportunityId, focusId, nextDate);
    }

    @AuraEnabled
    public static PipelineReviewWriteService.WriteResult snooze(Id opportunityId, Date untilDate) {
        PipelineReviewWriteService.assertCanWrite(false);
        return PipelineReviewWriteService.snooze(opportunityId, untilDate);
    }

    @AuraEnabled
    public static PipelineReviewAIService.GenerateResult generateNote(Id opportunityId, Boolean persist) {
        PipelineReviewWriteService.assertCanWrite(false);
        Opportunity o = [
            SELECT Id, Name, Account.Name, Owner.Name, StageName, CloseDate, ForecastCategoryName,
                   Director_Forecast_bf__c, Next_Step_bf__c, Next_Step_Date_bf__c, Director_Notes_bf__c,
                   ARR_Opportunity_Amount_USD_Num__c
            FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];
        List<PipelineReviewAIService.GenerateResult> rows =
            PipelineReviewAIService.generateNotes(new List<Opportunity>{ o }, Date.today(), false);
        PipelineReviewAIService.GenerateResult g = rows.isEmpty() ? new PipelineReviewAIService.GenerateResult() : rows[0];
        if (persist == true && g != null && g.ok) {
            PipelineReviewWriteService.saveDirectorNote(opportunityId, g.note, true);
        }
        return g;
    }

    @AuraEnabled
    public static Id enqueueGrade() {
        PipelineReviewWriteService.assertCanWrite(true);
        return Database.executeBatch(new PipelineReviewGradeBatch(), PipelineReviewConstants.DEFAULT_GRADE_BATCH);
    }

    private static List<RunDTO> listRuns() {
        List<RunDTO> out = new List<RunDTO>();
        try {
            for (Pipeline_Review_Run__c r : [
                SELECT Id, Status__c, Total__c, Completed__c, Failed__c, Skipped__c, Started_At__c, Finished_At__c
                FROM Pipeline_Review_Run__c
                ORDER BY CreatedDate DESC
                LIMIT 10
            ]) {
                RunDTO d = new RunDTO();
                d.id = r.Id;
                d.status = r.Status__c;
                d.total = r.Total__c;
                d.completed = r.Completed__c;
                d.failed = r.Failed__c;
                d.skipped = r.Skipped__c;
                d.startedAt = r.Started_At__c;
                d.finishedAt = r.Finished_At__c;
                out.add(d);
            }
        } catch (Exception e) {
            return out;
        }
        return out;
    }

    private static PipelineReviewSelector.Filter parseFilter(String filterJson) {
        PipelineReviewSelector.Filter f = new PipelineReviewSelector.Filter();
        if (String.isBlank(filterJson)) return f;
        try {
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(filterJson);
            if (m.containsKey('directorId') && m.get('directorId') != null) f.directorId = (Id) String.valueOf(m.get('directorId'));
            if (m.containsKey('teamMode')) f.teamMode = String.valueOf(m.get('teamMode'));
            if (m.containsKey('productType')) f.productType = String.valueOf(m.get('productType'));
            if (m.containsKey('search')) f.search = String.valueOf(m.get('search'));
            if (m.containsKey('mismatchOnly')) f.mismatchOnly = (Boolean) m.get('mismatchOnly');
            f.stages = toStrList(m.get('stages'));
            f.aeForecasts = toStrList(m.get('aeForecasts'));
            f.directorForecasts = toStrList(m.get('directorForecasts'));
            f.rollupForecasts = toStrList(m.get('rollupForecasts'));
            f.recommendedForecasts = toStrList(m.get('recommendedForecasts'));
            f.tags = toStrList(m.get('tags'));
            f.nextStepStates = toStrList(m.get('nextStepStates'));
            f.solutions = toStrList(m.get('solutions'));
            f.ownerIds = toIdList(m.get('ownerIds'));
            if (m.containsKey('arrMin') && m.get('arrMin') != null) f.arrMin = Decimal.valueOf(String.valueOf(m.get('arrMin')));
            if (m.containsKey('arrMax') && m.get('arrMax') != null) f.arrMax = Decimal.valueOf(String.valueOf(m.get('arrMax')));
            if (m.containsKey('closeFrom') && m.get('closeFrom') != null) f.closeFrom = Date.valueOf(String.valueOf(m.get('closeFrom')));
            if (m.containsKey('closeTo') && m.get('closeTo') != null) f.closeTo = Date.valueOf(String.valueOf(m.get('closeTo')));
        } catch (Exception e) {
            return new PipelineReviewSelector.Filter();
        }
        return f;
    }

    private static List<String> toStrList(Object raw) {
        List<String> out = new List<String>();
        if (!(raw instanceof List<Object>)) return out;
        for (Object o : (List<Object>) raw) if (o != null) out.add(String.valueOf(o));
        return out;
    }

    private static List<Id> toIdList(Object raw) {
        List<Id> out = new List<Id>();
        if (!(raw instanceof List<Object>)) return out;
        for (Object o : (List<Object>) raw) {
            if (o != null) out.add((Id) String.valueOf(o));
        }
        return out;
    }

    private static RowDTO toRow(Opportunity o, String tag) {
        RowDTO r = new RowDTO();
        r.id = o.Id;
        r.name = o.Name;
        r.account = o.Account == null ? o.Name : o.Account.Name;
        r.ae = o.Owner == null ? '' : o.Owner.Name;
        r.ownerId = o.OwnerId;
        r.stage = o.StageName;
        r.closeDate = o.CloseDate;
        r.arr = (Decimal) o.get('ARR_Opportunity_Amount_USD_Num__c');
        r.aeForecast = o.ForecastCategoryName;
        r.directorForecast = o.Director_Forecast_bf__c;
        r.rollupForecast = o.Roll_Up_Forecast_bf__c;
        r.recommendedForecast = (String) safeGet(o, 'Recommended_Forecast__c');
        r.grade = (String) safeGet(o, 'Pipeline_Grade__c');
        r.rationale = (String) safeGet(o, 'Grade_Rationale__c');
        r.tag = tag;
        r.mismatch = safeGet(o, 'Forecast_Mismatch__c') == true;
        r.dateConflict = safeGet(o, 'Date_Conflict__c') == true;
        r.nextStep = o.Next_Step_bf__c;
        r.nextStepDate = o.Next_Step_Date_bf__c;
        r.nextStepState = (String) safeGet(o, 'Next_Step_State__c');
        r.note = o.Director_Notes_bf__c;
        r.suggestedNextStep = (String) safeGet(o, 'Suggested_Next_Step__c');
        r.suggestedNextStepDate = (Date) safeGet(o, 'Suggested_Next_Step_Date__c');
        r.suggestionStatus = (String) safeGet(o, 'Suggestion_Status__c');
        r.nextStepSource = (String) safeGet(o, 'Next_Step_Source__c');
        r.priority = (Decimal) safeGet(o, 'Action_Priority__c');
        r.priorityReason = (String) safeGet(o, 'Action_Priority_Reason__c');
        r.bucket = (String) safeGet(o, 'Action_Bucket__c');
        try {
            r.contactName = o.Recommended_Contact__r == null ? null : o.Recommended_Contact__r.Name;
            r.contactTitle = o.Recommended_Contact__r == null ? null : o.Recommended_Contact__r.Title;
            r.contactEmail = o.Recommended_Contact__r == null ? null : o.Recommended_Contact__r.Email;
        } catch (Exception e) {
            r.contactName = null;
        }
        r.contactReason = (String) safeGet(o, 'Recommended_Contact_Reason__c');
        Decimal parked = (Decimal) safeGet(o, 'Parked_Cycles__c');
        r.parkedCycles = parked == null ? 0 : Integer.valueOf(parked);
        Decimal age = (Decimal) safeGet(o, 'Freshest_Activity_Age__c');
        r.freshestAge = age == null ? null : Integer.valueOf(age);
        r.url = '/' + o.Id;
        return r;
    }

    private static Object safeGet(SObject rec, String fieldName) {
        try {
            return rec.get(fieldName);
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean rowMatchesSearch(RowDTO row, String search) {
        String q = search.toLowerCase();
        return (row.account != null && row.account.toLowerCase().contains(q))
            || (row.name != null && row.name.toLowerCase().contains(q))
            || (row.note != null && row.note.toLowerCase().contains(q));
    }

    public static String resolveMode(String mode, Date today) {
        if (mode == PipelineReviewConstants.MODE_WEEK || mode == PipelineReviewConstants.MODE_TODAY) return mode;
        DateTime dt = DateTime.newInstance(today, Time.newInstance(12, 0, 0, 0));
        String dow = dt.format('u'); // 1=Monday
        return (dow == '1' || dow == '2')
            ? PipelineReviewConstants.MODE_WEEK
            : PipelineReviewConstants.MODE_TODAY;
    }

    public static Date weekStart(Date today) {
        DateTime dt = DateTime.newInstance(today, Time.newInstance(12, 0, 0, 0));
        Integer dow = Integer.valueOf(dt.format('u'));
        return today.addDays(1 - dow);
    }

    private class PriorityDesc implements Comparator<RowDTO> {
        public Integer compare(RowDTO a, RowDTO b) {
            Decimal pa = a == null || a.priority == null ? -1 : a.priority;
            Decimal pb = b == null || b.priority == null ? -1 : b.priority;
            if (pa == pb) return 0;
            return pa > pb ? -1 : 1;
        }
    }
}
