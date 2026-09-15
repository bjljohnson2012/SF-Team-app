/**
 * Covers: AnthropicService
 */
@isTest
private class AnthropicServiceTest {
    private class MockOk implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"content":[{"type":"text","text":"This is a summary."}]}');
            return res;
        }
    }

    private class MockError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody('{"error":{"message":"bad request"}}');
            return res;
        }
    }

    @isTest
    static void complete_success_returnsText() {
        Test.setMock(HttpCalloutMock.class, new MockOk());
        Test.startTest();
        String out = AnthropicService.complete('Hello');
        Test.stopTest();
        System.assertEquals('This is a summary.', out, 'Should return the text content block');
    }

    @isTest
    static void complete_httpError_throws() {
        Test.setMock(HttpCalloutMock.class, new MockError());
        Test.startTest();
        try {
            AnthropicService.complete('Hello', 'some-model', 256);
            System.assert(false, 'Expected an AnthropicException');
        } catch (AnthropicService.AnthropicException e) {
            System.assert(e.getMessage().contains('400'), 'Should surface the HTTP status');
        }
        Test.stopTest();
    }

    @isTest
    static void complete_blankPrompt_throws() {
        try {
            AnthropicService.complete('   ');
            System.assert(false, 'Expected an AnthropicException');
        } catch (AnthropicService.AnthropicException e) {
            System.assert(e.getMessage().contains('required'), 'Blank prompt should be rejected');
        }
    }

    @isTest
    static void extractText_noTextContent_throws() {
        try {
            AnthropicService.extractText('{"content":[]}');
            System.assert(false, 'Expected an AnthropicException');
        } catch (AnthropicService.AnthropicException e) {
            System.assert(true, 'Empty content should throw');
        }
    }

    @isTest
    static void extractText_malformed_throws() {
        try {
            AnthropicService.extractText('not-json');
            System.assert(false, 'Expected an AnthropicException');
        } catch (AnthropicService.AnthropicException e) {
            System.assert(true, 'Malformed body should throw');
        }
    }
}
