/**
 * Director-note and next-step generation. One AnthropicClient, one callout
 * per N opportunities. Never fabricates a note on parse failure.
 */
public with sharing class PipelineReviewAIService {
    public class GenerateResult {
        public Id opportunityId;
        public String note;
        public String forecast;
        public String nextStep;
        public Date nextStepDate;
        public String error;
        public Boolean ok;
        public Integer inputTokens;
        public Integer outputTokens;
    }

    public static String chooseModel(Decimal arr, String stage, Date closeDate, Date today) {
        Decimal quota = Decimal.valueOf(
            ForecastConfigService.stringOf('pipeline.quotaBasis',
                ForecastConfigService.stringOf('quota.quarterly', '761000'))
        );
        Decimal pct = Decimal.valueOf(ForecastConfigService.stringOf('pipeline.bigDealPercent', '5'));
        Pipeline_Priority_Config__mdt cfg = PipelineReviewSelector.priorityConfig();
        if (cfg != null) {
            if (cfg.Quota_Basis__c != null) quota = cfg.Quota_Basis__c;
            if (cfg.Big_Deal_Percent__c != null) pct = cfg.Big_Deal_Percent__c;
        }
        Decimal floor = quota * (pct / 100);
        Boolean late = stage != null && PipelineReviewConstants.LATE_STAGES.contains(stage);
        Boolean inQ = closeDate != null && today != null
            && closeDate.year() == today.year()
            && ((closeDate.month() - 1) / 3) == ((today.month() - 1) / 3);
        if ((arr != null && arr >= floor) || late || inQ) {
            return AnthropicClient.MODEL_SONNET_4_6;
        }
        return AnthropicClient.MODEL_HAIKU_4_5;
    }

    public static List<GenerateResult> generateNotes(List<Opportunity> opps, Date today, Boolean persistPreview) {
        List<GenerateResult> out = new List<GenerateResult>();
        if (opps == null || opps.isEmpty()) return out;
        Integer batchSize = PipelineReviewConstants.DEFAULT_NOTE_BATCH;
        String rawSize = ForecastConfigService.stringOf('pipeline.noteBatchSize', '15');
        try { batchSize = Integer.valueOf(rawSize); } catch (Exception e) { batchSize = 15; }
        List<Id> ids = new List<Id>();
        for (Opportunity o : opps) ids.add(o.Id);
        String model = chooseModel(
            (Decimal) opps[0].get('ARR_Opportunity_Amount_USD_Num__c'),
            opps[0].StageName,
            opps[0].CloseDate,
            today
        );
        AnthropicClient.CompletionRequest req = new AnthropicClient.CompletionRequest();
        req.model = model;
        req.disableThinking = true;
        req.maxTokens = 220 * opps.size();
        req.timeoutMs = 110000;
        req.systemPrompt = noteSystemPrompt();
        req.userPrompt = noteUserPrompt(opps, today);
        AnthropicClient.CompletionResponse res;
        try {
            res = AnthropicClient.complete(req);
        } catch (Exception e) {
            for (Opportunity o : opps) {
                GenerateResult g = new GenerateResult();
                g.opportunityId = o.Id;
                g.ok = false;
                g.error = e.getMessage();
                out.add(g);
            }
            return out;
        }
        PipelineReviewGradeService.ReplyMatch match =
            PipelineReviewGradeService.matchReply(ids, extractJsonArray(res == null ? null : res.text));
        for (Opportunity o : opps) {
            GenerateResult g = new GenerateResult();
            g.opportunityId = o.Id;
            g.inputTokens = res == null ? 0 : res.inputTokens;
            g.outputTokens = res == null ? 0 : res.outputTokens;
            if (match.matched.containsKey(o.Id)) {
                String note = match.matched.get(o.Id).get('note');
                String fc = match.matched.get(o.Id).get('forecast');
                if (PipelineReviewGradeService.isValidNote(note)) {
                    g.ok = true;
                    g.note = note;
                    g.forecast = fc;
                } else {
                    g.ok = false;
                    g.error = 'Note failed validation.';
                }
            } else {
                g.ok = false;
                g.error = 'Reply missing this opportunity.';
            }
            out.add(g);
        }
        return out;
    }

    public static GenerateResult generateNextStep(Opportunity o, Date today) {
        GenerateResult g = new GenerateResult();
        g.opportunityId = o.Id;
        if (o.CloseDate != null && today != null && today > o.CloseDate) {
            g.ok = false;
            g.error = 'Date conflict: today is after Close Date.';
            return g;
        }
        AnthropicClient.CompletionRequest req = new AnthropicClient.CompletionRequest();
        req.model = chooseModel(
            (Decimal) o.get('ARR_Opportunity_Amount_USD_Num__c'), o.StageName, o.CloseDate, today
        );
        req.disableThinking = true;
        req.maxTokens = 220;
        req.timeoutMs = 110000;
        req.systemPrompt = nextStepSystemPrompt();
        req.userPrompt = nextStepUserPrompt(o, today, false);
        try {
            AnthropicClient.CompletionResponse res = AnthropicClient.complete(req);
            PipelineReviewGradeService.ReplyMatch match =
                PipelineReviewGradeService.matchReply(new List<Id>{ o.Id }, extractJsonArray(res.text));
            if (!match.matched.containsKey(o.Id)) {
                g.ok = false;
                g.error = 'Reply missing this opportunity.';
                return g;
            }
            String step = match.matched.get(o.Id).get('nextStep');
            Date d = parseIsoDate(match.matched.get(o.Id).get('nextStepDate'));
            if (String.isBlank(step) || step.length() > PipelineReviewConstants.SUGGEST_MAX_CHARS) {
                g.ok = false;
                g.error = 'Suggestion failed validation.';
                return g;
            }
            if (PipelineReviewGradeService.similarity(step, o.Next_Step_bf__c) >= PipelineReviewConstants.PARKED_SIMILARITY) {
                req.userPrompt = nextStepUserPrompt(o, today, true);
                res = AnthropicClient.complete(req);
                match = PipelineReviewGradeService.matchReply(new List<Id>{ o.Id }, extractJsonArray(res.text));
                if (match.matched.containsKey(o.Id)) {
                    step = match.matched.get(o.Id).get('nextStep');
                    d = parseIsoDate(match.matched.get(o.Id).get('nextStepDate'));
                }
                if (PipelineReviewGradeService.similarity(step, o.Next_Step_bf__c) >= PipelineReviewConstants.PARKED_SIMILARITY) {
                    g.ok = false;
                    g.error = 'Suggestion paraphrased the current next step.';
                    return g;
                }
            }
            if (d == null || (today != null && d < today) || (o.CloseDate != null && d > o.CloseDate)) {
                g.ok = false;
                g.error = 'Suggestion date is outside today..CloseDate.';
                return g;
            }
            g.ok = true;
            g.nextStep = step;
            g.nextStepDate = d;
        } catch (Exception e) {
            g.ok = false;
            g.error = e.getMessage();
        }
        return g;
    }

    public static String extractJsonArray(String raw) {
        if (String.isBlank(raw)) return null;
        String s = raw.trim();
        Integer start = s.indexOf('[');
        Integer last = s.lastIndexOf(']');
        if (start < 0 || last <= start) return s;
        return s.substring(start, last + 1);
    }

    public static Date parseIsoDate(String raw) {
        if (String.isBlank(raw)) return null;
        try {
            return Date.valueOf(raw.trim().left(10));
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    static String noteSystemPrompt() {
        return 'You write a 400-character director pulse check, not a record summary. '
            + 'Return ONLY a JSON array of {"id":"006...","note":"MM/DD - ...","forecast":"Commit"}. '
            + 'Hard ceiling 400 characters including the MM/DD - prefix. Begin with today\'s date. '
            + 'Lead with what is true today. Never restate deal size. Never name the evidence channel. '
            + 'Never mention missing data. No em dashes. No sentence begins with I. Active voice, real names, real dates. '
            + 'End with one concrete dated next action naming the AE by first name. '
            + 'Good: 08/21 - Patray has legal reviewing the EULA and holds the Aug 28 negotiation session, so paper is moving for the first time since June. The expired quote is the one loose thread. Cindy to refresh it before Aug 28 so signature is not gated on pricing. '
            + 'Bad: 08/21 - $153,850 Verbal Win deal at Franklin County. Stage is Verbal Win. Close date Aug 19. Next step is negotiation. '
            + 'Legal forecast values: Commit, Most Likely, Best Case, Pipeline, Omitted. '
            + 'If you cannot write a valid note, omit that id. Never invent a person or a date.';
    }

    @TestVisible
    static String noteUserPrompt(List<Opportunity> opps, Date today) {
        List<String> blocks = new List<String>();
        String ds = today.month() + '/' + today.day();
        for (Opportunity o : opps) {
            String ae = o.Owner == null ? '' : o.Owner.Name;
            blocks.add(
                'Id=' + o.Id
                + '\nAccount=' + (o.Account == null ? o.Name : o.Account.Name)
                + '\nAE=' + ae
                + '\nStage=' + o.StageName
                + '\nClose=' + String.valueOf(o.CloseDate)
                + '\nAEForecast=' + o.ForecastCategoryName
                + '\nDirectorForecast=' + o.Director_Forecast_bf__c
                + '\nNextStep=' + o.Next_Step_bf__c
                + '\nNextStepDate=' + String.valueOf(o.Next_Step_Date_bf__c)
                + '\nExistingNote=' + o.Director_Notes_bf__c
                + '\nTodayPrefix=' + ds
            );
        }
        return String.join(blocks, '\n---\n');
    }

    @TestVisible
    static String nextStepSystemPrompt() {
        return 'You write one next-step ACTION, not a state. Return ONLY a JSON array of '
            + '{"id":"006...","nextStep":"...","nextStepDate":"YYYY-MM-DD"}. '
            + 'One sentence, under 160 characters. Names who does it and who it lands on. '
            + 'Date >= today and <= CloseDate. Do not paraphrase the current next step.';
    }

    @TestVisible
    static String nextStepUserPrompt(Opportunity o, Date today, Boolean differentMove) {
        return 'Id=' + o.Id
            + '\nToday=' + String.valueOf(today)
            + '\nCloseDate=' + String.valueOf(o.CloseDate)
            + '\nAE=' + (o.Owner == null ? '' : o.Owner.Name)
            + '\nCurrentNextStep=' + o.Next_Step_bf__c
            + '\nStage=' + o.StageName
            + (differentMove ? '\nPropose a DIFFERENT move than the current next step.' : '');
    }
}
