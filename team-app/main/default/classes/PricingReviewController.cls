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
        @AuraEnabled public String account, ae, stage, leadSource, director;
        @AuraEnabled public Decimal arr;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public Boolean reviewDone;
    }

    @AuraEnabled(cacheable=true)
    public static List<ReviewDeal> getReviewDeals() {
        Set<Id> owners = CockpitRosterService.teamIds(UserInfo.getUserId());
        owners.add(UserInfo.getUserId());
        List<Opportunity> opps = [
            SELECT Id, Name, Account.Name, Owner.Name, StageName, CloseDate, LeadSource,
                   Sales_Director__c, ARR_Opportunity_Amount_USD_Num__c, Pricing_Review_Answers__c
            FROM Opportunity
            WHERE IsClosed = false AND OwnerId IN :owners
              AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
              AND ARR_Opportunity_Amount_USD_Num__c >= :REVIEW_FLOOR
            ORDER BY ARR_Opportunity_Amount_USD_Num__c DESC
            LIMIT 500
        ];
        List<ReviewDeal> out = new List<ReviewDeal>();
        for (Opportunity o : opps) {
            ReviewDeal r = new ReviewDeal();
            r.id = o.Id;
            r.account = (o.Account != null) ? o.Account.Name : o.Name;
            r.ae = (o.Owner != null) ? o.Owner.Name : null;
            r.stage = o.StageName;
            r.arr = o.ARR_Opportunity_Amount_USD_Num__c;
            r.closeDate = o.CloseDate;
            r.leadSource = o.LeadSource;
            r.director = String.isNotBlank(o.Sales_Director__c) ? o.Sales_Director__c : DEFAULT_DIRECTOR;
            r.reviewDone = String.isNotBlank(o.Pricing_Review_Answers__c);
            out.add(r);
        }
        return out;
    }

    /** Opportunity ids whose pricing review is complete (answers persisted). */
    public static Set<Id> reviewedOppIds(Set<Id> oppIds) {
        Set<Id> done = new Set<Id>();
        if (oppIds == null || oppIds.isEmpty()) return done;
        // Long text areas can't be filtered in SOQL; select and test in Apex.
        for (Opportunity o : [
            SELECT Id, Pricing_Review_Answers__c FROM Opportunity WHERE Id IN :oppIds
        ]) { if (String.isNotBlank(o.Pricing_Review_Answers__c)) done.add(o.Id); }
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
        List<Opportunity> opps = [
            SELECT Id, Name, AccountId, Account.Name, Account.BillingState, Account.BillingCity,
                   Owner.Name, StageName, CloseDate, Amount, ARR_Opportunity_Amount_USD_Num__c,
                   EUNA_Solution__c, Sales_Segment__c, Sales_Director__c, ForecastCategoryName,
                   NextStep, Description, LeadSource, Type
            FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];
        if (opps.isEmpty()) throw new AuraHandledException('Opportunity not found or not accessible.');
        Opportunity o = opps[0];

        String prompt = buildDraftPrompt(o);
        String raw;
        try {
            raw = AnthropicService.complete(prompt, 'claude-sonnet-5', 4096);
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

    private static String buildDraftPrompt(Opportunity o) {
        String ctx = context(o);
        String qs = '';
        for (Integer i = 0; i < QUESTIONS.size(); i++) qs += 'Q' + (i + 1) + ': ' + QUESTIONS[i] + '\n';
        return 'You are helping a Euna Solutions Account Executive complete a Pricing Review Checklist '
            + 'for a government/public-sector software deal. Using ONLY the Salesforce context below, draft '
            + 'a concise suggested answer (1-3 sentences) for each of the 24 questions. Ground every answer in '
            + 'the data provided. If there is no evidence for a question, answer exactly '
            + '"[No data in Salesforce \u2014 AE to complete]". Do not invent facts, numbers, or names. '
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
            FROM Task WHERE WhatId = :o.Id ORDER BY CreatedDate DESC LIMIT 10
        ];
        if (tasks.isEmpty()) s += '  (none)\n';
        for (Task t : tasks) {
            s += '  - ' + (t.CreatedDate != null ? t.CreatedDate.date().format() : '') + ' [' + safe(t.Type) + '] '
               + safe(t.Subject) + ' \u2014 ' + clip(safe(t.Description), 300) + '\n';
        }

        // Gong calls incl. transcript/brief (Q4, Q9, Q17)
        s += '\nGong calls:\n';
        List<Gong__Gong_Call__c> calls = [
            SELECT Gong__Title__c, Gong__Call_Start__c, Gong__Call_Brief__c, Gong__Pricing_Duration__c,
                   Gong__Talk_Time_Them__c, Gong_Transcript__c
            FROM Gong__Gong_Call__c
            WHERE Gong__Primary_Opportunity__c = :o.Id AND Gong__Is_Private__c = false
              AND Gong__Scope__c = 'External'
            ORDER BY Gong__Call_Start__c DESC LIMIT 3
        ];
        if (calls.isEmpty()) s += '  (none)\n';
        for (Gong__Gong_Call__c c : calls) {
            String body = String.isNotBlank(c.Gong_Transcript__c) ? clip(c.Gong_Transcript__c, 1800)
                        : ('brief: ' + clip(safe(c.Gong__Call_Brief__c), 1000));
            s += '  - ' + (c.Gong__Call_Start__c != null ? c.Gong__Call_Start__c.date().format() : '') + ' '
               + safe(c.Gong__Title__c) + (c.Gong__Pricing_Duration__c != null && c.Gong__Pricing_Duration__c > 0 ? ' [pricing discussed]' : '')
               + '\n    ' + body + '\n';
        }
        return clip(s, 24000);
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
            // A non-JSON model reply leaves the map empty; caller fills defaults.
        }
        return out;
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
    private static String clip(String s, Integer n) { return (s != null && s.length() > n) ? s.substring(0, n) + '\u2026' : s; }
    private static String join(List<String> parts, String sep) {
        List<String> keep = new List<String>();
        for (String p : parts) if (String.isNotBlank(p)) keep.add(p);
        return String.join(keep, sep);
    }
}
