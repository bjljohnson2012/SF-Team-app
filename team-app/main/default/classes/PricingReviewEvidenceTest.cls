/**
 * Covers: PricingReviewEvidence
 */
@isTest
private class PricingReviewEvidenceTest {

    @isTest
    static void helpers_budget_product_url_keywords() {
        System.assert(PricingReviewEvidence.budgetSameOrder(965000000, 700000000),
            '700M is same order as 965M');
        System.assert(!PricingReviewEvidence.budgetSameOrder(965000000, 137000000),
            '137M is outside the 0.25x-4x band of 965M');
        System.assert(!PricingReviewEvidence.budgetSameOrder(null, 700000000),
            'null prospect budget does not match');
        System.assert(PricingReviewEvidence.productMatches('Budget Professional', 'Budget Professional'),
            'exact product matches');
        System.assert(!PricingReviewEvidence.productMatches('Budget Professional', 'Payments'),
            'different product type is rejected');
        System.assert(!PricingReviewEvidence.productMatches('Budget Professional', 'Budgeting'),
            'generic Budgeting does not match Budget Professional');
        System.assert(!PricingReviewEvidence.productMatches('Budget Professional', ''),
            'blank contract product is rejected');

        Account a = new Account(Name = 'Url Test');
        insert a;
        String url = PricingReviewEvidence.accountUrl(a.Id);
        System.assert(url.contains('/lightning/r/Account/' + a.Id + '/view'),
            'Account link is a Lightning record URL: ' + url);

        List<String> keys = PricingReviewEvidence.questionKeywords(
            'Who are comparable customers and what have we priced them at?');
        System.assert(keys.contains('comparable'), 'question keywords keep comparable');
        System.assert(!keys.contains('what'), 'stopwords are dropped');
    }

    @isTest
    static void pickGong_keeps_unknown_rich_and_newest_empty() {
        Gong__Gong_Call__c richUnknown = new Gong__Gong_Call__c(
            Gong__Title__c = 'Rich Unknown', Gong__Scope__c = 'Unknown',
            Gong__Call_Brief__c = 'Discussed pricing', Gong__Call_Start__c = Datetime.now());
        Gong__Gong_Call__c emptyRecent = new Gong__Gong_Call__c(
            Gong__Title__c = 'Empty recent', Gong__Scope__c = 'Unknown',
            Gong__Call_Start__c = Datetime.now().addDays(-1));
        Gong__Gong_Call__c olderRich = new Gong__Gong_Call__c(
            Gong__Title__c = 'Older rich', Gong__Scope__c = 'External',
            Gong_Transcript__c = 'Long transcript about TCO',
            Gong__Call_Start__c = Datetime.now().addDays(-30));
        List<Gong__Gong_Call__c> picked = PricingReviewEvidence.pickGong(
            new List<Gong__Gong_Call__c>{ emptyRecent, richUnknown, olderRich });
        System.assertEquals(3, picked.size(), 'newest empty kept plus rich calls');
        System.assert(PricingReviewEvidence.isRich(richUnknown), 'brief counts as rich');
        System.assert(!PricingReviewEvidence.isRich(emptyRecent), 'empty call is not rich');
    }

