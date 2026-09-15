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

    static String capturedBody;

    private class CaptureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            capturedBody = req.getBody();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"content":[{"type":"text","text":"ok"}]}');
            return res;
        }
    }

    private class ToolRejectThenOk implements HttpCalloutMock {
        Integer n = 0;
        public HttpResponse respond(HttpRequest req) {
            n++;
            HttpResponse res = new HttpResponse();
            if (n == 1) {
                res.setStatusCode(400);
                res.setBody('{"error":{"message":"unknown tool web_search"}}');
            } else {
                res.setStatusCode(200);
                res.setBody('{"content":[{"type":"text","text":"fallback"}]}');
            }
            return res;
        }
    }

    @isTest
    static void complete_withWebSearch_sendsTool() {
        capturedBody = null;
        Test.setMock(HttpCalloutMock.class, new CaptureMock());
        Test.startTest();
        String out = AnthropicService.complete('Need a cite', 'claude-sonnet-5', 256, true);
        Test.stopTest();
        System.assertEquals('ok', out, 'text is returned');
        System.assert(capturedBody != null && capturedBody.contains('web_search'),
            'request enables Anthropic web_search: ' + capturedBody);
    }

    @isTest
    static void complete_webSearchRejected_fallsBack() {
        Test.setMock(HttpCalloutMock.class, new ToolRejectThenOk());
        Test.startTest();
        String out = AnthropicService.complete('Need a cite', 'claude-sonnet-5', 256, true);
        Test.stopTest();
        System.assertEquals('fallback', out, 'retries without the tool after a tool rejection');
    }

    @isTest
    static void extractText_appendsCitationUrls() {
        String body = '{"content":[{"type":"text","text":"Infor is a common ERP peer.","citations":[{"type":"web_search_result_location","url":"https://example.com/infor"}]}]}';
        String text = AnthropicService.extractText(body);
        System.assert(text.contains('Infor is a common ERP peer.'), 'keeps the model text');
        System.assert(text.contains('https://example.com/infor'), 'appends the cited URL');
    }

    @isTest
    static void isToolRejected_detectsWebSearchErrors() {
        System.assert(AnthropicService.isToolRejected('unknown tool web_search'), 'web_search rejection');
        System.assert(!AnthropicService.isToolRejected('rate limited'), 'other errors are not tool rejections');
    }
}
