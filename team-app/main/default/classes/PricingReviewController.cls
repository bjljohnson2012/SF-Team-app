/**
 * Sales Tools > Pricing Review View Checklist Tool.
 * Implements the Euna "pricing-review-checklist" skill in-platform: for open
 * deals >= $30K ARR, the tool reads newest quote/opp/account/contact/activity/
 * email/call/Gong evidence (Unknown scope included) and asks Claude to pre-fill
 * the 24 checklist questions, searching the web only when that pack is silent.
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
        @AuraEnabled public String account, ae, stage, productInterest, leadSource, director, statusOverride;
        @AuraEnabled public String reviewFileTitle, reviewFileUrl;
        @AuraEnabled public Decimal arr;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public Boolean reviewDone, hasReviewFile;
        @AuraEnabled public Integer reviewFileCount;
    }

    public class ReviewFile {
        @AuraEnabled public Id documentId;
        @AuraEnabled public String title, url;
        @AuraEnabled public Datetime lastModified;
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
                   EUNA_Solution__c, Sales_Director__c, ARR_Opportunity_Amount_USD_Num__c,
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
            r.productInterest = o.EUNA_Solution__c;
            r.arr = o.ARR_Opportunity_Amount_USD_Num__c;
            r.closeDate = o.CloseDate;
            r.leadSource = o.LeadSource;
            r.director = String.isNotBlank(o.Sales_Director__c) ? o.Sales_Director__c : DEFAULT_DIRECTOR;
            r.statusOverride = o.Pricing_Review_Override__c;
            r.reviewDone = isDone(o.Pricing_Review_Answers__c, o.Pricing_Review_Override__c);
            r.hasReviewFile = false;
            r.reviewFileCount = 0;
            out.deals.add(r);
        }
        stampReviewFiles(out.deals);
        return out;
    }

    /**
     * Searches the opportunity Files for an existing Pricing Review checklist document.
     */
    @AuraEnabled
    public static List<ReviewFile> findReviewFiles(Id opportunityId) {
        if (opportunityId == null) throw new AuraHandledException('An opportunity is required.');
        return reviewFilesFor(new Set<Id>{ opportunityId }).get(opportunityId);
    }

    @TestVisible
    static Boolean isReviewFileTitle(String title) {
        if (String.isBlank(title)) return false;
        String t = title.toLowerCase();
        return t.contains('pricing review') || t.contains('euna_pricing_review');
    }

    private static void stampReviewFiles(List<ReviewDeal> deals) {
        if (deals == null || deals.isEmpty()) return;
        Map<Id, ReviewDeal> byId = new Map<Id, ReviewDeal>();
        for (ReviewDeal d : deals) byId.put(d.id, d);
        Map<Id, List<ReviewFile>> found = reviewFilesFor(byId.keySet());
        for (Id oppId : found.keySet()) {
            List<ReviewFile> files = found.get(oppId);
            ReviewDeal d = byId.get(oppId);
            if (d == null || files == null || files.isEmpty()) continue;
            d.hasReviewFile = true;
            d.reviewFileCount = files.size();
            d.reviewFileTitle = files[0].title;
            d.reviewFileUrl = files[0].url;
        }
    }

    private static Map<Id, List<ReviewFile>> reviewFilesFor(Set<Id> oppIds) {
        Map<Id, List<ReviewFile>> out = new Map<Id, List<ReviewFile>>();
        if (oppIds == null || oppIds.isEmpty()) return out;
        for (Id i : oppIds) out.put(i, new List<ReviewFile>());
        try {
            for (ContentDocumentLink l : [
                SELECT LinkedEntityId, ContentDocumentId, ContentDocument.Title, SystemModstamp
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :oppIds
                ORDER BY SystemModstamp DESC
            ]) {
                String title = (l.ContentDocument != null) ? l.ContentDocument.Title : '';
                if (!isReviewFileTitle(title)) continue;
                ReviewFile f = new ReviewFile();
                f.documentId = l.ContentDocumentId;
                f.title = title;
                f.url = '/lightning/r/ContentDocument/' + l.ContentDocumentId + '/view';
                f.lastModified = l.SystemModstamp;
                out.get(l.LinkedEntityId).add(f);
            }
        } catch (Exception e) {
            // File visibility varies by user; leave empty rather than failing the tool.
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
     * Reads the opportunity's newest Salesforce + Gong evidence and asks Claude
     * to draft each of the 24 questions. Web search is used only when that pack
     * still does not answer; reasoned answers stay prefixed INFERRED:.
     */
    @AuraEnabled
    public static Map<String, String> draftAnswers(Id opportunityId) {
        if (opportunityId == null) throw new AuraHandledException('An opportunity is required.');
        Opportunity o = loadContextOpp(opportunityId);

        String prompt = buildDraftPrompt(o);
        String raw;
        try {
            raw = AnthropicService.complete(prompt, 'claude-sonnet-5', 8192, true);
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
            + 'for a government/public-sector software deal. Search every evidence section below (quote, '
            + 'opportunity, account, contacts, all activity, emails, calls, Gong transcripts and briefs including '
            + 'Unknown scope), Active Contracts / Active ARR, LinkSquares agreements, RFP Details, and Files. '
            + 'Prefer the newest dated fact. If Salesforce and Gong still do not answer, search the web and cite '
            + 'the source URL. If the context has direct evidence, use it. If not, PREFIX with "INFERRED: ". '
            + 'For Q3, use Active ARR on contracts and LinkSquares; do not say there is no ARR if a figure exists '
            + 'for any current product. For an RFP, only report a timeline that is explicit in RFP Details or '
            + 'a dated RFP file. For Q1 on a GRANT deal (Amplifund / Grants / GrantExec), evaluate total grant '
            + 'funds managed, not just operating budget. For Q6, prefer exact vertical + same product + '
            + 'operating-budget 0.5x-2x; if none, keep the SAME product (never adjacent) and fall back to '
            + 'Special Districts / County / Town, then a wider 0.25x-4x budget; prefer the same ERP. '
            + 'Return ONLY the answer text \u2014 no preamble, no question restatement, no JSON.\n\n'
            + ask + '\n\nCONTEXT:\n' + PricingReviewEvidence.buildForQuestion(o, questionNum, q);
        String raw;
        try {
            raw = AnthropicService.complete(prompt, 'claude-sonnet-5', 700, true);
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
                   Account.Current_ERP_system__c, Account.Current_Grants_Management_System__c,
                   Account.Grant_Funds_Managed__c, Account.Grant_Funds_Managed_Sources__c,
                   Account.Grant_Funds_Managed_Rationale__c, Account.Government_Grants__c,
                   Account.Annual_Grant_Revenue_Amplifund__c, Account.Recent_Budget_Trends__c,
                   Owner.Name, StageName, CloseDate, Amount, ARR_Opportunity_Amount_USD_Num__c,
                   EUNA_Solution__c, Euna_Solutions_Lookup__r.Name, EUNA_Competitors__c,
                   Has_RFP_Attached__c, RFP_bf__c, RFP_Type__c,
                   Sales_Segment__c, Sales_Director__c, ForecastCategoryName,
                   NextStep, Description, LeadSource, Type
            FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];
        if (opps.isEmpty()) throw new AuraHandledException('Opportunity not found or not accessible.');
        return opps[0];
    }

    private static String buildDraftPrompt(Opportunity o) {
        String ctx = PricingReviewEvidence.build(o);
        String qs = '';
        for (Integer i = 0; i < QUESTIONS.size(); i++) qs += 'Q' + (i + 1) + ': ' + QUESTIONS[i] + '\n';
        return 'You are helping a Euna Solutions Account Executive complete a Pricing Review Checklist '
            + 'for a government/public-sector software deal. Provide a useful draft answer (1-3 sentences) for '
            + 'EVERY one of the 24 questions \u2014 do not leave any blank.\n'
            + 'For EVERY question, search the whole evidence pack: quote, opportunity, account, contacts, '
            + 'activity, emails, calls, Gong transcripts + briefs (Unknown scope included), Active Contracts '
            + '(Active ARR), LinkSquares agreements, RFP Details, and opportunity Files. Prefer the newest dated evidence.\n'
            + 'Map sources: ENTITY PROFILE for Q1 and Q7 \u2014 if this is a GRANT deal (Amplifund / Grants / '
            + 'GrantExec), Q1 must evaluate TOTAL GRANT FUNDS MANAGED (Annual Grants Revenue), not just the '
            + 'operating budget. EXISTING EUNA BOOK (Active ARR, contracts, '
            + 'LinkSquares, solution relationships) for Q3 \u2014 cite the actual Active ARR even when it is a '
            + 'different product than this deal; never say there is no ARR if a contract or agreement has a figure. '
            + 'COMPARABLE CUSTOMERS for Q6: same product only (never an adjacent product). Prefer exact vertical '
            + '+ 0.5x-2x operating budget; if none, fall back to Special Districts / County / Town, then widen '
            + 'to 0.25x-4x; prefer peers on the same ERP; name the product and include the Account URL. '
            + 'RFP Details + Files for Q2, '
            + 'Q10, Q11, Q19, Q23: if this is an RFP, a timeline is known ONLY when the RFP states it explicitly '
            + '(submission due, questions due, partner due, or a dated RFP file title); otherwise say the RFP '
            + 'does not state a timeline. QUOTES for Q21/Q24; Gong + emails + activity for Q4, Q5/Q17, Q9, Q16.\n'
            + 'For each question follow this order:\n'
            + '1) If Salesforce or Gong has direct evidence, answer from the newest of it.\n'
            + '2) If Salesforce + Gong still do not answer, search the web and cite the source URL. Do not '
            + 'guess silently.\n'
            + '3) If you must reason from entity type, size, or public-sector norms (no direct or web fact), '
            + 'PREFIX the answer with "INFERRED: ".\n'
            + '4) "[No data in Salesforce \u2014 AE to complete]" is almost never acceptable.\n'
            + 'Answer ALL 24. Every inferred answer MUST start with "INFERRED: ". Do not fabricate specific '
            + 'figures, quotes, or names that are not in the evidence or a cited web source.\n'
            + 'Keep every answer to 1-2 sentences (about 35 words max) so all 24 fit.\n'
            + 'Return ONLY a JSON object whose keys are Q1 through Q24 and whose values are strings. '
            + 'No markdown, no code fences, no commentary.\n\nQUESTIONS:\n' + qs + '\nCONTEXT:\n' + ctx;
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
        Blob docx = buildDocx(o, acct, director, answers);

        // Persist the responses so they can be reviewed again on the tool page.
        o.Pricing_Review_Answers__c = JSON.serialize(answers);
        update o;

        ContentVersion cv = new ContentVersion(
            Title = 'Pricing Review - ' + acct + ' - ' + Date.today().format(),
            PathOnClient = 'Euna_Pricing_Review_' + acct.replaceAll('[^a-zA-Z0-9]', '_') + '.docx',
            VersionData = docx
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

    // ---- .docx (WordprocessingML) generation ----
    private static final String INDIGO = '281978', ORANGE = 'FF6E14', RED = 'DC2626', GRAY = '64748B';
    private static final String CONTENT_TYPES = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        + '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        + '<Default Extension="xml" ContentType="application/xml"/>'
        + '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        + '</Types>';
    private static final String PKG_RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        + '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        + '</Relationships>';

    /** Builds the branded Euna Pricing Review Checklist as a real .docx package. */
    private static Blob buildDocx(Opportunity o, String acct, String director, Map<String, String> answers) {
        String rep = (o.Owner != null) ? o.Owner.Name : '';
        String body = wpara(wrun('EUNA SOLUTIONS\u00AE', true, ORANGE, 20), 40)
            + wpara(wrun('Pricing Review Checklist', true, INDIGO, 48), 40)
            + wpara(wrun('Complete before submitting for pricing approval \u2014 Internal Use Only', false, GRAY, 18), 200)
            + wheading('Opportunity Details')
            + wtbl(wdrow('Opportunity Name', o.Name) + wdrow('Date', Date.today().format())
                 + wdrow('Sales Rep', rep) + wdrow('Sales Director', director))
            + wpara(wrun('', false, null, 8), 120)
            + wheading('Review Questions')
            + wtbl(wqHeader() + wqRows(answers))
            + wpara(wrun('', false, null, 8), 120)
            + wheading('Sign-Off')
            + wtbl('<w:tr>' + wcell(wrun('Sales Director Approval', true, null, 20), 4800, null)
                 + wcell(wrun('No', false, null, 20), 4800, null) + '</w:tr>')
            + wpara(wrun('Euna Solutions\u00AE \u2014 Pricing Review Checklist \u2014 Internal Use Only', false, '9CA3AF', 16), 0);
        String docXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            + '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>' + body
            + '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1080" w:right="900" w:bottom="1080" w:left="900"/></w:sectPr>'
            + '</w:body></w:document>';
        return DocxZip.build(
            new List<String>{ '[Content_Types].xml', '_rels/.rels', 'word/document.xml' },
            new Map<String, Blob>{
                '[Content_Types].xml' => Blob.valueOf(CONTENT_TYPES),
                '_rels/.rels' => Blob.valueOf(PKG_RELS),
                'word/document.xml' => Blob.valueOf(docXml)
            });
    }
    private static String wqHeader() {
        return '<w:tr>' + wcell(wrun('#', true, 'FFFFFF', 18), 600, INDIGO)
            + wcell(wrun('Question / Review Item', true, 'FFFFFF', 18), 4000, INDIGO)
            + wcell(wrun('Notes / Response', true, 'FFFFFF', 18), 5000, INDIGO) + '</w:tr>';
    }
    private static String wqRows(Map<String, String> answers) {
        String rows = '';
        for (Integer i = 0; i < QUESTIONS.size(); i++) {
            String ans = answers.get('Q' + (i + 1));
            String ansRun = String.isBlank(ans) ? wrun('\u26A0 NOT ANSWERED', true, RED, 18) : wrun(ans, false, null, 18);
            rows += '<w:tr>' + wcell(wrun('Q' + (i + 1), true, null, 18), 600, null)
                + wcell(wrun(QUESTIONS[i], true, null, 18), 4000, null) + wcell(ansRun, 5000, null) + '</w:tr>';
        }
        return rows;
    }
    private static String wdrow(String k, String v) {
        return '<w:tr>' + wcell(wrun(k, true, 'FFFFFF', 20), 2880, INDIGO)
            + wcell(wrun(String.isBlank(v) ? '\u2014' : v, false, null, 20), 6720, null) + '</w:tr>';
    }
    private static String wrun(String t, Boolean bold, String color, Integer sz) {
        String rpr = '<w:rPr>' + (bold ? '<w:b/>' : '') + (color != null ? '<w:color w:val="' + color + '"/>' : '')
            + (sz != null ? '<w:sz w:val="' + sz + '"/>' : '') + '</w:rPr>';
        String bodyXml = '';
        List<String> lines = xesc(t).split('\n');
        for (Integer i = 0; i < lines.size(); i++) {
            if (i > 0) bodyXml += '<w:br/>';
            bodyXml += '<w:t xml:space="preserve">' + lines[i] + '</w:t>';
        }
        return '<w:r>' + rpr + bodyXml + '</w:r>';
    }
    private static String wpara(String runsXml, Integer spaceAfter) {
        return '<w:p><w:pPr><w:spacing w:after="' + spaceAfter + '"/></w:pPr>' + runsXml + '</w:p>';
    }
    private static String wheading(String t) { return wpara(wrun(t, true, INDIGO, 26), 80); }
    private static String wcell(String runsXml, Integer w, String fill) {
        return '<w:tc><w:tcPr><w:tcW w:w="' + w + '" w:type="dxa"/>'
            + (fill != null ? '<w:shd w:val="clear" w:fill="' + fill + '"/>' : '')
            + '<w:tcMar><w:top w:w="60" w:type="dxa"/><w:bottom w:w="60" w:type="dxa"/><w:left w:w="90" w:type="dxa"/><w:right w:w="90" w:type="dxa"/></w:tcMar>'
            + '</w:tcPr><w:p><w:pPr><w:spacing w:after="0"/></w:pPr>' + runsXml + '</w:p></w:tc>';
    }
    private static String wtbl(String rowsXml) {
        return '<w:tbl><w:tblPr><w:tblW w:w="9600" w:type="dxa"/><w:tblBorders>'
            + '<w:top w:val="single" w:sz="4" w:color="D1D5DB"/><w:left w:val="single" w:sz="4" w:color="D1D5DB"/>'
            + '<w:bottom w:val="single" w:sz="4" w:color="D1D5DB"/><w:right w:val="single" w:sz="4" w:color="D1D5DB"/>'
            + '<w:insideH w:val="single" w:sz="4" w:color="D1D5DB"/><w:insideV w:val="single" w:sz="4" w:color="D1D5DB"/>'
            + '</w:tblBorders></w:tblPr>' + rowsXml + '</w:tbl>';
    }
    private static String xesc(String s) {
        return s == null ? '' : s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;');
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
