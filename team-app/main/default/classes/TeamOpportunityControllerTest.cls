/**
 * Covers: TeamOpportunityController
 */
@isTest
private class TeamOpportunityControllerTest {
    private class MockOk implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"content":[{"type":"text","text":"Deal summary."}]}');
            return res;
        }
    }

    @isTest
    static void getDirectorOpportunities_returnsTeamOpps() {
        UserRole role = new UserRole(Name = 'Test Dir Role', DeveloperName = 'Test_Dir_Role_TOC');
        insert role;
        User u = buildUser(role.Id);
        insert u;

        System.runAs(u) {
            Account a = new Account(Name = 'Acme Co');
            insert a;
            Opportunity o = new Opportunity(
                Name = 'Acme Expansion',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                Amount = 25000,
                AccountId = a.Id
            );
            insert o;

            Test.startTest();
            List<TeamOpportunityController.OpportunityDto> res =
                TeamOpportunityController.getDirectorOpportunities();
            Test.stopTest();

            System.assertEquals(1, res.size(), 'Should return the team opportunity');
            System.assertEquals('Acme Expansion', res[0].name, 'Name should map');
            System.assertEquals('Acme Co', res[0].accountName, 'Account name should map');
        }
    }

    @isTest
    static void summarizeOpportunity_returnsSummary() {
        Account a = new Account(Name = 'Beta Inc');
        insert a;
        Opportunity o = new Opportunity(
            Name = 'Beta Deal',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(15),
            Amount = 5000,
            AccountId = a.Id
        );
        insert o;

        Test.setMock(HttpCalloutMock.class, new MockOk());
        Test.startTest();
        String summary = TeamOpportunityController.summarizeOpportunity(o.Id);
        Test.stopTest();

        System.assertEquals('Deal summary.', summary, 'Should return the LLM text');
    }

    @isTest
    static void summarizeOpportunity_nullId_throws() {
        try {
            TeamOpportunityController.summarizeOpportunity(null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'Null id should be rejected');
        }
    }

    @isTest
    static void summarizeOpportunity_notFound_throws() {
        Account a = new Account(Name = 'Gone Inc');
        insert a;
        Opportunity o = new Opportunity(
            Name = 'Gone Deal',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(5),
            AccountId = a.Id
        );
        insert o;
        Id goneId = o.Id;
        delete o;

        Test.setMock(HttpCalloutMock.class, new MockOk());
        try {
            TeamOpportunityController.summarizeOpportunity(goneId);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'Missing opportunity should be rejected');
        }
    }

    @isTest
    static void getRoleHierarchy_null_returnsEmpty() {
        System.assertEquals(
            0,
            TeamOpportunityController.getRoleHierarchy(null).size(),
            'Null role should yield an empty set'
        );
    }

    private static User buildUser(Id roleId) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniq = 'tocuser' + System.currentTimeMillis();
        return new User(
            FirstName = 'Test',
            LastName = 'Director',
            Alias = 'tdir',
            Email = uniq + '@example.com',
            Username = uniq + '@example.com.gtmtest',
            ProfileId = p.Id,
            UserRoleId = roleId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
}
