/**
 * Covers: PricingReviewController
 */
@isTest
private class PricingReviewControllerTest {

    // Returns an Anthropic-shaped response whose text is a JSON map of Q1..Q24.
    private class DraftMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            Map<String, String> a = new Map<String, String>();
            for (Integer i = 1; i <= 24; i++) a.put('Q' + i, 'Drafted answer ' + i);
            String text = JSON.serialize(a);
            Map<String, Object> body = new Map<String, Object>{
                'content' => new List<Object>{ new Map<String, Object>{ 'type' => 'text', 'text' => text } }
            };
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(body));
            return res;
        }
    }

    @isTest
    static void draft_prefills_all_questions() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User dir = usr(p.Id, null, 'Director');
        insert dir;
        Id rtId = [SELECT Id FROM RecordType WHERE SobjectType = 'Opportunity' AND DeveloperName = 'Euna_Sale' LIMIT 1].Id;

        System.runAs(dir) {
            Account a = new Account(Name = 'Acme County');
            insert a;
            Opportunity o = new Opportunity(
                Name = 'Acme Deal', AccountId = a.Id, OwnerId = dir.Id, RecordTypeId = rtId,
                Type = 'New Sale', StageName = 'Proposal', CloseDate = Date.today().addDays(30),
                LeadSource = 'Web');
            insert o;

            Test.setMock(HttpCalloutMock.class, new DraftMock());
            Test.startTest();
            Map<String, String> drafted = PricingReviewController.draftAnswers(o.Id);
            Test.stopTest();

            System.assertEquals(24, drafted.size(), 'every question is pre-filled');
            System.assertEquals('Drafted answer 1', drafted.get('Q1'), 'draft carried through from the model');
        }
    }

    @isTest
    static void complete_persists_attaches_and_reads_back() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User dir = usr(p.Id, null, 'Director');
        insert dir;
        User rep = usr(p.Id, dir.Id, 'Account Executive');
        insert rep;
        Id rtId = [SELECT Id FROM RecordType WHERE SobjectType = 'Opportunity' AND DeveloperName = 'Euna_Sale' LIMIT 1].Id;

        System.runAs(dir) {
            Account a = new Account(Name = 'Acme');
            insert a;
            Opportunity o = new Opportunity(
                Name = 'Deal', AccountId = a.Id, OwnerId = rep.Id, RecordTypeId = rtId,
                Type = 'New Sale', StageName = 'Proposal', CloseDate = Date.today().addDays(30),
                LeadSource = 'Web');
            insert o;

            Map<String, String> answers = new Map<String, String>{
                'Q2' => 'Inbound web', 'Q24' => '$85K ARR, 3-year term, 12% discount'
            };
            Test.startTest();
            List<PricingReviewController.ReviewDeal> before = PricingReviewController.getReviewDeals();
            Id docId = PricingReviewController.createReview(o.Id, answers);
            Boolean detected = PricingReviewController.reviewedOppIds(new Set<Id>{ o.Id }).contains(o.Id);
            Map<String, String> saved = PricingReviewController.getReview(o.Id);
            Test.stopTest();

            System.assertNotEquals(null, before, 'review-deal list returned');
            System.assertNotEquals(null, docId, 'a document was created');
            System.assert(detected, 'review is detected as done after completion');
            System.assertEquals('$85K ARR, 3-year term, 12% discount', saved.get('Q24'), 'saved responses read back on the tool page');

            Opportunity chk = [SELECT Pricing_Review_Answers__c FROM Opportunity WHERE Id = :o.Id];
            System.assert(String.isNotBlank(chk.Pricing_Review_Answers__c), 'answers persisted on the opportunity');
            ContentDocumentLink cdl = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :o.Id LIMIT 1];
            System.assertNotEquals(null, cdl.Id, 'file linked to the opportunity');
        }
    }

    @isTest
    static void createNull_throws() {
        try {
            PricingReviewController.createReview(null, new Map<String, String>());
            System.assert(false, 'expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'null opportunity rejected');
        }
    }

    @isTest
    static void getReview_empty_when_none() {
        Map<String, String> m = PricingReviewController.getReview(null);
        System.assertEquals(0, m.size(), 'no opportunity returns an empty map');
    }

    static Integer seq = 0;
    static User usr(Id profileId, Id mgr, String title) {
        seq++;
        String u = 'prc' + seq + '' + System.currentTimeMillis();
        return new User(
            FirstName = 'T', LastName = 'p' + seq, Alias = ('p' + seq).left(8),
            Email = u + '@example.com', Username = u + '@example.com.prc',
            ProfileId = profileId, ManagerId = mgr, Title = title,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
    }
}