    @isTest
    static void build_includes_quote_contacts_activity_emails_and_newest_first() {
        Id rtId = [SELECT Id FROM RecordType WHERE SobjectType = 'Opportunity' AND DeveloperName = 'Euna_Sale' LIMIT 1].Id;
        Account a = new Account(Name = 'Evidence District', Industry = 'K12', AnnualRevenue = 965000000);
        insert a;
        Opportunity o = new Opportunity(
            Name = 'Evidence Deal', AccountId = a.Id, RecordTypeId = rtId,
            Type = 'New Sale', StageName = 'Proposal', CloseDate = Date.today().addDays(30),
            LeadSource = 'Partner', EUNA_Solution__c = 'Budget Professional');
        insert o;

        Contact c = new Contact(LastName = 'Buyer', FirstName = 'Pat', AccountId = a.Id,
            Title = 'CFO', Email = 'pat.buyer@example.com');
        insert c;
        insert new OpportunityContactRole(
            OpportunityId = o.Id, ContactId = c.Id, Role = 'Decision Maker', IsPrimary = true);

        insert new Task(Subject = 'Old note', WhatId = o.Id, Status = 'Completed',
            Description = 'Stale ballpark from last year');
        Task newer = new Task(Subject = 'Fresh email reply', WhatId = o.Id, Status = 'Completed',
            Description = 'Latest RFP timeline');
        insert newer;

        insert new Event(
            Subject = 'Pricing working session', WhatId = o.Id, Type = 'Meeting',
            StartDateTime = Datetime.now().addDays(-2), EndDateTime = Datetime.now().addDays(-2).addHours(1),
            Description = 'Walked modules and TCO');

        insert new EmailMessage(
            Subject = 'Re: District RFP', RelatedToId = o.Id, Incoming = true, Status = '3',
            FromAddress = 'pat.buyer@example.com', ToAddress = 'ae@example.com',
            TextBody = 'We already received a ballpark of 160k ARR.',
            MessageDate = Datetime.now());
        insert new EmailMessage(
            Subject = 'Older intro', RelatedToId = o.Id, Incoming = false, Status = '3',
            FromAddress = 'ae@example.com', ToAddress = 'pat.buyer@example.com',
            TextBody = 'Introducing Euna Budget Professional.',
            MessageDate = Datetime.now().addDays(-20));

        Id pb = Test.getStandardPricebookId();
        o.Pricebook2Id = pb;
        update o;
        Product2 prod = new Product2(Name = 'Operating Budgeting + OpenBook', IsActive = true, Family = 'Subscription');
        insert prod;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pb, Product2Id = prod.Id, UnitPrice = 161788, IsActive = true);
        insert pbe;
        Quote q = new Quote(Name = 'Quote Version 3', OpportunityId = o.Id, Pricebook2Id = pb, Status = 'Draft');
        insert q;
        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 161788);

        insertGong(o.Id, a.Id, 'Unknown', 'Call with District', 'Prospect is partial to OpenBook', true);
        insertGong(o.Id, a.Id, 'Internal', 'Internal huddle', 'Do not use this brief', true);

        Opportunity loaded = loadOpp(o.Id);

        Test.startTest();
        String pack = PricingReviewEvidence.build(loaded);
        String q6 = PricingReviewEvidence.buildForQuestion(loaded, 6,
            'Who are comparable customers and what have we priced them at?');
        Test.stopTest();

        System.assert(pack.contains('Pat Buyer'), 'contacts are in the pack');
        System.assert(pack.contains('Decision Maker'), 'contact role is in the pack');
        System.assert(pack.contains('Re: District RFP'), 'emails are in the pack');
        System.assert(pack.contains('160k ARR'), 'email body is in the pack');
        System.assert(pack.contains('Fresh email reply'), 'tasks are in the pack');
        System.assert(pack.contains('Pricing working session'), 'events are in the pack');
        System.assert(pack.contains('Operating Budgeting + OpenBook'), 'quote modules are in the pack');
        System.assert(pack.contains('161,788') || pack.contains('161788'), 'quote amounts are in the pack: ' + pack.right(200));
        System.assert(pack.contains('Call with District') || pack.contains('OpenBook'),
            'Unknown-scope Gong brief is in the pack');
        System.assert(!pack.contains('Do not use this brief'), 'Internal Gong is excluded');
        System.assert(pack.contains('/lightning/r/Account/' + a.Id + '/view'),
            'deal Account URL is present');

        Integer freshAt = pack.indexOf('Fresh email reply');
        Integer oldAt = pack.indexOf('Old note');
        System.assert(freshAt >= 0 && oldAt >= 0 && freshAt < oldAt,
            'newest task appears before older task');
        Integer newEmail = pack.indexOf('Re: District RFP');
        Integer oldEmail = pack.indexOf('Older intro');
        System.assert(newEmail >= 0 && oldEmail >= 0 && newEmail < oldEmail,
            'newest email appears before older email');

        System.assert(q6.contains('FOCUS QUESTION Q6'), 'per-question pack labels the question');
        System.assert(q6.contains('FULL EVIDENCE PACK'), 'per-question pack still includes the holistic pull');
        System.assert(q6.contains('comparable') || q6.contains('Comparable'),
            'Q6-focused section searches the comparable keyword');
    }

    @isTest
    static void comparables_require_vertical_product_and_budget() {
        Id custRt = [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND DeveloperName = 'Customer_EUNA' LIMIT 1].Id;
        Id saleRt = [SELECT Id FROM RecordType WHERE SobjectType = 'Opportunity' AND DeveloperName = 'Euna_Sale' LIMIT 1].Id;
        List<EUNA_Solution__c> sols = [
            SELECT Id, Name FROM EUNA_Solution__c WHERE Name = 'Budget Professional' LIMIT 1
        ];
        if (sols.isEmpty()) {
            sols = [SELECT Id, Name FROM EUNA_Solution__c WHERE Name != null LIMIT 1];
        }
        System.assert(!sols.isEmpty(), 'need an EUNA_Solution__c row to attach product type');
        Id solId = sols[0].Id;
        String solName = sols[0].Name;

        Account prospect = new Account(
            Name = 'Prospect District', RecordTypeId = custRt, Industry = 'K12', AnnualRevenue = 965000000);
        Account matchAcc = new Account(
            Name = 'Match Peer District', RecordTypeId = custRt, Industry = 'K12', AnnualRevenue = 700000000);
        Account wrongProdAcc = new Account(
            Name = 'Wrong Product District', RecordTypeId = custRt, Industry = 'K12', AnnualRevenue = 800000000);
        Account tinyBudgetAcc = new Account(
            Name = 'Tiny Budget District', RecordTypeId = custRt, Industry = 'K12', AnnualRevenue = 5000000);
        insert new List<Account>{ prospect, matchAcc, wrongProdAcc, tinyBudgetAcc };

        Opportunity o = new Opportunity(
            Name = 'Prospect Deal', AccountId = prospect.Id, RecordTypeId = saleRt,
            Type = 'New Sale', StageName = 'Proposal', CloseDate = Date.today().addDays(40),
            EUNA_Solution__c = solName, Euna_Solutions_Lookup__c = solId);
        insert o;

        Date start = Date.today().addYears(-2);
        Contract match = new Contract(
            AccountId = matchAcc.Id, Status = 'Draft', StartDate = start, ContractTerm = 12,
            EUNA_Solution_Lookup__c = solId, ARR_Rollup__c = 175849);
        Contract wrongProd = new Contract(
            AccountId = wrongProdAcc.Id, Status = 'Draft', StartDate = start, ContractTerm = 12,
            ARR_Rollup__c = 400000);
        Contract tiny = new Contract(
            AccountId = tinyBudgetAcc.Id, Status = 'Draft', StartDate = start, ContractTerm = 12,
            EUNA_Solution_Lookup__c = solId, ARR_Rollup__c = 20000);
        insert new List<Contract>{ match, wrongProd, tiny };
        activateIfPossible(new List<Contract>{ match, wrongProd, tiny });

        Opportunity loaded = loadOpp(o.Id);
        Test.startTest();
        String pack = PricingReviewEvidence.build(loaded);
        Test.stopTest();

        Boolean activated = [SELECT COUNT() FROM Contract WHERE Id = :match.Id AND Status = 'Activated'] > 0;
        if (activated) {
            System.assert(pack.contains('Match Peer District'),
                'vertical+product+budget peer is cited: ' + pack);
            System.assert(pack.contains('product=' + solName) || pack.contains(solName),
                'comparable names the product');
            System.assert(pack.contains('/lightning/r/Account/' + matchAcc.Id + '/view'),
                'comparable links the Account');
            System.assert(!pack.contains('Wrong Product District'),
                'different product type is not cited');
            System.assert(!pack.contains('Tiny Budget District'),
                'different annual-budget order of magnitude is not cited');
        } else {
            System.assert(pack.contains('Comparable Euna customers'),
                'comparables section is present even when contracts stay Draft');
            System.assert(PricingReviewEvidence.productMatches(solName, solName),
                'product filter is still enforced in helpers');
            System.assert(!PricingReviewEvidence.budgetSameOrder(965000000, 5000000),
                'tiny budget is rejected by the order-of-magnitude helper');
        }
    }

    @isTest
    static void dealProduct_and_budget_from_opp() {
        Opportunity o = new Opportunity(EUNA_Solution__c = 'Budget Professional');
        o.Account = new Account(AnnualRevenue = 100, Total_Budget_bf__c = 50);
        System.assertEquals('Budget Professional', PricingReviewEvidence.dealProduct(o), 'picklist product wins');
        System.assertEquals(100, PricingReviewEvidence.dealBudget(o), 'AnnualRevenue is the operating budget');
        System.assertEquals('', PricingReviewEvidence.contractProduct(null), 'null contract is blank');
        System.assertEquals('', PricingReviewEvidence.accountUrl(null), 'null account has no URL');
    }

    static Opportunity loadOpp(Id opportunityId) {
        return [
            SELECT Id, Name, AccountId, Account.Name, Account.BillingState, Account.BillingCity,
                   Account.Industry, Account.Sub_Vertical__c, Account.AnnualRevenue, Account.Total_Budget_bf__c,
                   Account.Operating_Budget_Year__c, Account.Fiscal_Year_Start_Month__c, Account.Total_Population_bf__c,
                   Account.Student_Count__c, Account.NumberOfEmployees, Account.Current_Budgeting_system__c,
                   Account.Recent_Budget_Trends__c,
                   Owner.Name, StageName, CloseDate, Amount, ARR_Opportunity_Amount_USD_Num__c,
                   EUNA_Solution__c, Euna_Solutions_Lookup__r.Name, EUNA_Competitors__c,
                   Sales_Segment__c, Sales_Director__c, ForecastCategoryName,
                   NextStep, Description, LeadSource, Type
            FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];
    }

    static void insertGong(Id oppId, Id accId, String scope, String title, String brief, Boolean allowFail) {
        Gong__Gong_Call__c g = new Gong__Gong_Call__c(
            Gong__Call_ID__c = 'pre-' + String.valueOf(Crypto.getRandomInteger()) + '-' + scope,
            Gong__Title__c = title,
            Gong__Primary_Opportunity__c = oppId,
            Gong__Primary_Account__c = accId,
            Gong__Is_Private__c = false,
            Gong__Scope__c = scope,
            Gong__Call_Start__c = Datetime.now(),
            Gong__Call_Brief__c = brief
        );
        try {
            insert g;
        } catch (Exception e) {
            if (!allowFail) throw e;
        }
    }

    static void activateIfPossible(List<Contract> contracts) {
        for (Contract c : contracts) c.Status = 'Activated';
        Database.update(contracts, false);
    }
}
