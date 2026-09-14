/**
 * Sales Tools > Pricing Review View Checklist Tool.
 * Implements the Euna "pricing-review-checklist" skill in-platform: for open
 * deals >= $30K ARR, the tool reads the opportunity's context (fields, activity,
 * Gong calls, existing Euna relationships) and asks Claude to pre-fill the 24
 * checklist questions. The AE reviews/edits and clicks Complete, which persists
 * the answers on the opportunity and attaches a branded Euna Word document to
 * its Files. Saved answers are readable back on the tool page.
 */
public with sharing class PricingReviewController {

    public static final Decimal REVIEW_FLOOR = 30000;
    public static final String DEFAULT_DIRECTOR = 'Ben Johnson';

    // The 24 checklist questions, in order, from the skill.
    public static final List<String> QUESTIONS = new List<String>{
        'Total Budget and Operating Budget, Population/Student Count + Employees',
        'Where did this Opportunity come from?',
        'Do they have an Euna product currently? What? When purchased? Current ARR?',
        'How partial has the prospect been to our solution thus far?',
        'Who are we competing against and where do we expect them to be on pricing?',
        'Who are comparable customers and what have we priced them at?',
        'Does the prospect have budget for this project? How much?',
        'How much weight is being placed on pricing in the evaluation?',
        'Have we already communicated a previous quote or ballpark pricing?',
        'Any timing pressure on delivery of a pricing quote?',
        'Is this pricing based on: Budgetary / Direct Purchase / State Contract / RFP?',
        'What is their purchasing process? Open to cooperative purchasing vehicles?',
        'Is there an opportunity for a time-based incentive to drive a decision?',
        'Over what period is the prospect evaluating TCO? 3 years or less? 5 or more?',
        'What is more important: minimizing Year 1 cost or minimizing ongoing SaaS costs?',
        'What are the main drivers behind their decision to purchase?',
        'What differentiates Euna from our competition?',
        'How many users need access to the software?',
        'Is the target execution date known?',
        'Has a SE or IM reviewed or scoped this?',
        'What Sales Options have been included?',
        'What non-standard items have been requested?',
        'When does implementation need to be completed by?',
        'What are your recommendations on Pricing and Term?'
    };

    public class ReviewDeal {
        @AuraEnabled public Id id;
        @AuraEnabled public String account, ae, stage, leadSource, director, statusOverride;
        @AuraEnabled public Decimal arr;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public Boolean reviewDone;
    }

    public class ReviewData {
        @AuraEnabled public Boolean isDirector = false;
        @AuraEnabled public String scope;
        @AuraEnabled public List<ReviewDeal> deals = new List<ReviewDeal>();
    }

    /**
     * Deals for the tool, scoped by role: a director defaults to the team's open
     * deals (scope 'mine' narrows to their own); an AE always sees only their own.
     */
    @AuraEnabled(cacheable=true)
    public static ReviewData getReviewData(String scope) {
        ReviewData out = new ReviewData();
        Set<Id> team = CockpitRosterService.teamIds(UserInfo.getUserId());
        out.isDirector = !team.isEmpty();
        Boolean teamScope = out.isDirector && scope != 'mine';
        out.scope = teamScope ? 'team' : 'mine';

        Set<Id> owners = new Set<Id>{ UserInfo.getUserId() };
        if (teamScope) owners.addAll(team);

        for (Opportunity o : [
            SELECT Id, Name, Account.Name, Owner.Name, StageName, CloseDate, LeadSource,
                   Sales_Director__c, ARR_Opportunity_Amount_USD_Num__c,
                   Pricing_Review_Answers__c, Pricing_Review_Override__c
            FROM Opportunity
            WHERE IsClosed = false AND OwnerId IN :owners
              AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
              AND ARR_Opportunity_Amount_USD_Num__c >= :REVIEW_FLOOR
            ORDER BY ARR_Opportunity_Amount_USD_Num__c DESC
            LIMIT 500
        ]) {
            ReviewDeal r = new ReviewDeal();
            r.id = o.Id;
            r.account = (o.Account != null) ? o.Account.Name : o.Name;
            r.ae = (o.Owner != null) ? o.Owner.Name : null;
            r.stage = o.StageName;
            r.arr = o.ARR_Opportunity_Amount_USD_Num__c;
            r.closeDate = o.CloseDate;
            r.leadSource = o.LeadSource;
            r.director = String.isNotBlank(o.Sales_Director__c) ? o.Sales_Director__c : DEFAULT_DIRECTOR;
            r.statusOverride = o.Pricing_Review_Override__c;
            r.reviewDone = isDone(o.Pricing_Review_Answers__c, o.Pricing_Review_Override__c);
            out.deals.add(r);
        }
        return out;
    }

    /** Manual override of the completion status: 'Done', 'Not Done', or blank to auto-derive. */
    @AuraEnabled
    public static void setReviewStatus(Id opportunityId, String newStatus) {
        if (opportunityId == null) throw new AuraHandledException('An opportunity is required.');
        String v = String.isBlank(newStatus) ? null : newStatus.trim();
        if (v != null && v != 'Done' && v != 'Not Done') {
            throw new AuraHandledException('Status must be Done, Not Done, or blank.');
        }
        update new Opportunity(Id = opportunityId, Pricing_Review_Override__c = v);
    }

    /** Effective status: the override wins; otherwise derived from persisted answers. */
    private static Boolean isDone(String answers, String ovr) {
        if (ovr == 'Done') return true;
        if (ovr == 'Not Done') return false;
        return String.isNotBlank(answers);
    }

    /** Opportunity ids whose pricing review counts as complete (override-aware). */
    public static Set<Id> reviewedOppIds(Set<Id> oppIds) {
        Set<Id> done = new Set<Id>();
        if (oppIds == null || oppIds.isEmpty()) return done;
        // Long text areas can't be filtered in SOQL; select and test in Apex.
        for (Opportunity o : [
            SELECT Id, Pricing_Review_Answers__c, Pricing_Review_Override__c
            FROM Opportunity WHERE Id IN :oppIds
        ]) { if (isDone(o.Pricing_Review_Answers__c, o.Pricing_Review_Override__c)) done.add(o.Id); }
        return done;
    }

    /** Reads back the saved 24 answers so the AE can review them on the tool page. */
    @AuraEnabled
    public static Map<String, String> getReview(Id opportunityId) {
        if (opportunityId == null) return new Map<String, String>();
        List<Opportunity> opps = [
            SELECT Pricing_Review_Answers__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];
        if (opps.isEmpty() || String.isBlank(opps[0].Pricing_Review_Answers__c)) {
            return new Map<String, String>();
        }
        return toStringMap(opps[0].Pricing_Review_Answers__c);
    }

    /**
     * Reads the opportunity's context and asks Claude to draft an answer to each
     * of the 24 questions. Grounded in Salesforce only; questions with no basis
     * come back flagged for the AE to complete.
     */
    @AuraEnabled
    public static Map<String, String> draftAnswers(Id opportunityId) {
        if (opportunityId == null) throw new AuraHandledException('An opportunity is required.');
        Opportunity o = loadContextOpp(opportunityId);

        String prompt = buildDraftPrompt(o);
        String raw;
        try {
            raw = AnthropicService.complete(prompt, 'claude-sonnet-5', 8192);
        } catch (Exception e) {
            throw new AuraHandledException('AI pre-fill failed: ' + e.getMessage());
        }
        Map<String, String> drafted = toStringMap(stripFences(raw));
        // Guarantee a value for every question so the form is fully pre-filled.
        Map<String, String> out = new Map<String, String>();
        for (Integer i = 1; i <= QUESTIONS.size(); i++) {
            String v = drafted.get('Q' + i);
            out.put('Q' + i, String.isBlank(v) ? '[No data in Salesforce \u2014 AE to complete]' : v.trim());
        }
        return out;
    }

    /** Regenerates ('try') or expands ('expand') a single question via Claude. */
    @AuraEnabled
    public static String draftOne(Id opportunityId, Integer questionNum, String mode, String current) {
        if (opportunityId == null || questionNum == null || questionNum < 1 || questionNum > QUESTIONS.size()) {
            throw new AuraHandledException('A valid opportunity and question are required.');
        }
        Opportunity o = loadContextOpp(opportunityId);
        String q = QUESTIONS[questionNum - 1];
        String ask = (mode == 'expand')
            ? 'Expand and sharpen the following draft answer with more specific detail from the context.\nQuestion: ' + q + '\nCurrent draft: ' + (String.isBlank(current) ? '(none)' : current)
            : 'Draft a concise answer (1-3 sentences) to the following question.\nQuestion: ' + q;
        String prompt = 'You are helping a Euna Solutions Account Executive complete a Pricing Review Checklist '
            + 'for a government/public-sector software deal. Answer using the Salesforce context below. If the '
            + 'context has direct evidence, use it. If not, give your best inference from the context (entity type/'
            + 'size, US public-sector procurement norms, deal stage, typical competitors and TCO) and PREFIX it '
            + 'with "INFERRED: ". Do not fabricate specific figures, quotes, or names not in the context. '
            + 'Return ONLY the answer text \u2014 no preamble, no question restatement, no JSON.\n\n'
            + ask + '\n\nCONTEXT:\n' + context(o);
        String raw;
        try {
            raw = AnthropicService.complete(prompt, 'claude-sonnet-5', 700);
        } catch (Exception e) {
            throw new AuraHandledException('AI generation failed: ' + e.getMessage());
        }
        return String.isBlank(raw) ? '' : stripFences(raw).trim();
    }

    private static Opportunity loadContextOpp(Id opportunityId) {
        List<Opportunity> opps = [
            SELECT Id, Name, AccountId, Account.Name, Account.BillingState, Account.BillingCity,
                   Account.Industry, Account.Sub_Vertical__c, Account.AnnualRevenue, Account.Total_Budget_bf__c,
                   Account.Operating_Budget_Year__c, Account.Fiscal_Year_Start_Month__c, Account.Total_Population_bf__c,
                   Account.Student_Count__c, Account.NumberOfEmployees, Account.Current_Budgeting_system__c,
                   Account.Recent_Budget_Trends__c,
                   Owner.Name, StageName, CloseDate, Amount, ARR_Opportunity_Amount_USD_Num__c,
                   EUNA_Solution__c, Sales_Segment__c, Sales_Director__c, ForecastCategoryName,
                   NextStep, Description, LeadSource, Type
            FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];
        if (opps.isEmpty()) throw new AuraHandledException('Opportunity not found or not accessible.');
        return opps[0];
    }

    private static String buildDraftPrompt(Opportunity o) {
        String ctx = context(o);
        String qs = '';
        for (Integer i = 0; i < QUESTIONS.size(); i++) qs += 'Q' + (i + 1) + ': ' + QUESTIONS[i] + '\n';
        return 'You are helping a Euna Solutions Account Executive complete a Pricing Review Checklist '
            + 'for a government/public-sector software deal. Provide a useful draft answer (1-3 sentences) for '
            + 'EVERY one of the 24 questions \u2014 do not leave any blank.\n'
            + 'Map the context sources to questions: use the ENTITY PROFILE (operating/total budget, student '
            + 'count, employees, budget trends) for Q1 and Q7; the COMPARABLE CUSTOMERS list (their ARR) for Q6; '
            + 'the QUOTED PRODUCTS & SALES OPTIONS for Q21 and to anchor Q24 pricing; and the Gong call brief and '
            + 'transcript and recent activity for Q4 (engagement), Q5/Q17 (competition & differentiation), Q9 '
            + '(prior pricing/ballpark), Q13/Q19 (timing), and Q16 (decision drivers). Read the Gong transcript '
            + 'and budget-trends narrative carefully and extract concrete figures, competitors, timelines, and '
            + 'stakeholders rather than generalizing.\n'
            + 'For each question follow this order:\n'
            + '1) If the context has direct evidence, answer from it.\n'
            + '2) If not directly stated but reasonably inferable from the context (the entity type and size, '
            + 'US public-sector procurement/RFP norms, the deal stage and solution, typical competitors and TCO '
            + 'horizons for this kind of buyer), give your best inference and PREFIX it with "INFERRED: ".\n'
            + '3) "[No data in Salesforce \u2014 AE to complete]" is almost never acceptable \u2014 for a standard '
            + 'public-sector pricing checklist you can always reason a qualitative INFERRED answer (e.g. likely '
            + 'entity size, typical user counts, comparable buyers, common evaluation horizon, sensible pricing/'
            + 'term recommendation). Use it only if a question is truly impossible to infer.\n'
            + 'Answer ALL 24 \u2014 aim for zero "[No data]" responses. Every inferred answer MUST start with '
            + '"INFERRED: " so the AE knows to verify it. Do not fabricate specific figures, quotes, or names that '
            + 'are not in the context; inferences should be qualitative ranges or clearly hypothetical.\n'
            + 'Keep every answer to 1-2 sentences (about 35 words max) so all 24 fit.\n'
            + 'Return ONLY a JSON object whose keys are Q1 through Q24 and whose values are strings. '
            + 'No markdown, no code fences, no commentary.\n\nQUESTIONS:\n' + qs + '\nCONTEXT:\n' + ctx;
    }

    /** Assembles the deal context from opp fields, existing relationships, activity and Gong calls. */
    private static String context(Opportunity o) {
        String acct = (o.Account != null) ? o.Account.Name : o.Name;
        String s = 'Opportunity: ' + o.Name + '\nAccount: ' + acct
            + '\nLocation: ' + join(new List<String>{ safe(o.Account != null ? o.Account.BillingCity : null), safe(o.Account != null ? o.Account.BillingState : null) }, ', ')
            + '\nOwner (AE): ' + (o.Owner != null ? o.Owner.Name : '')
            + '\nSales Director: ' + safe(o.Sales_Director__c)
            + '\nStage: ' + safe(o.StageName) + '\nType: ' + safe(o.Type)
            + '\nForecast Category: ' + safe(o.ForecastCategoryName)
            + '\nClose Date: ' + (o.CloseDate != null ? o.CloseDate.format() : '')
            + '\nAmount: ' + (o.Amount != null ? String.valueOf(o.Amount) : '')
            + '\nARR (USD): ' + (o.ARR_Opportunity_Amount_USD_Num__c != null ? String.valueOf(o.ARR_Opportunity_Amount_USD_Num__c) : '')
            + '\nEuna Solution: ' + safe(o.EUNA_Solution__c) + '\nSales Segment: ' + safe(o.Sales_Segment__c)
            + '\nLead Source: ' + safe(o.LeadSource) + '\nNext Step: ' + safe(o.NextStep)
            + '\nDescription: ' + clip(safe(o.Description), 1500) + '\n';

        // Entity profile from the Account (Q1: budget, size, student/employee counts)
        if (o.Account != null) {
            s += '\nEntity profile (from the Account record \u2014 authoritative for Q1):\n'
              + '  Vertical / Sub-Vertical: ' + safe(o.Account.Industry) + ' / ' + safe(o.Account.Sub_Vertical__c) + '\n'
              + '  Latest Operating Budget: ' + fmtCur(o.Account.AnnualRevenue) + '\n'
              + '  Total Budget: ' + fmtCur(o.Account.Total_Budget_bf__c) + '\n'
              + '  Operating Budget Year: ' + num(o.Account.Operating_Budget_Year__c) + '\n'
              + '  Fiscal Year Start Month: ' + safe(o.Account.Fiscal_Year_Start_Month__c) + '\n'
              + '  Student Count: ' + num(o.Account.Student_Count__c) + '\n'
              + '  Population Served: ' + num(o.Account.Total_Population_bf__c) + '\n'
              + '  Employees: ' + num(o.Account.NumberOfEmployees) + '\n'
              + '  Current Budgeting System: ' + safe(o.Account.Current_Budgeting_system__c) + '\n'
              + '  Recent Budget Trends: ' + clip(safe(o.Account.Recent_Budget_Trends__c), 1400) + '\n';
        }

        // Comparable Euna customers by vertical for pricing anchors (Q6)
        if (o.Account != null && String.isNotBlank(o.Account.Industry)) {
            s += '\nComparable Euna customers (same vertical, active contracts \u2014 pricing anchors for Q6):\n';
            List<Contract> comps = [
                SELECT Account.Name, Account.Student_Count__c, ARR_Rollup__c, EUNA_Solution_Name_Formula__c
                FROM Contract
                WHERE Status = 'Activated' AND ARR_Rollup__c > 0
                  AND Account.Industry = :o.Account.Industry AND AccountId != :o.AccountId
                ORDER BY ARR_Rollup__c DESC LIMIT 8
            ];
            if (comps.isEmpty()) s += '  (none found)\n';
            for (Contract c : comps) {
                s += '  - ' + safe(c.Account != null ? c.Account.Name : '') + ' | students=' + num(c.Account != null ? c.Account.Student_Count__c : null)
                   + ' | ARR=' + fmtCur(c.ARR_Rollup__c) + ' | ' + safe(c.EUNA_Solution_Name_Formula__c) + '\n';
            }
        }

        // Quoted products / sales options (Q21)
        s += '\nQuoted products & sales options (from the opportunity\u2019s Quotes \u2014 authoritative for Q21):\n';
        Set<String> seenLines = new Set<String>();
        for (QuoteLineItem q : [
            SELECT Product2.Name, Quantity, UnitPrice, TotalPrice
            FROM QuoteLineItem WHERE Quote.OpportunityId = :o.Id
            ORDER BY Quote.CreatedDate DESC, TotalPrice DESC LIMIT 40
        ]) {
            Decimal qty = (q.Quantity == null) ? null : Decimal.valueOf(String.valueOf(q.Quantity));
            Decimal unit = (q.UnitPrice == null) ? null : Decimal.valueOf(String.valueOf(q.UnitPrice));
            Decimal tot = (q.TotalPrice == null) ? null : Decimal.valueOf(String.valueOf(q.TotalPrice));
            String line = safe(q.Product2 != null ? q.Product2.Name : '') + ' | qty=' + num(qty)
                        + ' | unit=' + fmtCur(unit) + ' | total=' + fmtCur(tot);
            if (seenLines.add(line)) s += '  - ' + line + '\n';
        }
        if (seenLines.isEmpty()) s += '  (no quote lines)\n';

        // Existing Euna relationships (Q3)
        List<String> rels = new List<String>();
        for (Account_Solution_Relationship__c r : [
            SELECT Euna_Solution__c, Status__c FROM Account_Solution_Relationship__c
            WHERE Account__c = :o.AccountId AND Status__c IN ('Customer', 'Customer - Child') LIMIT 10
        ]) { rels.add(safe(r.Euna_Solution__c) + ' (' + safe(r.Status__c) + ')'); }
        s += '\nExisting Euna relationships: ' + (rels.isEmpty() ? 'none found' : String.join(rels, '; ')) + '\n';

        // Recent activity (Q9, Q16)
        s += '\nRecent activity:\n';
        List<Task> tasks = [
            SELECT Subject, Description, ActivityDate, Type, CreatedDate
            FROM Task WHERE WhatId = :o.Id ORDER BY CreatedDate DESC LIMIT 15
        ];
        if (tasks.isEmpty()) s += '  (none)\n';
        for (Task t : tasks) {
            s += '  - ' + (t.CreatedDate != null ? t.CreatedDate.date().format() : '') + ' [' + safe(t.Type) + '] '
               + safe(t.Subject) + ' \u2014 ' + clip(safe(t.Description), 220) + '\n';
        }

        // Gong calls incl. transcript/brief (Q4, Q9, Q17). Scope is often 'Unknown'
        // in this org, so we include everything non-private rather than External-only.
        s += '\nGong calls:\n';
        List<Gong__Gong_Call__c> calls = [
            SELECT Gong__Title__c, Gong__Call_Start__c, Gong__Call_Brief__c, Gong__Pricing_Duration__c,
                   Gong__Talk_Time_Them__c, Gong_Transcript__c
            FROM Gong__Gong_Call__c
            WHERE Gong__Primary_Opportunity__c = :o.Id AND Gong__Is_Private__c = false
              AND Gong__Scope__c != 'Internal'
            ORDER BY Gong__Call_Start__c DESC LIMIT 3
        ];
        if (calls.isEmpty()) s += '  (none)\n';
        for (Gong__Gong_Call__c c : calls) {
            String body = '';
            if (String.isNotBlank(c.Gong__Call_Brief__c)) body += 'Brief: ' + clip(safe(c.Gong__Call_Brief__c), 900) + '\n    ';
            if (String.isNotBlank(c.Gong_Transcript__c)) body += 'Transcript: ' + clip(c.Gong_Transcript__c, 4200);
            if (String.isBlank(body)) body = '(no brief or transcript synced yet)';
            String talk = (c.Gong__Talk_Time_Them__c != null) ? ' prospect-talk-time=' + c.Gong__Talk_Time_Them__c : '';
            s += '  - ' + (c.Gong__Call_Start__c != null ? c.Gong__Call_Start__c.date().format() : '') + ' '
               + safe(c.Gong__Title__c) + (c.Gong__Pricing_Duration__c != null && c.Gong__Pricing_Duration__c > 0 ? ' [pricing discussed]' : '') + talk
               + '\n    ' + body + '\n';
        }
        return clip(s, 34000);
    }

    /** Builds and attaches the branded Euna Pricing Review Checklist and persists the answers. */
    @AuraEnabled
    public static Id createReview(Id opportunityId, Map<String, String> answers) {
        if (opportunityId == null) throw new AuraHandledException('An opportunity is required.');
        if (answers == null) answers = new Map<String, String>();
        List<Opportunity> opps = [
            SELECT Id, Name, Account.Name, Owner.Name, StageName, CloseDate, Sales_Director__c
            FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];
        if (opps.isEmpty()) throw new AuraHandledException('Opportunity not found or not accessible.');
        Opportunity o = opps[0];
        String acct = (o.Account != null) ? o.Account.Name : o.Name;
        String director = String.isNotBlank(o.Sales_Director__c) ? o.Sales_Director__c : DEFAULT_DIRECTOR;
        String html = buildDoc(o, acct, director, answers);

        // Persist the responses so they can be reviewed again on the tool page.
        o.Pricing_Review_Answers__c = JSON.serialize(answers);
        update o;

        ContentVersion cv = new ContentVersion(
            Title = 'Pricing Review - ' + acct + ' - ' + Date.today().format(),
            PathOnClient = 'Euna_Pricing_Review_' + acct.replaceAll('[^a-zA-Z0-9]', '_') + '.doc',
            VersionData = Blob.valueOf(html)
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId, LinkedEntityId = opportunityId,
            ShareType = 'V', Visibility = 'AllUsers');
        return docId;
    }

    // ---- helpers ----

    @SuppressWarnings('PMD')
    private static Map<String, String> toStringMap(String jsonText) {
        Map<String, String> out = new Map<String, String>();
        if (String.isBlank(jsonText)) return out;
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonText);
            for (String k : parsed.keySet()) {
                Object v = parsed.get(k);
                out.put(k, v == null ? '' : String.valueOf(v));
            }
        } catch (Exception e) {
            // Truncated/invalid JSON (e.g. a long reply cut off) \u2014 recover below.
        }
        // Regex recovery salvages complete "Qn":"..." pairs even from a truncated reply,
        // so one cut-off answer doesn't wipe the other 23.
        if (out.isEmpty()) {
            Matcher m = Pattern.compile('"(Q\\d+)"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"').matcher(jsonText);
            while (m.find()) { out.put(m.group(1), unescapeJson(m.group(2))); }
        }
        return out;
    }
    private static String unescapeJson(String s) {
        if (s == null) return '';
        return s.replace('\\n', '\n').replace('\\r', '').replace('\\t', ' ')
                .replace('\\"', '"').replace('\\/', '/').replace('\\\\', '\\');
    }

    /** Strips a ```json ... ``` fence if the model wrapped its reply. */
    private static String stripFences(String s) {
        if (String.isBlank(s)) return s;
        String t = s.trim();
        if (t.startsWith('```')) {
            t = t.replaceFirst('^```[a-zA-Z]*\\s*', '').replaceFirst('```\\s*$', '');
        }
        Integer a = t.indexOf('{'), b = t.lastIndexOf('}');
        return (a >= 0 && b > a) ? t.substring(a, b + 1) : t;
    }

    private static String buildDoc(Opportunity o, String acct, String director, Map<String, String> answers) {
        String rep = (o.Owner != null) ? o.Owner.Name : '';
        String rows = '';
        for (Integer i = 0; i < QUESTIONS.size(); i++) {
            String ans = answers.get('Q' + (i + 1));
            Boolean blank = String.isBlank(ans);
            String cellVal = blank
                ? '<span style="color:#DC2626;font-weight:bold">\u26A0 NOT ANSWERED</span>'
                : esc(ans);
            String bg = (Math.mod(i, 2) == 0) ? ' style="background:#F8F9FC"' : '';
            rows += '<tr' + bg + '><td><b>Q' + (i + 1) + '</b></td><td><b>' + esc(QUESTIONS[i])
                 + '</b></td><td>' + cellVal + '</td></tr>';
        }
        return '<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" '
            + 'xmlns="http://www.w3.org/TR/REC-html40"><head><meta charset="utf-8"><title>Euna Pricing Review Checklist</title></head>'
            + '<body style="font-family:\'Open Sans\',Calibri,Arial,sans-serif;color:#1a1a2e">'
            + '<p style="color:#FF6E14;font-weight:bold;font-size:11pt;margin:0">EUNA SOLUTIONS\u00AE</p>'
            + '<h1 style="color:#281978;font-family:Montserrat,Arial,sans-serif;font-size:24pt;margin:2px 0">Pricing Review Checklist</h1>'
            + '<p style="color:#64748B;font-size:10pt;margin:0 0 14px">Complete before submitting for pricing approval \u2014 Internal Use Only</p>'
            + '<h2 style="color:#281978;border-bottom:2px solid #281978;padding-bottom:3px">Opportunity Details</h2>'
            + '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;width:100%">'
            + drow('Opportunity Name', o.Name) + drow('Date', Date.today().format())
            + drow('Sales Rep', rep) + drow('Sales Director', director) + '</table>'
            + '<h2 style="color:#281978;border-bottom:2px solid #281978;padding-bottom:3px;margin-top:18px">Review Questions</h2>'
            + '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;width:100%">'
            + '<tr style="background:#281978;color:#fff"><td width="6%"><b>#</b></td><td width="42%"><b>Question / Review Item</b></td><td><b>Notes / Response</b></td></tr>'
            + rows + '</table>'
            + '<h2 style="color:#281978;border-bottom:2px solid #281978;padding-bottom:3px;margin-top:18px">Sign-Off</h2>'
            + '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;width:100%">'
            + '<tr><td width="50%"><b>Sales Director Approval</b></td><td>No</td></tr></table>'
            + '<p style="text-align:center;color:#9CA3AF;font-style:italic;font-size:9pt;margin-top:20px">'
            + 'Euna Solutions\u00AE \u2014 Pricing Review Checklist \u2014 Internal Use Only</p>'
            + '</body></html>';
    }
    private static String drow(String k, String v) {
        return '<tr><td style="background:#281978;color:#fff;width:30%"><b>' + esc(k) + '</b></td><td>' + esc(String.isBlank(v) ? '\u2014' : v) + '</td></tr>';
    }
    private static String esc(String s) {
        return s == null ? '' : s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }
    private static String safe(String s) { return s == null ? '' : s; }
    private static String num(Decimal d) { return d == null ? '' : String.valueOf(d.setScale(0)); }
    private static String fmtCur(Decimal d) { return d == null ? '' : '$' + d.setScale(0).format(); }
    private static String clip(String s, Integer n) { return (s != null && s.length() > n) ? s.substring(0, n) + '\u2026' : s; }
    private static String join(List<String> parts, String sep) {
        List<String> keep = new List<String>();
        for (String p : parts) if (String.isNotBlank(p)) keep.add(p);
        return String.join(keep, sep);
    }
}
