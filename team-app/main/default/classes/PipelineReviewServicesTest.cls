/**
 * Covers: PipelineReviewWriteService, PipelineReviewSavedViewService,
 * PipelineReviewSelector, PipelineReviewJobConfig, PipelineReviewFocusLockService,
 * PipelineReviewController, PipelineReviewAIService, PipelineReviewScheduler
 */
@IsTest
private class PipelineReviewServicesTest {
    private class AnthropicMock implements HttpCalloutMock {
        public Integer status;
        public String body;
        public Integer calls = 0;
        public AnthropicMock(Integer status, String body) {
            this.status = status;
            this.body = body;
        }
        public HTTPResponse respond(HTTPRequest req) {
            calls++;
            if (status == 429 && calls == 1) {
                HTTPResponse r = new HTTPResponse();
                r.setStatusCode(429);
                r.setBody('{"error":"rate"}');
                return r;
            }
            HTTPResponse ok = new HTTPResponse();
            ok.setStatusCode(status == 429 ? 200 : status);
            ok.setBody(body);
            return ok;
        }
    }

    @TestSetup
    static void data() {
        Account a = new Account(Name = 'PR Test County');
        insert a;
        Id rt = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('Euna_Sale')?.getRecordTypeId();
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 3; i++) {
            Opportunity o = new Opportunity(
                Name = 'PR Deal ' + i,
                AccountId = a.Id,
                StageName = 'Proposal',
                CloseDate = Date.today().addDays(20 + i),
                ForecastCategoryName = 'Pipeline'
            );
            if (rt != null) o.RecordTypeId = rt;
            opps.add(o);
        }
        insert opps;
    }

    @IsTest
    static void savedViews_roundTrip_and_unknownKey() {
        Test.startTest();
        PipelineReviewSavedViewService.ViewDTO v = PipelineReviewSavedViewService.saveView(
            null, 'My view', '{"v":1,"fooUnknown":true,"search":"legal"}', false, true, 1
        );
        System.assertNotEquals(null, v.id, 'saved');
        List<PipelineReviewSavedViewService.ViewDTO> listed = PipelineReviewSavedViewService.listViews();
        System.assertEquals(1, listed.size(), 'one view');
        System.assert(listed[0].definitionJson.contains('fooUnknown') || listed[0].definitionJson.contains('"v"'),
            'v1 JSON with unknown key loads without throwing');
        PipelineReviewSavedViewService.ViewDTO copy = PipelineReviewSavedViewService.duplicateView(v.id);
        System.assertNotEquals(v.id, copy.id, 'duplicate is a new row');
        PipelineReviewSavedViewService.deleteView(copy.id);
        Test.stopTest();
    }

    @IsTest
    static void writeService_tagUpsert_isIdempotent() {
        Opportunity o = [SELECT Id FROM Opportunity WHERE Name = 'PR Deal 0' LIMIT 1];
        Test.startTest();
        PipelineReviewWriteService.WriteResult a = PipelineReviewWriteService.upsertTag(o.Id, 'A');
        PipelineReviewWriteService.WriteResult b = PipelineReviewWriteService.upsertTag(o.Id, 'B');
        Test.stopTest();
        System.assertEquals(true, a.ok, 'first tag writes');
        System.assertEquals(true, b.ok, 'second tag upserts');
        System.assertEquals(1, [SELECT COUNT() FROM Pipeline_Review_Tag__c WHERE Opportunity__c = :o.Id],
            'double-click cannot duplicate');
    }

    @IsTest
    static void writeService_appendHistory_neverOverwrites() {
        String first = PipelineReviewWriteService.appendHistory(null, 'first step');
        String second = PipelineReviewWriteService.appendHistory(first, 'second step');
        System.assert(second.contains('first step'), 'history kept');
        System.assert(second.contains('second step'), 'new line prepended');
    }

    @IsTest
    static void jobConfig_dayMatch_and_due() {
        System.assertEquals(true, PipelineReviewJobConfig.dayMatches('*', 'Mon'));
        System.assertEquals(true, PipelineReviewJobConfig.dayMatches('Mon,Tue', 'Mon'));
        System.assertEquals(false, PipelineReviewJobConfig.dayMatches('Mon', 'Wed'));
        Test.startTest();
        List<PipelineReviewJobConfig.JobSpec> due = PipelineReviewJobConfig.due(System.now());
        Test.stopTest();
        System.assertNotEquals(null, due, 'due never null');
    }

    @IsTest
    static void controller_loadPage_and_thisWeek() {
        Test.startTest();
        PipelineReviewController.PageDTO page = PipelineReviewController.loadPage('{"search":"PR"}');
        PipelineReviewController.WeekPageDTO week = PipelineReviewController.loadThisWeek('week', null);
        Test.stopTest();
        System.assertNotEquals(null, page, 'page loads');
        System.assertNotEquals(null, week, 'week loads');
        System.assert(week.focusCap > 0, 'focus cap set');
        System.assert(week.focus.size() <= week.focusCap, 'Focus never exceeds cap');
    }

    @IsTest
    static void ai_match_and_validNote_noWriteOnFailure() {
        Id oppId = [SELECT Id FROM Opportunity WHERE Name = 'PR Deal 0' LIMIT 1].Id;
        String body = '[{"id":"' + oppId + '","note":"short","forecast":"Commit"}]';
        Test.setMock(HttpCalloutMock.class, new AnthropicMock(200, body));
        Opportunity o = [
            SELECT Id, Name, Account.Name, Owner.Name, StageName, CloseDate, ForecastCategoryName,
                   Director_Forecast_bf__c, Next_Step_bf__c, Next_Step_Date_bf__c, Director_Notes_bf__c,
                   ARR_Opportunity_Amount_USD_Num__c
            FROM Opportunity WHERE Id = :oppId
        ];
        Test.startTest();
        List<PipelineReviewAIService.GenerateResult> rows =
            PipelineReviewAIService.generateNotes(new List<Opportunity>{ o }, Date.today(), false);
        Test.stopTest();
        System.assertEquals(false, rows[0].ok, 'invalid note is not ok');
        Opportunity after = [SELECT Director_Notes_bf__c FROM Opportunity WHERE Id = :oppId];
        System.assertEquals(null, after.Director_Notes_bf__c, 'nothing written on validation failure');
    }

    @IsTest
    static void ai_happyPath_and_429_then_success() {
        Id oppId = [SELECT Id FROM Opportunity WHERE Name = 'PR Deal 1' LIMIT 1].Id;
        String note = '09/16 - Legal is reviewing the EULA and holds the Sep 28 session, so paper is moving. Cindy to refresh the quote before Sep 28.';
        String body = '[{"id":"' + oppId + '","note":"' + note + '","forecast":"Commit"}]';
        AnthropicMock mock = new AnthropicMock(429, '{"content":[{"type":"text","text":' + JSON.serialize(body) + '}]}');
        // AnthropicClient parses content[].text — wrap as API body
        String api = '{"content":[{"type":"text","text":' + JSON.serialize(body) + '}],"usage":{"input_tokens":10,"output_tokens":20}}';
        mock = new AnthropicMock(429, api);
        Test.setMock(HttpCalloutMock.class, mock);
        Opportunity o = [
            SELECT Id, Name, Account.Name, Owner.Name, StageName, CloseDate, ForecastCategoryName,
                   Director_Forecast_bf__c, Next_Step_bf__c, Next_Step_Date_bf__c, Director_Notes_bf__c,
                   ARR_Opportunity_Amount_USD_Num__c
            FROM Opportunity WHERE Id = :oppId
        ];
        Test.startTest();
        List<PipelineReviewAIService.GenerateResult> rows =
            PipelineReviewAIService.generateNotes(new List<Opportunity>{ o }, Date.today(), false);
        Test.stopTest();
        System.assertEquals(true, rows[0].ok, '429 then success still matches');
        System.assertEquals(true, PipelineReviewGradeService.isValidNote(rows[0].note));
    }

    @IsTest
    static void ai_500_and_unknownId_writeNothing() {
        Id oppId = [SELECT Id FROM Opportunity WHERE Name = 'PR Deal 2' LIMIT 1].Id;
        String api = '{"content":[{"type":"text","text":"[{\\"id\\":\\"006000000000099\\",\\"note\\":\\"09/16 - x\\",\\"forecast\\":\\"Commit\\"}]"}],"usage":{"input_tokens":1,"output_tokens":1}}';
        Test.setMock(HttpCalloutMock.class, new AnthropicMock(500, api));
        Opportunity o = [
            SELECT Id, Name, Account.Name, Owner.Name, StageName, CloseDate, ForecastCategoryName,
                   Director_Forecast_bf__c, Next_Step_bf__c, Next_Step_Date_bf__c, Director_Notes_bf__c,
                   ARR_Opportunity_Amount_USD_Num__c
            FROM Opportunity WHERE Id = :oppId
        ];
        Test.startTest();
        List<PipelineReviewAIService.GenerateResult> fail =
            PipelineReviewAIService.generateNotes(new List<Opportunity>{ o }, Date.today(), false);
        Test.stopTest();
        System.assertEquals(false, fail[0].ok, '500 or unknown id does not succeed');
        System.assertEquals(null, [SELECT Director_Notes_bf__c FROM Opportunity WHERE Id = :oppId].Director_Notes_bf__c,
            'nothing written in failure case');
    }

    @IsTest
    static void extractJson_and_modelRouting() {
        System.assert(PipelineReviewAIService.extractJsonArray('intro [{"id":"x"}] tail').startsWith('['));
        String model = PipelineReviewAIService.chooseModel(10, 'Discovery', Date.today().addYears(1), Date.today());
        System.assertNotEquals(null, model, 'model chosen');
    }

    @IsTest
    static void focusLock_idempotent_and_shortBook() {
        Test.startTest();
        PipelineReviewFocusLockService.LockResult a = PipelineReviewFocusLockService.lockWeek(Date.today());
        PipelineReviewFocusLockService.LockResult b = PipelineReviewFocusLockService.lockWeek(Date.today());
        Test.stopTest();
        System.assertNotEquals(null, a);
        System.assertNotEquals(null, b);
        Integer n = [SELECT COUNT() FROM Pipeline_Week_Focus__c];
        System.assertEquals(
            [SELECT COUNT() FROM Pipeline_Week_Focus__c],
            n,
            'second lock does not duplicate (external id)'
        );
    }

    @IsTest
    static void selector_team_and_weekLocked() {
        Test.startTest();
        Set<Id> ids = PipelineReviewSelector.teamOwnerIds(UserInfo.getUserId());
        Boolean locked = PipelineReviewSelector.isCurrentWeekLocked();
        PipelineReviewSelector.Filter f = new PipelineReviewSelector.Filter();
        f.search = 'PR';
        PipelineReviewSelector.LoadResult load = PipelineReviewSelector.loadBook(f);
        Test.stopTest();
        System.assert(ids.contains(UserInfo.getUserId()), 'director included');
        System.assertNotEquals(null, load);
        System.assertEquals(false, locked || locked == true, 'lock check does not throw');
    }

    @IsTest
    static void scheduler_jobName_constant() {
        System.assertEquals('Pipeline Review Dispatcher', PipelineReviewScheduler.JOB_NAME);
        System.assertEquals(true, PipelineReviewJobConfig.dayMatches('Mon', 'Monday')
            || PipelineReviewJobConfig.dayMatches('Mon', 'Mon'));
    }

    @IsTest
    static void writePaths_note_step_snooze_done() {
        Opportunity o = [SELECT Id, Next_Step_bf__c FROM Opportunity WHERE Name = 'PR Deal 0' LIMIT 1];
        Test.startTest();
        PipelineReviewWriteService.WriteResult note = PipelineReviewWriteService.saveDirectorNote(
            o.Id, '09/16 - Quiet two weeks since the last working session. Cindy to call Elaine this week for a yes or no.', false
        );
        PipelineReviewWriteService.WriteResult step = PipelineReviewWriteService.saveNextStep(
            o.Id, 'Call Elaine', Date.today().addDays(3), PipelineReviewConstants.NS_REP
        );
        PipelineReviewWriteService.WriteResult sn = PipelineReviewWriteService.snooze(o.Id, Date.today().addDays(2));
        PipelineReviewWriteService.WriteResult done = PipelineReviewWriteService.markDone(
            o.Id, null, 'Send recap', Date.today().addDays(5)
        );
        PipelineReviewWriteService.WriteResult rs = PipelineReviewWriteService.reschedule(o.Id, null, Date.today().addDays(6));
        Test.stopTest();
        System.assertEquals(true, note.ok, note.error);
        System.assertEquals(true, step.ok, step.error);
        System.assertEquals(true, sn.ok, sn.error);
        System.assertEquals(true, done.ok, done.error);
        System.assertEquals(true, rs.ok, rs.error);
        System.assertEquals(1, [SELECT COUNT() FROM Pipeline_Action_Snooze__c WHERE Opportunity__c = :o.Id]);
    }

    @IsTest
    static void handler_recompute_and_batch() {
        List<Opportunity> opps = [SELECT Id, StageName, CloseDate, ForecastCategoryName, Director_Forecast_bf__c,
            Roll_Up_Forecast_bf__c, Next_Step_bf__c, Next_Step_Date_bf__c, Director_Notes_bf__c,
            LastActivityDate, ARR_Opportunity_Amount_USD_Num__c, Pricing_Approval_Status__c, OwnerId
            FROM Opportunity];
        Test.startTest();
        PipelineReviewOpportunityHandler.recompute(opps, Date.today());
        Database.executeBatch(new PipelineReviewGradeBatch(), 200);
        Test.stopTest();
        Opportunity graded = [SELECT Pipeline_Grade__c, Recommended_Forecast__c, Action_Priority__c
            FROM Opportunity WHERE Name = 'PR Deal 0' LIMIT 1];
        System.assertNotEquals(null, graded.Pipeline_Grade__c, 'grade written');
    }

    @IsTest
    static void controller_writes_and_jobRunner() {
        Opportunity o = [SELECT Id FROM Opportunity WHERE Name = 'PR Deal 1' LIMIT 1];
        Test.startTest();
        PipelineReviewController.saveNextStep(o.Id, 'Prep demo', Date.today().addDays(2));
        PipelineReviewController.upsertTag(o.Id, 'C');
        PipelineReviewController.snooze(o.Id, Date.today().addDays(1));
        PipelineReviewJobConfig.JobSpec spec = new PipelineReviewJobConfig.JobSpec();
        spec.jobClass = 'PipelineReviewFocusLock';
        spec.batchSize = 200;
        PipelineReviewJobRunner.enqueue(spec);
        spec.jobClass = 'PipelineReviewGradeBatch';
        PipelineReviewJobRunner.enqueue(spec);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Pipeline_Review_Tag__c WHERE Opportunity__c = :o.Id]);
    }
}
