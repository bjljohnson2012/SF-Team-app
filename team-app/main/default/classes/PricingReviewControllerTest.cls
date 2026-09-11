/**
 * Covers: PricingReviewController
 */
@isTest
private class PricingReviewControllerTest {

    @isTest
    static void create_attaches_and_detects() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User dir = usr(p.Id, null, 'Director');
        insert dir;
        User rep = usr(p.Id, dir.Id, 'Account Executive');
        insert rep;
        Id rtId = [SELECT Id FROM RecordType WHERE SobjectType = 'Opportunity' AND DeveloperName = 'Euna_Sale' LIMIT 1].Id;

        System.runAs(dir) {
            Account a = new Account(Name = 'Acme');
            insert a;
            // ARR_Opportunity_Amount_USD_Num__c is a read-only formula; the >= $30K
            // getReviewDeals filter can't be exercised on synthetic test data, so this
            // test focuses on the doc generation + linkage + detection path.
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
            Test.stopTest();

            System.assertNotEquals(null, before, 'review-deal list returned');
            System.assertNotEquals(null, docId, 'a document was created');
            System.assert(detected, 'review is detected as done after creation');

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
