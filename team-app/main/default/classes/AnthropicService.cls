/**
 * Thin wrapper around the Anthropic Messages API, reached through the
 * `anthropic_api` Named Credential (which supplies the endpoint, the x-api-key
 * secret, and the anthropic-version header). Keeps all LLM-call plumbing in one
 * place so callers only pass a prompt.
 */
public with sharing class AnthropicService {
    // The two knobs for this MVP. Model is an alias so it tracks Anthropic's
    // current Sonnet; change here (or lift into Custom Metadata) to adjust.
    @TestVisible
    private static final String DEFAULT_MODEL = 'claude-sonnet-5';
    @TestVisible
    private static final Integer DEFAULT_MAX_TOKENS = 1024;

    public class AnthropicException extends Exception {}

    public static String complete(String userPrompt) {
        return complete(userPrompt, DEFAULT_MODEL, DEFAULT_MAX_TOKENS);
    }

    public static String complete(String userPrompt, String model, Integer maxTokens) {
        return complete(userPrompt, model, maxTokens, false);
    }

    /**
     * @param allowWebSearch when true, Claude may call Anthropic's server-side
     *        web_search tool if Salesforce/Gong context is not enough. Falls
     *        back to a no-tools request if the API rejects the tool.
     */
    public static String complete(String userPrompt, String model, Integer maxTokens, Boolean allowWebSearch) {
        if (String.isBlank(userPrompt)) {
            throw new AnthropicException('A prompt is required.');
        }
        Map<String, Object> payload = basePayload(userPrompt, model, maxTokens);
        if (allowWebSearch == true) {
            payload.put('tools', new List<Object>{
                new Map<String, Object>{
                    'type' => 'web_search_20250305',
                    'name' => 'web_search',
                    'max_uses' => 3
                }
            });
        }

        HttpResponse res = send(payload);
        Integer status = res.getStatusCode();
        if (allowWebSearch == true && status >= 400 && isToolRejected(res.getBody())) {
            payload.remove('tools');
            res = send(payload);
            status = res.getStatusCode();
        }
        if (status < 200 || status >= 300) {
            throw new AnthropicException('Anthropic API error (' + status + '): ' + res.getBody());
        }
        return extractText(res.getBody());
    }

    private static Map<String, Object> basePayload(String userPrompt, String model, Integer maxTokens) {
        return new Map<String, Object>{
            'model' => model,
            'max_tokens' => maxTokens,
            'messages' => new List<Object>{
                new Map<String, Object>{ 'role' => 'user', 'content' => userPrompt }
            }
        };
    }

    private static HttpResponse send(Map<String, Object> payload) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:anthropic_api/v1/messages');
        req.setMethod('POST');
        req.setTimeout(120000);
        req.setBody(JSON.serialize(payload));
        return new Http().send(req);
    }

    @TestVisible
    static Boolean isToolRejected(String body) {
        if (String.isBlank(body)) return false;
        String low = body.toLowerCase();
        return low.contains('web_search') || low.contains('unknown tool') || low.contains('invalid tool');
    }

    @TestVisible
    private static String extractText(String responseBody) {
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object> content = (List<Object>) parsed.get('content');
            if (content != null) {
                List<String> parts = new List<String>();
                Set<String> cites = new Set<String>();
                for (Object block : content) {
                    Map<String, Object> b = (Map<String, Object>) block;
                    if (b.get('type') == 'text' && b.get('text') != null) {
                        parts.add((String) b.get('text'));
                    }
                    if (b.get('citations') != null) {
                        for (Object c : (List<Object>) b.get('citations')) {
                            Map<String, Object> cit = (Map<String, Object>) c;
                            String url = (String) cit.get('url');
                            if (String.isNotBlank(url)) cites.add(url);
                        }
                    }
                }
                if (!parts.isEmpty()) {
                    String text = String.join(parts, '\n');
                    if (!cites.isEmpty()) text += '\nSources: ' + String.join(new List<String>(cites), '; ');
                    return text;
                }
            }
        } catch (Exception e) {
            throw new AnthropicException('Could not parse Anthropic response: ' + e.getMessage());
        }
        throw new AnthropicException('Anthropic response contained no text content.');
    }
}
