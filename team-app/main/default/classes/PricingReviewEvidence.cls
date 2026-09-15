/**
 * Holistic, newest-first evidence pack for Pricing Review drafts.
 * Each question is answered from quote, opportunity, account, contacts,
 * activity, emails, calls, and Gong transcripts/briefs before inferring.
 */
public with sharing class PricingReviewEvidence {

    @TestVisible static final Integer ACTIVITY_LIMIT = 25;
    @TestVisible static final Integer EMAIL_LIMIT = 12;
    @TestVisible static final Integer EVENT_LIMIT = 15;
    @TestVisible static final Integer GONG_SCAN = 20;
    @TestVisible static final Integer GONG_KEEP = 8;
    @TestVisible static final Integer COMP_SCAN = 40;
    @TestVisible static final Integer COMP_KEEP = 8;
    @TestVisible static final Integer CONTEXT_CAP = 48000;

    /**
     * Full pack used by the 24-question draft. Newest dated evidence first
     * inside each section and in the opening digest.
     */
    public static String build(Opportunity o) {
        if (o == null) return '';
        List<DatedLine> newest = new List<DatedLine>();
        String s = header(o);
        s += profile(o);
        s += comparables(o);
        s += quotes(o);
        s += relationships(o);
        s += contacts(o);
        s += activity(o, newest);
        s += emails(o, newest);
        s += calls(o, newest);
        s += gong(o, newest);
        newest.sort();
        String digest = newestDigest(newest);
        return clip(digest + s, CONTEXT_CAP);
    }

    /**
     * Per-question pack: same holistic pull, with matching lines hoisted so
     * Try again / Expand reads the latest relevant evidence first.
     */
    public static String buildForQuestion(Opportunity o, Integer questionNum, String question) {
        String full = build(o);
        String head = 'FOCUS QUESTION Q' + questionNum + ': ' + safe(question) + '\n'
            + 'Search quote, opportunity, account, contacts, all activity, emails, calls, '
            + 'and Gong transcripts/briefs (Unknown scope included). Newest evidence wins.\n';
        List<String> keys = questionKeywords(question);
        if (!keys.isEmpty()) {
            List<String> hits = new List<String>();
            for (String line : full.split('\n')) {
                if (String.isBlank(line) || hits.size() >= 20) continue;
                String low = line.toLowerCase();
                for (String k : keys) {
                    if (low.contains(k)) { hits.add(line.trim()); break; }
                }
            }
            if (!hits.isEmpty()) {
                head += '\nQuestion-focused evidence (from the newest-first pack):\n';
                for (String h : hits) head += '  ' + h + '\n';
            }
        }
        return clip(head + '\nFULL EVIDENCE PACK:\n' + full, CONTEXT_CAP);
    }

    @TestVisible
    static Boolean budgetSameOrder(Decimal prospect, Decimal comparable) {
        if (prospect == null || comparable == null || prospect <= 0 || comparable <= 0) return false;
        return comparable >= (prospect / 4) && comparable <= (prospect * 4);
    }

    @TestVisible
    static Boolean isComparable(String dealProduct, Decimal dealBudget, String contractProduct, Decimal contractBudget) {
        if (!productMatches(dealProduct, contractProduct)) return false;
        if (dealBudget != null && !budgetSameOrder(dealBudget, contractBudget)) return false;
        return true;
    }

    @TestVisible
    static Boolean productMatches(String dealProduct, String contractProduct) {
        if (String.isBlank(dealProduct) || String.isBlank(contractProduct)) return false;
        String a = dealProduct.trim().toLowerCase();
        String b = contractProduct.trim().toLowerCase();
        return a == b || b.contains(a);
    }

    @TestVisible
    static String accountUrl(Id accountId) {
        if (accountId == null) return '';
        return URL.getOrgDomainUrl().toExternalForm() + '/lightning/r/Account/' + accountId + '/view';
    }

    @TestVisible
    static String dealProduct(Opportunity o) {
        if (o == null) return '';
        if (String.isNotBlank(o.EUNA_Solution__c)) return o.EUNA_Solution__c;
        if (o.Euna_Solutions_Lookup__r != null && String.isNotBlank(o.Euna_Solutions_Lookup__r.Name)) {
            return o.Euna_Solutions_Lookup__r.Name;
        }
        return '';
    }

    @TestVisible
    static Decimal dealBudget(Opportunity o) {
        if (o == null || o.Account == null) return null;
        if (o.Account.AnnualRevenue != null && o.Account.AnnualRevenue > 0) return o.Account.AnnualRevenue;
        if (o.Account.Total_Budget_bf__c != null && o.Account.Total_Budget_bf__c > 0) return o.Account.Total_Budget_bf__c;
        return null;
    }

    @TestVisible
    static List<String> questionKeywords(String question) {
        Set<String> stop = new Set<String>{
            'this', 'that', 'they', 'them', 'have', 'been', 'from', 'with', 'what', 'when',
            'does', 'their', 'than', 'into', 'over', 'much', 'how', 'the', 'and', 'for',
            'are', 'was', 'who', 'any', 'our', 'has', 'did', 'not', 'you', 'your'
        };
        List<String> out = new List<String>();
        if (String.isBlank(question)) return out;
        for (String w : question.toLowerCase().replaceAll('[^a-z0-9 ]', ' ').split('\\s+')) {
            if (w.length() >= 4 && !stop.contains(w)) out.add(w);
        }
        return out;
    }

    // ---- sections ----

    private static String header(Opportunity o) {
        String acct = (o.Account != null) ? o.Account.Name : o.Name;
        return 'Opportunity: ' + o.Name + '\nAccount: ' + acct
            + (o.AccountId != null ? '\nAccount URL: ' + accountUrl(o.AccountId) : '')
            + '\nLocation: ' + join(new List<String>{
                safe(o.Account != null ? o.Account.BillingCity : null),
                safe(o.Account != null ? o.Account.BillingState : null)
            }, ', ')
            + '\nOwner (AE): ' + (o.Owner != null ? o.Owner.Name : '')
            + '\nSales Director: ' + safe(o.Sales_Director__c)
            + '\nStage: ' + safe(o.StageName) + '\nType: ' + safe(o.Type)
            + '\nForecast Category: ' + safe(o.ForecastCategoryName)
            + '\nClose Date: ' + (o.CloseDate != null ? o.CloseDate.format() : '')
            + '\nAmount: ' + (o.Amount != null ? String.valueOf(o.Amount) : '')
            + '\nARR (USD): ' + (o.ARR_Opportunity_Amount_USD_Num__c != null
                ? String.valueOf(o.ARR_Opportunity_Amount_USD_Num__c) : '')
            + '\nEuna Solution / product type: ' + dealProduct(o)
            + '\nSales Segment: ' + safe(o.Sales_Segment__c)
            + '\nLead Source: ' + safe(o.LeadSource)
            + '\nKnown competitors (opp field): ' + safe(o.EUNA_Competitors__c)
            + '\nNext Step: ' + safe(o.NextStep)
            + '\nDescription: ' + clip(safe(o.Description), 1500) + '\n';
    }

    private static String profile(Opportunity o) {
        if (o.Account == null) return '';
        return '\nEntity profile (from the Account record \u2014 authoritative for Q1):\n'
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

    private static String comparables(Opportunity o) {
        String product = dealProduct(o);
        Decimal budget = dealBudget(o);
        String vertical = (o.Account != null) ? o.Account.Industry : null;
        String s = '\nComparable Euna customers (must match vertical + product type + annual-budget order of magnitude):\n'
            + '  Filter: vertical=' + safe(vertical) + ' product=' + safe(product)
            + ' annual-budget=' + fmtCur(budget) + ' (band 0.25x-4x)\n';
        if (o.Account == null || String.isBlank(vertical) || String.isBlank(product)) {
            return s + '  (skipped \u2014 need vertical and product type on the deal)\n';
        }
        List<Contract> rows = [
            SELECT AccountId, Account.Name, Account.Industry, Account.AnnualRevenue, Account.Student_Count__c,
                   ARR_Rollup__c, EUNA_Solution_Name_Formula__c, EUNA_Solution_Lookup__r.Name
            FROM Contract
            WHERE Status = 'Activated' AND ARR_Rollup__c > 0
              AND Account.Industry = :vertical AND AccountId != :o.AccountId
              AND Account.RecordType.DeveloperName = 'Customer_EUNA'
            ORDER BY ARR_Rollup__c DESC
            LIMIT :COMP_SCAN
        ];
        Integer shown = 0;
        for (Contract c : rows) {
            String cProd = contractProduct(c);
            Decimal cBudget = (c.Account != null) ? c.Account.AnnualRevenue : null;
            if (!isComparable(product, budget, cProd, cBudget)) continue;
            s += '  - ' + safe(c.Account != null ? c.Account.Name : '')
               + ' | product=' + safe(cProd)
               + ' | ARR=' + fmtCur(c.ARR_Rollup__c)
               + ' | annual budget=' + fmtCur(cBudget)
               + ' | students=' + num(c.Account != null ? c.Account.Student_Count__c : null)
               + ' | Account: ' + accountUrl(c.AccountId) + '\n';
            shown++;
            if (shown >= COMP_KEEP) break;
        }
        if (shown == 0) {
            s += '  (none matched vertical + product type + annual-budget order of magnitude)\n';
        }
        return s;
    }

    @TestVisible
    static String contractProduct(Contract c) {
        if (c == null) return '';
        if (String.isNotBlank(c.EUNA_Solution_Name_Formula__c)) return c.EUNA_Solution_Name_Formula__c;
        if (c.EUNA_Solution_Lookup__r != null) return safe(c.EUNA_Solution_Lookup__r.Name);
        return '';
    }

    private static String quotes(Opportunity o) {
        String s = '\nQuotes (newest first \u2014 line items, modules, amounts):\n';
        List<Quote> qs = [
            SELECT Name, Status, GrandTotal, Total_Software_Contract_Value__c, CreatedDate, ExpirationDate
            FROM Quote WHERE OpportunityId = :o.Id
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];
        if (qs.isEmpty()) s += '  (no quotes)\n';
        for (Quote q : qs) {
            s += '  - ' + dt(q.CreatedDate) + ' ' + safe(q.Name) + ' | status=' + safe(q.Status)
               + ' | grand=' + fmtCur(q.GrandTotal)
               + ' | software TCV=' + fmtCur(q.Total_Software_Contract_Value__c)
               + ' | expires=' + (q.ExpirationDate != null ? q.ExpirationDate.format() : '') + '\n';
        }
        s += 'Quoted products / modules (newest quote first):\n';
        Set<String> seen = new Set<String>();
        for (QuoteLineItem qli : [
            SELECT Product2.Name, Product_Family__c, Product_Name__c, Quantity, UnitPrice, TotalPrice,
                   Quote.Name, Quote.CreatedDate, Quote.Status, Quote_Phase__r.Name
            FROM QuoteLineItem WHERE Quote.OpportunityId = :o.Id
            ORDER BY Quote.CreatedDate DESC, TotalPrice DESC
            LIMIT 40
        ]) {
            Decimal qty = (qli.Quantity == null) ? null : Decimal.valueOf(String.valueOf(qli.Quantity));
            Decimal unit = (qli.UnitPrice == null) ? null : Decimal.valueOf(String.valueOf(qli.UnitPrice));
            Decimal tot = (qli.TotalPrice == null) ? null : Decimal.valueOf(String.valueOf(qli.TotalPrice));
            String prod = qli.Product2 != null ? qli.Product2.Name : qli.Product_Name__c;
            String line = formatQli(
                dt(qli.Quote != null ? qli.Quote.CreatedDate : null),
                prod,
                qli.Product_Family__c,
                qli.Quote_Phase__r != null ? qli.Quote_Phase__r.Name : '',
                qty, unit, tot,
                qli.Quote != null ? qli.Quote.Name : '');
            if (seen.add(line)) s += '  - ' + line + '\n';
        }
        if (seen.isEmpty()) s += '  (no quote lines)\n';
        return s;
    }

    private static String relationships(Opportunity o) {
        if (o.AccountId == null) return '\nExisting Euna relationships: none found\n';
        List<String> rels = new List<String>();
        for (Account_Solution_Relationship__c r : [
            SELECT Euna_Solution__r.Name, Status__c, First_Solution_Contract_Date__c
            FROM Account_Solution_Relationship__c
            WHERE Account__c = :o.AccountId AND Status__c IN ('Customer', 'Customer - Child')
            LIMIT 10
        ]) {
            rels.add(safe(r.Euna_Solution__r != null ? r.Euna_Solution__r.Name : '')
                + ' (' + safe(r.Status__c) + ')'
                + (r.First_Solution_Contract_Date__c != null
                    ? ' purchased ' + r.First_Solution_Contract_Date__c.format() : ''));
        }
        return '\nExisting Euna relationships: ' + (rels.isEmpty() ? 'none found' : String.join(rels, '; ')) + '\n';
    }

    private static String contacts(Opportunity o) {
        String s = '\nContacts (opportunity contact roles):\n';
        List<OpportunityContactRole> roles = [
            SELECT Role, IsPrimary, Contact.Name, Contact.Title, Contact.Email
            FROM OpportunityContactRole WHERE OpportunityId = :o.Id
            LIMIT 15
        ];
        if (roles.isEmpty()) return s + '  (none)\n';
        for (OpportunityContactRole r : roles) {
            s += '  - ' + safe(r.Contact != null ? r.Contact.Name : '')
               + ' | title=' + safe(r.Contact != null ? r.Contact.Title : '')
               + ' | role=' + safe(r.Role) + (r.IsPrimary ? ' [primary]' : '')
               + ' | email=' + safe(r.Contact != null ? r.Contact.Email : '') + '\n';
        }
        return s;
    }

    private static String activity(Opportunity o, List<DatedLine> newest) {
        Set<Id> whatIds = whatIds(o);
        String s = '\nAll activity (Tasks, newest first):\n';
        List<Task> tasks = [
            SELECT Subject, Description, ActivityDate, Type, TaskSubtype, CreatedDate
            FROM Task WHERE WhatId IN :whatIds
            ORDER BY CreatedDate DESC
            LIMIT :ACTIVITY_LIMIT
        ];
        if (tasks.isEmpty()) s += '  (none)\n';
        for (Task t : tasks) {
            String kind = String.isNotBlank(t.TaskSubtype) ? t.TaskSubtype : safe(t.Type);
            String line = dt(t.CreatedDate) + ' [' + kind + '] ' + safe(t.Subject)
                + ' \u2014 ' + clip(safe(t.Description), 220);
            s += '  - ' + line + '\n';
            newest.add(new DatedLine(t.CreatedDate, 'Task ' + line));
        }
        s += '\nMeetings / events (newest first):\n';
        List<Event> evs = [
            SELECT Subject, Description, Type, StartDateTime, CreatedDate
            FROM Event WHERE WhatId IN :whatIds
            ORDER BY StartDateTime DESC NULLS LAST
            LIMIT :EVENT_LIMIT
        ];
        if (evs.isEmpty()) s += '  (none)\n';
        for (Event e : evs) {
            Datetime whenAt = e.StartDateTime != null ? e.StartDateTime : e.CreatedDate;
            String line = dt(whenAt) + ' [' + safe(e.Type) + '] ' + safe(e.Subject)
                + ' \u2014 ' + clip(safe(e.Description), 220);
            s += '  - ' + line + '\n';
            newest.add(new DatedLine(whenAt, 'Event ' + line));
        }
        return s;
    }

    private static String emails(Opportunity o, List<DatedLine> newest) {
        String s = '\nEmails (newest first):\n';
        Set<Id> related = whatIds(o);
        List<EmailMessage> msgs = [
            SELECT Subject, MessageDate, Incoming, FromAddress, ToAddress, TextBody, CreatedDate
            FROM EmailMessage
            WHERE RelatedToId IN :related
            ORDER BY MessageDate DESC NULLS LAST
            LIMIT :EMAIL_LIMIT
        ];
        if (msgs.isEmpty()) return s + '  (none)\n';
        for (EmailMessage m : msgs) {
            Datetime whenAt = m.MessageDate != null ? m.MessageDate : m.CreatedDate;
            String dir = m.Incoming ? 'IN' : 'OUT';
            String line = dt(whenAt) + ' [' + dir + '] ' + safe(m.Subject)
                + ' from=' + safe(m.FromAddress) + ' to=' + clip(safe(m.ToAddress), 80)
                + ' \u2014 ' + clip(safe(m.TextBody), 400);
            s += '  - ' + line + '\n';
            newest.add(new DatedLine(whenAt, 'Email ' + line));
        }
        return s;
    }

    private static String calls(Opportunity o, List<DatedLine> newest) {
        Set<Id> whatIds = whatIds(o);
        String s = '\nCalls (Salesforce Task/Event, newest first \u2014 Gong is in the next section):\n';
        Integer n = 0;
        for (Task t : [
            SELECT Subject, Description, Type, TaskSubtype, CreatedDate, ActivityDate
            FROM Task
            WHERE WhatId IN :whatIds AND (TaskSubtype = 'Call' OR Type = 'Call')
            ORDER BY CreatedDate DESC
            LIMIT 10
        ]) {
            String line = dt(t.CreatedDate) + ' [Call] ' + safe(t.Subject)
                + ' \u2014 ' + clip(safe(t.Description), 220);
            s += '  - ' + line + '\n';
            newest.add(new DatedLine(t.CreatedDate, 'Call ' + line));
            n++;
        }
        for (Event e : [
            SELECT Subject, Description, Type, StartDateTime, CreatedDate
            FROM Event
            WHERE WhatId IN :whatIds AND Type IN ('Call', 'Meeting')
            ORDER BY StartDateTime DESC NULLS LAST
            LIMIT 10
        ]) {
            Datetime whenAt = e.StartDateTime != null ? e.StartDateTime : e.CreatedDate;
            String line = dt(whenAt) + ' [' + safe(e.Type) + '] ' + safe(e.Subject)
                + ' \u2014 ' + clip(safe(e.Description), 220);
            s += '  - ' + line + '\n';
            newest.add(new DatedLine(whenAt, 'Call/Meeting ' + line));
            n++;
        }
        if (n == 0) s += '  (none)\n';
        return s;
    }

    private static String gong(Opportunity o, List<DatedLine> newest) {
        String s = '\nGong meetings (transcripts + briefs; Unknown scope included; Internal/private excluded; newest first):\n';
        List<Gong__Gong_Call__c> scanned = [
            SELECT Gong__Title__c, Gong__Call_Start__c, Gong__Call_Brief__c, Gong__Pricing_Duration__c,
                   Gong__Talk_Time_Them__c, Gong_Transcript__c, Gong__Scope__c, Gong__Call_Key_Points__c,
                   Gong__Call_Highlights_Next_Steps__c, Gong__Primary_Opportunity__c
            FROM Gong__Gong_Call__c
            WHERE Gong__Is_Private__c = false
              AND Gong__Scope__c != 'Internal'
              AND (Gong__Primary_Opportunity__c = :o.Id OR Gong__Primary_Account__c = :o.AccountId)
            ORDER BY Gong__Call_Start__c DESC NULLS LAST
            LIMIT :GONG_SCAN
        ];
        List<Gong__Gong_Call__c> keep = pickGong(scanned);
        if (keep.isEmpty()) return s + '  (none)\n';
        Integer idx = 0;
        for (Gong__Gong_Call__c c : keep) {
            Integer tClip = (idx == 0) ? 5000 : (idx == 1 ? 3500 : 1800);
            String body = '';
            if (String.isNotBlank(c.Gong__Call_Brief__c)) body += 'Brief: ' + clip(safe(c.Gong__Call_Brief__c), 1200) + '\n    ';
            if (String.isNotBlank(c.Gong__Call_Key_Points__c)) body += 'Key points: ' + clip(safe(c.Gong__Call_Key_Points__c), 600) + '\n    ';
            if (String.isNotBlank(c.Gong__Call_Highlights_Next_Steps__c)) {
                body += 'Next steps: ' + clip(safe(c.Gong__Call_Highlights_Next_Steps__c), 400) + '\n    ';
            }
            if (String.isNotBlank(c.Gong_Transcript__c)) body += 'Transcript: ' + clip(c.Gong_Transcript__c, tClip);
            if (String.isBlank(body)) body = '(no brief or transcript synced yet)';
            String talk = (c.Gong__Talk_Time_Them__c != null) ? ' prospect-talk-time=' + c.Gong__Talk_Time_Them__c : '';
            String scope = String.isNotBlank(c.Gong__Scope__c) ? ' scope=' + c.Gong__Scope__c : '';
            String line = dt(c.Gong__Call_Start__c) + ' ' + safe(c.Gong__Title__c)
                + (c.Gong__Pricing_Duration__c != null && c.Gong__Pricing_Duration__c > 0 ? ' [pricing discussed]' : '')
                + talk + scope;
            s += '  - ' + line + '\n    ' + body + '\n';
            newest.add(new DatedLine(c.Gong__Call_Start__c, 'Gong ' + line));
            idx++;
        }
        return s;
    }

    @TestVisible
    static String formatQli(String created, String prod, String family, String phase,
            Decimal qty, Decimal unit, Decimal tot, String quoteName) {
        return created + ' ' + safe(prod)
            + ' | family=' + safe(family)
            + ' | module/phase=' + safe(phase)
            + ' | qty=' + num(qty) + ' | unit=' + fmtCur(unit) + ' | total=' + fmtCur(tot)
            + ' | quote=' + safe(quoteName);
    }

    @TestVisible
    static List<Gong__Gong_Call__c> pickGong(List<Gong__Gong_Call__c> scanned) {
        List<Gong__Gong_Call__c> keep = new List<Gong__Gong_Call__c>();
        if (scanned == null) return keep;
        Integer i = 0;
        for (Gong__Gong_Call__c c : scanned) {
            Boolean rich = isRich(c);
            if (rich || keep.size() < 3) keep.add(c);
            if (keep.size() >= GONG_KEEP) break;
            i++;
        }
        return keep;
    }

    @TestVisible
    static Boolean isRich(Gong__Gong_Call__c c) {
        if (c == null) return false;
        return String.isNotBlank(c.Gong__Call_Brief__c)
            || String.isNotBlank(c.Gong_Transcript__c)
            || String.isNotBlank(c.Gong__Call_Key_Points__c);
    }

    private static String newestDigest(List<DatedLine> newest) {
        if (newest == null || newest.isEmpty()) return '';
        String s = 'Newest evidence first (mixed sources):\n';
        Integer n = 0;
        for (DatedLine d : newest) {
            s += '  - ' + d.line + '\n';
            n++;
            if (n >= 12) break;
        }
        return s + '\n';
    }

    private static Set<Id> whatIds(Opportunity o) {
        Set<Id> ids = new Set<Id>{ o.Id };
        if (o.AccountId != null) ids.add(o.AccountId);
        return ids;
    }

    private class DatedLine implements Comparable {
        Long ts;
        String line;
        DatedLine(Datetime dt, String line) {
            this.ts = dt == null ? 0 : dt.getTime();
            this.line = line;
        }
        public Integer compareTo(Object other) {
            DatedLine oth = (DatedLine) other;
            if (ts == oth.ts) return 0;
            return ts > oth.ts ? -1 : 1;
        }
    }

    private static String dt(Datetime d) { return d == null ? '' : d.date().format(); }
    private static String safe(String s) { return s == null ? '' : s; }
    private static String num(Decimal d) { return d == null ? '' : String.valueOf(d.setScale(0)); }
    private static String fmtCur(Decimal d) { return d == null ? '' : '$' + d.setScale(0).format(); }
    private static String clip(String s, Integer n) {
        return (s != null && s.length() > n) ? s.substring(0, n) + '\u2026' : s;
    }
    private static String join(List<String> parts, String sep) {
        List<String> keep = new List<String>();
        for (String p : parts) if (String.isNotBlank(p)) keep.add(p);
        return String.join(keep, sep);
    }
}
