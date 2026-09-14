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
        if (String.isBlank(userPrompt)) {
            throw new AnthropicException('A prompt is required.');
        }
        Map<String, Object> payload = new Map<String, Object>{
            'model' => model,
            'max_tokens' => maxTokens,
            'messages' => new List<Object>{
                new Map<String, Object>{ 'role' => 'user', 'content' => userPrompt }
            }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:anthropic_api/v1/messages');
        req.setMethod('POST');
        req.setTimeout(120000);
        req.setBody(JSON.serialize(payload));

        HttpResponse res = new Http().send(req);
        Integer status = res.getStatusCode();
        if (status < 200 || status >= 300) {
            throw new AnthropicException('Anthropic API error (' + status + '): ' + res.getBody());
        }
        return extractText(res.getBody());
    }

    @TestVisible
    private static String extractText(String responseBody) {
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object> content = (List<Object>) parsed.get('content');
            if (content != null) {
                List<String> parts = new List<String>();
                for (Object block : content) {
                    Map<String, Object> b = (Map<String, Object>) block;
                    if (b.get('type') == 'text' && b.get('text') != null) {
                        parts.add((String) b.get('text'));
                    }
                }
                if (!parts.isEmpty()) {
                    return String.join(parts, '\n');
                }
            }
        } catch (Exception e) {
            throw new AnthropicException('Could not parse Anthropic response: ' + e.getMessage());
        }
        throw new AnthropicException('Anthropic response contained no text content.');
    }
}
