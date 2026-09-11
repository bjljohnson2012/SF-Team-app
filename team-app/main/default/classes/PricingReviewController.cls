/**
 * Sales Tools > Pricing Review View Checklist Tool.
 * Implements the Euna "pricing-review-checklist" skill in-platform: for open
 * deals >= $30K ARR, the AE answers the 24-question checklist, and the tool
 * generates a branded Euna Word document and attaches it to the opportunity's
 * Files. "Done" = a Pricing Review file exists on the record.
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
                   ARR_Opportunity_Amount_USD_Num__c
            FROM Opportunity
            WHERE IsClosed = false AND OwnerId IN :owners
              AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
              AND ARR_Opportunity_Amount_USD_Num__c >= :REVIEW_FLOOR
            ORDER BY ARR_Opportunity_Amount_USD_Num__c DESC
            LIMIT 500
        ];
        Set<Id> done = reviewedOppIds(new Map<Id, Opportunity>(opps).keySet());
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
            r.director = DEFAULT_DIRECTOR;
            r.reviewDone = done.contains(o.Id);
            out.add(r);
        }
        return out;
    }

    /** Opportunity ids that already carry a Pricing Review file. */
    public static Set<Id> reviewedOppIds(Set<Id> oppIds) {
        Set<Id> done = new Set<Id>();
        if (oppIds.isEmpty()) return done;
        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId FROM ContentDocumentLink
            WHERE LinkedEntityId IN :oppIds AND ContentDocument.Title LIKE 'Pricing Review%'
        ]) { done.add(cdl.LinkedEntityId); }
        return done;
    }

    /** Builds and attaches the branded Euna Pricing Review Checklist. answers = { "Q1": "...", ... "Q24": "..." }. */
    @AuraEnabled
    public static Id createReview(Id opportunityId, Map<String, String> answers) {
        if (opportunityId == null) throw new AuraHandledException('An opportunity is required.');
        if (answers == null) answers = new Map<String, String>();
        List<Opportunity> opps = [
            SELECT Id, Name, Account.Name, Owner.Name, StageName, CloseDate
            FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];
        if (opps.isEmpty()) throw new AuraHandledException('Opportunity not found or not accessible.');
        Opportunity o = opps[0];
        String acct = (o.Account != null) ? o.Account.Name : o.Name;
        String html = buildDoc(o, acct, answers);

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

    private static String buildDoc(Opportunity o, String acct, Map<String, String> answers) {
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
            + drow('Sales Rep', rep) + drow('Sales Director', DEFAULT_DIRECTOR) + '</table>'
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
}
