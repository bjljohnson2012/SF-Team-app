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
    @TestVisible static final Integer COMP_SCAN = 80;
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
        s += existingBook(o);
        s += rfpAndFiles(o);
        s += comparables(o);
        s += quotes(o);
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
            + 'and Gong transcripts/briefs (Unknown scope included), Active Contracts / Active ARR, '
            + 'LinkSquares agreements, RFP Details, and opportunity Files. Newest evidence wins.\n';
        List<String> keys = questionKeywords(question);
        keys.addAll(extraKeywords(questionNum));
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
        return comparable >= (prospect * 0.5) && comparable <= (prospect * 2);
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
    static Boolean isGrantDeal(Opportunity o) {
        String p = dealProduct(o).toLowerCase();
        return p.contains('grant') || p.contains('amplifund');
    }

    @TestVisible
    static Decimal grantFunds(Opportunity o) {
        if (o == null || o.Account == null) return null;
        if (o.Account.Grant_Funds_Managed__c != null && o.Account.Grant_Funds_Managed__c > 0) {
            return o.Account.Grant_Funds_Managed__c;
        }
        return null;
    }

    @TestVisible
    static Boolean budgetWide(Decimal prospect, Decimal comparable) {
        if (prospect == null || comparable == null || prospect <= 0 || comparable <= 0) return false;
        return comparable >= (prospect * 0.25) && comparable <= (prospect * 4);
    }

    @TestVisible
    static Boolean hasErp(String erp) {
        if (String.isBlank(erp)) return false;
        String e = erp.trim().toLowerCase();
        return e != 'n/a' && e != 'na' && e != 'other' && e != 'none' && e != 'unknown';
    }

    @TestVisible
    static Boolean erpMatches(String dealErp, String peerErp) {
        return hasErp(dealErp) && hasErp(peerErp) && dealErp.trim().equalsIgnoreCase(peerErp.trim());
    }

    /** Fallback entity types: Special Districts, or a county / town / city / village / borough. */
    @TestVisible
    static Boolean isNeighborEntity(String industry, String subVertical) {
        if (String.isNotBlank(industry) && industry.trim().equalsIgnoreCase('Special Districts')) return true;
        if (String.isBlank(subVertical)) return false;
        String s = subVertical.trim().toLowerCase();
        return s == 'county' || s == 'town' || s == 'city' || s == 'village' || s == 'borough';
    }

    /**
     * 1 = same vertical + product + 0.5x-2x
     * 2 = same product + special district/county/town + 0.5x-2x
     * 3 = same product + neighbor + 0.25x-4x
     * 4 = same product + any vertical + 0.25x-4x
     * 0 = reject (wrong product, or budget still too far)
     */
    @TestVisible
    static Integer comparableTier(String dealVertical, String dealProduct, Decimal dealBudget,
            String peerVertical, String peerSub, String peerProduct, Decimal peerBudget) {
        if (!productMatches(dealProduct, peerProduct)) return 0;
        Boolean sameVert = String.isNotBlank(dealVertical) && dealVertical == peerVertical;
        Boolean neighbor = isNeighborEntity(peerVertical, peerSub);
        Boolean tight = (dealBudget == null) || budgetSameOrder(dealBudget, peerBudget);
        Boolean wide = (dealBudget == null) || budgetWide(dealBudget, peerBudget);
        if (sameVert && tight) return 1;
        if (neighbor && tight) return 2;
        if ((sameVert || neighbor) && wide) return 3;
        if (wide) return 4;
        return 0;
    }

    @TestVisible
    static String tierLabel(Integer tier) {
        if (tier == 1) return 'exact: vertical + product + 0.5x-2x';
        if (tier == 2) return 'fallback: same product + special district/county/town + 0.5x-2x';
        if (tier == 3) return 'fallback: same product + neighbor + 0.25x-4x budget';
        if (tier == 4) return 'fallback: same product + any vertical + 0.25x-4x budget';
        return 'rejected';
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
            if ((w.length() >= 4 || w == 'arr' || w == 'rfp') && !stop.contains(w)) out.add(w);
        }
        return out;
    }

    /** Domain terms the question text itself often omits (ARR, RFP due dates, budget band). */
    @TestVisible
    static List<String> extraKeywords(Integer questionNum) {
        if (questionNum == 3) {
            return new List<String>{
                'active arr', 'existing euna book', 'linksquares', 'active / arr-bearing',
                'solution relationships'
            };
        }
        if (questionNum == 2 || questionNum == 10 || questionNum == 11
                || questionNum == 19 || questionNum == 23) {
            return new List<String>{
                'rfp', 'submission due', 'questions due', 'partner due',
                'files on the opportunity', 'has rfp attached'
            };
        }
        if (questionNum == 1) {
            return new List<String>{
                'grant funds', 'annual grants', 'operating budget', 'current erp', 'entity profile'
            };
        }
        if (questionNum == 6) {
            return new List<String>{
                'comparable', 'operating-budget', '0.5x-2x', 'active arr', 'fallback', 'erp'
            };
        }
        return new List<String>();
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
        Boolean grant = isGrantDeal(o);
        String s = '\nEntity profile (from the Account record \u2014 authoritative for Q1):\n'
            + '  Vertical / Sub-Vertical: ' + safe(o.Account.Industry) + ' / ' + safe(o.Account.Sub_Vertical__c) + '\n'
            + '  Latest Operating Budget: ' + fmtCur(o.Account.AnnualRevenue) + '\n'
            + '  Total Budget: ' + fmtCur(o.Account.Total_Budget_bf__c) + '\n'
            + '  Grant funds managed (Annual Grants Revenue): ' + fmtCur(o.Account.Grant_Funds_Managed__c) + '\n'
            + '  Grant funds sources: ' + clip(safe(o.Account.Grant_Funds_Managed_Sources__c), 400) + '\n'
            + '  Grant funds rationale: ' + clip(safe(o.Account.Grant_Funds_Managed_Rationale__c), 400) + '\n'
            + '  Government Grants: ' + fmtCur(o.Account.Government_Grants__c) + '\n'
            + '  Amplifund annual grant revenue band: ' + safe(o.Account.Annual_Grant_Revenue_Amplifund__c) + '\n'
            + '  Operating Budget Year: ' + num(o.Account.Operating_Budget_Year__c) + '\n'
            + '  Fiscal Year Start Month: ' + safe(o.Account.Fiscal_Year_Start_Month__c) + '\n'
            + '  Student Count: ' + num(o.Account.Student_Count__c) + '\n'
            + '  Population Served: ' + num(o.Account.Total_Population_bf__c) + '\n'
            + '  Employees: ' + num(o.Account.NumberOfEmployees) + '\n'
            + '  Current Budgeting System: ' + safe(o.Account.Current_Budgeting_system__c) + '\n'
            + '  Current ERP system: ' + safe(o.Account.Current_ERP_system__c) + '\n'
            + '  Current Grants Management System: ' + safe(o.Account.Current_Grants_Management_System__c) + '\n'
            + '  Recent Budget Trends: ' + clip(safe(o.Account.Recent_Budget_Trends__c), 1400) + '\n';
        if (grant) {
            s += '  GRANT DEAL: For Q1, evaluate TOTAL GRANT FUNDS MANAGED by the agency '
                + '(Grant funds managed / Annual Grants Revenue above), not just the operating budget. '
                + 'Still mention operating budget as context.\n';
        }
        return s;
    }

    private static String comparables(Opportunity o) {
        String product = dealProduct(o);
        Decimal budget = dealBudget(o);
        String vertical = (o.Account != null) ? o.Account.Industry : null;
        String dealErp = (o.Account != null) ? o.Account.Current_ERP_system__c : null;
        String s = '\nComparable Euna customers (same product only \u2014 never an adjacent product):\n'
            + '  Prefer exact: same vertical + product + operating-budget 0.5x-2x.\n'
            + '  Fallback (same product only): expand to Special Districts / County / Town / City, '
            + 'then widen the operating-budget band to 0.25x-4x. Prefer peers on the same ERP.\n'
            + '  Filter: vertical=' + safe(vertical) + ' product=' + safe(product)
            + ' operating-budget=' + fmtCur(budget)
            + ' ERP=' + safe(dealErp)
            + (isGrantDeal(o) ? ' grant-funds=' + fmtCur(grantFunds(o)) : '') + '\n';
        if (o.Account == null || String.isBlank(product)) {
            return s + '  (skipped \u2014 need product type on the deal)\n';
        }
        List<Contract> rows = [
            SELECT AccountId, Account.Name, Account.Industry, Account.Sub_Vertical__c,
                   Account.AnnualRevenue, Account.Grant_Funds_Managed__c, Account.Current_ERP_system__c,
                   ARR_Rollup__c, Active_ARR__c, Active_ARR_Rollup__c,
                   EUNA_Solution_Name_Formula__c, EUNA_Solution_Lookup__r.Name
            FROM Contract
            WHERE Status = 'Activated'
              AND AccountId != :o.AccountId
              AND Account.RecordType.DeveloperName = 'Customer_EUNA'
              AND (ARR_Rollup__c > 0 OR Active_ARR__c > 0 OR Active_ARR_Rollup__c > 0)
            LIMIT :COMP_SCAN
        ];
        List<CompRow> ranked = new List<CompRow>();
        Integer bestTier = 99;
        for (Contract c : rows) {
            String cProd = contractProduct(c);
            String cVert = (c.Account != null) ? c.Account.Industry : null;
            String cSub = (c.Account != null) ? c.Account.Sub_Vertical__c : null;
            Decimal cBudget = (c.Account != null) ? c.Account.AnnualRevenue : null;
            Integer tier = comparableTier(vertical, product, budget, cVert, cSub, cProd, cBudget);
            if (tier == 0) continue;
            if (tier < bestTier) bestTier = tier;
            String cErp = (c.Account != null) ? c.Account.Current_ERP_system__c : null;
            Decimal cGrant = (c.Account != null) ? c.Account.Grant_Funds_Managed__c : null;
            ranked.add(new CompRow(c, cProd, cBudget, budget, effectiveArr(c), tier, cErp,
                erpMatches(dealErp, cErp), cGrant, cVert, cSub));
        }
        ranked.sort();
        Integer shown = 0;
        Integer shownExact = 0;
        for (CompRow row : ranked) {
            if (bestTier == 1 && row.tier > 1 && shownExact >= 3) break;
            s += '  - ' + row.line() + ' | Account: ' + accountUrl(row.accountId) + '\n';
            shown++;
            if (row.tier == 1) shownExact++;
            if (shown >= COMP_KEEP) break;
        }
        if (shown == 0) {
            s += '  (none matched this product, even after special-district/county/town and a wider budget band)\n';
        } else if (bestTier > 1) {
            s += '  Note: no exact vertical + 0.5x-2x peers; showing same-product fallbacks ('
                + tierLabel(bestTier) + ').\n';
        }
        return s;
    }

    @TestVisible
    static Decimal effectiveArr(Contract c) {
        if (c == null) return null;
        if (c.Active_ARR__c != null && c.Active_ARR__c > 0) return c.Active_ARR__c;
        if (c.Active_ARR_Rollup__c != null && c.Active_ARR_Rollup__c > 0) return c.Active_ARR_Rollup__c;
        if (c.ARR_Rollup__c != null && c.ARR_Rollup__c > 0) return c.ARR_Rollup__c;
        return null;
    }

    private class CompRow implements Comparable {
        Id accountId;
        String name, product, erp, vertical, subVertical;
        Decimal budget, arr, distance, grantFunds;
        Integer tier;
        Boolean sameErp;
        CompRow(Contract c, String product, Decimal budget, Decimal dealBudget, Decimal arr,
                Integer tier, String erp, Boolean sameErp, Decimal grantFunds,
                String vertical, String subVertical) {
            this.accountId = c.AccountId;
            this.name = (c.Account != null) ? c.Account.Name : '';
            this.product = product;
            this.budget = budget;
            this.arr = arr;
            this.tier = tier;
            this.erp = erp;
            this.sameErp = sameErp == true;
            this.grantFunds = grantFunds;
            this.vertical = vertical;
            this.subVertical = subVertical;
            this.distance = (dealBudget != null && dealBudget > 0 && budget != null)
                ? (budget - dealBudget).abs() : Decimal.valueOf(999999999);
        }
        public Integer compareTo(Object other) {
            CompRow oth = (CompRow) other;
            if (tier != oth.tier) return tier < oth.tier ? -1 : 1;
            if (sameErp != oth.sameErp) return sameErp ? -1 : 1;
            if (distance == oth.distance) return 0;
            return distance < oth.distance ? -1 : 1;
        }
        String line() {
            return safe(name) + ' | product=' + safe(product)
                + ' | vertical=' + safe(vertical) + '/' + safe(subVertical)
                + ' | operating budget=' + fmtCur(budget)
                + (grantFunds != null && grantFunds > 0 ? ' | grant funds=' + fmtCur(grantFunds) : '')
                + ' | ERP=' + safe(erp) + (sameErp ? ' [same ERP]' : '')
                + ' | Active ARR=' + fmtCur(arr)
                + ' | match=' + tierLabel(tier);
        }
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

    /**
     * Q3 book: every current product + Active ARR from contracts, plus
     * LinkSquares agreements. Do not say "no ARR" when any of these have a figure.
     */
    private static String existingBook(Opportunity o) {
        if (o.AccountId == null) return '\nExisting Euna book (Q3): none \u2014 no account on the opportunity\n';
        String s = '\nExisting Euna book (authoritative for Q3 \u2014 Active ARR / contracts / LinkSquares):\n'
            + '  Report EVERY current product and its Active ARR. Do not say there is no ARR '
            + 'if any contract or agreement below has a figure, even when it is a different product than this deal.\n';

        List<Contract> cons = [
            SELECT Status, StartDate, EndDate, ARR_Rollup__c, Active_ARR__c, Active_ARR_Rollup__c,
                   EUNA_Solution_Name_Formula__c, EUNA_Solution_Lookup__r.Name
            FROM Contract
            WHERE AccountId = :o.AccountId
              AND (Status = 'Activated' OR Active_ARR__c > 0 OR ARR_Rollup__c > 0 OR Active_ARR_Rollup__c > 0)
            ORDER BY Status ASC
            LIMIT 20
        ];
        if (cons.isEmpty()) s += '  Active contracts: (none with ARR)\n';
        else {
            s += '  Active / ARR-bearing contracts:\n';
            for (Contract c : cons) {
                s += '    - ' + formatExistingContract(c) + '\n';
            }
        }

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
        s += '  Solution relationships: ' + (rels.isEmpty() ? 'none found' : String.join(rels, '; ')) + '\n';

        List<LinkSquares__Agreement__c> ags = [
            SELECT Name, LinkSquares__Agreement_Name__c, LinkSquares__Document_Title__c,
                   LinkSquares__Effective_Date__c, LinkSquares__Commencement_Date__c,
                   LinkSquares__Renewal_Date__c, LinkSquares__Contract_Term_Months__c
            FROM LinkSquares__Agreement__c
            WHERE LinkSquares__Account__c = :o.AccountId
            ORDER BY LinkSquares__Effective_Date__c DESC NULLS LAST
            LIMIT 10
        ];
        if (ags.isEmpty()) s += '  LinkSquares agreements: (none)\n';
        else {
            s += '  LinkSquares agreements:\n';
            for (LinkSquares__Agreement__c a : ags) {
                s += '    - ' + formatAgreement(a) + '\n';
            }
        }
        return s;
    }

    @TestVisible
    static String formatExistingContract(Contract c) {
        if (c == null) return '';
        return safe(contractProduct(c))
            + ' | status=' + safe(c.Status)
            + ' | Active ARR=' + fmtCur(effectiveArr(c))
            + ' | ARR rollup=' + fmtCur(c.ARR_Rollup__c)
            + ' | start=' + (c.StartDate != null ? c.StartDate.format() : '')
            + ' | end=' + (c.EndDate != null ? c.EndDate.format() : '');
    }

    @TestVisible
    static String formatAgreement(LinkSquares__Agreement__c a) {
        if (a == null) return '';
        String title = String.isNotBlank(a.LinkSquares__Agreement_Name__c)
            ? a.LinkSquares__Agreement_Name__c : a.Name;
        return safe(title)
            + ' | doc=' + safe(a.LinkSquares__Document_Title__c)
            + ' | effective=' + (a.LinkSquares__Effective_Date__c != null ? a.LinkSquares__Effective_Date__c.format() : '')
            + ' | start=' + (a.LinkSquares__Commencement_Date__c != null ? a.LinkSquares__Commencement_Date__c.format() : '')
            + ' | renewal=' + (a.LinkSquares__Renewal_Date__c != null ? a.LinkSquares__Renewal_Date__c.format() : '')
            + ' | term-months=' + num(a.LinkSquares__Contract_Term_Months__c);
    }

    private static String rfpAndFiles(Opportunity o) {
        String s = '\nRFP and opportunity Files (authoritative for RFP timelines \u2014 Q2/Q10/Q11/Q19/Q23):\n'
            + '  If this is an RFP, only treat a timeline as known when it is explicit below '
            + '(submission due, questions due, partner due, or a dated RFP file title). '
            + 'If no explicit date is present, say the RFP does not state a timeline.\n'
            + '  Has RFP attached: ' + yn(o.Has_RFP_Attached__c)
            + ' | RFP flag: ' + yn(o.RFP_bf__c)
            + ' | RFP type: ' + safe(o.RFP_Type__c) + '\n';

        List<RFP_Details__c> rfps = [
            SELECT Name, RFP_Title__c, RFP_Number__c, RFP_Status__c, Date_Issued__c,
                   Submission_Due_Date__c, RFPQuestionsDueDate__c, Due_Date_to_Partner__c,
                   RFP_Notes__c, RFP_Source__c
            FROM RFP_Details__c
            WHERE Opportunity__c = :o.Id
            ORDER BY Submission_Due_Date__c DESC NULLS LAST
            LIMIT 5
        ];
        if (rfps.isEmpty()) s += '  RFP Details records: (none)\n';
        else {
            for (RFP_Details__c r : rfps) s += '  - ' + formatRfp(r) + '\n';
        }

        s += '  Files on the opportunity (newest first):\n';
        List<ContentDocumentLink> files = [
            SELECT ContentDocument.Title, ContentDocument.FileType, ContentDocument.FileExtension, SystemModstamp
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :o.Id
            ORDER BY SystemModstamp DESC
            LIMIT 20
        ];
        if (files.isEmpty()) s += '    (none)\n';
        for (ContentDocumentLink l : files) {
            String title = (l.ContentDocument != null) ? l.ContentDocument.Title : '';
            String typ = (l.ContentDocument != null)
                ? safe(l.ContentDocument.FileType) + '/' + safe(l.ContentDocument.FileExtension) : '';
            s += '    - ' + dt(l.SystemModstamp) + ' ' + safe(title) + ' [' + typ + ']\n';
        }
        return s;
    }

    @TestVisible
    static String formatRfp(RFP_Details__c r) {
        if (r == null) return '';
        return 'RFP ' + safe(r.Name)
            + ' | title=' + safe(r.RFP_Title__c)
            + ' | number=' + safe(r.RFP_Number__c)
            + ' | status=' + safe(r.RFP_Status__c)
            + ' | issued=' + (r.Date_Issued__c != null ? r.Date_Issued__c.format() : '')
            + ' | submission due=' + (r.Submission_Due_Date__c != null ? r.Submission_Due_Date__c.format() : '')
            + ' | questions due=' + (r.RFPQuestionsDueDate__c != null ? r.RFPQuestionsDueDate__c.format() : '')
            + ' | partner due=' + (r.Due_Date_to_Partner__c != null ? r.Due_Date_to_Partner__c.format() : '')
            + ' | source=' + safe(r.RFP_Source__c)
            + ' | notes=' + clip(safe(r.RFP_Notes__c), 400);
    }

    @TestVisible
    static String yn(Boolean b) { return b == true ? 'yes' : 'no'; }

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
